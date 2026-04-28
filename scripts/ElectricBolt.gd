class_name ElectricBolt
extends Label

# Overlay attached to a host enemy when it gets ELECTRIFIED. Pulses 1–3
# times: each pulse stuns the host for ~PULSE_TIME and shows a flickering
# lightning glyph; between pulses the host briefly regains agency. After
# the last pulse the overlay frees itself.
#
# Usage: ElectricBolt.trigger(host) — call after the 10-stack proc instead
# of setting _stun_timer/_no_attack_timer directly. Reads/writes the
# host's `_stun_timer` field by reflection so it works for every enemy
# script without needing a shared base class.

const PULSE_TIME := 0.35
const GAP_TIME   := 0.40
const BOLT_F0    := "~Z~"
const BOLT_F1    := "Z~Z"

# Owner-side state — kept on the overlay node so the host doesn't need
# any new fields to participate.
var _host: Node             = null
var _pulses_remaining: int  = 1
var _phase_t: float         = 0.0
var _in_pulse: bool         = true
var _anim_t: float          = 0.0
var _frame: int             = 0

static var _shared_font: Font = null

# Public entry point. Idempotent: re-triggering on an already-electrified
# host re-rolls the pulse count and restarts the cycle from a fresh pulse.
static func trigger(host: Node) -> void:
	if not is_instance_valid(host):
		return
	var existing := host.get_node_or_null("ElectricBolt")
	if existing != null:
		existing._pulses_remaining = randi_range(1, 3)
		existing._phase_t = PULSE_TIME
		existing._in_pulse = true
		existing.modulate.a = 1.0
		host.set("_stun_timer", maxf(float(host.get("_stun_timer")), PULSE_TIME))
		return
	var b := ElectricBolt.new()
	b.name = "ElectricBolt"
	b._pulses_remaining = randi_range(1, 3)
	host.add_child(b)

func _ready() -> void:
	if _shared_font == null:
		_shared_font = MonoFont.get_font()
	add_theme_font_override("font", _shared_font)
	add_theme_font_size_override("font_size", 16)
	add_theme_color_override("font_color", Color(0.95, 0.95, 0.30))
	add_theme_color_override("font_outline_color", Color(0.40, 0.30, 0.0))
	add_theme_constant_override("outline_size", 2)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	# Sit just above the entity's head so the bolt never covers the
	# silhouette but reads as "lightning crackling on this guy".
	offset_left   = -22.0
	offset_top    = -42.0
	offset_right  =  22.0
	offset_bottom = -16.0
	text = BOLT_F0
	z_index = 3
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host = get_parent()
	_phase_t = PULSE_TIME
	_in_pulse = true
	if is_instance_valid(_host):
		_host.set("_stun_timer", maxf(float(_host.get("_stun_timer")), PULSE_TIME))

func _process(delta: float) -> void:
	# Glyph flicker — fast frame swap so the bolt looks alive even during
	# the short pulse window.
	_anim_t += delta
	if _anim_t >= 0.07:
		_anim_t = 0.0
		_frame = 1 - _frame
		text = BOLT_F0 if _frame == 0 else BOLT_F1

	_phase_t -= delta
	if _phase_t > 0.0:
		return

	if _in_pulse:
		# End this pulse. If pulses remain, drop into the gap; otherwise
		# the entire ELECTRIFIED debuff is over.
		_pulses_remaining -= 1
		if _pulses_remaining <= 0:
			queue_free()
			return
		_in_pulse = false
		_phase_t = GAP_TIME
		modulate.a = 0.0   # vanish during the gap so the player sees a beat
	else:
		# Start the next pulse — re-stun host and reveal the glyph.
		_in_pulse = true
		_phase_t = PULSE_TIME
		modulate.a = 1.0
		if is_instance_valid(_host):
			_host.set("_stun_timer", maxf(float(_host.get("_stun_timer")), PULSE_TIME))
