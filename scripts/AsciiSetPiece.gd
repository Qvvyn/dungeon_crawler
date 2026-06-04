extends CanvasLayer
class_name AsciiSetPiece

# Full-screen display for LARGE curated ASCII art (title screen, boss reveal,
# NPC portrait, death screen). Completely separate from the entity sprite
# system (AsciiSprites / AsciiSpriteDriver): different scale, different
# lifecycle, never registered with the first-person rig.
#
# Art is plain .txt in res://assets/ascii/ (loaded via FileAccess) so curated
# pieces can be pasted in verbatim — no backslash escaping like the inline
# entity frames need. Optional animation: separate frames in the file with a
# line containing only "---" and pass animate=true.

@export var font_size: int = 16
@export var frame_interval: float = 0.28

var _label: Label = null
var _frames: PackedStringArray = PackedStringArray()
var _frame_idx: int = 0
var _anim_t: float = 0.0
var _animating: bool = false

func _ready() -> void:
	if _label == null:
		_build_label()
	set_process(false)

func _build_label() -> void:
	_label = Label.new()
	_label.name = "Art"
	_label.add_theme_font_override("font", MonoFont.get_font())
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_constant_override("line_separation", -2)
	_label.add_theme_constant_override("outline_size", 4)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

# Show art loaded from a res:// .txt file. Frames split on lines == "---".
func show_file(path: String, color: Color = Color.WHITE, animate: bool = false) -> void:
	if not FileAccess.file_exists(path):
		push_warning("AsciiSetPiece: missing art file %s" % path)
		return
	var text := FileAccess.get_file_as_string(path)
	show_text(text, color, animate)

# Show art from an in-memory string (e.g. a const). Same "---" frame split.
func show_text(text: String, color: Color = Color.WHITE, animate: bool = false) -> void:
	if _label == null:
		_build_label()
	_frames = _split_frames(text)
	# Pad to equal-width lines so center alignment preserves the column grid
	# (otherwise short top rows drift right relative to wide rows).
	for i in _frames.size():
		_frames[i] = AsciiSprites.pad_block(_frames[i])
	if _frames.is_empty():
		return
	_label.add_theme_color_override("font_color", color)
	_label.add_theme_font_override("font", MonoFont.get_font())  # pick up live font choice
	_frame_idx = 0
	_anim_t = 0.0
	_animating = animate and _frames.size() > 1
	_label.text = _frames[0]
	_label.visible = true
	set_process(_animating)

func hide_piece() -> void:
	if _label != null:
		_label.visible = false
	set_process(false)

func _split_frames(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var cur: Array = []
	for line in text.split("\n"):
		if (line as String).strip_edges() == "---":
			out.append("\n".join(cur))
			cur.clear()
		else:
			cur.append(line)
	if not cur.is_empty():
		out.append("\n".join(cur))
	return out

func _process(delta: float) -> void:
	if not _animating:
		return
	_anim_t += delta
	if _anim_t < frame_interval:
		return
	_anim_t = 0.0
	_frame_idx = (_frame_idx + 1) % _frames.size()
	_label.text = _frames[_frame_idx]
