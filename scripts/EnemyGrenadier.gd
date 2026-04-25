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
	get_tree().current_scene.add_child(_warning)
	# Danger-zone ring (Line2D circle outline) — clearly an indicator, not a fire patch
	var ring := Line2D.new()
	ring.width = 2.5
	ring.default_color = Color(1.0, 0.3, 0.0, 0.85)
	var r := 70.0
	var segs := 28
	for i in segs + 1:
		var ang := (TAU / float(segs)) * float(i)
		ring.add_point(Vector2(cos(ang), sin(ang)) * r)
	_warning.add_child(ring)

func _clear_warning() -> void:
	if is_instance_valid(_warning):
		_warning.queue_free()
	_warning = null

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
