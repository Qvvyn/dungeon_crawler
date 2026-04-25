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

# Status effects
var _chill_stacks: int        = 0
var _chill_decay_t: float     = 0.0
var _frozen: bool             = false
var _frozen_timer: float      = 0.0
var _burn_stacks: int         = 0
var _enflamed: bool           = false
var _enflame_timer: float     = 0.0
var _enflame_tick: float      = 0.0
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
var _status_lbl: Label        = null   # tiny status-stack readout above the bar
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
	_on_ready_extra()

# Tiny ASCII strip (e.g. "B5 C3") above the health bar showing active status
# stacks at a glance. Updated each frame from _tick_anim_base.
func _setup_status_label() -> void:
	_status_lbl = Label.new()
	_status_lbl.name = "StatusStrip"
	_status_lbl.position = Vector2(-26.0, -32.0)
	_status_lbl.size     = Vector2(56.0, 14.0)
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.add_theme_font_size_override("font_size", 9)
	_status_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	_status_lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_status_lbl.add_theme_constant_override("outline_size", 2)
	_status_lbl.visible = false
	add_child(_status_lbl)

func _setup_label_font() -> void:
	if _shared_font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Consolas", "Courier New", "Lucida Console"])
		_shared_font = f
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
				if not _credit_dot_damage("fire", 3):
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
			_chill_stacks = mini(_chill_stacks + 1, 10)
			_chill_decay_t = 3.0
			if _chill_stacks >= 10:
				_frozen = true
				_frozen_timer = 4.5
				FloatingText.spawn_str(global_position, "FROZEN!", Color(0.7, 0.95, 1.0), get_tree().current_scene)
		"burn_hit":
			_burn_stacks = mini(_burn_stacks + 1, 10)
			if _burn_stacks >= 10:
				_burn_stacks = 0
				_trigger_enflamed()
		"shock_hit":
			_shock_stacks = mini(_shock_stacks + 1, 10)
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
	# Drop a fire patch at the enemy's feet
	var fp := Node2D.new()
	fp.set_script(FIRE_PATCH_SCRIPT)
	fp.global_position = global_position
	get_tree().current_scene.add_child(fp)
	if not _credit_dot_damage("fire", 12):
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
	_stun_timer = 0.5
	_no_attack_timer = 1.5

func _trigger_poisoned() -> void:
	FloatingText.spawn_str(global_position, "POISONED!", Color(0.2, 1.0, 0.35), get_tree().current_scene)
	_poisoned = true
	_poison_timer = 9.0
	_poison_tick = 0.0

func _check_sight() -> void:
	if passive: return
	if global_position.distance_squared_to(_player.global_position) > _sight_range * _sight_range:
		return
	var space := get_world_2d().direct_space_state
	var params := PhysicsRayQueryParameters2D.create(global_position, _player.global_position)
	params.exclude = [get_rid()]
	var hit := space.intersect_ray(params)
	if hit.is_empty() or hit.get("collider") == _player:
		_has_aggro = true
		FloatingText.spawn_str(global_position, "!", Color(1.0, 0.9, 0.0), get_tree().current_scene)

func take_damage(amount: int) -> void:
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
		GameState.add_xp(5)
		if is_champion:
			_drop_champion_loot()
		else:
			if elite_modifier == 2 and _split_scene != null:
				_do_split()
			_drop_gold()
		queue_free()

func _do_split() -> void:
	FloatingText.spawn_str(global_position, "SPLIT!", Color(0.9, 0.4, 1.0), get_tree().current_scene)
	var enemies_node := get_tree().current_scene.get_node_or_null("Enemies")
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

func _drop_champion_loot() -> void:
	_drop_gold()
	for _i in 2:
		var bag := LOOT_BAG_SCENE.instantiate()
		bag.global_position = global_position + Vector2(randf_range(-32, 32), randf_range(-32, 32))
		bag.items = [ItemDB.random_drop()]
		get_tree().current_scene.call_deferred("add_child", bag)

func _drop_gold() -> void:
	if GameState.test_mode:
		GameState.gold += int(randi_range(1, 5) * (3 if is_elite else 1) * GameState.loot_multiplier)
		return
	var gold := GOLD_PICKUP_SCENE.instantiate()
	gold.global_position = global_position
	gold.value = int(randi_range(1, 5) * (3 if is_elite else 1) * GameState.loot_multiplier)
	get_tree().current_scene.call_deferred("add_child", gold)
	# Bag drop: 50% on elites, 8% on regular kills (was 100%/30%)
	if (is_elite and randi() % 100 < 50) or randi() % 100 < 8:
		var bag := LOOT_BAG_SCENE.instantiate()
		bag.global_position = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		get_tree().current_scene.call_deferred("add_child", bag)

func _update_health_bar() -> void:
	if _health_bar_fg == null: return
	var ratio := clampf(float(health) / float(max_health), 0.0, 1.0)
	_health_bar_fg.offset_right = -20.0 + 40.0 * ratio

func _get_status_modulate() -> Color:
	if _frozen: return Color(0.55, 0.82, 1.0)
	if _stun_timer > 0.0: return Color(0.9, 0.9, 0.3)
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

# Refreshes the per-enemy status icon strip — only writes the Label text
# when it actually changes, since most enemies have no statuses most frames.
func _update_status_strip() -> void:
	if _status_lbl == null:
		return
	var parts: Array = []
	if _frozen:
		parts.append("FRZ")
	elif _chill_stacks > 0:
		parts.append("C%d" % _chill_stacks)
	if _enflamed:
		parts.append("ENF")
	elif _burn_stacks > 0:
		parts.append("B%d" % _burn_stacks)
	if _stun_timer > 0.0:
		parts.append("STN")
	elif _shock_stacks > 0:
		parts.append("S%d" % _shock_stacks)
	if _poisoned:
		parts.append("POI")
	elif _poison_stacks > 0:
		parts.append("P%d" % _poison_stacks)
	var txt: String = " ".join(parts)
	if txt == _last_status_text:
		return
	_last_status_text = txt
	_status_lbl.text = txt
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
			_player.take_damage(amount)
