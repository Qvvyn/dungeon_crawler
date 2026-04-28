extends EnemyBase

const F0 := "  ^^ \n>>X<<\n /||\\"
const F1 := "  ^^ \n>>X<<\n // \\\\"

const MOVE_SPEED       := 95.0
const TELEGRAPH_TIME   := 0.7
const DASH_TIME        := 0.45
const DASH_SPEED       := 720.0
const COOLDOWN         := 1.2
const CONTACT_DAMAGE   := 4
const CONTACT_RADIUS   := 30.0
const TELEGRAPH_RANGE  := 360.0

enum State { CIRCLE, TELEGRAPH, DASH, COOLDOWN }
var _state: int        = State.CIRCLE
var _state_t: float    = 0.0
var _dash_dir: Vector2 = Vector2.ZERO
var _hit_player_this_dash: bool = false
var _telegraph_line: Line2D = null
var _anim_t: float     = 0.0
var _anim_f: int       = 0

func _on_ready_extra() -> void:
	max_health = 10
	health = 10
	_sight_range = 520.0
	if _lbl:
		_lbl.text = F0

func _enemy_tick(delta: float) -> void:
	if _frozen or _stun_timer > 0.0:
		velocity = Vector2.ZERO
		return
	var slow_mult := clampf(1.0 - float(_chill_stacks) * 0.1, 0.0, 1.0)

	match _state:
		State.CIRCLE:
			_circle_player(slow_mult)
			if _has_aggro and _no_attack_timer <= 0.0:
				if global_position.distance_to(_player.global_position) <= TELEGRAPH_RANGE:
					_enter_telegraph()
		State.TELEGRAPH:
			velocity = Vector2.ZERO
			_telegraphing = true
			_state_t -= delta
			_update_telegraph_line()
			if _state_t <= 0.0:
				_enter_dash()
		State.DASH:
			velocity = _dash_dir * DASH_SPEED * slow_mult
			_state_t -= delta
			if not _hit_player_this_dash and global_position.distance_to(_player.global_position) <= CONTACT_RADIUS:
				if _player.has_method("take_damage"):
					_player.take_damage(CONTACT_DAMAGE)
				_hit_player_this_dash = true
			if _state_t <= 0.0 or get_slide_collision_count() > 0:
				_enter_cooldown()
		State.COOLDOWN:
			velocity = Vector2.ZERO
			_state_t -= delta
			if _state_t <= 0.0:
				_state = State.CIRCLE

func _circle_player(slow_mult: float) -> void:
	var to_p := _player.global_position - global_position
	var dist := to_p.length()
	var toward := to_p.normalized()
	if dist > 220.0:
		velocity = toward * MOVE_SPEED * _speed_multiplier * slow_mult
	else:
		var lat := toward.rotated(PI * 0.5)
		velocity = (toward * 0.4 + lat * 0.6).normalized() * MOVE_SPEED * _speed_multiplier * slow_mult

func _enter_telegraph() -> void:
	_state = State.TELEGRAPH
	_state_t = TELEGRAPH_TIME
	_dash_dir = (_player.global_position - global_position).normalized()
	_hit_player_this_dash = false
	# Predictive line removed — chargers no longer telegraph their dash
	# trajectory with a visible line. The wind-up motion + flash on the
	# enemy itself is the only tell now.

func _update_telegraph_line() -> void:
	# Keeps the dash direction fresh during the wind-up so the dash
	# starts aimed at where the player is *now*, not where they were
	# when the telegraph began. No visual line anymore.
	_dash_dir = (_player.global_position - global_position).normalized()

func _enter_dash() -> void:
	_state = State.DASH
	_state_t = DASH_TIME
	_telegraphing = false
	if _telegraph_line:
		_telegraph_line.queue_free()
		_telegraph_line = null
	if SoundManager:
		SoundManager.play("whoosh", randf_range(0.95, 1.1))

func _enter_cooldown() -> void:
	_state = State.COOLDOWN
	_state_t = COOLDOWN

func _on_death() -> void:
	_cleanup_visual()

func _exit_tree() -> void:
	_cleanup_visual()

func _cleanup_visual() -> void:
	if is_instance_valid(_telegraph_line):
		_telegraph_line.queue_free()
	_telegraph_line = null

func _enemy_anim_update(delta: float) -> void:
	_anim_t += delta
	var rate := 0.12 if _state == State.DASH else 0.32
	if _anim_t >= rate:
		_anim_t = 0.0
		_anim_f = 1 - _anim_f
	var t := F0 if _anim_f == 0 else F1
	if _lbl.text != t:
		_lbl.text = t
