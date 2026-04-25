extends EnemyBase

const F0 := " (^_^)\n /[#]\\\n  | | "
const F1 := " (^_^)\n /[%]\\\n  | | "

const MINE_SCENE      := preload("res://scenes/Mine.tscn")
const MOVE_SPEED      := 70.0
const PREFERRED_DIST  := 380.0
const DROP_INTERVAL   := 2.5
const MAX_ACTIVE_MINES := 4

var _drop_t: float    = 1.5
var _anim_t: float    = 0.0
var _anim_f: int      = 0

func _on_ready_extra() -> void:
	max_health = 8
	health = 8
	_sight_range = 500.0
	if _lbl:
		_lbl.text = F0

func _enemy_tick(delta: float) -> void:
	if _frozen or _stun_timer > 0.0:
		velocity = Vector2.ZERO
		return
	var slow_mult := clampf(1.0 - float(_chill_stacks) * 0.1, 0.0, 1.0)
	# Skirt around the player at long range
	var to_p := _player.global_position - global_position
	var dist := to_p.length()
	var toward := to_p.normalized()
	var lat := toward.rotated(PI * 0.5)
	if dist < PREFERRED_DIST - 60.0:
		velocity = (-toward * 0.7 + lat * 0.3).normalized() * MOVE_SPEED * _speed_multiplier * slow_mult
	elif dist > PREFERRED_DIST + 60.0:
		velocity = (toward * 0.5 + lat * 0.5).normalized() * MOVE_SPEED * _speed_multiplier * slow_mult
	else:
		velocity = lat * MOVE_SPEED * _speed_multiplier * slow_mult

	if not _has_aggro: return
	if _no_attack_timer > 0.0: return

	_drop_t -= delta
	if _drop_t <= 0.0:
		_drop_t = DROP_INTERVAL
		_drop_mine()

func _drop_mine() -> void:
	# Cap concurrent mines
	var live := 0
	for m in get_tree().get_nodes_in_group("mine"):
		if is_instance_valid(m):
			live += 1
	if live >= MAX_ACTIVE_MINES:
		return
	# Reject placement if the spot overlaps a wall (or sits in an out-of-bounds void)
	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 22.0
	query.shape = circle
	query.transform = Transform2D(0.0, global_position)
	query.exclude = [get_rid()]
	for hit in space.intersect_shape(query, 8):
		if hit.get("collider") is StaticBody2D:
			return
	var mine := MINE_SCENE.instantiate()
	mine.global_position = global_position
	get_tree().current_scene.add_child(mine)
	FloatingText.spawn_str(global_position, "MINE", Color(1.0, 0.45, 0.05), get_tree().current_scene)

func _enemy_anim_update(delta: float) -> void:
	_anim_t += delta
	if _anim_t >= 0.45:
		_anim_t = 0.0
		_anim_f = 1 - _anim_f
	var t := F0 if _anim_f == 0 else F1
	if _lbl.text != t:
		_lbl.text = t
