extends Area2D

const LOOT_BAG_SCENE = preload("res://scenes/LootBag.tscn")

var _triggered: bool = false
var _lbl: Label = null

func setup(pos: Vector2) -> void:
	position = pos
	add_to_group("pressure_plate")
	collision_layer = 0
	collision_mask  = 1

	var cshape := CollisionShape2D.new()
	var circ := CircleShape2D.new()
	circ.radius = 10.0
	cshape.shape = circ
	add_child(cshape)

	_lbl = Label.new()
	_lbl.text = "[·]"
	_lbl.add_theme_color_override("font_color", Color(0.85, 0.75, 0.3))
	_lbl.add_theme_font_size_override("font_size", 11)
	_lbl.position = Vector2(-9.0, -8.0)
	add_child(_lbl)

	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if _triggered:
		return
	if not body.is_in_group("player"):
		return
	_triggered = true
	var bag := LOOT_BAG_SCENE.instantiate()
	bag.global_position = global_position + Vector2(randf_range(-12.0, 12.0), randf_range(-12.0, 12.0))
	get_tree().current_scene.add_child(bag)
	if _lbl:
		var tw := _lbl.create_tween()
		tw.tween_property(_lbl, "modulate:a", 0.0, 0.4)
		tw.tween_callback(func() -> void: queue_free())
