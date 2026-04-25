extends CharacterBody2D

const GOLD_PICKUP_SCENE := preload("res://scenes/GoldPickup.tscn")
const LOOT_BAG_SCENE    := preload("res://scenes/LootBag.tscn")
const FIRE_PATCH_SCRIPT = preload("res://scripts/FirePatch.gd")

@export var move_speed: float = 90.0
@export var max_health: int = 5
@export var enchant_interval: float = 5.0
@export var enchant_scene: PackedScene

const APPROACH_STOP_DIST := 80.0

# ASCII art frames — robed mage with staff
const ENCHANTER_F0 := "  /+\\ \n (o_o)\n  |~| \n /   \\"
const ENCHANTER_F1 := "  /+\\ \n (o_o)\n  |*| \n /   \\"

var health: int = 5
var passive: bool = false
var is_elite: bool    = false
var is_champion: bool = false
var _anim_timer: float = 0.0
var _anim_frame: int   = 0

# Elite modifiers (0=none 1=shielded 2=splitting 3=enraged)
var elite_modifier: int     = 0
var _shield_active: bool    = false
var _enrage_triggered: bool = false
var _split_scene: PackedScene = null
var _target: Node2D = null
var _enchant_timer: float = 2.0
var _speed_multiplier: float = 1.0
var _buff_timer: float = 0.0
var _effective_interval: float = 5.0

# ── Status effects (10-stack trigger system) ──────────────────────────────────
var _chill_stacks: int     = 0
var _chill_decay_t: float  = 0.0
var _frozen: bool          = false
var _frozen_timer: float   = 0.0
var _burn_stacks: int      = 0
var _enflamed: bool        = false
var _enflame_timer: float  = 0.0
var _enflame_tick: float   = 0.0
var _shock_stacks: int     = 0
var _stun_timer: float     = 0.0
var _no_attack_timer: float = 0.0
var _poison_stacks: int    = 0
var _poisoned: bool        = false
var _poison_timer: float   = 0.0
var _poison_tick: float    = 0.0

func _ready() -> void:
	collision_layer = 2
	collision_mask  = 1
	health = max_health
	_effective_interval = enchant_interval
	_update_health_bar()
	if enchant_scene == null:
		enchant_scene = load("res://scenes/EnchantProjectile.tscn")
	if elite_modifier == 1:
		_shield_active = true
	var lbl := get_node_or_null("AsciiChar")
	if lbl:
		var mono := SystemFont.new()
		mono.font_names = PackedStringArray(["Consolas", "Courier New", "Lucida Console"])
		lbl.add_theme_font_override("font", mono)
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_constant_override("line_separation", -4)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_TOP
		lbl.offset_left   = -30
		lbl.offset_top    = -58
		lbl.offset_right  =  32
		lbl.offset_bottom =  12
		lbl.text = ENCHANTER_F0

