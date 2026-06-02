extends Node2D

# Wall-to-wall beam trap. Fires a damaging beam across a corridor when the
# player approaches. Must dash through it (dash invincibility bypasses damage).
# low_beam variant sits at floor height and can also be avoided by levitating.
#
# Set these properties BEFORE add_child so _ready() sizes collision correctly:
#   beam_axis        0 = N-S beam in EW corridor, 1 = EW beam in NS corridor
#   beam_half_width  pixels from trap center to each wall face (typically 48)
#   low_beam         true = floor-level beam, bypassed by levitation

var beam_axis: int          = 0
var beam_half_width: float  = 48.0
var low_beam: bool          = false

const WARN_TIME     := 1.6
const FIRE_TIME     := 0.8
const COOLDOWN_TIME := 5.0
const DAMAGE        := 3
const TICK_RATE     := 0.25

enum State { IDLE, WARNING, FIRE, COOLDOWN }
var _state: State    = State.IDLE
var _timer: float    = 0.0
var _tick_t: float   = 0.0

var _marker_a: Label   = null
var _marker_b: Label   = null
var _beam_line: Line2D = null

var _trigger_area: Area2D  = null
var _beam_area: Area2D     = null
var _players_in_beam: Array[Node2D] = []

static var _shared_font: Font = null

func _ready() -> void:
	add_to_group("trap")
	if _shared_font == null:
		_shared_font = MonoFont.get_font()

	# Sizes depend on orientation.
	# beam_axis 0: beam goes along local Y (N-S), corridor along local X (EW).
	# beam_axis 1: beam goes along local X (EW), corridor along local Y (NS).
	var beam_w: float  = beam_half_width * 2.0   # wall-to-wall span
	var beam_d: float  = 24.0                     # depth of damage zone
	var trig_d: float  = 112.0                    # approach detection depth

	# --- Trigger area (detects player approaching from either side) ---
	_trigger_area = Area2D.new()
	_trigger_area.name = "TriggerArea"
	_trigger_area.collision_layer = 0
	_trigger_area.collision_mask  = 1   # player layer
	var trig_shape := CollisionShape2D.new()
	var trig_rect  := RectangleShape2D.new()
	if beam_axis == 0:
		trig_rect.size = Vector2(trig_d, beam_w)
	else:
		trig_rect.size = Vector2(beam_w, trig_d)
	trig_shape.shape = trig_rect
	_trigger_area.add_child(trig_shape)
	add_child(_trigger_area)
	_trigger_area.body_entered.connect(_on_trigger_entered)

	# --- Beam damage area (thin line, wall-to-wall) ---
	_beam_area = Area2D.new()
	_beam_area.name = "BeamArea"
	_beam_area.collision_layer = 0
	_beam_area.collision_mask  = 1
	var beam_shape := CollisionShape2D.new()
	var beam_rect  := RectangleShape2D.new()
	if beam_axis == 0:
		beam_rect.size = Vector2(beam_d, beam_w)
	else:
		beam_rect.size = Vector2(beam_w, beam_d)
	beam_shape.shape = beam_rect
	_beam_area.add_child(beam_shape)
	add_child(_beam_area)
	_beam_area.body_entered.connect(_on_beam_entered)
	_beam_area.body_exited.connect(_on_beam_exited)
	# Beam area only active when firing — disable until then.
	_beam_area.monitoring = false

	# --- Wall markers ---
	_marker_a = _make_marker()
	_marker_b = _make_marker()
	add_child(_marker_a)
	add_child(_marker_b)
	_position_markers()

	# --- Beam line (2D visual) ---
	_beam_line = Line2D.new()
	_beam_line.width = 3.0
	_beam_line.default_color = Color(1.0, 0.42, 0.0, 0.9)
	_beam_line.visible = false
	var inset := beam_half_width - 4.0   # slightly inside the wall face
	if beam_axis == 0:
		_beam_line.add_point(Vector2(0.0, -inset))
		_beam_line.add_point(Vector2(0.0,  inset))
	else:
		_beam_line.add_point(Vector2(-inset, 0.0))
		_beam_line.add_point(Vector2( inset, 0.0))
	add_child(_beam_line)

	_set_idle()

