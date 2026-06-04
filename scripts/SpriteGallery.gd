extends Control

# Dev-only ASCII art preview / approval gallery.
#
# Renders every entity sprite in AsciiSprites.SPRITES and every set-piece .txt
# in res://assets/ascii/ exactly as the game would draw it — real MonoFont,
# real font size, on a 32px tile grid so scale-vs-tile is obvious. Flip
# through candidates, play idle/walk/hurt/death, cycle all 9 fonts, and zoom
# to inspect. Nothing here ships in a build; it exists so ASCII art can get a
# fast human thumbs-up/down before it's committed.
#
# Run it directly:  Godot ... res://scenes/SpriteGallery.tscn   (or F6 in editor)
#
# Controls:
#   ← / →    previous / next sprite
#   1 2 3 4  idle / walk / hurt / death (entity sprites)
#   F        cycle font
#   G        toggle 32px tile grid
#   + / -    zoom preview
#   R        reload library + set-piece list from disk
#   Esc      quit

const TILE := 32.0
const WIZARD_REF := "   ^\n__/_\\__\n (*-*)\n /)V(\\|\n /___\\|"
# Which enemy each sprite is wired to (shown in the gallery header).
const SPRITE_TO_ENEMY := {
	"spider2": "Spider", "bat": "Stalker", "ghost_big": "Banshee / Phantom",
	"knight": "Berserker", "minotaur": "Charger", "fairy": "Enchanter",
	"goblin": "Chaser", "tank_man": "Tank", "jester_head": "Beam Sweep",
	"jester": "Spiral Mage", "boss_brute": "Boss (Brute)", "gnome": "Summoner",
	"swimmer": "Sniper", "ghost": "Splitter", "brute": "Mine Layer",
	"reflector": "Reflector", "bone_drake": "Bone Drake", "shooter": "Shooter",
	"eye2": "Missile Turret", "ice_sentinel": "Frost Sentinel",
	"grenadier": "Grenadier", "bomber": "Bomber",
	"archer": "Archer", "spawner": "Spawner",
	"wizard": "Enemy Wizard", "magma_slug": "Magma Slug",
	"boss_architect": "The Architect", "boss_devourer": "The Devourer",
	"boss_lich": "The Lich", "boss_magma": "Magma Tyrant", "boss_wraith": "The Wraith",
}
# Object / interactable sprites — labelled + grouped after the enemies.
const SPRITE_TO_OBJECT := {
	"shrine": "Shrine", "loot_bag": "Loot Bag", "enchant_table": "Enchant Table",
	"mine": "Mine", "training_dummy": "Training Dummy", "exit_portal": "Exit Portal",
	"portal": "Portal", "teleporter": "Teleporter", "descend_portal": "Descend Portal",
	"gold_pickup": "Gold", "bank": "Bank", "shop": "Shop", "quest_board": "Quest Board",
	"reroller": "Reroller", "sell_chest": "Sell Chest", "spike_trap": "Spike Trap",
}
const STATES := ["idle", "walk", "hurt", "death"]

var _entries: Array = []          # [{kind:"sprite"|"piece", key/path, name}]
var _idx: int = 0
var _state: String = "idle"
var _zoom: float = 2.0
var _show_grid: bool = true

# Frame cycling for the current entry.
var _frames: Array = []           # entity: Array of {t,d,mod?}; piece: Array of String
var _frame_idx: int = 0
var _frame_t: float = 0.0

var _grid: Control = null
var _stage: Label = null
var _info: Label = null
var _help: Label = null

