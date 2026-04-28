extends CharacterBody2D

const GOLD_PICKUP_SCENE := preload("res://scenes/GoldPickup.tscn")
const LOOT_BAG_SCENE    := preload("res://scenes/LootBag.tscn")
const FIRE_PATCH_SCRIPT = preload("res://scripts/FirePatch.gd")

@export var move_speed: float         = 70.0
@export var max_health: int           = 6
@export var preferred_distance: float = 480.0

# ASCII art frames — cloaked sniper
const SNIPER_F0 := "  ._. \n (-_-)\n  ||\\ \n  /\\ "
const SNIPER_F1 := "  ._. \n (>_-)\n  ||\\ \n  /\\ "

const SIGHT_RANGE    := 900.0
const SIGHT_INTERVAL := 0.2
const SHOOT_INTERVAL := 5.0
const WINDUP_TIME    := 1.5
const RETREAT_SPEED  := 200.0

var health: int             = 6
var passive: bool           = false
var is_elite: bool          = false
var is_champion: bool       = false
var elite_modifier: int     = 0
var _shield_active: bool    = false
var _enrage_triggered: bool = false
var _split_scene: PackedScene = null
var _speed_multiplier: float = 1.0
var _buff_timer: float      = 0.0

var _player: Node2D      = null
var _has_aggro: bool     = false
var _sight_timer: float  = 0.0

var _wander_dir: Vector2 = Vector2.ZERO
var _wander_timer: float = 0.0

var _patrol_pts:  Array = []
var _patrol_idx:  int   = 0
var _patrol_wait: float = 0.0

var _shoot_timer: float    = 2.0
var _winding_up: bool      = false
var _windup_elapsed: float = 0.0
var _aim_line: Line2D      = null
var _retreat_timer: float  = 0.0

var _stun_timer: float      = 0.0
var _no_attack_timer: float = 0.0

var _prev_player_pos: Vector2 = Vector2.ZERO
var _player_vel_est: Vector2  = Vector2.ZERO

var _chill_stacks: int    = 0
var _chill_decay_t: float = 0.0
var _frozen: bool         = false
var _frozen_timer: float  = 0.0
var _burn_stacks: int     = 0
var _enflamed: bool       = false
var _enflame_timer: float = 0.0
var _enflame_tick: float  = 0.0
var _shock_stacks: int    = 0
var _poison_stacks: int   = 0
var _poisoned: bool       = false
var _poison_timer: float  = 0.0
var _poison_tick: float   = 0.0
var _hit_flash_t: float    = 0.0
var _dmg_text_cd: float    = 0.0
var _lbl: Label             = null
var _health_bar_fg: Control = null

static var _shared_font: Font = null

func _ready() -> void:
	collision_layer = 2
	collision_mask  = 1
	health = max_health
	_player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(_player):
		_prev_player_pos = _player.global_position
	_update_health_bar()
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
		_lbl.offset_left   = -30
		_lbl.offset_top    = -44
		_lbl.offset_right  =  32
		_lbl.offset_bottom =  14
		_lbl.text = SNIPER_F0

func _physics_process(delta: float) -> void:
	if _buff_timer > 0.0:
		_buff_timer -= delta
		if _buff_timer <= 0.0:
			_speed_multiplier = 1.0

	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(_player):
		return

	var raw_vel := (_player.global_position - _prev_player_pos) / delta
	_player_vel_est = _player_vel_est.lerp(raw_vel, 0.15)
	_prev_player_pos = _player.global_position

	if not _has_aggro:
		_sight_timer -= delta
		if _sight_timer <= 0.0:
			_sight_timer = SIGHT_INTERVAL
			_check_sight()

	_tick_status(delta)
	if not is_instance_valid(self): return

	if _has_aggro:
		_move_combat(delta)
		if not passive:
			_tick_shoot(delta)
	else:
		_patrol(delta)

	move_and_slide()
	_tick_anim(delta)

