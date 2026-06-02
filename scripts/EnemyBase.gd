class_name EnemyBase
extends CharacterBody2D

# Shared base for all enemies — handles status effects, sight, drops, hit flash,
# label/font setup. Subclasses override _on_ready_extra(), _enemy_tick(delta),
# and _enemy_anim_update(delta) to provide unique behavior.

const GOLD_PICKUP_SCENE := preload("res://scenes/GoldPickup.tscn")
const LOOT_BAG_SCENE    := preload("res://scenes/LootBag.tscn")
const FIRE_PATCH_SCRIPT = preload("res://scripts/FirePatch.gd")

@export var max_health: int = 5

var health: int                = 5
var passive: bool              = false
var _player: Node2D            = null
var _has_aggro: bool           = false
var _sight_timer: float        = 0.0
var _sight_range: float        = 560.0   # ~17 tiles — covers a typical room end-to-end
const SIGHT_CHECK_INTERVAL     := 0.10

# Difficulty-scaled aggro multiplier — applied to _sight_range each frame
# during the sight check so high-tier floors aggro the player from much
# further out. ≥3.0 → ×1.3,  ≥5.0 → ×1.6.
static func _aggro_range_mult() -> float:
	var d: float = GameState.test_difficulty if GameState.test_mode else GameState.difficulty
	if d >= 5.0: return 1.6
	if d >= 3.0: return 1.3
	return 1.0

# Status effects
var _chill_stacks: int        = 0
var _chill_decay_t: float     = 0.0
var _frozen: bool             = false
var _frozen_timer: float      = 0.0
var _burn_stacks: int         = 0
var _enflamed: bool           = false
var _enflame_timer: float     = 0.0
var _enflame_tick: float      = 0.0
# Extra burn hits accumulated while already ENFLAMED. Every 2 hits spawn a
# fresh ground-fire patch (same trigger as the initial enflame) so sustained
# fire pressure on a burning target keeps stacking AoE pools at its feet.
var _enflame_extra_hits: int  = 0
var _shock_stacks: int        = 0
var _stun_timer: float        = 0.0
var _no_attack_timer: float   = 0.0
var _poison_stacks: int       = 0
var _poisoned: bool           = false
var _poison_timer: float      = 0.0
var _poison_tick: float       = 0.0

# Visual / hit
var _hit_flash_t: float       = 0.0
var _telegraphing: bool       = false
var _last_modulate: Color     = Color.WHITE  # cache to skip redundant writes
var _dmg_text_cd: float       = 0.0
# Aggregated damage text — hits land into _dmg_text_pending and a single
# floating number with the running total appears after _dmg_text_flush_t
# elapses. Cuts visual noise during high fire-rate combat.
var _dmg_text_pending: int    = 0
var _dmg_text_flush_t: float  = 0.0
const _DMG_TEXT_WINDOW: float = 0.20
var _lbl: Label               = null
var _health_bar_fg: Control   = null
var _status_lbl: RichTextLabel = null  # tiny per-element status-stack readout above the bar
var _last_status_text: String = ""

# Elite/champion (set externally by World._place_enemy)
var is_elite: bool            = false
var is_champion: bool         = false
var elite_modifier: int       = 0
var _shield_active: bool      = false
var _split_scene: PackedScene = null

# Buff (Enchanter compat)
var _speed_multiplier: float  = 1.0
var _buff_timer: float        = 0.0

static var _shared_font: Font = null

