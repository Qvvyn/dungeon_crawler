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
const HEARTH_SCRIPT  = preload("res://scripts/HearthSign.gd")
const QUEST_SCRIPT   = preload("res://scripts/QuestBoard.gd")
const REROLL_SCRIPT  = preload("res://scripts/Reroller.gd")
const TRAINING_DUMMY_SCRIPT = preload("res://scripts/TrainingDummy.gd")
const FIRST_PERSON_RIG_SCRIPT = preload("res://scripts/FirstPersonRig.gd")

const VILLAGE_W := 1600
const VILLAGE_H := 900
const TILE_PX   := 32
const VILLAGE_TW := 50   # VILLAGE_W / TILE_PX
const VILLAGE_TH := 28   # VILLAGE_H / TILE_PX rounded down + 1 wall row

var _fp_rig: CanvasLayer = null
var _v_grid: Array = []

func _ready() -> void:
	# Disable test mode and autoplay when entering the village so the bot
	# doesn't try to fight nothing or save state on idle frames.
	GameState.test_mode = false
	GameState.in_hub = true
	# Previous World scene freed itself on transition — clear the dangling
	# rig pointer; the village's own FP rig (built below) takes over from here.
	GameState.active_rig = null
	_build_floor()
	_build_walls()
	_build_title()
	_spawn_player(Vector2(VILLAGE_W * 0.5, VILLAGE_H * 0.6))
	_build_inn(    Vector2(VILLAGE_W * 0.20, VILLAGE_H * 0.30))
	_build_bank(   Vector2(VILLAGE_W * 0.50, VILLAGE_H * 0.20))
	_build_shop(   Vector2(VILLAGE_W * 0.80, VILLAGE_H * 0.30))
	_build_descend(Vector2(VILLAGE_W * 0.50, VILLAGE_H * 0.85))
	_build_hearth(Vector2(VILLAGE_W * 0.10, VILLAGE_H * 0.85))
	_build_quest_board(Vector2(VILLAGE_W * 0.90, VILLAGE_H * 0.85))
	_build_reroller(Vector2(VILLAGE_W * 0.50, VILLAGE_H * 0.45))
	_build_training_dummy(Vector2(VILLAGE_W * 0.32, VILLAGE_H * 0.65))
	_setup_fp_rig()
	# Honor whichever render mode the player toggled into before entering
	# the village. F1 now cycles modes in-village too (see Player.gd).
	if not GameState.render_mode_changed.is_connected(_on_render_mode_changed):
		GameState.render_mode_changed.connect(_on_render_mode_changed)
	_apply_render_mode(GameState.render_mode)

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
		"Return to the Dungeon", Color(0.85, 0.40, 0.60), pos, DESCEND_SCRIPT, 40.0)

func _build_hearth(pos: Vector2) -> void:
	_make_building_area("HEARTH",
		"Back to Title Screen", Color(0.65, 0.55, 0.85), pos, HEARTH_SCRIPT)

func _build_quest_board(pos: Vector2) -> void:
	_make_building_area("QUEST BOARD",
		"View & track quests", Color(0.85, 0.65, 0.30), pos, QUEST_SCRIPT)

func _build_reroller(pos: Vector2) -> void:
	_make_building_area("REROLL",
		"Shuffle stat points", Color(0.95, 0.65, 1.0), pos, REROLL_SCRIPT)

# Builds the visual shell for a hub building: an ASCII sign on a tinted
# Label, plus an Area2D that hosts the interaction script. The script is
# set BEFORE the node enters the tree so its _ready (which connects the
# body_entered/exited signals) actually fires.
func _make_building_area(title: String, subtitle: String, col: Color,
		pos: Vector2, area_script: Script, radius: float = 32.0) -> Area2D:
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

# ── Training dummy ─────────────────────────────────────────────────────────