# 3D preview ("3d" mode, toggled with F1): the sprite as a billboard in a
# simple grid-floor room with a human-scale reference, and an orbit camera you
# can back away / circle for framing. Mirrors how the FP rig sizes billboards.
var _mode: String = "2d"
var _vp_container: SubViewportContainer = null
var _vp: SubViewport = null
var _cam: Camera3D = null
# One Label3D per row (Godot trims leading whitespace on a multi-line Label3D's
# continuation rows, so a single label can't keep the column grid). The rows
# live under a Node3D that turns to face the camera as a rigid block.
var _sprite3d_root: Node3D = null
var _ref_root: Node3D = null   # player-wizard scale reference (tier 3)
var _rows: Array = []
var _ps3d: float = 0.01
var _color3d: Color = Color.WHITE
var _cam_yaw: float = 0.0
var _cam_pitch: float = 0.30
var _cam_height: float = 0.42   # low, near-floor eye height; dollying back never raises it
var _cam_dist: float = 4.0
var _cam_target: Vector3 = Vector3(0.0, 0.9, 0.0)
# Live tuning for the current sprite. Arrows edit these in-place (preview only);
# nothing is written to disk until you press Enter (save). _size_tier overrides
# the sprite's declared size; _height_offset is a manual vertical nudge added on
# top of the computed sprite Y (which rides on _base_sprite_y). _dirty tracks
# unsaved edits.
var _height_offset: float = 0.0
var _base_sprite_y: float = 0.0
var _size_tier: int = 3
var _dirty: bool = false
# Live base-colour tuning (C / Shift+C cycles a palette). Seeded from the
# sprite's meta on load; committed to the overrides file on Enter like the rest.
var _base_color: Color = Color.WHITE
var _palette_idx: int = -1
# Hitbox tuning (Ctrl+↑/↓ size, Ctrl+←/→ shape). Seeded from a saved override
# only — left unset, the enemy keeps its scene collider untouched. Preview is
# drawn at game scale (px) over the 2D view against the tile grid.
var _hitbox_size: float = 14.0
var _hitbox_shape: String = "circle"   # "circle" | "square"
var _hitbox_tuned: bool = false        # true once it differs from the scene default
const COLOR_PALETTE: Array = [
	Color(0.90, 0.90, 0.95),   # near-white
	Color(0.70, 0.72, 0.80),   # cool grey
	Color(0.85, 0.50, 0.40),   # brick red
	Color(0.90, 0.55, 0.20),   # orange
	Color(0.92, 0.85, 0.40),   # gold
	Color(0.55, 0.85, 0.45),   # green
	Color(0.40, 0.82, 0.70),   # teal
	Color(0.50, 0.78, 0.90),   # sky blue
	Color(0.55, 0.55, 0.95),   # indigo
	Color(0.75, 0.50, 0.90),   # violet
	Color(0.92, 0.55, 0.80),   # pink
	Color(0.60, 0.42, 0.30),   # brown
	Color(0.34, 0.36, 0.45),   # slate
	Color(0.12, 0.12, 0.15),   # near-black
]
# Fixed head-on distance used by the "fp" (first-person) preview camera.
const FP_CAM_DIST: float = 2.2

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_grid = Control.new()
	_grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.draw.connect(_draw_grid)
	add_child(_grid)

	_stage = Label.new()
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)

	_build_3d()   # added before info/help so those overlay it

	_info = Label.new()
	_info.position = Vector2(16, 12)
	_info.add_theme_font_size_override("font_size", 16)
	_info.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	_info.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_info.add_theme_constant_override("outline_size", 3)
	add_child(_info)

	_help = Label.new()
	_help.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_help.position = Vector2(16, -34)
	_help.add_theme_font_size_override("font_size", 13)
	_help.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	_help.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_help.add_theme_constant_override("outline_size", 2)
	_update_help()
	add_child(_help)

	_build_entries()
	_load_current()

func _update_help() -> void:
	if _mode == "3d":
		_help.text = "F1 1st-person   ←/→ sprite   ↑/↓ size·shift height·ctrl hitbox · ctrl←/→ shape · C colour · Enter save   1-4 state   WASD·QE cam   F font   Esc"
	elif _mode == "fp":
		_help.text = "F1 2D view   ←/→ sprite   ↑/↓ size·shift height·ctrl hitbox · ctrl←/→ shape · C colour · Enter save   1-4 state   F font   Esc"
	else:
		_help.text = "F1 3rd-person   ←/→ sprite   ctrl↑/↓ hitbox · ctrl←/→ shape · C colour · Enter save   1-4 state   F font   G grid   +/- zoom   Esc"