func _ready() -> void:
	# Move enemies onto layer 2 so they DON'T physically push each other or
	# the player around. Walls (layer 1) and projectiles (mask now 3) still
	# detect us correctly.
	collision_layer = 2
	collision_mask  = 1
	health = max_health
	_player = get_tree().get_first_node_in_group("player")
	if elite_modifier == 1:
		_shield_active = true
	_health_bar_fg = get_node_or_null("HealthBar/Foreground")
	_lbl = get_node_or_null("AsciiChar")
	if _lbl:
		_setup_label_font()
	_setup_status_label()
	_update_health_bar()
	# First-person modes hide every top-down glyph the enemy owns
	# (AsciiChar + status strip + HP bar). The rig draws its own
	# representation; we don't want the 2D bits leaking through.
	if not GameState.render_mode_changed.is_connected(_on_render_mode_changed):
		GameState.render_mode_changed.connect(_on_render_mode_changed)
	_apply_render_mode_visibility()
	# If a first-person rig is already live (we spawned mid-run, after the
	# user has cycled into a FP mode), self-register so the rig can render
	# us. Entities that spawn during World._ready before the rig is active
	# get bulk-registered by World._apply_render_mode.
	if GameState.active_rig != null and is_instance_valid(GameState.active_rig) \
			and GameState.active_rig.has_method("register_entity"):
		var enemy_glyph: String = "B" if (is_elite or is_champion) else "d"
		var tier: int = 2 if is_champion else (1 if is_elite else 0)
		GameState.active_rig.register_entity(self, enemy_glyph, GameState.enemy_fp_color(tier))
	_on_ready_extra()

func _exit_tree() -> void:
	# Drop our entry from the rig's registry on death / despawn so the rig
	# stops syncing a body that no longer exists.
	if GameState.active_rig != null and is_instance_valid(GameState.active_rig) \
			and GameState.active_rig.has_method("unregister_entity"):
		GameState.active_rig.unregister_entity(self)

func _on_render_mode_changed(_mode: int) -> void:
	_apply_render_mode_visibility()

func _apply_render_mode_visibility() -> void:
	var fp_active: bool = GameState.render_mode != GameState.RenderMode.TOPDOWN
	if _lbl != null:
		_lbl.visible = not fp_active
	if _status_lbl != null and fp_active:
		_status_lbl.visible = false
	# Hide the health bar's two ColorRect children too — the bar lives on the
	# enemy body and would otherwise float in space behind the FP overlay.
	var bar_bg := get_node_or_null("HealthBar")
	if bar_bg != null:
		bar_bg.visible = not fp_active

# Tiny ASCII strip (e.g. "B5 C3") above the health bar showing active status
# stacks at a glance. Updated each frame from _tick_anim_base.
func _setup_status_label() -> void:
	# RichTextLabel so each element's stack count can be its own color.
	# Plain Label gave one global tint, which made it hard to tell at a
	# glance whether the next chill stack would FREEZE or the next burn
	# stack would ENFLAME — info builds care about a lot.
	_status_lbl = RichTextLabel.new()
	_status_lbl.name = "StatusStrip"
	_status_lbl.position = Vector2(-34.0, -34.0)
	_status_lbl.size     = Vector2(72.0, 16.0)
	_status_lbl.bbcode_enabled = true
	_status_lbl.fit_content = false
	_status_lbl.scroll_active = false
	_status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_lbl.add_theme_font_size_override("normal_font_size", 11)
	_status_lbl.add_theme_color_override("default_color", Color(0.95, 0.95, 0.95))
	_status_lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_status_lbl.add_theme_constant_override("outline_size", 2)
	# Center-align via BBCode wrapper. RichTextLabel has no horiz_align prop.
	_status_lbl.visible = false
	add_child(_status_lbl)

func _setup_label_font() -> void:
	if _shared_font == null:
		_shared_font = MonoFont.get_font()
	_lbl.add_theme_font_override("font", _shared_font)
	_lbl.add_theme_font_size_override("font_size", 13)
	_lbl.add_theme_constant_override("line_separation", -4)
	_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_TOP
	_lbl.offset_left   = -34
	_lbl.offset_top    = -44
	_lbl.offset_right  =  38
	_lbl.offset_bottom =  14

func _on_ready_extra() -> void: pass

