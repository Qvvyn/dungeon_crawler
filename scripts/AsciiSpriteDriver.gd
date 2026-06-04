class_name AsciiSpriteDriver
extends RefCounted

# Drives an existing AsciiChar Label from the AsciiSprites library. One
# instance per entity, created in EnemyBase / Player _ready. It owns the
# label's font / size / colour / offsets and cycles animation frames per
# state (idle / walk / hurt / death).
#
# Division of labour with EnemyBase: the driver ONLY ever writes _lbl.text
# and the font_color theme override. EnemyBase keeps writing _lbl.modulate
# every frame for the multiplicative status / hit-flash tint, so the two
# never fight — the rendered colour is (frame font_color) × (status modulate).

var _lbl: Label = null
var _key: String = ""
var _meta: Dictionary = {}
var _anims: Dictionary = {}

var _state: String = ""
var _frames: Array = []
var _idx: int = 0
var _t: float = 0.0
var _one_shot: bool = false       # hurt / death don't loop
var _dying: bool = false

var _base_color: Color = Color.WHITE
var _color_overridden: bool = false
var _last_written: String = ""

# Caches metadata + applies the static label styling, then starts on idle.
# Returns false (and changes nothing) when the key is unknown so the caller
# can fall back to its legacy single-glyph path.
func setup(label: Label, key: String) -> bool:
	if label == null or not AsciiSprites.has(key):
		return false
	_lbl = label
	_key = key
	_meta = AsciiSprites.meta(key)
	_anims = _meta.get("anims", {}) as Dictionary
	if _anims.is_empty():
		_lbl = null
		return false
	_base_color = _meta.get("color", Color.WHITE)
	_apply_label_style()
	set_state("idle", true)
	return true

# Top-down (2D) on-screen height per size tier, in px (≈ 1 tile = 32px). The
# curated art is authored tall for the FP billboard, so the 2D Label auto-fits
# its font to land near these instead of sprawling across the room.
const TD_HEIGHTS := {1: 26.0, 2: 34.0, 3: 42.0, 4: 56.0, 5: 70.0}

# Sole writer of the label's font / size / spacing / offsets / base colour
# for sprite-driven entities. EnemyBase._setup_label_font() is skipped when a
# driver is active, so there's no font_size tug-of-war.
func _apply_label_style() -> void:
	var font := MonoFont.get_font()
	_lbl.add_theme_font_override("font", font)
	# Auto-fit the 2D font: rendered at its declared font_size, a 25-row sprite
	# spans ~8 tiles in top-down. Shrink the font so the whole sprite stands
	# roughly its tier height (≈1–2 tiles); never grow past the declared size.
	var first := first_frame_text()
	var lines := first.split("\n")
	var rows := maxi(1, lines.size())
	var max_cols := 1
	for ln in lines:
		max_cols = maxi(max_cols, String(ln).length())
	var declared_fs := int(_meta.get("font_size", 14))
	var tier := clampi(int(_meta.get("size", 3)), 1, 5)
	var target_h: float = float(TD_HEIGHTS.get(tier, 42.0))
	var hr: float = maxf(font.get_height(32) / 32.0, 0.5)   # px per font-size unit
	var fs := clampi(int(round(target_h / (float(rows) * hr))), 3, declared_fs)
	_lbl.add_theme_font_size_override("font_size", fs)
	# Scale spacing + outline so they stay proportional at the smaller size.
	var ls := int(round(float(int(_meta.get("line_sep", -4))) * float(fs) / float(maxi(1, declared_fs))))
	_lbl.add_theme_constant_override("line_separation", ls)
	var ol := maxi(1, int(round(float(int(_meta.get("outline", 3))) * float(fs) / float(maxi(1, declared_fs)))))
	_lbl.add_theme_constant_override("outline_size", ol)
	_lbl.add_theme_color_override("font_color", _base_color)
	_lbl.add_theme_color_override("font_outline_color", _meta.get("outline_color", Color(0, 0, 0, 1)))
	# Large hand-curated art relies on per-row leading whitespace (left-aligned
	# fixed grid). Centering each line independently would scramble it, so such
	# sprites declare "align": "left". Small symmetric sprites stay centered.
	if String(_meta.get("align", "center")) == "left":
		_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	else:
		_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Centre the art on the hitbox origin: a symmetric box sized to the fitted
	# text keeps CENTER alignment locked to (0,0) so the sprite sits on its
	# collider instead of drifting off to one corner.
	var char_w: float = font.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var w: float = maxf(float(max_cols) * char_w + 6.0, 16.0)
	var h: float = maxf(float(rows) * (font.get_height(fs) + float(ls)) + 6.0, 16.0)
	_lbl.offset_left = -w * 0.5
	_lbl.offset_right = w * 0.5
	_lbl.offset_top = -h * 0.5
	_lbl.offset_bottom = h * 0.5

