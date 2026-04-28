extends Area2D

# Dungeon → Village portal. Spawned every N floors (see World.gd's
# spawn condition). Lets the player bail with their loot intact instead
# of pushing deeper for another run-ending death — successful "delves"
# end at one of these.
#
# Run gold transfers automatically to the bank on exit so the player
# doesn't lose it if the gold-deposit step is skipped.

const _EXIT_GLYPH := "  ,-^^^-.  \n /  ###  \\ \n|>> ["
const _EXIT_AFTER := "] >>|\n \\  ###  / \n  `-vvv-'  "
const _FRAMES := ["EX", "XE", "==", "EX", "<<", ">>", "==", "XE"]

var _player_in_range: bool = false
var _anim_t: float = 0.0
var _label: Label = null
var _hint: Label = null

func _ready() -> void:
	add_to_group("portal")
	add_to_group("exit_portal")
	collision_layer = 0
	collision_mask = 1
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 36.0
	cs.shape = shape
	add_child(cs)

	_label = Label.new()
	_label.add_theme_font_override("font", MonoFont.get_font())
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	_label.add_theme_color_override("font_outline_color", Color(0.10, 0.07, 0.0))
	_label.add_theme_constant_override("outline_size", 2)
	_label.add_theme_constant_override("line_separation", -3)
	_label.size = Vector2(160, 80)
	_label.position = Vector2(-80, -40)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)

	_hint = Label.new()
	_hint.text = "[E] Return to Village"
	_hint.visible = false
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color(1.0, 0.85, 0.40))
	_hint.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_hint.add_theme_constant_override("outline_size", 2)
	_hint.size = Vector2(220, 22)
	_hint.position = Vector2(-110, 32)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)

func _process(delta: float) -> void:
	_anim_t += delta
	var idx := int(_anim_t / 0.18) % _FRAMES.size()
	_label.text = _EXIT_GLYPH + _FRAMES[idx] + _EXIT_AFTER
	# Pulse gold ↔ amber so it visually distinguishes from the cyan
	# next-floor portal.
	var pulse := 0.5 + 0.5 * sin(_anim_t * TAU * 0.65)
	_label.add_theme_color_override("font_color",
		Color(1.0, 0.65 + pulse * 0.30, 0.05 + pulse * 0.30, 1.0))

	if _player_in_range and Input.is_action_just_pressed("interact"):
		_use()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		_hint.visible = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		_hint.visible = false

func _use() -> void:
	# Auto-deposit run gold so the delve actually pays out.
	if GameState.gold > 0:
		PersistentStash.add_gold(GameState.gold)
		GameState.gold = 0
	# Clear the saved run so re-entering the dungeon starts fresh.
	if FileAccess.file_exists("user://save_run.json"):
		DirAccess.remove_absolute("user://save_run.json")
	get_tree().change_scene_to_file("res://scenes/Village.tscn")