func _build_entries() -> void:
	_entries.clear()
	# Order: enemy-wired sprites first, then objects/interactables, then
	# unassigned sprite drafts, then raw set-piece .txt last.
	var enemies: Array = []
	var objects: Array = []
	var unassigned: Array = []
	for key in AsciiSprites.SPRITES.keys():
		var entry := {"kind": "sprite", "key": String(key), "name": String(key)}
		if SPRITE_TO_ENEMY.has(String(key)):
			enemies.append(entry)
		elif SPRITE_TO_OBJECT.has(String(key)):
			objects.append(entry)
		else:
			unassigned.append(entry)
	_entries.append_array(enemies)
	_entries.append_array(objects)
	_entries.append_array(unassigned)
	var dir := DirAccess.open("res://assets/ascii")
	if dir != null:
		for f in dir.get_files():
			if f.get_extension().to_lower() == "txt":
				_entries.append({
					"kind": "piece",
					"path": "res://assets/ascii/".path_join(f),
					"name": f.get_basename(),
				})
	if _idx >= _entries.size():
		_idx = 0

func _load_current() -> void:
	_frame_idx = 0
	_frame_t = 0.0
	_dirty = false
	if _entries.is_empty():
		_stage.text = "(no sprites in AsciiSprites and no .txt in assets/ascii)"
		_info.text = "EMPTY"
		return
	var e: Dictionary = _entries[_idx]
	# Seed live tuning from the (override-merged) meta so previously-saved tweaks
	# load back; pieces have no tuning.
	_palette_idx = -1
	if e["kind"] == "sprite":
		var m: Dictionary = AsciiSprites.meta(e["key"])
		_size_tier = clampi(int(m.get("size", 3)), 1, 5)
		_height_offset = float(m.get("height_offset", 0.0))
		_base_color = m.get("color", Color.WHITE)
		_hitbox_tuned = AsciiSprites.override_value(e["key"], "hitbox_size", null) != null
		_hitbox_size = float(AsciiSprites.override_value(e["key"], "hitbox_size", 14.0))
		_hitbox_shape = String(AsciiSprites.override_value(e["key"], "hitbox_shape", "circle"))
	else:
		_size_tier = 3
		_height_offset = 0.0
		_base_color = Color(0.85, 0.82, 0.95)
		_hitbox_tuned = false
		_hitbox_size = 14.0
		_hitbox_shape = "circle"
	_stage.add_theme_font_override("font", MonoFont.get_font())
	_stage.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	if e["kind"] == "sprite":
		_load_sprite(e["key"])
	else:
		_load_piece(e["path"])
	_grid.queue_redraw()   # refresh the hitbox overlay for the new entry

func _load_sprite(key: String) -> void:
	var meta: Dictionary = AsciiSprites.meta(key)
	var fs := int(meta.get("font_size", 14)) * _zoom
	_stage.add_theme_font_size_override("font_size", int(fs))
	_stage.add_theme_constant_override("line_separation", int(meta.get("line_sep", -4)))
	_stage.add_theme_constant_override("outline_size", maxi(2, int(meta.get("outline", 3))))
	_stage.add_theme_color_override("font_color", _base_color)
	# Frames are padded to equal width (AsciiSprites.pad_block), so center is
	# safe and keeps the column grid. Set alignment explicitly every load so it
	# never inherits a previous entry's state.
	_stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stage.offset_left = 0.0
	if not AsciiSprites.anims(key).has(_state):
		_state = "idle"
	_frames = AsciiSprites.frames(key, _state)
	_apply_frame()
	_update_3d_size(true, meta)
	_update_info()

func _load_piece(path: String) -> void:
	_stage.add_theme_constant_override("line_separation", -2)
	_stage.add_theme_constant_override("outline_size", 3)
	_stage.add_theme_color_override("font_color", Color(0.85, 0.82, 0.95))
	# Set alignment explicitly so a set-piece never inherits a sprite's offset
	# (this was why arriving at the reaper from the left looked shifted).
	_stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stage.offset_left = 0.0
	var text := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "(missing)"
	# Split on lines == "---" for multi-frame pieces.
	var frames: Array = []
	var cur: Array = []
	for line in text.split("\n"):
		if (line as String).strip_edges() == "---":
			frames.append("\n".join(cur)); cur.clear()
		else:
			cur.append(line)
	if not cur.is_empty():
		frames.append("\n".join(cur))
	# Pad each frame to equal-width lines so center alignment keeps the grid.
	for i in frames.size():
		frames[i] = AsciiSprites.pad_block(frames[i])
	_frames = frames
	# Auto-fit: scale font so the widest line fits ~70% of the screen width.
	var first: String = String(frames[0]) if not frames.is_empty() else ""
	var cols := 1
	for ln in first.split("\n"):
		cols = maxi(cols, (ln as String).length())
	var fit := int(clampf((size.x * 0.7) / float(maxi(cols, 1)) * 1.7, 8.0, 28.0) * _zoom)
	_stage.add_theme_font_size_override("font_size", maxi(6, fit))
	_apply_frame()
	_update_3d_size(false, {})
	_update_info()

