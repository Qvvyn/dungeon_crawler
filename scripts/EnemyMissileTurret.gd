extends EnemyBase

const F0 := " <T> \n |#| \n /=\\ "
const F1 := " <T> \n |@| \n /=\\ "

const FIRE_INTERVAL  := 4.0
const TELEGRAPH_TIME := 0.6
const MISSILE_SPEED  := 200.0
const MISSILE_DMG    := 4
const MISSILE_LIFE   := 4.5

var _fire_t: float    = 1.5
var _anim_t: float    = 0.0
var _anim_f: int      = 0
var _proj_scene: PackedScene = null
var _lock_marker: ColorRect = null

func _on_ready_extra() -> void:
	max_health = 9
	health = 9
	_sight_range = 560.0
	_proj_scene = load("res://scenes/Projectile.tscn")
	if _lbl:
		_lbl.text = F0

func _enemy_tick(delta: float) -> void:
	# Stationary turret
	velocity = Vector2.ZERO
	if not _has_aggro: return
	if _stun_timer > 0.0 or _no_attack_timer > 0.0:
		_clear_lock()
		return

	_fire_t -= delta
	if _fire_t <= TELEGRAPH_TIME and not _telegraphing:
		_start_lock_on()
	if _fire_t <= 0.0:
		_fire_missile()
		_fire_t = FIRE_INTERVAL

func _start_lock_on() -> void:
	_telegraphing = true
	if _lock_marker == null and is_instance_valid(_player):
		_lock_marker = ColorRect.new()
		_lock_marker.size  = Vector2(28.0, 28.0)
		_lock_marker.color = Color(1.0, 0.15, 0.15, 0.55)
		_lock_marker.z_index = 4
		get_tree().current_scene.add_child(_lock_marker)

func _clear_lock() -> void:
	_telegraphing = false
	if is_instance_valid(_lock_marker):
		_lock_marker.queue_free()
	_lock_marker = null

func _tick_anim_base(delta: float) -> void:
	super(delta)
	# Track lock marker on player while telegraphing
	if is_instance_valid(_lock_marker) and is_instance_valid(_player):
		_lock_marker.position = _player.global_position - Vector2(14.0, 14.0)
		var p := sin(Time.get_ticks_msec() * 0.018) * 0.3 + 0.7
		_lock_marker.modulate = Color(1.0, p * 0.3, p * 0.3, 0.7)

func _fire_missile() -> void:
	_clear_lock()
	if _proj_scene == null or not is_instance_valid(_player): return
	var dir := (_player.global_position - global_position).normalized()
	var p := _proj_scene.instantiate()
	p.global_position = global_position
	p.direction       = dir
	p.set("source",     "enemy")
	p.set("shoot_type", "missile")
	p.set("speed",      MISSILE_SPEED)
	p.set("damage",     MISSILE_DMG)
	p.set("lifetime",   MISSILE_LIFE)
	get_tree().current_scene.add_child(p)
	if SoundManager:
		SoundManager.play("missile", randf_range(0.92, 1.08))

func _on_death() -> void:
	_clear_lock()

func _exit_tree() -> void:
	_clear_lock()

func _enemy_anim_update(delta: float) -> void:
	_anim_t += delta
	if _anim_t >= 0.4:
		_anim_t = 0.0
		_anim_f = 1 - _anim_f
	var t := F0 if _anim_f == 0 else F1
	if _lbl.text != t:
		_lbl.text = t
