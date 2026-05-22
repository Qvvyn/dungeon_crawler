extends CharacterBody2D

# Magma Tyrant — Lava Rift signature boss. Slow-moving siege caster that
# saturates the floor with lava puddles and lobbed fireballs. Kit forces
# the player to keep moving (puddles linger) without ever teleporting,
# which sets it apart from Architect (turret) and Wraith (blink-volley).

const GOLD_PICKUP_SCENE := preload("res://scenes/GoldPickup.tscn")
const LOOT_BAG_SCENE    := preload("res://scenes/LootBag.tscn")
const PROJECTILE_SCENE  := preload("res://scenes/Projectile.tscn")

const BOSS_F0 := " /^\\\n[#X#]\n /|\\"
const BOSS_F1 := " \\^/\n(#X#)\n /|\\"
const BOSS_NAME  := "MAGMA TYRANT"
const BOSS_COLOR := Color(1.00, 0.45, 0.10)

@export var max_health: int = 280

var health: int             = 280
var _player: Node2D         = null
var _lbl: Label             = null
var _anim_timer: float      = 0.0
var _anim_frame: int        = 0
var _phase: int             = 1
var _hit_flash_t: float     = 0.0
var _boss_canvas: CanvasLayer = null
var _boss_bar_fg: ColorRect   = null

# Erupt cycle — periodically spawns lava puddles around the player.
var _erupt_timer: float     = 2.0
const ERUPT_INT_P1 := 3.4
const ERUPT_INT_P2 := 2.0
const PUDDLES_P1   := 3
const PUDDLES_P2   := 5

# Fan-shot cycle (phase 2 only) — 5-shot arc of slow fireballs.
var _fan_timer: float       = 5.0
const FAN_INT      := 4.5
const FAN_COUNT    := 5
const FAN_ARC_DEG  := 70.0

# Move speed — slow shuffle so kiting works but the player still has to
# break sightlines if they let puddles stack.
const MOVE_SPEED_P1 := 60.0
const MOVE_SPEED_P2 := 95.0

const BOSS_STACK_THRESHOLD := 15

# Fire aura — chip damage when standing within MELT_RADIUS of the boss.
const MELT_RADIUS := 90.0
var _melt_tick_t: float = 0.0

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
	circ.radius = 26.0
	cshape.shape = circ
	add_child(cshape)

	_lbl = Label.new()
	var mono := MonoFont.get_font()
	_lbl.add_theme_font_override("font", mono)
	_lbl.add_theme_font_size_override("font_size", 22)
	_lbl.add_theme_constant_override("line_separation", -3)
	_lbl.add_theme_color_override("font_color", BOSS_COLOR)
	_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_TOP
	_lbl.offset_left   = -34
	_lbl.offset_top    = -32
	_lbl.offset_right  =  38
	_lbl.offset_bottom =  40
	_lbl.text = BOSS_F0
	add_child(_lbl)

	_create_boss_bar()
	FloatingText.spawn_str(global_position, "BOSS!", BOSS_COLOR, get_tree().current_scene)
	BossIntro.show_for(get_tree().current_scene, BOSS_NAME, BOSS_COLOR)
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

	# Slow march toward the player. Movement is light flavor — the real
	# threat is the puddle field forcing the player to relocate.
	var to_p: Vector2 = _player.global_position - global_position
	var spd: float = MOVE_SPEED_P2 if _phase >= 2 else MOVE_SPEED_P1
	if to_p.length() > 110.0:
		velocity = to_p.normalized() * spd
	else:
		velocity = Vector2.ZERO
	move_and_slide()

	_tick_erupt(delta)
	if _phase >= 2:
		_tick_fan(delta)
	_tick_melt_aura(delta)
	_tick_anim(delta)

func _check_phases() -> void:
	if _phase == 1 and health * 100 <= max_health * 50:
		_phase = 2
		FloatingText.spawn_str(global_position, "MELTDOWN!",
			Color(1.0, 0.55, 0.10), get_tree().current_scene)
		_erupt_timer = 0.6
		if SoundManager:
			SoundManager.play("boss_phase")