func _apply_frame() -> void:
	if _frames.is_empty():
		_stage.text = "(no frames)"
		return
	var fr: Variant = _frames[_frame_idx % _frames.size()]
	if fr is Dictionary:
		_stage.text = str((fr as Dictionary).get("t", ""))
		if (fr as Dictionary).has("mod"):
			_stage.add_theme_color_override("font_color", (fr as Dictionary)["mod"])
		else:
			var e: Dictionary = _entries[_idx]
			if e["kind"] == "sprite":
				# Use the live tuning colour (seeded from meta, updated by C) so a
				# colour pick survives frame animation instead of snapping back to
				# the preset a tick later.
				_stage.add_theme_color_override("font_color", _base_color)
	else:
		_stage.text = str(fr)
	# Mirror text + colour onto the 3D billboard rows.
	if _sprite3d_root != null:
		_color3d = _stage.get_theme_color("font_color")
		_render_3d()

# Renders the current text as one Label3D per row under _sprite3d_root. Each
# row keeps its own leading spaces (single-line Label3Ds preserve them) and
# left-aligns from a shared, block-centered origin so the columns line up.
func _render_3d() -> void:
	if _sprite3d_root == null:
		return
	var lines: PackedStringArray = _stage.text.split("\n")
	var rows: int = maxi(1, lines.size())
	var font := MonoFont.get_font()
	var char_w: float = font.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x
	var max_cols: int = 0
	for ln in lines:
		max_cols = maxi(max_cols, ln.length())
	var line_h: float = font.get_height(64) * _ps3d * 0.92
	var mid: float = float(rows - 1) * 0.5
	var half_w: float = 0.5 * float(max_cols) * char_w * _ps3d
	while _rows.size() < rows:
		var r := Label3D.new()
		r.font = font
		r.font_size = 64
		r.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		r.shaded = false
		r.double_sided = true
		r.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		r.outline_size = 10
		r.outline_modulate = Color(0, 0, 0, 1)
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		r.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_sprite3d_root.add_child(r)
		_rows.append(r)
	for i in _rows.size():
		var rl: Label3D = _rows[i]
		if i < rows:
			rl.visible = true
			rl.text = String(lines[i])
			rl.font = font
			rl.pixel_size = _ps3d
			rl.modulate = _color3d
			# Local frame; the parent turns to face the camera (rigid block).
			rl.position = Vector3(-half_w, (mid - float(i)) * line_h, 0.0)
		else:
			rl.visible = false

func _update_info() -> void:
	var e: Dictionary = _entries[_idx]
	var txt := str(_stage.text)
	var rows := txt.split("\n").size()
	var cols := 1
	for ln in txt.split("\n"):
		cols = maxi(cols, (ln as String).length())
	var head := "%d/%d  %s  [%s]" % [_idx + 1, _entries.size(), e["name"], e["kind"]]
	if e["kind"] == "sprite":
		var k := String(e.get("key", ""))
		var en: String = SPRITE_TO_ENEMY.get(k, SPRITE_TO_OBJECT.get(k, ""))
		head += "   → %s" % (en if en != "" else "(unassigned)")
	var line2 := "font: %s   size: %d   zoom: %.1fx   %dx%d chars" % [
		MonoFont.current_name(), _stage.get_theme_font_size("font_size"), _zoom, cols, rows]
	var line3 := ("state: %s   frame %d/%d" % [_state, (_frame_idx % maxi(_frames.size(),1)) + 1, _frames.size()]) \
		if e["kind"] == "sprite" else ("frames: %d" % _frames.size())
	var sz := ""
	if e["kind"] == "sprite":
		var th: float = AsciiSprites.SIZE_HEIGHTS.get(_size_tier, 1.05)
		var fly: bool = bool(AsciiSprites.meta(e["key"]).get("flying", false))
		var dirty := "  ●UNSAVED (Enter to save)" if _dirty else ""
		var hb := "%.0f %s" % [_hitbox_size, _hitbox_shape] + ("" if _hitbox_tuned else " (scene default)")
		sz = "size tier: %d (↑/↓)   height: %.2f  offset %+.2f (shift ↑/↓)   colour #%s (C)\nhitbox: %s (ctrl ↑/↓ size · ctrl ←/→ shape)%s%s" % [
			_size_tier, th, _height_offset, _base_color.to_html(false),
			hb, ("   (flying)" if fly else ""), dirty]
	_info.text = "%s\n%s\n%s\n%s" % [head, line2, line3, sz]

