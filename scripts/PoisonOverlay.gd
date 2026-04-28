class_name PoisonOverlay
extends Label

# Status overlay attached to a POISONED enemy. Completes the status-effect
# overlay family alongside FrozenBlock / EnflameOverlay / ElectricBolt.
# The host's `_tick_status` still ticks the poison damage; this is purely
# a visual marker so the player can read poison at a glance.

const DRIP_F0 := "~ ~"
const DRIP_F1 := " ~ "
const DRIP_F2 := "~ ~"
const DRIP_F3 := "~~~"

static var _shared_font: Font = null

var _anim_t: float = 0.0
var _frame: int    = 0

# Idempotent on no-op frames — only allocates when poisoned actually flips.
static func sync_to(host: Node, poisoned: bool) -> void:
	if not is_instance_valid(host):
		return
	var existing := host.get_node_or_null("PoisonOverlay") as Label
	if poisoned:
		if existing == null:
			var ov := PoisonOverlay.new()
			ov.name = "PoisonOverlay"
			host.add_child(ov)
	elif existing != null:
		existing.queue_free()

func _ready() -> void:
	if _shared_font == null:
		_shared_font = MonoFont.get_font()
	add_theme_font_override("font", _shared_font)
	add_theme_font_size_override("font_size", 14)
	add_theme_color_override("font_color", Color(0.45, 1.0, 0.55))
	add_theme_color_override("font_outline_color", Color(0.0, 0.30, 0.05))
	add_theme_constant_override("outline_size", 2)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	# Sit a little lower than fire/electric so multiple overlays don't
	# stack on the same row above the head — venom drips read as falling.
	offset_left   = -22.0
	offset_top    = -28.0
	offset_right  =  22.0
	offset_bottom =  -8.0
	text = DRIP_F0
	z_index = 3
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_anim_t += delta
	if _anim_t >= 0.18:
		_anim_t = 0.0
		_frame = (_frame + 1) % 4
		match _frame:
			0: text = DRIP_F0
			1: text = DRIP_F1
			2: text = DRIP_F2
			3: text = DRIP_F3
