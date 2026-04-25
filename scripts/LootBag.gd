extends Area2D

var items: Array = []
var _player_nearby: bool = false
var _hint: Label = null
var _popup: CanvasLayer = null
var _popup_rects: Array = []  # Rect2 for each item cell, parallel to items at time of open

func _ready() -> void:
	add_to_group("loot_bag")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Only generate random items if none were pre-set (e.g. from a discard)
	if items.is_empty():
		var count := randi_range(1, 3)
		for _i in count:
			items.append(ItemDB.random_drop())

	_recolor_by_rarity()

	_hint = Label.new()
	_hint.text = "[E] Loot"
	_hint.position = Vector2(-28.0, -38.0)
	_hint.visible = false
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	_hint.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_hint.add_theme_constant_override("outline_size", 2)
	add_child(_hint)

func _process(_delta: float) -> void:
	if _player_nearby and Input.is_action_just_pressed("interact"):
		if _popup == null:
			_open_popup()
		else:
			_close_popup()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_nearby = true
		if _hint:
			_hint.visible = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_nearby = false
		if _hint:
			_hint.visible = false
		_close_popup()

# ── Popup ─────────────────────────────────────────────────────────────────────

func _open_popup() -> void:
	if items.is_empty():
		queue_free()
		return

	_popup_rects.clear()
	_popup = CanvasLayer.new()
	_popup.layer = 12
	get_tree().current_scene.add_child(_popup)

	var cell_w := 110.0
	var cell_h := 90.0
	var gap    := 8.0
	var count  := items.size()
	var total_w := float(count) * cell_w + float(count - 1) * gap + 24.0
	var ox := (1600.0 - total_w) / 2.0
	var oy := 572.0

	# Background
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.12, 0.97)
	bg.position = Vector2(ox - 4.0, oy - 28.0)
	bg.size = Vector2(total_w + 8.0, cell_h + 48.0)
	_popup.add_child(bg)

	# Title
	var title := Label.new()
	title.text = "[ LOOT BAG ]  —  click item to collect  |  [E] close"
	title.position = Vector2(ox, oy - 22.0)
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.9, 0.75, 0.3))
	_popup.add_child(title)

	# Item cells
	for i in count:
		var item: Item = items[i]
		var ix := ox + float(i) * (cell_w + gap)
		var iy := oy

		_popup_rects.append(Rect2(ix, iy, cell_w, cell_h))

		var cell := ColorRect.new()
		cell.color = item.color.darkened(0.5)
		cell.position = Vector2(ix, iy)
		cell.size = Vector2(cell_w, cell_h)
		_popup.add_child(cell)

		var lbl := Label.new()
		lbl.text = item.icon_char + "\n" + item.display_name
		lbl.position = Vector2(ix + 4.0, iy + 4.0)
		lbl.size = Vector2(cell_w - 8.0, cell_h - 8.0)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", item.color.lightened(0.3))
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_popup.add_child(lbl)

func receive_item(item: Item) -> void:
	items.append(item)
	_recolor_by_rarity()
	if _popup != null:
		_close_popup()
		_open_popup()

# Tints the ASCII glyph by the highest-rarity item still in the bag, so the
# player can spot good drops at a glance:
#   LEGENDARY → purple "$", RARE → white "$", COMMON → bronze "$".
func _recolor_by_rarity() -> void:
	var visual := get_node_or_null("Visual") as Label
	if visual == null:
		return
	var max_r: int = -1
	for it in items:
		if it is Item and (it as Item).rarity > max_r:
			max_r = (it as Item).rarity
	var col: Color
	var glyph: String = "$"
	match max_r:
		Item.RARITY_LEGENDARY:
			col = Color(0.78, 0.32, 1.00)   # purple — top tier
		Item.RARITY_RARE:
			col = Color(0.95, 0.95, 0.95)   # white — second tier
		Item.RARITY_COMMON:
			col = Color(0.85, 0.55, 0.15)   # bronze — common (brighter so it reads on dark floors)
		_:
			col = Color(0.55, 0.55, 0.55)   # empty/unknown — gray
	visual.text = glyph
	visual.add_theme_color_override("font_color", col)
	visual.add_theme_color_override("font_outline_color", col.darkened(0.7))

func _close_popup() -> void:
	if _popup:
		_popup.queue_free()
		_popup = null
	_popup_rects.clear()
	if items.is_empty():
		queue_free()

# ── Input ─────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if _popup == null or not _player_nearby:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return

	var mp := get_viewport().get_mouse_position()
	for i in _popup_rects.size():
		if i >= items.size():
			break
		var r: Rect2 = _popup_rects[i]
		if r.has_point(mp):
			var item: Item = items[i]
			if InventoryManager.add_item(item):
				items.remove_at(i)
				_close_popup()
				if not items.is_empty():
					_open_popup()
			get_viewport().set_input_as_handled()
			return