func _process(delta: float) -> void:
	if _mode == "3d":
		_update_camera(delta)
	if _frames.size() <= 1:
		return
	_frame_t += delta
	var fr: Variant = _frames[_frame_idx % _frames.size()]
	var dur := float((fr as Dictionary).get("d", 0.3)) if fr is Dictionary else 0.4
	if _frame_t >= dur:
		_frame_t = 0.0
		_frame_idx += 1
		_apply_frame()
		_update_info()

func _draw_grid() -> void:
	var cx := size.x * 0.5
	var cy := size.y * 0.5
	if _show_grid:
		var col := Color(1, 1, 1, 0.06)
		var x := fmod(cx, TILE)
		while x < size.x:
			_grid.draw_line(Vector2(x, 0), Vector2(x, size.y), col, 1.0)
			x += TILE
		var y := fmod(cy, TILE)
		while y < size.y:
			_grid.draw_line(Vector2(0, y), Vector2(size.x, y), col, 1.0)
			y += TILE
		# Highlight the central tile so 1-tile scale is obvious (1 tile = 32px).
		_grid.draw_rect(Rect2(cx - TILE * 0.5, cy - TILE * 0.5, TILE, TILE),
			Color(0.4, 0.8, 1.0, 0.25), false, 1.5)
	# Hitbox footprint, drawn at game scale (px vs the 32px tile) over the 2D
	# sprite so it can be sized against the art.
	if _mode == "2d" and not _entries.is_empty() and _entries[_idx]["kind"] == "sprite":
		var hc := Color(1.0, 0.85, 0.2, 0.85) if _hitbox_tuned else Color(1.0, 0.85, 0.2, 0.45)
		if _hitbox_shape == "square":
			_grid.draw_rect(Rect2(cx - _hitbox_size, cy - _hitbox_size,
				_hitbox_size * 2.0, _hitbox_size * 2.0), hc, false, 2.0)
		else:
			_grid.draw_arc(Vector2(cx, cy), _hitbox_size, 0.0, TAU, 64, hc, 2.0)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_F1:
			# Cycle the same three views the game uses: flat 2D → 3rd-person
			# room → 1st-person head-on.
			var order := ["2d", "3d", "fp"]
			_set_mode(order[(order.find(_mode) + 1) % order.size()])
		KEY_RIGHT:
			if (event as InputEventKey).ctrl_pressed: _set_hitbox_shape("square")
			else:
				_idx = (_idx + 1) % maxi(_entries.size(), 1); _state = "idle"; _load_current()
		KEY_LEFT:
			if (event as InputEventKey).ctrl_pressed: _set_hitbox_shape("circle")
			else:
				_idx = (_idx - 1 + _entries.size()) % maxi(_entries.size(), 1); _state = "idle"; _load_current()
		KEY_UP:
			var ev_u := event as InputEventKey
			if ev_u.ctrl_pressed: _adjust_hitbox(1.0)
			elif _mode != "2d":
				if ev_u.shift_pressed: _adjust_height(0.1)
				else: _adjust_size(1)
		KEY_DOWN:
			var ev_d := event as InputEventKey
			if ev_d.ctrl_pressed: _adjust_hitbox(-1.0)
			elif _mode != "2d":
				if ev_d.shift_pressed: _adjust_height(-0.1)
				else: _adjust_size(-1)
		KEY_ENTER, KEY_KP_ENTER:
			_save_tuning()
		KEY_C:
			_cycle_color(-1 if (event as InputEventKey).shift_pressed else 1)
		KEY_1: _set_state("idle")
		KEY_2: _set_state("walk")
		KEY_3: _set_state("hurt")
		KEY_4: _set_state("death")
		KEY_F:
			GameState.font_choice = (GameState.font_choice + 1) % MonoFont.choice_count()
			MonoFont.invalidate()
			_stage.add_theme_font_override("font", MonoFont.get_font())
			if _mode != "2d":
				_render_3d()   # repaint the billboard rows in the new font
			_update_info()
		KEY_G:
			_show_grid = not _show_grid; _grid.queue_redraw()
		KEY_EQUAL, KEY_KP_ADD:
			_zoom = clampf(_zoom + 0.25, 0.5, 6.0); _load_current()
		KEY_MINUS, KEY_KP_SUBTRACT:
			_zoom = clampf(_zoom - 0.25, 0.5, 6.0); _load_current()
		KEY_R:
			_build_entries(); _load_current()
		KEY_ESCAPE:
			# Return to the title (the gallery is usually launched from there).
			if ResourceLoader.exists("res://scenes/TitleScreen.tscn"):
				get_tree().change_scene_to_file("res://scenes/TitleScreen.tscn")
			else:
				get_tree().quit()

