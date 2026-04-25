extends CharacterBody2D

const GOLD_PICKUP_SCENE := preload("res://scenes/GoldPickup.tscn")
const LOOT_BAG_SCENE    := preload("res://scenes/LootBag.tscn")
const PROJECTILE_SCENE  := preload("res://scenes/Projectile.tscn")

const BOSS_F0 := "/W\\\n ~~"
const BOSS_F1 := "\\W/\n~~~"
const BOSS_NAME  := "THE WRAITH"
const BOSS_COLOR := Color(0.7, 0.1, 1.0)

@export var max_health: int = 45

var health: int             = 45
var _player: Node2D         = null
var _lbl: Label             = null
var _anim_timer: float      = 0.0
var _anim_frame: int        = 0
var _blink_timer: float     = 2.0
var _shots_queued: int      = 0
var _shot_delay_timer: float = 0.0
var _phase: int             = 1
var _blinking: bool         = false
var _blink_flash_t: float   = 0.0
var _hit_flash_t: float     = 0.0
# Phase 2+ phantom form — intangible burst with shadow trail
var _phantom_t: float       = 8.0
var _phantom_active: bool   = false
var _phantom_dur: float     = 0.0
var _shadow_drop_t: float   = 0.0
var _is_invuln: bool        = false
var _boss_canvas: CanvasLayer = null
var _boss_bar_fg: ColorRect   = null

const BLINK_INT_P1 := 2.4
const BLINK_INT_P2 := 1.3
const SHOTS_P1     := 2
const SHOTS_P2     := 4
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
	circ.radius = 14.0
	cshape.shape = circ
	add_child(cshape)

	_lbl = Label.new()
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Courier New", "Lucida Console"])
	_lbl.add_theme_font_override("font", mono)
	_lbl.add_theme_font_size_override("font_size", 15)
	_lbl.add_theme_constant_override("line_separation", -2)
	_lbl.add_theme_color_override("font_color", BOSS_COLOR)
	_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_TOP
	_lbl.offset_left   = -18
	_lbl.offset_top    = -18
	_lbl.offset_right  =  22
	_lbl.offset_bottom =  22
	_lbl.text = BOSS_F0
	add_child(_lbl)

	_create_boss_bar()
	FloatingText.spawn_str(global_position, "BOSS!", Color(0.7, 0.1, 1.0), get_tree().current_scene)
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

	if _frozen or _stun_timer > 0.0:
		velocity = Vector2.ZERO
		move_and_slide()
		_tick_anim(delta)
		return

	# Phase 2+ phantom-form override: intangible high-speed glide leaving shadows
	if _phantom_active:
		_tick_phantom(delta)
		_tick_anim(delta)
		return

	velocity = Vector2.ZERO
	move_and_slide()

	_tick_blink(delta)
	_tick_shots(delta)
	_tick_phantom_meter(delta)
	_tick_anim(delta)

# ── Phase 2+ phantom form ────────────────────────────────────────────────────
func _tick_phantom_meter(delta: float) -> void:
	if _phase < 2:
		return
	_phantom_t -= delta
	if _phantom_t <= 0.0 and _shots_queued <= 0:
		_phantom_t = 8.0
		_enter_phantom()

func _enter_phantom() -> void:
	_phantom_active = true
	_phantom_dur = 1.6
	_is_invuln = true
	_shadow_drop_t = 0.0
	FloatingText.spawn_str(global_position, "PHANTOM!", Color(0.85, 0.45, 1.0), get_tree().current_scene)
	if SoundManager:
		SoundManager.play("teleport", randf_range(0.85, 0.95))

func _tick_phantom(delta: float) -> void:
	_phantom_dur -= delta
	if not is_instance_valid(_player):
		return
	var to_player := (_player.global_position - global_position).normalized()
	# Glide rapidly toward the player while ethereal — no damage taken, no
	# damage dealt; you have to wait it out and dodge incoming shots after.
	velocity = to_player * 280.0
	move_and_slide()
	_shadow_drop_t -= delta
	if _shadow_drop_t <= 0.0:
		_shadow_drop_t = 0.07
		_spawn_shadow()
	if _phantom_dur <= 0.0:
		_phantom_active = false
		_is_invuln = false