func _physics_process(delta: float) -> void:
	if _buff_timer > 0.0:
		_buff_timer -= delta
		if _buff_timer <= 0.0:
			_speed_multiplier = 1.0
			_on_buff_end()
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(_player):
		return
	if not _has_aggro:
		_sight_timer -= delta
		if _sight_timer <= 0.0:
			_sight_timer = SIGHT_CHECK_INTERVAL
			_check_sight()
	_tick_status(delta)
	if not is_instance_valid(self):
		return
	_enemy_tick(delta)
	move_and_slide()
	_tick_anim_base(delta)

func _enemy_tick(_delta: float) -> void: pass
func _on_buff_end() -> void: pass
func _on_buff_start() -> void: pass
func _enemy_anim_update(_delta: float) -> void: pass
func _on_death() -> void: pass

func _tick_status(delta: float) -> void:
	if _frozen:
		_frozen_timer -= delta
		if _frozen_timer <= 0.0:
			_frozen = false
			_chill_stacks = 0
	elif _chill_stacks > 0:
		_chill_decay_t -= delta
		if _chill_decay_t <= 0.0:
			_chill_decay_t = 2.5
			_chill_stacks -= 1
	if _enflamed:
		_enflame_timer -= delta
		if _enflame_timer <= 0.0:
			_enflamed = false
		else:
			_enflame_tick -= delta
			if _enflame_tick <= 0.0:
				_enflame_tick = 0.45
				# Fire DOT scales with INT now — base 3, +1 per 2 INT.
				var fire_tick: int = 3 + int(GameState.get_stat_bonus("INT")) / 2
				if not _credit_dot_damage("fire", fire_tick):
					return
	if _stun_timer > 0.0:
		_stun_timer -= delta
	if _no_attack_timer > 0.0:
		_no_attack_timer -= delta
	if _dmg_text_cd > 0.0:
		_dmg_text_cd -= delta
	# Flush aggregated damage when the window expires.
	if _dmg_text_flush_t > 0.0:
		_dmg_text_flush_t -= delta
		if _dmg_text_flush_t <= 0.0 and _dmg_text_pending > 0:
			FloatingText.spawn(global_position, _dmg_text_pending, false, get_tree().current_scene)
			_dmg_text_pending = 0
	if _hit_flash_t > 0.0:
		_hit_flash_t -= delta
	if _poisoned:
		_poison_timer -= delta
		if _poison_timer <= 0.0:
			_poisoned = false
		else:
			_poison_tick -= delta
			if _poison_tick <= 0.0:
				_poison_tick = 0.28
				if not _credit_dot_damage("poison", 5):
					return

func apply_status(effect: String, _duration: float) -> void:
	match effect:
		"freeze_hit":
			if _frozen: return
			# Splash freeze stacks only count against enemies the player has
			# already engaged. Without this, pierce/ricochet bolts grazing
			# adjacent rooms (or hitting through doorways) silently stack
			# unaggro'd enemies toward FROZEN before the player ever sees
			# them — portal rooms ended up pre-frozen on approach.
			if not _has_aggro: return
			var f_stacks: int = maxi(1, int(_duration))
			_chill_stacks = mini(_chill_stacks + f_stacks, 10)
			_chill_decay_t = 3.0
			if _chill_stacks >= 10:
				_frozen = true
				_frozen_timer = 4.5
				FloatingText.spawn_str(global_position, "FROZEN!", Color(0.7, 0.95, 1.0), get_tree().current_scene)
		"burn_hit":
			var b_stacks: int = maxi(1, int(_duration))
			if _enflamed:
				# Re-igniting an already-burning target: extend timer and
				# splash fire to neighbors instead of stacking further.
				# Every 2 burn-hits while ENFLAMED also drop a fresh ground
				# patch at the target's feet (handled by register_extra_burn).
				EnflameOverlay.refresh_pulse(self)
				EnflameOverlay.register_extra_burn(self, b_stacks)
			else:
				_burn_stacks = mini(_burn_stacks + b_stacks, 6)
				# Enflame threshold dropped 10 → 6 so fire ramps up faster.
				if _burn_stacks >= 6:
					_burn_stacks = 0
					_trigger_enflamed()
		"shock_hit":
			var s_stacks: int = maxi(1, int(_duration))
			_shock_stacks = mini(_shock_stacks + s_stacks, 10)
			if _shock_stacks >= 10:
				_shock_stacks = 0
				_trigger_electrified()
		"poison_hit":
			_poison_stacks = mini(_poison_stacks + 1, 10)
			if _poison_stacks >= 10:
				_poison_stacks = 0
				_trigger_poisoned()

