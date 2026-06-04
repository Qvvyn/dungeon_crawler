extends EnemyBase

const F0 := " /-\\ \n[ Θ ]\n |_| "
const F1 := " \\-/ \n[ Θ ]\n |_| "

const SWEEP_PERIOD     := 4.5
const SWEEP_DURATION   := 1.6   # beam visible/active duration
const TELEGRAPH_TIME   := 0.85   # bumped from 0.5 — more reaction time
const SWEEP_ARC        := PI * 0.55   # ~99° sweep arc
const BEAM_RANGE       := 380.0
const BEAM_DAMAGE      := 1     # per damage tick
const DAMAGE_INTERVAL  := 0.25  # how often the beam ticks damage on player

enum BState { IDLE, TELEGRAPH, SWEEP }
var _bstate: int        = BState.IDLE
var _bstate_t: float    = 0.0
var _cycle_t: float     = 0.5
var _start_angle: float = 0.0
var _end_angle: float   = 0.0
var _cur_angle: float   = 0.0
var _beam_line: Line2D  = null
var _telegraph_line: Line2D = null
var _dmg_tick_t: float  = 0.0
var _anim_t: float      = 0.0
var _anim_f: int        = 0

func _on_ready_extra() -> void:
	max_health = 22   # doubled from 11
	health = max_health
	_sight_range = 500.0
	if _lbl:
		_lbl.text = F0

func _enemy_tick(delta: float) -> void:
	velocity = Vector2.ZERO
	if not _has_aggro: return

	match _bstate:
		BState.IDLE:
			_cycle_t -= delta
			if _cycle_t <= 0.0 and _stun_timer <= 0.0 and _no_attack_timer <= 0.0:
				_enter_telegraph()
		BState.TELEGRAPH:
			_telegraphing = true
			_bstate_t -= delta
			# Aim direction toward player at telegraph start, but indicator stays
			_update_telegraph_line()
			if _bstate_t <= 0.0:
				_enter_sweep()
		BState.SWEEP:
			_telegraphing = false
			_bstate_t -= delta
			var t := 1.0 - clampf(_bstate_t / SWEEP_DURATION, 0.0, 1.0)
			_cur_angle = lerpf(_start_angle, _end_angle, t)
			_update_beam_line()
			_dmg_tick_t -= delta
			if _dmg_tick_t <= 0.0:
				_dmg_tick_t = DAMAGE_INTERVAL
				_check_beam_hit()
			if _bstate_t <= 0.0:
				_end_sweep()

func _enter_telegraph() -> void:
	_bstate = BState.TELEGRAPH
	_bstate_t = TELEGRAPH_TIME
	# Compute sweep arc starting offset to one side of player aim
	var to_p := (_player.global_position - global_position).normalized()
	var aim_angle := to_p.angle()
	var arc_sign := 1.0 if randf() > 0.5 else -1.0
	_start_angle = aim_angle - arc_sign * (SWEEP_ARC * 0.5)
	_end_angle   = aim_angle + arc_sign * (SWEEP_ARC * 0.5)
	if _telegraph_line == null:
		_telegraph_line = Line2D.new()
		# Widened from 1.5 → 3.5 and alpha 0.45 → 0.85 so the windup is
		# clearly readable. Brightness still ramps further in
		# _update_telegraph_line as the sweep approaches.
		_telegraph_line.width = 3.5
		_telegraph_line.default_color = Color(1.0, 0.4, 0.1, 0.85)
		_telegraph_line.z_index = -1
		get_tree().current_scene.add_child(_telegraph_line)
	if SoundManager:
		SoundManager.play("beam_charge")

func _update_telegraph_line() -> void:
	if _telegraph_line == null: return
	_telegraph_line.clear_points()
	_telegraph_line.add_point(global_position)
	var d := Vector2(cos(_start_angle), sin(_start_angle))
	var end_pt := global_position + d * BEAM_RANGE
	_telegraph_line.add_point(end_pt)
	# Mirror into FP — the 2D Line2D doesn't render in the 3D SubViewport.
	if GameState.active_rig != null and is_instance_valid(GameState.active_rig) \
			and GameState.active_rig.has_method("set_enemy_beam"):
		GameState.active_rig.set_enemy_beam(self, global_position, end_pt,
			Color(1.0, 0.45, 0.10), true)

