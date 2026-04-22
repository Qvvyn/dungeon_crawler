extends CharacterBody2D

const GOLD_PICKUP_SCENE  := preload("res://scenes/GoldPickup.tscn")
const LOOT_BAG_SCENE     := preload("res://scenes/LootBag.tscn")
const PROJECTILE_SCENE   := preload("res://scenes/Projectile.tscn")

@export var max_health: int = 40

var health: int             = 40
var _player: Node2D         = null
var _shoot_timer: float     = 0.5
var _teleport_timer: float  = 10.0
var _phase: int             = 1

const SPEED_P1       := 100.0
const SPEED_P2       := 160.0
const SHOOT_INT_P1   := 1.8
const SHOOT_INT_P2   := 0.9
const PREFERRED_DIST := 250.0

# ── Status effects (15-stack threshold for boss) ──────────────────────────────
# FREEZE
var _chill_stacks: int    = 0
var _chill_decay_t: float = 0.0
var _frozen: bool         = false
var _frozen_timer: float  = 0.0

# BURN
var _burn_stacks: int     = 0
var _enflamed: bool       = false
var _enflame_timer: float = 0.0
var _enflame_tick: float  = 0.0

# SHOCK
var _shock_stacks: int     = 0
var _stun_timer: float     = 0.0
var _no_attack_timer: float = 0.0

# POISON
var _poison_stacks: int   = 0
var _poisoned: bool       = false
var _poison_timer: float  = 0.0
var _poison_tick: float   = 0.0

const BOSS_STACK_THRESHOLD := 15

func _ready() -> void:
	health = max_health
	add_to_group("enemy")
	_player = get_tree().get_first_node_in_group("player")
	_update_health_bar()
	FloatingText.spawn_str(global_position, "BOSS!", Color(1.0, 0.2, 0.0), get_tree().current_scene)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(_player):
		return

	_tick_status(delta)
	if not is_instance_valid(self): return

	if _phase == 1 and health * 2 <= max_health:
		_phase = 2
		FloatingText.spawn_str(global_position, "ENRAGED!", Color(1.0, 0.0, 0.0), get_tree().current_scene)

	if _frozen or _stun_timer > 0.0:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var slow_mult := clampf(1.0 - float(_chill_stacks) * 0.067, 0.0, 1.0)  # 15 stacks = full stop
	var spd := SPEED_P2 if _phase == 2 else SPEED_P1
	var to_player := _player.global_position - global_position
	var dist := to_player.length()
	if dist > PREFERRED_DIST + 40.0:
		velocity = to_player.normalized() * spd * slow_mult
	elif dist < PREFERRED_DIST - 40.0:
		velocity = -to_player.normalized() * spd * 0.6 * slow_mult
	else:
		velocity = Vector2.ZERO
	move_and_slide()

	var interval := SHOOT_INT_P2 if _phase == 2 else SHOOT_INT_P1
	_shoot_timer -= delta
	if _shoot_timer <= 0.0 and _stun_timer <= 0.0 and _no_attack_timer <= 0.0:
		_shoot_timer = interval
		_fire()

	_teleport_timer -= delta
	if _teleport_timer <= 0.0:
		_teleport_timer = randf_range(8.0, 14.0)
		_teleport()

# ── Status ticking ────────────────────────────────────────────────────────────

func _tick_status(delta: float) -> void:
	if _frozen:
		_frozen_timer -= delta
		if _frozen_timer <= 0.0:
			_frozen = false
			_chill_stacks = 0
	elif _chill_stacks > 0:
		_chill_decay_t -= delta
		if _chill_decay_t <= 0.0:
			_chill_decay_t = 3.0
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

# ── Apply status ──────────────────────────────────────────────────────────────

func apply_status(effect: String, _duration: float) -> void:
	match effect:
		"freeze_hit":
			if _frozen:
				return
			_chill_stacks = mini(_chill_stacks + 1, BOSS_STACK_THRESHOLD)
			_chill_decay_t = 3.0
			if _chill_stacks >= BOSS_STACK_THRESHOLD:
				_frozen = true
				_frozen_timer = 3.0
				FloatingText.spawn_str(global_position, "FROZEN!", Color(0.7, 0.95, 1.0), get_tree().current_scene)
			else:
				FloatingText.spawn_str(global_position, "CHILL %d/%d" % [_chill_stacks, BOSS_STACK_THRESHOLD], Color(0.45, 0.82, 1.0), get_tree().current_scene)
		"burn_hit":
			_burn_stacks = mini(_burn_stacks + 1, BOSS_STACK_THRESHOLD)
			if _burn_stacks >= BOSS_STACK_THRESHOLD:
				_burn_stacks = 0
				_trigger_enflamed()
			else:
				FloatingText.spawn_str(global_position, "BURN %d/%d" % [_burn_stacks, BOSS_STACK_THRESHOLD], Color(1.0, 0.55, 0.2), get_tree().current_scene)
		"shock_hit":
			_shock_stacks = mini(_shock_stacks + 1, BOSS_STACK_THRESHOLD)
			if _shock_stacks >= BOSS_STACK_THRESHOLD:
				_shock_stacks = 0
				_trigger_electrified()
			else:
				FloatingText.spawn_str(global_position, "SHOCK %d/%d" % [_shock_stacks, BOSS_STACK_THRESHOLD], Color(0.7, 0.85, 1.0), get_tree().current_scene)
		"poison_hit":
			_poison_stacks = mini(_poison_stacks + 1, BOSS_STACK_THRESHOLD)
			if _poison_stacks >= BOSS_STACK_THRESHOLD:
				_poison_stacks = 0
				_trigger_poisoned()
			else:
				FloatingText.spawn_str(global_position, "VENOM %d/%d" % [_poison_stacks, BOSS_STACK_THRESHOLD], Color(0.35, 1.0, 0.4), get_tree().current_scene)

