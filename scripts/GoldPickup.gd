extends Area2D

var value: int = 1

func _ready() -> void:
	add_to_group("gold_pickup")
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		GameState.gold += value
		FloatingText.spawn(body.global_position, value, true, get_tree().current_scene, Color(1.0, 0.85, 0.1))
		queue_free()
