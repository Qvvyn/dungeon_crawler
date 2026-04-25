extends CharacterBody2D

const GOLD_PICKUP_SCENE := preload("res://scenes/GoldPickup.tscn")
const LOOT_BAG_SCENE    := preload("res://scenes/LootBag.tscn")
const PROJECTILE_SCENE  := preload("res://scenes/Projectile.tscn")
const MINE_SCENE        := preload("res://scenes/Mine.tscn")
const TURRET_SCENE      := preload("res://scenes/EnemyMissileTurret.tscn")

const BOSS_F0 := ".+.\n>*<\n.+."
const BOSS_F1 := "-+-\n>X<\n-+-"
const BOSS_NAME := "THE ARCHITECT"
const BOSS_COLOR := Color(0.1, 0.9, 0.85)

@export var max_health: int = 55

var health: int              = 55
var _player: Node2D          = null
var _lbl: Label              = null
var _anim_timer: float       = 0.0
var _anim_frame: int         = 0
var _shoot_timer: float      = 1.0
var _phase: int              = 1
var _burst_count: int        = 0      # shots remaining in current burst
var _burst_timer: float      = 0.0
var _strafe_dir: float       = 1.0   # +1 or -1
var _strafe_switch_t: float  = 0.0
var _invuln_timer: float     = 0.0
var _hit_flash_t: float      = 0.0
# Phase 2+ "construct" pattern: drops mines, summons turrets
var _mine_deploy_t: float    = 6.0
var _turret_summon_t: float  = 14.0
var _boss_canvas: CanvasLayer  = null
var _boss_bar_fg: ColorRect    = null
var _fire_telegraph_ring: Line2D = null
const FIRE_TELEGRAPH_LEAD: float = 0.45

const SPEED        := 130.0
const PREFERRED_DIST := 220.0
const SHOOT_INT_P1 := 2.2
const SHOOT_INT_P2 := 1.6
const SHOOT_INT_P3 := 2.0  # longer — burst replaces rapid single
const BOSS_STACK_THRESHOLD := 15

# ── Status effects ─────────────────────────────────────────────────────────────
var _chill_stacks: int    = 0
var _chill_decay_t: float = 0.0
var _frozen: bool         = false
var _frozen_timer: float  = 0.0
var _burn_stacks: int     = 0
var _enflamed: bool       = false
var _enflame_timer: float = 0.0
var _enflame_tick: float  = 0.0
var _shock_stacks: int    = 0
var _stun_timer: float    = 0.0
var _no_attack_timer: float = 0.0
var _poison_stacks: int   = 0
var _poisoned: bool       = false
var _poison_timer: float  = 0.0
var _poison_tick: float   = 0.0

func _ready() -> void:
	health = max_health
	add_to_group("enemy")
	add_to_group("boss")
	collision_layer = 2
	collision_mask  = 1
	_player = get_tree().get_first_node_in_group("player")

	var cshape := CollisionShape2D.new()
	var circ := CircleShape2D.new()
	circ.radius = 16.0
	cshape.shape = circ
	add_child(cshape)

	_lbl = Label.new()
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Courier New", "Lucida Console"])
	_lbl.add_theme_font_override("font", mono)
	_lbl.add_theme_font_size_override("font_size", 13)
	_lbl.add_theme_constant_override("line_separation", -2)
	_lbl.add_theme_color_override("font_color", BOSS_COLOR)
	_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_TOP
	_lbl.offset_left   = -18
	_lbl.offset_top    = -20
	_lbl.offset_right  =  22
	_lbl.offset_bottom =  28
	_lbl.text = BOSS_F0
	add_child(_lbl)

	_create_boss_bar()
	FloatingText.spawn_str(global_position, "BOSS!", Color(0.1, 0.9, 0.85), get_tree().current_scene)
	if SoundManager:
		SoundManager.play("boss_roar")

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(_player):
		return

	_tick_status(delta)
	if not is_instance_valid(self): return

	_check_phases()

	if _invuln_timer > 0.0:
		_invuln_timer -= delta

	if _frozen or _stun_timer > 0.0:
		velocity = Vector2.ZERO
		move_and_slide()
		_tick_anim(delta)
		return

	_tick_movement(delta)
	_tick_shoot(delta)
	_tick_construct(delta)
	_tick_anim(delta)

