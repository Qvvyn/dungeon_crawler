extends Node2D

const NOVA_SPAWNER_SCR := preload("res://scripts/NovaSpawner.gd")

var target_pos: Vector2    = Vector2.ZERO
var proj_scene: PackedScene = null
var _detonated: bool       = false

const SPEED         := 320.0
const HIT_RADIUS    := 22.0
const NOVA_COUNT    := 12
# Base damages. Actual damage scales with INT at detonation/contact time
# (see _int_bonus()) so nova keeps pace with the player's wand DPS, which
# also scales on INT now.
const NOVA_DAMAGE_BASE   := 2
const DIRECT_DAMAGE_BASE := 6

# Each INT point above 0 adds +1 to the contact damage and +0.5 (rounded)
# to each shard. INT bonus is the per-point delta above the stat baseline.
func _int_bonus() -> int:
	return int(GameState.get_stat_bonus("INT"))

func _ready() -> void:
	z_index = 3
	var lbl := Label.new()
	lbl.text = "✦"
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color",         Color(0.85, 0.2,  1.0))
	lbl.add_theme_color_override("font_outline_color", Color(0.25, 0.0, 0.45))
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.position = Vector2(-11, -16)
	add_child(lbl)
	var tw := create_tween()
	tw.set_loops()
	tw.tween_property(self, "scale", Vector2(1.2, 1.2), 0.22)
	tw.tween_property(self, "scale", Vector2(0.82, 0.82), 0.22)

func _process(delta: float) -> void:
	if _detonated:
		return
	var to_target := target_pos - global_position
	if to_target.length() < 14.0:
		_detonate()
		return
	global_position += to_target.normalized() * SPEED * delta
	for enemy: Node in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy):
			continue
		var ep := enemy as Node2D
		if ep != null and global_position.distance_to(ep.global_position) < HIT_RADIUS:
			if enemy.has_method("take_damage"):
				var direct_dmg: int = DIRECT_DAMAGE_BASE + _int_bonus()
				enemy.call("take_damage", direct_dmg)
			_detonate()
			return

func _detonate() -> void:
	_detonated = true
	FloatingText.spawn_str(global_position, "★ NOVA ★", Color(0.9, 0.2, 1.0), get_tree().current_scene)
	if proj_scene != null:
		var spawner := Node2D.new()
		spawner.set_script(NOVA_SPAWNER_SCR)
		spawner._spawn_pos  = global_position
		spawner._source     = "player"
		# Shard damage scales at half the rate of contact damage so a high-
		# INT nova hits hard up close *and* peppers enemies at range.
		spawner._damage     = NOVA_DAMAGE_BASE + int(round(float(_int_bonus()) * 0.5))
		spawner._speed      = 380.0
		spawner._shoot_type = "nova_shard"
		for i in NOVA_COUNT:
			var angle := float(i) / float(NOVA_COUNT) * TAU
			spawner._queue.append(Vector2(cos(angle), sin(angle)))
		get_tree().current_scene.add_child(spawner)
	queue_free()
