extends EnemyBase

# Bomber — kamikaze rusher. Sprints toward the player and detonates in
# a small radius on contact (or after a fuse if it can't reach in time).
# Can't be tanked, can't be ignored. Best handled by burst killing
# before it closes the gap, or kiting until its fuse expires.

const F0 := " . . \n(*X*)\n /|\\ "
const F1 := "  .  \n(*x*)\n /|\\ "

const MOVE_SPEED       := 145.0
const EXPLODE_RADIUS   := 70.0
const EXPLODE_DAMAGE   := 8
const FUSE_TIME        := 8.0       # if it can't reach the player in this long, just blow up
const CONTACT_DISTANCE := 36.0      # detonate when within this range
const TELEGRAPH_TIME   := 0.55      # final flash + sound before the boom

var _fuse_t: float    = FUSE_TIME
var _arming: bool     = false       # true during the final telegraph flash
var _arm_t: float     = 0.0
var _anim_t: float    = 0.0
var _anim_f: int      = 0

func _on_ready_extra() -> void:
	max_health = 12   # doubled from 6
	health = max_health
	_sight_range = 540.0
	if _lbl:
		_lbl.text = F0

func _enemy_tick(delta: float) -> void:
	if _frozen or _stun_timer > 0.0:
		velocity = Vector2.ZERO
		return
	if not _has_aggro:
		velocity = Vector2.ZERO
		return
	_fuse_t -= delta
	# Run straight at the player. No fancy strafing — bombers commit.
	var to_p: Vector2 = _player.global_position - global_position
	var dist := to_p.length()
	var slow_mult := clampf(1.0 - float(_chill_stacks) * 0.1, 0.0, 1.0)
	velocity = to_p.normalized() * MOVE_SPEED * _speed_multiplier * slow_mult
	# Trigger the arming flash when contact range is reached or the fuse
	# burns out — both paths funnel into _detonate after TELEGRAPH_TIME.
	if not _arming and (dist <= CONTACT_DISTANCE or _fuse_t <= 0.0):
		_arming = true
		_arm_t = TELEGRAPH_TIME
		velocity = Vector2.ZERO
		FloatingText.spawn_str(global_position, "BOOM!",
			Color(1.0, 0.4, 0.1), get_tree().current_scene)
	if _arming:
		velocity = Vector2.ZERO
		_arm_t -= delta
		if _arm_t <= 0.0:
			_detonate()

func _enemy_anim_update(delta: float) -> void:
	_anim_t += delta
	# Pulse faster while arming so the player can read "imminent" without
	# needing a UI tag.
	var period: float = 0.18 if _arming else 0.34
	if _anim_t >= period:
		_anim_t = 0.0
		_anim_f = 1 - _anim_f
		if _lbl and _sprite == null:
			_lbl.text = F0 if _anim_f == 0 else F1
	if _arming and _lbl:
		# Bright red pulse while telegraphing so it pops over the
		# normal hit-flash modulate.
		_lbl.modulate = Color(1.0, 0.3 + 0.5 * sin(Time.get_ticks_msec() * 0.04), 0.1)

func _detonate() -> void:
	# Damage the player if in radius, plus splash-damage other enemies
	# (friendly fire — bombers don't care). Linear falloff: full damage
	# at the centre tapering to 35% at the edge so kiting / partial
	# disengage actually reduces the hit instead of the previous
	# binary "in range = full damage" punishment.
	var tree := get_tree()
	if tree == null:
		queue_free()
		return
	if is_instance_valid(_player):
		var d: float = global_position.distance_to(_player.global_position)
		if d <= EXPLODE_RADIUS and _player.has_method("take_damage"):
			var falloff: float = lerpf(1.0, 0.35,
				clampf(d / EXPLODE_RADIUS, 0.0, 1.0))
			var dealt: int = max(1, int(round(float(EXPLODE_DAMAGE) * falloff)))
			_player.call("take_damage", dealt)
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or e == self:
			continue
		var ne := e as Node2D
		var ed: float = ne.global_position.distance_to(global_position)
		if ed <= EXPLODE_RADIUS:
			if ne.has_method("take_damage"):
				var efalloff: float = lerpf(1.0, 0.35,
					clampf(ed / EXPLODE_RADIUS, 0.0, 1.0))
				ne.take_damage(max(1, int(round(float(EXPLODE_DAMAGE) * 0.5 * efalloff))))
	# Visual shockwave ring.
	var ring := Line2D.new()
	ring.width = 4.0
	ring.default_color = Color(1.0, 0.45, 0.05, 0.95)
	for i in 24 + 1:
		var a := (TAU / 24.0) * float(i)
		ring.add_point(Vector2(cos(a), sin(a)) * EXPLODE_RADIUS * 0.5)
	var holder := Node2D.new()
	holder.global_position = global_position
	holder.add_child(ring)
	tree.current_scene.add_child(holder)
	var tw := holder.create_tween()
	tw.tween_property(holder, "scale", Vector2(2.0, 2.0), 0.30)
	tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.30)
	tw.tween_callback(holder.queue_free)
	if SoundManager:
		SoundManager.play("explosion", randf_range(0.95, 1.10))
	# Award credit so the kill counts.
	GameState.kills += 1
	queue_free()
