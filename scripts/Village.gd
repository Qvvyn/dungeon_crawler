extends Node2D

# Wizard Village — the player's hub between dungeon delves. Houses an
# Inn (free heal + save), a Bank (persistent stash + bank gold), a Shop
# (buy potions, sell loot), and a Descend portal back to the dungeon.
#
# The village is intentionally a small open room rather than a procedural
# floor — no enemies, no path generation, no AsciiWalls. Buildings are
# Area2D nodes with [E] interaction prompts that open small UI overlays.

const PLAYER_SCENE = preload("res://scenes/Player.tscn")
const INN_SCRIPT    = preload("res://scripts/Inn.gd")
const BANK_SCRIPT   = preload("res://scripts/Bank.gd")
const SHOP_SCRIPT   = preload("res://scripts/Shop.gd")
const DESCEND_SCRIPT = preload("res://scripts/DescendPortal.gd")

const VILLAGE_W := 1600
const VILLAGE_H := 900

func _ready() -> void:
	# Disable test mode and autoplay when entering the village so the bot
	# doesn't try to fight nothing or save state on idle frames.
	GameState.test_mode = false
	GameState.in_hub = true
	_build_floor()
	_build_walls()
	_build_title()
	_spawn_player(Vector2(VILLAGE_W * 0.5, VILLAGE_H * 0.6))
	_build_inn(    Vector2(VILLAGE_W * 0.20, VILLAGE_H * 0.30))
	_build_bank(   Vector2(VILLAGE_W * 0.50, VILLAGE_H * 0.20))
	_build_shop(   Vector2(VILLAGE_W * 0.80, VILLAGE_H * 0.30))
	_build_descend(Vector2(VILLAGE_W * 0.50, VILLAGE_H * 0.85))

# ── World shell ────────────────────────────────────────────────────────────

func _build_floor() -> void:
	# Dim purple-grey backdrop, no tile rendering — keeps the focus on
	# the building signs and the player.
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.10)
	bg.position = Vector2.ZERO
	bg.size = Vector2(VILLAGE_W, VILLAGE_H)
	bg.z_index = -10
	add_child(bg)

func _build_walls() -> void:
	# Thin invisible-ish boundary walls so the player can't walk off the
	# screen edges. Just StaticBody2D rects on collision layer 1 to match
	# what Player's CharacterBody collides against.
	var thickness := 32.0
	var rects: Array = [
		Rect2(0, 0, VILLAGE_W, thickness),                  # top
		Rect2(0, VILLAGE_H - thickness, VILLAGE_W, thickness),  # bottom
		Rect2(0, 0, thickness, VILLAGE_H),                  # left
		Rect2(VILLAGE_W - thickness, 0, thickness, VILLAGE_H),  # right
	]
	for r: Rect2 in rects:
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = r.position + r.size * 0.5
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = r.size
		cs.shape = shape
		body.add_child(cs)
		add_child(body)

func _build_title() -> void:
	var lbl := Label.new()
	lbl.text = "— WIZARD VILLAGE —"
	lbl.position = Vector2(0, 50)
	lbl.size = Vector2(VILLAGE_W, 60)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_override("font", MonoFont.get_font())
	lbl.add_theme_font_size_override("font_size", 32)
	lbl.add_theme_color_override("font_color", Color(0.78, 0.62, 1.0))
	lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.0, 0.10))
	lbl.add_theme_constant_override("outline_size", 3)
	add_child(lbl)

	var sub := Label.new()
	sub.text = "Rest at the Inn · Bank your loot · Stock up at the Shop · Descend when ready"
	sub.position = Vector2(0, 100)
	sub.size = Vector2(VILLAGE_W, 24)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.45, 0.40, 0.60))
	add_child(sub)

# ── Player ─────────────────────────────────────────────────────────────────

func _spawn_player(pos: Vector2) -> void:
	# Don't consume an existing dungeon save on village entry — the player
	# may want to come back later via Title → CONTINUE RUN.
	GameState.skip_save_load_once = true
	GameState.has_saved_state = false
	var p := PLAYER_SCENE.instantiate()
	p.position = pos
	p.add_to_group("player")
	add_child(p)

# ── Building factories ─────────────────────────────────────────────────────

func _build_inn(pos: Vector2) -> void:
	_make_building_area("INN", "Heal & Save", Color(0.55, 0.95, 0.6), pos, INN_SCRIPT)

func _build_bank(pos: Vector2) -> void:
	_make_building_area("BANK", "Stash & Coin", Color(1.0, 0.85, 0.30), pos, BANK_SCRIPT)

func _build_shop(pos: Vector2) -> void:
	_make_building_area("SHOP", "Buy & Sell", Color(0.55, 0.80, 1.0), pos, SHOP_SCRIPT)

func _build_descend(pos: Vector2) -> void:
	_make_building_area("DESCEND",
		"Return to the Dungeon", Color(0.85, 0.40, 0.60), pos, DESCEND_SCRIPT, 90.0)

# Builds the visual shell for a hub building: an ASCII sign on a tinted
# Label, plus an Area2D that hosts the interaction script. The script is
# set BEFORE the node enters the tree so its _ready (which connects the
# body_entered/exited signals) actually fires.
func _make_building_area(title: String, subtitle: String, col: Color,
		pos: Vector2, area_script: Script, radius: float = 70.0) -> Area2D:
	var area := Area2D.new()
	area.set_script(area_script)
	area.position = pos
	area.collision_layer = 0
	area.collision_mask = 1   # detect Player (layer 1)
	add_child(area)

	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	cs.shape = shape
	area.add_child(cs)

	# Building "wall" — ASCII border around the sign.
	var box := Label.new()
	box.text = "+--------------+\n|              |\n|              |\n+--------------+"
	box.add_theme_font_override("font", MonoFont.get_font())
	box.add_theme_font_size_override("font_size", 22)
	box.add_theme_color_override("font_color", col.darkened(0.25))
	box.add_theme_constant_override("line_separation", -4)
	box.size = Vector2(280, 130)
	box.position = Vector2(-140, -65)
	box.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	area.add_child(box)

	# Building name on its own line.
	var name_lbl := Label.new()
	name_lbl.text = "[ %s ]" % title
	name_lbl.add_theme_font_override("font", MonoFont.get_font())
	name_lbl.add_theme_font_size_override("font_size", 24)
	name_lbl.add_theme_color_override("font_color", col)
	name_lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	name_lbl.add_theme_constant_override("outline_size", 2)
	name_lbl.size = Vector2(280, 28)
	name_lbl.position = Vector2(-140, -34)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	area.add_child(name_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = subtitle
	sub_lbl.add_theme_font_override("font", MonoFont.get_font())
	sub_lbl.add_theme_font_size_override("font_size", 13)
	sub_lbl.add_theme_color_override("font_color", col.darkened(0.15))
	sub_lbl.size = Vector2(280, 18)
	sub_lbl.position = Vector2(-140, -8)
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	area.add_child(sub_lbl)

	# Per-building hint shown only while player is in range. The
	# interaction scripts (Inn/Bank/Shop) toggle this on body_entered/
	# exited and listen to "interact" presses themselves.
	var hint := Label.new()
	hint.name = "InteractHint"
	hint.text = "[E] Interact"
	hint.visible = false
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	hint.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	hint.add_theme_constant_override("outline_size", 2)
	hint.size = Vector2(160, 22)
	hint.position = Vector2(-80, 36)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	area.add_child(hint)

	return area
