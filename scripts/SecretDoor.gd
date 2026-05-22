extends StaticBody2D

const LOOT_BAG_SCENE = preload("res://scenes/LootBag.tscn")

var wall_color: Color = Color(0.12, 0.10, 0.18)
var loot_world_pos: Vector2 = Vector2.ZERO
var loot_items: Array = []
# When >= 0, spawn the matching biome boss inside the secret room when
# the player opens the door. Set by World._place_secret_doors on a 5%
# roll so the rare-but-juicy "secret boss" surprise costs the player a
# fight to claim the loot. -1 = no boss (default).
var spawn_boss_biome: int = -1
var _player_nearby: bool = false
var _hint: Label = null

func _ready() -> void:
	add_to_group("secret_door")
	# Tint the visual to match the current wall colour
	var vis := get_node_or_null("Visual")
	if vis:
		vis.color = wall_color
	GameState.attach_fp_visual(self, "?", Color(0.65, 0.65, 0.55), 0.55)

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
		_trigger_open()

func _trigger_open() -> void:
	FloatingText.spawn_str(global_position, "SECRET FOUND!",
		Color(1.0, 0.9, 0.2), get_tree().current_scene)
	if not loot_items.is_empty():
		var bag := LOOT_BAG_SCENE.instantiate()
		bag.position = loot_world_pos
		bag.set("items", loot_items)
		get_tree().current_scene.add_child(bag)
	# Surprise boss — World stamps spawn_boss_biome on a 5 % roll. Pulls the
	# biome boss factory off the active World scene since SecretDoor doesn't
	# preload the boss scenes itself.
	if spawn_boss_biome >= 0:
		var world := get_tree().current_scene
		if world != null and world.has_method("_instantiate_biome_boss"):
			var boss: Node2D = world._instantiate_biome_boss(
				spawn_boss_biome, GameState.difficulty)
			if boss != null:
				boss.position = loot_world_pos
				var enemies_node := world.get_node_or_null("Enemies")
				if enemies_node != null:
					enemies_node.add_child(boss)
				else:
					world.add_child(boss)
				FloatingText.spawn_str(loot_world_pos + Vector2(0.0, -40.0),
					"AMBUSH!", Color(1.0, 0.35, 0.35), world)
	queue_free()

func _on_detect_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_nearby = true
		_hint.visible = true
		# Autoplay auto-triggers so it doesn't get hung up on the door body.
		# After the trigger we nudge the bot to invalidate its A* cache —
		# the door tile was weighted 4.0 in the prior build, so cached paths
		# may take an unnecessary detour around the now-clear entrance.
		if body.get("_autoplay") == true:
			_trigger_open()
			if body.has_method("_autoplay_invalidate_path"):
				body._autoplay_invalidate_path()

func _on_detect_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_nearby = false
		_hint.visible = false
