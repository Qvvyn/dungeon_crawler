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

# Camera framing — the rig hosts two modes. "first" keeps the camera at the
# player's eye height (legacy FP); "third" lifts and pulls back so the
# player's wizard body is visible in front of the camera. World.gd flips
# between them via set_camera_mode() when the render mode changes.
#
# 3rd-person tuning notes:
#   - HEIGHT 0.55 keeps the camera comfortably below the new 1.5-tall walls
#     (so corridor ceilings don't read as a hard "horizon band").
#   - FOLLOW_DIST 1.3 stays close enough that the wizard body fills a
#     useful chunk of frame.
#   - LOOK_FORWARD 1.1 aims the focal point ahead of the wizard so enemies
#     in the player's aim cone read clearly.
# These produce an over-the-shoulder feel (~23° pitch) rather than a
# tilted top-down. _resolve_camera_position() then raycasts against the
# wall grid each frame so the camera never sits inside / behind a wall.
var _camera_mode: String = "first"
# Tuned 2× pass: camera was 1.3 behind / 0.55 above, which was too close to
# the wizard (it dominated screen mid) AND too high (read as top-down).
# New framing pulls way back + drops the angle to a clear over-shoulder
# stance: camera at y≈0.95 looking at the player roughly horizontally, and
# the wizard now spans enough SubViewport pixels to be legible through
# the ASCII post-shader (~10 source pixels per character vs. ~5 before).
const TP_FOLLOW_DIST: float  = 1.6
const TP_HEIGHT: float       = 0.55
const TP_LOOK_FORWARD: float = 1.2
const TP_MIN_DIST: float     = 0.45   # how close the camera can clamp to player when a wall pinches in
const TP_WALL_PAD: float     = 0.18   # back-off from the wall hit so camera doesn't clip the surface

# Render layers — walls/floor/ceiling on bit 0 (mask 1), entity Label3Ds
# (player, enemies, projectiles, HP bars) on bit 1 (mask 2). The main
# camera renders only the environment so the ASCII post-shader can stylize
# the walls. The entity camera renders only the Label3Ds without a shader,
# so enemy ASCII art stays crisp while still perspective-scaling and being
# occluded by walls via the per-frame raycast.
const LAYER_ENV: int = 1
const LAYER_ENT: int = 2

# Wall height (world units). Boxes are centered, so a wall's center y = _WALL_H/2.
# Shared by the static wall mesh (rebuild_walls) and animated wall segments.
const _WALL_H: float = 1.5

# Vertical spacing multiplier between rows of multi-line ASCII art. 1.0
# packs rows at exactly font height; a little above 1.0 opens up the
# silhouette so stacked glyphs (e.g. the wizard) read more clearly.
const ROW_SPACING: float = 1.18

var _viewport_ent: SubViewport = null   # entity-only viewport (no shader)
var _camera_ent: Camera3D = null         # mirrors _camera each frame
var _ent_world3d: Node3D = null          # root inside _viewport_ent's world

# Wall albedo — set by World to the active biome's 2D wall color so FP
# walls match top-down. Defaults to the old tan until set.
var _wall_albedo: Color = Color(0.78, 0.74, 0.70)
# Floor albedo — set by World per biome so the FP ground reads the zone
# (was a fixed warm grey for every biome).
var _floor_albedo: Color = Color(0.15, 0.13, 0.10)

# In 3rd-person mode the player needs a Label3D so they're actually visible
# in front of the camera. Tracked here so we can register on entry to
# 3rd-person and unregister on exit (first-person should not show a
# floating wizard at the camera position).

var _viewport: SubViewport = null
var _world3d: Node3D       = null
var _camera: Camera3D      = null
# Walls are partitioned into uniform grid chunks (Build-engine-style sectors)
# so future per-tile height changes (DOOM_DESIGN.md §3 — lifts, crushers)
# only have to rebuild one chunk's MultiMesh, not all walls. Chunk coord =
# (tile_x / WALL_CHUNK_SIZE, tile_y / WALL_CHUNK_SIZE), stored as Vector2i.
const WALL_CHUNK_SIZE: int = 8
var _wall_chunks: Dictionary = {}   # Vector2i → MultiMeshInstance3D
# Floor + ceiling plane instances, tracked so rebuild_walls() (which can run
# again mid-floor when a secret passage opens) frees the old ones instead of
# stacking duplicate planes that z-fight.
var _floor_ceiling: Array[MeshInstance3D] = []
# Animated wall segments (doors / lifts / crushers). Separate MeshInstance3D
# nodes in _world3d so animating a height never triggers a full rebuild_walls().
var _wall_segments: Dictionary = {}   # id -> MeshInstance3D
# Per-segment tile + open_amount tracking so the entity-occlusion raycast
# can treat closed segments as walls. Without this, enemies behind a closed
# door render right through the visual wall (door tiles aren't in _grid).
var _segment_tile: Dictionary = {}    # id -> Vector2i (the grid tile the segment sits on)
var _segment_open: Dictionary = {}    # id -> float (0=closed, 1=fully open)
var _tile_blocks_sight: Dictionary = {}  # Vector2i -> true (only blocking tiles stored)
const _SEGMENT_BLOCK_THRESHOLD: float = 0.5   # wall blocks sight while it's at least half-height
var _next_segment_id: int = 1
var _player_light: OmniLight3D = null
# ASCII post-shader material — referenced so set_blinded() can drive the
# `darkness` uniform without re-finding the container each call.
var _ascii_mat: ShaderMaterial = null
# ── Sector lighting (DOOM-style per-room darkness + torch flicker) ─────────────
var _env: Environment = null          # stored so ambient_light_energy is drivable
var _light_rooms: Array = []          # Array[Rect2i], parallel to _light_levels
var _light_levels: Array = []         # 0=NORMAL, 1=DARK, 2=FLICKER
var _cur_room_idx: int = -1           # cached room the player is in
const _AMBIENT_NORMAL: float = 0.95   # matches the base ambient in _build_scene
const _AMBIENT_DARK: float = 0.12     # torch-only pool; shader thins to sparse glyphs
const _TORCH_BASE_ENERGY: float = 4.0
var _entity_root: Node3D   = null
# body InstanceID → {body, label3d (Label3D), stored_glyph, stored_color, base_pixel_size}
var _entities: Dictionary = {}
var _ice_cubes: Dictionary = {}  # body instance_id → persistent ice-cube Label3D in _world3d

# Hitbox wireframe debug mesh — rebuilt each frame when GameState.show_hitboxes
var _hitbox_mesh: ImmediateMesh      = null
var _hitbox_mi:   MeshInstance3D     = null
var _hitbox_mat:  StandardMaterial3D = null

var _grid: Array = []
var _grid_w: int = 0
var _grid_h: int = 0

# Beam / melee transient effects — owned by the rig so they can render in
# the SubViewport's 3D world. The player tells the rig "draw a beam from
# here to there" or "punch landed at this point" and the rig pools labels
# accordingly.
var _beam_dots: Array[Label3D] = []
var _beam_tube: MeshInstance3D = null
var _beam_active: bool = false
var _melee_lbl: Label3D = null
var _melee_timer: float = 0.0
const MELEE_LIFE: float = 0.18

# Enemy beam emitter visuals — keyed by the emitter's instance ID so multiple
# beam-sweeping enemies can fire concurrently without trampling each other.
# Telegraph phase uses pooled "·" Label3D dots (the warning visual the
# player can clearly read as "incoming beam, get out"); sweep phase uses a
# solid CylinderMesh tube per emitter — same "crunchy ray" visual the
# player's beam wand produces, oriented via the shared _orient_beam_tube
# helper. Both stored per-emitter so concurrent sweepers don't collide.
var _enemy_beam_pools: Dictionary = {}   # emitter_id → Array[Label3D] (telegraph dots)
var _enemy_beam_tubes: Dictionary = {}   # emitter_id → MeshInstance3D (sweep cylinder)

# (Shock zap is now fire-and-forget — each tick spawns a brief Line2D that
# fades + queue_frees itself, no per-emitter pool. The old pooled approach
# left orphaned lines when projection failed at projectile-near-camera
# spawn frames.)

# Floating combat text tracks its source world position each frame so the
# text stays anchored to the enemy as the camera moves — was tweening the
# screen-space position once at spawn, which made the text drift off the
# enemy if the camera turned. Each entry: {label, world_pos, age, lifetime, drift_y}.
var _floating_texts: Array = []
# Per-emitter persistent warning ring (grenadier danger zone).
var _enemy_warning_pools: Dictionary = {}
# Lock-on warning — multiple turrets can lock the player at once; we just
# need to know whether ANY of them currently has a lock to flash the
# screen-space "[ LOCK ]" warning.
var _lock_emitters: Dictionary = {}
var _lock_label: Label = null

# Interact hint surfacing — scans registered entities each frame for any
# visible "[E] ..." style sub-Label and floats it on the FP CanvasLayer
# so the player can read what's interactable without seeing the 2D world.
var _interact_label: Label = null

# Enemy HP bar pool — keyed by enemy instance id. Each entry is a Label3D
# placed above the enemy's head inside the SubViewport, so the ASCII
# post-shader pixelates the bar text along with everything else (instead
# of the bar sitting crisp on the CanvasLayer above the ASCII view).
var _hp_bars: Dictionary = {}     # enemy_id -> Label3D (LAYER_ENT)
var _hp_bar_fill: Dictionary = {} # enemy_id -> last filled-cell count (text-rebuild cache)
var _hp_bar_color: Dictionary = {} # enemy_id -> last color bucket (0/1/2), modulate-assign cache
# Debug name overlay (KEY_N) — Label3Ds floated above enemy heads. Created
# lazily when GameState.show_enemy_names flips on; reaped here when the
# enemy dies AND on the same toggle going off.
var _name_labels: Dictionary = {}  # enemy_id -> Label3D (LAYER_ENT)
# Per-frame counter used to stagger raycasts across entities.
var _frame_counter: int = 0
# Cached wall-occlusion result per entity (key → bool). Recomputed on a
# rolling 3-frame schedule so each entity raycasts once every 3 frames.
var _occlusion_cache: Dictionary = {}

# Camera shake — added on top of the normal cam_pos each frame and decays
# linearly. Driven by `shake(duration, intensity)` from gameplay events the
# same way Player.camera_shake nudges the 2D Camera2D.
var _shake_t: float = 0.0
var _shake_total: float = 0.0
var _shake_intensity: float = 0.0

func _ready() -> void:
	layer = 1
	visible = false
	_build_scene()

# Called by World when the render mode flips. "first" puts the camera at
# the player's eyes; "third" lifts + pulls back so the wizard Label3D sits
# in front of the camera. Player registration happens at the World level
# (with wizard art + purple tint + fp_multiline meta) so the Label3D is
# always present; this just toggles whether _process draws it.
func set_camera_mode(mode: String) -> void:
	if mode != "first" and mode != "third":
		return
	_camera_mode = mode

# Drives the ASCII post-shader's `darkness` uniform. 0.0 = no vignette,
# 1.0 = nearly all the screen blacked out except a tight center disk.
# Hook for status effects ("blinded" debuff) or environmental hazards.
func set_blinded(amount: float) -> void:
	if _ascii_mat == null:
		return
	_ascii_mat.set_shader_parameter("darkness", clampf(amount, 0.0, 1.0))

# Walks a ray (in tile coords) from `from` toward `to`, returning the
# point just before the first wall cell. Used by 3rd-person to keep the
# camera in front of any wall behind the player. Steps in ~0.1-tile
# increments since walls are 1×1 tiles — coarse enough to be cheap, fine
# enough to never overshoot. Returns `to` if nothing's in the way.
func _raycast_to_grid(from: Vector2, to: Vector2) -> Vector2:
	if _grid.is_empty() or _grid_w == 0 or _grid_h == 0:
		return to
	var diff: Vector2 = to - from
	var dist: float = diff.length()
	if dist < 0.001:
		return to
	var dir: Vector2 = diff / dist
	const STEP: float = 0.10
	var traveled: float = 0.0
	var prev_clear: Vector2 = from
	while traveled < dist:
		traveled += STEP
		var t: float = minf(traveled, dist)
		var pt: Vector2 = from + dir * t
		var gx: int = int(floor(pt.x))
		var gy: int = int(floor(pt.y))
		if gx < 0 or gy < 0 or gx >= _grid_w or gy >= _grid_h:
			# Out of bounds — treat like a wall so the camera doesn't escape.
			return prev_clear
		var row: Array = _grid[gy]
		# Closed-enough wall segments (doors, lifts, crushers) also block
		# sight — without this, enemies render right through a closed door
		# because the door tile itself is FLOOR in _grid.
		if int(row[gx]) == 1 or _tile_blocks_sight.has(Vector2i(gx, gy)):
			# Back off slightly along the ray so we sit in front of the wall.
			var safe_t: float = maxf(0.0, t - TP_WALL_PAD)
			return from + dir * safe_t
		prev_clear = pt
	return to

