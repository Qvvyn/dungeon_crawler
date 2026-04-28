extends CharacterBody2D

const GOLD_PICKUP_SCENE := preload("res://scenes/GoldPickup.tscn")
const LOOT_BAG_SCENE    := preload("res://scenes/LootBag.tscn")
const FIRE_PATCH_SCRIPT = preload("res://scripts/FirePatch.gd")

@export var move_speed: float         = 80.0
@export var shoot_interval: float     = 2.0
@export var preferred_distance: float = 350.0
@export var max_health: int           = 5
@export var projectile_scene: PackedScene

# ASCII art frames — spider
const SHOOTER_F0 := "\\(o.o)/\n  [*]  \n / | \\"
const SHOOTER_F1 := "-(o.o)-\n  [*]  \n \\ | /"

var health: int                = 5
var passive: bool              = false
var _player: Node2D            = null
var _anim_timer: float         = 0.0
var _anim_frame: int           = 0
var _shoot_timer: float        = 1.0
var _speed_multiplier: float   = 1.0
var _buff_timer: float         = 0.0
var _effective_interval: float = 2.0

# ── Sight & wander ────────────────────────────────────────────────────────────
const SIGHT_RANGE          := 320.0
const SIGHT_CHECK_INTERVAL := 0.15

var _has_aggro: bool     = false
var _sight_timer: float  = 0.0
var _wander_dir: Vector2 = Vector2.ZERO
var _wander_timer: float = 0.0

var _patrol_pts:  Array = []
var _patrol_idx:  int   = 0
var _patrol_wait: float = 0.0

var _strafe_dir: float      = 1.0
var _strafe_switch_t: float = 0.0

var is_elite: bool    = false
var is_champion: bool = false

# Elite modifiers (0=none 1=shielded 2=splitting 3=enraged)
var elite_modifier: int     = 0
var _shield_active: bool    = false
var _enrage_triggered: bool = false
var _split_scene: PackedScene = null

# ── Status effects (10-stack trigger system) ──────────────────────────────────
# FREEZE: gradual slow per stack; 10 stacks → FROZEN (stopped, +25% dmg taken)
var _chill_stacks: int     = 0
var _chill_decay_t: float  = 0.0
var _frozen: bool          = false
var _frozen_timer: float   = 0.0

# BURN: 10 stacks → ENFLAMED (burst dmg + AOE spread + DoT)
var _burn_stacks: int      = 0
var _enflamed: bool        = false
var _enflame_timer: float  = 0.0
var _enflame_tick: float   = 0.0

# SHOCK: 10 stacks → ELECTRIFIED (burst dmg + stun + no-attack debuff)
var _shock_stacks: int     = 0
var _stun_timer: float     = 0.0
var _no_attack_timer: float = 0.0

# POISON: 10 stacks → POISONED (rapid health drain — highest total damage)
var _poison_stacks: int    = 0
var _poisoned: bool        = false
var _poison_timer: float   = 0.0
var _poison_tick: float    = 0.0
var _hit_flash_t: float    = 0.0
var _telegraphing: bool    = false
var _dmg_text_cd: float    = 0.0
var _lbl: Label             = null
var _health_bar_fg: Control = null

static var _shared_font: Font = null

func _ready() -> void:
	collision_layer = 2
	collision_mask  = 1
	health = max_health
	_effective_interval = shoot_interval
	_strafe_dir = 1.0 if randf() > 0.5 else -1.0
	_strafe_switch_t = randf_range(1.5, 3.0)
	_player = get_tree().get_first_node_in_group("player")
	_update_health_bar()
	if projectile_scene == null:
		projectile_scene = load("res://scenes/Projectile.tscn")
	_setup_patrol()
	if elite_modifier == 1:
		_shield_active = true
	_health_bar_fg = get_node_or_null("HealthBar/Foreground")
	_lbl = get_node_or_null("AsciiChar")
	if _lbl:
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
		_lbl.text = SHOOTER_F0

