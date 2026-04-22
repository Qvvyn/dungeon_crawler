extends Node2D

var target_pos: Vector2    = Vector2.ZERO
var proj_scene: PackedScene = null
var _detonated: bool       = false

const SPEED         := 320.0
const HIT_RADIUS    := 22.0
const NOVA_COUNT    := 12
const NOVA_DAMAGE   := 2
const DIRECT_DAMAGE := 6

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
				enemy.call("take_damage", DIRECT_DAMAGE)
			_detonate()
			return

func _detonate() -> void:
	_detonated = true
	FloatingText.spawn_str(global_position, "★ NOVA ★", Color(0.9, 0.2, 1.0), get_tree().current_scene)
	if proj_scene != null:
		for i in NOVA_COUNT:
			var angle := float(i) / float(NOVA_COUNT) * TAU
			var proj := proj_scene.instantiate()
			proj.global_position = global_position
			proj.set("direction",          Vector2(cos(angle), sin(angle)))
			proj.set("source",             "player")
			proj.set("damage",             NOVA_DAMAGE)
			proj.set("speed",              380.0)
			proj.set("pierce_remaining",   0)
			proj.set("ricochet_remaining", 0)
			proj.set("chain_remaining",    0)
			proj.set("shoot_type",         "")
			proj.set("apply_freeze",       false)
			proj.set("apply_burn",         false)
			proj.set("apply_shock",        false)
			proj.set("drift_speed",        0.0)
			get_tree().current_scene.add_child(proj)
	queue_free()
