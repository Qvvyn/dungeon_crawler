extends EnemyBase

const F0 := "  *  \n[ ◉ ]\n  *  "
const F1 := " *.* \n[ ◉ ]\n .*. "

const PULSE_INTERVAL  := 0.28
const SHOTS_PER_PULSE := 4
const ROTATE_PER_PULSE := 0.55   # radians added each pulse — creates spiral
const PROJ_SPEED      := 175.0
const PROJ_DAMAGE     := 1
const PROJ_LIFETIME   := 2.6

var _pulse_t: float    = 0.4
var _spiral: float     = 0.0
var _anim_t: float     = 0.0
var _anim_f: int       = 0

var _proj_scene: PackedScene = null

func _on_ready_extra() -> void:
	max_health = 8
	health = 8
	_sight_range = 500.0
	_proj_scene = load("res://scenes/Projectile.tscn")
	if _lbl:
		_lbl.text = F0

func _enemy_tick(delta: float) -> void:
	# Stationary; only sway slightly
	velocity = Vector2.ZERO
	if not _has_aggro: return
	if _stun_timer > 0.0 or _no_attack_timer > 0.0: return

	_pulse_t -= delta
	if _pulse_t <= 0.0:
		_pulse_t = PULSE_INTERVAL
		_fire_pulse()

func _fire_pulse() -> void:
	_spiral += ROTATE_PER_PULSE
	for i in SHOTS_PER_PULSE:
		var ang := _spiral + (TAU / float(SHOTS_PER_PULSE)) * float(i)
		var dir := Vector2(cos(ang), sin(ang))
		var p := _proj_scene.instantiate()
		p.global_position = global_position + dir * 18.0
		p.direction       = dir
		p.set("source",   "enemy")
		p.set("speed",    PROJ_SPEED)
		p.set("damage",   PROJ_DAMAGE)
		p.set("lifetime", PROJ_LIFETIME)
		get_tree().current_scene.add_child(p)

func _enemy_anim_update(delta: float) -> void:
	_anim_t += delta
	if _anim_t >= 0.18:
		_anim_t = 0.0
		_anim_f = 1 - _anim_f
	var t := F0 if _anim_f == 0 else F1
	if _lbl.text != t:
		_lbl.text = t