func _move_combat(delta: float) -> void:
	if _frozen or _stun_timer > 0.0 or _winding_up:
		velocity = Vector2.ZERO
		return
	var slow_mult := clampf(1.0 - float(_chill_stacks) * 0.1, 0.0, 1.0)
	if _retreat_timer > 0.0:
		_retreat_timer -= delta
		var dir_away := (global_position - _player.global_position).normalized()
		velocity = dir_away * RETREAT_SPEED * _speed_multiplier * slow_mult
		return
	var to_player := _player.global_position - global_position
	var dist := to_player.length()
	if dist > preferred_distance + 50.0:
		velocity = to_player.normalized() * move_speed * _speed_multiplier * slow_mult
	elif dist < preferred_distance - 50.0:
		velocity = -to_player.normalized() * move_speed * _speed_multiplier * slow_mult
	else:
		velocity = Vector2.ZERO

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
	velocity = to_pt.normalized() * move_speed * 0.4 * _speed_multiplier * slow_mult

func _wander(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_pick_wander_dir()
	elif _wander_dir != Vector2.ZERO:
		_wander_dir = _wander_dir.rotated(randf_range(-2.0, 2.0) * delta)
	var slow_mult := clampf(1.0 - float(_chill_stacks) * 0.1, 0.0, 1.0)
	velocity = _wander_dir * move_speed * 0.4 * _speed_multiplier * slow_mult

func _pick_wander_dir() -> void:
	if randf() < 0.2:
		_wander_dir   = Vector2.ZERO
		_wander_timer = randf_range(0.5, 1.5)
	else:
		var angle := randf() * TAU
		_wander_dir   = Vector2(cos(angle), sin(angle))
		_wander_timer = randf_range(1.0, 3.0)

func _tick_anim(delta: float) -> void:
	if _lbl == null:
		return
	FrozenBlock.sync_to(self, _frozen)
	EnflameOverlay.sync_to(self, _enflamed)
	PoisonOverlay.sync_to(self, _poisoned)
	if _hit_flash_t > 0.0:
		_hit_flash_t -= delta
		_lbl.modulate = Color(1.0, 0.3, 0.3)
	elif _winding_up:
		var progress := _windup_elapsed / WINDUP_TIME
		_lbl.modulate = Color(1.0, lerpf(1.0, 0.08, progress), lerpf(1.0, 0.0, progress))
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

# ── Shoot cycle: wait → wind-up → fire ────────────────────────────────────────

func _tick_shoot(delta: float) -> void:
	if _winding_up:
		_windup_elapsed += delta
		# Cancel windup the moment LOS is broken — no firing through walls
		if not _has_los_to_player():
			_abort_windup()
			return
		_update_windup_visual()
		if _windup_elapsed >= WINDUP_TIME:
			_finish_windup()
		return
	_shoot_timer -= delta
	if _shoot_timer <= 0.0 and _stun_timer <= 0.0 and _no_attack_timer <= 0.0:
		# Only commit to a shot when we actually have line of sight
		if _has_los_to_player():
			_start_windup()

func _has_los_to_player() -> bool:
	if not is_instance_valid(_player):
		return false
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, _player.global_position)
	query.exclude = [get_rid()]
	query.collision_mask = 1   # walls (layer 1), not other enemies (layer 2)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return true
	return hit.get("collider") == _player

func _abort_windup() -> void:
	_winding_up = false
	_windup_elapsed = 0.0
	_shoot_timer = 0.4   # short recheck delay so we re-engage quickly when LOS returns
	if _aim_line != null:
		_aim_line.queue_free()
		_aim_line = null
	var lbl := get_node_or_null("AsciiChar")
	if lbl:
		lbl.text = SNIPER_F0

func _start_windup() -> void:
	_winding_up    = true
	_windup_elapsed = 0.0
	_aim_line = Line2D.new()
	_aim_line.width = 0.6   # hair-thin tracer — clearly readable but not a wall of orange
	_aim_line.default_color = Color(1.0, 0.5, 0.0, 0.15)
	_aim_line.add_point(Vector2.ZERO)
	_aim_line.add_point(Vector2.ZERO)
	add_child(_aim_line)
	var lbl := get_node_or_null("AsciiChar")
	if lbl:
		lbl.text = SNIPER_F1
	FloatingText.spawn_str(global_position, "...", Color(1.0, 0.6, 0.2), get_tree().current_scene)

func _update_windup_visual() -> void:
	if _aim_line == null or not is_instance_valid(_player):
		return
	var progress := _windup_elapsed / WINDUP_TIME
	_aim_line.default_color = Color(1.0, lerpf(0.5, 0.05, progress), 0.0, lerpf(0.15, 0.9, progress))
	var predicted := _player.global_position + _player_vel_est * 0.2
	var dir := (predicted - global_position).normalized()
	_aim_line.set_point_position(1, to_local(global_position + dir * 1200.0))

