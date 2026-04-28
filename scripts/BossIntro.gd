class_name BossIntro
extends RefCounted

# Boss-spawn banner card. Big centered ASCII frame holds the boss's name
# for ~1.5 s, then fades + frees. Each boss script calls
# BossIntro.show_for(name, color) from its _ready().

const TOP    := "┌─────────────────────────────────┐"
const BOT    := "└─────────────────────────────────┘"
const HOLD_T := 1.5
const FADE_T := 0.5

static var _shared_font: Font = null

static func _font() -> Font:
	if _shared_font == null:
		_shared_font = MonoFont.get_font()
	return _shared_font

static func show_for(scene_root: Node, boss_name: String, color: Color) -> void:
	if not is_instance_valid(scene_root) or not scene_root.is_inside_tree():
		return
	# CanvasLayer keeps the banner camera-anchored.
	var cl := CanvasLayer.new()
	cl.layer = 22
	scene_root.add_child(cl)

	var banner := Label.new()
	# Manually pad the boss name to 31 chars so the banner box stays
	# aligned (GDScript String has no .center()).
	var padded := boss_name
	var box_w := 31
	if padded.length() < box_w:
		var total_pad: int = box_w - padded.length()
		var left_pad: int = total_pad / 2
		var right_pad: int = total_pad - left_pad
		padded = " ".repeat(left_pad) + padded + " ".repeat(right_pad)
	banner.text = "%s\n│ %s │\n%s" % [TOP, padded, BOT]
	banner.add_theme_font_override("font", _font())
	banner.add_theme_font_size_override("font_size", 22)
	banner.add_theme_color_override("font_color", color)
	banner.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	banner.add_theme_constant_override("outline_size", 3)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	# Anchored to the bottom edge so the banner tracks the boss healthbar
	# (which is also bottom-anchored). The boss name label sits 92 px above
	# the bottom; the banner's bottom edge ends 100 px above bottom, leaving
	# an 8 px gap. On tall browser windows the banner stays glued just
	# above the bar instead of floating in the middle of the screen.
	banner.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	banner.offset_top    = -200.0
	banner.offset_bottom = -100.0
	banner.modulate.a = 0.0
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(banner)

	# Fade in → hold → fade out → free
	var tw := banner.create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, 0.30)
	tw.tween_interval(HOLD_T)
	tw.tween_property(banner, "modulate:a", 0.0, FADE_T)
	tw.tween_callback(cl.queue_free)
