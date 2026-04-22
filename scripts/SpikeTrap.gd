extends Area2D

const PROJECTILE_SCENE := preload("res://scenes/Projectile.tscn")

const WARN_TIME    := 1.5   # seconds of glow warning before firing
const COOLDOWN     := 7.0   # seconds before trap resets
const PROJ_SPEED   := 270.0
const PROJ_DAMAGE  := 2
const PROJ_COUNT   := 8
const SPAWN_OFFSET := 32.0  # spawn projectiles outside player collision box

enum State { IDLE, WARNING, COOLDOWN }

var _state: State   = State.IDLE
var _timer: float   = 0.0
var _label: Label   = null

func _ready() -> void:
	add_to_group("trap")
	body_entered.connect(_on_body_entered)
	_label = $AsciiChar
	_set_idle()

func _physics_process(delta: float) -> void:
	match _state:
		State.WARNING:
			_timer -= delta
			# Pulse from dim amber → bright red-orange as countdown expires
			var t: float = clampf(1.0 - (_timer / WARN_TIME), 0.0, 1.0)
			var r: float = lerp(0.6, 1.0, t)
			var g: float = lerp(0.5, 0.15, t)
			_label.add_theme_color_override("font_color", Color(r, g, 0.0))
			_label.add_theme_font_size_override("font_size", int(lerp(14.0, 22.0, t)))
			if _timer <= 0.0:
				_fire()
		State.COOLDOWN:
			_timer -= delta
			if _timer <= 0.0:
				_set_idle()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and body.get("_is_levitating"):
		return  # levitating players float over traps
	if body.is_in_group("player") and _state == State.IDLE:
		_state = State.WARNING
		_timer = WARN_TIME
		_label.text = "!"
		_label.add_theme_font_size_override("font_size", 14)
		_label.add_theme_color_override("font_color", Color(0.7, 0.5, 0.0))

func _fire() -> void:
	_state = State.COOLDOWN
	_timer = COOLDOWN
	FloatingText.spawn_str(global_position, "TRAP!", Color(1.0, 0.45, 0.0), get_tree().current_scene)
	for i in PROJ_COUNT:
		var angle := (TAU / float(PROJ_COUNT)) * float(i)
		var dir := Vector2(cos(angle), sin(angle))
		var proj: Node = PROJECTILE_SCENE.instantiate()
		# Offset spawn so projectiles don't immediately hit the triggering player
		proj.global_position = global_position + dir * SPAWN_OFFSET
		proj.set("direction", dir)
		proj.set("source", "enemy")
		proj.set("speed", PROJ_SPEED)
		proj.set("damage", PROJ_DAMAGE)
		get_tree().current_scene.add_child(proj)
	_label.text = "·"
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.5, 0.2, 0.0, 0.5))

func _set_idle() -> void:
	_state = State.IDLE
	_label.text = "·"
	_label.add_theme_font_size_override("font_size", 14)
	# Very dim — blends into the floor
	_label.add_theme_color_override("font_color", Color(0.32, 0.26, 0.20, 0.55))
