extends CharacterBody2D

const GOLD_PICKUP_SCENE  := preload("res://scenes/GoldPickup.tscn")
const LOOT_BAG_SCENE     := preload("res://scenes/LootBag.tscn")
const PROJECTILE_SCENE   := preload("res://scenes/Projectile.tscn")
const FIRE_PATCH_SCRIPT  := preload("res://scripts/FirePatch.gd")

@export var max_health: int = 200   # bumped 40 → 100 → 200 — boss is a real fight

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

# Phase 2+ charge attack — mirrors the Charger enemy
enum ChargeState { IDLE, TELEGRAPH, DASH, COOLDOWN }
var _charge_state: int     = ChargeState.IDLE
var _charge_t: float       = 9.0   # initial delay before first charge
var _charge_dir: Vector2   = Vector2.ZERO
var _charge_line: Line2D   = null
var _charge_hit: bool      = false
const CHARGE_INTERVAL: float  = 7.0
const CHARGE_TELEGRAPH: float = 0.55
const CHARGE_DURATION: float  = 0.50
const CHARGE_SPEED: float     = 720.0
const CHARGE_DAMAGE: int      = 3

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
var _fire_telegraph_ring: Line2D = null
const FIRE_TELEGRAPH_LEAD: float = 0.45

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
	add_to_group("boss")
	collision_layer = 2
	collision_mask  = 1
	_player = get_tree().get_first_node_in_group("player")
	_update_health_bar()
	_create_boss_bar()
	FloatingText.spawn_str(global_position, "BOSS!", Color(1.0, 0.2, 0.0), get_tree().current_scene)
	BossIntro.show_for(get_tree().current_scene, "THE VOID HERALD", Color(1.0, 0.45, 0.20))
	if SoundManager:
		SoundManager.play("boss_roar")
	var lbl := get_node_or_null("AsciiChar")
	if lbl:
		var mono := MonoFont.get_font()
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
		if SoundManager: SoundManager.play("boss_phase")
	if _phase == 2 and health * 4 <= max_health:
		_phase = 3
		FloatingText.spawn_str(global_position, "PHASE 3!", Color(1.0, 0.0, 0.5), get_tree().current_scene)
		if SoundManager: SoundManager.play("boss_phase")

	if _frozen or _stun_timer > 0.0:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# Phase 2+ charge attack overrides normal movement while active
	if _phase >= 2:
		_charge_t -= delta
		match _charge_state:
			ChargeState.IDLE:
				if _charge_t <= 0.0 and _no_attack_timer <= 0.0:
					_enter_charge_telegraph()
			ChargeState.TELEGRAPH:
				velocity = Vector2.ZERO
				move_and_slide()
				_update_charge_line()
				if _charge_t <= 0.0:
					_enter_charge_dash()
				return
			ChargeState.DASH:
				velocity = _charge_dir * CHARGE_SPEED
				move_and_slide()
				if not _charge_hit and global_position.distance_to(_player.global_position) <= 34.0:
					if _player.has_method("take_damage"):
						_player.take_damage(CHARGE_DAMAGE)
					_charge_hit = true
				if _charge_t <= 0.0 or get_slide_collision_count() > 0:
					_enter_charge_cooldown()
				return
			ChargeState.COOLDOWN:
				if _charge_t <= 0.0:
					_charge_state = ChargeState.IDLE
					_charge_t = CHARGE_INTERVAL

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
	# Telegraph the upcoming burst with a pulsing ring around the boss so the
	# player can pre-position before pellets spray out.
	_update_fire_telegraph()
	if _shoot_timer <= 0.0 and _stun_timer <= 0.0 and _no_attack_timer <= 0.0:
		_shoot_timer = interval
		_fire()
		_clear_fire_telegraph()

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
		FrozenBlock.sync_to(self, _frozen)
		EnflameOverlay.sync_to(self, _enflamed)
		PoisonOverlay.sync_to(self, _poisoned)
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
	var stacks: int = maxi(1, int(_duration))
	match effect:
		"freeze_hit":
			if _frozen:
				return
			_chill_stacks = mini(_chill_stacks + stacks, BOSS_STACK_THRESHOLD)
			_chill_decay_t = 3.0
			if _chill_stacks >= BOSS_STACK_THRESHOLD:
				_frozen = true
				_frozen_timer = 3.0
				FloatingText.spawn_str(global_position, "FROZEN!", Color(0.7, 0.95, 1.0), get_tree().current_scene)
			else:
				FloatingText.spawn_str(global_position, "CHILL %d/%d" % [_chill_stacks, BOSS_STACK_THRESHOLD], Color(0.45, 0.82, 1.0), get_tree().current_scene)
		"burn_hit":
			if _enflamed:
				EnflameOverlay.refresh_pulse(self)
			else:
				_burn_stacks = mini(_burn_stacks + stacks, BOSS_STACK_THRESHOLD)
				if _burn_stacks >= BOSS_STACK_THRESHOLD:
					_burn_stacks = 0
					_trigger_enflamed()
				else:
					FloatingText.spawn_str(global_position, "BURN %d/%d" % [_burn_stacks, BOSS_STACK_THRESHOLD], Color(1.0, 0.55, 0.2), get_tree().current_scene)
		"shock_hit":
			_shock_stacks = mini(_shock_stacks + stacks, BOSS_STACK_THRESHOLD)
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
	_burn_stacks = mini(_burn_stacks + count, BOSS_STACK_THRESHOLD - 1)
	if _burn_stacks >= 8:
		FloatingText.spawn_str(global_position, "BURN %d/%d" % [_burn_stacks, BOSS_STACK_THRESHOLD], Color(1.0, 0.55, 0.2), get_tree().current_scene)

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