func _physics_process(delta: float) -> void:
	if _buff_timer > 0.0:
		_buff_timer -= delta
		if _buff_timer <= 0.0:
			_speed_multiplier = 1.0
			_effective_interval = enchant_interval

	_tick_status(delta)
	if not is_instance_valid(self): return

	_target = _nearest_ally()

	if _frozen or _stun_timer > 0.0:
		velocity = Vector2.ZERO
	elif _target != null:
		var slow_mult := clampf(1.0 - float(_chill_stacks) * 0.1, 0.0, 1.0)
		var to_target := _target.global_position - global_position
		if to_target.length() > APPROACH_STOP_DIST:
			velocity = to_target.normalized() * move_speed * _speed_multiplier * slow_mult
		else:
			velocity = Vector2.ZERO
	else:
		velocity = Vector2.ZERO
	move_and_slide()
	_tick_anim(delta)

	_enchant_timer -= delta
	if _enchant_timer <= 0.0 and _target != null and _no_attack_timer <= 0.0 and not passive:
		_enchant_timer = _effective_interval
		_cast(_target)

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
				take_damage(3)
				if not is_instance_valid(self): return
	if _stun_timer > 0.0:
		_stun_timer -= delta
	if _no_attack_timer > 0.0:
		_no_attack_timer -= delta
	if _poisoned:
		_poison_timer -= delta
		if _poison_timer <= 0.0:
			_poisoned = false
		else:
			_poison_tick -= delta
			if _poison_tick <= 0.0:
				_poison_tick = 0.28
				take_damage(5)
				if not is_instance_valid(self): return

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
			else:
				FloatingText.spawn_str(global_position, "CHILL %d/10" % _chill_stacks, Color(0.45, 0.82, 1.0), get_tree().current_scene)
		"burn_hit":
			_burn_stacks = mini(_burn_stacks + 1, 10)
			if _burn_stacks >= 10:
				_burn_stacks = 0
				FloatingText.spawn_str(global_position, "ENFLAMED!", Color(1.0, 0.3, 0.0), get_tree().current_scene)
				_enflamed = true
				_enflame_timer = 5.0
				_enflame_tick = 0.0
				var fp := Node2D.new()
				fp.set_script(FIRE_PATCH_SCRIPT)
				fp.global_position = global_position
				get_tree().current_scene.add_child(fp)
				take_damage(12)
			else:
				FloatingText.spawn_str(global_position, "BURN %d/10" % _burn_stacks, Color(1.0, 0.55, 0.2), get_tree().current_scene)
		"shock_hit":
			_shock_stacks = mini(_shock_stacks + 1, 10)
			if _shock_stacks >= 10:
				_shock_stacks = 0
				FloatingText.spawn_str(global_position, "ELECTRIFIED!", Color(0.75, 0.9, 1.0), get_tree().current_scene)
				take_damage(10)
				if is_instance_valid(self):
					_stun_timer = 0.5
					_no_attack_timer = 1.5
			else:
				FloatingText.spawn_str(global_position, "SHOCK %d/10" % _shock_stacks, Color(0.7, 0.85, 1.0), get_tree().current_scene)
		"poison_hit":
			_poison_stacks = mini(_poison_stacks + 1, 10)
			if _poison_stacks >= 10:
				_poison_stacks = 0
				FloatingText.spawn_str(global_position, "POISONED!", Color(0.2, 1.0, 0.35), get_tree().current_scene)
				_poisoned = true
				_poison_timer = 9.0
				_poison_tick = 0.0
			else:
				FloatingText.spawn_str(global_position, "VENOM %d/10" % _poison_stacks, Color(0.35, 1.0, 0.4), get_tree().current_scene)

func _add_burn_stacks(count: int) -> void:
	_burn_stacks = mini(_burn_stacks + count, 9)

func _nearest_ally() -> Node2D:
	var nearest_unbuffed: Node2D = null
	var best_unbuffed := INF
	var nearest_any: Node2D = null
	var best_any := INF
	for e: Node2D in get_tree().get_nodes_in_group("enemy"):
		if e == self:
			continue
		var d := global_position.distance_to(e.global_position)
		if d < best_any:
			best_any = d
			nearest_any = e
		var buff_timer = e.get("_buff_timer")
		var is_buffed: bool = buff_timer != null and float(buff_timer) > 0.0
		if not is_buffed and d < best_unbuffed:
			best_unbuffed = d
			nearest_unbuffed = e
	return nearest_unbuffed if nearest_unbuffed != null else nearest_any

func _tick_anim(delta: float) -> void:
	var lbl := get_node_or_null("AsciiChar")
	if lbl == null:
		return
	_anim_timer += delta
	if _anim_timer >= 0.5:
		_anim_timer = 0.0
		_anim_frame = 1 - _anim_frame
	lbl.text = ENCHANTER_F0 if _anim_frame == 0 else ENCHANTER_F1

