extends Area2D

# Hearth Sign — village's "go to title screen" exit. Sits at the edge
# of the hub. Lets the player escape the run loop without quitting the
# game (e.g. to check leaderboards, change settings, view run history).

var _player_in_range: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(_delta: float) -> void:
	if _player_in_range and Input.is_action_just_pressed("interact"):
		_use()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		var hint := get_node_or_null("InteractHint")
		if hint != null:
			hint.visible = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		var hint := get_node_or_null("InteractHint")
		if hint != null:
			hint.visible = false

func _use() -> void:
	GameState.in_hub = false
	get_tree().change_scene_to_file("res://scenes/TitleScreen.tscn")
