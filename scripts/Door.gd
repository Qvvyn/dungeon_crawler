extends Node2D

# Auto-opening door spanning a 3-wide corridor cross-section. As the player
# approaches, the wall section sinks into the floor; it rises back after they
# pass. First concrete use of the FP rig's animated wall-segment primitive
# (see DOOM_DESIGN.md). Collision blocks while closed, clears while open.
#
# Set before add_child:
#   cover_tiles    Array[Vector2i] — the grid tiles the door occupies (the
#                  corridor cross-section, perpendicular to travel)
#   corridor_axis  0 = E-W corridor (door span is vertical / along Y)
#                  1 = N-S corridor (door span is horizontal / along X)

const TILE: int = 32
const OPEN_SPEED := 3.5    # open/close lerp rate (units of open-amount per sec)

var cover_tiles: Array[Vector2i] = []
var corridor_axis: int = 0
var remote_only: bool = false   # true = no auto proximity open; only open()/close()
var start_open: bool = false    # spawn already open (e.g. a seal that closes later)

var _open_amount: float = 0.0   # 0 = closed, 1 = fully open
var _open_target: float = 0.0
var _seg_ids: Array[int] = []
var _segments_built: bool = false

var _body: StaticBody2D = null
var _col_shape: CollisionShape2D = null
var _trigger: Area2D = null
var _glyphs: Array[Label] = []   # top-down 2D visual (one "+" per covered tile)

static var _shared_font: Font = null

func _ready() -> void:
	add_to_group("door")
	if _shared_font == null:
		_shared_font = MonoFont.get_font()
	# Center of the covered tiles (in pixels) becomes our origin reference.
	# We place the node at the cover-tiles centroid via World; collision +
	# trigger are built in LOCAL space around that origin.
	var span_perp: float = float(cover_tiles.size()) * float(TILE)   # full corridor width
	var depth: float = float(TILE)                                   # 1 tile along travel

	# --- Blocking collision (toggled by open state) ---
	_body = StaticBody2D.new()
	_body.collision_layer = 1   # walls live on layer 1 (player mask hits it)
	_body.collision_mask = 0
	_col_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	if corridor_axis == 0:
		# E-W corridor: door spans vertically (Y), thin along X.
		rect.size = Vector2(depth, span_perp)
	else:
		rect.size = Vector2(span_perp, depth)
	_col_shape.shape = rect
	_body.add_child(_col_shape)
	add_child(_body)

	# --- Player proximity trigger (reaches ~1.5 tiles each side along travel) ---
	_trigger = Area2D.new()
	_trigger.collision_layer = 0
	_trigger.collision_mask = 1   # detect the player body
	var trig_shape := CollisionShape2D.new()
	var trig_rect := RectangleShape2D.new()
	var reach: float = float(TILE) * 3.0   # total depth of detection along travel
	if corridor_axis == 0:
		trig_rect.size = Vector2(reach, span_perp)
	else:
		trig_rect.size = Vector2(span_perp, reach)
	trig_shape.shape = trig_rect
	_trigger.add_child(trig_shape)
	add_child(_trigger)
	_trigger.body_entered.connect(_on_trigger_entered)
	_trigger.body_exited.connect(_on_trigger_exited)

	# --- Top-down 2D visual: a "+" (closed door) glyph per covered tile ---
	var origin_tile := cover_tiles[cover_tiles.size() / 2]  # node sits at this tile's center
	for t: Vector2i in cover_tiles:
		var g := Label.new()
		g.add_theme_font_override("font", _shared_font)
		g.add_theme_font_size_override("font_size", 18)
		g.add_theme_color_override("font_color", Color(0.72, 0.55, 0.32))
		g.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.03))
		g.add_theme_constant_override("outline_size", 2)
		g.text = "+"
		g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		g.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		g.size = Vector2(TILE, TILE)
		# Position relative to the node origin (which is the center tile's center).
		g.position = Vector2(
			float(t.x - origin_tile.x) * TILE - TILE * 0.5,
			float(t.y - origin_tile.y) * TILE - TILE * 0.5)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.z_index = 1
		add_child(g)
		_glyphs.append(g)

	# Seal-style doors spawn already open (passable); a later close() raises the wall.
	if start_open:
		_open_amount = 1.0
		_open_target = 1.0
		_col_shape.disabled = true

	# Build FP segments now (if a rig is live) and whenever the render mode flips.
	if not GameState.render_mode_changed.is_connected(_on_render_mode_changed):
		GameState.render_mode_changed.connect(_on_render_mode_changed)
	_sync_fp_segments()