func _trigger_enflamed() -> void:
	FloatingText.spawn_str(global_position, "ENFLAMED!", Color(1.0, 0.3, 0.0), get_tree().current_scene)
	_enflamed = true
	_enflame_timer = 5.0
	_enflame_tick = 0.0
	_enflame_extra_hits = 0
	# Visual: ASCII flames mounted directly on the entity AND a ground-fire
	# patch spawned underneath. The mounted flames track the moving target;
	# the ground patch lingers in place so kiting through a burned cluster
	# leaves a trail of damaging tiles.
	EnflameOverlay.sync_to(self, true)
	EnflameOverlay.spawn_patch(self)
	# Enflame trigger damage scales with INT — base 12, +1 per INT point.
	var enflame_dmg: int = 12 + int(GameState.get_stat_bonus("INT"))
	if not _credit_dot_damage("fire", enflame_dmg):
		return
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy) or enemy == self: continue
		if global_position.distance_to(enemy.global_position) < 160.0:
			if enemy.has_method("_add_burn_stacks"):
				enemy._add_burn_stacks(5)

func _add_burn_stacks(count: int) -> void:
	_burn_stacks = mini(_burn_stacks + count, 9)

func _trigger_electrified() -> void:
	FloatingText.spawn_str(global_position, "ELECTRIFIED!", Color(0.75, 0.9, 1.0), get_tree().current_scene)
	if not _credit_dot_damage("shock", 10):
		return
	# Pulsing stun — 1–3 brief stuns separated by short recovery gaps,
	# managed by the ElectricBolt overlay. Shows lightning art on each
	# pulse so the debuff has a clear visual beat.
	ElectricBolt.trigger(self)
	# FP: radial burst + expanding ring so the proc reads as a dramatic
	# electrical explosion in first-person.
	var rig := GameState.active_rig
	if rig != null and is_instance_valid(rig):
		var pos: Vector2 = global_position
		if rig.has_method("spawn_burst_2d"):
			rig.spawn_burst_2d(pos, "~", Color(1.0, 0.95, 0.2), 8, 0.5,
					0.30, Vector2.ZERO, TAU, 0.012, 0.55)
		if rig.has_method("spawn_ring_2d"):
			rig.spawn_ring_2d(pos, "~", Color(0.8, 1.0, 0.3),
					0.2, 1.2, 12, 0.28, 0.010, 0.55)

func _trigger_poisoned() -> void:
	FloatingText.spawn_str(global_position, "POISONED!", Color(0.2, 1.0, 0.35), get_tree().current_scene)
	_poisoned = true
	_poison_timer = 9.0
	_poison_tick = 0.0

func _check_sight() -> void:
	if passive: return
	# Effective sight range stretches at high difficulty so enemies aggro
	# from further away, putting more pressure on a player trying to slip
	# past them. Multiplier is bounded; at low diff it's exactly the
	# original behavior.
	var eff_range: float = _sight_range * _aggro_range_mult()
	if global_position.distance_squared_to(_player.global_position) > eff_range * eff_range:
		return
	var space := get_world_2d().direct_space_state
	var params := PhysicsRayQueryParameters2D.create(global_position, _player.global_position)
	params.exclude = [get_rid()]
	# Only check walls (layer 1) and the player (also layer 1). Without
	# this filter the ray hits *other enemies* on layer 2 first when the
	# floor is packed, fails the "collider == player" check, and the
	# enemy stays passive even though it's looking right at the player —
	# producing a noticeable delay between portal entry and the first
	# enemy aggroing.
	params.collision_mask = 1
	var hit := space.intersect_ray(params)
	if hit.is_empty() or hit.get("collider") == _player:
		_has_aggro = true
		FloatingText.spawn_str(global_position, "!", Color(1.0, 0.9, 0.0), get_tree().current_scene)

