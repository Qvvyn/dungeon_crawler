extends CharacterBody2D

# The Devourer — sustain-DPS check boss for floors 25+. Massive HP, slow
# movement, periodically chain-tethers the player and drags them in for
# a melee bite. Punishes burst-only builds: you can't kill him before
# multiple tethers, and dodging the bite costs distance you spent
# closing for the next damage window.

const GOLD_PICKUP_SCENE := preload("res://scenes/GoldPickup.tscn")
const LOOT_BAG_SCENE    := preload("res://scenes/LootBag.tscn")

const BOSS_F0 := "/(O)\\\n \\m/ "
const BOSS_F1 := "/(o)\\\n /M\\ "
const BOSS_NAME  := "THE DEVOURER"
const BOSS_COLOR := Color(1.0, 0.45, 0.10)

@export var max_health: int = 600
var _gate: BossGate = BossGate.new()    # Theme C HP threshold gates — see BossGate.gd

var health: int            = 600
var _player: Node2D        = null
var _lbl: Label            = null
var _sprite: AsciiSpriteDriver = null   # boss_devourer sprite (standalone, manual driver)
var _anim_t: float         = 0.0
var _anim_f: int           = 0
var _hit_flash_t: float    = 0.0

# Tether: telegraphed grab + pull. State machine cycles:
#   IDLE → TELEGRAPH (1.0 s warning) → PULL (1.0 s drag) → COOLDOWN (5 s)
enum TetherState { IDLE, TELEGRAPH, PULL, COOLDOWN }
var _tether_state: int       = TetherState.IDLE
var _tether_t: float         = 4.0
var _tether_target: Vector2  = Vector2.ZERO   # captured at telegraph start
var _tether_line: Line2D     = null

# Bite: contact AoE that fires when player is within bite radius and
# we're not in a cooldown.
const BITE_RADIUS  := 90.0
const BITE_DAMAGE  := 12
var _bite_cd: float = 0.0

const TETHER_TELEGRAPH := 1.0
const TETHER_PULL      := 1.0
const TETHER_COOLDOWN  := 4.0
const TETHER_PULL_DIST := 280.0

# Status effect plumbing — same fields the other bosses use.
var _chill_stacks: int      = 0
var _chill_decay_t: float   = 0.0
var _frozen: bool           = false
var _frozen_timer: float    = 0.0
var _burn_stacks: int       = 0
var _enflamed: bool         = false
var _enflame_timer: float   = 0.0
var _enflame_tick: float    = 0.0
var _shock_stacks: int      = 0
var _stun_timer: float      = 0.0
var _no_attack_timer: float = 0.0
var _poisoned: bool         = false
var _poison_timer: float    = 0.0
var _poison_tick: float     = 0.0

var _boss_canvas: CanvasLayer = null
var _boss_bar_fg: ColorRect   = null

func _ready() -> void:
	health = max_health
	add_to_group("enemy")
	add_to_group("boss")
	collision_layer = 2
	collision_mask  = 1
	_player = get_tree().get_first_node_in_group("player")
	# Bosses loom large in FP — ~1.7× a normal body (base 0.014) so they read
	# as a real threat filling the corridor.
	set_meta("fp_pixel_size", 0.024)

	var cshape := CollisionShape2D.new()
	var circ := CircleShape2D.new()
	circ.radius = 26.0   # navigable: fits a 3-wide corridor (art stays big, collider doesn't)
	cshape.shape = circ
	add_child(cshape)

	_lbl = Label.new()
	_lbl.name = "AsciiChar"   # so the FP rig's live-glyph sync finds it
	_lbl.add_theme_font_override("font", MonoFont.get_font())
	_lbl.add_theme_font_size_override("font_size", 26)
	_lbl.add_theme_constant_override("line_separation", -3)
	_lbl.add_theme_color_override("font_color", BOSS_COLOR)
	_lbl.add_theme_color_override("font_outline_color", Color(0.30, 0.10, 0.0))
	_lbl.add_theme_constant_override("outline_size", 2)
	_lbl.text = BOSS_F0
	_lbl.size = Vector2(120, 90)
	_lbl.position = Vector2(-50, -40)
	add_child(_lbl)
	_sprite = AsciiSpriteDriver.new()
	if _sprite.setup(_lbl, "boss_devourer"):
		var fm := _sprite.fp_metas()
		for mk in fm:
			set_meta(mk, fm[mk])
		AsciiSprites.apply_hitbox(self, "boss_devourer")
	else:
		_sprite = null

	_tether_line = Line2D.new()
	_tether_line.width = 0.0   # invisible until telegraph fires
	_tether_line.default_color = Color(1.0, 0.4, 0.05, 0.9)
	_tether_line.z_index = 4
	add_child(_tether_line)

	BossIntro.show_for(get_tree().current_scene, BOSS_NAME, BOSS_COLOR)
	_create_boss_bar()

