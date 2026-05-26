extends EnemyBase

# Magma Slug — Lava Rift only. Very slow, leaves a trail of LavaTiles
# behind itself. Easy to kill in isolation, but if it weaves around the
# room first the floor becomes lava-soaked. Pairs with the eruption
# biome mechanic — lava sources stack.

const LAVA_TILE_SCRIPT = preload("res://scripts/LavaTile.gd")

const F0 := " ()(\n((O))\n ))( "
const F1 := " )()\n((o))\n )(( "

const MOVE_SPEED         := 30.0   # very slow
const TRAIL_INTERVAL     := 1.6
const TRAIL_DROP_DIST    := 64.0   # don't drop another tile until we've moved this far

var _trail_t: float           = 0.0
var _last_trail_pos: Vector2  = Vector2.ZERO
var _anim_t: float            = 0.0
var _anim_f: int              = 0

func _on_ready_extra() -> void:
	max_health = 18   # doubled from 9
	health = max_health
	_sight_range = 480.0
	if _lbl:
		_lbl.text = F0
	_last_trail_pos = global_position

func _enemy_tick(delta: float) -> void:
	if _frozen or _stun_timer > 0.0:
		velocity = Vector2.ZERO
		return
	if not _has_aggro:
		velocity = Vector2.ZERO
		return
	var slow_mult := clampf(1.0 - float(_chill_stacks) * 0.1, 0.0, 1.0)
	var to_p: Vector2 = _player.global_position - global_position
	velocity = to_p.normalized() * MOVE_SPEED * _speed_multiplier * slow_mult
	_trail_t -= delta
	if _trail_t <= 0.0:
		var moved: float = global_position.distance_to(_last_trail_pos)
		if moved >= TRAIL_DROP_DIST:
			_trail_t = TRAIL_INTERVAL
			_last_trail_pos = global_position
			_drop_lava()

func _drop_lava() -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var lava: Node = LAVA_TILE_SCRIPT.new()
	if lava is Node2D:
		(lava as Node2D).global_position = global_position
	# Cap the trail so it doesn't permanently coat the arena floor — the
	# slug can lay several tiles per fight and they used to persist for the
	# whole run, cluttering the room (especially loud in FP).
	lava.set("lifetime", 8.0)
	tree.current_scene.add_child(lava)

func _enemy_anim_update(delta: float) -> void:
	_anim_t += delta
	if _anim_t >= 0.50:   # languid pace, fits the slow movement
		_anim_t = 0.0
		_anim_f = 1 - _anim_f
		if _lbl:
			_lbl.text = F0 if _anim_f == 0 else F1