# Wake this enemy if a loud event happened within `radius`. Generic "heard you"
# hook — used by ambush springs now, and sound-propagation alerting later.
func alert_by_sound(source_pos: Vector2, radius: float) -> void:
	if passive or _has_aggro:
		return
	if global_position.distance_to(source_pos) <= radius:
		_has_aggro = true
		FloatingText.spawn_str(global_position, "!", Color(1.0, 0.9, 0.0), get_tree().current_scene)

func take_damage(amount: int, _source: Node = null) -> void:
	if _shield_active:
		_shield_active = false
		FloatingText.spawn_str(global_position, "BLOCKED!", Color(0.4, 0.9, 1.0), get_tree().current_scene)
		return
	if not passive and not _has_aggro:
		_has_aggro = true
		FloatingText.spawn_str(global_position, "!", Color(1.0, 0.9, 0.0), get_tree().current_scene)
	var actual := int(float(amount) * 1.25) if (_frozen or _chill_stacks > 0) else amount
	health -= actual
	_hit_flash_t = 0.14
	# Aggregate damage numbers — accumulate hits inside a short window then
	# spawn one labeled "23" instead of three "8s". A pending hit kicks off
	# the flush timer; subsequent hits before flush just add to the total.
	_dmg_text_pending += actual
	if _dmg_text_flush_t <= 0.0:
		_dmg_text_flush_t = _DMG_TEXT_WINDOW
	_update_health_bar()
	if health <= 0:
		# Flush aggregated damage on death so the killing blow is visible.
		if _dmg_text_pending > 0:
			FloatingText.spawn(global_position, _dmg_text_pending, false, get_tree().current_scene)
			_dmg_text_pending = 0
		_on_death()
		GameState.kills += 1
		GameState.last_kill_msec = Time.get_ticks_msec()
		GameState.since_kill_s = 0.0
		GameState.add_xp(5)
		QuestLog.note_kill(self)
		# Test-mode drops toggle — when disabled, enemies skip their entire
		# drop block (gold, loot bags, champion treasure). Lets the user
		# tune combat without piles of pickups cluttering the arena.
		var drops_ok: bool = not (GameState.test_mode and not GameState.test_drops_enabled)
		if drops_ok:
			# Always spawn the gold coin pickup. The bag drop is split off
			# into a separate path so the per-enemy bag count is exactly
			# one OR zero — no more "champion drops three bags at high
			# difficulty" piles.
			_drop_gold_pickup()
			if is_champion:
				_drop_champion_loot()
			else:
				if elite_modifier == 2 and _split_scene != null:
					_do_split()
				if elite_modifier == 5:
					_do_volatile()
				_maybe_drop_bag()
		# Catacombs biome mechanic — 25 % of regular non-boss / non-champion
		# deaths roll a delayed zombie reanimation 5 s later at the corpse
		# position. Schedule before queue_free; the timer callback does the
		# spawn via the scene tree, never references self.
		if GameState.biome == 1 and not is_champion:
			_schedule_catacombs_reanimation(global_position, get_tree())
		EffectFx.spawn_death_pop(global_position, get_tree().current_scene)
		queue_free()

