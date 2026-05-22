extends CanvasLayer

# Option C: 3D scene → low-res SubViewport → ASCII post-process shader.
# Walls / floor / ceiling are MultiMeshInstance3D in the 3D world; entities
# are Label3D billboards in the same world, which means:
#   - the walls naturally occlude them via depth testing
#   - they always face the camera (no manual projection math)
#   - their text is the entity's live ASCII glyph (read each frame from
#     the body's AsciiChar) so 2-frame animations carry through
#   - the post-shader processes everything together, so entities come out
#     as ASCII-density splats matching the wall aesthetic
#
# Coordinate mapping: 2D (x, y) pixels → 3D (x/TILE, eye_height, y/TILE).
# Godot uses Y-up in 3D, so the 2D Y axis maps to the 3D Z axis.

const TILE_PX: float = 32.0
const VIEWPORT_W: int = 200
const VIEWPORT_H: int = 80
const CELL_PX: float = 8.0

var _viewport: SubViewport = null
var _world3d: Node3D       = null
var _camera: Camera3D      = null
var _wall_mm: MultiMeshInstance3D = null
var _player_light: OmniLight3D = null
var _entity_root: Node3D   = null
# body InstanceID → {body, label3d (Label3D), stored_glyph, stored_color, base_pixel_size}
var _entities: Dictionary = {}

var _grid: Array = []
var _grid_w: int = 0
var _grid_h: int = 0

func _ready() -> void:
	layer = 1
	visible = false
	_build_scene()

func _build_scene() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.anchor_right = 1.0
	container.anchor_bottom = 1.0
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/ascii_post.gdshader")
	mat.set_shader_parameter("cell_px", CELL_PX)
	mat.set_shader_parameter("viewport_size", Vector2(VIEWPORT_W, VIEWPORT_H))
	container.material = mat
	add_child(container)

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(VIEWPORT_W, VIEWPORT_H)
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.handle_input_locally = false
	_viewport.snap_2d_transforms_to_pixel = true
	_viewport.own_world_3d = true
	container.add_child(_viewport)

	_world3d = Node3D.new()
	_viewport.add_child(_world3d)

	_camera = Camera3D.new()
	_camera.fov = 75.0
	_camera.near = 0.05
	_camera.far = 120.0
	_camera.position = Vector3(0, 0.5, 0)
	_world3d.add_child(_camera)
	_camera.make_current()

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.02, 0.02, 0.04)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.18, 0.18, 0.22)
	environment.ambient_light_energy = 0.6
	env.environment = environment
	_world3d.add_child(env)

	_player_light = OmniLight3D.new()
	_player_light.light_energy = 4.0
	_player_light.omni_range = 14.0
	_player_light.light_color = Color(1.0, 0.92, 0.78)
	_world3d.add_child(_player_light)

	_entity_root = Node3D.new()
	_world3d.add_child(_entity_root)

	# Crosshair stays as a 2D Label on the CanvasLayer (it's always at
	# screen-center regardless of camera).
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.add_theme_font_override("font", MonoFont.get_font())
	crosshair.add_theme_font_size_override("font_size", 28)
	crosshair.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.85))
	crosshair.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	crosshair.add_theme_constant_override("outline_size", 3)
	crosshair.anchor_left = 0.5
	crosshair.anchor_top = 0.5
	crosshair.anchor_right = 0.5
	crosshair.anchor_bottom = 0.5
	crosshair.offset_left = -10
	crosshair.offset_top = -16
	crosshair.offset_right = 10
	crosshair.offset_bottom = 16
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(crosshair)

func set_grid(grid: Array, grid_w: int, grid_h: int) -> void:
	_grid = grid
	_grid_w = grid_w
	_grid_h = grid_h
	rebuild_walls()

func rebuild_walls() -> void:
	if _grid.is_empty():
		return
	if _wall_mm != null and is_instance_valid(_wall_mm):
		_wall_mm.queue_free()
	var positions: Array[Vector3] = []
	for y in _grid_h:
		var row: Array = _grid[y]
		for x in _grid_w:
			if int(row[x]) == 1:
				positions.append(Vector3(float(x) + 0.5, 0.5, float(y) + 0.5))
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.74, 0.70)
	mat.roughness = 1.0
	box.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = positions.size()
	for i in positions.size():
		mm.set_instance_transform(i, Transform3D(Basis(), positions[i]))
	_wall_mm = MultiMeshInstance3D.new()
	_wall_mm.multimesh = mm
	_world3d.add_child(_wall_mm)
	_build_floor_ceiling()

func _build_floor_ceiling() -> void:
	for kv in [
		{"y": 0.0,  "color": Color(0.15, 0.13, 0.10)},
		{"y": 1.0,  "color": Color(0.05, 0.05, 0.08)},
	]:
		var plane := PlaneMesh.new()
		plane.size = Vector2(float(_grid_w) * 2.0, float(_grid_h) * 2.0)
		var pm := StandardMaterial3D.new()
		pm.albedo_color = kv["color"]
		pm.roughness = 1.0
		plane.material = pm
		var inst := MeshInstance3D.new()
		inst.mesh = plane
		inst.position = Vector3(float(_grid_w) * 0.5, kv["y"], float(_grid_h) * 0.5)
		_world3d.add_child(inst)

# Pixel size (world units per font pixel) baseline by kind. Bigger pixel
# size = bigger label in world space. Substantial projectiles get a bump
# so fire/shock/freeze read as impactful.
func _pixel_size_for(kind: String) -> float:
	match kind:
		"projectile_substantial":
			return 0.012
		"projectile":
			return 0.006
		_:
			return 0.014   # bodies (enemies, portals)