func _physics_process(delta: float) -> void:
	if _buff_timer > 0.0:
		_buff_timer -= delta
		if _buff_timer <= 0.0:
			_speed_multiplier = 1.0
			_effective_interval = shoot_interval

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
	if not is_instance_valid(self): return

	if _has_aggro:
		_move_combat(delta)
		_tick_shoot(delta)
	else:
		_patrol(delta)

	move_and_slide()
	_tick_anim(delta)

# ── Status ticking ────────────────────────────────────────────────────────────

func _tick_status(delta: float) -> void:
	# FREEZE — chill stacks decay when not being hit
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

	# ENFLAMED — DoT
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

	# STUN / NO-ATTACK timers
	if _stun_timer > 0.0:
		_stun_timer -= delta
	if _no_attack_timer > 0.0:
		_no_attack_timer -= delta
	if _dmg_text_cd > 0.0:
		_dmg_text_cd -= delta

	# POISONED — fast drain (highest damage)
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

# ── Apply status ──────────────────────────────────────────────────────────────

func apply_status(effect: String, _duration: float) -> void:
	# `_duration` is repurposed as wand_status_stacks (stacks per hit).
	var stacks: int = maxi(1, int(_duration))
	match effect:
		"freeze_hit":
			if _frozen:
				return
			if not _has_aggro: return   # don't stack-freeze unaggro'd grazes
			_chill_stacks = mini(_chill_stacks + stacks, 10)
			_chill_decay_t = 3.0
			if _chill_stacks >= 10:
				_frozen = true
				_frozen_timer = 4.5
				FloatingText.spawn_str(global_position, "FROZEN!", Color(0.7, 0.95, 1.0), get_tree().current_scene)
		"burn_hit":
			if _enflamed:
				EnflameOverlay.refresh_pulse(self)
			else:
				_burn_stacks = mini(_burn_stacks + stacks, 10)
				if _burn_stacks >= 10:
					_burn_stacks = 0
					_trigger_enflamed()
		"shock_hit":
			_shock_stacks = mini(_shock_stacks + stacks, 10)
			if _shock_stacks >= 10:
				_shock_stacks = 0
				_trigger_electrified()
		"poison_hit":
			_poison_stacks = mini(_poison_stacks + 1, 10)
			if _poison_stacks >= 10:
				_poison_stacks = 0
				_trigger_poisoned()

# ── Trigger effects ───────────────────────────────────────────────────────────

func _trigger_enflamed() -> void:
	FloatingText.spawn_str(global_position, "ENFLAMED!", Color(1.0, 0.3, 0.0), get_tree().current_scene)
	_enflamed      = true
	_enflame_timer = 5.0
	_enflame_tick  = 0.0
	EnflameOverlay.sync_to(self, true)
	take_damage(12)
	if not is_instance_valid(self): return
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy) or enemy == self:
			continue
		if global_position.distance_to(enemy.global_position) < 160.0:
			if enemy.has_method("_add_burn_stacks"):
				enemy._add_burn_stacks(5)

func _add_burn_stacks(count: int) -> void:
	_burn_stacks = mini(_burn_stacks + count, 9)
	if _burn_stacks >= 5:
		FloatingText.spawn_str(global_position, "BURN %d/10" % _burn_stacks, Color(1.0, 0.55, 0.2), get_tree().current_scene)

func _trigger_electrified() -> void:
	FloatingText.spawn_str(global_position, "ELECTRIFIED!", Color(0.75, 0.9, 1.0), get_tree().current_scene)
	take_damage(10)
	if not is_instance_valid(self): return
	ElectricBolt.trigger(self)

func _trigger_poisoned() -> void:
	FloatingText.spawn_str(global_position, "POISONED!", Color(0.2, 1.0, 0.35), get_tree().current_scene)
	_poisoned     = true
	_poison_timer = 9.0
	_poison_tick  = 0.0

# ── Movement ──────────────────────────────────────────────────────────────────

