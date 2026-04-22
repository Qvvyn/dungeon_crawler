extends Area2D

var value: int = 1
var _player: Node2D = null
var _collected: bool = false

const MAGNET_RANGE  := 160.0
const PICKUP_RANGE  := 45.0
const MAGNET_SPEED  := 340.0

func _ready() -> void:
	add_to_group("gold_pickup")
	body_entered.connect(_on_body_entered)
	_player = get_tree().get_first_node_in_group("player")
	var vis := get_node_or_null("Visual")
	if vis: vis.visible = false
	var lbl := Label.new()
	lbl.text = "$"
	lbl.position = Vector2(-10, -12)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
	lbl.add_theme_color_override("font_outline_color", Color(0.4, 0.25, 0.0))
	lbl.add_theme_constant_override("outline_size", 2)
	add_child(lbl)

func _collect() -> void:
	if _collected:
		return
	_collected = true
	GameState.gold += value
	var pos := _player.global_position if is_instance_valid(_player) else global_position
	FloatingText.spawn(pos, value, true, get_tree().current_scene, Color(1.0, 0.85, 0.1))
	queue_free()

func _physics_process(delta: float) -> void:
	if _collected:
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(_player):
		return
	var dist := global_position.distance_to(_player.global_position)
	if dist <= PICKUP_RANGE:
		_collect()
	elif dist <= MAGNET_RANGE:
		var dir := (_player.global_position - global_position).normalized()
		global_position += dir * MAGNET_SPEED * delta

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player = body
		_collect()