func _cast(target: Node2D) -> void:
	if enchant_scene == null:
		return
	var proj := enchant_scene.instantiate()
	proj.global_position = global_position
	proj.direction = (target.global_position - global_position).normalized()
	proj.source_entity = self   # prevents the projectile hitting its own caster
	get_tree().current_scene.add_child(proj)
	if SoundManager:
		SoundManager.play("enchant", randf_range(0.95, 1.08))

func heal(amount: int) -> void:
	var prev := health
	health = mini(health + amount, max_health)
	var gained := health - prev
	if gained > 0:
		FloatingText.spawn(global_position, gained, true, get_tree().current_scene)
	_update_health_bar()

func apply_buff(duration: float) -> void:
	_speed_multiplier = 2.0
	_effective_interval = enchant_interval / 2.0
	_buff_timer += duration

func take_damage(amount: int) -> void:
	if _shield_active:
		_shield_active = false
		FloatingText.spawn_str(global_position, "BLOCKED!", Color(0.4, 0.9, 1.0), get_tree().current_scene)
		return
	var actual := int(float(amount) * 1.25) if (_frozen or _chill_stacks > 0) else amount
	health -= actual
	FloatingText.spawn(global_position, actual, false, get_tree().current_scene)
	_update_health_bar()
	if elite_modifier == 3 and not _enrage_triggered and health > 0 and health * 2 <= max_health:
		_enrage_triggered = true
		move_speed *= 1.5
		_effective_interval = maxf(1.0, _effective_interval * 0.6)
		FloatingText.spawn_str(global_position, "ENRAGED!", Color(1.0, 0.15, 0.0), get_tree().current_scene)
		var lbl := get_node_or_null("AsciiChar")
		if lbl:
			lbl.add_theme_color_override("font_color", Color(1.0, 0.2, 0.0))
	if health <= 0:
		GameState.kills += 1
		GameState.add_xp(5)
		if is_champion:
			_drop_champion_loot()
		else:
			if elite_modifier == 2 and _split_scene != null:
				_do_split()
			_drop_gold()
		queue_free()

func _drop_champion_loot() -> void:
	_drop_gold()
	for _i in 2:
		var bag := LOOT_BAG_SCENE.instantiate()
		bag.global_position = global_position + Vector2(randf_range(-32, 32), randf_range(-32, 32))
		bag.items = [ItemDB.random_drop()]
		get_tree().current_scene.call_deferred("add_child", bag)

func _do_split() -> void:
	FloatingText.spawn_str(global_position, "SPLIT!", Color(0.9, 0.4, 1.0), get_tree().current_scene)
	var enemies_node := get_tree().current_scene.get_node_or_null("Enemies")
	if enemies_node == null:
		return
	for _i in 2:
		var clone: Node = _split_scene.instantiate()
		clone.position = global_position + Vector2(randf_range(-28.0, 28.0), randf_range(-28.0, 28.0))
		if "max_health" in clone:
			clone.max_health = maxi(1, max_health / 2)
		if "elite_modifier" in clone:
			clone.elite_modifier = 0
		enemies_node.call_deferred("add_child", clone)

func _drop_gold() -> void:
	if GameState.test_mode:
		GameState.gold += int(randi_range(1, 5) * (3 if is_elite else 1) * GameState.loot_multiplier)
		return
	var gold := GOLD_PICKUP_SCENE.instantiate()
	gold.global_position = global_position
	gold.value = int(randi_range(1, 5) * (3 if is_elite else 1) * GameState.loot_multiplier)
	get_tree().current_scene.call_deferred("add_child", gold)
	if (is_elite and randi() % 100 < 50) or randi() % 100 < 8:
		var bag := LOOT_BAG_SCENE.instantiate()
		bag.global_position = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		get_tree().current_scene.call_deferred("add_child", bag)

func _update_health_bar() -> void:
	var bar := get_node_or_null("HealthBar/Foreground")
	if bar == null:
		return
	var ratio := clampf(float(health) / float(max_health), 0.0, 1.0)
	bar.offset_right = -20.0 + 40.0 * ratio
