extends Node2D

# Draws collision shape outlines in screen space so the overlay is visible in
# both top-down and first-person modes. Hosted inside a CanvasLayer at layer 50
# (above the FP rig at layer 1) so it always renders on top.
#
# Colours by role:
#   green  = player
#   red    = enemy
#   orange = Area2D  (projectiles, hazards, loot, triggers)
#   cyan   = other   (static walls, misc bodies)
#   yellow = FirePatch soft-radius (distance-based, no CollisionShape2D)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if not GameState.show_hitboxes:
		return
	if GameState.render_mode != GameState.RenderMode.TOPDOWN:
		return
	var vt := get_viewport().get_canvas_transform()
	var zoom := vt.get_scale().x
	_scan_node(get_tree().current_scene, vt, zoom)
	# FirePatch uses distance-based detection — no CollisionShape2D, needs manual ring.
	for fp in get_tree().get_nodes_in_group("fire_patch"):
		if fp is Node2D and "_radius" in fp:
			var sp := vt * (fp as Node2D).global_position
			draw_arc(sp, fp._radius * zoom, 0.0, TAU, 24,
					Color(1.0, 0.85, 0.1, 0.9), 1.5)

func _scan_node(node: Node, vt: Transform2D, zoom: float) -> void:
	if node is CollisionShape2D:
		var cs := node as CollisionShape2D
		if not cs.disabled and cs.shape != null:
			_draw_shape(cs, _color_for(cs.get_parent()), vt, zoom)
	for child in node.get_children():
		_scan_node(child, vt, zoom)

func _color_for(parent: Node) -> Color:
	if parent == null:
		return Color(0.6, 0.6, 0.6, 0.6)
	if parent.is_in_group("player"):
		return Color(0.2, 1.0, 0.3, 0.9)
	if parent.is_in_group("enemy"):
		return Color(1.0, 0.25, 0.25, 0.9)
	if parent is Area2D:
		return Color(1.0, 0.65, 0.1, 0.9)
	return Color(0.5, 0.85, 1.0, 0.5)

func _draw_shape(cs: CollisionShape2D, color: Color, vt: Transform2D, zoom: float) -> void:
	var shape := cs.shape
	var wp    := cs.global_position
	var rot   := cs.global_rotation
	if shape is CircleShape2D:
		draw_arc(vt * wp, (shape as CircleShape2D).radius * zoom, 0.0, TAU, 24, color, 1.5)
	elif shape is RectangleShape2D:
		var h := (shape as RectangleShape2D).size * 0.5
		var pts := PackedVector2Array([
			vt * (wp + Vector2(-h.x, -h.y).rotated(rot)),
			vt * (wp + Vector2( h.x, -h.y).rotated(rot)),
			vt * (wp + Vector2( h.x,  h.y).rotated(rot)),
			vt * (wp + Vector2(-h.x,  h.y).rotated(rot)),
			vt * (wp + Vector2(-h.x, -h.y).rotated(rot)),
		])
		draw_polyline(pts, color, 1.5)
