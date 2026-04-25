extends Node2D

# Spawned by ENFLAMED proc (10 burn stacks). Sits on the ground for a few
# seconds, ticking damage to any enemy in radius.

const DURATION  := 4.0
const TICK_RATE := 0.8
const TICK_DMG  := 4

const FLAME_F0 := " )( )( ,(\n((()(())\n)(())(((\n  ()((\n   ))"
const FLAME_F1 := " ,) )(  )\n)(()(()\n((((())(\n  (()((\n   ((  "

var _life: float   = DURATION
var _tick_t: float = 0.0
var _radius: float = 36.0
var _patch: Label  = null
var _anim_t: float = 0.0
var _anim_f: int   = 0

static var _shared_font: Font = null

func _ready() -> void:
	# Scale radius with player level (mirrors Player._fire intelligence calc)
	var intel: int = clampi(1 + (GameState.level - 1) / 2, 1, 8)
	_radius = 28.0 + float(intel) * 5.0

	if _shared_font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Consolas", "Courier New", "Lucida Console"])
		_shared_font = f

	_patch = Label.new()
	_patch.text = FLAME_F0
	_patch.add_theme_font_override("font", _shared_font)
	_patch.add_theme_color_override("font_color", Color(1.0, 0.45, 0.05))
	_patch.add_theme_color_override("font_outline_color", Color(0.45, 0.05, 0.0))
	_patch.add_theme_constant_override("outline_size", 2)
	_patch.add_theme_constant_override("line_separation", -3)
	_patch.add_theme_font_size_override("font_size", maxi(11, int(_radius * 0.45)))
	_patch.size = Vector2(_radius * 2.4, _radius * 2.4)
	_patch.position = Vector2(-_radius * 1.2, -_radius * 1.2)
	_patch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_patch.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_patch.modulate = Color(1.0, 1.0, 1.0, 0.85)
	_patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_patch)

func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	# Fade in last 30% of life
	if _life < DURATION * 0.3:
		_patch.modulate.a = clampf(_life / (DURATION * 0.3), 0.0, 1.0) * 0.85
	# Frame swap for flicker
	_anim_t += delta
	if _anim_t >= 0.16:
		_anim_t = 0.0
		_anim_f = 1 - _anim_f
		_patch.text = FLAME_F0 if _anim_f == 0 else FLAME_F1
	# Damage tick
	_tick_t -= delta
	if _tick_t <= 0.0:
		_tick_t = TICK_RATE
		_do_damage()

func _do_damage() -> void:
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy):
			continue
		if (enemy as Node2D).global_position.distance_to(global_position) <= _radius:
			if enemy.has_method("take_damage"):
				enemy.take_damage(TICK_DMG)
				GameState.damage_dealt += TICK_DMG
				GameState.record_weapon_damage("fire", TICK_DMG)
				if enemy.is_queued_for_deletion():
					GameState.record_weapon_kill("fire")