func _enter_sweep() -> void:
	_bstate = BState.SWEEP
	_bstate_t = SWEEP_DURATION
	_dmg_tick_t = 0.0
	if _telegraph_line:
		_telegraph_line.queue_free()
		_telegraph_line = null
	# Drop the FP telegraph dots so the rig swaps cleanly to the brighter
	# sweep glyphs — without this the dim "·" stayed visible for a frame
	# under the new beam, reading as visual noise.
	if GameState.active_rig != null and is_instance_valid(GameState.active_rig) \
			and GameState.active_rig.has_method("clear_enemy_beam"):
		GameState.active_rig.clear_enemy_beam(self)
	if _beam_line == null:
		_beam_line = Line2D.new()
		_beam_line.width = 4.5
		_beam_line.default_color = Color(1.0, 0.5, 0.15, 0.95)
		_beam_line.z_index = 1
		get_tree().current_scene.add_child(_beam_line)
	_cur_angle = _start_angle

func _end_sweep() -> void:
	_bstate = BState.IDLE
	_cycle_t = SWEEP_PERIOD - SWEEP_DURATION - TELEGRAPH_TIME
	if _beam_line:
		_beam_line.queue_free()
		_beam_line = null
	if GameState.active_rig != null and is_instance_valid(GameState.active_rig) \
			and GameState.active_rig.has_method("clear_enemy_beam"):
		GameState.active_rig.clear_enemy_beam(self)

func _update_beam_line() -> void:
	if _beam_line == null: return
	var dir := Vector2(cos(_cur_angle), sin(_cur_angle))
	# Raycast to find beam end (wall or full range)
	var space := get_world_2d().direct_space_state
	var params := PhysicsRayQueryParameters2D.create(global_position, global_position + dir * BEAM_RANGE)
	params.exclude = [get_rid()]
	var hit := space.intersect_ray(params)
	var end_pt := global_position + dir * BEAM_RANGE
	if not hit.is_empty() and hit.get("collider") is StaticBody2D:
		end_pt = hit.get("position", end_pt)
	_beam_line.clear_points()
	_beam_line.add_point(global_position)
	_beam_line.add_point(end_pt)
	# Mirror the active beam into FP using the orange sweep color, matching
	# the 2D Line2D's brighter hue (telegraph is the dim version above).
	if GameState.active_rig != null and is_instance_valid(GameState.active_rig) \
			and GameState.active_rig.has_method("set_enemy_beam"):
		GameState.active_rig.set_enemy_beam(self, global_position, end_pt,
			Color(1.0, 0.50, 0.15), false)

func _check_beam_hit() -> void:
	if not is_instance_valid(_player): return
	var dir := Vector2(cos(_cur_angle), sin(_cur_angle))
	var to_p := _player.global_position - global_position
	var proj_dist := to_p.dot(dir)
	if proj_dist < 0.0 or proj_dist > BEAM_RANGE: return
	var perp := absf(to_p.dot(dir.rotated(PI * 0.5)))
	if perp <= 14.0:
		# Wall blocks check
		var space := get_world_2d().direct_space_state
		var params := PhysicsRayQueryParameters2D.create(global_position, _player.global_position)
		params.exclude = [get_rid()]
		var hit := space.intersect_ray(params)
		if hit.is_empty() or hit.get("collider") == _player:
			if _player.has_method("take_damage"):
				_player.take_damage(BEAM_DAMAGE, self)

func _on_death() -> void:
	_cleanup_visuals()

func _exit_tree() -> void:
	# Safety net — guarantees the beam/telegraph lines are freed even if
	# _on_death didn't fire (scene change, edge cases, etc.)
	_cleanup_visuals()

func _cleanup_visuals() -> void:
	if is_instance_valid(_beam_line): _beam_line.queue_free()
	if is_instance_valid(_telegraph_line): _telegraph_line.queue_free()
	_beam_line = null
	_telegraph_line = null
	if GameState.active_rig != null and is_instance_valid(GameState.active_rig) \
			and GameState.active_rig.has_method("clear_enemy_beam"):
		GameState.active_rig.clear_enemy_beam(self)

func _enemy_anim_update(delta: float) -> void:
	if _sprite != null:
		return   # driver owns the label (jester-head sprite)
	_anim_t += delta
	if _anim_t >= 0.3:
		_anim_t = 0.0
		_anim_f = 1 - _anim_f
	var t := F0 if _anim_f == 0 else F1
	if _lbl.text != t:
		_lbl.text = t