func _physics_process(delta: float) -> void:
	# Tick status timers + the HP gate FIRST, so freeze/stun actually
	# expire and the gate keeps counting down even while the boss is
	# frozen/stunned. (Previously these ran after the early-return below,
	# so a frozen boss never thawed AND a triggered gate never released —
	# making the boss effectively immortal under a freeze/shock build.)
	_tick_status(delta)
	if not is_instance_valid(self): return
	_gate.tick(delta)
	if _frozen or _stun_timer > 0.0:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	_anim_t += delta
	if _anim_t >= 0.5:
		_anim_t = 0.0
		_anim_f = 1 - _anim_f
		if _sprite == null:   # driver owns the label (its idle art) when wired
			_lbl.text = BOSS_F0 if _anim_f == 0 else BOSS_F1

	# Slow shamble toward the player. Tether handles the burst pressure.
	if is_instance_valid(_player):
		var to_p: Vector2 = _player.global_position - global_position
		velocity = to_p.normalized() * 55.0
	move_and_slide()

	_tick_tether(delta)
	_tick_bite(delta)

	if _hit_flash_t > 0.0:
		_hit_flash_t -= delta
		_lbl.modulate = Color(1.0, 0.6, 0.6)
	else:
		_lbl.modulate = _get_status_modulate()

func _get_status_modulate() -> Color:
	if _frozen: return StatusTint.frozen()
	if _stun_timer > 0.0: return StatusTint.stun()
	if _poisoned: return Color(0.45, 1.0, 0.55)
	if _enflamed: return Color(1.0, 0.45, 0.05)
	return Color.WHITE

# ── Tether ─────────────────────────────────────────────────────────────────

func _tick_tether(delta: float) -> void:
	if not is_instance_valid(_player):
		return
	_tether_t -= delta * GameState.enemy_attack_rate()   # frequency-led difficulty
	match _tether_state:
		TetherState.IDLE:
			if _tether_t <= 0.0 and _no_attack_timer <= 0.0:
				_tether_state = TetherState.TELEGRAPH
				_tether_t = TETHER_TELEGRAPH
				_tether_target = _player.global_position
				_tether_line.width = 3.0
				if SoundManager:
					SoundManager.play("summon", 0.6)
		TetherState.TELEGRAPH:
			# Track the player's position so the line "snaps" to where they are
			# at the moment the pull lands.
			_tether_target = _player.global_position
			_update_tether_line(_tether_target,
				Color(1.0, 0.4, 0.05, 0.45 + 0.4 * sin(Time.get_ticks_msec() * 0.018)))
			if _tether_t <= 0.0:
				_tether_state = TetherState.PULL
				_tether_t = TETHER_PULL
				_apply_tether_pull()
		TetherState.PULL:
			_update_tether_line(_player.global_position,
				Color(1.0, 0.6, 0.10, 0.95))
			if _tether_t <= 0.0:
				_tether_state = TetherState.COOLDOWN
				_tether_t = TETHER_COOLDOWN
				_tether_line.width = 0.0
				# FP beam cleanup — pair with the per-tick set_enemy_beam
				# in _update_tether_line.
				if GameState.active_rig != null and is_instance_valid(GameState.active_rig) \
						and GameState.active_rig.has_method("clear_enemy_beam"):
					GameState.active_rig.clear_enemy_beam(self)
		TetherState.COOLDOWN:
			if _tether_t <= 0.0:
				_tether_state = TetherState.IDLE
				_tether_t = 0.5

