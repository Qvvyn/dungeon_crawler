extends EnemyBase

# Hidden enemy spawner ("nest"). Static, no movement, no attack — just sits in
# a corner of a back room and pumps out minions of one fixed type until the
# player destroys it. World.gd places these on diff ≥ 4 floors at the room
# farthest from the player spawn; the player has to seek them out.
#
# Spawn type / rate / cap design — see chat conversation for the rationale:
#   - type      : one biome-keyed pool entry, locked at spawn (one nest = one species)
#   - interval  : clampf(7.0 - diff * 0.15, 4.0, 7.0)
#   - cap       : 4 minions per spawner (tracked via "spawner_id" meta on each child)
#   - HP        : 90 × (1 + diff * 0.5) — meaningful soak, not a boss
#   - drops     : richer gold + guaranteed loot bag + 10% champion-item bonus
#
# LOS gating: hidden until the player has direct line-of-sight (matches the
# "hidden somewhere" framing). FP rig already handles its own occlusion, so
# the 2D Label is the only thing we explicitly toggle here.

const LOS_CHECK_INTERVAL: float = 0.30
# Per-nest concurrent minion cap. Scales with floor difficulty so late floors
# get noticeably hungrier nests, with a hard ceiling so they don't snowball
# past the global enemy cap (World.MAX_LIVE_ENEMIES = 45). At diff 4 (the
# threshold where nests start spawning) the cap is 3, climbing one step per
# +10 diff up to a max of 7 minions per nest at diff 44+.
const MAX_MINIONS_BASE: int    = 3
const MAX_MINIONS_CEILING: int = 7

const ART_F0: String = " /^\\ \n[~~~]\n ‾‾‾ "
const ART_F1: String = " /^\\ \n[≈≈≈]\n ‾‾‾ "

# Picked at spawn time by World.gd and set via .set("minion_scene", …). Each
# spawner instance fixes its species for life so a "spider nest" stays spiders.
var minion_scene: PackedScene = null
var minion_name: String       = "minion"   # cosmetic — used in the spawn floater

var _spawn_interval: float = 7.0
var _spawn_t: float        = 0.0
var _telegraph_t: float    = 0.0   # brief flash window right before each spawn
var _max_minions: int      = MAX_MINIONS_BASE   # diff-scaled at spawn time

var _los_t: float    = 0.0
var _los_clear: bool = false

var _anim_t: float = 0.0
var _anim_f: int   = 0

func _on_ready_extra() -> void:
	# Static — no movement, no aggro-from-sight. Player still has to find us.
	passive = true
	_has_aggro = false
	_sight_range = 0.0
	# Difficulty-tuned HP. Same +50% per +1.0 diff curve as regular enemies
	# so a t-N spawner scales like a t-N tank.
	var diff: float = GameState.test_difficulty if GameState.test_mode else GameState.difficulty
	max_health = int(round(90.0 * (1.0 + maxf(0.0, diff) * 0.5)))
	health = max_health
	# Spawn rate ramps faster at higher diff but never under 4 s.
	_spawn_interval = clampf(7.0 - diff * 0.15, 4.0, 7.0)
	_spawn_t = _spawn_interval * 0.6   # short stagger so first spawn isn't instant
	# Minion cap climbs by +1 per +10 diff, capped at MAX_MINIONS_CEILING so
	# a single deep-floor nest can't dominate the global enemy budget.
	_max_minions = clampi(MAX_MINIONS_BASE + int(diff / 10.0), MAX_MINIONS_BASE, MAX_MINIONS_CEILING)
	if _lbl:
		_lbl.text = ART_F0
		_lbl.add_theme_color_override("font_color", Color(0.95, 0.55, 0.25))
		_lbl.add_theme_constant_override("line_separation", -2)
	_update_health_bar()
	# Start hidden — _tick_anim flips visibility once the player has LOS.
	_apply_visibility(false)

func _enemy_tick(delta: float) -> void:
	# Static body — no velocity, no slide. move_and_slide in the base class
	# runs harmlessly on a zero-velocity body.
	velocity = Vector2.ZERO
	if minion_scene == null:
		return
	_los_t -= delta
	if _los_t <= 0.0:
		_los_t = LOS_CHECK_INTERVAL
		_los_clear = _has_los_to_player()
		_apply_visibility(_los_clear)
	if _telegraph_t > 0.0:
		_telegraph_t -= delta
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = _spawn_interval
		_try_spawn_minion()

