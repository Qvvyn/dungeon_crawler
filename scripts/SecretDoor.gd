extends StaticBody2D

# A secret wall segment — looks like ordinary wall, but it's destructible.
# There's no "?" marker and no [E] prompt: the player discovers it by
# noticing wand-hit feedback on what looks like a normal wall ("for those
# paying attention"), then breaks through to claim the hidden room's loot
# (and, on a rare roll, an ambush boss). Routes through the same
# `breakable_wall` damage path that Projectile.gd already handles, so no
# HP bar — just the hit burst.

const LOOT_BAG_SCENE = preload("res://scenes/LootBag.tscn")

var wall_color: Color = Color(0.12, 0.10, 0.18)
var loot_world_pos: Vector2 = Vector2.ZERO
var loot_items: Array = []
# Grid coords of the entrance (set by World). On break we ask World to carve
# the passage open for real (set the grid tiles to FLOOR + rebuild FP walls),
# so the door is an actual change to the level geometry rather than a floating
# overlay that never read correctly in FP.
var entrance_tile: Vector2i = Vector2i(-1, -1)
# When >= 0, spawn the matching biome boss inside the secret room when the
# wall is broken. World stamps this on a 5% roll.
var spawn_boss_biome: int = -1
# A touch tankier than a plain BreakableWall (3) so cracking a secret open
# feels earned once it's been found.
var _health: int = 6

func _ready() -> void:
	add_to_group("secret_door")
	add_to_group("breakable_wall")   # Projectile.gd routes wand damage here
	# Blend into the surrounding wall surface in 2D.
	var vis := get_node_or_null("Visual")
	if vis:
		vis.color = wall_color
	# Drop the legacy "?" mark + proximity detector if the scene still ships
	# them (kept the .tscn lean, but guard in case).
	var mark := get_node_or_null("Mark")
	if mark:
		mark.queue_free()
	var detect := get_node_or_null("DetectArea")
	if detect:
		detect.queue_free()
	# No FP billboard: the entrance tiles are WALL in the grid, so the FP rig
	# already renders this segment as solid wall geometry, indistinguishable
	# from the surrounding wall. The player discovers it by the hit-spark
	# feedback when a shot lands on what looks like ordinary wall.

func take_damage(amount: int) -> void:
	_health -= amount
	# Wand-hit feedback (burst) fires on every hit so an attentive player
	# notices this "wall" reacts. Full break-open happens at <= 0.
	_hit_spark()
	if _health <= 0:
		_break_open()

func _break_open() -> void:
	FloatingText.spawn_str(global_position, "SECRET FOUND!",
		Color(1.0, 0.9, 0.2), get_tree().current_scene)
	_rubble_burst()
	# Carve the passage open for real — flips the entrance grid tiles to FLOOR
	# and rebuilds the FP wall mesh so the opening appears in first-person /
	# 3rd-person, not just 2D.
	var world := get_tree().current_scene
	if world != null and world.has_method("open_secret_passage") and entrance_tile.x >= 0:
		world.open_secret_passage(entrance_tile)
	if not loot_items.is_empty():
		var bag := LOOT_BAG_SCENE.instantiate()
		bag.position = loot_world_pos
		bag.set("items", loot_items)
		get_tree().current_scene.add_child(bag)
	# Ambush boss — World stamps spawn_boss_biome on a 5 % roll. Pulls the
	# biome boss factory off the active World scene.
	if spawn_boss_biome >= 0:
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
	# queue_free takes the child cover ColorRect with it, revealing the room.
	queue_free()

# Small per-hit spark so the destructible wall "answers" each shot.
func _hit_spark() -> void:
	if GameState.active_rig != null and is_instance_valid(GameState.active_rig) \
			and GameState.active_rig.has_method("spawn_burst_2d"):
		GameState.active_rig.spawn_burst_2d(global_position, "#",
			wall_color.lightened(0.5), 1, 0.5, 0.22, Vector2.ZERO, TAU, 0.010, 0.50)
	var c := Label.new()
	c.text = "#"
	c.add_theme_color_override("font_color", wall_color.lightened(0.5))
	c.add_theme_font_size_override("font_size", 11)
	c.position = global_position + Vector2(randf_range(-6.0, 6.0), randf_range(-10.0, 10.0))
	get_tree().current_scene.add_child(c)
	var tw := c.create_tween()
	tw.tween_property(c, "modulate:a", 0.0, 0.22)
	tw.tween_callback(c.queue_free)

# Full collapse burst on break — mirrors BreakableWall's rubble scatter.
func _rubble_burst() -> void:
	var gpos := global_position
	var chars := ["#", "+", "*", "x"]
	for i in 8:
		var c := Label.new()
		c.text = chars[i % 4]
		c.add_theme_color_override("font_color", wall_color.lightened(0.5))
		c.add_theme_font_size_override("font_size", 11)
		var angle := (TAU / 8.0) * float(i) + randf_range(-0.3, 0.3)
		var dist := randf_range(14.0, 30.0)
		c.position = gpos + Vector2(cos(angle), sin(angle)) * dist * 0.3
		get_tree().current_scene.add_child(c)
		var tw := c.create_tween()
		tw.tween_property(c, "position", gpos + Vector2(cos(angle), sin(angle)) * dist, 0.35)
		tw.parallel().tween_property(c, "modulate:a", 0.0, 0.35)
		tw.tween_callback(c.queue_free)
	if GameState.active_rig != null and is_instance_valid(GameState.active_rig) \
			and GameState.active_rig.has_method("spawn_burst_2d"):
		var fp_col := wall_color.lightened(0.5)
		GameState.active_rig.spawn_burst_2d(gpos, "#", fp_col, 2, 0.65, 0.35, Vector2.ZERO, TAU, 0.010, 0.50)
		GameState.active_rig.spawn_burst_2d(gpos, "+", fp_col, 2, 0.65, 0.35, Vector2.ZERO, TAU, 0.010, 0.50)
	if SoundManager:
		SoundManager.play("explosion", randf_range(0.85, 1.0))