func _frames_for(state: String) -> Array:
	# Go through AsciiSprites.frames() so file-backed frames resolve to text.
	var f := AsciiSprites.frames(_key, state)
	if not f.is_empty():
		return f
	# Graceful fallbacks so a sprite needn't define every state.
	match state:
		"walk", "hurt":
			return AsciiSprites.frames(_key, "idle")
		"death":
			var h := AsciiSprites.frames(_key, "hurt")
			return h if not h.is_empty() else AsciiSprites.frames(_key, "idle")
	return AsciiSprites.frames(_key, "idle")

func set_state(state: String, force: bool = false) -> void:
	if _dying and state != "death":
		return                       # death is terminal
	if state == _state and not force:
		return
	var frames := _frames_for(state)
	if frames.is_empty():
		return
	_state = state
	_frames = frames
	_idx = 0
	_t = 0.0
	_one_shot = (state == "hurt" or state == "death")
	if state == "death":
		_dying = true
		_start_death_fade()
	_write_current()

# Called once per physics frame from the host's anim tick. `moving` toggles
# the auto idle<->walk loop; one-shots (hurt/death) ignore it until they end.
func tick(delta: float, moving: bool) -> void:
	if _lbl == null:
		return
	if not _one_shot:
		var want := "walk" if (moving and _anims.has("walk")) else "idle"
		if want != _state:
			set_state(want)
	_advance(delta)

func _advance(delta: float) -> void:
	if _frames.size() <= 1:
		return                       # static state — nothing to cycle
	_t += delta
	var dur: float = float((_frames[_idx] as Dictionary).get("d", 0.3))
	if _t < dur:
		return
	_t = 0.0
	if _idx < _frames.size() - 1:
		_idx += 1
		_write_current()
	elif _dying:
		return                       # hold the final death frame
	elif _one_shot:
		_one_shot = false            # hurt finished — resume the auto loop
		set_state("idle", true)
	else:
		_idx = 0                     # loop idle / walk
		_write_current()

func _write_current() -> void:
	if _frames.is_empty():
		return
	var fr: Dictionary = _frames[_idx] as Dictionary
	var txt: String = str(fr.get("t", ""))
	if txt != _last_written:
		_lbl.text = txt
		_last_written = txt
	if fr.has("mod"):
		_lbl.add_theme_color_override("font_color", fr["mod"])
		_color_overridden = true
	elif _color_overridden:
		_lbl.add_theme_color_override("font_color", _base_color)
		_color_overridden = false

# Fades the label out over the back half of the death sequence. Runs on the
# label's own tween so it's independent of the host's physics ticking.
func _start_death_fade() -> void:
	if _lbl == null or not _lbl.is_inside_tree():
		return
	var d := death_duration()
	var tw := _lbl.create_tween()
	tw.tween_interval(d * 0.5)
	tw.tween_property(_lbl, "modulate:a", 0.0, d * 0.5)

func death_duration() -> float:
	var total := 0.0
	for fr in _frames_for("death"):
		total += float((fr as Dictionary).get("d", 0.3))
	return maxf(total, 0.35)

# The idle frame written at setup — used as the glyph passed to the FP rig's
# register_entity so the billboard registers as multi-line from the start.
func first_frame_text() -> String:
	var frames := _frames_for("idle")
	if frames.is_empty():
		return ""
	return str((frames[0] as Dictionary).get("t", ""))

func is_dying() -> bool:
	return _dying

# Per-entity FP metadata for the host to apply via set_meta before it
# registers with the first-person rig.
# Re-asserts the driver's label styling + current frame. EnemyBase calls this
# after a subclass's _on_ready_extra(), which may have stomped the label with
# the enemy's old single-char art — this makes the sprite win.
func reapply() -> void:
	if _lbl == null:
		return
	_apply_label_style()
	_last_written = ""
	_write_current()

func fp_metas() -> Dictionary:
	# Derive FP size + floor placement from the sprite's size tier so in-game
	# enemies match the gallery: tier height drives pixel_size, and the billboard
	# is centred so its base sits on the floor (flyers hover at ~eye level).
	# fp_grid routes through the rig's per-row path (keeps leading-space columns).
	var tier: int = clampi(int(_meta.get("size", 3)), 1, 5)
	var target_h: float = float(AsciiSprites.SIZE_HEIGHTS.get(tier, 1.05))
	# Rig per-row total height = 64 * ROW_SPACING(1.18) * pixel_size, so:
	var ps: float = target_h / (64.0 * 1.18)
	var center_y: float
	if bool(_meta.get("flying", false)):
		center_y = maxf(0.55, target_h * 0.5 + 0.1)   # hover; never sink below floor
	else:
		center_y = target_h * 0.5                       # base on floor
	# Manual vertical nudge tuned in the gallery (e.g. drop a boss so its back
	# leg sits on the floor). Persisted per-sprite in AsciiSprites overrides.
	center_y += float(_meta.get("height_offset", 0.0))
	return {
		"fp_multiline": true,
		"fp_grid": true,
		"fp_pixel_size": ps,
		"fp_height": center_y,
		"fp_outline_size": int(_meta.get("fp_outline_size", 10)),
	}