# ── Erupt — drops puddles in a ring around the player ────────────────────────
func _tick_erupt(delta: float) -> void:
	_erupt_timer -= delta
	if _erupt_timer > 0.0 or _no_attack_timer > 0.0:
		return
	_erupt_timer = ERUPT_INT_P2 if _phase >= 2 else ERUPT_INT_P1
	var count: int = PUDDLES_P2 if _phase >= 2 else PUDDLES_P1
	if not is_instance_valid(_player): return
	var center: Vector2 = _player.global_position
	for i in count:
		var ang: float = randf() * TAU
		var radius: float = randf_range(40.0, 130.0)
		var spot: Vector2 = center + Vector2(cos(ang), sin(ang)) * radius
		_spawn_lava_puddle(spot)

# Single lava puddle — telegraph circle, then a damaging Area2D for 4 s.
# Built locally rather than using the Mine scene so the scaling/tint/fuse
# can be tuned independently.
func _spawn_lava_puddle(pos: Vector2) -> void:
	var holder := Node2D.new()
	holder.global_position = pos
	get_tree().current_scene.add_child(holder)

	# Telegraph ring — soft pulse for 0.55 s before the puddle lands.
	var tele := Line2D.new()
	tele.width = 2.0
	tele.default_color = Color(1.0, 0.35, 0.05, 0.6)
	var segs := 22
	for i in segs + 1:
		var a := (TAU / float(segs)) * float(i)
		tele.add_point(Vector2(cos(a), sin(a)) * 32.0)
	holder.add_child(tele)
	var tw := holder.create_tween()
	tw.tween_property(tele, "modulate:a", 0.15, 0.55)
	tw.tween_callback(_finish_telegraph.bind(holder, tele))

func _finish_telegraph(holder: Node2D, tele: Line2D) -> void:
	if not is_instance_valid(holder): return
	if is_instance_valid(tele):
		tele.queue_free()
	_arm_puddle(holder)

func _arm_puddle(holder: Node2D) -> void:
	if not is_instance_valid(holder): return
	# Audio cue for the puddle landing — uses a low-pitched explosion sound
	# (the engine's existing sample) so the player gets a "splat" feel
	# without needing a new asset. Pitch jitter so multiple puddles in a
	# single eruption don't sound copy-pasted.
	if SoundManager:
		SoundManager.play("explosion", randf_range(0.55, 0.70))
	# ASCII glyph for the active puddle so we stay on-brand with the rest
	# of the visuals (per the project's MonoFont preference).
	var glyph := Label.new()
	var mono := MonoFont.get_font()
	glyph.add_theme_font_override("font", mono)
	glyph.add_theme_font_size_override("font_size", 14)
	glyph.add_theme_constant_override("line_separation", -4)
	glyph.add_theme_color_override("font_color", Color(1.0, 0.45, 0.05))
	glyph.add_theme_color_override("font_outline_color", Color(0.25, 0.0, 0.0))
	glyph.add_theme_constant_override("outline_size", 2)
	glyph.text = "~~~\n>X<\n~~~"
	glyph.position = Vector2(-18, -18)
	glyph.size     = Vector2(40, 40)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(glyph)

	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask  = 1
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = 30.0
	cs.shape = sh
	area.add_child(cs)
	holder.add_child(area)

	holder.set_meta("life", 4.0)
	holder.set_meta("tick", 0.0)
	# Tick via a Timer so we don't have to subclass Node2D. The callback
	# is a bound method (not an anon lambda) so the closing parens stay
	# unambiguous to the GDScript parser.
	var t := Timer.new()
	t.wait_time = 0.10
	t.autostart = true
	holder.add_child(t)
	t.timeout.connect(_puddle_tick.bind(holder, glyph, area))

func _puddle_tick(holder: Node2D, glyph: Label, area: Area2D) -> void:
	if not is_instance_valid(holder): return
	var life: float = float(holder.get_meta("life", 0.0)) - 0.10
	var tick: float = float(holder.get_meta("tick", 0.0)) + 0.10
	if life <= 0.0:
		holder.queue_free()
		return
	holder.set_meta("life", life)
	holder.set_meta("tick", tick)
	# Fade as the puddle expires so the player can see it's almost gone.
	var fade: float = clampf(life / 4.0, 0.0, 1.0)
	if is_instance_valid(glyph):
		glyph.modulate = Color(1.0, 0.5 + 0.3 * fade, 0.1, 0.55 + 0.45 * fade)
	# 0.5 s damage tick — the player has to leave, not tank.
	if tick >= 0.5:
		holder.set_meta("tick", 0.0)
		if is_instance_valid(area):
			for body in area.get_overlapping_bodies():
				if body.is_in_group("player") and body.has_method("take_damage"):
					body.take_damage(3)

