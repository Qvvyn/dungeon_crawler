class_name FloatingText
# Static utility — call FloatingText.spawn() from any script.
# No autoload needed; class_name makes it globally visible once the file is parsed.

# Hard cap on concurrent floaters so busy combat rooms don't spawn hundreds of
# Labels + Tweens per second. Excess spawn calls are silently dropped.
const MAX_ACTIVE := 32
# Labels are recycled instead of new/free'd each spawn — heavy combat (damage
# numbers, "!" alerts, infight chip) churned a Label + Tween per event. Released
# labels are DETACHED (removed from the scene), so they survive floor changes and
# get re-parented on reuse. Pool is bounded.
const MAX_POOL := 48
static var _active_count: int = 0
static var _pool: Array = []   # detached, reusable Labels

# Called by World on floor load. Labels still mid-animation when the scene is
# freed never fire their release callback, so the active count would otherwise
# leak upward across floors until it pinned at MAX_ACTIVE and dropped all text.
static func reset() -> void:
	_active_count = 0

static func _acquire() -> Label:
	while not _pool.is_empty():
		var l: Variant = _pool.pop_back()
		if is_instance_valid(l):
			return l as Label
	return Label.new()

static func _release(label: Label) -> void:
	_active_count = maxi(0, _active_count - 1)
	if not is_instance_valid(label):
		return
	var p := label.get_parent()
	if p != null:
		p.remove_child(label)
	if _pool.size() < MAX_POOL:
		_pool.append(label)
	else:
		label.queue_free()

static func _setup_label(label: Label, col: Color) -> void:
	# Reset state that the previous use's fade tween left behind, then configure.
	label.modulate = Color(1, 1, 1, 1)
	label.visible = true
	label.size = Vector2(160, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", col)
	label.add_theme_constant_override("outline_size", 2)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.z_index = 100

static func spawn_str(world_pos: Vector2, text: String, col: Color, parent: Node) -> void:
	if _active_count >= MAX_ACTIVE:
		return
	_active_count += 1
	var label := _acquire()
	label.text = text
	_setup_label(label, col)
	parent.add_child(label)
	label.global_position = world_pos + Vector2(-80.0 + randf_range(-8.0, 8.0), -52.0)
	var tween := label.create_tween()
	tween.tween_property(label, "position", label.position + Vector2(0.0, -50.0), 0.85)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.85)
	tween.tween_callback(_release.bind(label))
	# FP mirror — float a Label3D billboard up from the same world point so
	# the player sees CRIT/SHATTER/FLARE/BURN callouts in first-person too.
	if GameState.active_rig != null and is_instance_valid(GameState.active_rig) \
			and GameState.active_rig.has_method("spawn_floating_text"):
		GameState.active_rig.spawn_floating_text(world_pos, text, col, 0.85)

static func spawn(world_pos: Vector2, value: int, is_heal: bool, parent: Node, custom_color: Color = Color.TRANSPARENT) -> void:
	if _active_count >= MAX_ACTIVE:
		return
	_active_count += 1
	var label := _acquire()
	var text_str := ("+" if is_heal else "") + str(value)
	label.text = text_str
	var col: Color
	if custom_color.a > 0.0:
		col = custom_color
	else:
		col = Color(0.15, 0.9, 0.15) if is_heal else Color(1.0, 0.15, 0.15)
	_setup_label(label, col)
	parent.add_child(label)
	label.global_position = world_pos + Vector2(-80.0 + randf_range(-8.0, 8.0), -52.0)

	var tween := label.create_tween()
	tween.tween_property(label, "position", label.position + Vector2(0.0, -50.0), 0.85)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.85)
	tween.tween_callback(_release.bind(label))
	if GameState.active_rig != null and is_instance_valid(GameState.active_rig) \
			and GameState.active_rig.has_method("spawn_floating_text"):
		GameState.active_rig.spawn_floating_text(world_pos, text_str, col, 0.85)
