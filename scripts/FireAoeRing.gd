class_name FireAoeRing
extends Node2D

# Visualizes the splash radius of the fire-flare AoE that triggers when an
# already-enflamed enemy is hit again. Attached/removed by EnflameOverlay
# alongside the small head-flame overlay so it shares the enflamed
# lifecycle.
#
# Renders the radius with multi-line ASCII flames (same style as the old
# ground FirePatch) so the visual reads as fire instead of a flat ring.
# pulse() brightens + slightly enlarges the flames briefly when the flare
# AoE actually triggers.

# Mirrors EnflameOverlay.REFRESH_RADIUS — kept in sync manually since both
# files are tiny and a cross-import isn't worth the coupling.
const RADIUS         := 80.0
const PULSE_DURATION := 0.45

const FLAME_F0 := " )( )( ,(\n((()(())\n)(())(((\n  ()((\n   ))"
const FLAME_F1 := " ,) )(  )\n)(()(()\n((((())(\n  (()((\n   ((  "

var _pulse_t: float  = 0.0
var _anim_t: float   = 0.0
var _frame: int      = 0
var _label: Label    = null

func _ready() -> void:
	z_index = -1
	_label = Label.new()
	_label.add_theme_font_override("font", MonoFont.get_font())
	# 1/4 the previous linear size — flames now read as a small fire patch
	# instead of swallowing the whole AoE area.
	_label.add_theme_font_size_override("font_size", maxi(9, int(RADIUS * 0.11)))
	_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.05))
	_label.add_theme_color_override("font_outline_color", Color(0.45, 0.05, 0.0))
	_label.add_theme_constant_override("outline_size", 1)
	_label.add_theme_constant_override("line_separation", -1)
	_label.size = Vector2(RADIUS * 0.6, RADIUS * 0.6)
	_label.position = Vector2(-RADIUS * 0.3, -RADIUS * 0.3)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_label.modulate = Color(1.0, 1.0, 1.0, 0.85)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.text = FLAME_F0
	add_child(_label)

func _process(delta: float) -> void:
	# Frame swap for the flame flicker.
	_anim_t += delta
	if _anim_t >= 0.16:
		_anim_t = 0.0
		_frame = 1 - _frame
		_label.text = FLAME_F0 if _frame == 0 else FLAME_F1
	# Pulse brighten + scale on flare trigger.
	if _pulse_t > 0.0:
		_pulse_t = maxf(0.0, _pulse_t - delta)
		var t: float = _pulse_t / PULSE_DURATION
		_label.modulate = Color(1.0, 0.6 + 0.4 * t, 0.05 + 0.5 * t, 0.85 + 0.15 * t)
		_label.scale = Vector2.ONE * (1.0 + 0.18 * t)
	else:
		_label.modulate = Color(1.0, 0.55, 0.05, 0.78)
		_label.scale = Vector2.ONE

func pulse() -> void:
	_pulse_t = PULSE_DURATION
