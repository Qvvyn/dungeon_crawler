extends Area2D

const DISORIENT_DURATION := 4.0
const COOLDOWN           := 6.0   # seconds before it can re-trigger

enum State { IDLE, COOLDOWN }

var _state: State = State.IDLE
var _cd: float    = 0.0
var _label: Label = null

func _ready() -> void:
	add_to_group("trap")
	body_entered.connect(_on_body_entered)
	_label = $AsciiChar
	_set_idle()

func _process(delta: float) -> void:
	if _state == State.COOLDOWN:
		_cd -= delta
		if _cd <= 0.0:
			_set_idle()
	# Slow swirl on the glyph itself so it looks alive
	if _label and _state == State.IDLE:
		var t := Time.get_ticks_msec() * 0.001
		_label.rotation = sin(t * 1.4) * 0.35

func _on_body_entered(body: Node2D) -> void:
	if _state != State.IDLE:
		return
	if body.is_in_group("player") and body.get("_is_levitating"):
		return  # levitating players float over traps
	if not body.is_in_group("player"):
		return
	if body.has_method("apply_status"):
		body.apply_status("disorient", DISORIENT_DURATION)
	FloatingText.spawn_str(global_position, "VERTIGO!", Color(0.85, 0.5, 1.0), get_tree().current_scene)
	_state = State.COOLDOWN
	_cd = COOLDOWN
	if _label:
		_label.add_theme_color_override("font_color", Color(0.35, 0.2, 0.45, 0.4))

func _set_idle() -> void:
	_state = State.IDLE
	if _label:
		_label.text = "@"
		_label.add_theme_color_override("font_color", Color(0.65, 0.35, 0.85, 0.55))