# Public remote control (used by switches, ambush seals, etc.).
func open() -> void:
	_open_target = 1.0

func close() -> void:
	_open_target = 0.0

func _on_render_mode_changed(_mode: int) -> void:
	_sync_fp_segments()

func _sync_fp_segments() -> void:
	var rig: Node = GameState.active_rig
	var fp_active: bool = rig != null and is_instance_valid(rig) \
		and GameState.render_mode != GameState.RenderMode.TOPDOWN
	if fp_active and not _segments_built and rig.has_method("add_wall_segment"):
		var color: Color = Color(0.55, 0.50, 0.42)
		if rig.has_method("get_wall_color"):
			color = rig.get_wall_color()
		# Slight warm shift so the door reads as a door, not seamless wall.
		color = color.lerp(Color(0.70, 0.55, 0.35), 0.25)
		for t: Vector2i in cover_tiles:
			var px := Vector2(float(t.x) * TILE + TILE * 0.5, float(t.y) * TILE + TILE * 0.5)
			var id: int = rig.add_wall_segment(px, color)
			if id >= 0:
				_seg_ids.append(id)
				rig.set_wall_segment_open(id, _open_amount)
		# Only mark built if segments actually got created — otherwise retry
		# next frame (rig's _world3d may not have existed yet).
		_segments_built = _seg_ids.size() > 0
	elif not fp_active and _segments_built:
		_clear_fp_segments()

func _clear_fp_segments() -> void:
	var rig: Node = GameState.active_rig
	if rig != null and is_instance_valid(rig) and rig.has_method("remove_wall_segment"):
		for id in _seg_ids:
			rig.remove_wall_segment(id)
	_seg_ids.clear()
	_segments_built = false

func _process(delta: float) -> void:
	# Lazily (re)build/teardown FP segments — robust to the rig becoming active
	# AFTER the door spawned (floor loaded directly into FP), since World's
	# render-mode apply doesn't re-emit render_mode_changed during the build.
	var fp_active: bool = GameState.active_rig != null \
		and is_instance_valid(GameState.active_rig) \
		and GameState.render_mode != GameState.RenderMode.TOPDOWN
	if fp_active != _segments_built:
		_sync_fp_segments()
	# Top-down glyphs: hidden in FP (rig draws the 3D segments instead), and
	# fade out / swap "+"→"/" as the door opens.
	var topdown: bool = GameState.render_mode == GameState.RenderMode.TOPDOWN
	for g in _glyphs:
		g.visible = topdown
		if topdown:
			g.modulate.a = clampf(1.0 - _open_amount, 0.0, 1.0)
			var want := "/" if _open_amount > 0.5 else "+"
			if g.text != want:
				g.text = want
	if absf(_open_amount - _open_target) > 0.001:
		_open_amount = move_toward(_open_amount, _open_target, OPEN_SPEED * delta)
		_push_open_amount()
		# Collision is solid only while essentially closed.
		var solid: bool = _open_amount <= 0.05
		if _col_shape.disabled == solid:
			_col_shape.disabled = not solid

func _push_open_amount() -> void:
	var rig: Node = GameState.active_rig
	if rig == null or not is_instance_valid(rig) or not rig.has_method("set_wall_segment_open"):
		return
	for id in _seg_ids:
		rig.set_wall_segment_open(id, _open_amount)

func _on_trigger_entered(body: Node2D) -> void:
	if remote_only:
		return
	if not body.is_in_group("player"):
		return
	if _open_target != 1.0:
		_open_target = 1.0
		if SoundManager:
			SoundManager.play("whoosh", randf_range(0.85, 0.95))

func _on_trigger_exited(body: Node2D) -> void:
	if remote_only:
		return
	if not body.is_in_group("player"):
		return
	# Only close once no player remains in the trigger.
	for b in _trigger.get_overlapping_bodies():
		if is_instance_valid(b) and b.is_in_group("player"):
			return
	if _open_target != 0.0:
		_open_target = 0.0
		if SoundManager:
			SoundManager.play("whoosh", randf_range(0.7, 0.8))

func _exit_tree() -> void:
	_clear_fp_segments()
