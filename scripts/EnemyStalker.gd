extends EnemyBase

# Stalker — only attacks when the player has direct LOS on it. Idles
# in a room corner; once the player rounds the doorway and sees it,
# the stalker rushes for one melee bite, then dives to the nearest
# wall corner to hide. Camping a doorway is dangerous because once
# the stalker sees you it's already committed to the strike.

const F_HIDDEN := " ... "
const F_SEEN_0 := " /^\\ \n[. .]\n /-\\ "
const F_SEEN_1 := " \\^/ \n[o o]\n /-\\ "

const APPROACH_SPEED := 220.0
const RETREAT_SPEED  := 160.0
const HITBOX_REACH   := 30.0
const ATTACK_INTERVAL := 0.18
const ATTACK_DURATION := 0.16
const HIT_DAMAGE      := 4
const RETREAT_TIME    := 1.6
const COMMIT_LOS_GAP  := 0.40   # stays committed even if LOS breaks for this many seconds
# Pre-commit "I see you" beat — stalker stands up and tints red but stays
# rooted briefly so the player has a window to dodge before the bite rush.
# Without this it commits + bites in the same eyeblink the player rounds
# the doorway, which read as instakill cheap rather than tense.
const SPOT_TIME       := 0.40

enum State { HIDDEN, SPOTTED, COMMITTED, RETREAT }
var _state: int        = State.HIDDEN
var _state_t: float    = 0.0
var _los_lost_t: float = 0.0
var _last_seen_pos: Vector2 = Vector2.ZERO
var _hitbox: Area2D    = null
var _anim_t: float     = 0.0
var _anim_f: int       = 0
var _struck: bool      = false   # true once the bite has landed this commit

func _on_ready_extra() -> void:
	max_health = 14
	health = 14
	_sight_range = 720.0   # very long detect — stalker reads the room
	if _lbl:
		_lbl.text = F_HIDDEN
		# Start nearly invisible so the player has to actually scan to
		# spot one. Bumps to full alpha when committed.
		_lbl.modulate = Color(0.85, 0.85, 0.95, 0.20)
	_hitbox = Area2D.new()
	_hitbox.name = "MeleeHitbox"
	_hitbox.monitoring = false
	_hitbox.monitorable = false
	_hitbox.collision_mask = 1
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 18.0
	cs.shape = shape
	_hitbox.add_child(cs)
	add_child(_hitbox)
	_hitbox.body_entered.connect(_on_melee_hit)

# Override sight: stalker checks BOTH directions — it sees the player
# (to engage) AND the player needs to see it (to commit it). When the
# player can see the stalker, it commits and rushes.
func _check_sight() -> void:
	if not is_instance_valid(_player):
		return
	if global_position.distance_squared_to(_player.global_position) > _sight_range * _sight_range:
		return
	var space := get_world_2d().direct_space_state
	var params := PhysicsRayQueryParameters2D.create(global_position, _player.global_position)
	params.exclude = [get_rid()]
	params.collision_mask = 1
	var hit := space.intersect_ray(params)
	# LOS is "the ray hits the player or nothing" — a wall in between
	# means the stalker stays hidden. Same standard as the player's
	# autoplay LOS check.
	# Explicit bool — `hit.get("collider")` returns Variant so the parser
	# can't infer the type of the OR expression on its own.
	var has_los: bool = hit.is_empty() or hit.get("collider") == _player
	if has_los and _state == State.HIDDEN:
		_spot()

