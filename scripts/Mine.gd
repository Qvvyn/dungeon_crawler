extends Area2D

const ARM_TIME    := 1.0
const RADIUS      := 56.0
const DAMAGE      := 5
const LIFETIME    := 18.0

const F_UNARMED  := " ,_, \n( . )\n '_' "
const F_ARMED_0  := " \\!/ \n(>X<)\n /_\\ "
const F_ARMED_1  := " -!- \n[#X#]\n /_\\ "

var _armed: bool      = false
var _arm_t: float     = ARM_TIME
var _life_t: float    = LIFETIME
var _detonated: bool  = false
var _lbl: Label       = null
var _anim_t: float    = 0.0
var _anim_f: int      = 0

static var _shared_font: Font = null

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	add_to_group("mine")
	if _shared_font == null:
		_shared_font = MonoFont.get_font()
	_lbl = Label.new()
	_lbl.add_theme_font_override("font", _shared_font)
	_lbl.add_theme_font_size_override("font_size", 13)
	_lbl.add_theme_constant_override("line_separation", -4)
	_lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_lbl.add_theme_constant_override("outline_size", 2)
	_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.2))
	_lbl.text = F_UNARMED
	_lbl.size = Vector2(60.0, 50.0)
	_lbl.position = Vector2(-30.0, -25.0)
	_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lbl)

func _process(delta: float) -> void:
	_life_t -= delta
	if _life_t <= 0.0:
		queue_free()
		return
	if _arm_t > 0.0:
		_arm_t -= delta
		if _arm_t <= 0.0:
			_armed = true
			_lbl.text = F_ARMED_0
			_lbl.add_theme_color_override("font_color", Color(1.0, 0.15, 0.0))
	if _armed and _lbl:
		# Frame swap for menacing flicker
		_anim_t += delta
		if _anim_t >= 0.18:
			_anim_t = 0.0
			_anim_f = 1 - _anim_f
			_lbl.text = F_ARMED_0 if _anim_f == 0 else F_ARMED_1
		# Pulse alpha
		var p := sin(Time.get_ticks_msec() * 0.012) * 0.3 + 0.7
		_lbl.modulate = Color(1.0, p * 0.5 + 0.3, p * 0.3, 1.0)

func _on_body_entered(body: Node) -> void:
	if not _armed or _detonated: return
	if body.is_in_group("player"):
		_detonate()

func _detonate() -> void:
	_detonated = true
	var ply := get_tree().get_first_node_in_group("player")
	if is_instance_valid(ply) and (ply as Node2D).global_position.distance_to(global_position) <= RADIUS:
		if ply.has_method("take_damage"):
			ply.take_damage(DAMAGE)
	if SoundManager:
		SoundManager.play("explosion", randf_range(1.05, 1.18))
	# Expanding shockwave ring — clearly an explosion, not a square on the ground
	var holder := Node2D.new()
	holder.global_position = global_position
	get_tree().current_scene.add_child(holder)
	var ring := Line2D.new()
	ring.width = 4.0
	ring.default_color = Color(1.0, 0.45, 0.05, 0.95)
	var segs := 24
	for i in segs + 1:
		var ang := (TAU / float(segs)) * float(i)
		ring.add_point(Vector2(cos(ang), sin(ang)) * RADIUS * 0.5)
	holder.add_child(ring)
	var tw := holder.create_tween()
	tw.tween_property(holder, "scale", Vector2(2.2, 2.2), 0.30)
	tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.30)
	tw.tween_callback(holder.queue_free)
	queue_free()
