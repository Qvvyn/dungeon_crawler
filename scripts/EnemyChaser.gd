extends CharacterBody2D

const GOLD_PICKUP_SCENE := preload("res://scenes/GoldPickup.tscn")
const LOOT_BAG_SCENE    := preload("res://scenes/LootBag.tscn")

@export var speed: float       = 150.0
@export var max_health: int    = 5

var health: int = 5
var _player: Node2D  = null
var _hitbox: Area2D  = null
var _attack_elapsed: float  = 0.0
var _speed_multiplier: float = 1.0
var _buff_timer: float       = 0.0
var _effective_interval: float = 1.0

const BASE_INTERVAL   := 1.0
const ATTACK_DURATION := 0.25
const HITBOX_REACH    := 40.0

# ── Sight & wander ────────────────────────────────────────────────────────────
const SIGHT_RANGE          := 300.0
const SIGHT_CHECK_INTERVAL := 0.15

var _has_aggro: bool      = false
var _sight_timer: float   = 0.0
var _wander_dir: Vector2  = Vector2.ZERO
var _wander_timer: float  = 0.0

var is_elite: bool = false

# ── Status effects (10-stack trigger system) ──────────────────────────────────
# FREEZE: gradual slow per stack; 10 stacks → FROZEN (stopped, +25% dmg taken)
var _chill_stacks: int     = 0
var _chill_decay_t: float  = 0.0   # countdown to losing one chill stack
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

func _ready() -> void:
	health = max_health
	_effective_interval = BASE_INTERVAL
	_player = get_tree().get_first_node_in_group("player")
	_hitbox = $MeleeHitbox
	_hitbox.body_entered.connect(_on_melee_hit)
	_update_health_bar()
	_pick_wander_dir()

func _physics_process(delta: float) -> void:
	if _buff_timer > 0.0:
		_buff_timer -= delta
		if _buff_timer <= 0.0:
			_speed_multiplier = 1.0
			_effective_interval = BASE_INTERVAL

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
		_chase(delta)
	else:
		_wander(delta)

	move_and_slide()

	if _has_aggro:
		_attack_elapsed += delta
		if _attack_elapsed >= _effective_interval and _stun_timer <= 0.0 and _no_attack_timer <= 0.0:
			_attack_elapsed = 0.0
			var dir := (_player.global_position - global_position).normalized()
			_launch_attack(dir)
	else:
		if get_slide_collision_count() > 0:
			_pick_wander_dir()

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
	match effect:
		"freeze_hit":
			if _frozen:
				return
			_chill_stacks = mini(_chill_stacks + 1, 10)
			_chill_decay_t = 3.0   # reset decay window on each hit
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
				_trigger_enflamed()
			else:
				FloatingText.spawn_str(global_position, "BURN %d/10" % _burn_stacks, Color(1.0, 0.55, 0.2), get_tree().current_scene)
		"shock_hit":
			_shock_stacks = mini(_shock_stacks + 1, 10)
			if _shock_stacks >= 10:
				_shock_stacks = 0
				_trigger_electrified()
			else:
				FloatingText.spawn_str(global_position, "SHOCK %d/10" % _shock_stacks, Color(0.7, 0.85, 1.0), get_tree().current_scene)
		"poison_hit":
			_poison_stacks = mini(_poison_stacks + 1, 10)
			if _poison_stacks >= 10:
				_poison_stacks = 0
				_trigger_poisoned()
			else:
				FloatingText.spawn_str(global_position, "VENOM %d/10" % _poison_stacks, Color(0.35, 1.0, 0.4), get_tree().current_scene)

# ── Trigger effects ───────────────────────────────────────────────────────────

func _trigger_enflamed() -> void:
	FloatingText.spawn_str(global_position, "ENFLAMED!", Color(1.0, 0.3, 0.0), get_tree().current_scene)
	_enflamed     = true
	_enflame_timer = 5.0
	_enflame_tick  = 0.0
	take_damage(12)
	if not is_instance_valid(self): return
	# AOE — spread burn stacks to nearby enemies (capped to avoid cascade)
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy) or enemy == self:
			continue
		if global_position.distance_to(enemy.global_position) < 160.0:
			if enemy.has_method("_add_burn_stacks"):
				enemy._add_burn_stacks(5)

func _add_burn_stacks(count: int) -> void:
	# Called by AOE spread — cap at 9 so we don't cascade-trigger another ENFLAMED
	_burn_stacks = mini(_burn_stacks + count, 9)
	if _burn_stacks >= 5:
		FloatingText.spawn_str(global_position, "BURN %d/10" % _burn_stacks, Color(1.0, 0.55, 0.2), get_tree().current_scene)

