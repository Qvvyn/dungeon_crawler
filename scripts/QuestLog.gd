extends Node

# Persistent quest log — small directed-objective system that lives
# alongside the run loop. Quests live across runs so a "kill 100
# chargers" objective can span multiple delves. Persisted to
# user://quests.json same way PersistentStash handles items.
#
# Each quest is a Dictionary with:
#   id        : String   — unique key
#   title     : String   — short display name
#   desc      : String   — fuller description shown in the quest UI
#   kind      : String   — "kill" | "floor" | "gold"
#   target_id : String   — for "kill": script-path substring; for "floor": biome key; for "gold": "" (any source)
#   amount    : int      — count required
#   progress  : int      — current count, persisted
#   reward_gold: int     — bank-gold reward on completion
#   reward_legendary : bool — drops a guaranteed legendary item to the bank
#   complete  : bool     — marked complete; reward already paid out

const SAVE_PATH := "user://quests.json"

signal quest_completed(quest: Dictionary)
signal quest_progress(quest: Dictionary)

# Master quest list. The IDs are stable across saves so progress doesn't
# get lost when adding new entries. To add a quest, append here and run
# once — the autoload's _load merges any new IDs into the saved state.
const QUESTS: Array = [
	{
		"id": "kill_chargers", "title": "Charger Slayer",
		"desc": "Defeat 50 chargers in any biome.",
		"kind": "kill", "target_id": "EnemyCharger", "amount": 50,
		"reward_gold": 500, "reward_legendary": false,
	},
	{
		"id": "kill_wizards", "title": "Wand Reaper",
		"desc": "Defeat 25 rival wizards.",
		"kind": "kill", "target_id": "EnemyWizard", "amount": 25,
		"reward_gold": 800, "reward_legendary": true,
	},
	{
		"id": "kill_bosses", "title": "Architect of Ruin",
		"desc": "Defeat 10 bosses.",
		"kind": "kill", "target_id": "EnemyBoss", "amount": 10,
		"reward_gold": 1500, "reward_legendary": true,
	},
	{
		"id": "floor_lava", "title": "Heat Tolerance",
		"desc": "Reach floor 15 in the Lava Rift.",
		"kind": "floor", "target_id": "lava", "amount": 15,
		"reward_gold": 700, "reward_legendary": false,
	},
	{
		"id": "floor_ice", "title": "Frost Pioneer",
		"desc": "Reach floor 15 in the Ice Cavern.",
		"kind": "floor", "target_id": "ice", "amount": 15,
		"reward_gold": 700, "reward_legendary": false,
	},
	{
		"id": "gold_total", "title": "Hoarder",
		"desc": "Earn 10,000 total gold across all runs.",
		"kind": "gold", "target_id": "", "amount": 10000,
		"reward_gold": 1000, "reward_legendary": true,
	},
]

# Per-id progress dictionary. {quest_id → {"progress": N, "complete": bool}}
var state: Dictionary = {}

func _ready() -> void:
	_load()

# ── Tracking entry points ──────────────────────────────────────────────────

# Called from EnemyBase on every kill. Walks the active quests, bumps any
# kill-quest whose target_id substring is in the dying enemy's script path.
func note_kill(enemy: Node) -> void:
	if enemy == null:
		return
	var s: Script = enemy.get_script() as Script
	if s == null:
		return
	var path: String = s.resource_path.get_file()
	for q in QUESTS:
		if String(q["kind"]) != "kill":
			continue
		var tag: String = String(q["target_id"])
		if path.contains(tag):
			_bump(q, 1)

# Called by Portal/ExitPortal when the player advances or exits floors.
# Tracks the deepest floor reached per biome.
func note_floor_reached(biome_key: String, floor_n: int) -> void:
	for q in QUESTS:
		if String(q["kind"]) != "floor":
			continue
		if String(q["target_id"]) != biome_key:
			continue
		# floor-reach is best-of, not a counter — overwrite if higher.
		var entry := _entry(String(q["id"]))
		if floor_n > int(entry.get("progress", 0)):
			entry["progress"] = floor_n
			state[q["id"]] = entry
			_check_complete(q)
			quest_progress.emit(q)
			_save()

# Called whenever the player gains gold (per-run gold or bank deposits).
func note_gold_gained(amount: int) -> void:
	if amount <= 0:
		return
	for q in QUESTS:
		if String(q["kind"]) != "gold":
			continue
		_bump(q, amount)

# ── Internals ──────────────────────────────────────────────────────────────

func _entry(id: String) -> Dictionary:
	if not state.has(id):
		state[id] = {"progress": 0, "complete": false}
	return state[id]

func _bump(q: Dictionary, amount: int) -> void:
	var id := String(q["id"])
	var entry := _entry(id)
	if bool(entry.get("complete", false)):
		return
	entry["progress"] = int(entry.get("progress", 0)) + amount
	state[id] = entry
	_check_complete(q)
	quest_progress.emit(q)
	_save()

func _check_complete(q: Dictionary) -> void:
	var entry := _entry(String(q["id"]))
	if bool(entry.get("complete", false)):
		return
	if int(entry.get("progress", 0)) >= int(q["amount"]):
		entry["complete"] = true
		state[q["id"]] = entry
		_grant_reward(q)
		quest_completed.emit(q)

func _grant_reward(q: Dictionary) -> void:
	if int(q.get("reward_gold", 0)) > 0:
		# Scale by the player's current depth so a quest that completes
		# during a Hellpit run pays out proportional to the gear/upgrade
		# costs at that tier. Earlier tiers stay at the base reward.
		# Curve: +30% per +1 difficulty above 1, capped at 4× so the
		# numbers stay legible.
		var d: float = maxf(GameState.difficulty, GameState.starting_difficulty)
		var scale: float = clampf(1.0 + maxf(0.0, d - 1.0) * 0.30, 1.0, 4.0)
		PersistentStash.add_gold(int(round(float(q["reward_gold"]) * scale)))
	if bool(q.get("reward_legendary", false)):
		var loot: Item = ItemDB.generate_wand(Item.RARITY_LEGENDARY)
		if loot != null:
			PersistentStash.deposit(loot)
	# Floating text in case the player is in-world when this fires.
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p is Node2D:
		FloatingText.spawn_str((p as Node2D).global_position,
			"QUEST: %s" % String(q["title"]),
			Color(1.0, 0.9, 0.4),
			get_tree().current_scene)
	if SoundManager:
		SoundManager.play("crystal", 1.10)

# ── Persistence ────────────────────────────────────────────────────────────

func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(state, "\t"))
	f.close()

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var raw: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if raw is Dictionary:
		state = raw