func _set_state(s: String) -> void:
	if _entries.is_empty() or _entries[_idx]["kind"] != "sprite":
		return
	_state = s
	_frame_idx = 0
	_frame_t = 0.0
	_load_sprite(_entries[_idx]["key"])

# ── 3D preview room ─────────────────────────────────────────────────────────

func _build_3d() -> void:
	_vp_container = SubViewportContainer.new()
	_vp_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vp_container.stretch = true
	_vp_container.visible = false
	_vp_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vp_container)

	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp_container.add_child(_vp)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.ambient_light_energy = 1.0
	we.environment = env
	_vp.add_child(we)

	_cam = Camera3D.new()
	_vp.add_child(_cam)

	_vp.add_child(_make_floor_grid())

	# Player-wizard scale reference (tier 3) standing on the floor beside the
	# previewed sprite, so its size reads against the actual player.
	_ref_root = Node3D.new()
	_ref_root.position = Vector3(1.8, 0.0, 0.0)
	_vp.add_child(_ref_root)
	_build_reference_wizard()

	_sprite3d_root = Node3D.new()
	_vp.add_child(_sprite3d_root)

func _build_reference_wizard() -> void:
	if _ref_root == null:
		return
	var lines: PackedStringArray = WIZARD_REF.split("\n")
	var rows := lines.size()
	var font := MonoFont.get_font()
	var fh := font.get_height(64)
	var target_h: float = AsciiSprites.SIZE_HEIGHTS.get(3, 1.05)
	var ps := target_h / (float(rows) * fh * 0.92)
	var char_w := font.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x * ps
	var max_cols := 0
	for ln in lines:
		max_cols = maxi(max_cols, ln.length())
	var half_w := 0.5 * float(max_cols) * char_w
	var line_h := fh * ps * 0.92
	var mid := float(rows - 1) * 0.5
	for i in rows:
		var rl := Label3D.new()
		rl.text = String(lines[i])
		rl.font = font
		rl.font_size = 64
		rl.pixel_size = ps
		rl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		rl.shaded = false
		rl.double_sided = true
		rl.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		rl.outline_size = 8
		rl.outline_modulate = Color(0, 0, 0, 1)
		rl.modulate = Color(0.55, 0.45, 0.90)
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		rl.position = Vector3(-half_w, target_h * 0.5 + (mid - float(i)) * line_h, 0.0)
		_ref_root.add_child(rl)

func _make_floor_grid() -> MeshInstance3D:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var n := 8
	var col := Color(0.24, 0.24, 0.30)
	for i in range(-n, n + 1):
		im.surface_set_color(col)
		im.surface_add_vertex(Vector3(i, 0.0, -n))
		im.surface_set_color(col)
		im.surface_add_vertex(Vector3(i, 0.0, n))
		im.surface_set_color(col)
		im.surface_add_vertex(Vector3(-n, 0.0, i))
		im.surface_set_color(col)
		im.surface_add_vertex(Vector3(n, 0.0, i))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mi.material_override = mat
	return mi

