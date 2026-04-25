extends EnemyBase

# Tiny, fast, fragile chaser. Spawned in groups, passes through other enemies,
# damages the player on contact.

const F0 := " \\|/ \n-(*)-\n /|\\ "
const F1 := " /|\\ \n=(o)=\n \\|/ "

const MOVE_SPEED       := 310.0
const CONTACT_DAMAGE   := 1
const CONTACT_RADIUS   := 22.0
const CONTACT_COOLDOWN := 0.55
const SIGHT            := 560.0

var _contact_cd: float = 0.0
var _anim_t: float     = 0.0
var _anim_f: int       = 0

func _on_ready_extra() -> void:
	max_health  = 2
	health      = 2
	_sight_range = SIGHT
	if _lbl:
		_lbl.text = F0
		_lbl.add_theme_font_size_override("font_size", 13)
		_lbl.add_theme_constant_override("line_separation", -3)

func _enemy_tick(delta: float) -> void:
	if _frozen or _stun_timer > 0.0:
		velocity = Vector2.ZERO
		return
	if _contact_cd > 0.0:
		_contact_cd -= delta

	var slow_mult := clampf(1.0 - float(_chill_stacks) * 0.1, 0.0, 1.0)
	var to_p     := _player.global_position - global_position
	var move_vel := to_p.normalized() * MOVE_SPEED * _speed_multiplier * slow_mult

	# Manual movement — pass through enemies, but still respect walls
	_move_through(delta, move_vel)
	# Zero velocity so the base class's move_and_slide is a no-op
	velocity = Vector2.ZERO

	# Contact damage on overlap
	if to_p.length() <= CONTACT_RADIUS and _contact_cd <= 0.0:
		if _player.has_method("take_damage"):
			_player.take_damage(CONTACT_DAMAGE)
			_contact_cd = CONTACT_COOLDOWN

func _move_through(delta: float, vel: Vector2) -> void:
	var motion := vel * delta
	if motion.length_squared() < 0.0001:
		return
	var dir := vel.normalized()
	var space := get_world_2d().direct_space_state
	var excluded: Array[RID] = [get_rid()]
	var end_pos := global_position + motion + dir * 5.0
	# Iterate raycasts, skipping past non-wall colliders (other enemies, player)
	for _i in 5:
		var query := PhysicsRayQueryParameters2D.create(global_position, end_pos)
		query.exclude = excluded
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			global_position += motion
			return
		var c = hit.get("collider")
		if c is StaticBody2D:
			# Wall — stop just short
			var hit_pos: Vector2 = hit.get("position")
			global_position = hit_pos - dir * 8.0
			return
		if c is CollisionObject2D:
			excluded.append((c as CollisionObject2D).get_rid())
	# Fell through all iterations without hitting a wall — just move
	global_position += motion

func _enemy_anim_update(delta: float) -> void:
	_anim_t += delta
	if _anim_t >= 0.12:
		_anim_t = 0.0
		_anim_f = 1 - _anim_f
	var t := F0 if _anim_f == 0 else F1
	if _lbl.text != t:
		_lbl.text = t
