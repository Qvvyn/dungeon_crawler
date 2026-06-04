extends EnemyBase

# Phantom — invisible while idle, fades in for ~0.45 s when firing,
# then back out. Forces the player to predict shots from the muzzle
# flash window rather than tracking a visible target. Beam / nova /
# AoE builds eat phantoms; pure single-target builds struggle.

const PROJ_SCENE := preload("res://scenes/Projectile.tscn")

const F0 := " ~  \n(o o)\n  ~ "
# Idle alpha bumped 0.10 → 0.15 so close-range phantoms aren't invisible
# against dark biome backgrounds. They still fade away beyond a screen
# length but the player can spot the silhouette from a couple tiles out.
const FADE_OUT_ALPHA := 0.15
const VISIBLE_TIME   := 0.45
const SHOOT_INTERVAL := 1.6
const PROJ_SPEED     := 380.0
const PROJ_DAMAGE    := 2

var _shoot_t: float    = randf_range(0.5, 1.5)
var _visible_t: float  = 0.0
var _drift_dir: Vector2 = Vector2.ZERO
var _drift_t: float    = 0.0

func _on_ready_extra() -> void:
	max_health = 14   # doubled from 7
	health = max_health
	_sight_range = 600.0
	if _lbl:
		_lbl.text = F0
		# Faint cyan outline so the phantom's silhouette reads even at low
		# alpha. Without this the body just dissolves into dark biome
		# backgrounds and players reported "what hit me" deaths.
		_lbl.add_theme_color_override("font_outline_color",
			Color(0.30, 0.55, 0.85, 0.55))
		_lbl.add_theme_constant_override("outline_size", 2)
	# Start nearly invisible; visible only during shooting window.
	if _lbl:
		_lbl.modulate = Color(1.0, 1.0, 1.0, FADE_OUT_ALPHA)

func _enemy_tick(delta: float) -> void:
	if _frozen or _stun_timer > 0.0:
		velocity = Vector2.ZERO
		return
	if not _has_aggro:
		velocity = Vector2.ZERO
		return
	# Slow strafe — phantom wants to be hard to predict, not hard to reach.
	_drift_t -= delta
	if _drift_t <= 0.0:
		_drift_t = randf_range(1.2, 2.0)
		var to_p := (_player.global_position - global_position).normalized()
		var sign_choice: float = 1.0 if randf() > 0.5 else -1.0
		_drift_dir = to_p.rotated(PI * 0.5) * sign_choice
	velocity = _drift_dir * 60.0 * _speed_multiplier
	# Shooting cycle.
	_shoot_t -= delta
	if _shoot_t <= 0.0 and _no_attack_timer <= 0.0:
		_shoot_t = SHOOT_INTERVAL + randf_range(-0.3, 0.3)
		_fire_shot()
	if _visible_t > 0.0:
		_visible_t -= delta

func _fire_shot() -> void:
	if not is_instance_valid(_player):
		return
	# Re-check LOS so a raised door / moving wall blocks the shot.
	if not EnemyVision.has_los(self, _player.global_position):
		return
	_visible_t = VISIBLE_TIME   # the firing window the player sees
	var dir := (_player.global_position - global_position).normalized()
	var p := PROJ_SCENE.instantiate()
	p.global_position = global_position
	p.set("direction", dir)
	p.set("source", "enemy")
	p.set("damage", PROJ_DAMAGE)
	p.set("speed", PROJ_SPEED)
	p.set("shoot_type", "regular")
	get_tree().current_scene.add_child(p)

func _enemy_anim_update(_delta: float) -> void:
	if _lbl == null:
		return
	# Smoothly tween the alpha based on visible_t so the phantom flashes
	# in on each shot. Hit flashes still show — they're applied on top
	# via the base EnemyBase modulate dance.
	var t: float = clampf(_visible_t / VISIBLE_TIME, 0.0, 1.0)
	var alpha: float = lerpf(FADE_OUT_ALPHA, 0.92, t)
	# Don't override hit flash from base.
	if _hit_flash_t <= 0.0:
		_lbl.modulate = Color(0.85, 0.95, 1.0, alpha)
