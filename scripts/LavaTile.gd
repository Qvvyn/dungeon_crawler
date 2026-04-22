extends Area2D

const BURN_INTERVAL := 0.65
const BURN_DAMAGE   := 1

var _player_inside: bool = false
var _burn_timer: float   = 0.0
var _pulse_t: float      = 0.0
var _label: Label        = null

func _ready() -> void:
	var cshape := CollisionShape2D.new()
	var shape  := CircleShape2D.new()
	shape.radius = 12.0
	cshape.shape = shape
	add_child(cshape)

	_label = Label.new()
	_label.text = "≈"
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.0, 0.85))
	_label.position = Vector2(-7.0, -12.0)
	add_child(_label)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_inside = true
		_burn_timer = 0.0

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_inside = false

func _process(delta: float) -> void:
	_pulse_t += delta * 2.2
	var pulse := 0.55 + 0.45 * sin(_pulse_t)
	if _label:
		_label.add_theme_color_override("font_color",
			Color(1.0, 0.25 + pulse * 0.3, 0.0, 0.65 + pulse * 0.35))

	if not _player_inside:
		return
	_burn_timer -= delta
	if _burn_timer <= 0.0:
		_burn_timer = BURN_INTERVAL
		var player: Node2D = get_tree().get_first_node_in_group("player")
		if is_instance_valid(player) and player.has_method("take_damage"):
			player.take_damage(BURN_DAMAGE)
			FloatingText.spawn_str(global_position, "BURN!", Color(1.0, 0.35, 0.0), get_tree().current_scene)
