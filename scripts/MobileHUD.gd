extends CanvasLayer

# Touch-only HUD: virtual movement stick on the left, plus a single
# auto-engage toggle on the bottom-right. Player.gd instantiates this
# when GameState.is_mobile is true.
#
# Movement: drives the existing move_* input actions via Input.action_press
# / action_release so the rest of the game code is input-source agnostic.
# Combat: tap the AUTO button to toggle Player._mobile_auto_combat — when
# on, the player auto-aims + auto-shoots at visible enemies while the
# human still drives movement via the joystick.

const STICK_BASE_R := 70.0   # max radius the knob can travel from origin
const STICK_DEAD   := 0.20   # below this normalized magnitude, no movement
const STICK_THRESH := 0.30   # axis threshold for committing a move action

var _stick_root: Control       = null
var _stick_base_label: Label   = null
var _stick_knob_label: Label   = null
var _stick_finger: int         = -1
var _stick_origin: Vector2     = Vector2.ZERO   # where the touch started
var _stick_base_center: Vector2 = Vector2.ZERO  # in stick_root coords

var _auto_btn: Button         = null
var _auto_btn_label: Label    = null
var _auto_state: bool         = false

# Second toggle: full autoplay (the same mode KEY_0 enables on desktop).
# Mutually exclusive with the auto-aim toggle above — full autoplay drives
# movement too, so the auto-aim flag becomes redundant when this is on.
var _full_auto_btn: Button         = null
var _full_auto_btn_label: Label    = null
var _full_auto_state: bool         = false

# Wand randomizer between the two auto toggles. Tap to roll a fresh
# random wand from the full pool — useful on mobile where there's no
# keyboard shortcut for the debug shuffle.
var _wand_btn: Button         = null
var _wand_btn_label: Label    = null

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()

func _build() -> void:
	var root := Control.new()
	root.anchor_left   = 0.0
	root.anchor_top    = 0.0
	root.anchor_right  = 1.0
	root.anchor_bottom = 1.0
	root.mouse_filter  = Control.MOUSE_FILTER_IGNORE   # let touches fall through
	add_child(root)
	_build_stick(root)
	_build_auto_button(root)
	_build_wand_button(root)
	_build_full_auto_button(root)
	_build_pause_button(root)

# ── Virtual joystick ───────────────────────────────────────────────────────

func _build_stick(parent: Control) -> void:
	# Touch zone: bottom-left, but pulled in from the corner along both axes
	# so the player's thumb has room to maneuver instead of cramping into
	# the screen edge. The visual base sits roughly in the middle of the
	# zone — that's the rest position; the actual stick origin is wherever
	# the user puts their thumb, so the entire zone is forgiving.
	_stick_root = Control.new()
	_stick_root.anchor_left   = 0.0
	_stick_root.anchor_top    = 0.4
	_stick_root.anchor_right  = 0.5
	_stick_root.anchor_bottom = 1.0
	_stick_root.offset_left   = 0.0
	_stick_root.offset_top    = 0.0
	_stick_root.offset_right  = 0.0
	_stick_root.offset_bottom = 0.0
	_stick_root.mouse_filter  = Control.MOUSE_FILTER_STOP
	_stick_root.gui_input.connect(_on_stick_gui_input)
	parent.add_child(_stick_root)

	_stick_base_label = Label.new()
	_stick_base_label.text = "(  )"
	_stick_base_label.add_theme_font_override("font", MonoFont.get_font())
	_stick_base_label.add_theme_font_size_override("font_size", 96)
	_stick_base_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.32))
	_stick_base_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.6))
	_stick_base_label.add_theme_constant_override("outline_size", 2)
	_stick_base_label.size = Vector2(180, 180)
	_stick_base_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stick_base_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_stick_base_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_root.add_child(_stick_base_label)

	_stick_knob_label = Label.new()
	_stick_knob_label.text = "*"
	_stick_knob_label.add_theme_font_override("font", MonoFont.get_font())
	_stick_knob_label.add_theme_font_size_override("font_size", 56)
	_stick_knob_label.add_theme_color_override("font_color", Color(0.85, 0.65, 1.0, 0.85))
	_stick_knob_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.7))
	_stick_knob_label.add_theme_constant_override("outline_size", 2)
	_stick_knob_label.size = Vector2(80, 80)
	_stick_knob_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stick_knob_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_stick_knob_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_root.add_child(_stick_knob_label)

	# Hidden until the player taps somewhere — the stick spawns at the
	# touch point so the thumb never has to hunt for a fixed home.
	_stick_base_label.visible = false
	_stick_knob_label.visible = false

