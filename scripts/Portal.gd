extends Area2D

var _player_in_range: bool = false
var _anim_t: float = 0.0

const _BEFORE := "  ,-===-.  \n /  >>>  \\ \n|>> ["
const _AFTER  := "] >>|\n \\  >>>  / \n  `-===-'  "
const _FRAMES := ["<>", "><", ">>", "<<", "==", "><", "<>", "<<"]

func _ready() -> void:
	add_to_group("portal")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(delta: float) -> void:
	_anim_t += delta

	# Cycle centre character every 0.18 s
	var frame_idx := int(_anim_t / 0.18) % _FRAMES.size()
	$AsciiArt.text = _BEFORE + _FRAMES[frame_idx] + _AFTER

	# Pulse colour between cyan and bright white-cyan
	var pulse := 0.5 + 0.5 * sin(_anim_t * TAU * 0.7)
	$AsciiArt.add_theme_color_override("font_color",
		Color(0.3 + pulse * 0.5, 0.85 + pulse * 0.15, 1.0, 1.0))

	if _player_in_range and Input.is_action_just_pressed("interact"):
		_use_portal()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		$InteractHint.visible = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		$InteractHint.visible = false

func _use_portal() -> void:
	GameState.portals_used += 1
	GameState.difficulty  += 0.3
	GameState.biome        = (GameState.portals_used / 3) % 4
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("save_state"):
		player.save_state()
	get_tree().reload_current_scene()