# Spawns a low-HP EnemyChaser at the given position 5 s after the host
# died. Uses get_tree().create_timer so the host can be freed safely;
# the captured `pos` is value-typed (Vector2), no dangling reference.
static func _schedule_catacombs_reanimation(pos: Vector2, tree: SceneTree) -> void:
	if randf() >= 0.10:
		return
	if tree == null:
		return
	var scene_root := tree.current_scene
	if scene_root == null:
		return
	const CHASER_SCENE := preload("res://scenes/EnemyChaser.tscn")
	var t := tree.create_timer(5.0)
	t.timeout.connect(func() -> void:
		var current := tree.current_scene
		if current == null:
			return
		var enemies := current.get_node_or_null("Enemies")
		if enemies == null:
			return
		# Respect the global live-enemy cap (checked at spawn time, not schedule time).
		if current.has_method("can_spawn_enemy") and not current.can_spawn_enemy():
			return
		# Faint green telegraph at the spawn point so the player knows
		# something's about to rise.
		FloatingText.spawn_str(pos, "RISES…",
			Color(0.55, 0.95, 0.6), current)
		var z: Node = CHASER_SCENE.instantiate()
		if z is Node2D:
			(z as Node2D).global_position = pos
		# Mark as reanimated so EnemyChaser._ready can dial down HP/dmg.
		# Set as metadata so we don't need a real property on the script.
		z.set_meta("is_zombie_revive", true)
		enemies.add_child(z))

func _do_volatile() -> void:
	FloatingText.spawn_str(global_position, "BOOM!", Color(1.0, 0.55, 0.0), get_tree().current_scene)
	var dmg := int(max_health / 3)
	damage_player_in_radius(dmg, 90.0)
	var fp := FIRE_PATCH_SCRIPT.new()
	if fp is Node2D:
		(fp as Node2D).position = global_position
	get_tree().current_scene.call_deferred("add_child", fp)

static func volatile_explosion(pos: Vector2, hp: int, player: Node, scene: Node, source: Node = null) -> void:
	FloatingText.spawn_str(pos, "BOOM!", Color(1.0, 0.55, 0.0), scene)
	var dmg := int(hp / 3)
	if is_instance_valid(player) and player.has_method("take_damage"):
		if pos.distance_to(player.global_position) <= 90.0:
			# Caller passes the exploding enemy so the death log attributes
			# the hit to "EnemyArcher" / "EnemyChaser" / etc. instead of "?".
			player.take_damage(dmg, source)
	const FP := preload("res://scripts/FirePatch.gd")
	var fp: Node = FP.new()
	if fp is Node2D:
		(fp as Node2D).position = pos
	scene.call_deferred("add_child", fp)

func _do_split() -> void:
	var scene_node := get_tree().current_scene
	# Respect the global live-enemy cap so splitters can't snowball the count.
	if scene_node != null and scene_node.has_method("can_spawn_enemy") and not scene_node.can_spawn_enemy():
		return
	if scene_node == null:
		return
	FloatingText.spawn_str(global_position, "SPLIT!", Color(0.9, 0.4, 1.0), scene_node)
	var enemies_node := scene_node.get_node_or_null("Enemies")
	if enemies_node == null: return
	for _i in 2:
		var clone: Node = _split_scene.instantiate()
		clone.position = global_position + Vector2(randf_range(-28.0, 28.0), randf_range(-28.0, 28.0))
		if "max_health" in clone:
			clone.max_health = maxi(1, max_health / 2)
		if "elite_modifier" in clone:
			clone.elite_modifier = 0
		enemies_node.call_deferred("add_child", clone)

func heal(amount: int) -> void:
	var prev := health
	health = mini(health + amount, max_health)
	var gained := health - prev
	if gained > 0:
		FloatingText.spawn(global_position, gained, true, get_tree().current_scene)
	_update_health_bar()

func apply_buff(duration: float) -> void:
	_speed_multiplier = 2.0
	_buff_timer += duration
	_on_buff_start()

