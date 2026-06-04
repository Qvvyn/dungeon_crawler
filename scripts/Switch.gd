extends Area2D

# Lever switch. Walk up and press E (the "interact" action) to open its wired
# target (a remote_only Door) — "pull the lever to open the gate". One-shot.
#
# Non-blocking on purpose: the player (and autoplay) passes straight through it,
# so the bot never snags on a lever. Projectiles pass through too — it's in the
# "interactable" group, so it can no longer be triggered by shooting it.
# Autoplay can't press E, so it auto-pulls the lever on contact and still opens
# the gate it's wired to.
#
# World sets `_target` (the Door to open) before add_child.

var _target: Node = null
var _fired: bool = false
var _player_in_range: bool = false
var _lbl: Label = null
var _hint: Label = null

func _ready() -> void:
	add_to_group("switch")
	add_to_group("interactable")   # projectiles pass through; autoplay targets it
	collision_layer = 0            # blocks nothing — player walks through freely
	collision_mask = 1             # detect the player body (layer 1)
	monitoring = true
	z_index = 1
	# Detection area (non-blocking) — a touch wider than the old 8x8 collider so
	# the E-prompt range is forgiving.
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(28, 28)
	cs.shape = rect
	add_child(cs)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

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

	# "[E]" prompt shown while the player stands on the lever (also drives the
	# FP interact-hint scan, which looks for a visible child label starting "[").
	_hint = Label.new()
	_hint.name = "InteractHint"
	_hint.add_theme_font_override("font", MonoFont.get_font())
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hint.add_theme_constant_override("outline_size", 2)
	_hint.text = "[E] lever"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.position = Vector2(-30, -30)
	_hint.size = Vector2(60, 16)
	_hint.visible = false
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)

	set_meta("fp_outline_size", 3)
	GameState.attach_fp_visual(self, "I", Color(1.0, 0.85, 0.30), 0.5)

func _process(_delta: float) -> void:
	if not _fired and _player_in_range and Input.is_action_just_pressed("interact"):
		_activate()

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = true
	if _hint:
		_hint.visible = not _fired
	# Autoplay can't press E — pull the lever automatically on contact so the
	# bot still opens the gate it's wired to.
	if body.get("_autoplay") == true:
		_activate()

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		if _hint:
			_hint.visible = false

func _activate() -> void:
	if _fired:
		return
	_fired = true
	if _hint:
		_hint.visible = false
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