# ── Combat ────────────────────────────────────────────────────────────────────

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

func _update_fire_telegraph() -> void:
	if _shoot_timer > FIRE_TELEGRAPH_LEAD or _stun_timer > 0.0 or _no_attack_timer > 0.0:
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
	# Color: dim red far from firing → bright red just before the burst.
	var t: float = clampf(1.0 - (_shoot_timer / FIRE_TELEGRAPH_LEAD), 0.0, 1.0)
	_fire_telegraph_ring.default_color = Color(1.0, lerpf(0.4, 0.05, t), 0.05,
		0.35 + 0.55 * t)

func _clear_fire_telegraph() -> void:
	if is_instance_valid(_fire_telegraph_ring):
		_fire_telegraph_ring.queue_free()
	_fire_telegraph_ring = null

func _teleport() -> void:
	var offset := Vector2(randf_range(-240.0, 240.0), randf_range(-240.0, 240.0))
	global_position = _safe_teleport_pos(global_position + offset)
	FloatingText.spawn_str(global_position, "!", Color(0.8, 0.1, 1.0), get_tree().current_scene)

# Snaps a candidate teleport position to the nearest floor tile, or stays put
# if nothing valid is nearby. Without this the boss happily lands inside walls
# or off the edge of the grid and becomes unreachable.
func _safe_teleport_pos(target_pos: Vector2) -> Vector2:
	var world := get_tree().current_scene
	if world == null or not ("_grid" in world):
		return target_pos
	var tile: int   = int(world.TILE)
	var grid_w: int = int(world.GRID_W)
	var grid_h: int = int(world.GRID_H)
	var grid: Array = world._grid
	var tx: int = int(target_pos.x / float(tile))
	var ty: int = int(target_pos.y / float(tile))
	if tx >= 0 and tx < grid_w and ty >= 0 and ty < grid_h \
			and int((grid[ty] as Array)[tx]) == 0:
		return target_pos
	for r in range(1, 8):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var nx: int = tx + dx
				var ny: int = ty + dy
				if nx < 0 or nx >= grid_w or ny < 0 or ny >= grid_h:
					continue
				if int((grid[ny] as Array)[nx]) == 0:
					return Vector2(float(nx) + 0.5, float(ny) + 0.5) * float(tile)
	return global_position

# ── Charge attack (phase 2+) ──────────────────────────────────────────────────
func _enter_charge_telegraph() -> void:
	_charge_state = ChargeState.TELEGRAPH
	_charge_t = CHARGE_TELEGRAPH
	_charge_hit = false
	if _charge_line == null:
		_charge_line = Line2D.new()
		_charge_line.width = 4.0
		_charge_line.default_color = Color(1.0, 0.2, 0.0, 0.7)
		_charge_line.z_index = -1
		get_tree().current_scene.add_child(_charge_line)
	_update_charge_line()

func _update_charge_line() -> void:
	if _charge_line == null or not is_instance_valid(_player):
		return
	_charge_dir = (_player.global_position - global_position).normalized()
	_charge_line.clear_points()
	_charge_line.add_point(global_position)
	_charge_line.add_point(global_position + _charge_dir * (CHARGE_SPEED * CHARGE_DURATION))