# Champion drop — a single fatter bag with two guaranteed items, instead
# of two separate one-item bags (the old behavior). One-bag-per-enemy is
# the project-wide invariant now; the room-clear merge no longer has to
# fight piles of champion loot.
func _drop_champion_loot() -> void:
	var bag := LOOT_BAG_SCENE.instantiate()
	bag.global_position = global_position + Vector2(randf_range(-24, 24), randf_range(-24, 24))
	bag.items = [ItemDB.random_drop(), ItemDB.random_drop()]
	get_tree().current_scene.call_deferred("add_child", bag)

# Gold-coin pickup only. Used to be combined with the probabilistic bag
# spawn inside `_drop_gold`, but that meant a champion enemy could end up
# dropping 3 bags total (1 chance bag + 2 from _drop_champion_loot). Now
# the bag spawn lives in `_maybe_drop_bag` so the kill path can pick AT
# MOST one bag-drop call site per enemy.
func _drop_gold_pickup() -> void:
	if GameState.test_mode:
		GameState.gold += int(randi_range(1, 5) * (3 if is_elite else 1) * GameState.loot_multiplier)
		return
	var gold := GOLD_PICKUP_SCENE.instantiate()
	gold.global_position = global_position
	gold.value = int(randi_range(1, 5) * (3 if is_elite else 1) * GameState.loot_multiplier)
	get_tree().current_scene.call_deferred("add_child", gold)

# Probabilistic bag drop for non-champion enemies. Rates fall with difficulty:
# more enemies spawn at higher tiers, so per-kill odds must drop to keep total
# floor loot manageable. Elite 25%→8%, regular 5%→2% across diff 1→11+.
func _maybe_drop_bag() -> void:
	if GameState.test_mode:
		return
	# Enemies finished off by monster infighting drop no loot bag (XP/gold still
	# flow) so "let them kill each other" can't be AFK-farmed for items.
	if get_meta("_infight_victim", false):
		return
	var diff_extra: float = maxf(0.0, GameState.difficulty - 1.0)
	var elite_chance: int = clampi(25 - int(diff_extra * 1.5), 8, 25)
	var reg_chance: int   = clampi(5  - int(diff_extra * 0.3), 2,  5)
	if (is_elite and randi() % 100 < elite_chance) or randi() % 100 < reg_chance:
		var bag := LOOT_BAG_SCENE.instantiate()
		bag.global_position = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		get_tree().current_scene.call_deferred("add_child", bag)

func _update_health_bar() -> void:
	if _health_bar_fg == null: return
	var ratio := clampf(float(health) / float(max_health), 0.0, 1.0)
	_health_bar_fg.offset_right = -20.0 + 40.0 * ratio

func _get_status_modulate() -> Color:
	if _frozen: return StatusTint.frozen()
	if _stun_timer > 0.0: return StatusTint.stun()
	if _poisoned: return Color(0.45, 1.0, 0.55)
	if _enflamed:
		var f := sin(Time.get_ticks_msec() * 0.025) * 0.12 + 0.88
		return Color(1.0, f * 0.35, 0.05)
	if _chill_stacks > 0:
		var t := float(_chill_stacks) / 10.0
		return Color(lerpf(1.0, 0.55, t), lerpf(1.0, 0.82, t), 1.0)
	if _burn_stacks > 0:
		var t2 := float(_burn_stacks) / 10.0
		return Color(1.0, lerpf(1.0, 0.35, t2), lerpf(1.0, 0.05, t2))
	if _shock_stacks > 0:
		var t3 := float(_shock_stacks) / 10.0
		return Color(1.0, 1.0, lerpf(1.0, 0.2, t3))
	if _poison_stacks > 0:
		var t4 := float(_poison_stacks) / 10.0
		return Color(lerpf(1.0, 0.45, t4), 1.0, lerpf(1.0, 0.55, t4))
	return Color.WHITE