func _update_tether_line(target_global: Vector2, col: Color) -> void:
	if _tether_line == null:
		return
	_tether_line.clear_points()
	_tether_line.add_point(Vector2.ZERO)
	_tether_line.add_point(_tether_line.to_local(target_global))
	_tether_line.default_color = col
	# FP mirror — emit a beam from the boss to the tether target so the
	# pull telegraph + the active pull both read in first-person. Telegraph
	# state shows a solid YELLOW beam (clear "warming up" cue, easy to read
	# at a glance as non-damaging); the PULL state uses the caller's hot
	# orange for the actual pull. Both render as a single MeshInstance3D
	# tube — the old dotted "·" pool was more expensive and read as
	# "already firing" peripherally.
	if GameState.active_rig != null and is_instance_valid(GameState.active_rig) \
			and GameState.active_rig.has_method("set_enemy_beam"):
		var beam_col: Color = col
		if _tether_state == TetherState.TELEGRAPH:
			var pulse: float = 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.012)
			beam_col = Color(1.0, 0.92, 0.20, clampf(pulse, 0.25, 1.0))
		GameState.active_rig.set_enemy_beam(self, global_position, target_global,
			beam_col, false)

func _apply_tether_pull() -> void:
	if not is_instance_valid(_player):
		return
	# Use Player.apply_knockback so the pull respects the Player's existing
	# knockback decay system (and isn't immediately overwritten by the
	# Player's per-frame velocity assignment from input).
	if _player.has_method("apply_knockback"):
		var to_boss: Vector2 = (global_position - _player.global_position).normalized()
		_player.call("apply_knockback", to_boss * (TETHER_PULL_DIST / TETHER_PULL))
	FloatingText.spawn_str(_player.global_position, "PULLED!",
		Color(1.0, 0.4, 0.05), get_tree().current_scene)

# Bite — quick AoE hit when the player crowds the Devourer between
# tethers. Soft damage cap via cooldown so chip-DPS isn't crippling.
func _tick_bite(delta: float) -> void:
	_bite_cd -= delta * GameState.enemy_attack_rate()   # frequency-led difficulty
	if _bite_cd > 0.0:
		return
	if not is_instance_valid(_player):
		return
	if global_position.distance_to(_player.global_position) > BITE_RADIUS:
		return
	_bite_cd = 1.6
	if _player.has_method("take_damage"):
		_player.call("take_damage", BITE_DAMAGE)
	FloatingText.spawn_str(global_position, "BITE!",
		Color(1.0, 0.3, 0.05), get_tree().current_scene)

# ── Status / damage ────────────────────────────────────────────────────────

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
				take_damage(8)
				if not is_instance_valid(self): return
	if _stun_timer > 0.0: _stun_timer -= delta
	if _no_attack_timer > 0.0: _no_attack_timer -= delta
	if _poisoned:
		_poison_timer -= delta
		if _poison_timer <= 0.0:
			_poisoned = false
		else:
			_poison_tick -= delta
			if _poison_tick <= 0.0:
				_poison_tick = 0.28
				take_damage(10)
				if not is_instance_valid(self): return