func _try_spawn_minion() -> void:
	if _frozen or _stun_timer > 0.0:
		return
	if _live_minion_count() >= _max_minions:
		return
	# Respect the global live-enemy ceiling so spawner stacks can't snowball.
	var scene_root := get_tree().current_scene
	if scene_root != null and scene_root.has_method("can_spawn_enemy") \
			and not scene_root.can_spawn_enemy():
		return
	var enemies_node := scene_root.get_node_or_null("Enemies")
	if enemies_node == null:
		return
	var m: Node = minion_scene.instantiate()
	if m is Node2D:
		# Slight random offset so back-to-back spawns don't stack pixel-perfectly.
		(m as Node2D).global_position = global_position + Vector2(randf_range(-12, 12), randf_range(-12, 12))
	# Aggro on spawn — player can't be caught off-guard by a fresh add that
	# just stands there for two seconds.
	if "_has_aggro" in m:
		m.set("_has_aggro", true)
	# Tag the minion with our instance id so _live_minion_count can find them
	# without scanning every enemy on the floor.
	m.set_meta("spawner_id", get_instance_id())
	enemies_node.call_deferred("add_child", m)
	_telegraph_t = 0.6
	FloatingText.spawn_str(global_position, "A WHISPER…",
		Color(0.85, 0.55, 0.95), get_tree().current_scene)

# Counts how many enemies on the floor came out of THIS spawner. Linear scan
# of the Enemies node — fine for the typical <45 live enemies cap.
func _live_minion_count() -> int:
	var enemies_node := get_tree().current_scene.get_node_or_null("Enemies") if get_tree().current_scene else null
	if enemies_node == null:
		return 0
	var count: int = 0
	var our_id: int = get_instance_id()
	for child in enemies_node.get_children():
		if not is_instance_valid(child):
			continue
		if child.get_meta("spawner_id", 0) == our_id:
			count += 1
	return count

func _has_los_to_player() -> bool:
	if not is_instance_valid(_player):
		return false
	# 14-tile cap: spawner can be quite far from spawn, no need to bother
	# raycasting if the player is across the entire floor.
	if global_position.distance_squared_to(_player.global_position) > 448.0 * 448.0:
		return false
	var space := get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(global_position, _player.global_position)
	q.exclude = [get_rid()]
	q.collision_mask = 1   # walls only
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return true
	return hit.get("collider") == _player

func _apply_visibility(visible_now: bool) -> void:
	# 2D label only — FP rig's occlusion + cull-distance handle the FP side.
	# We also keep the HP bar in lockstep so the bar isn't a giveaway.
	if _lbl != null:
		_lbl.visible = visible_now and (GameState.render_mode == GameState.RenderMode.TOPDOWN)
	var bar := get_node_or_null("HealthBar")
	if bar != null:
		bar.visible = visible_now and (GameState.render_mode == GameState.RenderMode.TOPDOWN)

func _enemy_anim_update(delta: float) -> void:
	if _lbl == null:
		return
	_anim_t += delta
	if _anim_t >= 0.40:
		_anim_t = 0.0
		_anim_f = 1 - _anim_f
		_lbl.text = ART_F0 if _anim_f == 0 else ART_F1
	# Brief brightening pulse right before / after a spawn so the player can
	# read "this just produced something" even if the minion ran off-screen.
	if _telegraph_t > 0.0 and _hit_flash_t <= 0.0:
		var pulse: float = _telegraph_t / 0.6
		_lbl.modulate = Color(1.0,
			lerpf(0.55, 0.95, pulse),
			lerpf(0.25, 0.65, pulse))

# Suppress the base-class gold + bag rolls so the custom _on_death below is
# the sole source of nest drops (no double-pickup). EnemyBase calls _on_death
# first, then _drop_gold_pickup + _maybe_drop_bag unconditionally.
func _drop_gold_pickup() -> void:
	pass

func _maybe_drop_bag() -> void:
	pass

# Custom death override — richer drop than a regular enemy since the player
# had to find AND fight through minions to clear the nest.
func _on_death() -> void:
	var diff: float = GameState.test_difficulty if GameState.test_mode else GameState.difficulty
	var gold_amt: int = int(round(float(randi_range(8, 18)) * (1.0 + diff * 0.10)))
	for _i in mini(gold_amt, 5):
		# Spread coin-pickups around the corpse so the drop reads as a real
		# reward and not a single floating number.
		var gold := GOLD_PICKUP_SCENE.instantiate()
		gold.global_position = global_position + Vector2(randf_range(-22, 22), randf_range(-22, 22))
		@warning_ignore("integer_division")
		gold.value = maxi(1, gold_amt / 5)
		get_tree().current_scene.call_deferred("add_child", gold)
	var bag := LOOT_BAG_SCENE.instantiate()
	bag.global_position = global_position
	get_tree().current_scene.call_deferred("add_child", bag)
	# 10% bonus champion-tier item — fat reward roll, mirrors champion logic.
	if randf() < 0.10:
		var extra := LOOT_BAG_SCENE.instantiate()
		extra.global_position = global_position + Vector2(randf_range(-30, 30), randf_range(-30, 30))
		extra.items = [ItemDB.random_drop(), ItemDB.random_drop()]
		get_tree().current_scene.call_deferred("add_child", extra)
	FloatingText.spawn_str(global_position, "NEST DESTROYED",
		Color(0.95, 0.55, 0.95), get_tree().current_scene)
