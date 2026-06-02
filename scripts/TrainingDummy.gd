extends CharacterBody2D

# Training dummy for the Wizard Village. Soaks every attack, never dies, and
# shows a rolling 5-second DPS readout above its head so the player can
# benchmark weapon / stat / wand-flaw combinations in a controlled space.
#
# Extends CharacterBody2D (not StaticBody2D) because Projectile._on_body_entered
# routes any StaticBody2D body to the wall-bounce/wall-damage branch — a
# StaticBody2D dummy would never reach the "enemy" branch even though it's in
# the enemy group. CharacterBody2D skips that branch and the projectile falls
# through to the enemy-hit path. The dummy never calls move_and_slide so it
# sits in place like a true static target.

const DPS_WINDOW: float = 5.0   # seconds of damage history averaged for DPS
const DUMMY_ART: String = "[O_O]\n |Y| \n /_\\ "

var max_health: int = 999_999_999
var health: int     = 999_999_999
var is_elite: bool      = false
var is_champion: bool   = false
var elite_modifier: int = 0
var _has_aggro: bool    = true   # always "aggro'd" so probe queries don't skip
var passive: bool       = false

# (timestamp_ms, damage) entries, evicted from the front once older than DPS_WINDOW.
var _events: Array = []
var _peak_dps: float = 0.0
var _total_damage_session: int = 0

var _ascii: Label = null
var _lbl: Label   = null

func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 2
	collision_mask = 0
	z_index = 1

	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(36, 44)
	cs.shape = rect
	add_child(cs)

	# Body ASCII — the FP rig reads this Label's .text live each frame, so
	# stuffing the DPS readout into the first row makes it show above the
	# dummy's head in both 2D and first-person.
	_ascii = Label.new()
	_ascii.name = "AsciiChar"
	_ascii.add_theme_font_override("font", MonoFont.get_font())
	_ascii.add_theme_font_size_override("font_size", 14)
	_ascii.add_theme_color_override("font_color", Color(0.95, 0.82, 0.55))
	_ascii.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_ascii.add_theme_constant_override("outline_size", 2)
	_ascii.add_theme_constant_override("line_separation", -2)
	_ascii.text = DUMMY_ART
	_ascii.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ascii.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_ascii.size = Vector2(80, 64)
	_ascii.position = Vector2(-40, -22)
	_ascii.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ascii)

	# DPS readout — separate Label so we can color it independently from the
	# body art. Renders above the head in 2D; FP picks up the same readout
	# via the AsciiChar text prefix below.
	_lbl = Label.new()
	_lbl.add_theme_font_override("font", MonoFont.get_font())
	_lbl.add_theme_font_size_override("font_size", 14)
	_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.35))
	_lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_lbl.add_theme_constant_override("outline_size", 2)
	_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl.size = Vector2(180, 18)
	_lbl.position = Vector2(-90, -54)
	_lbl.text = "DPS: 0"
	_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lbl)

	# Tag for FP rig so the dummy is rendered as a billboard in first-person.
	set_meta("fp_multiline", true)
	GameState.attach_fp_visual(self, DUMMY_ART, Color(0.95, 0.82, 0.55), 0.45)

func _process(_delta: float) -> void:
	var now_ms := Time.get_ticks_msec()
	var cutoff: int = now_ms - int(DPS_WINDOW * 1000.0)
	while _events.size() > 0 and int(_events[0][0]) < cutoff:
		_events.pop_front()
	var sum: int = 0
	for e in _events:
		sum += int(e[1])
	var dps: float = float(sum) / DPS_WINDOW
	if dps > _peak_dps:
		_peak_dps = dps
	_update_readout(dps)

func _update_readout(dps: float) -> void:
	if _lbl != null:
		_lbl.text = "DPS: %d   peak: %d" % [int(round(dps)), int(round(_peak_dps))]
	if _ascii != null:
		# Prepend the DPS row to the ASCII body so the FP rig (which reads
		# live_text from AsciiChar each frame) shows the readout above the
		# dummy in first-person too. No fp_visual re-registration needed.
		_ascii.text = "DPS:%d\n%s" % [int(round(dps)), DUMMY_ART]

# Projectile / melee / hazard damage all funnels through here. We log every
# hit into the rolling window, suppress death, and let the player keep
# benching forever.
func take_damage(amount: int, _source: Variant = null) -> void:
	if amount <= 0:
		return
	_events.append([Time.get_ticks_msec(), amount])
	_total_damage_session += amount
	if health <= 0:
		health = max_health
	FloatingText.spawn(global_position, amount, false, get_tree().current_scene)

# Swallow status effects silently — a frozen / stunned dummy would skew DPS
# measurements (frozen targets take amplified damage; stunned targets stop
# triggering some effects). Burn/poison ticks still hit via take_damage.
func apply_status(_effect: String, _stacks: float) -> void:
	pass

func heal(_amount: int) -> void:
	pass

func apply_buff(_duration: float) -> void:
	pass
