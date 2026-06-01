extends StaticBody2D

var _health: int = 3
var _col: Color = Color(0.25, 0.15, 0.10)
var _tiles_covered: Array[Vector2i] = []

func setup(pos: Vector2, size: Vector2, col: Color) -> void:
	position = pos
	_col = col
	# Record which grid tiles this wall occupies so we can clear them on death.
	const _TILE: int = 32
	var left := int((pos.x - size.x * 0.5) / _TILE)
	var top  := int((pos.y - size.y * 0.5) / _TILE)
	var cols := int(size.x / _TILE)
	var rows := int(size.y / _TILE)
	for gy in range(top, top + rows):
		for gx in range(left, left + cols):
			_tiles_covered.append(Vector2i(gx, gy))
	add_to_group("breakable_wall")
	z_index = -5
	GameState.attach_fp_visual(self, "#", Color(0.60, 0.55, 0.50), 0.50)

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
	# Clear the covered tiles from the shared world grid and rebuild the FP wall
	# mesh so the destroyed segment becomes transparent in first-person mode.
	var world := get_tree().current_scene
	if is_instance_valid(world) and world.has_method("notify_wall_destroyed"):
		world.notify_wall_destroyed(_tiles_covered)
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
	# FP rubble — three quick bursts using the same char palette so the
	# wall collapse reads as chunks of stone scattering in first-person.
	if GameState.active_rig != null and is_instance_valid(GameState.active_rig) \
			and GameState.active_rig.has_method("spawn_burst_2d"):
		var fp_col := _col.lightened(0.5)
		GameState.active_rig.spawn_burst_2d(gpos, "#", fp_col, 2, 0.65, 0.35, Vector2.ZERO, TAU, 0.010, 0.50)
		GameState.active_rig.spawn_burst_2d(gpos, "+", fp_col, 2, 0.65, 0.35, Vector2.ZERO, TAU, 0.010, 0.50)
		GameState.active_rig.spawn_burst_2d(gpos, "*", fp_col, 2, 0.65, 0.35, Vector2.ZERO, TAU, 0.010, 0.50)