func _trigger_electrified() -> void:
	FloatingText.spawn_str(global_position, "ELECTRIFIED!", Color(0.75, 0.9, 1.0), get_tree().current_scene)
	take_damage(10)
	if not is_instance_valid(self): return
	_stun_timer      = 0.5
	_no_attack_timer = 1.5   # 0.5s stun + 1s no-attack after

func _trigger_poisoned() -> void:
	FloatingText.spawn_str(global_position, "POISONED!", Color(0.2, 1.0, 0.35), get_tree().current_scene)
	_poisoned     = true
	_poison_timer = 9.0
	_poison_tick  = 0.0

# ── Movement ──────────────────────────────────────────────────────────────────

func _chase(_delta: float) -> void:
	if _frozen or _stun_timer > 0.0:
		velocity = Vector2.ZERO
		return
	var slow_mult := clampf(1.0 - float(_chill_stacks) * 0.1, 0.0, 1.0)
	var dir := (_player.global_position - global_position).normalized()
	velocity = dir * speed * _speed_multiplier * slow_mult

func _wander(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_pick_wander_dir()
	elif _wander_dir != Vector2.ZERO:
		var jitter := randf_range(-3.0, 3.0) * delta
		_wander_dir = _wander_dir.rotated(jitter)
	var slow_mult := clampf(1.0 - float(_chill_stacks) * 0.1, 0.0, 1.0)
	velocity = _wander_dir * speed * 0.45 * _speed_multiplier * slow_mult

func _pick_wander_dir() -> void:
	if randf() < 0.15:
		_wander_dir   = Vector2.ZERO
		_wander_timer = randf_range(0.3, 0.7)
	else:
		var angle := randf() * TAU
		_wander_dir   = Vector2(cos(angle), sin(angle))
		_wander_timer = randf_range(0.6, 2.0)

# ── Sight ─────────────────────────────────────────────────────────────────────

func _check_sight() -> void:
	if global_position.distance_squared_to(_player.global_position) > SIGHT_RANGE * SIGHT_RANGE:
		return
	var space  := get_world_2d().direct_space_state
	var params := PhysicsRayQueryParameters2D.create(global_position, _player.global_position)
	params.exclude = [get_rid()]
	var hit := space.intersect_ray(params)
	if hit.is_empty() or hit.get("collider") == _player:
		_has_aggro = true
		FloatingText.spawn_str(global_position, "!", Color(1.0, 0.9, 0.0), get_tree().current_scene)

# ── Attack ────────────────────────────────────────────────────────────────────

func _launch_attack(dir: Vector2) -> void:
	_hitbox.position = dir * HITBOX_REACH
	_hitbox.monitoring = true
	_hitbox.get_node("Visual").visible = true
	get_tree().create_timer(ATTACK_DURATION).timeout.connect(func() -> void:
		if not is_instance_valid(self):
			return
		_hitbox.monitoring = false
		_hitbox.get_node("Visual").visible = false
	)

func _on_melee_hit(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(1)

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
	_effective_interval = BASE_INTERVAL / 2.0
	_buff_timer += duration

func take_damage(amount: int) -> void:
	if not _has_aggro:
		_has_aggro = true
		FloatingText.spawn_str(global_position, "!", Color(1.0, 0.9, 0.0), get_tree().current_scene)
	# Frozen targets take 25% more damage
	var actual := int(float(amount) * 1.25) if (_frozen or _chill_stacks > 0) else amount
	health -= actual
	FloatingText.spawn(global_position, actual, false, get_tree().current_scene)
	_update_health_bar()
	if health <= 0:
		GameState.kills += 1
		GameState.add_xp(5)
		_drop_gold()
		queue_free()

func _drop_gold() -> void:
	var gold := GOLD_PICKUP_SCENE.instantiate()
	gold.global_position = global_position
	gold.value = randi_range(1, 5) * (3 if is_elite else 1)
	get_tree().current_scene.call_deferred("add_child", gold)
	if is_elite or randi() % 100 < 30:
		var bag := LOOT_BAG_SCENE.instantiate()
		bag.global_position = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		get_tree().current_scene.call_deferred("add_child", bag)

func _update_health_bar() -> void:
	var bar := get_node_or_null("HealthBar/Foreground")
	if bar == null:
		return
	var ratio := clampf(float(health) / float(max_health), 0.0, 1.0)
	bar.offset_right = -20.0 + 40.0 * ratio
