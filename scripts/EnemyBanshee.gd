extends EnemyBase

# Banshee — stationary caster that emits a 2 s telegraphed AoE pulse on
# a fixed cycle. Forces the player into engage-then-retreat windows:
# stand inside the pulse and you eat damage; back off too far and you
# stop hitting the banshee. Pairs naturally with the catacombs theme.

const F0 := " ~~~ \n(>_<)\n VVV "
const F1 := " === \n(O_O)\n vVv "

const PULSE_RADIUS    := 130.0
const PULSE_DAMAGE    := 6
const TELEGRAPH_TIME  := 1.4
const PULSE_INTERVAL  := 4.0   # time from one telegraph start to the next

enum BState { IDLE, TELEGRAPH, PULSE_END }
var _bstate: int        = BState.IDLE
var _bstate_t: float    = 0.0
var _cycle_t: float     = 1.5
var _ring: Line2D       = null
var _anim_t: float      = 0.0
var _anim_f: int        = 0

func _on_ready_extra() -> void:
	max_health = 28   # doubled from 14
	health = max_health
	_sight_range = 460.0
	if _lbl:
		_lbl.text = F0
	# Telegraph ring lives as a child so it pulses with the banshee.
	_ring = Line2D.new()
	_ring.width = 2.5
	_ring.default_color = Color(0.65, 0.30, 1.0, 0.0)
	for i in 32 + 1:
		var a := (TAU / 32.0) * float(i)
		_ring.add_point(Vector2(cos(a), sin(a)) * PULSE_RADIUS)
	_ring.z_index = -1
	add_child(_ring)

func _enemy_tick(delta: float) -> void:
	velocity = Vector2.ZERO   # rooted
	if not _has_aggro:
		return
	match _bstate:
		BState.IDLE:
			_cycle_t -= delta
			if _cycle_t <= 0.0 and _stun_timer <= 0.0 and _no_attack_timer <= 0.0:
				_bstate = BState.TELEGRAPH
				_bstate_t = TELEGRAPH_TIME
				# Telegraph onset audio — rising "charge" sound so players
				# instinctively look for the ring before the pulse lands.
				# Pitches up over the 1.4s telegraph window via _bstate_t.
				if SoundManager:
					SoundManager.play("beam_charge", 0.75)
		BState.TELEGRAPH:
			_bstate_t -= delta
			# Ring brightens + slightly grows as the pulse approaches so
			# the player has a clear "GTFO" cue. Reduce-flashing damps the
			# colour swing (purple→red) and caps the alpha so the ring
			# still expands but doesn't strobe.
			var t: float = clampf(1.0 - (_bstate_t / TELEGRAPH_TIME), 0.0, 1.0)
			if GameState.disable_flashing:
				_ring.default_color = Color(0.85, 0.40, 0.85,
					lerpf(0.25, 0.55, t))
			else:
				_ring.default_color = Color(1.0, lerpf(0.30, 0.10, t), lerpf(1.0, 0.30, t),
					lerpf(0.30, 0.95, t))
			_ring.scale = Vector2.ONE * (1.0 + 0.06 * t)
			if _bstate_t <= 0.0:
				_emit_pulse()
				_bstate = BState.PULSE_END
				_bstate_t = 0.25
		BState.PULSE_END:
			_bstate_t -= delta
			# Quick fade after the pulse, then back to idle. Reduce-flashing
			# uses a lower-contrast tint so the pulse doesn't punch the eye.
			var t2: float = clampf(_bstate_t / 0.25, 0.0, 1.0)
			if GameState.disable_flashing:
				_ring.default_color = Color(0.85, 0.55, 0.85, t2 * 0.45)
			else:
				_ring.default_color = Color(1.0, 0.95, 0.95, t2 * 0.7)
			if _bstate_t <= 0.0:
				_ring.default_color = Color(0.65, 0.30, 1.0, 0.0)
				_ring.scale = Vector2.ONE
				_bstate = BState.IDLE
				_cycle_t = PULSE_INTERVAL - TELEGRAPH_TIME

func _emit_pulse() -> void:
	if is_instance_valid(_player):
		var d: float = global_position.distance_to(_player.global_position)
		if d <= PULSE_RADIUS and _player.has_method("take_damage"):
			_player.call("take_damage", PULSE_DAMAGE)
	if SoundManager:
		SoundManager.play("explosion", randf_range(1.10, 1.25))

func _enemy_anim_update(delta: float) -> void:
	if _sprite != null:
		return   # driver owns the label (ghost sprite)
	_anim_t += delta
	if _anim_t >= 0.35:
		_anim_t = 0.0
		_anim_f = 1 - _anim_f
		if _lbl:
			_lbl.text = F0 if _anim_f == 0 else F1
