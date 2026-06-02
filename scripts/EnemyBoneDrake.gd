extends EnemyBase

# Bone Drake — Catacombs-only. Fast melee with a 2-hit chain attack:
# lunges in, swings twice with a brief pause between, then retreats.
# Pairs with the catacombs reanimation mechanic — a corpse pile of
# bone drakes feels appropriately dread.

const F0 := " /^\\ \n(O O)\n /v\\ "
const F1 := " /v\\ \n(O O)\n /^\\ "

const APPROACH_SPEED   := 130.0
const RETREAT_SPEED    := 95.0
const HITBOX_REACH     := 30.0
const ATTACK_PERIOD    := 2.5
const COMBO_GAP        := 0.25
const ATTACK_DURATION  := 0.18
const COMBO_HITS       := 2
const HIT_DAMAGE       := 3

enum State { CHASE, COMBO, RETREAT }
var _state: int       = State.CHASE
var _state_t: float   = 0.0
var _attack_cd: float = 1.0
var _combo_left: int  = 0
var _hitbox: Area2D   = null
var _anim_t: float    = 0.0
var _anim_f: int      = 0

func _on_ready_extra() -> void:
	max_health = 22   # doubled from 11
	health = max_health
	_sight_range = 580.0
	if _lbl:
		_lbl.text = F0
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

func _enemy_tick(delta: float) -> void:
	if _frozen or _stun_timer > 0.0:
		velocity = Vector2.ZERO
		return
	if not _has_aggro:
		velocity = Vector2.ZERO
		return
	var to_p: Vector2 = _player.global_position - global_position
	var dist := to_p.length()
	var slow_mult := clampf(1.0 - float(_chill_stacks) * 0.1, 0.0, 1.0)
	match _state:
		State.CHASE:
			velocity = to_p.normalized() * APPROACH_SPEED * _speed_multiplier * slow_mult
			_attack_cd -= delta
			if _attack_cd <= 0.0 and dist <= HITBOX_REACH * 1.5 and _no_attack_timer <= 0.0:
				_state = State.COMBO
				_combo_left = COMBO_HITS
				_state_t = 0.0
		State.COMBO:
			velocity = to_p.normalized() * 30.0   # gentle drift in
			_state_t -= delta
			if _state_t <= 0.0 and _combo_left > 0:
				_combo_left -= 1
				_swing(to_p.normalized())
				_state_t = COMBO_GAP
			if _combo_left <= 0 and _state_t <= 0.0:
				_state = State.RETREAT
				_state_t = 0.7
		State.RETREAT:
			velocity = -to_p.normalized() * RETREAT_SPEED * _speed_multiplier * slow_mult
			_state_t -= delta
			if _state_t <= 0.0:
				_state = State.CHASE
				_attack_cd = ATTACK_PERIOD

func _swing(dir: Vector2) -> void:
	_hitbox.position = dir * HITBOX_REACH
	_hitbox.set_deferred("monitoring", true)
	get_tree().create_timer(ATTACK_DURATION).timeout.connect(_end_attack)

func _end_attack() -> void:
	_hitbox.set_deferred("monitoring", false)

func _on_melee_hit(body: Node2D) -> void:
	if not _should_melee_hit(body):
		return
	body.take_damage(HIT_DAMAGE, self)

func _enemy_anim_update(delta: float) -> void:
	_anim_t += delta
	if _anim_t >= 0.30:
		_anim_t = 0.0
		_anim_f = 1 - _anim_f
		if _lbl:
			_lbl.text = F0 if _anim_f == 0 else F1
