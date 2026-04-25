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

	# Locked while a boss is alive — dim red instead of pulsing cyan
	var locked := _boss_alive()
	if locked:
		$AsciiArt.add_theme_color_override("font_color",
			Color(0.55, 0.18, 0.18, 0.55))
		if has_node("InteractHint"):
			$InteractHint.text = "DEFEAT BOSS"
	else:
		# Pulse colour between cyan and bright white-cyan
		var pulse := 0.5 + 0.5 * sin(_anim_t * TAU * 0.7)
		$AsciiArt.add_theme_color_override("font_color",
			Color(0.3 + pulse * 0.5, 0.85 + pulse * 0.15, 1.0, 1.0))
		if has_node("InteractHint"):
			$InteractHint.text = "[E] Enter"

	if _player_in_range:
		# Locked while a boss is alive on this floor
		if _boss_alive():
			return
		# Autoplay enters portals automatically — no key press required
		var ply := get_tree().get_first_node_in_group("player")
		if ply and ply.get("_autoplay") == true:
			_use_portal()
			return
		if Input.is_action_just_pressed("interact"):
			_use_portal()

func _boss_alive() -> bool:
	for b in get_tree().get_nodes_in_group("boss"):
		if is_instance_valid(b):
			return true
	return false

# Mutates the wand's shoot_type to a random different one and primes the
# associated per-type stats so the new behaviour actually fires correctly.
const _ROTATABLE_TYPES := ["regular", "pierce", "ricochet", "freeze", "fire",
	"shock", "beam", "shotgun", "homing", "nova"]
func _rotate_wand_shoot_type(wand: Item) -> void:
	var current: String = wand.wand_shoot_type
	var pool: Array = []
	for t in _ROTATABLE_TYPES:
		if t != current:
			pool.append(t)
	if pool.is_empty():
		return
	var new_type: String = pool[randi() % pool.size()]
	wand.wand_shoot_type = new_type
	# Reset and seed type-specific stats — without this, "pierce" wands have
	# wand_pierce=0 and don't actually pierce, etc.
	wand.wand_pierce = 0
	wand.wand_ricochet = 0
	match new_type:
		"pierce":
			wand.wand_pierce = 3
		"ricochet":
			wand.wand_ricochet = 3
		"freeze", "fire", "shock":
			wand.wand_status_stacks = max(wand.wand_status_stacks, 3)
		"beam":
			wand.wand_mana_cost = max(wand.wand_mana_cost, 9.0)
	FloatingText.spawn_str(global_position,
		new_type.to_upper() + " WAND",
		Color(0.5, 1.0, 0.8), get_tree().current_scene)

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
	GameState.difficulty  += 0.25
	GameState.biome        = (GameState.portals_used / 3) % 4
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("save_state"):
		# Floor-clear reward: +10 HP carried into the next floor (capped at max)
		if "health" in player and player.has_method("_max_hp"):
			var hp_now: int = int(player.get("health"))
			var hp_max: int = int(player.call("_max_hp"))
			player.set("health", mini(hp_max, hp_now + 10))
		# Autoplay: rotate the equipped wand's shot type on every floor
		# so the bot visibly tries different archetypes as the run goes on
		if player.get("_autoplay") == true and InventoryManager:
			var w: Item = InventoryManager.equipped.get("wand") as Item
			if w != null:
				_rotate_wand_shoot_type(w)
		player.save_state()
	get_tree().reload_current_scene()