func _classify_entity(body: Node, glyph: String) -> String:
	if body.get("shoot_type") != null:
		var t: String = str(body.get("shoot_type"))
		if t in ["fire", "shock", "freeze", "nova_shard", "homing", "grenade"]:
			return "projectile_substantial"
		return "projectile"
	if glyph in ["*", "o", ".", "+", ","]:
		return "projectile"
	return "body"

func register_entity(body: Node2D, glyph: String = "X", color: Color = Color(0.95, 0.2, 0.2)) -> void:
	if not is_instance_valid(body):
		return
	if _entity_root == null or not is_instance_valid(_entity_root):
		return
	var key := body.get_instance_id()
	if _entities.has(key):
		return
	var kind: String = _classify_entity(body, glyph)
	var pixel_size: float = _pixel_size_for(kind)
	var lbl := Label3D.new()
	lbl.text = glyph
	lbl.font = MonoFont.get_font()
	lbl.font_size = 64
	lbl.outline_size = 12
	lbl.pixel_size = pixel_size
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = false   # walls occlude entities naturally
	lbl.shaded = false           # full self-light so the post-shader sees it crisp
	lbl.double_sided = true
	lbl.modulate = color
	lbl.outline_modulate = Color(0, 0, 0, 1)
	lbl.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	# Park at the body's spawn position so the very first frame already
	# has it placed (avoids a 1-frame flicker at origin).
	var bp: Vector2 = body.global_position
	lbl.position = Vector3(bp.x / TILE_PX, 0.5, bp.y / TILE_PX)
	_entity_root.add_child(lbl)
	_entities[key] = {
		"body": body,
		"label": lbl,
		"stored_glyph": glyph,
		"stored_color": color,
		"kind": kind,
	}

func unregister_entity(body: Node2D) -> void:
	if not is_instance_valid(body):
		return
	var key := body.get_instance_id()
	if not _entities.has(key):
		return
	var entry: Dictionary = _entities[key]
	var lbl_v: Variant = entry["label"]
	if is_instance_valid(lbl_v):
		(lbl_v as Node).queue_free()
	_entities.erase(key)

func clear_entities() -> void:
	for key in _entities.keys():
		var entry: Dictionary = _entities[key]
		var lbl_v: Variant = entry["label"]
		if is_instance_valid(lbl_v):
			(lbl_v as Node).queue_free()
	_entities.clear()

func _process(_delta: float) -> void:
	if not visible:
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player) or not (player is Node2D):
		return
	var player2d: Node2D = player as Node2D
	var pp: Vector2 = player2d.global_position

	# Camera sync.
	var aim: Vector2 = Vector2.RIGHT
	if player.has_method("get_aim_direction"):
		aim = player.get_aim_direction()
	var cam_pos := Vector3(pp.x / TILE_PX, 0.5, pp.y / TILE_PX)
	_camera.position = cam_pos
	_camera.look_at(cam_pos + Vector3(aim.x, 0.0, aim.y), Vector3.UP)
	_player_light.position = cam_pos

	# Entity sync — pull live glyph + status modulate from each body's
	# AsciiChar each frame so 2-frame animations + status tints carry into FP.
	var stale: Array = []
	for key in _entities.keys():
		var entry: Dictionary = _entities[key]
		var body_v: Variant = entry["body"]
		if not is_instance_valid(body_v) or not (body_v is Node2D):
			stale.append(key)
			continue
		var body: Node2D = body_v as Node2D
		var lbl_v: Variant = entry["label"]
		if not is_instance_valid(lbl_v):
			stale.append(key)
			continue
		var lbl: Label3D = lbl_v as Label3D
		if body == player2d:
			# Don't render the player's own glyph — the camera is them.
			lbl.visible = false
			continue
		var bp: Vector2 = body.global_position
		# Optional per-entity vertical placement — floor hazards register
		# with fp_height ~= 0.05 so they hug the ground; bodies default
		# to chest height.
		var ent_y: float = 0.55
		if body.has_meta("fp_height"):
			ent_y = float(body.get_meta("fp_height"))
		var ent_3d := Vector3(bp.x / TILE_PX, ent_y, bp.y / TILE_PX)
		# Near-cull so projectiles fresh off the gun don't engulf the view.
		if cam_pos.distance_to(ent_3d) < 0.55:
			lbl.visible = false
			continue
		lbl.visible = true
		lbl.position = ent_3d
		# Live glyph + modulate from body's AsciiChar.
		var stored_glyph: String = entry["stored_glyph"]
		var stored_color: Color = entry["stored_color"]
		var live_text: String = stored_glyph
		var live_modulate := Color(1, 1, 1, 1)
		var ascii_child: Node = body.get_node_or_null("AsciiChar")
		if ascii_child != null and ascii_child is Label:
			var al: Label = ascii_child as Label
			if al.text != "":
				# Use the first line only so multi-row enemy labels (e.g.
				# "d\n_") don't tower across the screen as a Label3D.
				var first_line: String = al.text.split("\n")[0]
				if first_line.strip_edges() != "":
					live_text = first_line
			live_modulate = al.modulate
		lbl.text = live_text
		lbl.modulate = stored_color * live_modulate
	for key in stale:
		var entry2: Dictionary = _entities[key]
		var lbl_v2: Variant = entry2["label"]
		if is_instance_valid(lbl_v2):
			(lbl_v2 as Node).queue_free()
		_entities.erase(key)
