extends EnemyBase

# Berserker — gets faster and hits harder as HP drops. Speed scales
# from 1.0× at full HP to 1.8× at 0 HP; melee damage scales similarly.
# Punishes the "leave it for last" tendency: a low-HP berserker is more
# dangerous than a fresh one. Rewards burst-kill builds.

const F0 := "  ;  \n(>X<)\n /|\\ "
const F1 := "  ;  \n(>x<)\n /|\\ "

const BASE_SPEED      := 95.0
const BASE_DAMAGE     := 2
const HITBOX_REACH    := 28.0
const ATTACK_INTERVAL := 1.0
const ATTACK_DURATION := 0.20

var _attack_t: float = 0.6
var _hitbox: Area2D  = null
var _anim_t: float   = 0.0
var _anim_f: int     = 0

func _on_ready_extra() -> void:
	max_health = 28   # doubled from 14
	health = max_health
	_sight_range = 540.0
	if _lbl:
		_lbl.text = F0
	# Build melee hitbox in code so the .tscn stays minimal.
	_hitbox = Area2D.new()
	_hitbox.name = "MeleeHitbox"
	_hitbox.monitoring = false
	_hitbox.monitorable = false
	_hitbox.collision_mask = 3   # player (1) + enemy (2) for bewitched targeting
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 18.0
	cs.shape = shape
	_hitbox.add_child(cs)
	add_child(_hitbox)
	_hitbox.body_entered.connect(_on_melee_hit)

func _hp_ratio() -> float:
	return clampf(float(health) / float(maxi(1, max_health)), 0.0, 1.0)

# 1.0 at full HP → 1.8 at 0 HP. Used as a multiplier on speed and damage.
func _rage_mult() -> float:
	return 1.0 + (1.0 - _hp_ratio()) * 0.8

func _enemy_tick(delta: float) -> void:
	if _frozen or _stun_timer > 0.0:
		velocity = Vector2.ZERO
		return
	if not _has_aggro:
		velocity = Vector2.ZERO
		return
	var slow_mult := clampf(1.0 - float(_chill_stacks) * 0.1, 0.0, 1.0)
	var to_p: Vector2 = _player.global_position - global_position
	velocity = to_p.normalized() * BASE_SPEED * _speed_multiplier * _rage_mult() * slow_mult

	_attack_t -= delta
	if _attack_t <= 0.0 and _no_attack_timer <= 0.0:
		var dist := to_p.length()
		if dist <= HITBOX_REACH * 1.5:
			_attack_t = ATTACK_INTERVAL
			_launch_attack(to_p.normalized())

func _launch_attack(dir: Vector2) -> void:
	_hitbox.position = dir * HITBOX_REACH
	_hitbox.set_deferred("monitoring", true)
	get_tree().create_timer(ATTACK_DURATION).timeout.connect(_end_attack)

func _end_attack() -> void:
	_hitbox.set_deferred("monitoring", false)

func _on_melee_hit(body: Node2D) -> void:
	if not _should_melee_hit(body):
		return
	body.take_damage(int(round(float(BASE_DAMAGE) * _rage_mult())), self)

func _enemy_anim_update(delta: float) -> void:
	if _sprite != null:
		return   # driver owns the label (brute sprite)
	_anim_t += delta
	# Animation pace also scales with rage so the visual reads "more
	# frenzied" as HP drops.
	var period: float = 0.42 / _rage_mult()
	if _anim_t >= period:
		_anim_t = 0.0
		_anim_f = 1 - _anim_f
		if _lbl:
			_lbl.text = F0 if _anim_f == 0 else F1
	if _lbl and _hp_ratio() < 0.5:
		# Red tint deepens as HP drops, signaling the rage state visually.
		var rage := 1.0 - _hp_ratio()
		_lbl.modulate = Color(1.0, lerpf(1.0, 0.25, rage), lerpf(1.0, 0.20, rage))