func _build_scene() -> void:
	# Environment viewport — walls/floor/ceiling, processed by the ASCII
	# post-shader. Camera_env renders only LAYER_ENV.
	var container := SubViewportContainer.new()
	container.stretch = true
	container.anchor_right = 1.0
	container.anchor_bottom = 1.0
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Fixed resolution. The old low-res mode (halving vp_w/vp_h/cell_px
	# from GameState.fp_low_res) produced a mostly-black scene at runtime —
	# disabled until that's diagnosed. The GameState flag is left around
	# for save-file compatibility but not read anywhere.
	var vp_w: int   = VIEWPORT_W
	var vp_h: int   = VIEWPORT_H
	var cell: float = CELL_PX

	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/ascii_post.gdshader")
	mat.set_shader_parameter("cell_px", cell)
	mat.set_shader_parameter("viewport_size", Vector2(vp_w, vp_h))
	mat.set_shader_parameter("darkness", 0.0)
	container.material = mat
	_ascii_mat = mat
	add_child(container)

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(vp_w, vp_h)
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.handle_input_locally = false
	_viewport.snap_2d_transforms_to_pixel = true
	_viewport.own_world_3d = true
	container.add_child(_viewport)

	_world3d = Node3D.new()
	_viewport.add_child(_world3d)

	_camera = Camera3D.new()
	_camera.fov = 82.0
	_camera.near = 0.05
	_camera.far = 120.0
	_camera.position = Vector3(0, 0.5, 0)
	_world3d.add_child(_camera)
	_camera.make_current()

	# Entity viewport — same 3D world, second camera, only renders Label3Ds
	# (cull_mask=LAYER_ENT). Transparent bg so the env container shows
	# through. No shader on this container — entity ASCII art renders crisp
	# at SubViewport resolution. Added AFTER container so it sits above
	# the shader-filtered environment.
	var container_ent := SubViewportContainer.new()
	container_ent.stretch = true
	container_ent.anchor_right = 1.0
	container_ent.anchor_bottom = 1.0
	container_ent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container_ent)

	_viewport_ent = SubViewport.new()
	_viewport_ent.size = Vector2i(vp_w, vp_h)
	_viewport_ent.transparent_bg = true
	_viewport_ent.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport_ent.handle_input_locally = false
	_viewport_ent.snap_2d_transforms_to_pixel = true
	# Separate World3D — entity Label3Ds register their visual reps with
	# this viewport's scenario, and camera_ent renders only this scenario.
	# Two completely independent rendering worlds avoids the cross-viewport
	# world-sharing pitfalls.
	_viewport_ent.own_world_3d = true
	container_ent.add_child(_viewport_ent)

	_ent_world3d = Node3D.new()
	_viewport_ent.add_child(_ent_world3d)

	_camera_ent = Camera3D.new()
	_camera_ent.fov = 82.0
	_camera_ent.near = 0.05
	_camera_ent.far = 120.0
	_ent_world3d.add_child(_camera_ent)
	_camera_ent.make_current()

	# Entity Label3Ds live here — register_entity() adds children to this
	# node, so they end up in the entity viewport's world (renders without
	# the post-shader).
	_entity_root = Node3D.new()
	_ent_world3d.add_child(_entity_root)

	_hitbox_mesh = ImmediateMesh.new()
	_hitbox_mat  = StandardMaterial3D.new()
	_hitbox_mat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hitbox_mat.vertex_color_use_as_albedo = true
	_hitbox_mat.cull_mode                 = BaseMaterial3D.CULL_DISABLED
	_hitbox_mi   = MeshInstance3D.new()
	_hitbox_mi.mesh              = _hitbox_mesh
	_hitbox_mi.material_override = _hitbox_mat
	_hitbox_mi.layers            = LAYER_ENT
	_ent_world3d.add_child(_hitbox_mi)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.02, 0.02, 0.04)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Theme F — lift dark corners. Bumped energy 0.6→0.95 and the color
	# itself slightly so far walls catch enough light to be readable while
	# still keeping the moody, dim-dungeon feel (the OmniLight player
	# torch is still the primary lighting that makes nearby detail pop).
	environment.ambient_light_color = Color(0.22, 0.22, 0.26)
	environment.ambient_light_energy = _AMBIENT_NORMAL
	env.environment = environment
	_world3d.add_child(env)
	_env = environment   # kept so per-room darkness can drive ambient each frame

	_player_light = OmniLight3D.new()
	_player_light.light_energy = 4.0
	_player_light.omni_range = 14.0
	_player_light.light_color = Color(1.0, 0.92, 0.78)
	_world3d.add_child(_player_light)

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

func set_wall_color(col: Color) -> void:
	_wall_albedo = col
	# If walls already exist, rebuild so the new color takes effect.
	if not _wall_chunks.is_empty() and not _grid.is_empty():
		rebuild_walls()

# Biome wall albedo (already lightened the same way the baked walls are) so
# animated segments can match the surrounding wall color.
func get_wall_color() -> Color:
	return _wall_albedo.lightened(0.15)

# ── Sector lighting ───────────────────────────────────────────────────────────
# World passes per-room light levels (0=NORMAL, 1=DARK, 2=FLICKER) parallel to
# the room rects. _update_lighting (per frame) drives ambient + torch from these.
func set_room_lighting(rooms: Array, levels: Array) -> void:
	_light_rooms = rooms
	_light_levels = levels
	_cur_room_idx = -1

func _update_lighting(delta: float, pp: Vector2) -> void:
	if _env == null or not is_instance_valid(_player_light):
		return
	var amp_scale: float = 0.35 if GameState.disable_flashing else 1.0
	var t: float = Time.get_ticks_msec() * 0.001
	# Which room is the player in? Use the cached one if still inside; else rescan.
	var level: int = 0
	if not _light_rooms.is_empty() and _light_rooms.size() == _light_levels.size():
		var ptile := Vector2i(int(pp.x / TILE_PX), int(pp.y / TILE_PX))
		if _cur_room_idx >= 0 and _cur_room_idx < _light_rooms.size() \
				and (_light_rooms[_cur_room_idx] as Rect2i).has_point(ptile):
			level = int(_light_levels[_cur_room_idx])
		else:
			_cur_room_idx = -1
			for i in _light_rooms.size():
				if (_light_rooms[i] as Rect2i).has_point(ptile):
					_cur_room_idx = i
					level = int(_light_levels[i])
					break
	# Ambient target by level. FLICKER strobes directly; others ease.
	if level == 2 and not GameState.disable_flashing:
		var flick: float = clampf(sin(t * 12.0) * sin(t * 3.3) + 0.25, 0.0, 1.0)
		_env.ambient_light_energy = lerpf(_AMBIENT_DARK, _AMBIENT_NORMAL, flick)
	else:
		var target: float = _AMBIENT_NORMAL
		if level == 1:
			target = _AMBIENT_DARK
		elif level == 2:
			target = (_AMBIENT_DARK + _AMBIENT_NORMAL) * 0.5   # reduce-flashing: steady mid
		_env.ambient_light_energy = lerpf(_env.ambient_light_energy, target, clampf(delta * 3.0, 0.0, 1.0))
	# Torch flicker — subtle layered sine so the torch reads as alive.
	var tf: float = (sin(t * 9.0) * 0.5 + 0.5) * 0.6 + (sin(t * 23.0 + 2.1) * 0.5 + 0.5) * 0.4
	var torch_amp: float = 0.12 * amp_scale
	_player_light.light_energy = _TORCH_BASE_ENERGY * (1.0 - torch_amp + torch_amp * tf)

func set_floor_color(col: Color) -> void:
	_floor_albedo = col
	# Rebuild so the floor plane picks up the new biome color.
	if not _wall_chunks.is_empty() and not _grid.is_empty():
		rebuild_walls()

func set_grid(grid: Array, grid_w: int, grid_h: int) -> void:
	_grid = grid
	_grid_w = grid_w
	_grid_h = grid_h
	rebuild_walls()

func rebuild_walls() -> void:
	if _grid.is_empty():
		return
	# Free any existing chunks before rebuilding.
	for chunk_v in _wall_chunks.values():
		if is_instance_valid(chunk_v):
			(chunk_v as Node).queue_free()
	_wall_chunks.clear()
	# Bucket wall tiles by chunk coord so each chunk gets its own MultiMesh.
	# Build-engine-style partition: future per-tile floor/ceiling height
	# changes (lifts, crushers — DOOM_DESIGN.md §3) can rebuild only the
	# affected chunk via _rebuild_wall_chunk(), not the whole grid.
	# Theme F — walls raised 1.0→1.5 tall to lift their tops well above the
	# 0.5 eye line. At full 1.0 height the wall ceiling sat exactly at the
	# camera's Y, which gave the horizon a flat "ceiling band" that swallowed
	# distant enemies. With taller walls the player's torch fades cleanly into
	# darkness above, distant entities stay below the ceiling line, and the
	# corridors feel more mazey. Mesh is centered, so position y = height/2.
	var buckets: Dictionary = {}   # Vector2i → Array[Vector3]
	for y in _grid_h:
		var row: Array = _grid[y]
		for x in _grid_w:
			if int(row[x]) != 1:
				continue
			var co := Vector2i(x / WALL_CHUNK_SIZE, y / WALL_CHUNK_SIZE)
			if not buckets.has(co):
				buckets[co] = [] as Array
			(buckets[co] as Array).append(Vector3(float(x) + 0.5, _WALL_H * 0.5, float(y) + 0.5))
	# Shared box + material across every chunk — single geometry resource,
	# one MultiMeshInstance3D draw call per non-empty chunk.
	var box := BoxMesh.new()
	box.size = Vector3(1.0, _WALL_H, 1.0)
	var mat := StandardMaterial3D.new()
	# Brighten the biome wall color a touch so it reads under the dim
	# dungeon lighting + ASCII shader (the raw 2D color is quite dark).
	mat.albedo_color = _wall_albedo.lightened(0.15)
	mat.roughness = 1.0
	box.material = mat
	for co in buckets.keys():
		var positions: Array = buckets[co]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = box
		mm.instance_count = positions.size()
		for i in positions.size():
			mm.set_instance_transform(i, Transform3D(Basis(), positions[i] as Vector3))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.layers = LAYER_ENV
		_world3d.add_child(mmi)
		_wall_chunks[co] = mmi
	_build_floor_ceiling()

# Future hook for per-tile height changes — rebuilds only the wall chunk
# that contains the given grid tile, leaving all other chunks intact.
# Not currently wired (no per-tile heights yet), but ready for the lifts /
# crushers work in DOOM_DESIGN.md §3.
func rebuild_wall_chunk_for_tile(gx: int, gy: int) -> void:
	if _grid.is_empty() or _world3d == null or not is_instance_valid(_world3d):
		return
	if gx < 0 or gy < 0 or gx >= _grid_w or gy >= _grid_h:
		return
	_rebuild_wall_chunk(Vector2i(gx / WALL_CHUNK_SIZE, gy / WALL_CHUNK_SIZE))

