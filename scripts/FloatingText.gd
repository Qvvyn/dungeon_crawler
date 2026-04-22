class_name FloatingText
# Static utility — call FloatingText.spawn() from any script.
# No autoload needed; class_name makes it globally visible once the file is parsed.

static func _setup_label(label: Label, col: Color) -> void:
	label.size = Vector2(160, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", col)
	label.add_theme_constant_override("outline_size", 2)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.z_index = 100

static func spawn_str(world_pos: Vector2, text: String, col: Color, parent: Node) -> void:
	var label := Label.new()
	label.text = text
	_setup_label(label, col)
	parent.add_child(label)
	label.global_position = world_pos + Vector2(-80.0 + randf_range(-8.0, 8.0), -40.0)
	var tween := label.create_tween()
	tween.tween_property(label, "position", label.position + Vector2(0.0, -50.0), 0.85)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.85)
	tween.tween_callback(label.queue_free)

static func spawn(world_pos: Vector2, value: int, is_heal: bool, parent: Node, custom_color: Color = Color.TRANSPARENT) -> void:
	var label := Label.new()
	label.text = ("+" if is_heal else "") + str(value)
	var col: Color
	if custom_color.a > 0.0:
		col = custom_color
	else:
		col = Color(0.15, 0.9, 0.15) if is_heal else Color(1.0, 0.15, 0.15)
	_setup_label(label, col)
	parent.add_child(label)
	label.global_position = world_pos + Vector2(-80.0 + randf_range(-8.0, 8.0), -40.0)

	var tween := label.create_tween()
	tween.tween_property(label, "position", label.position + Vector2(0.0, -50.0), 0.85)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.85)
	tween.tween_callback(label.queue_free)
