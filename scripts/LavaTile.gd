extends Area2D

# Tunables — set before add_child to override (e.g. the Magma boss
# spawns a bigger, harder-hitting puddle that reuses this same tile).
var burn_interval: float = 0.65
var burn_damage: int     = 1
var tile_radius: float   = 7.0

var _player_inside: bool = false
var _burn_timer: float   = 0.0
var _pulse_t: float      = 0.0
var _label: Label        = null
# Optional expiry — 0 means "permanent" (biome generator placement); the
# magma slug / arena eruption / boss puddle set this to a few seconds so
# dropped tiles don't accumulate forever and clutter the room.
var lifetime: float = 0.0
var _life_t: float  = 0.0

func _ready() -> void:
	add_to_group("hazard")
	# FP mirrors the 2D label's single "~" — small + floor-level so the
	# lava tile reads as a puddle on the ground, not a chest-high glyph.
	# Unified orange "~" so lava tiles and the Magma boss puddle read as
	# the same hazard.
	# Larger boss puddles get a double-row ~~ glyph and bigger pixel_size
	# so they read as visibly more dangerous than the small biome tiles.
	var fp_glyph: String = "~~\n~~" if tile_radius > 10.0 else "~"
	var fp_ps: float     = 0.008    if tile_radius > 10.0 else 0.006
	set_meta("fp_pixel_size", fp_ps)
	set_meta("fp_multiline", tile_radius > 10.0)
	set_meta("fp_floor_decal", true)   # lie flat on the floor in FP
	set_meta("fp_outline_size", 3)     # thin glyph outline
	GameState.attach_fp_visual(self, fp_glyph, Color(1.0, 0.45, 0.05), 0.04)
	var cshape := CollisionShape2D.new()
	var shape  := CircleShape2D.new()
	shape.radius = tile_radius
	cshape.shape = shape
	add_child(cshape)

	_label = Label.new()
	_label.text = "~"
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.05, 0.85))
	_label.position = Vector2(-7.0, -12.0)
	add_child(_label)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_inside = true
		_burn_timer = 0.0

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_inside = false

func _process(delta: float) -> void:
	# Lifetime decay for transient tiles (slug trail, eruptions). When set,
	# the tile self-destructs once life expires; the last second fades alpha
	# so it doesn't pop out abruptly.
	if lifetime > 0.0:
		_life_t += delta
		if _life_t >= lifetime:
			queue_free()
			return
		var remain := lifetime - _life_t
		if _label and remain < 1.0:
			_label.modulate.a = clampf(remain, 0.0, 1.0)

	_pulse_t += delta * 2.2
	var pulse := 0.55 + 0.45 * sin(_pulse_t)
	if _label:
		_label.add_theme_color_override("font_color",
			Color(1.0, 0.25 + pulse * 0.3, 0.0, 0.65 + pulse * 0.35))

	if not _player_inside:
		return
	_burn_timer -= delta
	if _burn_timer <= 0.0:
		_burn_timer = burn_interval
		var player: Node2D = get_tree().get_first_node_in_group("player")
		if is_instance_valid(player) and player.has_method("take_damage"):
			player.take_damage(burn_damage)
			FloatingText.spawn_str(global_position, "BURN!", Color(1.0, 0.35, 0.0), get_tree().current_scene)
