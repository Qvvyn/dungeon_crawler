extends EnemyBase

# Frost Sentinel — Ice Cavern only. Slow tank that periodically spawns
# IceTile patches around itself, turning its arena into a slipping
# floor. Pairs with the hypothermia mechanic (player needs kills to
# regen stamina, but the sentinel forces you to commit to engagement).

const ICE_TILE_SCRIPT = preload("res://scripts/IceTile.gd")

const F0 := " ###\n[X X]\n /|\\ "
const F1 := " ###\n[* *]\n /|\\ "

const MOVE_SPEED         := 50.0
const ICE_SPAWN_INTERVAL := 4.0
const ICE_TILES_PER_WAVE := 5
const ICE_RADIUS         := 80.0   # how far ice tiles can spawn from sentinel

var _ice_t: float  = 2.0
var _anim_t: float = 0.0
var _anim_f: int   = 0

func _on_ready_extra() -> void:
	max_health = 44   # doubled from 22
	health = max_health
	_sight_range = 540.0
	if _lbl:
		_lbl.text = F0

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
	_ice_t -= delta
	if _ice_t <= 0.0 and _no_attack_timer <= 0.0:
		_ice_t = ICE_SPAWN_INTERVAL
		_drop_ice()

func _drop_ice() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var scene_root := tree.current_scene
	if scene_root == null:
		return
	for _i in ICE_TILES_PER_WAVE:
		var ang := randf() * TAU
		var dist := randf_range(ICE_RADIUS * 0.4, ICE_RADIUS)
		var pos := global_position + Vector2(cos(ang), sin(ang)) * dist
		var tile: Node = ICE_TILE_SCRIPT.new()
		if tile is Node2D:
			(tile as Node2D).global_position = pos
		# Each wave times out after a few seconds — previously the sentinel
		# slowly carpeted the arena with permanent ice, which was unreadable
		# in FP and tedious in top-down.
		tile.set("lifetime", 10.0)
		scene_root.add_child(tile)
	if SoundManager:
		SoundManager.play("crystal", randf_range(0.85, 1.05))

func _enemy_anim_update(delta: float) -> void:
	_anim_t += delta
	if _anim_t >= 0.40:
		_anim_t = 0.0
		_anim_f = 1 - _anim_f
		if _lbl:
			_lbl.text = F0 if _anim_f == 0 else F1
