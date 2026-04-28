extends Area2D

# Village → Dungeon portal. Resets per-run state and loads World.tscn at
# the player's currently-selected difficulty / climb rate. The Title
# Screen tier picker still drives those when the player started the run
# from the village; otherwise we fall back to the saved settings.

var _player_in_range: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(_delta: float) -> void:
	if _player_in_range and Input.is_action_just_pressed("interact"):
		_descend()

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

func _descend() -> void:
	# Wipe leftover save_run.json so the dungeon load doesn't restore
	# the previous run mid-village-departure.
	if FileAccess.file_exists("user://save_run.json"):
		DirAccess.remove_absolute("user://save_run.json")
	GameState.test_mode = false
	GameState.in_hub = false
	GameState.portals_used = 0
	GameState.kills        = 0
	GameState.damage_dealt = 0
	GameState.gold         = 0   # bank gold survives via PersistentStash
	# Wipe the run bag (grid) so the dungeon starts fresh, but keep the
	# equipped loadout — the player's chosen kit is part of their hub
	# progression. Anything left in the bag at descend time is lost; the
	# bank is the way to preserve loot across runs.
	for i in InventoryManager.grid.size():
		InventoryManager.grid[i] = null
	InventoryManager.inventory_changed.emit()
	GameState.run_start_msec = Time.get_ticks_msec()
	# Use the currently-saved tier settings (set on title-screen tier select)
	# so the player keeps their chosen difficulty / climb rate.
	GameState.difficulty = GameState.starting_difficulty
	get_tree().change_scene_to_file("res://scenes/World.tscn")