# ── Phase 2+ pattern: deploy mines + summon turrets ─────────────────────────
func _tick_construct(delta: float) -> void:
	if _phase < 2:
		return
	if _no_attack_timer > 0.0:
		return
	_mine_deploy_t -= delta
	if _mine_deploy_t <= 0.0:
		_mine_deploy_t = 8.5
		_deploy_mines_around_player()
	if _phase >= 3:
		_turret_summon_t -= delta
		if _turret_summon_t <= 0.0:
			_turret_summon_t = 13.0
			_summon_turret()

func _deploy_mines_around_player() -> void:
	if not is_instance_valid(_player):
		return
	var center: Vector2 = _player.global_position
	# 4 mines in cardinal pattern around player at 70px — forces them to move
	var dirs := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
	var space := get_world_2d().direct_space_state
	for dir in dirs:
		var pos: Vector2 = center + dir * 70.0
		var query := PhysicsShapeQueryParameters2D.new()
		var circ := CircleShape2D.new()
		circ.radius = 18.0
		query.shape = circ
		query.transform = Transform2D(0.0, pos)
		query.exclude = [get_rid()]
		var blocked := false
		for hit in space.intersect_shape(query, 4):
			if hit.get("collider") is StaticBody2D:
				blocked = true
				break
		if blocked:
			continue
		var mine := MINE_SCENE.instantiate()
		mine.global_position = pos
		get_tree().current_scene.add_child(mine)
	FloatingText.spawn_str(global_position, "DEPLOY!", BOSS_COLOR, get_tree().current_scene)

func _summon_turret() -> void:
	var enemies_node := get_tree().current_scene.get_node_or_null("Enemies")
	if enemies_node == null:
		return
	var turret := TURRET_SCENE.instantiate()
	var offset := Vector2(randf_range(-180.0, 180.0), randf_range(-180.0, 180.0))
	turret.position = global_position + offset
	enemies_node.call_deferred("add_child", turret)
	FloatingText.spawn_str(global_position, "TURRET!", BOSS_COLOR, get_tree().current_scene)
	if SoundManager:
		SoundManager.play("summon", randf_range(0.85, 0.95))

func _check_phases() -> void:
	if _phase == 1 and health * 100 <= max_health * 60:
		_phase = 2
		FloatingText.spawn_str(global_position, "PHASE 2!", Color(0.1, 0.9, 0.85), get_tree().current_scene)
		if SoundManager:
			SoundManager.play("boss_phase")
		_fire_nova()
		_invuln_timer = 0.6
	if _phase == 2 and health * 100 <= max_health * 30:
		_phase = 3
		FloatingText.spawn_str(global_position, "ENRAGED!", Color(1.0, 0.1, 0.0), get_tree().current_scene)
		if SoundManager:
			SoundManager.play("boss_phase")

func _tick_movement(delta: float) -> void:
	var slow_mult := clampf(1.0 - float(_chill_stacks) * 0.067, 0.0, 1.0)
	var to_player := _player.global_position - global_position
	var dist := to_player.length()
	var approach_dir := to_player.normalized()
	var perp := approach_dir.rotated(PI * 0.5) * _strafe_dir

	_strafe_switch_t -= delta
	if _strafe_switch_t <= 0.0:
		_strafe_switch_t = randf_range(1.2, 2.4)
		_strafe_dir = 1.0 if randf() > 0.5 else -1.0

	if dist > PREFERRED_DIST + 50.0:
		velocity = (approach_dir * 0.6 + perp * 0.4).normalized() * SPEED * slow_mult
	elif dist < PREFERRED_DIST - 50.0:
		velocity = (-approach_dir * 0.5 + perp * 0.5).normalized() * SPEED * slow_mult
	else:
		velocity = perp * SPEED * slow_mult
	move_and_slide()

