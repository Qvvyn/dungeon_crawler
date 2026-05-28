extends CharacterBody2D

# The Lich — summoner boss for floors 20+. Stationary glass-cannon that
# spawns skeleton chasers in waves; punishes single-target burst builds
# that can't keep up with adds. At < 50 % HP he sacrifices a nearby
# skeleton to heal himself ~12 % HP, so the player has to either burn
# him down fast or AoE-clear the minions before they get consumed.

const GOLD_PICKUP_SCENE := preload("res://scenes/GoldPickup.tscn")
const LOOT_BAG_SCENE    := preload("res://scenes/LootBag.tscn")
const MINION_SCENE      := preload("res://scenes/EnemyChaser.tscn")

const BOSS_F0 := " /=\\ \n |O| \n /^\\ "
const BOSS_F1 := " /=\\ \n |o| \n /v\\ "
const BOSS_NAME  := "THE LICH"
const BOSS_COLOR := Color(0.55, 1.0, 0.55)

@export var max_health: int = 280
var _gate: BossGate = BossGate.new()    # Theme C HP threshold gates — see BossGate.gd

var health: int            = 280
var _player: Node2D        = null
var _lbl: Label            = null
var _anim_t: float         = 0.0
var _anim_f: int           = 0
var _summon_t: float       = 3.0   # first summon shortly after intro
var _drift_t: float        = 0.0
var _drift_dir: Vector2    = Vector2.ZERO
var _heal_cd: float        = 0.0
var _hit_flash_t: float    = 0.0

# Status effect plumbing (mirrors EnemyBossWraith) so player wand stacks
# work normally on this boss.
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

# Tracks minions spawned by this lich so we know which ones we can
# sacrifice for the heal. Cleaned up lazily as entries free themselves.
var _minions: Array = []

const SUMMON_INTERVAL := 5.0
const SUMMONS_PER_WAVE := 3
const HEAL_AMOUNT_PCT  := 0.12
const HEAL_THRESHOLD_PCT := 0.50

func _ready() -> void:
	health = max_health
	add_to_group("enemy")
	add_to_group("boss")
	collision_layer = 2
	collision_mask  = 1
	_player = get_tree().get_first_node_in_group("player")

	var cshape := CollisionShape2D.new()
	var circ := CircleShape2D.new()
	circ.radius = 24.0
	cshape.shape = circ
	add_child(cshape)

	_lbl = Label.new()
	_lbl.name = "AsciiChar"   # so the FP rig's live-glyph sync finds it
	_lbl.add_theme_font_override("font", MonoFont.get_font())
	_lbl.add_theme_font_size_override("font_size", 24)
	_lbl.add_theme_constant_override("line_separation", -3)
	_lbl.add_theme_color_override("font_color", BOSS_COLOR)
	_lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.18, 0.0))
	_lbl.add_theme_constant_override("outline_size", 2)
	_lbl.text = BOSS_F0
	_lbl.size = Vector2(96, 96)
	_lbl.position = Vector2(-40, -40)
	add_child(_lbl)

	BossIntro.show_for(get_tree().current_scene, BOSS_NAME, BOSS_COLOR)
	_create_boss_bar()

func _physics_process(delta: float) -> void:
	if _frozen or _stun_timer > 0.0:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	_anim_t += delta
	if _anim_t >= 0.45:
		_anim_t = 0.0
		_anim_f = 1 - _anim_f
		_lbl.text = BOSS_F0 if _anim_f == 0 else BOSS_F1
	_tick_status(delta)
	if not is_instance_valid(self): return
	_gate.tick(delta)

	# Light kite — drift slowly perpendicular to the player vector with
	# occasional reversals so the lich doesn't park in melee range.
	if is_instance_valid(_player):
		_drift_t -= delta
		if _drift_t <= 0.0:
			_drift_t = randf_range(2.5, 4.0)
			var to_p := (_player.global_position - global_position).normalized()
			var sign_choice: float = 1.0 if randf() > 0.5 else -1.0
			_drift_dir = to_p.rotated(PI * 0.5) * sign_choice * 0.55
			# Back off if too close
			var d := global_position.distance_to(_player.global_position)
			if d < 220.0:
				_drift_dir -= to_p * 0.7
		velocity = _drift_dir * 80.0
	move_and_slide()

	_summon_t -= delta
	if _summon_t <= 0.0 and _no_attack_timer <= 0.0:
		_summon_t = SUMMON_INTERVAL
		_summon_wave()

	_heal_cd -= delta
	if _heal_cd <= 0.0 and float(health) / float(max_health) < HEAL_THRESHOLD_PCT:
		_heal_cd = 4.0   # only attempt every 4 s
		_try_sacrifice_heal()

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

