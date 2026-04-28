class_name FrozenBlock
extends Label

# Ice-block overlay. Mounted as a child of any frozen entity so the silvery
# tint on the entity's own glyph is paired with a clear "trapped in ice"
# silhouette. Sync via FrozenBlock.sync_to(host, _frozen) once per frame —
# spawns the overlay on the rising edge, queue_frees it when freeze ends.
#
# Designed as a single Label attached directly to the enemy's CharacterBody2D
# so positioning rides along with movement (e.g. boss kited while frozen).

const ICE_GLYPH := ".======.\n|      |\n|      |\n'======'"

static var _shared_font: Font = null

# One-call frame-sync helper. Cheap when nothing changed: only walks the
# child tree once and only allocates on state transitions.
static func sync_to(host: Node, frozen: bool) -> void:
	if not is_instance_valid(host):
		return
	var existing := host.get_node_or_null("FrozenBlock") as Label
	if frozen:
		if existing == null:
			var fb := FrozenBlock.new()
			fb.name = "FrozenBlock"
			host.add_child(fb)
	elif existing != null:
		existing.queue_free()

func _ready() -> void:
	if _shared_font == null:
		_shared_font = MonoFont.get_font()
	add_theme_font_override("font", _shared_font)
	add_theme_font_size_override("font_size", 16)
	add_theme_constant_override("line_separation", -2)
	add_theme_color_override("font_color", Color(0.78, 0.92, 1.0))
	add_theme_color_override("font_outline_color", Color(0.40, 0.62, 0.90))
	add_theme_constant_override("outline_size", 2)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	# Box generous enough to contain even multi-line glyphs (shooter, spider).
	# Centered alignment keeps the ice frame lined up around the entity's
	# origin regardless of which sprite size the host enemy uses.
	offset_left   = -42.0
	offset_top    = -34.0
	offset_right  =  42.0
	offset_bottom =  34.0
	text = ICE_GLYPH
	modulate.a = 0.92
	# z_index 1 sits behind the enemy's AsciiChar (z_index 2) so the entity
	# silhouette stays readable through the frame instead of being covered.
	z_index = 1
	mouse_filter = Control.MOUSE_FILTER_IGNORE
