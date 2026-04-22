extends StaticBody2D

var wall_color: Color = Color(0.12, 0.10, 0.18)
var _player_nearby: bool = false
var _hint: Label = null

func _ready() -> void:
	# Tint the visual to match the current wall colour
	var vis := get_node_or_null("Visual")
	if vis:
		vis.color = wall_color

	_hint = Label.new()
	_hint.text = "[E] Open"
	_hint.position = Vector2(-28.0, -28.0)
	_hint.visible = false
	_hint.add_theme_font_size_override("font_size", 11)
	_hint.add_theme_color_override("font_color", Color(1.0, 0.95, 0.3))
	_hint.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_hint.add_theme_constant_override("outline_size", 2)
	add_child(_hint)

	$DetectArea.body_entered.connect(_on_detect_entered)
	$DetectArea.body_exited.connect(_on_detect_exited)

func _process(_delta: float) -> void:
	if _player_nearby and Input.is_action_just_pressed("interact"):
		FloatingText.spawn_str(global_position, "SECRET FOUND!",
			Color(1.0, 0.9, 0.2), get_tree().current_scene)
		queue_free()

func _on_detect_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_nearby = true
		_hint.visible = true

func _on_detect_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_nearby = false
		_hint.visible = false
