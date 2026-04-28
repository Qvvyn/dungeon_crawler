extends Area2D

# Village Inn — full heal, mana / stamina refill, and save run state.
# Free of charge; the player's idea of "rest before delving" shouldn't
# be gated behind currency. Save points still let you bail and return.

var _player_in_range: bool = false
var _cooldown: float = 0.0   # rate-limit so a held E doesn't spam-heal

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)
	if _player_in_range and _cooldown <= 0.0 \
			and Input.is_action_just_pressed("interact"):
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
	_cooldown = 0.6
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		return
	if p.has_method("heal_to_full"):
		p.heal_to_full()
	if "mana" in p and "max_mana" in p:
		p.mana = p.max_mana
	if "stamina" in p and "max_stamina" in p:
		p.stamina = p.max_stamina
	if p.has_method("_save_run"):
		p.call("_save_run")
	if SoundManager:
		SoundManager.play("save_run", randf_range(0.95, 1.05))
	FloatingText.spawn_str(p.global_position,
		"RESTED",
		Color(0.5, 1.0, 0.6),
		get_tree().current_scene)
