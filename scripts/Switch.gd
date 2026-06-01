extends StaticBody2D

# Shootable wall switch. When a projectile hits it, it opens its wired target
# (a remote_only Door) — DOOM's "shoot the switch to open the gate". One-shot.
# Reuses the projectile breakable-wall hit path (group "breakable_wall" →
# take_damage), so no Projectile changes are needed.
#
# World sets `_target` (the Door to open) before add_child.

var _target: Node = null
var _fired: bool = false
var _lbl: Label = null

func _ready() -> void:
	add_to_group("breakable_wall")   # makes player/enemy shots call take_damage()
	add_to_group("switch")
	collision_layer = 1
	collision_mask = 0
	z_index = 1
	# Small collision so it reads as a fixture without blocking a 3-wide corridor.
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(14, 14)
	cs.shape = rect
	add_child(cs)

	_lbl = Label.new()
	_lbl.add_theme_font_override("font", MonoFont.get_font())
	_lbl.add_theme_font_size_override("font_size", 18)
	_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	_lbl.add_theme_color_override("font_outline_color", Color(0.2, 0.12, 0.0))
	_lbl.add_theme_constant_override("outline_size", 2)
	_lbl.text = "I"
	_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lbl.size = Vector2(16, 16)
	_lbl.position = Vector2(-8, -10)
	_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lbl)

	set_meta("fp_outline_size", 3)
	GameState.attach_fp_visual(self, "I", Color(1.0, 0.85, 0.30), 0.5)

func take_damage(_amount: int) -> void:
	if _fired:
		return
	_fired = true
	if is_instance_valid(_target) and _target.has_method("open"):
		_target.open()
	# Thrown state — recolour + swap glyph in both 2D and FP.
	if _lbl:
		_lbl.text = "/"
		_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	GameState.update_fp_visual(self, "/", Color(0.55, 0.55, 0.55))
	FloatingText.spawn_str(global_position, "CLICK", Color(0.95, 0.9, 0.5), get_tree().current_scene)
	if SoundManager:
		SoundManager.play("whoosh", 1.25)