func _spawn_shadow() -> void:
	var ghost := Label.new()
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Courier New", "Lucida Console"])
	ghost.add_theme_font_override("font", mono)
	ghost.add_theme_font_size_override("font_size", 15)
	ghost.add_theme_constant_override("line_separation", -2)
	ghost.add_theme_color_override("font_color", Color(0.45, 0.10, 0.65, 0.65))
	ghost.text = BOSS_F0 if _anim_frame == 0 else BOSS_F1
	ghost.position = global_position + Vector2(-18, -18)
	ghost.size = Vector2(40, 40)
	ghost.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ghost.vertical_alignment   = VERTICAL_ALIGNMENT_TOP
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().current_scene.add_child(ghost)
	var tw := ghost.create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, 0.55)
	tw.tween_callback(ghost.queue_free)

func _check_phases() -> void:
	if _phase == 1 and health * 100 <= max_health * 45:
		_phase = 2
		FloatingText.spawn_str(global_position, "UNBOUND!", Color(0.7, 0.1, 1.0), get_tree().current_scene)
		if SoundManager:
			SoundManager.play("boss_phase")

func _tick_blink(delta: float) -> void:
	if _shots_queued > 0:
		return
	_blink_timer -= delta
	var interval := BLINK_INT_P2 if _phase >= 2 else BLINK_INT_P1
	if _blink_timer <= 0.0:
		_blink_timer = interval
		_do_blink()

func _do_blink() -> void:
	_blinking = true
	if is_instance_valid(_player):
		var offset := Vector2(randf_range(-200.0, 200.0), randf_range(-200.0, 200.0))
		global_position = _player.global_position + offset
	FloatingText.spawn_str(global_position, "!", Color(0.8, 0.2, 1.0), get_tree().current_scene)
	_shots_queued = SHOTS_P2 if _phase >= 2 else SHOTS_P1
	_shot_delay_timer = 0.35
	_blink_flash_t = 0.4

func _tick_shots(delta: float) -> void:
	if _shots_queued <= 0:
		return
	_shot_delay_timer -= delta
	if _shot_delay_timer <= 0.0 and _no_attack_timer <= 0.0:
		_shot_delay_timer = 0.22
		_shots_queued -= 1
		_fire_aimed()
		if _shots_queued == 0:
			_blinking = false

func _fire_aimed() -> void:
	if not is_instance_valid(_player):
		return
	var base_dir := (_player.global_position - global_position).normalized()
	var jitter := randf_range(-0.28, 0.28)
	var proj: Node = PROJECTILE_SCENE.instantiate()
	proj.global_position = global_position
	proj.set("direction", base_dir.rotated(jitter))
	proj.set("source", "enemy")
	proj.set("damage", 2)
	proj.set("speed", 310.0)
	get_tree().current_scene.add_child(proj)

func _tick_anim(delta: float) -> void:
	_anim_timer += delta
	if _anim_timer >= 0.4:
		_anim_timer = 0.0
		_anim_frame = 1 - _anim_frame
	if _lbl == null: return
	_lbl.text = BOSS_F0 if _anim_frame == 0 else BOSS_F1
	if _blink_flash_t > 0.0:
		_blink_flash_t -= delta
		_lbl.modulate = Color(0.7, 0.1, 1.0, lerpf(0.2, 1.0, 1.0 - _blink_flash_t / 0.4))
	elif _hit_flash_t > 0.0:
		_hit_flash_t -= delta
		_lbl.modulate = Color(1.0, 0.3, 0.3)
	elif _blinking:
		_lbl.modulate = Color(0.7, 0.1, 1.0, 0.35)
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
	if _stun_timer > 0.0:      _stun_timer -= delta
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
	# Phantom form ignores incoming damage entirely
	if _is_invuln:
		FloatingText.spawn_str(global_position, "ETHEREAL", Color(0.7, 0.4, 1.0), get_tree().current_scene)
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
	bg.color = Color(0.03, 0.0, 0.06, 0.88)
	bg.position = Vector2(100.0, 828.0)
	bg.size = Vector2(1400.0, 22.0)
	_boss_canvas.add_child(bg)
	_boss_bar_fg = ColorRect.new()
	_boss_bar_fg.color = Color(0.65, 0.08, 0.95)
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