func _show_stick_at(point: Vector2) -> void:
	# Re-anchor the visual stick to the supplied point in stick_root local
	# coords. Called every time a new touch begins so the base appears
	# under the player's thumb, wherever in the touch zone they tap.
	_stick_base_center = point
	if _stick_base_label != null:
		_stick_base_label.position = _stick_base_center - _stick_base_label.size * 0.5
		_stick_base_label.visible = true
	if _stick_knob_label != null:
		_stick_knob_label.position = _stick_base_center - _stick_knob_label.size * 0.5
		_stick_knob_label.visible = true

func _hide_stick() -> void:
	if _stick_base_label != null:
		_stick_base_label.visible = false
	if _stick_knob_label != null:
		_stick_knob_label.visible = false

func _on_stick_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var ev := event as InputEventScreenTouch
		if ev.pressed:
			if _stick_finger == -1:
				_stick_finger = ev.index
				_stick_origin = ev.position
				_show_stick_at(ev.position)
				_apply_stick(Vector2.ZERO)
		elif ev.index == _stick_finger:
			_stick_finger = -1
			_release_all_move_actions()
			_hide_stick()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _stick_finger:
			var off: Vector2 = drag.position - _stick_origin
			_apply_stick(off)

func _apply_stick(offset_from_origin: Vector2) -> void:
	var clamped: Vector2 = offset_from_origin.limit_length(STICK_BASE_R)
	if _stick_knob_label != null:
		_stick_knob_label.position = (_stick_base_center + clamped) - _stick_knob_label.size * 0.5
	var norm: Vector2 = offset_from_origin / STICK_BASE_R
	if norm.length() < STICK_DEAD:
		_release_all_move_actions()
		return
	_set_move("move_right", norm.x >  STICK_THRESH)
	_set_move("move_left",  norm.x < -STICK_THRESH)
	_set_move("move_down",  norm.y >  STICK_THRESH)
	_set_move("move_up",    norm.y < -STICK_THRESH)

func _set_move(action: String, pressed: bool) -> void:
	if not InputMap.has_action(action):
		return
	if pressed and not Input.is_action_pressed(action):
		Input.action_press(action)
	elif not pressed and Input.is_action_pressed(action):
		Input.action_release(action)

func _release_all_move_actions() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		if InputMap.has_action(a) and Input.is_action_pressed(a):
			Input.action_release(a)

# ── Auto-engage button (bottom-right) ──────────────────────────────────────

func _build_auto_button(parent: Control) -> void:
	# Auto-aim toggle (top of the bottom-right corner stack).
	_auto_btn_label = _make_corner_label("[ AUTO ]", -640.0, -460.0, 26)
	parent.add_child(_auto_btn_label)
	_auto_btn = _make_corner_button(-640.0, -460.0)
	_auto_btn.pressed.connect(_toggle_auto)
	parent.add_child(_auto_btn)
	_refresh_auto_visual()

func _build_wand_button(parent: Control) -> void:
	# Wand randomizer (middle slot). One-shot tap — equips a random wand
	# from the full pool. Calls Player._debug_random_wand which already
	# handles the inventory swap, equip-stat refresh, and floating-text
	# announce. No state to display — it's an action button, not a toggle.
	_wand_btn_label = _make_corner_label("[ WAND? ]", -440.0, -260.0, 26)
	_wand_btn_label.add_theme_color_override("font_color", Color(0.85, 0.7, 1.0))
	parent.add_child(_wand_btn_label)
	_wand_btn = _make_corner_button(-440.0, -260.0)
	_wand_btn.pressed.connect(_press_wand)
	parent.add_child(_wand_btn)

func _build_full_auto_button(parent: Control) -> void:
	# Full autoplay toggle — same effect as KEY_0 on desktop. Sits at the
	# bottom (most thumb-reachable). Mutually exclusive with the auto-aim
	# flag (full autoplay is a strict superset that also drives movement
	# / pathing / perks).
	_full_auto_btn_label = _make_corner_label("[ FULL AUTO ]", -240.0, -60.0, 24)
	parent.add_child(_full_auto_btn_label)
	_full_auto_btn = _make_corner_button(-240.0, -60.0)
	_full_auto_btn.pressed.connect(_toggle_full_auto)
	parent.add_child(_full_auto_btn)
	_refresh_full_auto_visual()

func _press_wand() -> void:
	var p := get_parent()
	if p != null and p.has_method("_debug_random_wand"):
		p.call("_debug_random_wand")
	# Brief visual punch — fade the label momentarily so the player gets
	# tap feedback even though there's no persistent toggled state.
	if _wand_btn_label != null:
		var tw := create_tween()
		tw.tween_property(_wand_btn_label, "modulate:a", 0.4, 0.08)
		tw.tween_property(_wand_btn_label, "modulate:a", 1.0, 0.18)

