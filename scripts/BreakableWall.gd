extends StaticBody2D

var _health: int = 3
var _col: Color = Color(0.25, 0.15, 0.10)

func setup(pos: Vector2, size: Vector2, col: Color) -> void:
	position = pos
	_col = col
	add_to_group("breakable_wall")
	z_index = -5

	var cshape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	cshape.shape = rect
	add_child(cshape)

	var vis := ColorRect.new()
	vis.color = col.darkened(0.25)
	vis.offset_left   = -size.x * 0.5
	vis.offset_top    = -size.y * 0.5
	vis.offset_right  =  size.x * 0.5
	vis.offset_bottom =  size.y * 0.5
	add_child(vis)

	var lbl := Label.new()
	lbl.text = "#"
	lbl.add_theme_color_override("font_color", col.lightened(0.4))
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.position = Vector2(-5.0, -8.0)
	add_child(lbl)

func take_damage(amount: int) -> void:
	_health -= amount
	if _health <= 0:
		_burst()
		queue_free()

func _burst() -> void:
	var gpos := global_position
	var chars := ["#", "+", "*", "x"]
	for i in 6:
		var c := Label.new()
		c.text = chars[i % 4]
		c.add_theme_color_override("font_color", _col.lightened(0.5))
		c.add_theme_font_size_override("font_size", 10)
		var angle := (TAU / 6.0) * float(i) + randf_range(-0.3, 0.3)
		var dist := randf_range(10.0, 22.0)
		c.position = gpos + Vector2(cos(angle), sin(angle)) * dist * 0.3
		get_tree().current_scene.add_child(c)
		var tw := c.create_tween()
		tw.tween_property(c, "position", gpos + Vector2(cos(angle), sin(angle)) * dist, 0.35)
		tw.parallel().tween_property(c, "modulate:a", 0.0, 0.35)
		tw.tween_callback(c.queue_free)
