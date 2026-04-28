extends CharacterBody2D

# Rival wizard — uses the same multi-line ASCII silhouette as the player but
# in a randomized robe color (no blue glow). Fires a real, lootable wand: on
# death the wand drops in a regular loot bag so the player can pick it up.
# Spawned exactly once per portal room (see World._spawn_portal_wizard).

const GOLD_PICKUP_SCENE := preload("res://scenes/GoldPickup.tscn")
const LOOT_BAG_SCENE    := preload("res://scenes/LootBag.tscn")
const PROJ_SCENE        := preload("res://scenes/Projectile.tscn")
const FIRE_PATCH_SCRIPT = preload("res://scripts/FirePatch.gd")

@export var move_speed: float         = 110.0
@export var preferred_distance: float = 300.0
@export var max_health: int           = 180  # 18 → 35 → 60 → 180 (3× across the board)

# Robe color pool — picked once at spawn so each wizard reads as a distinct
# rival caster instead of all looking like the player. Avoids the player's
# blue (0.45, 0.75, 1.0) so the silhouette is still recognizably *enemy*.
const ROBE_COLORS: Array[Color] = [
	Color(0.85, 0.30, 0.30),   # crimson
	Color(0.65, 0.85, 0.30),   # acid green
	Color(0.95, 0.55, 0.10),   # ember orange
	Color(0.70, 0.40, 0.95),   # violet
	Color(0.30, 0.85, 0.70),   # teal
	Color(0.95, 0.85, 0.35),   # ochre
	Color(0.95, 0.40, 0.75),   # magenta
	Color(0.55, 0.55, 0.62),   # ash
]

# Wand the wizard fires with. Generated at spawn if null. Drops as loot on
# death. Rarity scales with floor difficulty so deep-floor wizards drop
# meaningful gear, not just commons.
var equipped_wand: Item = null

var health: int             = 18
var _player: Node2D         = null
var _shoot_timer: float     = 1.0
var _has_aggro: bool        = false
var _sight_timer: float     = 0.0
var _strafe_dir: float      = 1.0
var _strafe_switch_t: float = 0.0
var _hit_flash_t: float     = 0.0
var _telegraphing: bool     = false
var _dmg_text_cd: float     = 0.0
var _lbl: Label             = null
var _health_bar_fg: Control = null

# Status effect plumbing — mirrors EnemyShooter so player wand stacks work.
var _chill_stacks: int     = 0
var _chill_decay_t: float  = 0.0
var _frozen: bool          = false
var _frozen_timer: float   = 0.0
var _burn_stacks: int      = 0
var _enflamed: bool        = false
var _enflame_timer: float  = 0.0
var _enflame_tick: float   = 0.0
var _shock_stacks: int     = 0
var _stun_timer: float     = 0.0
var _no_attack_timer: float = 0.0
var _poison_stacks: int    = 0
var _poisoned: bool        = false
var _poison_timer: float   = 0.0
var _poison_tick: float    = 0.0

const SIGHT_RANGE          := 380.0
const SIGHT_CHECK_INTERVAL := 0.15

# ASCII silhouette mirrors the player's full wizard sprite — pointed hat,
# face, and robes — across two mouth frames for a subtle blink animation.
# The only readable distinction is the randomized non-glowing robe color
# picked from ROBE_COLORS at spawn time.
const WIZARD_F0 := "   ^\n__/_\\__\n (*-*)\n /)V(\\|\n /___\\|"
const WIZARD_F1 := "   ^\n__/_\\__\n (*3*)\n /)V(\\|\n /___\\|"

var _anim_t: float = 0.0
var _anim_frame: int = 0

static var _shared_font: Font = null

func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 2
	collision_mask  = 1
	health = max_health
	_strafe_dir = 1.0 if randf() > 0.5 else -1.0
	_strafe_switch_t = randf_range(1.5, 3.0)
	_player = get_tree().get_first_node_in_group("player")
	if equipped_wand == null:
		equipped_wand = _generate_wand_for_floor()
	# Health scales loosely with the wand's tier so legendary-wand wizards
	# don't fold instantly to the very weapon they're about to drop.
	max_health = int(round(float(max_health) * (1.0 + float(equipped_wand.rarity) * 0.4)))
	# Floor difficulty scaling — same +45% HP per +1.0 diff used elsewhere.
	max_health = int(round(float(max_health) * (1.0 + maxf(0.0, GameState.difficulty - 1.0) * 0.45)))
	health = max_health
	_health_bar_fg = get_node_or_null("HealthBar/Foreground")
	_lbl = get_node_or_null("AsciiChar")
	if _lbl:
		if _shared_font == null:
			_shared_font = MonoFont.get_font()
		_lbl.add_theme_font_override("font", _shared_font)
		_lbl.add_theme_constant_override("line_separation", -6)
		_lbl.text = WIZARD_F0
		_lbl.add_theme_color_override("font_color", _pick_robe_color())
	_update_health_bar()

