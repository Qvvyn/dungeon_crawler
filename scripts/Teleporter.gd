extends Area2D

const BASE_FP_PS: float = 0.013   # baseline FP pixel size; oscillates around this

var _partner: Node2D = null
var _cooldown: float = 0.0
var _lbl: Label = null
var _pulse_t: float = 0.0

func setup(pos: Vector2) -> void:
	position = pos
	add_to_group("teleporter")
	collision_layer = 0
	collision_mask  = 1
	# "O" matches the 2D ring label below — FP previously diverged with "T".
	GameState.attach_fp_visual(self, "O", Color(0.55, 1.0, 0.85), 0.45)
	# Drive the FP size oscillation by updating this meta per-frame; the rig
	# re-reads fp_pixel_size every frame for single-line entities.
	set_meta("fp_pixel_size", BASE_FP_PS)

	var cshape := CollisionShape2D.new()
	var circ := CircleShape2D.new()
	circ.radius = 12.0
	cshape.shape = circ
	add_child(cshape)

	_lbl = Label.new()
	# Named "AsciiChar" so the rig mirrors this label's live modulate into FP,
	# letting the glow pulse below reach first-person.
	_lbl.name = "AsciiChar"
	_lbl.text = "O"
	_lbl.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
	_lbl.add_theme_font_size_override("font_size", 14)
	_lbl.position = Vector2(-5.0, -10.0)
	add_child(_lbl)

	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
	# Glow + size oscillation. A slow sine breathes the FP pixel size and
	# brightens the glyph toward an overbright peak so the teleporter clearly
	# pulses + glows in first-person (and softly pulses in 2D too). Damped when
	# "reduce flashing" is on.
	_pulse_t += delta
	var s: float = sin(_pulse_t * 3.0) * 0.5 + 0.5   # 0 → 1
	var size_amp: float = 0.35 if not GameState.disable_flashing else 0.12
	set_meta("fp_pixel_size", BASE_FP_PS * (1.0 + size_amp * s))
	if _lbl != null:
		var peak: float = 1.45 if not GameState.disable_flashing else 1.15
		var g: float = lerp(0.75, peak, s)
		_lbl.modulate = Color(g, g, g, 1.0)

func link(other: Node2D) -> void:
	_partner = other

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if _cooldown > 0.0:
		return
	if _partner == null or not is_instance_valid(_partner):
		return
	_cooldown = 1.5
	_partner._cooldown = 1.5
	if SoundManager:
		SoundManager.play("teleport")
	# Autoplay: remember both endpoints so future paths route around them
	if body.get("_autoplay") == true and body.has_method("_autoplay_blacklist_pos"):
		body.call("_autoplay_blacklist_pos", global_position)
		body.call("_autoplay_blacklist_pos", _partner.global_position)
	body.global_position = _partner.global_position