# ── Summoning ──────────────────────────────────────────────────────────────

func _summon_wave() -> void:
	var enemies_node := get_tree().current_scene.get_node_or_null("Enemies")
	if enemies_node == null:
		return
	if SoundManager:
		SoundManager.play("summon", randf_range(0.85, 1.0))
	for i in SUMMONS_PER_WAVE:
		var ang := (TAU / float(SUMMONS_PER_WAVE)) * float(i)
		var spawn_pos := global_position + Vector2(cos(ang), sin(ang)) * 64.0
		var m: Node = MINION_SCENE.instantiate()
		if m is Node2D:
			(m as Node2D).global_position = spawn_pos
		# Half-HP minions so they're meaningful but don't stall the fight.
		m.set_meta("is_zombie_revive", true)
		_minions.append(weakref(m))
		enemies_node.add_child(m)

func _try_sacrifice_heal() -> void:
	# Find the closest still-alive minion and consume it for HP. Falls
	# through silently if no minion is alive — the lich just keeps
	# fighting and tries again next interval.
	var best_d_sq: float = INF
	var best_idx: int = -1
	var best_node: Node2D = null
	for i in _minions.size():
		var w: WeakRef = _minions[i] as WeakRef
		var n := w.get_ref() as Node2D
		if n == null or not is_instance_valid(n):
			continue
		var d_sq := global_position.distance_squared_to(n.global_position)
		if d_sq < best_d_sq:
			best_d_sq = d_sq
			best_idx = i
			best_node = n
	if best_node == null:
		return
	# Visual line + heal pop, then free the minion.
	FloatingText.spawn_str(best_node.global_position, "DEVOURED",
		Color(0.55, 1.0, 0.55), get_tree().current_scene)
	var heal_amt: int = maxi(1, int(round(float(max_health) * HEAL_AMOUNT_PCT)))
	health = mini(max_health, health + heal_amt)
	FloatingText.spawn(global_position, heal_amt, true, get_tree().current_scene)
	_update_boss_bar()
	best_node.queue_free()
	_minions.remove_at(best_idx)

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
				take_damage(4)
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
				take_damage(6)
				if not is_instance_valid(self): return

func apply_status(effect: String, _duration: float) -> void:
	var stacks: int = maxi(1, int(_duration))
	match effect:
		"freeze_hit":
			_chill_stacks = mini(_chill_stacks + stacks, 10)
			_chill_decay_t = 3.0
			if _chill_stacks >= 10:
				_frozen = true
				_frozen_timer = 3.5
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
				_stun_timer = 1.0
		"poison_hit":
			_poisoned = true
			_poison_timer = 9.0

func take_damage(amount: int) -> void:
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
		GameState.kills += 5
		GameState.add_xp(40)
		_drop_loot()
		EffectFx.spawn_death_pop(global_position, get_tree().current_scene, BOSS_COLOR)
		queue_free()

func _drop_loot() -> void:
	for i in 5:
		var gold := GOLD_PICKUP_SCENE.instantiate()
		gold.global_position = global_position + Vector2(randf_range(-40.0, 40.0), randf_range(-40.0, 40.0))
		gold.value = int(randi_range(8, 20) * GameState.loot_multiplier)
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
	bg.color = Color(0.0, 0.05, 0.0, 0.88)
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
	_boss_bar_fg.color = Color(0.55, 1.0, 0.55)
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