func _pick_robe_color() -> Color:
	return ROBE_COLORS[randi() % ROBE_COLORS.size()]

# Picks a wand rarity weighted by floor difficulty. Mirrors the random_drop
# table the player sees: commons dominate early, legendaries appear past
# diff 2.5. Floors past diff 4 promise at least a rare.
func _generate_wand_for_floor() -> Item:
	var diff := GameState.difficulty
	var roll := randf()
	var rarity: int = Item.RARITY_COMMON
	if diff >= 4.0:
		rarity = Item.RARITY_LEGENDARY if roll < 0.30 else Item.RARITY_RARE
	elif diff >= 2.5:
		if roll < 0.15:
			rarity = Item.RARITY_LEGENDARY
		elif roll < 0.55:
			rarity = Item.RARITY_RARE
	elif diff >= 1.5:
		rarity = Item.RARITY_RARE if roll < 0.30 else Item.RARITY_COMMON
	return ItemDB.generate_wand(rarity)

func _physics_process(delta: float) -> void:
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
		_move_combat(delta)
		_tick_shoot(delta)
	else:
		velocity = Vector2.ZERO

	move_and_slide()
	_tick_visual(delta)

# ── Status (10-stack trigger) ────────────────────────────────────────────────

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
			if _frozen:
				return
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

func _trigger_enflamed() -> void:
	FloatingText.spawn_str(global_position, "ENFLAMED!", Color(1.0, 0.3, 0.0), get_tree().current_scene)
	_enflamed      = true
	_enflame_timer = 5.0
	_enflame_tick  = 0.0
	EnflameOverlay.sync_to(self, true)
	take_damage(12)

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

func _add_burn_stacks(count: int) -> void:
	_burn_stacks = mini(_burn_stacks + count, 9)

# ── Movement: kite at preferred distance ────────────────────────────────────

func _move_combat(delta: float) -> void:
	if _frozen or _stun_timer > 0.0:
		velocity = Vector2.ZERO
		return
	var slow_mult := clampf(1.0 - float(_chill_stacks) * 0.1, 0.0, 1.0)
	var to_player := _player.global_position - global_position
	var dist := to_player.length()
	var toward := to_player.normalized()
	var lateral := toward.rotated(PI * 0.5) * _strafe_dir

	_strafe_switch_t -= delta
	if _strafe_switch_t <= 0.0:
		_strafe_dir = -_strafe_dir
		_strafe_switch_t = randf_range(1.5, 3.5)

	if dist > preferred_distance + 60.0:
		velocity = (toward * 0.7 + lateral * 0.3).normalized() * move_speed * slow_mult
	elif dist < preferred_distance - 60.0:
		velocity = (-toward * 0.7 + lateral * 0.3).normalized() * move_speed * slow_mult
	else:
		velocity = lateral * move_speed * slow_mult

# ── Visual / status tint ────────────────────────────────────────────────────

func _tick_visual(delta: float) -> void:
	if _lbl == null:
		return
	FrozenBlock.sync_to(self, _frozen)
	EnflameOverlay.sync_to(self, _enflamed)
	PoisonOverlay.sync_to(self, _poisoned)
	# Mouth-blink animation while moving or shooting, mirrors Player._tick_wizard_anim.
	var is_active: bool = velocity.length_squared() > 100.0 or _telegraphing
	if is_active:
		_anim_t += delta
		if _anim_t >= 0.22:
			_anim_t = 0.0
			_anim_frame = 1 - _anim_frame
	else:
		_anim_frame = 0
		_anim_t = 0.0
	_lbl.text = WIZARD_F0 if _anim_frame == 0 else WIZARD_F1
	if _hit_flash_t > 0.0:
		_hit_flash_t -= delta
		_lbl.modulate = Color(1.0, 0.3, 0.3)
	elif _telegraphing:
		var blink := sin(Time.get_ticks_msec() * 0.013) * 0.5 + 0.5
		_lbl.modulate = Color(1.0, lerpf(0.8, 0.1, blink), lerpf(0.7, 0.0, blink))
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
	return Color.WHITE

# ── Sight ───────────────────────────────────────────────────────────────────

func _check_sight() -> void:
	if global_position.distance_squared_to(_player.global_position) > SIGHT_RANGE * SIGHT_RANGE:
		return
	var space  := get_world_2d().direct_space_state
	var params := PhysicsRayQueryParameters2D.create(global_position, _player.global_position)
	params.exclude = [get_rid()]
	params.collision_mask = 1   # walls + player only — packed enemies don't block sight
	var hit := space.intersect_ray(params)
	if hit.is_empty() or hit.get("collider") == _player:
		_has_aggro = true
		FloatingText.spawn_str(global_position, "!", Color(1.0, 0.9, 0.0), get_tree().current_scene)

# ── Wand-driven shooting ────────────────────────────────────────────────────