func _tick_shoot(delta: float) -> void:
	if _no_attack_timer > 0.0:
		return
	if _invuln_timer > 0.0:
		return

	if _burst_count > 0:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_burst_timer = 0.28
			_burst_count -= 1
			_fire_spread(5)
		return

	var interval := SHOOT_INT_P3 if _phase == 3 else (SHOOT_INT_P2 if _phase == 2 else SHOOT_INT_P1)
	_shoot_timer -= delta
	_update_fire_telegraph()
	if _shoot_timer <= 0.0:
		_shoot_timer = interval
		if _phase >= 3:
			_burst_count = 2
			_burst_timer = 0.0
		else:
			_fire_spread(3 if _phase == 1 else 5)
		_clear_fire_telegraph()

func _update_fire_telegraph() -> void:
	if _shoot_timer > FIRE_TELEGRAPH_LEAD or _no_attack_timer > 0.0:
		_clear_fire_telegraph()
		return
	if _fire_telegraph_ring == null:
		_fire_telegraph_ring = Line2D.new()
		_fire_telegraph_ring.width = 3.0
		_fire_telegraph_ring.z_index = -1
		var radius := 32.0
		var segs := 28
		for i in segs + 1:
			var a := (TAU / float(segs)) * float(i)
			_fire_telegraph_ring.add_point(Vector2(cos(a), sin(a)) * radius)
		add_child(_fire_telegraph_ring)
	var t: float = clampf(1.0 - (_shoot_timer / FIRE_TELEGRAPH_LEAD), 0.0, 1.0)
	_fire_telegraph_ring.default_color = Color(1.0, lerpf(0.4, 0.05, t), 0.05,
		0.35 + 0.55 * t)

func _clear_fire_telegraph() -> void:
	if is_instance_valid(_fire_telegraph_ring):
		_fire_telegraph_ring.queue_free()
	_fire_telegraph_ring = null

func _fire_spread(count: int) -> void:
	var base_dir := (_player.global_position - global_position).normalized()
	var spread := deg_to_rad(36.0)
	for i in count:
		var offset := -spread * 0.5 + spread * (float(i) / float(count - 1)) if count > 1 else 0.0
		var proj: Node = PROJECTILE_SCENE.instantiate()
		proj.global_position = global_position
		proj.set("direction", base_dir.rotated(offset))
		proj.set("source", "enemy")
		proj.set("damage", 2)
		proj.set("speed", 280.0)
		get_tree().current_scene.add_child(proj)

func _fire_nova() -> void:
	for i in 12:
		var angle := (TAU / 12.0) * float(i)
		var proj: Node = PROJECTILE_SCENE.instantiate()
		proj.global_position = global_position
		proj.set("direction", Vector2(cos(angle), sin(angle)))
		proj.set("source", "enemy")
		proj.set("damage", 1)
		proj.set("speed", 240.0)
		get_tree().current_scene.add_child(proj)

func _tick_anim(delta: float) -> void:
	_anim_timer += delta
	if _anim_timer >= 0.4:
		_anim_timer = 0.0
		_anim_frame = 1 - _anim_frame
	if _lbl == null: return
	_lbl.text = BOSS_F0 if _anim_frame == 0 else BOSS_F1
	if _invuln_timer > 0.0:
		_lbl.modulate = Color(1.0, 1.0, 1.0, absf(sin(Time.get_ticks_msec() * 0.04)))
	elif _hit_flash_t > 0.0:
		_hit_flash_t -= delta
		_lbl.modulate = Color(1.0, 0.3, 0.3)
	else:
		_lbl.modulate = _get_status_modulate()