func _enemy_tick(delta: float) -> void:
	if _frozen or _stun_timer > 0.0:
		velocity = Vector2.ZERO
		return
	# Refresh LOS each frame so the commit window adapts to the player.
	var has_los := _has_los_to_player()
	if has_los and is_instance_valid(_player):
		_last_seen_pos = _player.global_position
		_los_lost_t = 0.0
	else:
		_los_lost_t += delta

	match _state:
		State.HIDDEN:
			velocity = Vector2.ZERO
			# Sight check (every SIGHT_CHECK_INTERVAL) handles the spot
		State.SPOTTED:
			# Brief stand-up beat. Stalker is rooted, tinted red, and the
			# "SEEN!" floater is up — the player's window to dodge before
			# the rush. Still visible during this so the threat is read.
			velocity = Vector2.ZERO
			_state_t -= delta
			if _state_t <= 0.0:
				_commit()
		State.COMMITTED:
			# Charge the player's last-seen position. If LOS comes back
			# we update; if it stays broken too long, give up and retreat.
			var to_t: Vector2 = _last_seen_pos - global_position
			velocity = to_t.normalized() * APPROACH_SPEED
			# Bite when in melee range
			_state_t -= delta
			if _state_t <= 0.0 and not _struck \
					and is_instance_valid(_player) \
					and global_position.distance_to(_player.global_position) <= HITBOX_REACH * 1.4:
				_state_t = ATTACK_INTERVAL
				_struck = true
				var dir: Vector2 = (_player.global_position - global_position).normalized()
				_swing(dir)
			# Lost the player too long? Retreat.
			if _los_lost_t > COMMIT_LOS_GAP and _struck:
				_enter_retreat()
			# Or — bite landed and we're past the swing — retreat anyway.
			if _struck and _state_t <= -0.20:
				_enter_retreat()
		State.RETREAT:
			# Run away from the player toward the nearest wall direction
			# (cheap heuristic: just flee in opposite direction).
			if is_instance_valid(_player):
				var away := (global_position - _player.global_position).normalized()
				velocity = away * RETREAT_SPEED
			_state_t -= delta
			if _state_t <= 0.0:
				_state = State.HIDDEN
				_struck = false
				if _lbl:
					_lbl.text = F_HIDDEN
					_lbl.modulate = Color(0.85, 0.85, 0.95, 0.20)

func _has_los_to_player() -> bool:
	if not is_instance_valid(_player):
		return false
	var space := get_world_2d().direct_space_state
	var params := PhysicsRayQueryParameters2D.create(global_position, _player.global_position)
	params.exclude = [get_rid()]
	params.collision_mask = 1
	var hit := space.intersect_ray(params)
	return hit.is_empty() or hit.get("collider") == _player

# First reveal — the player crossed LOS and the stalker is now visible
# but rooted in place for SPOT_TIME before charging. Plays the "SEEN!"
# pop here (not in _commit) so it lines up with when the threat
# actually appears on screen.
func _spot() -> void:
	_state = State.SPOTTED
	_state_t = SPOT_TIME
	_struck = false
	_has_aggro = true
	if _lbl:
		# Swap to the seen glyph immediately so the player isn't reading the
		# red-tinted "..." for the first anim frame. The standard anim swap
		# takes over on the next tick.
		_lbl.text = F_SEEN_0
		# Bright red tint so the stalker pops out of the dim wall background.
		_lbl.modulate = Color(1.0, 0.55, 0.55, 1.0)
	FloatingText.spawn_str(global_position, "SEEN!",
		Color(1.0, 0.9, 0.30), get_tree().current_scene)
	# Audio cue — low whoosh sells the "stalker stands up" beat. Without
	# this the SPOT_TIME window has no sound and players miss the warning.
	if SoundManager:
		SoundManager.play("whoosh", randf_range(0.65, 0.80))

func _commit() -> void:
	_state = State.COMMITTED
	_state_t = 0.0
	_struck = false
	_has_aggro = true
	if _lbl:
		_lbl.modulate = Color(1.0, 0.95, 0.95, 1.0)

func _enter_retreat() -> void:
	_state = State.RETREAT
	_state_t = RETREAT_TIME

func _swing(dir: Vector2) -> void:
	_hitbox.position = dir * HITBOX_REACH
	_hitbox.set_deferred("monitoring", true)
	get_tree().create_timer(ATTACK_DURATION).timeout.connect(_end_attack)

func _end_attack() -> void:
	_hitbox.set_deferred("monitoring", false)

func _on_melee_hit(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(HIT_DAMAGE)

func _enemy_anim_update(delta: float) -> void:
	if _state == State.HIDDEN:
		return   # static glyph while idle
	_anim_t += delta
	if _anim_t >= 0.18:
		_anim_t = 0.0
		_anim_f = 1 - _anim_f
		if _lbl:
			_lbl.text = F_SEEN_0 if _anim_f == 0 else F_SEEN_1