# Sizes the billboard the same way the FP rig does: font_size 64 with
# pixel_size = fp_pixel_size / row_count, so what you frame here matches what
# the game will draw. Set-pieces (no fp size) get scaled to ~2.5 units tall.
func _update_3d_size(is_sprite: bool, meta: Dictionary) -> void:
	if _sprite3d_root == null:
		return
	var rows := maxi(1, str(_stage.text).split("\n").size())
	# Use the live tier being tuned (seeded from meta on load) so size edits
	# preview immediately.
	var tier := clampi(_size_tier if is_sprite else 3, 1, 5)
	var target_h: float = AsciiSprites.SIZE_HEIGHTS.get(tier, 1.05)
	var fh := MonoFont.get_font().get_height(64)
	# Scale so the sprite stands exactly its tier height regardless of row count.
	_ps3d = target_h / (float(rows) * fh * 0.92)
	var flying: bool = bool(meta.get("flying", false)) if is_sprite else false
	if flying:
		# Hover: small flyers ride up to eye level; big ones keep their bottom
		# just off the floor (centring a tall flyer at eye level would sink half
		# of it below the floor — the gryphon problem).
		_base_sprite_y = maxf(_cam_height, target_h * 0.5 + 0.05)
	else:
		_base_sprite_y = target_h * 0.5 + 0.02  # base on floor
	_reposition_sprite3d()
	_cam_target = Vector3(0.0, _cam_height, 0.0)
	_render_3d()
	if _mode == "fp":
		_frame_fp_camera()

# Places the billboard at its computed base height plus the manual Up/Down nudge.
func _reposition_sprite3d() -> void:
	if _sprite3d_root != null:
		_sprite3d_root.position = Vector3(0.0, _base_sprite_y + _height_offset, 0.0)

# Up/Down (no shift): bump the size tier 1..5. Preview only — Enter saves it.
func _adjust_size(d: int) -> void:
	if _entries.is_empty() or _entries[_idx]["kind"] != "sprite":
		return
	var nw := clampi(_size_tier + d, 1, 5)
	if nw == _size_tier:
		return
	_size_tier = nw
	_dirty = true
	_update_3d_size(true, AsciiSprites.meta(_entries[_idx]["key"]))
	_update_info()

# Shift+Up/Down: nudge the vertical height offset. Preview only — Enter saves it.
func _adjust_height(d: float) -> void:
	if _entries.is_empty() or _entries[_idx]["kind"] != "sprite":
		return
	_height_offset = clampf(_height_offset + d, -1.5, 4.0)
	_dirty = true
	_reposition_sprite3d()
	_update_info()

# Ctrl+Up/Down: resize the collision hitbox (px). Ctrl+Left/Right: shape.
# Preview only — Enter saves it (and applies in-game to the wired enemy).
func _adjust_hitbox(d: float) -> void:
	if _entries.is_empty() or _entries[_idx]["kind"] != "sprite":
		return
	_hitbox_size = clampf(_hitbox_size + d, 2.0, 64.0)
	_hitbox_tuned = true
	_dirty = true
	_grid.queue_redraw()
	_update_info()

func _set_hitbox_shape(s: String) -> void:
	if _entries.is_empty() or _entries[_idx]["kind"] != "sprite" or _hitbox_shape == s:
		return
	_hitbox_shape = s
	_hitbox_tuned = true
	_dirty = true
	_grid.queue_redraw()
	_update_info()

# C / Shift+C: cycle the base colour through the palette. Preview only — Enter
# saves it. The stage's font_color drives both the 2D label and the 3D rows.
func _cycle_color(d: int) -> void:
	if _entries.is_empty() or _entries[_idx]["kind"] != "sprite":
		return
	_palette_idx = (_palette_idx + d + COLOR_PALETTE.size()) % COLOR_PALETTE.size()
	_base_color = COLOR_PALETTE[_palette_idx]
	_dirty = true
	_apply_color()
	_update_info()

func _apply_color() -> void:
	_stage.add_theme_color_override("font_color", _base_color)
	_color3d = _base_color
	if _mode != "2d":
		_render_3d()