func _tick_shoot(delta: float) -> void:
	_shoot_timer -= delta
	var interval := _effective_fire_interval()
	if _shoot_timer <= 0.3 and not _telegraphing and _stun_timer <= 0.0 and _no_attack_timer <= 0.0:
		_telegraphing = true
	if _stun_timer > 0.0 or _no_attack_timer > 0.0:
		_telegraphing = false
	if _shoot_timer <= 0.0 and _stun_timer <= 0.0 and _no_attack_timer <= 0.0:
		_telegraphing = false
		_fire_wand()
		_shoot_timer = interval

# Wizards can't be too oppressive — clamp the wand's true rate so legendary
# fire-rate-monster wands don't melt the player on contact. Floor 0.35s.
func _effective_fire_interval() -> float:
	if equipped_wand == null:
		return 1.0
	return maxf(0.35, equipped_wand.wand_fire_rate * 1.6)

func _fire_wand() -> void:
	if equipped_wand == null:
		return
	var aim_dir := (_player.global_position - global_position).normalized()
	# Backwards flaw: enemy wand intentionally fires opposite. Funny tell.
	if "backwards" in equipped_wand.wand_flaws:
		aim_dir = -aim_dir
	if "sloppy" in equipped_wand.wand_flaws:
		aim_dir = aim_dir.rotated(deg_to_rad(randf_range(-13.0, 13.0)))
	if "erratic" in equipped_wand.wand_flaws:
		aim_dir = aim_dir.rotated(randf_range(-0.7, 0.7))

	if equipped_wand.wand_shoot_type == "shotgun":
		var spread_total := deg_to_rad(48.0)
		for i in 5:
			var ang := -spread_total * 0.5 + spread_total * (float(i) / 4.0)
			_spawn_proj(aim_dir.rotated(ang), "shotgun")
		return
	_spawn_proj(aim_dir, equipped_wand.wand_shoot_type)

func _spawn_proj(dir: Vector2, shoot_type: String) -> void:
	var p := PROJ_SCENE.instantiate()
	p.global_position = global_position
	p.direction = dir
	p.set("source", "enemy")
	p.set("shoot_type", shoot_type)
	p.set("damage", maxi(1, equipped_wand.wand_damage))
	p.set("pierce_remaining", equipped_wand.wand_pierce)
	p.set("ricochet_remaining", equipped_wand.wand_ricochet)
	p.set("apply_freeze", shoot_type == "freeze")
	p.set("apply_burn",   shoot_type == "fire")
	p.set("apply_shock",  shoot_type == "shock")
	p.set("status_stacks", maxi(1, equipped_wand.wand_status_stacks))
	var spd := equipped_wand.wand_proj_speed
	if "slow_shots" in equipped_wand.wand_flaws:
		spd *= 0.5
	p.set("speed", spd)
	get_tree().current_scene.add_child(p)

# ── Damage / death ──────────────────────────────────────────────────────────

func take_damage(amount: int) -> void:
	if not _has_aggro:
		_has_aggro = true
		FloatingText.spawn_str(global_position, "!", Color(1.0, 0.9, 0.0), get_tree().current_scene)
	var actual := int(float(amount) * 1.25) if (_frozen or _chill_stacks > 0) else amount
	health -= actual
	_hit_flash_t = 0.14
	if _dmg_text_cd <= 0.0:
		FloatingText.spawn(global_position, actual, false, get_tree().current_scene)
		_dmg_text_cd = 0.22
	_update_health_bar()
	if health <= 0:
		GameState.kills += 1
		GameState.add_xp(12)   # rival wizard worth more than a basic enemy
		_drop_loot()
		EffectFx.spawn_death_pop(global_position, get_tree().current_scene)
		queue_free()

func heal(amount: int) -> void:
	var prev := health
	health = mini(health + amount, max_health)
	var gained := health - prev
	if gained > 0:
		FloatingText.spawn(global_position, gained, true, get_tree().current_scene)
	_update_health_bar()

func _drop_loot() -> void:
	# Drop the equipped wand inside a regular loot bag at the corpse so the
	# player can stroll over and loot it through the existing UI.
	if equipped_wand != null:
		var bag := LOOT_BAG_SCENE.instantiate()
		bag.global_position = global_position
		bag.items = [equipped_wand]
		get_tree().current_scene.call_deferred("add_child", bag)
	# Plus a small gold drop so the kill always pays something even if the
	# wand bag's already been claimed mid-fight.
	var gold := GOLD_PICKUP_SCENE.instantiate()
	gold.global_position = global_position + Vector2(randf_range(-12.0, 12.0), randf_range(-12.0, 12.0))
	gold.value = randi_range(8, 16)
	get_tree().current_scene.call_deferred("add_child", gold)

func _update_health_bar() -> void:
	if _health_bar_fg == null:
		return
	var ratio := clampf(float(health) / float(max_health), 0.0, 1.0)
	_health_bar_fg.offset_right = -20.0 + 40.0 * ratio
