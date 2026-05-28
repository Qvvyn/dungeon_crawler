extends Area2D

# Ice Cavern biome hazard — applies slow status to the player while they
# walk on it.

const SLOW_DURATION := 1.4

var _player_inside: bool = false
var _refresh_t: float    = 0.0
var _pulse_t: float      = 0.0
var _label: Label        = null
# Optional expiry — 0 means "permanent" (biome generator placement); the
# frost sentinel sets this so its ice waves don't accumulate forever and
# the arena floor stays readable.
var lifetime: float = 0.0
var _life_t: float  = 0.0

func _ready() -> void:
	add_to_group("hazard")
	# FP mirrors the 2D label's single "*" (was a 3-line patch which read
	# too big and chest-high). Small pixel_size + floor-level fp_height
	# makes it look like ice crystals dusting the ground.
	set_meta("fp_pixel_size", 0.006)
	set_meta("fp_floor_decal", true)   # lie flat on the floor in FP
	GameState.attach_fp_visual(self, "*", Color(0.55, 0.92, 1.0), 0.04)
	var cshape := CollisionShape2D.new()
	var shape  := CircleShape2D.new()
	shape.radius = 14.0
	cshape.shape = shape
	add_child(cshape)

	_label = Label.new()
	_label.text = "*"
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(0.65, 0.92, 1.0, 0.70))
	_label.position = Vector2(-6.0, -14.0)
	add_child(_label)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_inside = true
		_apply_slow()

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_inside = false

func _process(delta: float) -> void:
	if lifetime > 0.0:
		_life_t += delta
		if _life_t >= lifetime:
			queue_free()
			return
		var remain := lifetime - _life_t
		if _label and remain < 1.0:
			_label.modulate.a = clampf(remain, 0.0, 1.0)

	_pulse_t += delta * 1.4
	var pulse := 0.5 + 0.5 * sin(_pulse_t)
	if _label:
		_label.add_theme_color_override("font_color",
			Color(0.55 + pulse * 0.30, 0.85, 1.0, 0.55 + pulse * 0.30))
	if not _player_inside:
		return
	# Refresh slow continuously so the debuff doesn't expire while standing on it
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 0.5
		_apply_slow()

func _apply_slow() -> void:
	var ply: Node2D = get_tree().get_first_node_in_group("player")
	if is_instance_valid(ply) and ply.has_method("apply_status"):
		ply.apply_status("slow", SLOW_DURATION)
