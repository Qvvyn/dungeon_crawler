extends Area2D

# Catacombs biome hazard — applies the player's poison status while they
# stand inside the cloud. The DOT itself (10% max HP over 10s) is dealt by
# Player._tick_status' poison handler; this cloud just keeps refreshing the
# status timer so contact-grazing still ticks for the full duration.

const POISON_DURATION := 10.0
const TICK_INTERVAL   := 0.8

var _player_inside: bool = false
var _tick_t: float       = 0.0
var _pulse_t: float      = 0.0
var _label: Label        = null

func _ready() -> void:
	add_to_group("hazard")
	var cshape := CollisionShape2D.new()
	var shape  := CircleShape2D.new()
	shape.radius = 14.0
	cshape.shape = shape
	add_child(cshape)

	_label = Label.new()
	_label.text = "~"
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(0.30, 0.85, 0.30, 0.70))
	_label.position = Vector2(-7.0, -14.0)
	add_child(_label)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_inside = true
		_tick_t = 0.0

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_inside = false

func _process(delta: float) -> void:
	_pulse_t += delta * 1.8
	var pulse := 0.55 + 0.45 * sin(_pulse_t)
	if _label:
		_label.add_theme_color_override("font_color",
			Color(0.20, 0.55 + pulse * 0.35, 0.20, 0.55 + pulse * 0.30))
	if not _player_inside:
		return
	_tick_t -= delta
	if _tick_t <= 0.0:
		_tick_t = TICK_INTERVAL
		var ply: Node2D = get_tree().get_first_node_in_group("player")
		if is_instance_valid(ply) and ply.has_method("apply_status"):
			ply.apply_status("poison", POISON_DURATION)