func _rebuild_wall_chunk(co: Vector2i) -> void:
	# Free the old chunk if present.
	if _wall_chunks.has(co):
		var old_v: Variant = _wall_chunks[co]
		if is_instance_valid(old_v):
			(old_v as Node).queue_free()
		_wall_chunks.erase(co)
	# Scan only this chunk's tile range and bucket walls.
	var x_start: int = co.x * WALL_CHUNK_SIZE
	var y_start: int = co.y * WALL_CHUNK_SIZE
	var x_end: int = mini(x_start + WALL_CHUNK_SIZE, _grid_w)
	var y_end: int = mini(y_start + WALL_CHUNK_SIZE, _grid_h)
	if x_start < 0 or y_start < 0 or x_start >= _grid_w or y_start >= _grid_h:
		return
	var positions: Array[Vector3] = []
	for y in range(y_start, y_end):
		var row: Array = _grid[y]
		for x in range(x_start, x_end):
			if int(row[x]) == 1:
				positions.append(Vector3(float(x) + 0.5, _WALL_H * 0.5, float(y) + 0.5))
	if positions.is_empty():
		return
	var box := BoxMesh.new()
	box.size = Vector3(1.0, _WALL_H, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _wall_albedo.lightened(0.15)
	mat.roughness = 1.0
	box.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = positions.size()
	for i in positions.size():
		mm.set_instance_transform(i, Transform3D(Basis(), positions[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.layers = LAYER_ENV
	_world3d.add_child(mmi)
	_wall_chunks[co] = mmi

func _build_floor_ceiling() -> void:
	# Free any planes from a previous build so re-runs (secret passage opening)
	# don't stack duplicates.
	for old in _floor_ceiling:
		if is_instance_valid(old):
			old.queue_free()
	_floor_ceiling.clear()
	# Ceiling matches the wall top (1.5) so the camera never floats above
	# it. The original 1.0 ceiling was below the new 1.5 walls, which the
	# 3rd-person camera (y≈1.05) sat *above* — making the dark ceiling
	# plane render as a giant black billboard covering most of the lower
	# half of the screen.
	# Floor + ceiling — flat planes with simple standard materials. Earlier
	# experiments with a purple/blue night-sky shader on the ceiling
	# produced beam-like artifacts and unreliable star visibility through
	# the ASCII post-shader; reverted to plain black up top until a
	# different approach is tried.
	for kv in [
		{"y": 0.0,  "color": _floor_albedo},
		{"y": 1.5,  "color": Color(0.0, 0.0, 0.0)},
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
		inst.layers = LAYER_ENV
		_world3d.add_child(inst)
		_floor_ceiling.append(inst)

# ── Animated wall segments (doors / lifts / crushers) ─────────────────────────
# A wall-shaped box that a caller (e.g. Door.gd) animates independently of the
# baked wall mesh. Lives in _world3d on LAYER_ENV so it reads exactly like a
# real wall through the ASCII post-shader. Returns an id for later control.
func add_wall_segment(pos_2d: Vector2, color: Color) -> int:
	if _world3d == null or not is_instance_valid(_world3d):
		return -1
	var box := BoxMesh.new()
	box.size = Vector3(1.0, _WALL_H, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	box.material = mat
	var seg := MeshInstance3D.new()
	seg.mesh = box
	seg.position = Vector3(pos_2d.x / TILE_PX, _WALL_H * 0.5, pos_2d.y / TILE_PX)
	seg.layers = LAYER_ENV
	_world3d.add_child(seg)
	var id := _next_segment_id
	_next_segment_id += 1
	_wall_segments[id] = seg
	# Record the tile so the entity-occlusion raycast can treat this segment
	# as a wall when it's closed. Tile coord derives from the pos_2d (which
	# Door.gd hands in as tile-center pixel coords).
	var tile := Vector2i(int(floor(pos_2d.x / TILE_PX)), int(floor(pos_2d.y / TILE_PX)))
	_segment_tile[id] = tile
	_segment_open[id] = 0.0   # spawns closed by convention; set_wall_segment_open updates this
	_recompute_tile_block(tile)
	return id

# t in [0,1]: 0 = closed (full height), 1 = open (sunk fully into the floor).
func set_wall_segment_open(id: int, t: float) -> void:
	var seg: MeshInstance3D = _wall_segments.get(id) as MeshInstance3D
	if seg == null or not is_instance_valid(seg):
		return
	var amt: float = clampf(t, 0.0, 1.0)
	seg.scale.y = maxf(0.001, 1.0 - amt)
	# Keep the base on the floor while the top sinks: center y = remaining/2.
	seg.position.y = _WALL_H * (1.0 - amt) * 0.5
	_segment_open[id] = amt
	if _segment_tile.has(id):
		_recompute_tile_block(_segment_tile[id] as Vector2i)

func remove_wall_segment(id: int) -> void:
	var seg: MeshInstance3D = _wall_segments.get(id) as MeshInstance3D
	if seg != null and is_instance_valid(seg):
		seg.queue_free()
	_wall_segments.erase(id)
	var tile_v: Variant = _segment_tile.get(id)
	_segment_tile.erase(id)
	_segment_open.erase(id)
	if tile_v != null:
		_recompute_tile_block(tile_v as Vector2i)

# Walks every segment on `tile` and flips _tile_blocks_sight accordingly.
# Called whenever a segment is added/removed or its open_amount changes —
# cheap because the dungeon never has many active segments at once.
func _recompute_tile_block(tile: Vector2i) -> void:
	for sid in _segment_tile.keys():
		if _segment_tile[sid] != tile:
			continue
		if float(_segment_open.get(sid, 1.0)) < _SEGMENT_BLOCK_THRESHOLD:
			_tile_blocks_sight[tile] = true
			return
	_tile_blocks_sight.erase(tile)

# Pixel size (world units per font pixel) baseline by kind. Projectiles are
# kept small and uniform so they read as fast-moving sparks rather than
# screen-filling sprites — the previous "substantial" bump made fire/shock/
# freeze shots tower across the view. Bodies keep the larger size so enemies
# remain visible at range.
func _pixel_size_for(kind: String) -> float:
	match kind:
		"projectile_substantial":
			return 0.006
		"projectile":
			return 0.004
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
	# Per-body override — multi-line ASCII art (e.g. the freeze ice block)
	# needs a smaller pixel_size so the billboard fits within the corridor.
	if body.has_meta("fp_pixel_size"):
		pixel_size = float(body.get_meta("fp_pixel_size"))
	# Outline rules:
	#  - Projectiles get NO outline — they're small, fast-moving glyphs and
	#    a thick black border just thickens them visually without adding
	#    legibility.
	#  - Bodies default to 12 px so the silhouette reads against the
	#    shader-rendered environment.
	#  - Per-entity `fp_outline_size` meta overrides either.
	var outline_size: int = 12
	if kind == "projectile" or kind == "projectile_substantial":
		outline_size = 0
	if body.has_meta("fp_outline_size"):
		outline_size = int(body.get_meta("fp_outline_size"))

	var bp: Vector2 = body.global_position
	var anchor_pos := Vector3(bp.x / TILE_PX, 0.5, bp.y / TILE_PX)
	var raw_lines: Array = glyph.split("\n")
	var is_multiline: bool = raw_lines.size() > 1
	# Floor decals lie FLAT on the floor (rotated -90° about X so the text
	# plane faces up) with billboarding disabled, instead of the upright
	# camera-facing default. Used by floor hazards (traps, lava, etc).
	var is_floor_decal: bool = body.has_meta("fp_floor_decal") and bool(body.get_meta("fp_floor_decal"))
	# entry["label"] is the rendered Node3D — for multi-line it's a parent
	# Node3D whose children are per-row Label3Ds; for single-line it's the
	# Label3D itself. Other code can read .position / .visible / .modulate
	# without caring which (Node3D + Label3D both expose .position / .visible;
	# modulate is per-Label3D, handled by the _process loop for multi-line).
	var lbl: Node3D = null
	var line_labels: Array[Label3D] = []
	# Multi-line entities take one of two paths:
	#  - Consolidated (default): a single Label3D with embedded \n. Native
	#    Godot multi-line text — 1 draw call regardless of row count, and
	#    status overlays just append more \n lines. The headline win for
	#    bigger ASCII sprites.
	#  - Legacy per-row: a Node3D parent with one Label3D child per row.
	#    Required when the entity needs sub-row positioning (the wizard's
	#    `fp_line_x_offsets` half-shifts the robe) or floor-decal flat
	#    layout. Opt-in via those metas.
	var is_consolidated: bool = is_multiline \
		and not is_floor_decal \
		and not body.has_meta("fp_line_x_offsets")
	if is_multiline and not is_consolidated:
		lbl = Node3D.new()
		# Scale per-row pixel_size so the whole multi-line entity fits in
		# the same vertical envelope as a single-line entity (mirrors the
		# pixel_size / line_count auto-scale the old single-Label3D path
		# used). Without this, each row renders at the base size and a
		# 5-row wizard towers 5x taller than it should.
		var line_count: int = raw_lines.size()
		var row_ps: float = pixel_size / float(maxi(1, line_count))
		var line_h: float = 64.0 * row_ps * ROW_SPACING
		var mid_row: float = float(line_count - 1) * 0.5
		# Per-row x offset (in CHARS) for fine-tuning rows that the
		# even-char-count CENTER alignment lands a half-char off. Body
		# may expose `fp_line_x_offsets` as an Array[float], one entry
		# per row; missing entries default to 0.
		var x_offsets: Array = []
		if body.has_meta("fp_line_x_offsets"):
			var xv: Variant = body.get_meta("fp_line_x_offsets")
			if xv is Array:
				x_offsets = xv
		# 1 char in world units ≈ font_size * row_ps * advance_ratio.
		const CHAR_ADVANCE_RATIO: float = 0.55
		var char_world: float = 64.0 * row_ps * CHAR_ADVANCE_RATIO
		for i in line_count:
			# Strip leading AND trailing whitespace so each row's visible
			# content centers around the parent X position.
			var row_text: String = (raw_lines[i] as String).strip_edges()
			var row_lbl := Label3D.new()
			row_lbl.text = row_text
			row_lbl.font = MonoFont.get_font()
			row_lbl.font_size = 64
			row_lbl.outline_size = outline_size
			row_lbl.pixel_size = row_ps
			row_lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED if is_floor_decal else BaseMaterial3D.BILLBOARD_ENABLED
			row_lbl.no_depth_test = false
			row_lbl.shaded = false
			row_lbl.double_sided = true
			row_lbl.modulate = color
			row_lbl.outline_modulate = Color(0, 0, 0, 1)
			row_lbl.alpha_cut = Label3D.ALPHA_CUT_DISCARD
			row_lbl.layers = LAYER_ENT
			var row_x_off: float = 0.0
			if i < x_offsets.size():
				row_x_off = float(x_offsets[i]) * char_world
			row_lbl.position = Vector3(row_x_off, (mid_row - float(i)) * line_h, 0.0)
			lbl.add_child(row_lbl)
			line_labels.append(row_lbl)
	elif is_consolidated:
		# Single Label3D with the full multi-line glyph. Godot Label3D
		# centers each line independently around the local X axis when
		# HORIZONTAL_ALIGNMENT_CENTER is set, matching the legacy stacked
		# look without per-row children.
		var sl_c := Label3D.new()
		sl_c.text = glyph
		sl_c.font = MonoFont.get_font()
		sl_c.font_size = 64
		sl_c.outline_size = outline_size
		sl_c.pixel_size = pixel_size / float(maxi(1, raw_lines.size()))
		sl_c.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sl_c.no_depth_test = false
		sl_c.shaded = false
		sl_c.double_sided = true
		sl_c.modulate = color
		sl_c.outline_modulate = Color(0, 0, 0, 1)
		sl_c.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		sl_c.layers = LAYER_ENT
		sl_c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl = sl_c
	else:
		var sl := Label3D.new()
		sl.text = glyph
		sl.font = MonoFont.get_font()
		sl.font_size = 64
		sl.outline_size = outline_size
		sl.pixel_size = pixel_size
		sl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sl.no_depth_test = false
		sl.shaded = false
		sl.double_sided = true
		sl.modulate = color
		sl.outline_modulate = Color(0, 0, 0, 1)
		sl.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		sl.layers = LAYER_ENT
		if body.has_meta("fp_rotation_z") or body.has_meta("fp_spin_rate") or is_floor_decal:
			sl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		lbl = sl
	lbl.position = anchor_pos
	# Lay floor decals flat on the floor — text plane faces up (+Y).
	if is_floor_decal:
		lbl.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	_entity_root.add_child(lbl)
	_entities[key] = {
		"body": body,
		"label": lbl,
		"line_labels": line_labels,
		"stored_glyph": glyph,
		"stored_color": color,
		"kind": kind,
		"is_multiline": is_multiline,
		"is_floor_decal": is_floor_decal,
		"is_consolidated": is_consolidated,
		"registered_rows": raw_lines.size() if is_multiline else 1,
	}

# Updates an already-registered entity's stored_glyph and stored_color.
# Used by entities whose displayed art changes after spawn (e.g. LootBag
# re-tinting + reshaping when its rarity tier changes). The live AsciiChar
# read still wins per-frame if the body has an AsciiChar child; this is
# strictly for bodies that don't have one.
func update_fp_visual(body: Node2D, glyph: String, color: Color) -> void:
	if not is_instance_valid(body):
		return
	var key := body.get_instance_id()
	if not _entities.has(key):
		return
	var entry: Dictionary = _entities[key]
	entry["stored_glyph"] = glyph
	entry["stored_color"] = color

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
	if _ice_cubes.has(key):
		if is_instance_valid(_ice_cubes[key]):
			(_ice_cubes[key] as Node).queue_free()
		_ice_cubes.erase(key)

func clear_entities() -> void:
	for key in _entities.keys():
		var entry: Dictionary = _entities[key]
		var lbl_v: Variant = entry["label"]
		if is_instance_valid(lbl_v):
			(lbl_v as Node).queue_free()
	_entities.clear()
	# Free any animated wall segments (doors etc.) so they don't leak across floors.
	for sid in _wall_segments.keys():
		var seg_v: Variant = _wall_segments[sid]
		if is_instance_valid(seg_v):
			(seg_v as Node).queue_free()
	_wall_segments.clear()
	_segment_tile.clear()
	_segment_open.clear()
	_tile_blocks_sight.clear()

func _process(delta: float) -> void:
	if not visible:
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player) or not (player is Node2D):
		return
	var player2d: Node2D = player as Node2D
	var pp: Vector2 = player2d.global_position
	# Fetch the enemy group ONCE this frame — reused by the auto-register loop
	# below and by _update_enemy_hp_bars(), instead of allocating the array twice.
	var enemies: Array = get_tree().get_nodes_in_group("enemy")

	# Camera sync.
	var aim: Vector2 = Vector2.RIGHT
	if player.has_method("get_aim_direction"):
		aim = player.get_aim_direction()
	# player_pos_3d is always where the wizard body is. cam_pos is where the
	# camera renders from — same as player in first-person, behind/above in
	# 3rd-person. Player light and shake reference still anchor to the
	# player's body so the torchlight follows the wizard, not the camera.
	var player_pos_3d := Vector3(pp.x / TILE_PX, 0.5, pp.y / TILE_PX)
	var aim_3d := Vector3(aim.x, 0.0, aim.y)
	if aim_3d.length() < 0.001:
		aim_3d = Vector3.FORWARD
	else:
		aim_3d = aim_3d.normalized()
	var cam_pos: Vector3
	var look_target: Vector3
	if _camera_mode == "third":
		# Desired camera spot is FOLLOW_DIST behind player along the aim axis.
		# Raycast against the wall grid so walls behind the player pull the
		# camera in instead of swallowing it. Height layered on after the
		# raycast since walls are uniform-height in this rig.
		var pp_tile := Vector2(player_pos_3d.x, player_pos_3d.z)
		var desired_tile := pp_tile - Vector2(aim_3d.x, aim_3d.z) * TP_FOLLOW_DIST
		var safe_tile: Vector2 = _raycast_to_grid(pp_tile, desired_tile)
		# Clamp to a sensible minimum so a flush-against-wall camera doesn't
		# pop directly on top of the player (which would re-trigger the
		# near-cull and hide the wizard).
		# No MIN_DIST rescale here — extending back along the wall normal
		# would push the camera INTO the wall again. Just use the raycast
		# result directly. If the wall pinches the camera right up against
		# the player, the existing < 0.55 near-cull will hide the wizard
		# Label3D so it doesn't engulf the view (effectively first-person
		# fallback in that pinch).
		cam_pos = Vector3(safe_tile.x, player_pos_3d.y + TP_HEIGHT, safe_tile.y)
		look_target = player_pos_3d + aim_3d * TP_LOOK_FORWARD
	else:
		cam_pos = player_pos_3d
		look_target = player_pos_3d + aim_3d
	# Camera shake — random per-frame offset that decays linearly over the
	# shake's duration. Tweens to zero so the rest of the frame uses the
	# clean cam_pos for look_at and the player light.
	var shake_offset := Vector3.ZERO
	if _shake_t > 0.0:
		_shake_t = maxf(0.0, _shake_t - delta)
		var amp: float = _shake_intensity * (_shake_t / maxf(_shake_total, 0.001))
		shake_offset = Vector3(randf_range(-amp, amp), 0.0, randf_range(-amp, amp))
	_camera.position = cam_pos + shake_offset
	_camera.look_at(look_target, Vector3.UP)
	# Mirror the entity camera so both viewports render from the same POV.
	# Both cameras share the same World3D — they just have different
	# cull_masks, so the env camera sees walls and the ent camera sees
	# entity Label3Ds.
	if _camera_ent != null and is_instance_valid(_camera_ent):
		_camera_ent.global_transform = _camera.global_transform
	_player_light.position = player_pos_3d
	_update_lighting(delta, pp)

	# Auto-register any enemy that's in the "enemy" group but missing from
	# _entities — about half the enemy scripts (Wizard, all 5 bosses, the
	# Chaser/Shooter/Sniper/Summoner/Tank/Archer family) extend CharacterBody2D
	# directly instead of EnemyBase, so they never self-register on _ready.
	# Without this, those enemies are invisible in FP even though HP bars +
	# damage still work, which is what produced the "healthbars moving toward
	# me with no sprite" report. The rig's live-glyph sync reads AsciiChar.text
	# each frame, so any placeholder glyph works at registration time.
	# Catching unregistered stragglers only needs to happen "soon", not every
	# frame — throttle the O(enemies) walk to 1/10 frames (still ~6×/sec).
	if _frame_counter % 10 == 0:
		for e: Node in enemies:
			if not is_instance_valid(e) or not (e is Node2D):
				continue
			if _entities.has(e.get_instance_id()):
				continue
			register_entity(e as Node2D, "D", Color(0.95, 0.28, 0.22))

	# Camera-forward, hoisted out of the entity loop — used by the frustum
	# early-out below. Computed once per frame since the camera transform is
	# finalized at this point (look_at above, ent-camera mirror at line 788).
	var cam_fwd: Vector3 = -_camera.global_transform.basis.z

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
		# entry["label"] is a Node3D parent for multi-line entities, or a
		# Label3D for single-line. Both expose .position / .visible so most
		# of this loop treats them uniformly. The per-line text writes at
		# the bottom of the loop branch on entry["is_multiline"].
		var lbl: Node3D = lbl_v as Node3D
		var is_multiline: bool = bool(entry.get("is_multiline", false))
		var is_floor_decal: bool = bool(entry.get("is_floor_decal", false))
		if body == player2d and _camera_mode != "third":
			# First-person: the camera IS the player; suppress the glyph.
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
		# Player grounding (3rd-person) — the shrunken wizard billboard is
		# centered at chest height, which leaves his robe floating above the
		# floor. Keep that raised height while LEVITATING (he's meant to hover),
		# but drop him when grounded so the bottom of the robe meets the floor.
		if body == player2d and _camera_mode == "third":
			ent_3d.y = 0.55 if (body.get("_is_levitating") == true) else 0.38
		# Near-cull so the PLAYER's own shots (fresh off the gun, right at
		# the camera) don't engulf the view. Enemy projectiles are NOT
		# culled — an incoming shot vanishing right before it hits read as
		# "invisible projectiles", so we keep those visible all the way in.
		if cam_pos.distance_to(ent_3d) < 0.55 and str(body.get("source")) == "player":
			lbl.visible = false
			continue
		# Distance cull — beyond 13 tiles, the entity is far enough into the
		# dark horizon that the torch can't reach it; skip occlusion + the
		# per-frame status/billboard work entirely. Matches the HP-bar cull
		# in _update_enemy_hp_bars so bars don't float over invisible enemies.
		if cam_pos.distance_to(ent_3d) > 13.0:
			lbl.visible = false
			continue
		# Frustum early-out — entities strictly behind the camera skip the
		# occlusion raycast, status-overlay scan, and per-row Label3D writes.
		# Common when the player spins to face a new direction.
		if (ent_3d - cam_pos).dot(cam_fwd) < 0.0:
			lbl.visible = false
			continue
		# Wall occlusion — throttled to once every 3 frames per entity,
		# staggered so the cost spreads evenly across frames.
		var cam_tile := Vector2(_camera.global_position.x, _camera.global_position.z)
		var ent_tile := Vector2(ent_3d.x, ent_3d.z)
		var is_occluded: bool = _occlusion_cache.get(key, false)
		if (_frame_counter + key) % 3 == 0:
			var ray_hit_e: Vector2 = _raycast_to_grid(cam_tile, ent_tile)
			is_occluded = ray_hit_e.distance_to(ent_tile) > 0.05
			_occlusion_cache[key] = is_occluded
		if is_occluded:
			lbl.visible = false
			continue
		lbl.visible = true
		lbl.position = ent_3d
		# Floor-decal entities lie flat (-PI/2 on X). If the body has a
		# travel direction, rotate around Y so the glyph points along it.
		if is_floor_decal:
			var ry: float = 0.0
			var dir_v: Variant = body.get("direction")
			if dir_v is Vector2:
				var d := dir_v as Vector2
				if d.length_squared() > 0.001:
					ry = -d.angle()
			if body.has_meta("fp_floor_rotation_offset"):
				ry += float(body.get_meta("fp_floor_rotation_offset"))
			lbl.rotation = Vector3(-PI / 2.0, ry, 0.0)
		# Manual camera-facing orientation for entities that need an
		# in-plane Z rotation that Godot's shader-billboard would wipe.
		# Used by the pierce projectile (")" rotated +PI/2 reads as ⌒).
		# fp_rotation_from_direction: Z rotation is derived from the body's
		# live direction vector each frame (fp_rotation_z acts as an offset),
		# so the glyph tip tracks the projectile's travel direction.
		# fp_spin_rate (rad/sec): adds a continuous time-driven rotation on
		# top of the static offset — fire projectile uses it for a clockwise
		# tumble. Negative = clockwise (screen space, +Z is camera-out).
		if body.has_meta("fp_rotation_z") or body.has_meta("fp_spin_rate"):
			var to_cam_e: Vector3 = cam_pos - lbl.position
			if to_cam_e.length() > 0.001:
				lbl.look_at(lbl.position - to_cam_e, Vector3.UP)
				var z_rot: float = float(body.get_meta("fp_rotation_z", 0.0))
				if body.get_meta("fp_rotation_from_direction", false):
					var dir_v2: Variant = body.get("direction")
					if dir_v2 is Vector2:
						var d2: Vector2 = dir_v2 as Vector2
						if d2.length_squared() > 0.001:
							z_rot = -d2.angle() + z_rot
				if body.has_meta("fp_spin_rate"):
					var spin_rate: float = float(body.get_meta("fp_spin_rate"))
					z_rot += spin_rate * (Time.get_ticks_msec() / 1000.0)
				lbl.rotate_object_local(Vector3(0, 0, 1), z_rot)
		# Live glyph + modulate from body's AsciiChar.
		var stored_glyph: String = entry["stored_glyph"]
		var stored_color: Color = entry["stored_color"]
		var kind: String = entry.get("kind", "body")
		var live_text: String = stored_glyph
		var live_modulate := Color(1, 1, 1, 1)
		var ascii_child: Node = body.get_node_or_null("AsciiChar")
		# Portal-style entities use "AsciiArt" as their label name; fall back
		# to that so their animation reaches FP without renaming the .tscn.
		if ascii_child == null:
			ascii_child = body.get_node_or_null("AsciiArt")
		if ascii_child != null and ascii_child is Label:
			var al: Label = ascii_child as Label
			# Live text sync — for body-kind entities (enemies animate
			# multi-frame), OR any projectile that opts in via fp_animate
			# (nova swaps + ↔ x). Static-glyph projectiles like pierce keep
			# their FP-specific stored_glyph instead of being clobbered by
			# the 2D AsciiChar.text.
			var allow_text_sync: bool = (kind == "body") or bool(body.get_meta("fp_animate", false))
			if allow_text_sync and al.text != "":
				var allow_multiline: bool = bool(body.get_meta("fp_multiline", false)) \
						or kind == "body"
				if allow_multiline:
					live_text = al.text
				else:
					var first_line: String = al.text.split("\n")[0]
					if first_line.strip_edges() != "":
						live_text = first_line
			live_modulate = al.modulate
		# Status overlay sync — read FrozenBlock / EnflameOverlay / ElectricBolt
		# siblings off the body so debuffs read in FP the same way they do in
		# top-down. Frozen tints the enemy ice-blue and spawns a persistent ice-cube
		# Label3D in _world3d (through the ASCII shader); burn and shock prepend
		# their glyph above the entity.
		var status_modulate := Color(1, 1, 1, 1)
		var has_status := false
		# Status overlays only exist on "body" entities (enemies/player) — skip
		# the sibling lookups entirely for projectiles, sparks, and floor decals.
		# Per-frame get_node_or_null (no cache) — caching the Label refs led
		# to "Trying to cast a freed object" errors when enemies despawn /
		# respawn overlays mid-frame. Lookups are cheap; the actual win below
		# is the no-debuff fast path that skips the Array build + join.
		var frozen_child: Label = (body.get_node_or_null("FrozenBlock") as Label) if kind == "body" else null
		var enflame_child: Label = null
		var electric_child: Label = null
		var poison_child: Label = null
		if frozen_child != null and frozen_child.text != "":
			# Enemy art stays unchanged -- just apply ice-blue tint.
			status_modulate = Color(0.72, 0.92, 1.0)
			has_status = true
			# Create or reposition the persistent crunched ice-cube Label3D in _world3d.
			if not _ice_cubes.has(key):
				var ice := Label3D.new()
				ice.text = ".========.\n|        |\n|        |\n|        |\n|        |\n|        |\n'========'"
				ice.font = MonoFont.get_font()
				ice.font_size = 64
				ice.outline_size = 0
				ice.pixel_size = 0.003
				ice.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				ice.no_depth_test = false
				ice.shaded = false
				ice.double_sided = true
				ice.modulate = Color(0.90, 0.97, 1.0, 0.85)
				ice.outline_modulate = Color(0, 0, 0, 1)
				ice.alpha_cut = Label3D.ALPHA_CUT_DISCARD
				_world3d.add_child(ice)
				_ice_cubes[key] = ice
			(_ice_cubes[key] as Label3D).position = ent_3d
		else:
			if _ice_cubes.has(key):
				if is_instance_valid(_ice_cubes[key]):
					(_ice_cubes[key] as Node).queue_free()
				_ice_cubes.erase(key)
			# Fast-path: if none of the overlays carry text right now, skip
			# the Array build + "\n".join entirely. Healthy enemies hit this
			# branch every frame, so this is the biggest per-frame win.
			if kind == "body":
				enflame_child  = body.get_node_or_null("EnflameOverlay") as Label
				electric_child = body.get_node_or_null("ElectricBolt") as Label
				poison_child   = body.get_node_or_null("PoisonOverlay") as Label
			var en_text: String = enflame_child.text if enflame_child != null else ""
			var el_text: String = electric_child.text if electric_child != null else ""
			var po_text: String = poison_child.text if poison_child != null else ""
			var el_visible: bool = (electric_child != null and electric_child.modulate.a > 0.0)
			if en_text != "" or po_text != "" or (el_text != "" and el_visible):
				var status_lines: Array[String] = []
				if el_text != "" and el_visible:
					status_lines.append(el_text)
				if en_text != "":
					status_lines.append(en_text)
				if po_text != "":
					status_lines.append(po_text)
				status_lines.append(live_text)
				live_text = "
".join(status_lines)
				has_status = true
				# Priority for the tint when multiple effects stack: burn >
				# shock > poison. Each picks the overlay's own modulate so
				# the tint matches the dominant status the player can read.
				if enflame_child != null:
					status_modulate = enflame_child.modulate
				elif electric_child != null:
					status_modulate = electric_child.modulate
				elif poison_child != null:
					status_modulate = poison_child.modulate
		var final_modulate: Color = status_modulate if has_status else stored_color * live_modulate
		var base_ps: float
		if body.has_meta("fp_pixel_size"):
			base_ps = float(body.get_meta("fp_pixel_size"))
		else:
			base_ps = _pixel_size_for(entry.get("kind", "body"))
		# Cache the newline split — most entities' glyph is identical frame to
		# frame, so this skips a per-entity allocation + parse every frame.
		var split_lines: Array
		if entry.has("_split_src") and entry["_split_src"] == live_text:
			split_lines = entry["_split_arr"] as Array
		else:
			split_lines = Array(live_text.split("\n"))
			entry["_split_src"] = live_text
			entry["_split_arr"] = split_lines
		if is_multiline:
			# Consolidated path — one Label3D with embedded \n. Native
			# multi-line text, 1 draw call regardless of row count, and
			# Label3D billboards itself so no manual camera-facing rotation
			# is needed. The whole legacy per-row block below is skipped.
			if bool(entry.get("is_consolidated", false)):
				var sl_consol: Label3D = lbl as Label3D
				sl_consol.text = live_text
				sl_consol.modulate = final_modulate
				var live_count_c: int = split_lines.size()
				var designed_rows_c: int = int(entry.get("registered_rows", live_count_c))
				sl_consol.pixel_size = base_ps / float(maxi(1, designed_rows_c))
				continue
			# Per-row Label3D rendering. Each child centers its own line
			# independently — no per-line drift from a shared multi-line
			# bbox. Dynamic resize: status overlays (ice block, burn/shock
			# stack) can grow the line count past the registered art.
			var live_lines_arr: Array = split_lines
			var row_labels: Array = entry.get("line_labels", [])
			# Per-row pixel_size = base / DESIGNED row count (the line count
			# the entity registered with). Using the live row count here
			# would shrink the whole sprite whenever a status overlay added
			# a line on top (frozen + burn + shock + poison stack pushes a
			# 5-row wizard to 8 rows, compressing the art mid-fight). With
			# the designed count, status overlays only extend the envelope
			# upward and the base art keeps its size.
			var designed_rows: int = int(entry.get("registered_rows", live_lines_arr.size()))
			var ps_now: float = base_ps / float(maxi(1, designed_rows))
			# Grow children if we have more lines than labels.
			while row_labels.size() < live_lines_arr.size():
				var new_row := Label3D.new()
				new_row.font = MonoFont.get_font()
				new_row.font_size = 64
				new_row.outline_size = (row_labels[0] as Label3D).outline_size if row_labels.size() > 0 else 12
				new_row.pixel_size = ps_now
				new_row.billboard = BaseMaterial3D.BILLBOARD_DISABLED if is_floor_decal else BaseMaterial3D.BILLBOARD_ENABLED
				new_row.no_depth_test = false
				new_row.shaded = false
				new_row.double_sided = true
				new_row.outline_modulate = Color(0, 0, 0, 1)
				new_row.alpha_cut = Label3D.ALPHA_CUT_DISCARD
				new_row.layers = LAYER_ENT
				lbl.add_child(new_row)
				row_labels.append(new_row)
			entry["line_labels"] = row_labels
			# Position + text + modulate per row. Hide leftover rows.
			var line_h: float = 64.0 * ps_now * ROW_SPACING
			var mid_row: float = float(live_lines_arr.size() - 1) * 0.5
			var x_offsets2: Array = []
			if body.has_meta("fp_line_x_offsets"):
				var xv2: Variant = body.get_meta("fp_line_x_offsets")
				if xv2 is Array:
					x_offsets2 = xv2
			const CHAR_ADVANCE_RATIO_2: float = 0.55
			var char_world2: float = 64.0 * ps_now * CHAR_ADVANCE_RATIO_2
			# Limb drift — each row is its own billboard, so an x offset
			# fixed in WORLD space parallax-swings relative to the body as
			# the camera orbits (the rows "float" loosely). Default OFF:
			# the offset is applied along the camera's horizontal RIGHT
			# vector so it always reads as a consistent screen-space shift
			# (rows stay locked to the body). Opt in via the `fp_limb_drift`
			# meta for the floaty effect.
			var drift_on: bool = GameState.fp_limb_drift
			var cam_right := _camera.global_transform.basis.x
			cam_right.y = 0.0
			cam_right = cam_right.normalized() if cam_right.length() > 0.001 else Vector3.RIGHT
			# When drift is OFF, render the whole multi-line entity as one rigid
			# plane: per-row billboarding is disabled below and the parent
			# Y-billboards toward the camera here, so the art stays solid with
			# no inter-row wobble. When ON, the parent stays unrotated and each
			# row billboards independently (the loose "drift" look).
			if not is_floor_decal:
				if drift_on:
					lbl.rotation = Vector3.ZERO
				else:
					var to_cam := _camera.global_position - lbl.global_position
					to_cam.y = 0.0
					if to_cam.length() > 0.001:
						lbl.rotation = Vector3(0.0, atan2(to_cam.x, to_cam.z), 0.0)
			else:
				# Re-apply flat rotation each frame so nothing can accidentally
				# reset a multi-line floor decal back to upright.
				lbl.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
			for i in row_labels.size():
				var row_lbl: Label3D = row_labels[i] as Label3D
				if i < live_lines_arr.size():
					row_lbl.visible = true
					row_lbl.text = (live_lines_arr[i] as String).strip_edges()
					row_lbl.modulate = final_modulate
					row_lbl.pixel_size = ps_now
					var row_x_off2: float = 0.0
					if i < x_offsets2.size():
						row_x_off2 = float(x_offsets2[i]) * char_world2
					var row_y: float = (mid_row - float(i)) * line_h
					if is_floor_decal:
						# Parent is rotated flat; keep rows in plain local
						# space (local Y → world Z spreads them across the
						# floor). cam_right logic assumes an unrotated parent.
						row_lbl.position = Vector3(row_x_off2, row_y, 0.0)
					elif drift_on:
						# Each row billboards on its own; the offset rides the
						# camera-right vector so it stays screen-aligned.
						row_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
						row_lbl.position = Vector3(cam_right.x * row_x_off2, row_y, cam_right.z * row_x_off2)
					else:
						# Rigid: rows fixed in the parent's local frame, which
						# the parent already rotated to face the camera.
						row_lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
						row_lbl.position = Vector3(row_x_off2, row_y, 0.0)
				else:
					row_lbl.visible = false
		else:
			# Single-line path — write directly to the Label3D.
			var sl: Label3D = lbl as Label3D
			sl.text = live_text
			sl.modulate = final_modulate
			var line_count: int = split_lines.size()
			# Also factor in the width of the widest row so that 5-char-wide
			# multi-row art doesn't render twice as wide as a single-char enemy.
			var max_col: int = 1
			for ln: String in split_lines:
				max_col = maxi(max_col, ln.strip_edges().length())
			var dim_scale: float = maxf(float(line_count), float(max_col))
			sl.pixel_size = base_ps / dim_scale
	for key in stale:
		var entry2: Dictionary = _entities[key]
		var lbl_v2: Variant = entry2["label"]
		if is_instance_valid(lbl_v2):
			(lbl_v2 as Node).queue_free()
		_entities.erase(key)
		_occlusion_cache.erase(key)
		if _ice_cubes.has(key):
			if is_instance_valid(_ice_cubes[key]):
				(_ice_cubes[key] as Node).queue_free()
			_ice_cubes.erase(key)

	_update_hitbox_mesh()

	# Melee swoosh decay — auto-hides the punch label after MELEE_LIFE so
	# the player doesn't see a stuck fist between strikes.
	if _melee_lbl != null and is_instance_valid(_melee_lbl):
		if _melee_timer > 0.0:
			_melee_timer -= delta
			if _melee_timer <= 0.0:
				_melee_lbl.visible = false
	# Lock pulse — refreshes the red modulate so the warning visibly
	# breathes while a turret is targeting the player.
	if _lock_label != null and is_instance_valid(_lock_label) and _lock_label.visible:
		var p: float = sin(Time.get_ticks_msec() * 0.018) * 0.5 + 0.5
		_lock_label.modulate = Color(1.0, 0.20 + p * 0.30, 0.20 + p * 0.30, 0.7 + p * 0.30)
	# Interact hint scan — find the closest registered entity within ~80
	# px (2.5 tiles) of the player whose children include a visible hint
	# Label (text starts with "[" or matches portal "DEFEAT BOSS" / "DEFEAT
	# WIZARD" gates). Surface that text on a centered FP CanvasLayer label.
	_frame_counter += 1
	_update_interact_hint(pp)
	# Enemy health bars — project enemy positions to screen and draw a
	# small bar above each one. Floor is occupied by hazards so bars sit
	# above the head.
	_update_enemy_hp_bars(enemies)
	# Debug name overlay (KEY_N). Reaps existing labels on toggle-off, so
	# turning the overlay off cleans up immediately without waiting for
	# each enemy to die.
	_update_enemy_names(enemies)
	# Floating damage text — re-projects each active text from its source
	# world position so the labels stay glued to the enemy when the
	# camera turns (was tweening screen-space, drifted off).
	# Updated every other frame — human eye can't tell at these timescales.
	if _frame_counter % 2 == 0:
		_update_floating_texts(delta)

# Beam wand — a single blue 3D tube (cylinder) from the muzzle to end_pos2d.
# Lives on LAYER_ENV so the ASCII post-shader converts it to glyphs (a solid
# beam reads cleaner than the old "=" billboard chain) and it occludes behind
# walls like the rest of the environment. Called every frame the beam fires;
# clear_beam() hides it on release.
func set_beam(start_pos2d: Vector2, end_pos2d: Vector2, color: Color) -> void:
	if not visible or _world3d == null or not is_instance_valid(_world3d):
		return
	# 0.22 matches player projectile fp_height so the beam appears to come
	# from the same waist-level muzzle as everything else.
	var start_3d := Vector3(start_pos2d.x / TILE_PX, 0.22, start_pos2d.y / TILE_PX)
	var end_3d   := Vector3(end_pos2d.x / TILE_PX, 0.22, end_pos2d.y / TILE_PX)
	# Bias the tube blue regardless of the wand's element tint.
	var tube_col: Color = color.lerp(Color(0.35, 0.65, 1.0), 0.6)
	if _beam_tube == null or not is_instance_valid(_beam_tube):
		_beam_tube = _build_beam_tube(0.08, tube_col)
	if not _orient_beam_tube(_beam_tube, start_3d, end_3d, tube_col, 0.6):
		clear_beam()
		return
	_beam_tube.visible = true
	_beam_active = true

# Creates a freshly-parented CylinderMesh instance for a beam tube.
# Shared by the player wand path (set_beam) and the enemy sweep path
# (set_enemy_beam). Caller owns the resulting node and is responsible for
# parenting it into _world3d on LAYER_ENV (so the ASCII post-shader picks
# it up as crunchy glyphs).
func _build_beam_tube(radius: float, color: Color) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 1.0
	cyl.radial_segments = 8
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	cyl.material = mat
	inst.mesh = cyl
	inst.layers = LAYER_ENV
	_world3d.add_child(inst)
	return inst

# Stretches `tube` along the (start_3d → end_3d) segment, with `skip_from_start`
# trimmed off the near end so the tube doesn't engulf the camera/muzzle.
# Returns false if the segment is too short to render (caller should hide
# the tube and bail). Updates the tube's albedo color so emitters that
# change color mid-beam (e.g. telegraph→sweep gradient, future) animate
# cleanly without rebuilding the mesh.
func _orient_beam_tube(tube: MeshInstance3D, start_3d: Vector3, end_3d: Vector3,
		color: Color, skip_from_start: float) -> bool:
	var dist: float = start_3d.distance_to(end_3d)
	if dist <= skip_from_start:
		return false
	var dir3d: Vector3 = (end_3d - start_3d) / dist
	var seg_len: float = dist - skip_from_start
	var mid: Vector3 = start_3d + dir3d * (skip_from_start + seg_len * 0.5)
	var cyl_mesh := tube.mesh as CylinderMesh
	if cyl_mesh != null:
		var m := cyl_mesh.material as StandardMaterial3D
		if m != null:
			m.albedo_color = color
	# Orient the cylinder's local +Y along the beam and stretch it to seg_len;
	# X/Z stay unit so the radius is unchanged.
	var up_ref: Vector3 = Vector3.UP if absf(dir3d.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var xv: Vector3 = up_ref.cross(dir3d).normalized()
	var zv: Vector3 = xv.cross(dir3d).normalized()
	tube.global_transform = Transform3D(Basis(xv, dir3d * seg_len, zv), mid)
	return true

func clear_beam() -> void:
	if not _beam_active:
		return
	if _beam_tube != null and is_instance_valid(_beam_tube):
		_beam_tube.visible = false
	for lbl in _beam_dots:
		if is_instance_valid(lbl):
			lbl.visible = false
	_beam_active = false

# Melee strike — flashes a fist glyph at hit_pos2d for MELEE_LIFE seconds.
# Re-uses a single pooled Label3D so successive punches don't accrete nodes.
func flash_melee(hit_pos2d: Vector2, color: Color) -> void:
	if not visible or _world3d == null or not is_instance_valid(_world3d):
		return
	if _melee_lbl == null or not is_instance_valid(_melee_lbl):
		_melee_lbl = Label3D.new()
		_melee_lbl.font = MonoFont.get_font()
		_melee_lbl.font_size = 64
		_melee_lbl.outline_size = 10
		_melee_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_melee_lbl.no_depth_test = false
		_melee_lbl.shaded = false
		_melee_lbl.double_sided = true
		_melee_lbl.outline_modulate = Color(0, 0, 0, 1)
		_melee_lbl.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		_world3d.add_child(_melee_lbl)
	_melee_lbl.text = "><"
	_melee_lbl.pixel_size = 0.018
	_melee_lbl.position = Vector3(hit_pos2d.x / TILE_PX, 0.35, hit_pos2d.y / TILE_PX)
	_melee_lbl.modulate = color
	_melee_lbl.visible = true
	_melee_timer = MELEE_LIFE

# Enemy beam mirror — places a chain of glyphs from emitter to end_pos in the
# 3D world. is_telegraph swaps the glyph to a faint "·" so the windup reads
# distinctly from the actual sweep. Each emitter has its own pooled label
# array so concurrent beam enemies don't fight over the same dots.
func set_enemy_beam(emitter: Node, start_pos2d: Vector2, end_pos2d: Vector2, color: Color, is_telegraph: bool = false, y: float = 0.45) -> void:
	if not visible or _world3d == null or not is_instance_valid(_world3d):
		return
	if not is_instance_valid(emitter):
		return
	var key := emitter.get_instance_id()
	var start_3d := Vector3(start_pos2d.x / TILE_PX, y, start_pos2d.y / TILE_PX)
	var end_3d   := Vector3(end_pos2d.x / TILE_PX, y, end_pos2d.y / TILE_PX)
	if is_telegraph:
		# Telegraph phase — dotted "·" pool. The fragmented look is the whole
		# point of the warning: easy to spot the line, easy to dodge across.
		# Hide any sweep tube that might still be parented from a prior cycle
		# (clean handoff if telegraph re-fires after a sweep).
		if _enemy_beam_tubes.has(key):
			var prev_tube: MeshInstance3D = _enemy_beam_tubes[key] as MeshInstance3D
			if is_instance_valid(prev_tube):
				prev_tube.visible = false
		var pool: Array = _enemy_beam_pools.get(key, []) as Array
		var dist := start_3d.distance_to(end_3d)
		var step := 0.35
		var count: int = maxi(0, int(dist / step))
		while pool.size() < count:
			var lbl := Label3D.new()
			lbl.text = "·"
			lbl.font = MonoFont.get_font()
			lbl.font_size = 48
			lbl.outline_size = 6
			lbl.pixel_size = 0.008
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.no_depth_test = false
			lbl.shaded = false
			lbl.double_sided = true
			lbl.outline_modulate = Color(0, 0, 0, 1)
			lbl.alpha_cut = Label3D.ALPHA_CUT_DISCARD
			_world3d.add_child(lbl)
			pool.append(lbl)
		var dir3d := Vector3.ZERO if dist <= 0.0 else (end_3d - start_3d) / dist
		for i in count:
			var lbl: Label3D = pool[i]
			lbl.text = "·"
			lbl.pixel_size = 0.008
			lbl.position = start_3d + dir3d * (float(i) * step + step * 0.5)
			lbl.modulate = color
			lbl.visible = true
		for i in range(count, pool.size()):
			(pool[i] as Label3D).visible = false
		_enemy_beam_pools[key] = pool
		return
	# Sweep phase — crunchy CylinderMesh tube, same visual language as the
	# player's beam wand (just in the emitter's hostile color, no blue lerp).
	# Hide the dotted telegraph pool so the warning cleanly hands off to the
	# damage visual.
	if _enemy_beam_pools.has(key):
		var dot_pool: Array = _enemy_beam_pools[key] as Array
		for lbl in dot_pool:
			if is_instance_valid(lbl):
				(lbl as Label3D).visible = false
	var tube: MeshInstance3D = _enemy_beam_tubes.get(key) as MeshInstance3D
	if tube == null or not is_instance_valid(tube):
		tube = _build_beam_tube(0.08, color)
		_enemy_beam_tubes[key] = tube
	# Skip 0.0 from start — the emitter is the enemy's position, not a
	# player muzzle; the player isn't standing on top of it, so no near-cull
	# needed and the tube can reach all the way back to the source.
	if not _orient_beam_tube(tube, start_3d, end_3d, color, 0.0):
		tube.visible = false
		return
	tube.visible = true

func clear_enemy_beam(emitter: Node) -> void:
	if not is_instance_valid(emitter):
		return
	var key := emitter.get_instance_id()
	if _enemy_beam_pools.has(key):
		var pool: Array = _enemy_beam_pools[key] as Array
		for lbl in pool:
			if is_instance_valid(lbl):
				(lbl as Node).queue_free()
		_enemy_beam_pools.erase(key)
	if _enemy_beam_tubes.has(key):
		var tube: MeshInstance3D = _enemy_beam_tubes[key] as MeshInstance3D
		if is_instance_valid(tube):
			tube.queue_free()
		_enemy_beam_tubes.erase(key)

# ── Shock zap line (per-projectile crackling line) ────────────────────────────
# Fire-and-forget: each tick the projectile calls this, we spawn a short
# Line2D inside _viewport that fades + queue_frees itself. No pool, no per-
# emitter storage to leak when projection fails or the projectile dies
# before its line cleans up. Caller throttles with _zap_skip.
func spawn_shock_zap(pos_2d: Vector2, dir_2d: Vector2, color: Color, lifetime: float = 0.12) -> void:
	if not visible or _viewport == null or not is_instance_valid(_viewport):
		return
	if _camera == null or not is_instance_valid(_camera):
		return
	var world_pos := Vector3(pos_2d.x / TILE_PX, 0.22, pos_2d.y / TILE_PX)
	if _camera.is_position_behind(world_pos):
		return
	# Guard against degenerate projection when the projectile is at (or
	# essentially at) the camera position — unproject_position blows up
	# because the camera-space z is near zero and the projection divides
	# by it, snapping the result to screen-center. That's what produced
	# "lightning artifacts stuck at screen middle going horizontally."
	var dist_to_cam: float = _camera.global_position.distance_to(world_pos)
	if dist_to_cam < 0.6:
		return
	var center: Vector2 = _camera.unproject_position(world_pos)
	# Project a forward point to get screen-space direction so the zag
	# orients along the projectile's flight.
	var fwd_world := world_pos + Vector3(dir_2d.x, 0.0, dir_2d.y) * 0.4
	var fwd_screen: Vector2 = center
	if not _camera.is_position_behind(fwd_world):
		fwd_screen = _camera.unproject_position(fwd_world)
	var screen_dir: Vector2 = (fwd_screen - center)
	if screen_dir.length() < 1.0:
		screen_dir = Vector2.RIGHT
	screen_dir = screen_dir.normalized()
	var perp: Vector2 = Vector2(-screen_dir.y, screen_dir.x)
	var line := Line2D.new()
	line.width = 1.5
	line.default_color = color
	line.antialiased = false
	line.joint_mode = Line2D.LINE_JOINT_SHARP
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	for i in 7:
		var t: float = float(i) / 6.0
		var px: float = -12.0 + 24.0 * t
		var pt: Vector2 = center + screen_dir * px
		if i > 0 and i < 6:
			pt += perp * randf_range(-3.0, 3.0)
		line.add_point(pt)
	_viewport.add_child(line)
	var tw := line.create_tween()
	tw.tween_property(line, "modulate:a", 0.0, lifetime)
	tw.tween_callback(line.queue_free)

# ── Transient effect spawners ────────────────────────────────────────────────
# Generic Label3D helper. Each spawned label tweens its modulate alpha to
# zero then frees itself, so callers never need to track them. Used as the
# atomic unit for the burst / ring / chain helpers below.
func _spawn_fx_label(pos: Vector3, text: String, color: Color, pixel_size: float,
		end_pos: Vector3, lifetime: float) -> void:
	if _world3d == null or not is_instance_valid(_world3d):
		return
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font = MonoFont.get_font()
	lbl.font_size = 48
	lbl.outline_size = 0
	lbl.pixel_size = pixel_size
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = false
	lbl.shaded = false
	lbl.double_sided = true
	lbl.modulate = color
	lbl.outline_modulate = Color(0, 0, 0, 1)
	lbl.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	lbl.position = pos
	_world3d.add_child(lbl)
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "position", end_pos, lifetime)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, lifetime)
	tw.tween_callback(lbl.queue_free)

# Scatter burst — N labels at pos_2d, optionally biased into a cone aimed
# along direction_2d (cone_angle = TAU means full circle). Each label drifts
# `spread` units outward over `lifetime` and fades.
func spawn_burst_2d(pos_2d: Vector2, glyph: String, color: Color, count: int,
		spread: float = 0.55, lifetime: float = 0.22,
		direction_2d: Vector2 = Vector2.ZERO, cone_angle: float = TAU,
		pixel_size: float = 0.010, y: float = 0.40) -> void:
	if not visible:
		return
	var start_3d := Vector3(pos_2d.x / TILE_PX, y, pos_2d.y / TILE_PX)
	var base_angle: float = direction_2d.angle() if direction_2d.length() > 0.0 else 0.0
	for i in count:
		var ang: float
		if cone_angle >= TAU - 0.001:
			ang = (TAU / float(count)) * float(i) + randf_range(-0.2, 0.2)
		else:
			var t := (float(i) + 0.5) / float(count)
			ang = base_angle + (t - 0.5) * cone_angle + randf_range(-0.1, 0.1)
		var dist := randf_range(spread * 0.55, spread)
		var end_3d := start_3d + Vector3(cos(ang), 0.0, sin(ang)) * dist
		_spawn_fx_label(start_3d, glyph, color, pixel_size, end_3d, lifetime)

# Forward streak — `count` short labels striking out along direction_2d.
# Used by pierce / shotgun where the spread is collimated rather than radial.
func spawn_streak_2d(pos_2d: Vector2, direction_2d: Vector2, glyph: String,
		color: Color, count: int, length: float = 0.7, lifetime: float = 0.18,
		pixel_size: float = 0.010, y: float = 0.40) -> void:
	if not visible:
		return
	if direction_2d.length() == 0.0:
		direction_2d = Vector2.RIGHT
	var dir_n := direction_2d.normalized()
	var perp := dir_n.rotated(PI * 0.5)
	var start_3d := Vector3(pos_2d.x / TILE_PX, y, pos_2d.y / TILE_PX)
	for i in count:
		var lateral := randf_range(-0.18, 0.18)
		var origin := start_3d + Vector3(perp.x * lateral, 0.0, perp.y * lateral)
		var travel := length * randf_range(0.70, 1.0)
		var end_3d := origin + Vector3(dir_n.x * travel, 0.0, dir_n.y * travel)
		_spawn_fx_label(origin, glyph, color, pixel_size, end_3d, lifetime)

# Expanding ring — places `segments` labels in a circle and tweens their
# radius outward + fades them. The labels themselves don't rotate (they're
# billboards) so the visual reads as a shockwave outline.
func spawn_ring_2d(pos_2d: Vector2, glyph: String, color: Color,
		start_radius: float = 0.25, end_radius: float = 1.4,
		segments: int = 16, lifetime: float = 0.30,
		pixel_size: float = 0.009, y: float = 0.35) -> void:
	if not visible:
		return
	var center := Vector3(pos_2d.x / TILE_PX, y, pos_2d.y / TILE_PX)
	for i in segments:
		var ang := (TAU / float(segments)) * float(i)
		var dir3d := Vector3(cos(ang), 0.0, sin(ang))
		var start_pos := center + dir3d * start_radius
		var end_pos := center + dir3d * end_radius
		_spawn_fx_label(start_pos, glyph, color, pixel_size, end_pos, lifetime)

# Chain arc — jagged chain of Label3D glyphs in 3D world space between two
# 2D positions. Zigzags through 4 intermediate waypoints with perpendicular
# and vertical jitter, placing one glyph per waypoint and one at each
# segment midpoint. Ends with burst impacts at both endpoints.
func spawn_chain_arc_2d(from_2d: Vector2, to_2d: Vector2, color: Color,
		_count_unused: int = 0, lifetime: float = 0.35, _jitter_unused: float = 0.0,
		_pixel_unused: float = 0.0, y: float = 0.45, _glyph_unused: String = "") -> void:
	if not visible or _world3d == null or not is_instance_valid(_world3d):
		return
	var from_3d := Vector3(from_2d.x / TILE_PX, y, from_2d.y / TILE_PX)
	var to_3d   := Vector3(to_2d.x   / TILE_PX, y, to_2d.y   / TILE_PX)
	var delta   := to_3d - from_3d
	if delta.length() <= 0.01:
		return
	var perp := delta.cross(Vector3.UP)
	perp = perp.normalized() if perp.length() > 0.0 else Vector3(1.0, 0.0, 0.0)

	# Build zigzag waypoints alternating left/right of the straight path.
	const N_SEGS: int = 4
	var waypoints: Array[Vector3] = [from_3d]
	var sign: float = 1.0 if randi() % 2 == 0 else -1.0
	for i in range(1, N_SEGS):
		var t: float = clampf(float(i) / float(N_SEGS) + randf_range(-0.04, 0.04), 0.05, 0.95)
		var pt: Vector3 = from_3d.lerp(to_3d, t)
		pt += perp * (sign * randf_range(0.18, 0.38))
		pt.y = clampf(pt.y + randf_range(-0.12, 0.22), 0.10, 1.4)
		sign = -sign
		waypoints.append(pt)
	waypoints.append(to_3d)

	# Place fading Label3Ds at each waypoint + each segment midpoint.
	var glyphs := ["~", "Z", "z", "~", "Z", "~"]
	const PS: float = 0.013
	for i in range(waypoints.size() - 1):
		var a: Vector3 = waypoints[i]
		var b: Vector3 = waypoints[i + 1]
		_spawn_fx_label(a, glyphs[i % glyphs.size()],           color, PS, a, lifetime)
		_spawn_fx_label(a.lerp(b, 0.5), glyphs[(i + 2) % glyphs.size()], color, PS,
				a.lerp(b, 0.5), lifetime)
	_spawn_fx_label(waypoints[waypoints.size() - 1], "Z", color, PS,
			waypoints[waypoints.size() - 1], lifetime)

	# Burst impact at the origin endpoint only — * removed per design.
	spawn_burst_2d(from_2d, "~", color, 4, 0.25, lifetime * 0.65,
			Vector2.ZERO, TAU, 0.010, y)

# ── Per-emitter persistent warning ring ──────────────────────────────────────
# Mirrors the grenadier's 2D Polygon2D + Line2D danger zone. Each emitter
# owns a pooled circle of Label3D "o" glyphs that stays alive until cleared.
# `intensity` (0..1) ramps the modulate alpha so callers can pulse the ring
# during their countdown the way the 2D version does.
func set_warning_ring(emitter: Node, pos_2d: Vector2, radius_world: float,
		color: Color, intensity: float = 1.0, segments: int = 18,
		glyph: String = "o", y: float = 0.20) -> void:
	if not visible or _world3d == null or not is_instance_valid(_world3d):
		return
	if not is_instance_valid(emitter):
		return
	var key := emitter.get_instance_id()
	var pool: Array = _enemy_warning_pools.get(key, []) as Array
	while pool.size() < segments:
		var lbl := Label3D.new()
		lbl.text = glyph
		lbl.font = MonoFont.get_font()
		lbl.font_size = 48
		lbl.outline_size = 6
		lbl.pixel_size = 0.011
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = false
		lbl.shaded = false
		lbl.double_sided = true
		lbl.outline_modulate = Color(0, 0, 0, 1)
		lbl.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		_world3d.add_child(lbl)
		pool.append(lbl)
	var center := Vector3(pos_2d.x / TILE_PX, y, pos_2d.y / TILE_PX)
	var tint := Color(color.r, color.g, color.b, color.a * clampf(intensity, 0.0, 1.0))
	for i in segments:
		var ang := (TAU / float(segments)) * float(i)
		var lbl: Label3D = pool[i]
		lbl.text = glyph
		lbl.position = center + Vector3(cos(ang) * radius_world, 0.0, sin(ang) * radius_world)
		lbl.modulate = tint
		lbl.visible = true
	# Hide any extras from a previous larger ring.
	for i in range(segments, pool.size()):
		(pool[i] as Label3D).visible = false
	_enemy_warning_pools[key] = pool

func clear_warning_ring(emitter: Node) -> void:
	if not is_instance_valid(emitter):
		return
	var key := emitter.get_instance_id()
	if not _enemy_warning_pools.has(key):
		return
	var pool: Array = _enemy_warning_pools[key] as Array
	for lbl in pool:
		if is_instance_valid(lbl):
			(lbl as Node).queue_free()
	_enemy_warning_pools.erase(key)

# ── Target-lock screen warning ───────────────────────────────────────────────
# Multiple emitters can lock concurrently — we just need to know if ANY do.
# Renders a pulsing "[ LOCK ]" label on the FP CanvasLayer (not in the 3D
# world) so it's always visible regardless of where the turret is. The 2D
# game shows the lock square ON the player; in FP the player IS the camera
# so a screen-space warning reads better.
func set_target_lock(emitter: Node, on: bool) -> void:
	if not is_instance_valid(emitter):
		return
	var key := emitter.get_instance_id()
	if on:
		_lock_emitters[key] = true
	else:
		_lock_emitters.erase(key)
	_refresh_lock_label()

func _refresh_lock_label() -> void:
	if _lock_emitters.is_empty():
		if _lock_label != null and is_instance_valid(_lock_label):
			_lock_label.visible = false
		return
	if _lock_label == null or not is_instance_valid(_lock_label):
		_lock_label = Label.new()
		_lock_label.text = "[ LOCK ]"
		_lock_label.add_theme_font_override("font", MonoFont.get_font())
		_lock_label.add_theme_font_size_override("font_size", 22)
		_lock_label.add_theme_color_override("font_color", Color(1.0, 0.20, 0.20))
		_lock_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		_lock_label.add_theme_constant_override("outline_size", 3)
		_lock_label.anchor_left = 0.5
		_lock_label.anchor_right = 0.5
		_lock_label.anchor_top = 0.5
		_lock_label.anchor_bottom = 0.5
		_lock_label.offset_left = -60
		_lock_label.offset_right = 60
		_lock_label.offset_top = -90
		_lock_label.offset_bottom = -60
		_lock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_lock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_lock_label)
	_lock_label.visible = true

# Place a Label3D above each damaged enemy's head with a 10-cell bar made
# of = (filled) and - (empty) chars. Lives on LAYER_ENT so it renders
# through camera_ent (no shader), staying crisp like the rest of the
# entity ASCII art. Wall occlusion via raycast (camera_ent has no walls
# to provide depth-based occlusion).
const _HP_BAR_CELLS: int = 10
func _update_enemy_hp_bars(enemies: Array) -> void:
	# HP bars live in _ent_world3d (entity viewport, no shader) alongside
	# the entity Label3Ds so they read crisp like the enemy art.
	if _ent_world3d == null or not is_instance_valid(_ent_world3d):
		return
	if _camera == null or not is_instance_valid(_camera):
		return
	var alive_keys: Dictionary = {}
	for e: Node in enemies:
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		var enemy_2d: Node2D = e as Node2D
		var max_hp_v: Variant = enemy_2d.get("max_health")
		var hp_v: Variant = enemy_2d.get("health")
		if not (max_hp_v is int) or not (hp_v is int) or int(max_hp_v) <= 0:
			continue
		var ratio: float = clampf(float(hp_v) / float(max_hp_v), 0.0, 1.0)
		if ratio >= 0.999:
			continue
		var filled: int = clampi(int(round(float(_HP_BAR_CELLS) * ratio)), 0, _HP_BAR_CELLS)
		var key := enemy_2d.get_instance_id()
		alive_keys[key] = true
		var lbl: Label3D = _hp_bars.get(key) as Label3D
		if lbl == null or not is_instance_valid(lbl):
			lbl = Label3D.new()
			lbl.font = MonoFont.get_font()
			lbl.font_size = 64
			lbl.outline_size = 8
			lbl.pixel_size = 0.005
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.no_depth_test = false
			lbl.shaded = false
			lbl.double_sided = true
			lbl.outline_modulate = Color(0, 0, 0, 1)
			lbl.alpha_cut = Label3D.ALPHA_CUT_DISCARD
			_ent_world3d.add_child(lbl)
			_hp_bars[key] = lbl
		# Position above the entity. Wall occlusion via throttled raycast
		# (1/3 of bars per frame, staggered by instance id).
		var anchor_pos := Vector3(
			enemy_2d.global_position.x / TILE_PX,
			1.05,
			enemy_2d.global_position.y / TILE_PX)
		# Distance / behind-camera cull — keep HP bars from floating in the
		# dark horizon past where the enemy itself is visible. 13 tiles in
		# normal-lit rooms (covers most engagement ranges); tightens to ~6
		# in DARK / FLICKER rooms since the torch can't illuminate that far
		# in pitch-black sectors and the bare HP line would read as "lonely
		# green stripe in the void".
		var hp_cull_dist: float = 13.0
		if _cur_room_idx >= 0 and _cur_room_idx < _light_levels.size():
			if int(_light_levels[_cur_room_idx]) != 0:
				hp_cull_dist = 6.0
		var cam_p: Vector3 = _camera.global_position
		if cam_p.distance_to(anchor_pos) > hp_cull_dist:
			lbl.visible = false
			continue
		var cam_fwd_hp: Vector3 = -_camera.global_transform.basis.z
		if (anchor_pos - cam_p).dot(cam_fwd_hp) < 0.0:
			lbl.visible = false
			continue
		var is_hp_occluded: bool = _occlusion_cache.get(key, false)
		if (_frame_counter + key) % 3 == 0:
			var cam_tile_hp := Vector2(_camera.global_position.x, _camera.global_position.z)
			var ent_tile_hp := Vector2(anchor_pos.x, anchor_pos.z)
			var ray_hp: Vector2 = _raycast_to_grid(cam_tile_hp, ent_tile_hp)
			is_hp_occluded = ray_hp.distance_to(ent_tile_hp) > 0.05
			_occlusion_cache[key] = is_hp_occluded
		if is_hp_occluded:
			lbl.visible = false
			continue
		lbl.visible = true
		# Only rebuild the bar string when the filled-cell count actually
		# changes — avoids a "=".repeat()/"-".repeat() alloc every frame per
		# damaged enemy.
		if _hp_bar_fill.get(key, -1) != filled:
			lbl.text = "=".repeat(filled) + "-".repeat(_HP_BAR_CELLS - filled)
			_hp_bar_fill[key] = filled
		lbl.position = anchor_pos
		# Modulate cache — most damaged enemies sit in the same color bucket
		# for many frames, so only assign Color when the bucket flips.
		var color_bucket: int = 0 if ratio > 0.6 else (1 if ratio > 0.3 else 2)
		if _hp_bar_color.get(key, -1) != color_bucket:
			if color_bucket == 0:
				lbl.modulate = Color(0.30, 1.0, 0.30)
			elif color_bucket == 1:
				lbl.modulate = Color(1.0, 0.85, 0.20)
			else:
				lbl.modulate = Color(1.0, 0.30, 0.20)
			_hp_bar_color[key] = color_bucket
	# Reap stale (dead) bars.
	for key in _hp_bars.keys():
		if not alive_keys.has(key):
			var stale_lbl: Label3D = _hp_bars[key] as Label3D
			if is_instance_valid(stale_lbl):
				stale_lbl.queue_free()
			_hp_bars.erase(key)
			_hp_bar_fill.erase(key)
			_hp_bar_color.erase(key)

# Debug overlay (KEY_N) — float each enemy's script-derived name above its
# head. Reads the script's filename (e.g. "EnemyChaser") so the labels stay
# accurate as enemies are added without anyone maintaining a name table.
# When the toggle is OFF we proactively reap any leftover labels instead of
# waiting for the parent enemy to die.
func _update_enemy_names(enemies: Array) -> void:
	if _ent_world3d == null or not is_instance_valid(_ent_world3d):
		return
	if not GameState.show_enemy_names:
		if not _name_labels.is_empty():
			for key in _name_labels.keys():
				var dead_lbl: Label3D = _name_labels[key] as Label3D
				if is_instance_valid(dead_lbl):
					dead_lbl.queue_free()
			_name_labels.clear()
		return
	var alive_keys: Dictionary = {}
	for e: Node in enemies:
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		var enemy_2d: Node2D = e as Node2D
		var key := enemy_2d.get_instance_id()
		alive_keys[key] = true
		var lbl: Label3D = _name_labels.get(key) as Label3D
		if lbl == null or not is_instance_valid(lbl):
			lbl = Label3D.new()
			lbl.font = MonoFont.get_font()
			lbl.font_size = 64
			lbl.outline_size = 8
			lbl.pixel_size = 0.004
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.no_depth_test = false
			lbl.shaded = false
			lbl.double_sided = true
			lbl.modulate = Color(0.65, 1.0, 1.0)
			lbl.outline_modulate = Color(0, 0, 0, 1)
			lbl.alpha_cut = Label3D.ALPHA_CUT_DISCARD
			_ent_world3d.add_child(lbl)
			_name_labels[key] = lbl
			# Derive a stable name from the script filename — "EnemyChaser.gd"
			# → "EnemyChaser". Falls back to Node.name if the enemy has no
			# script attached (unlikely but safe).
			var nm: String = enemy_2d.name
			var scr: Script = enemy_2d.get_script() as Script
			if scr != null:
				var path: String = scr.resource_path
				if path != "":
					nm = path.get_file().get_basename()
			lbl.text = nm
		# Position slightly above the HP bar slot (1.05) so the two don't fight.
		lbl.position = Vector3(
			enemy_2d.global_position.x / TILE_PX,
			1.25,
			enemy_2d.global_position.y / TILE_PX)
	# Reap labels for enemies that just died.
	for key in _name_labels.keys():
		if not alive_keys.has(key):
			var stale_lbl: Label3D = _name_labels[key] as Label3D
			if is_instance_valid(stale_lbl):
				stale_lbl.queue_free()
			_name_labels.erase(key)

# Pulls the best "[E] …" hint off any nearby registered interactable and
# floats it on the FP CanvasLayer. Most interactables already toggle their
# own 2D Label.visible on body_entered/exited; we just mirror it here.
func _update_interact_hint(player_pos_2d: Vector2) -> void:
	var best_text: String = ""
	var best_dist_sq: float = 80.0 * 80.0   # ~2.5 tiles
	for key in _entities.keys():
		var entry: Dictionary = _entities[key]
		var body_v: Variant = entry["body"]
		if not is_instance_valid(body_v) or not (body_v is Node2D):
			continue
		var body: Node2D = body_v as Node2D
		var d_sq := player_pos_2d.distance_squared_to(body.global_position)
		if d_sq > best_dist_sq:
			continue
		var hint_text := _scan_hint_text(body)
		if hint_text == "":
			continue
		best_dist_sq = d_sq
		best_text = hint_text
	if best_text == "":
		if _interact_label != null and is_instance_valid(_interact_label):
			_interact_label.visible = false
		return
	if _interact_label == null or not is_instance_valid(_interact_label):
		_interact_label = Label.new()
		_interact_label.add_theme_font_override("font", MonoFont.get_font())
		_interact_label.add_theme_font_size_override("font_size", 18)
		_interact_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
		_interact_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		_interact_label.add_theme_constant_override("outline_size", 3)
		_interact_label.anchor_left = 0.5
		_interact_label.anchor_right = 0.5
		_interact_label.anchor_top = 0.5
		_interact_label.anchor_bottom = 0.5
		_interact_label.offset_left = -200
		_interact_label.offset_right = 200
		_interact_label.offset_top = 80
		_interact_label.offset_bottom = 110
		_interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_interact_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_interact_label)
	_interact_label.text = best_text
	_interact_label.visible = true

# Returns the first interact-hint-style text found among `body`'s children.
# Heuristic: visible Label, name not in {AsciiChar, AsciiArt, Visual} (those
# are body art), and text starts with "[" or matches the portal-gate
# strings ("DEFEAT BOSS" / "DEFEAT WIZARD") so portals' lock-state messages
# show too. Returns "" when nothing qualifies.
func _scan_hint_text(body: Node) -> String:
	for c in body.get_children():
		if not (c is Label):
			continue
		var lbl: Label = c as Label
		if not lbl.visible:
			continue
		var nm := lbl.name
		if nm == "AsciiChar" or nm == "AsciiArt" or nm == "Visual":
			continue
		var t: String = lbl.text
		if t == "":
			continue
		if t.begins_with("[") or t.begins_with("DEFEAT"):
			return t
	return ""

# Floating damage / status text — rendered as a 2D Label on the FP CanvasLayer
# (bypassing the ASCII post-shader) so the text stays sharp + legible at
# any distance. Anchored to the source WORLD position each frame (not
# tweened in screen space) so the text stays glued to the enemy when the
# player turns the camera.
func spawn_floating_text(pos_2d: Vector2, text: String, color: Color,
		lifetime: float = 0.85, y: float = 1.2) -> void:
	if not visible or _camera == null or not is_instance_valid(_camera):
		return
	var world_pos := Vector3(pos_2d.x / TILE_PX, y, pos_2d.y / TILE_PX)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", MonoFont.get_font())
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size = Vector2(160, 28)
	lbl.z_index = 7
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	# Random horizontal nudge so stacked hits don't overlap exactly.
	var x_jitter: float = randf_range(-12.0, 12.0)
	_floating_texts.append({
		"label": lbl,
		"world_pos": world_pos,
		"age": 0.0,
		"lifetime": lifetime,
		"x_offset": x_jitter,
		"color": color,
	})

# Per-frame updater for floating combat text — re-projects each label's
# anchor world position to screen space, applies the screen-space upward
# drift + alpha fade, removes when expired. Called from _process.
func _update_floating_texts(delta: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var i := _floating_texts.size() - 1
	while i >= 0:
		var entry: Dictionary = _floating_texts[i]
		var lbl: Label = entry["label"] as Label
		if not is_instance_valid(lbl):
			_floating_texts.remove_at(i)
			i -= 1
			continue
		var age: float = float(entry["age"]) + delta
		var lifetime: float = float(entry["lifetime"])
		if age >= lifetime:
			lbl.queue_free()
			_floating_texts.remove_at(i)
			i -= 1
			continue
		entry["age"] = age
		var world_pos: Vector3 = entry["world_pos"] as Vector3
		if _camera.is_position_behind(world_pos):
			lbl.visible = false
			i -= 1
			continue
		# Scale font size by distance so close hits read prominent and
		# far hits don't crowd. Done each frame so it tracks zoom changes.
		var d: float = _camera.global_position.distance_to(world_pos)
		var font_size: int = clampi(int(round(28.0 - d * 1.8)), 14, 28)
		lbl.add_theme_font_size_override("font_size", font_size)
		var screen_pos: Vector2 = _camera.unproject_position(world_pos)
		# Drift upward in SCREEN space (60 px over the lifetime) so the
		# text floats off the head regardless of camera angle.
		var drift_y: float = -60.0 * (age / lifetime)
		lbl.position = screen_pos + Vector2(float(entry["x_offset"]) - 80.0, drift_y - 14.0)
		var fade: float = 1.0 - (age / lifetime)
		var c: Color = entry["color"] as Color
		lbl.modulate = Color(c.r, c.g, c.b, fade)
		lbl.visible = true
		i -= 1

# Trigger a camera shake — `intensity` is in world units (one tile = 1.0).
# Caller passes the same duration the 2D camera_shake uses; the rig converts
# its 2D-pixel amplitude into world units by dividing by TILE_PX.
func shake(duration: float, intensity_px: float) -> void:
	# Most recent shake wins if it's bigger — same "don't compound" rule
	# Player.camera_shake uses on the 2D Camera2D.
	var new_amp: float = intensity_px / TILE_PX
	if _shake_t > 0.0 and _shake_intensity * (_shake_t / maxf(_shake_total, 0.001)) > new_amp:
		return
	_shake_t = duration
	_shake_total = duration
	_shake_intensity = new_amp

# ── Hitbox debug wireframes ───────────────────────────────────────────────────

func _update_hitbox_mesh() -> void:
	_hitbox_mesh.clear_surfaces()
	if not GameState.show_hitboxes or _entities.is_empty():
		return
	_hitbox_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for entry in _entities.values():
		var body: Node2D = entry["body"]
		if not is_instance_valid(body):
			continue
		var color := _hitbox_color_for(body)
		if body.is_in_group("fire_patch") and "_radius" in body:
			_draw_fire_patch_ring(body, color)
			continue
		for child in body.get_children():
			if child is CollisionShape2D:
				_draw_hitbox_shape(child as CollisionShape2D, color)
	_hitbox_mesh.surface_end()

func _hitbox_color_for(body: Node2D) -> Color:
	if body.is_in_group("player"):     return Color(0.2, 1.0, 0.3)
	if body.is_in_group("enemy"):      return Color(1.0, 0.25, 0.25)
	if body.is_in_group("fire_patch"): return Color(1.0, 0.70, 0.05)
	if body is Area2D:                 return Color(1.0, 0.65, 0.1)
	return Color(0.5, 0.85, 1.0)

func _draw_hitbox_shape(cs: CollisionShape2D, color: Color) -> void:
	var shape := cs.shape
	if shape == null or cs.disabled:
		return
	var cx  := cs.global_position.x / TILE_PX
	var cz  := cs.global_position.y / TILE_PX
	var rot := cs.global_rotation
	const Y0 := 0.05
	const Y1 := 0.95
	_hitbox_mesh.surface_set_color(color)
	if shape is RectangleShape2D:
		var h := (shape as RectangleShape2D).size * 0.5 / TILE_PX
		var corners: Array[Vector2] = [
			Vector2(-h.x, -h.y).rotated(rot),
			Vector2( h.x, -h.y).rotated(rot),
			Vector2( h.x,  h.y).rotated(rot),
			Vector2(-h.x,  h.y).rotated(rot),
		]
		for i in 4:
			var a := corners[i]
			var b := corners[(i + 1) % 4]
			# bottom edge
			_hitbox_mesh.surface_add_vertex(Vector3(cx + a.x, Y0, cz + a.y))
			_hitbox_mesh.surface_add_vertex(Vector3(cx + b.x, Y0, cz + b.y))
			# top edge
			_hitbox_mesh.surface_add_vertex(Vector3(cx + a.x, Y1, cz + a.y))
			_hitbox_mesh.surface_add_vertex(Vector3(cx + b.x, Y1, cz + b.y))
			# vertical pillar
			_hitbox_mesh.surface_add_vertex(Vector3(cx + a.x, Y0, cz + a.y))
			_hitbox_mesh.surface_add_vertex(Vector3(cx + a.x, Y1, cz + a.y))
	elif shape is CircleShape2D:
		var r := (shape as CircleShape2D).radius / TILE_PX
		const N := 16
		for i in N:
			var a0 := TAU * float(i)       / N
			var a1 := TAU * float(i + 1)   / N
			var p0 := Vector2(cos(a0), sin(a0)) * r
			var p1 := Vector2(cos(a1), sin(a1)) * r
			# bottom ring
			_hitbox_mesh.surface_add_vertex(Vector3(cx + p0.x, Y0, cz + p0.y))
			_hitbox_mesh.surface_add_vertex(Vector3(cx + p1.x, Y0, cz + p1.y))
			# top ring
			_hitbox_mesh.surface_add_vertex(Vector3(cx + p0.x, Y1, cz + p0.y))
			_hitbox_mesh.surface_add_vertex(Vector3(cx + p1.x, Y1, cz + p1.y))
		# 4 vertical pillars at cardinal points
		for i in [0, 4, 8, 12]:
			var a  := TAU * float(i) / N
			var px := cx + cos(a) * r
			var pz := cz + sin(a) * r
			_hitbox_mesh.surface_add_vertex(Vector3(px, Y0, pz))
			_hitbox_mesh.surface_add_vertex(Vector3(px, Y1, pz))

func _draw_fire_patch_ring(body: Node2D, color: Color) -> void:
	var cx := body.global_position.x / TILE_PX
	var cz := body.global_position.y / TILE_PX
	var r  := float(body.get("_radius")) / TILE_PX
	const N    := 24
	const Y_FL := 0.05
	_hitbox_mesh.surface_set_color(color)
	for i in N:
		var a0 := TAU * float(i)       / N
		var a1 := TAU * float(i + 1)   / N
		var p0 := Vector2(cos(a0), sin(a0)) * r
		var p1 := Vector2(cos(a1), sin(a1)) * r
		_hitbox_mesh.surface_add_vertex(Vector3(cx + p0.x, Y_FL, cz + p0.y))
		_hitbox_mesh.surface_add_vertex(Vector3(cx + p1.x, Y_FL, cz + p1.y))