func _build_training_dummy(pos: Vector2) -> void:
	# CharacterBody2D so projectile hits route to the enemy branch (see the
	# class doc on TrainingDummy.gd for why this matters).
	var dummy: CharacterBody2D = CharacterBody2D.new()
	dummy.set_script(TRAINING_DUMMY_SCRIPT)
	dummy.position = pos
	dummy.name = "TrainingDummy"
	add_child(dummy)

	var sign_lbl := Label.new()
	sign_lbl.text = "TRAINING DUMMY"
	sign_lbl.add_theme_font_override("font", MonoFont.get_font())
	sign_lbl.add_theme_font_size_override("font_size", 13)
	sign_lbl.add_theme_color_override("font_color", Color(0.85, 0.7, 0.45))
	sign_lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	sign_lbl.add_theme_constant_override("outline_size", 2)
	sign_lbl.size = Vector2(180, 16)
	sign_lbl.position = pos + Vector2(-90, 32)
	sign_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sign_lbl)

# ── First-person rig ───────────────────────────────────────────────────────

# Builds the FP rig (mirroring World._setup_render_rigs) and a flat tile grid
# for it to render — boundary tiles are walls, interior tiles are floor.
# Kept off-screen until the player cycles render mode to FP via F1.
func _setup_fp_rig() -> void:
	_fp_rig = CanvasLayer.new()
	_fp_rig.set_script(FIRST_PERSON_RIG_SCRIPT)
	_fp_rig.name = "FirstPersonRig"
	_fp_rig.visible = false
	add_child(_fp_rig)

	# Boundary-wall grid: outermost tile-row/col are walls, everything else
	# is floor. Matches the 4 StaticBody2D boundary rects from _build_walls
	# so 2D collision and FP visuals agree.
	_v_grid.clear()
	for y in VILLAGE_TH:
		var row: Array = []
		for x in VILLAGE_TW:
			var is_boundary: bool = (x == 0 or y == 0 or x == VILLAGE_TW - 1 or y == VILLAGE_TH - 1)
			row.append(1 if is_boundary else 0)
		_v_grid.append(row)

func _on_render_mode_changed(mode: int) -> void:
	_apply_render_mode(mode)

func _apply_render_mode(mode: int) -> void:
	if _fp_rig == null or not is_instance_valid(_fp_rig):
		return
	var fp_active: bool = (mode != GameState.RenderMode.TOPDOWN)
	_fp_rig.visible = fp_active
	if not fp_active:
		if _fp_rig.has_method("clear_entities"):
			_fp_rig.clear_entities()
		GameState.active_rig = null
		return
	if _fp_rig.has_method("clear_entities"):
		_fp_rig.clear_entities()
	if _fp_rig.has_method("set_camera_mode"):
		_fp_rig.set_camera_mode("first" if mode == GameState.RenderMode.FIRSTPERSON_SHADER else "third")
	if _fp_rig.has_method("set_wall_color"):
		_fp_rig.set_wall_color(Color(0.32, 0.26, 0.45))   # village's purple-grey wall
	if _fp_rig.has_method("set_floor_color"):
		_fp_rig.set_floor_color(Color(0.12, 0.10, 0.18))  # match _build_floor backdrop
	if _fp_rig.has_method("set_grid"):
		_fp_rig.set_grid(_v_grid, VILLAGE_TW, VILLAGE_TH)
	# Village hub is always fully illuminated — the player should be able
	# to see every building / dummy / NPC from anywhere in the room. This
	# overrides GameState.fp_illuminated (which only drives dungeon FP).
	if _fp_rig.has_method("set_fully_illuminated"):
		_fp_rig.set_fully_illuminated(true)
	GameState.active_rig = _fp_rig
	_register_fp_entities()

# Mirror of World._register_all_entities_with for the village hub. Player gets
# the wizard art; anything tagged "fp_visible" (training dummy) is auto-picked.
func _register_fp_entities() -> void:
	if _fp_rig == null or not _fp_rig.has_method("register_entity"):
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and player is Node2D:
		var wizard_glyph: String = "   ^\n__/_\\__\n (*-*)\n /)V(\\|\n /___\\|"
		if "WIZARD_F0" in player:
			wizard_glyph = player.get("WIZARD_F0")
		player.set_meta("fp_multiline", true)
		player.set_meta("fp_pixel_size", 0.0105)
		_fp_rig.register_entity(player, wizard_glyph, GameState.wizard_color)
	for node in get_tree().get_nodes_in_group("fp_visible"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var g: String = str(node.get_meta("fp_glyph", "?"))
		var c_v: Variant = node.get_meta("fp_color", Color.WHITE)
		var c: Color = c_v if c_v is Color else Color.WHITE
		_fp_rig.register_entity(node, g, c)
