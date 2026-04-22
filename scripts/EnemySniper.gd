extends CharacterBody2D

const GOLD_PICKUP_SCENE := preload("res://scenes/GoldPickup.tscn")
const LOOT_BAG_SCENE    := preload("res://scenes/LootBag.tscn")

@export var move_speed: float         = 70.0
@export var max_health: int           = 6
@export var preferred_distance: float = 480.0

# ASCII art frames — cloaked sniper
const SNIPER_F0 := "  ._. \n (-_-)\n  ||\\ \n  /\\ "
const SNIPER_F1 := "  ._. \n (>_-)\n  ||\\ \n  /\\ "

const SIGHT_RANGE    := 500.0
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
var _hit_flash_t: float   = 0.0

func _ready() -> void:
	health = max_health
	_player = get_tree().get_first_node_in_group("player")
	_update_health_bar()
	_setup_patrol()
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
		lbl.offset_top    = -44
		lbl.offset_right  =  32
		lbl.offset_bottom =  14
		lbl.text = SNIPER_F0

func _physics_process(delta: float) -> void:
	if _buff_timer > 0.0:
		_buff_timer -= delta
		if _buff_timer <= 0.0:
			_speed_multiplier = 1.0

	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(_player):
		return

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
	var lbl := get_node_or_null("AsciiChar")
	if lbl == null:
		return
	if _hit_flash_t > 0.0:
		_hit_flash_t -= delta
		lbl.modulate = Color(1.0, 0.3, 0.3)
	elif _winding_up:
		var progress := _windup_elapsed / WINDUP_TIME
		lbl.modulate = Color(1.0, lerpf(1.0, 0.08, progress), lerpf(1.0, 0.0, progress))
	else:
		lbl.modulate = _get_status_modulate()

func _get_status_modulate() -> Color:
	if _frozen:
		return Color(0.55, 0.82, 1.0)
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
		_update_windup_visual()
		if _windup_elapsed >= WINDUP_TIME:
			_finish_windup()
		return
	_shoot_timer -= delta
	if _shoot_timer <= 0.0 and _stun_timer <= 0.0 and _no_attack_timer <= 0.0:
		_start_windup()

func _start_windup() -> void:
	_winding_up    = true
	_windup_elapsed = 0.0
	_aim_line = Line2D.new()
	_aim_line.width = 2.0
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
	var dir := (_player.global_position - global_position).normalized()
	_aim_line.set_point_position(1, to_local(global_position + dir * 640.0))

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

	# Instant beam — raycast to find hit point
	var dir := (_player.global_position - global_position).normalized()
	var beam_end := global_position + dir * 680.0
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

func _add_burn_stacks(count: int) -> void:
	_burn_stacks = mini(_burn_stacks + count, 9)

func _trigger_enflamed() -> void:
	FloatingText.spawn_str(global_position, "ENFLAMED!", Color(1.0, 0.3, 0.0), get_tree().current_scene)
	_enflamed      = true
	_enflame_timer = 5.0
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
	_stun_timer      = 0.5
	_no_attack_timer = 1.5

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
	FloatingText.spawn(global_position, actual, false, get_tree().current_scene)
	_update_health_bar()
	if elite_modifier == 3 and not _enrage_triggered and health > 0 and health * 2 <= max_health:
		_enrage_triggered = true
		move_speed *= 1.5
		FloatingText.spawn_str(global_position, "ENRAGED!", Color(1.0, 0.15, 0.0), get_tree().current_scene)
		var lbl := get_node_or_null("AsciiChar")
		if lbl:
			lbl.add_theme_color_override("font_color", Color(1.0, 0.2, 0.0))
	if health <= 0:
		GameState.kills += 1
		GameState.add_xp(6)
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
		bag.items = [ItemDB.random_legendary()]
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
	var gold := GOLD_PICKUP_SCENE.instantiate()
	gold.global_position = global_position
	gold.value = int(randi_range(2, 6) * (3 if is_elite else 1) * GameState.loot_multiplier)
	get_tree().current_scene.call_deferred("add_child", gold)
	if is_elite or randi() % 100 < 35:
		var bag := LOOT_BAG_SCENE.instantiate()
		bag.global_position = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		get_tree().current_scene.call_deferred("add_child", bag)

func _update_health_bar() -> void:
	var bar := get_node_or_null("HealthBar/Foreground")
	if bar == null:
		return
	var ratio := clampf(float(health) / float(max_health), 0.0, 1.0)
	bar.offset_right = -20.0 + 40.0 * ratio