# ── Phase-2 fan shot ─────────────────────────────────────────────────────────
func _tick_fan(delta: float) -> void:
	_fan_timer -= delta
	if _fan_timer > 0.0 or _no_attack_timer > 0.0:
		return
	_fan_timer = FAN_INT
	if not is_instance_valid(_player): return
	var base_dir: Vector2 = (_player.global_position - global_position).normalized()
	var arc_rad: float = deg_to_rad(FAN_ARC_DEG)
	for i in FAN_COUNT:
		var t: float = -0.5 + float(i) / float(FAN_COUNT - 1)
		var dir: Vector2 = base_dir.rotated(t * arc_rad)
		var p: Node = PROJECTILE_SCENE.instantiate()
		p.global_position = global_position
		p.set("direction", dir)
		p.set("source", "enemy")
		p.set("damage", 3)
		p.set("speed", 280.0)
		get_tree().current_scene.add_child(p)
	if SoundManager:
		SoundManager.play("explosion", randf_range(1.20, 1.35))

# ── Melt aura — chip damage when standing on top of the boss ─────────────────
func _tick_melt_aura(delta: float) -> void:
	_melt_tick_t -= delta
	if _melt_tick_t > 0.0:
		return
	_melt_tick_t = 0.6
	if not is_instance_valid(_player): return
	if global_position.distance_to(_player.global_position) <= MELT_RADIUS:
		if _player.has_method("take_damage"):
			_player.call("take_damage", 2)

# ── Anim ────────────────────────────────────────────────────────────────────
func _tick_anim(delta: float) -> void:
	_anim_timer += delta
	if _anim_timer >= 0.32:
		_anim_timer = 0.0
		_anim_frame = 1 - _anim_frame
	if _lbl == null: return
	_lbl.text = BOSS_F0 if _anim_frame == 0 else BOSS_F1
	if _hit_flash_t > 0.0:
		_hit_flash_t -= delta
		_lbl.modulate = Color(1.0, 0.4, 0.4)
	else:
		_lbl.modulate = _get_status_modulate()
	FrozenBlock.sync_to(self, _frozen)
	EnflameOverlay.sync_to(self, _enflamed)
	PoisonOverlay.sync_to(self, _poisoned)

# ── Status (boss pattern, copied from existing bosses) ──────────────────────
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
	var stacks: int = maxi(1, int(_duration))
	match effect:
		"freeze_hit":
			if _frozen: return
			_chill_stacks = mini(_chill_stacks + stacks, BOSS_STACK_THRESHOLD)
			_chill_decay_t = 3.0
			if _chill_stacks >= BOSS_STACK_THRESHOLD:
				_frozen = true
				_frozen_timer = 3.0
				FloatingText.spawn_str(global_position, "FROZEN!",
					Color(0.7, 0.95, 1.0), get_tree().current_scene)
			else:
				FloatingText.spawn_str(global_position,
					"CHILL %d/%d" % [_chill_stacks, BOSS_STACK_THRESHOLD],
					Color(0.45, 0.82, 1.0), get_tree().current_scene)
		"burn_hit":
			# Magma Tyrant is fire-resistant — burn stacks decay 50% faster
			# and cap lower. Encourages elemental swap rather than fire-onto-fire.
			if _enflamed:
				EnflameOverlay.refresh_pulse(self)
				EnflameOverlay.register_extra_burn(self, stacks)
			else:
				_burn_stacks = mini(_burn_stacks + stacks, BOSS_STACK_THRESHOLD)
				if _burn_stacks >= BOSS_STACK_THRESHOLD:
					_burn_stacks = 0
					_enflamed = true
					_enflame_timer = 3.0   # shorter than other bosses (5.0)
					_enflame_tick = 0.0
					FloatingText.spawn_str(global_position, "ENFLAMED!",
						Color(1.0, 0.3, 0.0), get_tree().current_scene)
					take_damage(8)         # smaller pop than other bosses (12)
					if is_instance_valid(self):
						EnflameOverlay.sync_to(self, true)
						EnflameOverlay.spawn_patch(self)
				else:
					FloatingText.spawn_str(global_position,
						"BURN %d/%d" % [_burn_stacks, BOSS_STACK_THRESHOLD],
						Color(1.0, 0.55, 0.2), get_tree().current_scene)
		"shock_hit":
			_shock_stacks = mini(_shock_stacks + stacks, BOSS_STACK_THRESHOLD)
			if _shock_stacks >= BOSS_STACK_THRESHOLD:
				_shock_stacks = 0
				FloatingText.spawn_str(global_position, "ELECTRIFIED!",
					Color(0.75, 0.9, 1.0), get_tree().current_scene)
				take_damage(10)
				if is_instance_valid(self):
					ElectricBolt.trigger(self)
			else:
				FloatingText.spawn_str(global_position,
					"SHOCK %d/%d" % [_shock_stacks, BOSS_STACK_THRESHOLD],
					Color(0.7, 0.85, 1.0), get_tree().current_scene)