func _move_combat(delta: float) -> void:
	if _frozen or _stun_timer > 0.0:
		velocity = Vector2.ZERO
		return
	var slow_mult := clampf(1.0 - float(_chill_stacks) * 0.1, 0.0, 1.0)
	var to_player := _player.global_position - global_position
	var dist := to_player.length()
	var toward := to_player.normalized()
	var lateral := toward.rotated(PI * 0.5) * _strafe_dir

	# Tick strafe direction flip
	_strafe_switch_t -= delta
	if _strafe_switch_t <= 0.0:
		_strafe_dir = -_strafe_dir
		_strafe_switch_t = randf_range(1.5, 3.5)

	if dist > preferred_distance + 60.0:
		# Too far — close diagonally (mostly toward, some lateral)
		velocity = (toward * 0.7 + lateral * 0.3).normalized() * move_speed * _speed_multiplier * slow_mult
	elif dist < preferred_distance - 60.0:
		# Too close — retreat diagonally
		velocity = (-toward * 0.7 + lateral * 0.3).normalized() * move_speed * _speed_multiplier * slow_mult
	else:
		# At preferred range — pure lateral strafe
		velocity = lateral * move_speed * _speed_multiplier * slow_mult

func _setup_patrol() -> void:
	_patrol_pts.clear()
	var count := randi_range(2, 3)
	for i in count:
		var angle := float(i) / float(count) * TAU + randf_range(-0.4, 0.4)
		var dist  := randf_range(48.0, 108.0)
		_patrol_pts.append(global_position + Vector2(cos(angle), sin(angle)) * dist)
	_patrol_pts.append(global_position)

func _patrol(delta: float) -> void:
	if _patrol_wait > 0.0:
		_patrol_wait -= delta
		velocity = Vector2.ZERO
		return
	var slow_mult := clampf(1.0 - float(_chill_stacks) * 0.1, 0.0, 1.0)
	var target: Vector2 = _patrol_pts[_patrol_idx]
	var to_pt: Vector2  = target - global_position
	if to_pt.length() < 10.0 or get_slide_collision_count() > 0:
		_patrol_idx  = (_patrol_idx + 1) % _patrol_pts.size()
		_patrol_wait = randf_range(0.5, 1.5)
		velocity = Vector2.ZERO
		return
	velocity = to_pt.normalized() * move_speed * 0.45 * _speed_multiplier * slow_mult

