extends EnemyBase

const F0 := " ___ \n(O o)\n /^\\ "
const F1 := " ___ \n(o O)\n / ^\\"

const MOVE_SPEED        := 60.0
const PREFERRED_DIST    := 280.0
const LOB_INTERVAL      := 3.6
const TELEGRAPH_TIME    := 0.55   # warning circle visible this long
const GRENADE_SPEED     := 230.0
const GRENADE_DAMAGE    := 5

var _lob_t: float        = 1.5
var _warning: Node2D     = null
var _warning_ring: Line2D    = null
var _warning_fill: Polygon2D = null
var _warning_inner: Line2D   = null
var _predicted: Vector2  = Vector2.ZERO
var _anim_t: float       = 0.0
var _anim_f: int         = 0
var _proj_scene: PackedScene = null

func _on_ready_extra() -> void:
	max_health = 9
	health = 9
	_sight_range = 480.0
	_proj_scene = load("res://scenes/Projectile.tscn")
	if _lbl:
		_lbl.text = F0

func _enemy_tick(delta: float) -> void:
	# Cancel any in-progress telegraph if our state no longer permits firing
	if _telegraphing and (_frozen or _stun_timer > 0.0 or _no_attack_timer > 0.0 or not _has_aggro):
		_telegraphing = false
		_clear_warning()
		_lob_t = LOB_INTERVAL
	if _frozen or _stun_timer > 0.0:
		velocity = Vector2.ZERO
		return
	var slow_mult := clampf(1.0 - float(_chill_stacks) * 0.1, 0.0, 1.0)
	# Kite movement
	var to_p := _player.global_position - global_position
	var dist := to_p.length()
	var toward := to_p.normalized()
	var lat    := toward.rotated(PI * 0.5)
	if dist < PREFERRED_DIST - 50.0:
		velocity = -toward * MOVE_SPEED * _speed_multiplier * slow_mult
	elif dist > PREFERRED_DIST + 50.0:
		velocity = toward * MOVE_SPEED * _speed_multiplier * slow_mult
	else:
		velocity = lat * MOVE_SPEED * 0.6 * _speed_multiplier * slow_mult

	if not _has_aggro: return
	if _no_attack_timer > 0.0: return

	_lob_t -= delta
	if _lob_t <= TELEGRAPH_TIME and not _telegraphing:
		_start_telegraph()
	if _telegraphing:
		_update_warning_visuals()
	if _lob_t <= 0.0:
		_lob_grenade()
		_lob_t = LOB_INTERVAL

func _start_telegraph() -> void:
	_telegraphing = true
	# Predict landing spot
	var pvel := Vector2.ZERO
	if _player is CharacterBody2D:
		pvel = (_player as CharacterBody2D).velocity
	var dist  := global_position.distance_to(_player.global_position)
	var ftime := clampf(dist / GRENADE_SPEED, 0.3, 1.4)
	_predicted = _player.global_position + pvel * ftime

	_warning = Node2D.new()
	_warning.global_position = _predicted
	_warning.z_index = 1
	get_tree().current_scene.add_child(_warning)

	var r := 70.0
	var segs := 32

	# Filled "danger zone" disk — fades + grows as detonation approaches.
	# Polygon2D is a real filled shape so the player can see the AoE
	# footprint at a glance, instead of guessing from a thin outline.
	_warning_fill = Polygon2D.new()
	var fill_pts := PackedVector2Array()
	for i in segs:
		var ang_f := (TAU / float(segs)) * float(i)
		fill_pts.append(Vector2(cos(ang_f), sin(ang_f)) * r)
	_warning_fill.polygon = fill_pts
	_warning_fill.color = Color(1.0, 0.25, 0.05, 0.10)
	_warning.add_child(_warning_fill)

	# Inner ring — pulses thicker / brighter near detonation. Provides a
	# secondary cue layered over the fill so peripheral vision picks it
	# up even when the player isn't looking directly at the patch.
	_warning_inner = Line2D.new()
	_warning_inner.width = 2.0
	_warning_inner.default_color = Color(1.0, 0.65, 0.0, 0.7)
	for i in segs + 1:
		var ang_in := (TAU / float(segs)) * float(i)
		_warning_inner.add_point(Vector2(cos(ang_in), sin(ang_in)) * (r * 0.55))
	_warning.add_child(_warning_inner)

	# Outer outline — same thicker ring as before, but width and brightness
	# now ramp with countdown progress.
	_warning_ring = Line2D.new()
	_warning_ring.width = 3.5
	_warning_ring.default_color = Color(1.0, 0.3, 0.0, 0.95)
	for i in segs + 1:
		var ang := (TAU / float(segs)) * float(i)
		_warning_ring.add_point(Vector2(cos(ang), sin(ang)) * r)
	_warning.add_child(_warning_ring)

# Drives the telegraph countdown visuals. Called every _enemy_tick frame
# while the warning is up — ramps fill alpha, pulses ring width, and
# shifts color from amber → bright red as detonation approaches.
func _update_warning_visuals() -> void:
	if not is_instance_valid(_warning):
		return
	var t: float = clampf(1.0 - (_lob_t / TELEGRAPH_TIME), 0.0, 1.0)   # 0 → 1 as we approach lob
	var pulse: float = (sin(Time.get_ticks_msec() * 0.022) * 0.5 + 0.5)
	if is_instance_valid(_warning_fill):
		_warning_fill.color = Color(1.0, lerpf(0.25, 0.05, t), 0.04,
			lerpf(0.10, 0.35, t) + 0.05 * pulse)
	if is_instance_valid(_warning_inner):
		_warning_inner.width = lerpf(2.0, 4.0, t) + 1.0 * pulse
		_warning_inner.default_color = Color(1.0, lerpf(0.65, 0.15, t), 0.0,
			lerpf(0.55, 0.95, t))
	if is_instance_valid(_warning_ring):
		_warning_ring.width = lerpf(3.5, 6.0, t) + 1.5 * pulse
		_warning_ring.default_color = Color(1.0, lerpf(0.30, 0.05, t), 0.0,
			lerpf(0.85, 1.0, t))

func _clear_warning() -> void:
	if is_instance_valid(_warning):
		_warning.queue_free()
	_warning = null
	_warning_ring = null
	_warning_fill = null
	_warning_inner = null

func _lob_grenade() -> void:
	_telegraphing = false
	_clear_warning()
	if not is_instance_valid(_player) or _proj_scene == null: return
	var to_target := (_predicted - global_position).normalized()
	var arc_sign  := 1.0 if randf() > 0.5 else -1.0
	var p := _proj_scene.instantiate()
	p.global_position = global_position
	p.direction = to_target.rotated(arc_sign * deg_to_rad(28.0))
	p.set("arc_target", _predicted)
	p.set("shoot_type", "grenade")
	p.set("source",     "enemy")
	p.set("speed",      GRENADE_SPEED)
	p.set("damage",     GRENADE_DAMAGE)
	# lifetime ~= flight time; explodes on lifetime if it doesn't hit
	var dist := global_position.distance_to(_predicted)
	p.set("lifetime", clampf(dist / GRENADE_SPEED + 0.05, 0.4, 1.6))
	get_tree().current_scene.add_child(p)

func _on_death() -> void:
	_clear_warning()

func _exit_tree() -> void:
	_clear_warning()

func _enemy_anim_update(delta: float) -> void:
	_anim_t += delta
	if _anim_t >= 0.4:
		_anim_t = 0.0
		_anim_f = 1 - _anim_f
	var t := F0 if _anim_f == 0 else F1
	if _lbl.text != t:
		_lbl.text = t