# ── Trigger effects ───────────────────────────────────────────────────────────

func _trigger_enflamed() -> void:
	FloatingText.spawn_str(global_position, "ENFLAMED!", Color(1.0, 0.3, 0.0), get_tree().current_scene)
	_enflamed      = true
	_enflame_timer = 5.0
	_enflame_tick  = 0.0
	take_damage(12)
	if not is_instance_valid(self): return
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy) or enemy == self:
			continue
		if global_position.distance_to(enemy.global_position) < 160.0:
			if enemy.has_method("_add_burn_stacks"):
				enemy._add_burn_stacks(5)

func _add_burn_stacks(count: int) -> void:
	_burn_stacks = mini(_burn_stacks + count, BOSS_STACK_THRESHOLD - 1)
	if _burn_stacks >= 8:
		FloatingText.spawn_str(global_position, "BURN %d/%d" % [_burn_stacks, BOSS_STACK_THRESHOLD], Color(1.0, 0.55, 0.2), get_tree().current_scene)

func _trigger_electrified() -> void:
	FloatingText.spawn_str(global_position, "ELECTRIFIED!", Color(0.75, 0.9, 1.0), get_tree().current_scene)
	take_damage(10)
	if not is_instance_valid(self): return
	_stun_timer      = 0.5
	_no_attack_timer = 1.5

func _trigger_poisoned() -> void:
	FloatingText.spawn_str(global_position, "POISONED!", Color(0.2, 1.0, 0.35), get_tree().current_scene)
	_poisoned     = true
	_poison_timer = 9.0
	_poison_tick  = 0.0

# ── Combat ────────────────────────────────────────────────────────────────────

func _fire() -> void:
	var count := 8 if _phase == 2 else 4
	var base_angle := randf() * TAU
	for i in count:
		var angle := base_angle + (TAU / float(count)) * float(i)
		var proj: Node = PROJECTILE_SCENE.instantiate()
		proj.global_position = global_position
		proj.set("direction", Vector2(cos(angle), sin(angle)))
		proj.set("source", "enemy")
		proj.set("speed", 240.0)
		get_tree().current_scene.add_child(proj)

func _teleport() -> void:
	var offset := Vector2(randf_range(-240.0, 240.0), randf_range(-240.0, 240.0))
	global_position += offset
	FloatingText.spawn_str(global_position, "!", Color(0.8, 0.1, 1.0), get_tree().current_scene)

# ── Shared ────────────────────────────────────────────────────────────────────

func take_damage(amount: int) -> void:
	var actual := int(float(amount) * 1.25) if (_frozen or _chill_stacks > 0) else amount
	health -= actual
	FloatingText.spawn(global_position, actual, false, get_tree().current_scene)
	_update_health_bar()
	if health <= 0:
		GameState.kills += 5
		GameState.add_xp(40)
		_drop_loot()
		queue_free()

func _drop_loot() -> void:
	for i in 5:
		var gold := GOLD_PICKUP_SCENE.instantiate()
		gold.global_position = global_position + Vector2(randf_range(-40.0, 40.0), randf_range(-40.0, 40.0))
		gold.value = randi_range(8, 20)
		get_tree().current_scene.call_deferred("add_child", gold)
	var bag := LOOT_BAG_SCENE.instantiate()
	bag.global_position = global_position
	bag.items = [ItemDB.random_legendary(), ItemDB.random_legendary()]
	get_tree().current_scene.call_deferred("add_child", bag)

func _update_health_bar() -> void:
	var bar := get_node_or_null("HealthBar/Foreground")
	if bar == null:
		return
	var ratio := clampf(float(health) / float(max_health), 0.0, 1.0)
	bar.offset_right = -30.0 + 60.0 * ratio
