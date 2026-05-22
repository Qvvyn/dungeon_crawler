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

	# Locked while a boss OR the portal sentinel-wizard is alive. The
	# wizard guards every non-boss floor's exit; killing him is now
	# mandatory to descend.
	var locked := _boss_alive()
	var wiz_locked := _portal_wizard_alive() if not locked else false
	if locked:
		$AsciiArt.add_theme_color_override("font_color",
			Color(0.55, 0.18, 0.18, 0.55))
		if has_node("InteractHint"):
			$InteractHint.text = "DEFEAT BOSS"
	elif wiz_locked:
		$AsciiArt.add_theme_color_override("font_color",
			Color(0.55, 0.30, 0.55, 0.65))
		if has_node("InteractHint"):
			$InteractHint.text = "DEFEAT WIZARD"
	else:
		# Pulse colour between cyan and bright white-cyan
		var pulse := 0.5 + 0.5 * sin(_anim_t * TAU * 0.7)
		$AsciiArt.add_theme_color_override("font_color",
			Color(0.3 + pulse * 0.5, 0.85 + pulse * 0.15, 1.0, 1.0))
		if has_node("InteractHint"):
			$InteractHint.text = "[E] Enter"

	if _player_in_range:
		# Locked while a boss OR the portal-sentinel wizard is still alive
		# on this floor. Both gates use the same "wait, then enter" UX.
		if _boss_alive() or _portal_wizard_alive():
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

func _portal_wizard_alive() -> bool:
	for w in get_tree().get_nodes_in_group("portal_wizard"):
		if is_instance_valid(w):
			return true
	return false

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		$InteractHint.visible = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		$InteractHint.visible = false

# Per-portal difficulty increment is locked by the dungeon the player
# *started* in (set on the title-screen tier select). Each tier explicitly
# carries its own climb rate via GameState.starting_climb_rate so two tiers
# with the same starting difficulty can still escalate at different speeds
# (e.g. Catacombs and Dungeon both start at 1.0 but climb at 1.0 and 0.5).
#   CELLAR    (start 0.5) → +0.25 per portal
#   DUNGEON   (start 1.0) → +0.50 per portal
#   CATACOMBS (start 1.0) → +1.00 per portal
#   ABYSS     (start 3.2) → +1.50 per portal
#   HELLPIT   (start 5.5) → +2.00 per portal
func _difficulty_step() -> float:
	return GameState.starting_climb_rate

func _use_portal() -> void:
	GameState.portals_used += 1
	# Quest tracking — note the deepest floor reached in the current biome.
	# floor count is portals_used (now incremented above) which also equals
	# "floors descended"; mapped to biome key via the same table the
	# Leaderboard uses.
	const BIOME_KEYS := ["dungeon", "catacombs", "ice", "lava"]
	var bk: String = BIOME_KEYS[clampi(GameState.biome, 0, 3)]
	QuestLog.note_floor_reached(bk, GameState.portals_used)
	GameState.difficulty  += _difficulty_step()
	GameState.biome        = (GameState.portals_used / 3) % 4
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("save_state"):
		# Floor-clear reward: +10 HP carried into the next floor (capped at max)
		if "health" in player and player.has_method("_max_hp"):
			var hp_now: int = int(player.get("health"))
			var hp_max: int = int(player.call("_max_hp"))
			player.set("health", mini(hp_max, hp_now + 10))
		# Autoplay: drop the equipped wand on every portal so the bot is forced
		# to try a new one each floor. Auto-equip leaves the wand in the grid
		# alongside the equip slot, so we clear *both*. After the drop, if no
		# permanent wand remains, generate a common fallback so the bot always
		# has something to fire next floor.
		if player.get("_autoplay") == true and InventoryManager:
			var w: Item = InventoryManager.equipped.get("wand") as Item
			if w != null:
				# Clear the wand from its row 0 slot. _sync_active_wand
				# rewrites equipped["wand"] from the next held wand (or
				# null when nothing else is in the row).
				for i in InventoryManager.grid.size():
					if InventoryManager.grid[i] == w:
						InventoryManager.grid[i] = null
				InventoryManager._sync_active_wand()
			var has_permanent := false
			for it_chk in InventoryManager.grid:
				var w_chk: Item = it_chk as Item
				if w_chk != null and w_chk.type == Item.Type.WAND \
						and w_chk.wand_max_charges == 0:
					has_permanent = true
					break
			if not has_permanent:
				InventoryManager.add_item(ItemDB.generate_wand(Item.RARITY_COMMON))
			InventoryManager.inventory_changed.emit()
			FloatingText.spawn_str(player.global_position + Vector2(0.0, -28.0),
				"WAND DROPPED",
				Color(0.95, 0.7, 0.4),
				get_tree().current_scene)
		player.save_state()
	get_tree().reload_current_scene()