# Commit the current tier + height + colour to the persisted overrides so the
# tweak carries to the real enemy in-game and survives restarts.
func _save_tuning() -> void:
	if _entries.is_empty() or _entries[_idx]["kind"] != "sprite":
		return
	var key: String = _entries[_idx]["key"]
	AsciiSprites.set_override(key, "size", _size_tier)
	AsciiSprites.set_override(key, "height_offset", snappedf(_height_offset, 0.01))
	AsciiSprites.set_override(key, "color", _base_color.to_html(false))
	if _hitbox_tuned:
		AsciiSprites.set_override(key, "hitbox_size", snappedf(_hitbox_size, 0.5))
		AsciiSprites.set_override(key, "hitbox_shape", _hitbox_shape)
	AsciiSprites.save_overrides()
	_dirty = false
	var hb := "  hitbox %.0f %s" % [_hitbox_size, _hitbox_shape] if _hitbox_tuned else ""
	_help.text = "✓ saved %s — size %d, height %+.2f, #%s%s   (applies in-game)" % [
		key, _size_tier, _height_offset, _base_color.to_html(false), hb]
	_update_info()

func _set_mode(m: String) -> void:
	_mode = m
	var threed := (m == "3d" or m == "fp")
	_vp_container.visible = threed
	_stage.visible = not threed
	_grid.visible = (m == "2d")   # grid Control also hosts the hitbox overlay
	_grid.queue_redraw()
	# The player-wizard scale reference belongs in the 3rd-person room; the
	# 1st-person view is a clean head-on encounter, so hide it there.
	if _ref_root != null:
		_ref_root.visible = (m == "3d")
	if threed:
		_apply_frame()
		var e: Dictionary = _entries[_idx]
		if e["kind"] == "sprite":
			_update_3d_size(true, AsciiSprites.meta(e["key"]))
		else:
			_update_3d_size(false, {})
	_update_help()
	_update_info()

# 1st-person framing: a fixed camera straight in front of the sprite at eye
# level (no orbit), so you see it exactly as the player would when facing it.
func _frame_fp_camera() -> void:
	if _cam == null:
		return
	_cam_yaw = 0.0
	_cam.position = Vector3(_cam_target.x, _cam_height, _cam_target.z + FP_CAM_DIST)
	_cam.look_at(Vector3(_cam_target.x, _cam_height, _cam_target.z), Vector3.UP)
	if _sprite3d_root != null:
		var to_cam := _cam.position - _sprite3d_root.global_position
		to_cam.y = 0.0
		if to_cam.length() > 0.001:
			_sprite3d_root.rotation = Vector3(0.0, atan2(to_cam.x, to_cam.z), 0.0)

func _update_camera(delta: float) -> void:
	var rot := 1.4 * delta
	var zoom := 4.0 * delta
	if Input.is_physical_key_pressed(KEY_A): _cam_yaw -= rot
	if Input.is_physical_key_pressed(KEY_D): _cam_yaw += rot
	if Input.is_physical_key_pressed(KEY_E): _cam_height = clampf(_cam_height + rot * 0.7, 0.1, 4.0)
	if Input.is_physical_key_pressed(KEY_Q): _cam_height = clampf(_cam_height - rot * 0.7, 0.1, 4.0)
	if Input.is_physical_key_pressed(KEY_W): _cam_dist = maxf(0.8, _cam_dist - zoom)
	if Input.is_physical_key_pressed(KEY_S): _cam_dist = minf(16.0, _cam_dist + zoom)
	var offset := Vector3(
		_cam_dist * sin(_cam_yaw),
		_cam_height - _cam_target.y,
		_cam_dist * cos(_cam_yaw))
	_cam.position = _cam_target + offset
	# Look STRAIGHT AHEAD at eye level (not at the sprite's centre) so tall/dense
	# enemies don't tilt the view — their size reads from how high they rise in
	# frame, like a real FPS.
	_cam.look_at(Vector3(_cam_target.x, _cam_height, _cam_target.z), Vector3.UP)
	# Turn the row-block to face the camera (Y only) so it reads as a rigid,
	# camera-facing sprite without the rows billboarding independently.
	if _sprite3d_root != null:
		var to_cam := _cam.position - _sprite3d_root.global_position
		to_cam.y = 0.0
		if to_cam.length() > 0.001:
			_sprite3d_root.rotation = Vector3(0.0, atan2(to_cam.x, to_cam.z), 0.0)
	if _ref_root != null:
		var rc := _cam.position - _ref_root.global_position
		rc.y = 0.0
		if rc.length() > 0.001:
			_ref_root.rotation = Vector3(0.0, atan2(rc.x, rc.z), 0.0)
