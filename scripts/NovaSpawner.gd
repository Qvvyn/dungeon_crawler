extends Node2D

# Spawns queued nova projectiles at 2 per frame to avoid instantiation spikes.
# Set all vars, then call add_child — _process starts draining on the next frame.

const PROJ_SCENE := preload("res://scenes/Projectile.tscn")
const PER_FRAME  := 2

var _queue: Array       = []   # Array[Vector2] directions
var _spawn_pos: Vector2 = Vector2.ZERO
var _source: String     = "player"
var _damage: int        = 1
var _speed: float       = 0.0   # 0 = use Projectile default
var _shoot_type: String = "regular"
var _pierce: int        = 0
var _apply_freeze: bool = false
var _apply_burn: bool   = false
var _apply_shock: bool  = false

func _process(_delta: float) -> void:
	for _i in PER_FRAME:
		if _queue.is_empty():
			queue_free()
			return
		var dir: Vector2 = _queue.pop_front()
		var proj: Node = PROJ_SCENE.instantiate()
		proj.global_position = _spawn_pos
		proj.set("direction",        dir)
		proj.set("source",           _source)
		proj.set("damage",           _damage)
		proj.set("shoot_type",       _shoot_type)
		proj.set("pierce_remaining", _pierce)
		proj.set("apply_freeze",     _apply_freeze)
		proj.set("apply_burn",       _apply_burn)
		proj.set("apply_shock",      _apply_shock)
		if _speed > 0.0:
			proj.set("speed", _speed)
		get_tree().current_scene.add_child(proj)