# Bottom-right corner control factories. The two action toggles share the
# same anchoring pattern; only their vertical offsets differ.
func _make_corner_label(text: String, off_top: float, off_bottom: float, font_sz: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", MonoFont.get_font())
	lbl.add_theme_font_size_override("font_size", font_sz)
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.anchor_left   = 1.0
	lbl.anchor_right  = 1.0
	lbl.anchor_top    = 1.0
	lbl.anchor_bottom = 1.0
	lbl.offset_left   = -260.0
	lbl.offset_top    = off_top
	lbl.offset_right  = -40.0
	lbl.offset_bottom = off_bottom
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

func _make_corner_button(off_top: float, off_bottom: float) -> Button:
	var btn := Button.new()
	btn.text = ""
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.anchor_left   = 1.0
	btn.anchor_right  = 1.0
	btn.anchor_top    = 1.0
	btn.anchor_bottom = 1.0
	btn.offset_left   = -260.0
	btn.offset_top    = off_top
	btn.offset_right  = -40.0
	btn.offset_bottom = off_bottom
	return btn

func _toggle_auto() -> void:
	_auto_state = not _auto_state
	# Turning auto-aim on while full autoplay is active is redundant;
	# turn full autoplay off so the buttons can't both be lit.
	if _auto_state and _full_auto_state:
		_full_auto_state = false
		_refresh_full_auto_visual()
		var p_full := get_parent()
		if p_full != null and p_full.has_method("_set_autoplay"):
			p_full.call("_set_autoplay", false)
	_refresh_auto_visual()
	var p := get_parent()
	if p != null and p.has_method("set_mobile_auto_combat"):
		p.set_mobile_auto_combat(_auto_state)

func _toggle_full_auto() -> void:
	_full_auto_state = not _full_auto_state
	# Full autoplay is a superset of auto-aim — clear the redundant flag
	# when entering full autoplay.
	if _full_auto_state and _auto_state:
		_auto_state = false
		_refresh_auto_visual()
		var p_aim := get_parent()
		if p_aim != null and p_aim.has_method("set_mobile_auto_combat"):
			p_aim.set_mobile_auto_combat(false)
	_refresh_full_auto_visual()
	var p := get_parent()
	if p != null and p.has_method("_set_autoplay"):
		p.call("_set_autoplay", _full_auto_state)

func _refresh_auto_visual() -> void:
	if _auto_btn_label == null:
		return
	if _auto_state:
		_auto_btn_label.text = "[ AUTO • ON ]"
		_auto_btn_label.add_theme_color_override("font_color", Color(0.45, 1.0, 0.55))
	else:
		_auto_btn_label.text = "[ AUTO ]"
		_auto_btn_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))

func _refresh_full_auto_visual() -> void:
	if _full_auto_btn_label == null:
		return
	if _full_auto_state:
		_full_auto_btn_label.text = "[ FULL AUTO • ON ]"
		_full_auto_btn_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	else:
		_full_auto_btn_label.text = "[ FULL AUTO ]"
		_full_auto_btn_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))

# ── Pause button (top-right) ───────────────────────────────────────────────

func _build_pause_button(parent: Control) -> void:
	var lbl := Label.new()
	lbl.text = "[ II ]"
	lbl.add_theme_font_override("font", MonoFont.get_font())
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.anchor_left   = 1.0
	lbl.anchor_right  = 1.0
	lbl.anchor_top    = 0.0
	lbl.anchor_bottom = 0.0
	lbl.offset_left   = -110.0
	lbl.offset_top    = 30.0
	lbl.offset_right  = -30.0
	lbl.offset_bottom = 90.0
	lbl.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	parent.add_child(lbl)

	var btn := Button.new()
	btn.text = ""
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.anchor_left   = 1.0
	btn.anchor_right  = 1.0
	btn.anchor_top    = 0.0
	btn.anchor_bottom = 0.0
	btn.offset_left   = -110.0
	btn.offset_top    = 30.0
	btn.offset_right  = -30.0
	btn.offset_bottom = 90.0
	btn.pressed.connect(_send_pause_key)
	parent.add_child(btn)

func _send_pause_key() -> void:
	var press := InputEventKey.new()
	press.physical_keycode = KEY_ESCAPE
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventKey.new()
	release.physical_keycode = KEY_ESCAPE
	release.pressed = false
	Input.parse_input_event(release)
