class_name EffectFx
extends RefCounted

# One-shot ASCII visual effects: death pops, muzzle flashes, etc. Each
# spawns a Label with a tween that handles its own teardown — fire and
# forget. Centralized here so call sites stay one line at every spawn
# point (hits to enemies, fire button press, …).

static var _shared_font: Font = null

static func _font() -> Font:
	if _shared_font == null:
		_shared_font = MonoFont.get_font()
	return _shared_font

# ── Death pop ────────────────────────────────────────────────────────────
# Big, readable "X" that scales out and fades. Spawned by enemy death paths
# right before queue_free(); the tween + queue_free of the label is fully
# detached from the dying enemy so the visual survives the host's removal.
static func spawn_death_pop(pos: Vector2, scene_root: Node, color: Color = Color(1.0, 0.4, 0.4)) -> void:
	if not is_instance_valid(scene_root) or not scene_root.is_inside_tree():
		return
	var lbl := Label.new()
	lbl.text = "X"
	lbl.add_theme_font_override("font", _font())
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.position = pos - Vector2(16.0, 14.0)
	lbl.size     = Vector2(32.0, 28.0)
	lbl.z_index  = 4
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.pivot_offset = Vector2(16.0, 14.0)
	scene_root.add_child(lbl)
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "scale", Vector2(2.2, 2.2), 0.35)
	tw.parallel().tween_property(lbl, "rotation", randf_range(-0.6, 0.6), 0.35)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.35)
	tw.tween_callback(lbl.queue_free)

# ── Muzzle flash ─────────────────────────────────────────────────────────
# Brief glyph at the wand tip in the wand's color/icon. Reads as "this
# wand fired" without reading like another projectile.
static func spawn_muzzle_flash(pos: Vector2, glyph: String, color: Color, scene_root: Node) -> void:
	if not is_instance_valid(scene_root) or not scene_root.is_inside_tree():
		return
	var lbl := Label.new()
	lbl.text = glyph
	lbl.add_theme_font_override("font", _font())
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.position = pos - Vector2(14.0, 14.0)
	lbl.size     = Vector2(28.0, 28.0)
	lbl.z_index  = 5
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.pivot_offset = Vector2(14.0, 14.0)
	scene_root.add_child(lbl)
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "scale", Vector2(1.7, 1.7), 0.10)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.10)
	tw.tween_callback(lbl.queue_free)