func _get_status_modulate() -> Color:
	if _frozen:           return Color(0.78, 0.92, 1.0)
	if _stun_timer > 0.0: return Color(0.9, 0.9, 0.3)
	if _enflamed:
		var flicker := sin(Time.get_ticks_msec() * 0.025) * 0.12 + 0.88
		return Color(1.0, flicker * 0.35, 0.05)
	# Idle pulse — slow lava throb so the boss reads as molten without
	# flashing. Damped further when reduce-flashing is on.
	var pulse: float = 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.003)
	if GameState.disable_flashing:
		pulse = 0.92
	return Color(1.0, 0.45 * pulse, 0.10 * pulse)

func take_damage(amount: int) -> void:
	# Shock crit — same +25% as other bosses.
	var actual := int(float(amount) * 1.25) if (_shock_stacks >= 5) else amount
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
		EffectFx.spawn_death_pop(global_position, get_tree().current_scene,
			Color(1.0, 0.55, 0.1))
		queue_free()

func _drop_loot() -> void:
	for i in 5:
		var gold := GOLD_PICKUP_SCENE.instantiate()
		gold.global_position = global_position + Vector2(
			randf_range(-40.0, 40.0), randf_range(-40.0, 40.0))
		gold.value = int(randi_range(8, 20) * GameState.loot_multiplier)
		get_tree().current_scene.call_deferred("add_child", gold)
	var bag := LOOT_BAG_SCENE.instantiate()
	bag.global_position = global_position
	bag.items = [ItemDB.boss_signature_magma(),
		ItemDB.random_drop(), ItemDB.random_drop(), ItemDB.random_drop()]
	get_tree().current_scene.call_deferred("add_child", bag)

func _create_boss_bar() -> void:
	_boss_canvas = CanvasLayer.new()
	_boss_canvas.layer = 18
	get_tree().current_scene.add_child(_boss_canvas)
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.02, 0.0, 0.88)
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
	_boss_bar_fg.color = Color(1.0, 0.40, 0.05)
	_boss_bar_fg.anchor_left = 0.5
	_boss_bar_fg.anchor_right = 0.5
	_boss_bar_fg.anchor_top = 1.0
	_boss_bar_fg.anchor_bottom = 1.0
	_boss_bar_fg.offset_left = -699.0
	_boss_bar_fg.offset_right = -699.0
	_boss_bar_fg.offset_top = -71.0
	_boss_bar_fg.offset_bottom = -51.0
	_boss_canvas.add_child(_boss_bar_fg)
	var name_lbl := Label.new()
	name_lbl.text = BOSS_NAME
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
	name_lbl.add_theme_color_override("font_color", BOSS_COLOR)
	_boss_canvas.add_child(name_lbl)

func _update_boss_bar() -> void:
	if _boss_bar_fg == null: return
	_boss_bar_fg.offset_right = -699.0 + 1398.0 * clampf(
		float(health) / float(max_health), 0.0, 1.0)