func _finish_windup() -> void:
	_winding_up     = false
	_windup_elapsed = 0.0
	if _aim_line != null:
		_aim_line.queue_free()
		_aim_line = null
	var lbl := get_node_or_null("AsciiChar")
	if lbl:
		lbl.text = SNIPER_F0
	_shoot_timer = SHOOT_INTERVAL
	if not is_instance_valid(_player):
		return

	# Instant beam — raycast to find hit point (aim at predicted position)
	var predicted := _player.global_position + _player_vel_est * 0.2
	var dir := (predicted - global_position).normalized()
	var beam_end := global_position + dir * 1200.0
	var space  := get_world_2d().direct_space_state
	var params := PhysicsRayQueryParameters2D.create(global_position, beam_end)
	params.exclude = [get_rid()]
	var hit := space.intersect_ray(params)
	if not hit.is_empty():
		beam_end = hit.get("position", beam_end)
		var collider: Object = hit.get("collider")
		if collider != null and collider.is_in_group("player") and collider.has_method("take_damage"):
			collider.take_damage(4)

	# Outer glow
	var glow := Line2D.new()
	glow.width = 8.0
	glow.default_color = Color(1.0, 0.1, 0.0, 0.45)
	glow.add_point(global_position)
	glow.add_point(beam_end)
	glow.z_index = 4
	get_tree().current_scene.add_child(glow)
	var tw_g := glow.create_tween()
	tw_g.tween_property(glow, "modulate:a", 0.0, 0.3)
	tw_g.tween_callback(glow.queue_free)

	# Bright inner core
	var core := Line2D.new()
	core.width = 3.0
	core.default_color = Color(1.0, 0.88, 0.55, 1.0)
	core.add_point(global_position)
	core.add_point(beam_end)
	core.z_index = 5
	get_tree().current_scene.add_child(core)
	var tw_c := core.create_tween()
	tw_c.tween_property(core, "modulate:a", 0.0, 0.3)
	tw_c.tween_callback(core.queue_free)

	_retreat_timer = 0.6

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
	if _dmg_text_cd > 0.0:
		_dmg_text_cd -= delta
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
	var stacks: int = maxi(1, int(_duration))
	match effect:
		"freeze_hit":
			if _frozen: return
			if not _has_aggro: return
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

func _add_burn_stacks(count: int) -> void:
	_burn_stacks = mini(_burn_stacks + count, 9)

func _trigger_enflamed() -> void:
	FloatingText.spawn_str(global_position, "ENFLAMED!", Color(1.0, 0.3, 0.0), get_tree().current_scene)
	_enflamed      = true
	_enflame_timer = 5.0
	EnflameOverlay.sync_to(self, true)
	_enflame_tick  = 0.0
	take_damage(12)
	if not is_instance_valid(self): return
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy) or enemy == self: continue
		if global_position.distance_to(enemy.global_position) < 160.0:
			if enemy.has_method("_add_burn_stacks"):
				enemy._add_burn_stacks(5)

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
		FloatingText.spawn_str(global_position, "ENRAGED!", Color(1.0, 0.15, 0.0), get_tree().current_scene)
		if _lbl:
			_lbl.add_theme_color_override("font_color", Color(1.0, 0.2, 0.0))
	if health <= 0:
		GameState.kills += 1
		GameState.add_xp(6)
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
		GameState.gold += int(randi_range(2, 6) * (3 if is_elite else 1) * GameState.loot_multiplier)
		return
	var gold := GOLD_PICKUP_SCENE.instantiate()
	gold.global_position = global_position
	gold.value = int(randi_range(2, 6) * (3 if is_elite else 1) * GameState.loot_multiplier)
	get_tree().current_scene.call_deferred("add_child", gold)
	if (is_elite and randi() % 100 < 55) or randi() % 100 < 10:
		var bag := LOOT_BAG_SCENE.instantiate()
		bag.global_position = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		get_tree().current_scene.call_deferred("add_child", bag)

func _update_health_bar() -> void:
	if _health_bar_fg == null:
		return
	var ratio := clampf(float(health) / float(max_health), 0.0, 1.0)
	_health_bar_fg.offset_right = -20.0 + 40.0 * ratio