func _make_marker() -> Label:
	var lbl := Label.new()
	lbl.add_theme_font_override("font", _shared_font)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.size = Vector2(16.0, 16.0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.z_index = 2
	return lbl

func _position_markers() -> void:
	var offset := beam_half_width - 10.0
	if beam_axis == 0:
		_marker_a.position = Vector2(-8.0, -offset - 8.0)
		_marker_b.position = Vector2(-8.0,  offset - 8.0)
	else:
		_marker_a.position = Vector2(-offset - 8.0, -8.0)
		_marker_b.position = Vector2( offset - 8.0, -8.0)

func _process(delta: float) -> void:
	match _state:
		State.WARNING:
			_timer -= delta
			var t := clampf(1.0 - (_timer / WARN_TIME), 0.0, 1.0)
			var r  := lerpf(0.6, 1.0, t)
			var g  := lerpf(0.5, 0.1, t)
			var col := Color(r, g, 0.0)
			_marker_a.add_theme_color_override("font_color", col)
			_marker_b.add_theme_color_override("font_color", col)
			# Update FP telegraph beam each frame.
			_update_fp_beam(true, Color(1.0, 0.55, 0.05, 0.5))
			if _timer <= 0.0:
				_enter_fire()

		State.FIRE:
			_timer -= delta
			_tick_t -= delta
			if _tick_t <= 0.0:
				_tick_t = TICK_RATE
				_tick_damage()
			_update_fp_beam(false, Color(1.0, 0.42, 0.0, 1.0))
			if _timer <= 0.0:
				_enter_cooldown()

		State.COOLDOWN:
			_timer -= delta
			if _timer <= 0.0:
				_set_idle()

func _on_trigger_entered(body: Node2D) -> void:
	if _state != State.IDLE:
		return
	if not body.is_in_group("player"):
		return
	_enter_warning()

func _on_beam_entered(body: Node2D) -> void:
	if body.is_in_group("player") and not _players_in_beam.has(body):
		_players_in_beam.append(body)

func _on_beam_exited(body: Node2D) -> void:
	_players_in_beam.erase(body)

func _enter_warning() -> void:
	_state = State.WARNING
	_timer = WARN_TIME
	_marker_a.text = "X"
	_marker_b.text = "X"

func _enter_fire() -> void:
	_state  = State.FIRE
	_timer  = FIRE_TIME
	_tick_t = 0.0
	_beam_line.visible = true
	_beam_area.monitoring = true
	_marker_a.add_theme_color_override("font_color", Color(1.0, 0.15, 0.0))
	_marker_b.add_theme_color_override("font_color", Color(1.0, 0.15, 0.0))
	FloatingText.spawn_str(global_position, "BEAM!", Color(1.0, 0.45, 0.0),
		get_tree().current_scene)

func _enter_cooldown() -> void:
	_state = State.COOLDOWN
	_timer = COOLDOWN_TIME
	_beam_line.visible = false
	_beam_area.monitoring = false
	_players_in_beam.clear()
	_clear_fp_beam()
	_set_idle()

func _set_idle() -> void:
	_state = State.IDLE
	if _marker_a:
		_marker_a.text = "·"
		_marker_a.add_theme_color_override("font_color", Color(0.50, 0.35, 0.20, 0.60))
	if _marker_b:
		_marker_b.text = "·"
		_marker_b.add_theme_color_override("font_color", Color(0.50, 0.35, 0.20, 0.60))
	if _beam_line:
		_beam_line.visible = false
	if _beam_area:
		_beam_area.monitoring = false

func _tick_damage() -> void:
	var ply: Node2D = null
	for body: Node2D in _players_in_beam:
		if is_instance_valid(body) and body.is_in_group("player"):
			ply = body
			break
	if ply == null:
		return
	if ply.get("_is_invincible"):
		return
	if low_beam and ply.get("_is_levitating"):
		return
	if ply.has_method("take_damage"):
		ply.take_damage(DAMAGE, self)

func _end_a() -> Vector2:
	var offset := beam_half_width - 2.0
	if beam_axis == 0:
		return global_position + Vector2(0.0, -offset)
	return global_position + Vector2(-offset, 0.0)

func _end_b() -> Vector2:
	var offset := beam_half_width - 2.0
	if beam_axis == 0:
		return global_position + Vector2(0.0, offset)
	return global_position + Vector2(offset, 0.0)

func _fp_y() -> float:
	return 0.10 if low_beam else 0.45

func _update_fp_beam(telegraph: bool, color: Color) -> void:
	if GameState.active_rig == null or not is_instance_valid(GameState.active_rig):
		return
	if not GameState.active_rig.has_method("set_enemy_beam"):
		return
	GameState.active_rig.set_enemy_beam(self, _end_a(), _end_b(), color, telegraph, _fp_y())

func _clear_fp_beam() -> void:
	if GameState.active_rig != null and is_instance_valid(GameState.active_rig) \
			and GameState.active_rig.has_method("clear_enemy_beam"):
		GameState.active_rig.clear_enemy_beam(self)

func _exit_tree() -> void:
	_clear_fp_beam()