# ── Status (copy of boss pattern) ─────────────────────────────────────────────

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
	if _stun_timer > 0.0:     _stun_timer -= delta
	if _no_attack_timer > 0.0: _no_attack_timer -= delta
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
				_enflamed = true
				_enflame_timer = 5.0
				_enflame_tick = 0.0
				FloatingText.spawn_str(global_position, "ENFLAMED!", Color(1.0, 0.3, 0.0), get_tree().current_scene)
				take_damage(12)
			else:
				FloatingText.spawn_str(global_position, "BURN %d/%d" % [_burn_stacks, BOSS_STACK_THRESHOLD], Color(1.0, 0.55, 0.2), get_tree().current_scene)
		"shock_hit":
			_shock_stacks = mini(_shock_stacks + 1, BOSS_STACK_THRESHOLD)
			if _shock_stacks >= BOSS_STACK_THRESHOLD:
				_shock_stacks = 0
				_stun_timer = 0.5
				_no_attack_timer = 1.5
				FloatingText.spawn_str(global_position, "ELECTRIFIED!", Color(0.75, 0.9, 1.0), get_tree().current_scene)
				take_damage(10)
			else:
				FloatingText.spawn_str(global_position, "SHOCK %d/%d" % [_shock_stacks, BOSS_STACK_THRESHOLD], Color(0.7, 0.85, 1.0), get_tree().current_scene)

func _get_status_modulate() -> Color:
	if _frozen:       return Color(0.55, 0.82, 1.0)
	if _stun_timer > 0.0: return Color(0.9, 0.9, 0.3)
	if _enflamed:
		var flicker := sin(Time.get_ticks_msec() * 0.025) * 0.12 + 0.88
		return Color(1.0, flicker * 0.35, 0.05)
	return Color.WHITE

func take_damage(amount: int) -> void:
	if _invuln_timer > 0.0:
		return
	var actual := int(float(amount) * 1.25) if (_frozen or _chill_stacks > 0) else amount
	health -= actual
	_hit_flash_t = 0.14
	FloatingText.spawn(global_position, actual, false, get_tree().current_scene)
	_update_boss_bar()
	if health <= 0:
		if is_instance_valid(_boss_canvas):
			_boss_canvas.queue_free()
		GameState.kills += 5
		GameState.add_xp(40)
		_drop_loot()
		queue_free()

func _drop_loot() -> void:
	for i in 5:
		var gold := GOLD_PICKUP_SCENE.instantiate()
		gold.global_position = global_position + Vector2(randf_range(-40.0, 40.0), randf_range(-40.0, 40.0))
		gold.value = int(randi_range(8, 20) * GameState.loot_multiplier)
		get_tree().current_scene.call_deferred("add_child", gold)
	var bag := LOOT_BAG_SCENE.instantiate()
	bag.global_position = global_position
	bag.items = [ItemDB.random_drop(), ItemDB.random_drop(), ItemDB.random_drop()]
	get_tree().current_scene.call_deferred("add_child", bag)

func _create_boss_bar() -> void:
	_boss_canvas = CanvasLayer.new()
	_boss_canvas.layer = 18
	get_tree().current_scene.add_child(_boss_canvas)
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.04, 0.05, 0.88)
	bg.position = Vector2(100.0, 828.0)
	bg.size = Vector2(1400.0, 22.0)
	_boss_canvas.add_child(bg)
	_boss_bar_fg = ColorRect.new()
	_boss_bar_fg.color = Color(0.08, 0.82, 0.78)
	_boss_bar_fg.position = Vector2(101.0, 829.0)
	_boss_bar_fg.size = Vector2(1398.0, 20.0)
	_boss_canvas.add_child(_boss_bar_fg)
	var name_lbl := Label.new()
	name_lbl.text = BOSS_NAME
	name_lbl.position = Vector2(0.0, 808.0)
	name_lbl.size = Vector2(1600.0, 20.0)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", BOSS_COLOR)
	_boss_canvas.add_child(name_lbl)

func _update_boss_bar() -> void:
	if _boss_bar_fg == null: return
	_boss_bar_fg.size.x = 1398.0 * clampf(float(health) / float(max_health), 0.0, 1.0)
