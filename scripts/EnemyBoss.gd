extends CharacterBody2D

const GOLD_PICKUP_SCENE  := preload("res://scenes/GoldPickup.tscn")
const LOOT_BAG_SCENE     := preload("res://scenes/LootBag.tscn")
const PROJECTILE_SCENE   := preload("res://scenes/Projectile.tscn")

@export var max_health: int = 40

# ASCII art frames — demon lord
const BOSS_F0 := "/\\ /\\\n(>@_@<)\n )||||  \n/|   |\\"
const BOSS_F1 := "\\/ \\/\n(>@_@<)\n )||||  \n\\|   |/"

var health: int             = 40
var _player: Node2D         = null
var _anim_timer: float      = 0.0
var _anim_frame: int        = 0
var _shoot_timer: float     = 0.5
var _teleport_timer: float  = 10.0
var _phase: int             = 1

const SPEED_P1       := 100.0
const SPEED_P2       := 160.0
const SPEED_P3       := 220.0
const SHOOT_INT_P1   := 1.8
const SHOOT_INT_P2   := 0.9
const SHOOT_INT_P3   := 0.5
const PREFERRED_DIST := 250.0

var _spiral_angle: float  = 0.0
var _boss_canvas: CanvasLayer = null
var _boss_bar_fg: ColorRect   = null

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
var _hit_flash_t: float   = 0.0

const BOSS_STACK_THRESHOLD := 15

func _ready() -> void:
	health = max_health
	add_to_group("enemy")
	_player = get_tree().get_first_node_in_group("player")
	_update_health_bar()
	_create_boss_bar()
	FloatingText.spawn_str(global_position, "BOSS!", Color(1.0, 0.2, 0.0), get_tree().current_scene)
	var lbl := get_node_or_null("AsciiChar")
	if lbl:
		var mono := SystemFont.new()
		mono.font_names = PackedStringArray(["Consolas", "Courier New", "Lucida Console"])
		lbl.add_theme_font_override("font", mono)
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_constant_override("line_separation", -3)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_TOP
		lbl.offset_left   = -42
		lbl.offset_top    = -28
		lbl.offset_right  =  44
		lbl.offset_bottom =  48
		lbl.text = BOSS_F0

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
	if _phase == 2 and health * 4 <= max_health:
		_phase = 3
		FloatingText.spawn_str(global_position, "PHASE 3!", Color(1.0, 0.0, 0.5), get_tree().current_scene)

	if _frozen or _stun_timer > 0.0:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var slow_mult := clampf(1.0 - float(_chill_stacks) * 0.067, 0.0, 1.0)  # 15 stacks = full stop
	var spd := SPEED_P3 if _phase == 3 else (SPEED_P2 if _phase == 2 else SPEED_P1)
	var to_player := _player.global_position - global_position
	var dist := to_player.length()
	if dist > PREFERRED_DIST + 40.0:
		velocity = to_player.normalized() * spd * slow_mult
	elif dist < PREFERRED_DIST - 40.0:
		velocity = -to_player.normalized() * spd * 0.6 * slow_mult
	else:
		velocity = Vector2.ZERO
	move_and_slide()

	var interval := SHOOT_INT_P3 if _phase == 3 else (SHOOT_INT_P2 if _phase == 2 else SHOOT_INT_P1)
	_shoot_timer -= delta
	if _shoot_timer <= 0.0 and _stun_timer <= 0.0 and _no_attack_timer <= 0.0:
		_shoot_timer = interval
		_fire()

	_teleport_timer -= delta
	if _teleport_timer <= 0.0:
		_teleport_timer = randf_range(8.0, 14.0)
		_teleport()

	_anim_timer += delta
	if _anim_timer >= 0.4:
		_anim_timer = 0.0
		_anim_frame = 1 - _anim_frame
	var _lbl := get_node_or_null("AsciiChar")
	if _lbl:
		_lbl.text = BOSS_F0 if _anim_frame == 0 else BOSS_F1
		if _hit_flash_t > 0.0:
			_hit_flash_t -= delta
			_lbl.modulate = Color(1.0, 0.3, 0.3)
		else:
			_lbl.modulate = _get_status_modulate()

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
		var t := float(_chill_stacks) / float(BOSS_STACK_THRESHOLD)
		return Color(lerpf(1.0, 0.55, t), lerpf(1.0, 0.82, t), 1.0)
	if _burn_stacks > 0:
		var t2 := float(_burn_stacks) / float(BOSS_STACK_THRESHOLD)
		return Color(1.0, lerpf(1.0, 0.35, t2), lerpf(1.0, 0.05, t2))
	if _shock_stacks > 0:
		var t3 := float(_shock_stacks) / float(BOSS_STACK_THRESHOLD)
		return Color(1.0, 1.0, lerpf(1.0, 0.2, t3))
	if _poison_stacks > 0:
		var t4 := float(_poison_stacks) / float(BOSS_STACK_THRESHOLD)
		return Color(lerpf(1.0, 0.45, t4), 1.0, lerpf(1.0, 0.55, t4))
	return Color.WHITE

func _fire() -> void:
	if _phase == 3:
		for i in 16:
			var angle := _spiral_angle + (TAU / 16.0) * float(i)
			var proj: Node = PROJECTILE_SCENE.instantiate()
			proj.global_position = global_position
			proj.set("direction", Vector2(cos(angle), sin(angle)))
			proj.set("source", "enemy")
			proj.set("speed", SPEED_P3)
			get_tree().current_scene.add_child(proj)
		_spiral_angle = fmod(_spiral_angle + PI / 6.0, TAU)
		return
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

func _create_boss_bar() -> void:
	_boss_canvas = CanvasLayer.new()
	_boss_canvas.layer = 18
	get_tree().current_scene.add_child(_boss_canvas)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.0, 0.0, 0.88)
	bg.position = Vector2(100.0, 828.0)
	bg.size = Vector2(1400.0, 22.0)
	_boss_canvas.add_child(bg)

	_boss_bar_fg = ColorRect.new()
	_boss_bar_fg.color = Color(0.85, 0.08, 0.08)
	_boss_bar_fg.position = Vector2(101.0, 829.0)
	_boss_bar_fg.size = Vector2(1398.0, 20.0)
	_boss_canvas.add_child(_boss_bar_fg)

	var name_lbl := Label.new()
	name_lbl.text = "THE VOID HERALD"
	name_lbl.position = Vector2(0.0, 808.0)
	name_lbl.size = Vector2(1600.0, 20.0)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
	_boss_canvas.add_child(name_lbl)

func _update_boss_bar() -> void:
	if _boss_bar_fg == null:
		return
	var ratio := clampf(float(health) / float(max_health), 0.0, 1.0)
	_boss_bar_fg.size.x = 1398.0 * ratio

func take_damage(amount: int) -> void:
	var actual := int(float(amount) * 1.25) if (_frozen or _chill_stacks > 0) else amount
	health -= actual
	_hit_flash_t = 0.14
	FloatingText.spawn(global_position, actual, false, get_tree().current_scene)
	_update_health_bar()
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
	bag.items = [ItemDB.random_legendary(), ItemDB.random_legendary()]
	get_tree().current_scene.call_deferred("add_child", bag)

func _update_health_bar() -> void:
	var bar := get_node_or_null("HealthBar/Foreground")
	if bar == null:
		return
	var ratio := clampf(float(health) / float(max_health), 0.0, 1.0)
	bar.offset_right = -30.0 + 60.0 * ratio