func apply_status(effect: String, _duration: float) -> void:
	var stacks: int = maxi(1, int(_duration))
	match effect:
		"freeze_hit":
			_chill_stacks = mini(_chill_stacks + stacks, 10)
			_chill_decay_t = 3.0
			if _chill_stacks >= 10:
				_frozen = true
				_frozen_timer = 3.0
		"burn_hit":
			if _enflamed:
				EnflameOverlay.refresh_pulse(self)
				EnflameOverlay.register_extra_burn(self, stacks)
			else:
				_burn_stacks = mini(_burn_stacks + stacks, 10)
				if _burn_stacks >= 10:
					_burn_stacks = 0
					_enflamed = true
					_enflame_timer = 5.0
					EnflameOverlay.sync_to(self, true)
					EnflameOverlay.spawn_patch(self)
		"shock_hit":
			_shock_stacks = mini(_shock_stacks + stacks, 10)
			if _shock_stacks >= 10:
				_shock_stacks = 0
				_stun_timer = 0.8   # tank — shorter stun
		"poison_hit":
			_poisoned = true
			_poison_timer = 9.0

func take_damage(amount: int, _source: Node = null) -> void:
	var actual := int(float(amount) * 1.25) if (_frozen or _chill_stacks > 0) else amount
	var r: Dictionary = _gate.apply(actual, health, max_health)
	if r.triggered:
		health = int(r.new_hp)
		_hit_flash_t = 0.28
		FloatingText.spawn_str(global_position + Vector2(0, -28),
			"GATE!", Color(1.0, 0.85, 0.30), get_tree().current_scene)
		EffectFx.spawn_death_pop(global_position, get_tree().current_scene, Color(1.0, 0.85, 0.30))
		_update_boss_bar()
		return
	if r.blocked:
		health = int(r.new_hp)
		_hit_flash_t = 0.10
		FloatingText.spawn(global_position, int(r.actual), false, get_tree().current_scene)
		_update_boss_bar()
		return
	if r.broke:
		EffectFx.spawn_death_pop(global_position, get_tree().current_scene, Color(1.0, 0.85, 0.30))
	health = int(r.new_hp)
	_hit_flash_t = 0.14
	FloatingText.spawn(global_position, int(r.actual), false, get_tree().current_scene)
	_update_boss_bar()
	if health <= 0:
		if is_instance_valid(_boss_canvas):
			_boss_canvas.queue_free()
		# Clear any active FP tether so the pooled Line2D doesn't linger
		# after the boss dies mid-pull.
		if GameState.active_rig != null and is_instance_valid(GameState.active_rig) \
				and GameState.active_rig.has_method("clear_enemy_beam"):
			GameState.active_rig.clear_enemy_beam(self)
		GameState.kills += 5
		GameState.add_xp(40)
		_drop_loot()
		EffectFx.spawn_death_pop(global_position, get_tree().current_scene, BOSS_COLOR)
		queue_free()

func _drop_loot() -> void:
	for i in 7:
		var gold := GOLD_PICKUP_SCENE.instantiate()
		gold.global_position = global_position + Vector2(randf_range(-50.0, 50.0), randf_range(-50.0, 50.0))
		gold.value = int(randi_range(10, 24) * GameState.loot_multiplier)
		get_tree().current_scene.call_deferred("add_child", gold)
	var bag := LOOT_BAG_SCENE.instantiate()
	bag.global_position = global_position
	bag.items = [ItemDB.generate_wand(Item.RARITY_LEGENDARY)]
	get_tree().current_scene.call_deferred("add_child", bag)

# ── Boss bar ───────────────────────────────────────────────────────────────

func _create_boss_bar() -> void:
	_boss_canvas = CanvasLayer.new()
	_boss_canvas.layer = 18
	get_tree().current_scene.add_child(_boss_canvas)
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.0, 0.0, 0.88)
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
	_boss_bar_fg.color = Color(1.0, 0.45, 0.10)
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
	name_lbl.offset_top = -92.0
	name_lbl.offset_bottom = -72.0
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", BOSS_COLOR)
	_boss_canvas.add_child(name_lbl)

func _update_boss_bar() -> void:
	if _boss_bar_fg == null: return
	_boss_bar_fg.offset_right = -699.0 + 1398.0 * clampf(float(health) / float(max_health), 0.0, 1.0)