func _wander(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_pick_wander_dir()
	elif _wander_dir != Vector2.ZERO:
		var jitter := randf_range(-3.0, 3.0) * delta
		_wander_dir = _wander_dir.rotated(jitter)
	var slow_mult := clampf(1.0 - float(_chill_stacks) * 0.1, 0.0, 1.0)
	velocity = _wander_dir * move_speed * 0.5 * _speed_multiplier * slow_mult

func _pick_wander_dir() -> void:
	if randf() < 0.15:
		_wander_dir   = Vector2.ZERO
		_wander_timer = randf_range(0.3, 0.8)
	else:
		var angle := randf() * TAU
		_wander_dir   = Vector2(cos(angle), sin(angle))
		_wander_timer = randf_range(0.7, 2.2)

func _tick_anim(delta: float) -> void:
	if _lbl == null:
		return
	_anim_timer += delta
	if _anim_timer >= 0.35:
		_anim_timer = 0.0
		_anim_frame = 1 - _anim_frame
	var new_text := SHOOTER_F0 if _anim_frame == 0 else SHOOTER_F1
	if _lbl.text != new_text:
		_lbl.text = new_text
	FrozenBlock.sync_to(self, _frozen)
	EnflameOverlay.sync_to(self, _enflamed)
	PoisonOverlay.sync_to(self, _poisoned)
	if _hit_flash_t > 0.0:
		_hit_flash_t -= delta
		_lbl.modulate = Color(1.0, 0.3, 0.3)
	elif _telegraphing:
		var blink := sin(Time.get_ticks_msec() * 0.013) * 0.5 + 0.5
		_lbl.modulate = Color(1.0, lerpf(0.8, 0.1, blink), lerpf(0.7, 0.0, blink))
	else:
		_lbl.modulate = _get_status_modulate()

func _get_status_modulate() -> Color:
	if _frozen:
		return Color(0.78, 0.92, 1.0)
	if _stun_timer > 0.0:
		return Color(0.9, 0.9, 0.3)
	if _poisoned:
		return Color(0.45, 1.0, 0.55)
	if _enflamed:
		var flicker := sin(Time.get_ticks_msec() * 0.025) * 0.12 + 0.88
		return Color(1.0, flicker * 0.35, 0.05)
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

# ── Sight ─────────────────────────────────────────────────────────────────────

func _check_sight() -> void:
	if passive:
		return
	if global_position.distance_squared_to(_player.global_position) > SIGHT_RANGE * SIGHT_RANGE:
		return
	var space  := get_world_2d().direct_space_state
	var params := PhysicsRayQueryParameters2D.create(global_position, _player.global_position)
	params.exclude = [get_rid()]
	var hit := space.intersect_ray(params)
	if hit.is_empty() or hit.get("collider") == _player:
		_has_aggro = true
		FloatingText.spawn_str(global_position, "!", Color(1.0, 0.9, 0.0), get_tree().current_scene)

# ── Shooting ──────────────────────────────────────────────────────────────────

func _tick_shoot(delta: float) -> void:
	_shoot_timer -= delta
	if _shoot_timer <= 0.3 and not _telegraphing and _stun_timer <= 0.0 and _no_attack_timer <= 0.0:
		_telegraphing = true
	if _stun_timer > 0.0 or _no_attack_timer > 0.0:
		_telegraphing = false
	if _shoot_timer <= 0.0 and _stun_timer <= 0.0 and _no_attack_timer <= 0.0:
		_telegraphing = false
		_fire()
		_shoot_timer = _effective_interval

func _fire() -> void:
	if projectile_scene == null:
		return
	var proj := projectile_scene.instantiate()
	proj.global_position = global_position
	proj.direction = (_player.global_position - global_position).normalized()
	proj.source = "enemy"
	proj.speed = 320.0
	get_tree().current_scene.add_child(proj)

# ── Shared ────────────────────────────────────────────────────────────────────

func heal(amount: int) -> void:
	var prev := health
	health = mini(health + amount, max_health)
	var gained := health - prev
	if gained > 0:
		FloatingText.spawn(global_position, gained, true, get_tree().current_scene)
	_update_health_bar()

func apply_buff(duration: float) -> void:
	_speed_multiplier = 2.0
	_effective_interval = shoot_interval / 2.0
	_buff_timer += duration

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
	if _dmg_text_cd <= 0.0:
		FloatingText.spawn(global_position, actual, false, get_tree().current_scene)
		_dmg_text_cd = 0.22
	_update_health_bar()
	if elite_modifier == 3 and not _enrage_triggered and health > 0 and health * 2 <= max_health:
		_enrage_triggered = true
		move_speed *= 1.5
		_effective_interval = maxf(0.5, _effective_interval * 0.6)
		FloatingText.spawn_str(global_position, "ENRAGED!", Color(1.0, 0.15, 0.0), get_tree().current_scene)
		if _lbl:
			_lbl.add_theme_color_override("font_color", Color(1.0, 0.2, 0.0))
	if health <= 0:
		GameState.kills += 1
		GameState.add_xp(5)
		if is_champion:
			_drop_champion_loot()
		else:
			if elite_modifier == 2 and _split_scene != null:
				_do_split()
			_drop_gold()
		EffectFx.spawn_death_pop(global_position, get_tree().current_scene)
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
	if _health_bar_fg == null:
		return
	var ratio := clampf(float(health) / float(max_health), 0.0, 1.0)
	_health_bar_fg.offset_right = -20.0 + 40.0 * ratio