func _enter_charge_dash() -> void:
	_charge_state = ChargeState.DASH
	_charge_t = CHARGE_DURATION
	if is_instance_valid(_charge_line):
		_charge_line.queue_free()
	_charge_line = null
	if SoundManager:
		SoundManager.play("whoosh", randf_range(0.85, 1.0))

func _enter_charge_cooldown() -> void:
	_charge_state = ChargeState.COOLDOWN
	_charge_t = 1.2
	if is_instance_valid(_charge_line):
		_charge_line.queue_free()
	_charge_line = null

func _exit_tree() -> void:
	if is_instance_valid(_charge_line):
		_charge_line.queue_free()
	_charge_line = null

# ── Shared ────────────────────────────────────────────────────────────────────

func _create_boss_bar() -> void:
	_boss_canvas = CanvasLayer.new()
	_boss_canvas.layer = 18
	get_tree().current_scene.add_child(_boss_canvas)

	# Bar + name plate are anchored to bottom-center so they hug the bottom
	# edge of the viewport even when the canvas is wider/taller than the
	# 1600x900 design rect (web stretch aspect = expand).
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.0, 0.0, 0.88)
	bg.anchor_left = 0.5
	bg.anchor_right = 0.5
	bg.anchor_top = 1.0
	bg.anchor_bottom = 1.0
	bg.offset_left = -700.0
	bg.offset_right = 700.0
	bg.offset_top = -72.0
	bg.offset_bottom = -50.0
	_boss_canvas.add_child(bg)

	_boss_bar_fg = ColorRect.new()
	_boss_bar_fg.color = Color(0.85, 0.08, 0.08)
	_boss_bar_fg.anchor_left = 0.5
	_boss_bar_fg.anchor_right = 0.5
	_boss_bar_fg.anchor_top = 1.0
	_boss_bar_fg.anchor_bottom = 1.0
	_boss_bar_fg.offset_left = -699.0
	_boss_bar_fg.offset_right = -699.0  # full width set by _update_boss_bar
	_boss_bar_fg.offset_top = -71.0
	_boss_bar_fg.offset_bottom = -51.0
	_boss_canvas.add_child(_boss_bar_fg)

	var name_lbl := Label.new()
	name_lbl.text = "THE VOID HERALD"
	name_lbl.anchor_left = 0.0
	name_lbl.anchor_right = 1.0
	name_lbl.anchor_top = 1.0
	name_lbl.anchor_bottom = 1.0
	name_lbl.offset_left = 0.0
	name_lbl.offset_right = 0.0
	name_lbl.offset_top = -92.0
	name_lbl.offset_bottom = -72.0
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
	_boss_canvas.add_child(name_lbl)

func _update_boss_bar() -> void:
	if _boss_bar_fg == null:
		return
	var ratio := clampf(float(health) / float(max_health), 0.0, 1.0)
	# offset_left fixed at -699; offset_right grows from -699 (empty) to
	# +699 (full) so the fill expands rightward from the same start point.
	_boss_bar_fg.offset_right = -699.0 + 1398.0 * ratio

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
		EffectFx.spawn_death_pop(global_position, get_tree().current_scene, Color(1.0, 0.6, 0.2))
		queue_free()

func _drop_loot() -> void:
	for i in 5:
		var gold := GOLD_PICKUP_SCENE.instantiate()
		gold.global_position = global_position + Vector2(randf_range(-40.0, 40.0), randf_range(-40.0, 40.0))
		gold.value = int(randi_range(8, 20) * GameState.loot_multiplier)
		get_tree().current_scene.call_deferred("add_child", gold)
	var bag := LOOT_BAG_SCENE.instantiate()
	bag.global_position = global_position
	# Signature: Brutehammer always drops alongside the random rolls so the
	# boss kill has a guaranteed themed reward.
	bag.items = [ItemDB.boss_signature_brute(),
		ItemDB.random_drop(), ItemDB.random_drop(), ItemDB.random_drop()]
	get_tree().current_scene.call_deferred("add_child", bag)

func _update_health_bar() -> void:
	var bar := get_node_or_null("HealthBar/Foreground")
	if bar == null:
		return
	var ratio := clampf(float(health) / float(max_health), 0.0, 1.0)
	bar.offset_right = -30.0 + 60.0 * ratio