func _tick_anim_base(delta: float) -> void:
	if _lbl == null: return
	_enemy_anim_update(delta)
	FrozenBlock.sync_to(self, _frozen)
	EnflameOverlay.sync_to(self, _enflamed)
	PoisonOverlay.sync_to(self, _poisoned)
	var target: Color
	if _hit_flash_t > 0.0:
		target = Color(1.0, 0.3, 0.3)
	elif _telegraphing:
		var blink := sin(Time.get_ticks_msec() * 0.015) * 0.5 + 0.5
		target = Color(1.0, lerpf(0.8, 0.1, blink), lerpf(0.7, 0.0, blink))
	else:
		target = _get_status_modulate()
	# Skip the write when it would be a no-op — most idle enemies paint pure
	# white every frame, which still flushes Control change notifications.
	if not target.is_equal_approx(_last_modulate):
		_lbl.modulate = target
		_last_modulate = target
	_update_status_strip()

# Refreshes the per-enemy status icon strip. Each element gets its own
# BBCode color so the player can scan for the build-relevant status at a
# glance. When a stack count is one short of the threshold (or the proc
# is currently active) the entry brightens / bolds so "next hit FREEZES"
# is obvious without counting tiny digits.
func _update_status_strip() -> void:
	if _status_lbl == null:
		return
	var parts: Array = []
	if _frozen:
		parts.append("[color=#aef0ff][b]FRZ[/b][/color]")
	elif _chill_stacks > 0:
		# Threshold = 10. Brighten + bold once the next stack would freeze.
		var hot: bool = _chill_stacks >= 9
		var col: String = "#aef0ff" if hot else "#7ec8ff"
		var bb: String = "[color=%s]C%d[/color]" % [col, _chill_stacks]
		if hot:
			bb = "[b]" + bb + "[/b]"
		parts.append(bb)
	if _enflamed:
		parts.append("[color=#ffb060][b]ENF[/b][/color]")
	elif _burn_stacks > 0:
		var hot: bool = _burn_stacks >= 5
		var col: String = "#ffb060" if hot else "#ff8030"
		var bb: String = "[color=%s]B%d[/color]" % [col, _burn_stacks]
		if hot:
			bb = "[b]" + bb + "[/b]"
		parts.append(bb)
	if _stun_timer > 0.0:
		parts.append("[color=#fff080][b]STN[/b][/color]")
	elif _shock_stacks > 0:
		var hot: bool = _shock_stacks >= 9
		var col: String = "#fff080" if hot else "#ffe040"
		var bb: String = "[color=%s]S%d[/color]" % [col, _shock_stacks]
		if hot:
			bb = "[b]" + bb + "[/b]"
		parts.append(bb)
	if _poisoned:
		parts.append("[color=#a0ff80][b]POI[/b][/color]")
	elif _poison_stacks > 0:
		parts.append("[color=#80d060]P%d[/color]" % _poison_stacks)
	var txt: String = " ".join(parts)
	if txt == _last_status_text:
		return
	_last_status_text = txt
	# Wrap in a center tag so the multi-color line stays head-aligned.
	_status_lbl.text = "[center]" + txt + "[/center]" if txt != "" else ""
	_status_lbl.visible = txt != ""

# DoT damage source attribution. Wraps take_damage and credits the deducted
# HP (post-DEF, post-modifiers) to the supplied wand type so the per-weapon
# stats panel reflects burn/shock/poison ticks. Returns false if this enemy
# died from the hit so the caller can short-circuit further work.
func _credit_dot_damage(wand_type: String, amount: int) -> bool:
	var prev_hp: int = health
	take_damage(amount)
	if not is_instance_valid(self):
		return false
	var dealt: int = maxi(0, prev_hp - health)
	if dealt > 0:
		GameState.record_weapon_damage(wand_type, dealt)
		GameState.damage_dealt += dealt
	if is_queued_for_deletion():
		GameState.record_weapon_kill(wand_type)
		return false
	return true

func damage_player_in_radius(amount: int, radius: float) -> void:
	if not is_instance_valid(_player): return
	if global_position.distance_to(_player.global_position) <= radius:
		if _player.has_method("take_damage"):
			_player.take_damage(amount, self)
