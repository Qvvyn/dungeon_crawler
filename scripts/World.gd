extends Node2D

# ── Grid constants ─────────────────────────────────────────────────────────────
const TILE: int        = 32    # pixels per tile
const GRID_W: int      = 72    # tiles wide  → 2304 px
const GRID_H: int      = 56    # tiles tall  → 1792 px
const FLOOR: int       = 0
const WALL: int        = 1

# BSP: minimum partition size (tiles) before we stop splitting
const MIN_SPLIT_W: int = 12
const MIN_SPLIT_H: int = 10

# ── Resources ─────────────────────────────────────────────────────────────────
const PLAYER_SCENE       = preload("res://scenes/Player.tscn")
const PORTAL_SCENE       = preload("res://scenes/Portal.tscn")
const SELL_CHEST_SCENE   = preload("res://scenes/SellChest.tscn")
const FLOOR_SHADER       = preload("res://shaders/floor_dots.gdshader")
const CHASER_SCENE       = preload("res://scenes/EnemyChaser.tscn")
const SHOOTER_SCENE      = preload("res://scenes/EnemyShooter.tscn")
const ENCHANTER_SCENE    = preload("res://scenes/EnemyEnchanter.tscn")
const TANK_SCENE         = preload("res://scenes/EnemyTank.tscn")
const SNIPER_SCENE       = preload("res://scenes/EnemySniper.tscn")
const SUMMONER_SCENE     = preload("res://scenes/EnemySummoner.tscn")
const BOSS_SCENE         = preload("res://scenes/EnemyBoss.tscn")
const SPIKE_TRAP_SCENE   = preload("res://scenes/SpikeTrap.tscn")
const SECRET_DOOR_SCENE  = preload("res://scenes/SecretDoor.tscn")
const ENCHANT_TABLE_SCENE= preload("res://scenes/EnchantTable.tscn")
const LOOT_BAG_SCENE     = preload("res://scenes/LootBag.tscn")
const GOLD_PICKUP_SCENE  = preload("res://scenes/GoldPickup.tscn")
const LAVA_TILE_SCRIPT   = preload("res://scripts/LavaTile.gd")

# ── Biome palette ─────────────────────────────────────────────────────────────
const BIOME_NAMES := ["Dungeon", "Catacombs", "Ice Cavern", "Lava Rift"]
const BIOME_WALL_COLORS: Array[Color] = [
	Color(0.12, 0.10, 0.18),   # Dungeon
	Color(0.08, 0.14, 0.07),   # Catacombs
	Color(0.06, 0.10, 0.24),   # Ice Cavern
	Color(0.22, 0.07, 0.04),   # Lava Rift
]
const BIOME_FLOOR_TINTS: Array[Color] = [
	Color(1.00, 1.00, 1.00),   # Dungeon  (no tint)
	Color(0.80, 1.00, 0.78),   # Catacombs
	Color(0.80, 0.88, 1.00),   # Ice Cavern
	Color(1.00, 0.82, 0.76),   # Lava Rift
]

# ── Floor modifiers ───────────────────────────────────────────────────────────
const FLOOR_MODIFIERS := {
	"cursed":    {"name": "CURSED",    "desc": "Enemies move 50% faster"},
	"bloodlust": {"name": "BLOODLUST", "desc": "Enemies have double HP"},
	"haunted":   {"name": "HAUNTED",   "desc": "All enemies are elite"},
	"arcane":    {"name": "ARCANE",    "desc": "Mana regenerates twice as fast"},
	"haste":     {"name": "HASTE",     "desc": "You move 30% faster"},
}

# ── Secret door tracking ───────────────────────────────────────────────────────
var _secret_door_data: Array = []   # [{tile, loot_tile}]

# ── Test mode ─────────────────────────────────────────────────────────────────
var _is_test_mode: bool        = false
var _test_wave: int            = 0
var _test_spawn_queue: Array   = []
var _test_spawn_timer: float   = 0.0
var _test_wave_wait: float     = -1.0   # >0 = countdown to next wave; -1 = not waiting
var _test_arena_room: Rect2i   = Rect2i()
var _test_wave_label: Label    = null

# ── Minimap ────────────────────────────────────────────────────────────────────
const MINIMAP_SCALE  := 2.0
const MINIMAP_W      := GRID_W * MINIMAP_SCALE   # 144
const MINIMAP_H      := GRID_H * MINIMAP_SCALE   # 112
const MINIMAP_X      := 1642.0 - MINIMAP_W - 50.0
const MINIMAP_Y      := 8.0
var _minimap_dot: ColorRect = null
var _had_enemies: bool = false
var _room_cleared: bool = false

# ── BSP tree node ─────────────────────────────────────────────────────────────
class BSPNode:
	var rect: Rect2i = Rect2i()
	var room: Rect2i = Rect2i()   # only valid on leaves
	var left  = null               # BSPNode | null
	var right = null               # BSPNode | null

	func is_leaf() -> bool:
		return left == null and right == null

# ── Generation mode ───────────────────────────────────────────────────────────
enum GenMode { ROOMS, CAVE, HALLS }
var _gen_mode: GenMode = GenMode.ROOMS

# ── State ─────────────────────────────────────────────────────────────────────
var _grid: Array = []   # [y][x] → FLOOR or WALL
var _rooms: Array = []  # Array of Rect2i (tile coords), order = BSP depth-first
var _portal_tile: Vector2i = Vector2i.ZERO

# ── Entry ─────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_init_grid()

	if GameState.test_mode:
		_is_test_mode = true
		_setup_test_arena()
		return

	_roll_gen_mode()
	_generate_level()

	_build_floor_visual()
	_build_walls()

	if _gen_mode == GenMode.ROOMS:
		_place_secret_doors()

	var player_room: Rect2i = _pick_spawn_room()
	var portal_room: Rect2i = _farthest_room(player_room)
	var player_pos  := _tile_center(player_room.get_center())
	var portal_pos  := _tile_center(portal_room.get_center())

	_spawn_player(player_pos)
	_spawn_portal(portal_pos)

	var is_boss_floor := GameState.portals_used > 0 and GameState.portals_used % 5 == 4
	var is_shop_floor := GameState.portals_used > 0 and GameState.portals_used % 5 == 0

	if is_shop_floor:
		_spawn_sell_chest(portal_room)
	if is_boss_floor:
		_spawn_boss(portal_room)
	if GameState.portals_used >= 1:
		_spawn_enchant_table(player_room)

	_roll_floor_modifier()
	_spawn_traps()
	_spawn_lava_tiles()
	_spawn_enemies(player_room, portal_room if is_boss_floor else Rect2i())
	_spawn_hazard_rooms(player_room, portal_room)
	_spawn_challenge_room(player_room, portal_room if is_boss_floor else Rect2i())
	_create_minimap()

	if GameState.portals_used > 0 and GameState.portals_used % 3 == 0:
		_show_biome_banner()
	if GameState.floor_modifier != "":
		_show_modifier_banner()

	if GameState.crt_enabled:
		_spawn_crt_overlay()

# ── Test Arena ────────────────────────────────────────────────────────────────

func _setup_test_arena() -> void:
	var room := Rect2i(4, 4, GRID_W - 8, GRID_H - 8)
	_rooms.append(room)
	_carve_room(room)
	_test_arena_room = room

	_build_floor_visual()
	_build_walls()

	var center_pos := _tile_center(room.get_center())
	_spawn_player(center_pos)
	_create_minimap()
	_setup_test_wave_ui()

	if GameState.crt_enabled:
		_spawn_crt_overlay()

	# Populate first wave queue immediately (no defer — safe, only builds array)
	_start_test_wave()
	# Give player best gear on next frame so Player._ready() has finished
	call_deferred("_give_test_gear")

func _give_test_gear() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and player.has_method("_debug_best_gear"):
		player._debug_best_gear()

func _setup_test_wave_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 18
	add_child(canvas)

	var bg := ColorRect.new()
	bg.color    = Color(0.0, 0.0, 0.0, 0.55)
	bg.position = Vector2(580, 12)
	bg.size     = Vector2(440, 36)
	canvas.add_child(bg)

	_test_wave_label = Label.new()
	_test_wave_label.text = "TESTING GROUNDS  —  WAVE 1"
	_test_wave_label.position = Vector2(580, 14)
	_test_wave_label.size = Vector2(440, 32)
	_test_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_test_wave_label.add_theme_font_size_override("font_size", 18)
	_test_wave_label.add_theme_color_override("font_color", Color(0.25, 0.95, 0.85))
	canvas.add_child(_test_wave_label)

func _update_test_wave_label() -> void:
	if _test_wave_label:
		_test_wave_label.text = "TESTING GROUNDS  —  WAVE %d" % (_test_wave + 1)

func _start_test_wave() -> void:
	_test_spawn_queue.clear()
	var count := mini(100 + _test_wave * 10, 300)
	var hp_mult := 1.0 + float(_test_wave) * 0.4

	for i in count:
		var scene: PackedScene
		var r := i % 15
		if r < 4:
			scene = CHASER_SCENE
		elif r < 7:
			scene = SHOOTER_SCENE
		elif r < 9:
			scene = ENCHANTER_SCENE
		elif r < 11:
			scene = TANK_SCENE
		elif r < 13:
			scene = SNIPER_SCENE
		else:
			scene = SUMMONER_SCENE
		_test_spawn_queue.append({"scene": scene, "hp_mult": hp_mult})

	_test_spawn_queue.shuffle()
	_test_spawn_timer = 0.5

func _spawn_test_enemy(scene: PackedScene, hp_mult: float) -> void:
	var enemy := scene.instantiate()
	var center := _tile_center(_test_arena_room.get_center())
	var pos := center
	for _attempt in 60:
		var candidate := _random_pos_in_room(_test_arena_room)
		if candidate.distance_to(center) > 160.0:
			pos = candidate
			break
	enemy.position = pos
	if "max_health" in enemy:
		enemy.max_health = maxi(1, int(enemy.max_health * hp_mult))
	if "passive" in enemy:
		enemy.passive = true
	$Enemies.add_child(enemy)

func _tick_test_wave(delta: float) -> void:
	# Between-wave countdown
	if _test_wave_wait > 0.0:
		_test_wave_wait -= delta
		if _test_wave_wait <= 0.0:
			_test_wave_wait = -1.0
			_test_wave += 1
			_update_test_wave_label()
			if _test_wave_label:
				_test_wave_label.add_theme_color_override("font_color", Color(0.25, 0.95, 0.85))
			_start_test_wave()
		return

	# Spawn all queued enemies immediately
	if not _test_spawn_queue.is_empty():
		for data: Dictionary in _test_spawn_queue:
			if data.has("scene"):
				_spawn_test_enemy(data["scene"], float(data.get("hp_mult", 1.0)))
		_test_spawn_queue.clear()
		return

	# Check if all enemies dead after queue is empty
	if _test_wave_wait < 0.0:
		var all_enemies: Array = get_tree().get_nodes_in_group("enemy")
		var live := 0
		for e: Node in all_enemies:
			if not e.is_queued_for_deletion():
				live += 1
		if live == 0:
			_test_wave_wait = 2.0
			if _test_wave_label:
				_test_wave_label.text = "WAVE CLEARED! Next wave in 2s…"
				_test_wave_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))

# ── Grid ──────────────────────────────────────────────────────────────────────
func _init_grid() -> void:
	_grid.resize(GRID_H)
	for y in GRID_H:
		var row: Array = []
		row.resize(GRID_W)
		for x in GRID_W:
			row[x] = WALL
		_grid[y] = row

func _set_floor(x: int, y: int) -> void:
	if x >= 0 and x < GRID_W and y >= 0 and y < GRID_H:
		_grid[y][x] = FLOOR

func _carve_room(room: Rect2i) -> void:
	for y in range(room.position.y, room.position.y + room.size.y):
		for x in range(room.position.x, room.position.x + room.size.x):
			_set_floor(x, y)

# ── BSP ───────────────────────────────────────────────────────────────────────
func _bsp_split(rect: Rect2i) -> BSPNode:
	var node := BSPNode.new()
	node.rect = rect

	var can_h := rect.size.x >= MIN_SPLIT_W * 2
	var can_v := rect.size.y >= MIN_SPLIT_H * 2

	if not can_h and not can_v:
		return node   # leaf — too small to split

	var split_h: bool
	if can_h and can_v:
		if rect.size.x > rect.size.y + 4:
			split_h = randf() < 0.75
		elif rect.size.y > rect.size.x + 4:
			split_h = randf() < 0.25
		else:
			split_h = randf() < 0.5
	else:
		split_h = can_h

	if split_h:
		var lo := MIN_SPLIT_W
		var hi := rect.size.x - MIN_SPLIT_W
		var sp := randi_range(lo, hi)
		node.left  = _bsp_split(Rect2i(rect.position.x,        rect.position.y, sp,                    rect.size.y))
		node.right = _bsp_split(Rect2i(rect.position.x + sp,   rect.position.y, rect.size.x - sp,  rect.size.y))
	else:
		var lo := MIN_SPLIT_H
		var hi := rect.size.y - MIN_SPLIT_H
		var sp := randi_range(lo, hi)
		node.left  = _bsp_split(Rect2i(rect.position.x, rect.position.y,      rect.size.x, sp))
		node.right = _bsp_split(Rect2i(rect.position.x, rect.position.y + sp, rect.size.x, rect.size.y - sp))

	return node

@warning_ignore("integer_division")
func _bsp_place_rooms(node: BSPNode) -> void:
	if node == null:
		return
	if node.is_leaf():
		var pad := 2
		var max_w := node.rect.size.x - pad * 2
		var max_h := node.rect.size.y - pad * 2
		if max_w < 6 or max_h < 5:
			return
		# 10% chance to leave partition empty — creates varied density
		if randf() < 0.10:
			return
		# 20% chance of L-shaped room when partition is large enough
		if randf() < 0.20 and max_w >= 14 and max_h >= 10:
			_place_l_shape_room(node)
			return
		# Vary room size: allow rooms from 35–90% of partition width
		var tightness := randf()
		var min_frac: float = lerpf(0.38, 0.85, tightness)
		var min_w: int = max(6, int(float(max_w) * min_frac))
		var min_h: int = max(5, int(float(max_h) * min_frac))
		if min_w > max_w: min_w = max_w
		if min_h > max_h: min_h = max_h
		var rw := randi_range(min_w, max_w)
		var rh := randi_range(min_h, max_h)
		var rx_lo := node.rect.position.x + pad
		var rx_hi := node.rect.position.x + node.rect.size.x - rw - pad
		var ry_lo := node.rect.position.y + pad
		var ry_hi := node.rect.position.y + node.rect.size.y - rh - pad
		if rx_lo > rx_hi: rx_lo = rx_hi
		if ry_lo > ry_hi: ry_lo = ry_hi
		var rx := randi_range(rx_lo, rx_hi)
		var ry := randi_range(ry_lo, ry_hi)
		node.room = Rect2i(rx, ry, rw, rh)
		_rooms.append(node.room)
		_carve_room(node.room)
	else:
		_bsp_place_rooms(node.left)
		_bsp_place_rooms(node.right)

@warning_ignore("integer_division")
func _place_l_shape_room(node: BSPNode) -> void:
	var pad := 2
	var mw := randi_range(node.rect.size.x / 2, node.rect.size.x - pad * 2)
	var mh := randi_range(node.rect.size.y / 2, node.rect.size.y - pad * 2)
	var rx_lo := node.rect.position.x + pad
	var rx_hi := node.rect.position.x + node.rect.size.x - mw - pad
	var ry_lo := node.rect.position.y + pad
	var ry_hi := node.rect.position.y + node.rect.size.y - mh - pad
	if rx_lo > rx_hi: rx_lo = rx_hi
	if ry_lo > ry_hi: ry_lo = ry_hi
	var rx := randi_range(rx_lo, rx_hi)
	var ry := randi_range(ry_lo, ry_hi)
	var main_r := Rect2i(rx, ry, mw, mh)
	node.room = main_r
	_rooms.append(main_r)
	_carve_room(main_r)
	var wing_w := randi_range(4, maxi(4, mw / 2))
	var wing_h := randi_range(3, maxi(3, mh / 2))
	var corner := randi() % 4
	var wx: int = 0
	var wy: int = 0
	match corner:
		0: wx = rx + mw;       wy = ry + mh - wing_h
		1: wx = rx - wing_w;   wy = ry + mh - wing_h
		2: wx = rx + mw;       wy = ry
		3: wx = rx - wing_w;   wy = ry
	_carve_room(Rect2i(
		clampi(wx, 2, GRID_W - wing_w - 2),
		clampi(wy, 2, GRID_H - wing_h - 2),
		wing_w, wing_h
	))

# ── Corridors ─────────────────────────────────────────────────────────────────
func _bsp_connect(node: BSPNode) -> void:
	if node == null or node.is_leaf():
		return
	_bsp_connect(node.left)
	_bsp_connect(node.right)
	_carve_corridor(_subtree_center(node.left), _subtree_center(node.right))

@warning_ignore("integer_division")
func _subtree_center(node: BSPNode) -> Vector2i:
	if node == null:
		return Vector2i(GRID_W / 2, GRID_H / 2)
	if node.is_leaf():
		if node.room != Rect2i():
			return node.room.get_center()
		return node.rect.get_center()
	if node.left != null and node.right != null:
		var lc := _subtree_center(node.left)
		var rc := _subtree_center(node.right)
		return Vector2i((lc.x + rc.x) / 2, (lc.y + rc.y) / 2)
	if node.left != null:
		return _subtree_center(node.left)
	return _subtree_center(node.right)

func _carve_corridor(a: Vector2i, b: Vector2i) -> void:
	if randf() < 0.5:
		_carve_h_segment(a.x, b.x, a.y)
		_carve_v_segment(b.x, a.y, b.y)
	else:
		_carve_v_segment(a.x, a.y, b.y)
		_carve_h_segment(a.x, b.x, b.y)
	# 20% chance of a parallel extra corridor — creates wider paths and loops
	if randf() < 0.20:
		var offset := 3 if randf() < 0.5 else -3
		if randf() < 0.5:
			_carve_h_segment(a.x, b.x, a.y + offset)
		else:
			_carve_v_segment(a.x + offset, a.y, b.y)

func _carve_h_segment(x0: int, x1: int, y: int) -> void:
	for x in range(mini(x0, x1), maxi(x0, x1) + 1):
		_set_floor(x, y - 1)
		_set_floor(x, y)
		_set_floor(x, y + 1)

func _carve_v_segment(x: int, y0: int, y1: int) -> void:
	for y in range(mini(y0, y1), maxi(y0, y1) + 1):
		_set_floor(x - 1, y)
		_set_floor(x,     y)
		_set_floor(x + 1, y)

# ── Level generation variants ─────────────────────────────────────────────────

func _roll_gen_mode() -> void:
	var is_boss := GameState.portals_used > 0 and GameState.portals_used % 5 == 4
	var is_shop := GameState.portals_used > 0 and GameState.portals_used % 5 == 0
	if is_boss or is_shop:
		_gen_mode = GenMode.ROOMS
		return
	var r := randf()
	if r < 0.50:
		_gen_mode = GenMode.ROOMS
	elif r < 0.80:
		_gen_mode = GenMode.CAVE
	else:
		_gen_mode = GenMode.HALLS

func _generate_level() -> void:
	match _gen_mode:
		GenMode.ROOMS: _gen_rooms()
		GenMode.CAVE:  _gen_cave()
		GenMode.HALLS: _gen_halls()
	if _rooms.size() < 3:
		_init_grid()
		_rooms.clear()
		_gen_mode = GenMode.ROOMS
		_gen_rooms()

func _gen_rooms() -> void:
	var bounds := _roll_bsp_bounds()
	var root := _bsp_split(bounds)
	_bsp_place_rooms(root)
	if _rooms.is_empty():
		var fb := Rect2i(4, 4, GRID_W - 8, GRID_H - 8)
		_rooms.append(fb)
		_carve_room(fb)
	_bsp_connect(root)
	_try_secret_rooms()

@warning_ignore("integer_division")
func _roll_bsp_bounds() -> Rect2i:
	var r := randf()
	if r < 0.30:
		var w := randi_range(38, 52)
		var h := randi_range(30, 42)
		var ox := (GRID_W - w) / 2
		var oy := (GRID_H - h) / 2
		return Rect2i(ox, oy, w, h)
	return Rect2i(1, 1, GRID_W - 2, GRID_H - 2)

# ── Cave generator (cellular automata) ───────────────────────────────────────

func _gen_cave() -> void:
	for y in GRID_H:
		for x in GRID_W:
			if x <= 1 or x >= GRID_W - 2 or y <= 1 or y >= GRID_H - 2:
				_grid[y][x] = WALL
			else:
				_grid[y][x] = FLOOR if randf() < 0.47 else WALL
	for _i in 5:
		_ca_smooth_pass()
	_cull_disconnected_floor()
	_widen_cave_passages()
	_sample_cave_rooms()

func _widen_cave_passages() -> void:
	var to_open: Array = []
	for y in range(1, GRID_H - 1):
		for x in range(1, GRID_W - 1):
			if _grid[y][x] == FLOOR:
				if _grid[y - 1][x] == WALL and _grid[y + 1][x] == WALL:
					to_open.append(Vector2i(x, y - 1))
					to_open.append(Vector2i(x, y + 1))
				if _grid[y][x - 1] == WALL and _grid[y][x + 1] == WALL:
					to_open.append(Vector2i(x - 1, y))
					to_open.append(Vector2i(x + 1, y))
	for p: Vector2i in to_open:
		_set_floor(p.x, p.y)

func _ca_smooth_pass() -> void:
	var next: Array = []
	next.resize(GRID_H)
	for y in GRID_H:
		var row: Array = []
		row.resize(GRID_W)
		for x in GRID_W:
			if x <= 0 or x >= GRID_W - 1 or y <= 0 or y >= GRID_H - 1:
				row[x] = WALL
			else:
				var walls := 0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						walls += 1 if _grid[y + dy][x + dx] == WALL else 0
				row[x] = WALL if walls >= 5 else FLOOR
		next[y] = row
	_grid = next

func _cull_disconnected_floor() -> void:
	var visited: Array = []
	visited.resize(GRID_H)
	for y in GRID_H:
		var row: Array = []
		row.resize(GRID_W)
		row.fill(false)
		visited[y] = row
	var best: Array = []
	for sy in range(1, GRID_H - 1):
		for sx in range(1, GRID_W - 1):
			if _grid[sy][sx] == FLOOR and not visited[sy][sx]:
				var region: Array = []
				var stack: Array = [Vector2i(sx, sy)]
				while not stack.is_empty():
					var p: Vector2i = stack.pop_back()
					if p.x < 1 or p.x >= GRID_W - 1 or p.y < 1 or p.y >= GRID_H - 1:
						continue
					if visited[p.y][p.x] or _grid[p.y][p.x] != FLOOR:
						continue
					visited[p.y][p.x] = true
					region.append(p)
					stack.push_back(Vector2i(p.x + 1, p.y))
					stack.push_back(Vector2i(p.x - 1, p.y))
					stack.push_back(Vector2i(p.x, p.y + 1))
					stack.push_back(Vector2i(p.x, p.y - 1))
				if region.size() > best.size():
					best = region
	var keep: Dictionary = {}
	for p: Vector2i in best:
		keep[p] = true
	for y in range(1, GRID_H - 1):
		for x in range(1, GRID_W - 1):
			if _grid[y][x] == FLOOR and not keep.has(Vector2i(x, y)):
				_grid[y][x] = WALL

@warning_ignore("integer_division")
func _sample_cave_rooms() -> void:
	var step := 12
	for gy in range(step / 2, GRID_H - step / 2, step):
		for gx in range(step / 2, GRID_W - step / 2, step):
			for _att in 20:
				var tx := randi_range(maxi(1, gx - step / 2), mini(GRID_W - 2, gx + step / 2))
				var ty := randi_range(maxi(1, gy - step / 2), mini(GRID_H - 2, gy + step / 2))
				if _grid[ty][tx] == FLOOR:
					_rooms.append(Rect2i(tx - 2, ty - 2, 5, 5))
					break

# ── Halls generator (few large rooms, wide corridors) ─────────────────────────

func _gen_halls() -> void:
	var num_rooms := randi_range(4, 7)
	var placed: Array = []
	for _i in num_rooms * 5:
		if placed.size() >= num_rooms:
			break
		var w := randi_range(14, 26)
		var h := randi_range(10, 18)
		var x := randi_range(3, GRID_W - w - 3)
		var y := randi_range(3, GRID_H - h - 3)
		var room := Rect2i(x, y, w, h)
		var ok := true
		for pr in placed:
			var prr: Rect2i = pr
			var bloat := Rect2i(prr.position.x - 6, prr.position.y - 6,
				prr.size.x + 12, prr.size.y + 12)
			if bloat.intersects(room):
				ok = false
				break
		if ok:
			placed.append(room)
			_rooms.append(room)
			_carve_room(room)
	for i in range(1, placed.size()):
		var a: Rect2i = placed[i - 1]
		var b: Rect2i = placed[i]
		_carve_wide_corridor(a.get_center(), b.get_center(), randi_range(2, 3))
	if placed.size() >= 3:
		var fa: Rect2i = placed[placed.size() - 1]
		var fb: Rect2i = placed[0]
		_carve_wide_corridor(fa.get_center(), fb.get_center(), 2)

func _carve_wide_corridor(a: Vector2i, b: Vector2i, hw: int) -> void:
	if randf() < 0.5:
		for dy in range(-hw, hw + 1):
			for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
				_set_floor(x, a.y + dy)
		for dx in range(-hw, hw + 1):
			for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
				_set_floor(b.x + dx, y)
	else:
		for dx in range(-hw, hw + 1):
			for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
				_set_floor(a.x + dx, y)
		for dy in range(-hw, hw + 1):
			for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
				_set_floor(x, b.y + dy)

# ── Spawn room selection ──────────────────────────────────────────────────────

func _pick_spawn_room() -> Rect2i:
	var eligible: Array = []
	for r in _rooms:
		var room: Rect2i = r
		if room.size.x >= 5 and room.size.y >= 4:
			eligible.append(room)
	if eligible.is_empty():
		return _rooms[0] if not _rooms.is_empty() else Rect2i(4, 4, 8, 8)
	return eligible[randi() % eligible.size()]

# ── Floor visual ──────────────────────────────────────────────────────────────
func _build_floor_visual() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = FLOOR_SHADER
	mat.set_shader_parameter("node_size", Vector2(GRID_W * TILE, GRID_H * TILE))

	var floor_rect := ColorRect.new()
	floor_rect.position = Vector2.ZERO
	floor_rect.size = Vector2(GRID_W * TILE, GRID_H * TILE)
	floor_rect.material = mat
	floor_rect.z_index = -20
	floor_rect.modulate = BIOME_FLOOR_TINTS[GameState.biome]
	add_child(floor_rect)

# ── Wall building (scanline batch) ────────────────────────────────────────────
func _build_walls() -> void:
	var wall_col: Color = BIOME_WALL_COLORS[GameState.biome]
	for y in GRID_H:
		var x_start := -1
		for x in GRID_W:
			if _grid[y][x] == WALL:
				if x_start == -1:
					x_start = x
			else:
				if x_start != -1:
					_make_wall_strip(x_start, y, x - x_start, wall_col)
					x_start = -1
		if x_start != -1:
			_make_wall_strip(x_start, y, GRID_W - x_start, wall_col)

func _make_wall_strip(tx: int, ty: int, tw: int, wall_col: Color = Color(0.12, 0.10, 0.18)) -> void:
	var pw := float(tw * TILE)
	var ph := float(TILE)
	var cx := float(tx * TILE) + pw * 0.5
	var cy := float(ty * TILE) + ph * 0.5

	var body := StaticBody2D.new()
	body.position = Vector2(cx, cy)
	body.z_index = -5

	var cshape := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = Vector2(pw, ph)
	cshape.shape = rect_shape
	body.add_child(cshape)

	var vis := ColorRect.new()
	vis.color = wall_col
	vis.offset_left   = -pw * 0.5
	vis.offset_top    = -ph * 0.5
	vis.offset_right  =  pw * 0.5
	vis.offset_bottom =  ph * 0.5
	body.add_child(vis)

	add_child(body)

# ── Helpers ───────────────────────────────────────────────────────────────────
func _tile_center(tile: Vector2i) -> Vector2:
	return Vector2(float(tile.x) * TILE + TILE * 0.5, float(tile.y) * TILE + TILE * 0.5)

func _farthest_room(from_room: Rect2i) -> Rect2i:
	var from_c := Vector2(from_room.get_center())
	var best   := from_room
	var best_d := 0.0
	for _r in _rooms:
		var room: Rect2i = _r
		var d := from_c.distance_to(Vector2(room.get_center()))
		if d > best_d:
			best_d = d
			best   = room
	return best

func _random_pos_in_room(room: Rect2i) -> Vector2:
	# Validate against the actual grid so enemies never land on a wall tile.
	for _attempt in 30:
		var tx := randi_range(room.position.x + 1, room.position.x + room.size.x - 2)
		var ty := randi_range(room.position.y + 1, room.position.y + room.size.y - 2)
		if tx >= 0 and tx < GRID_W and ty >= 0 and ty < GRID_H:
			if _grid[ty][tx] == FLOOR:
				return _tile_center(Vector2i(tx, ty))
	return _tile_center(room.get_center())   # fallback: dead-centre of room

# ── Spawners ──────────────────────────────────────────────────────────────────
func _spawn_player(pos: Vector2) -> void:
	var player := PLAYER_SCENE.instantiate()
	player.position = pos
	var cam := player.get_node_or_null("Camera2D")
	if cam:
		cam.limit_right  = GRID_W * TILE
		cam.limit_bottom = GRID_H * TILE
		cam.position_smoothing_enabled = true
		cam.position_smoothing_speed = 8.0
	add_child(player)

func _spawn_portal(pos: Vector2) -> void:
	_portal_tile = Vector2i(int(pos.x / float(TILE)), int(pos.y / float(TILE)))
	var portal := PORTAL_SCENE.instantiate()
	portal.position = pos
	add_child(portal)

# Returns a pixel-center position safely inside a room, with an optional tile offset
# clamped so it never lands on a wall.
func _safe_pos_in_room(room: Rect2i, dx: int = 0, dy: int = 0) -> Vector2:
	var cx := clampi(room.get_center().x + dx,
		room.position.x + 1, room.position.x + room.size.x - 2)
	var cy := clampi(room.get_center().y + dy,
		room.position.y + 1, room.position.y + room.size.y - 2)
	if _grid[cy][cx] != FLOOR:
		cx = room.get_center().x
		cy = room.get_center().y
	return _tile_center(Vector2i(cx, cy))

func _spawn_sell_chest(room: Rect2i) -> void:
	var chest := SELL_CHEST_SCENE.instantiate()
	chest.position = _safe_pos_in_room(room, 2, 0)
	add_child(chest)

@warning_ignore("integer_division")
func _spawn_enemies(player_room: Rect2i, skip_room: Rect2i = Rect2i()) -> void:
	var diff        := GameState.difficulty
	var health_mult := 1.0 + diff * 0.2

	for _r in _rooms:
		var room: Rect2i = _r
		if room == player_room or room == skip_room:
			continue
		if room.size.x < 4 or room.size.y < 4:
			continue

		var area: int   = room.size.x * room.size.y
		var budget: int = max(1, area / 20 + int(diff))

		var n_chasers: int    = randi_range(0, min(budget, 3 + int(diff)))
		budget = max(0, budget - n_chasers)
		var n_shooters: int   = randi_range(0, min(budget, 2 + int(diff * 0.5)))
		budget = max(0, budget - n_shooters)
		var n_enchanters: int = randi_range(0, min(budget, 1 + int(diff * 0.3)))
		budget = max(0, budget - n_enchanters)
		var n_tanks: int      = randi_range(0, min(budget, 1 + int(diff * 0.3)))
		budget = max(0, budget - n_tanks)
		var n_snipers: int    = randi_range(0, min(budget, 1 + int(diff * 0.3)))
		budget = max(0, budget - n_snipers)
		var n_summoners: int  = randi_range(0, min(budget, 1 + int(diff * 0.2)))

		for _i in n_chasers:
			_place_enemy(CHASER_SCENE, room, health_mult)
		for _i in n_shooters:
			_place_enemy(SHOOTER_SCENE, room, health_mult)
		for _i in n_enchanters:
			_place_enemy(ENCHANTER_SCENE, room, health_mult)
		for _i in n_tanks:
			_place_enemy(TANK_SCENE, room, health_mult)
		for _i in n_snipers:
			_place_enemy(SNIPER_SCENE, room, health_mult)
		for _i in n_summoners:
			_place_enemy(SUMMONER_SCENE, room, health_mult)

func _place_enemy(scene: PackedScene, room: Rect2i, health_mult: float) -> void:
	var enemy := scene.instantiate()
	enemy.position = _random_pos_in_room(room)
	if health_mult != 1.0 and "max_health" in enemy:
		enemy.max_health = maxi(1, int(enemy.max_health * health_mult))

	# 15% chance of elite: doubled HP, random modifier
	if randf() < 0.15 and "is_elite" in enemy:
		enemy.is_elite = true
		if "max_health" in enemy:
			enemy.max_health = maxi(1, enemy.max_health * 2)
		if "elite_modifier" in enemy:
			var mod := randi_range(1, 3)
			enemy.elite_modifier = mod
			if mod == 2 and "_split_scene" in enemy:
				enemy._split_scene = scene
		enemy.set_meta("_make_elite_visual", true)

	$Enemies.add_child(enemy)

	_apply_biome_debuffs(enemy)
	_apply_floor_modifier_to_enemy(enemy)

	# Apply elite visual now that the node is in the tree
	if enemy.get_meta("_make_elite_visual", false):
		var lbl := enemy.get_node_or_null("AsciiChar")
		if lbl:
			var mod: int = enemy.get("elite_modifier") if "elite_modifier" in enemy else 0
			var elite_col: Color
			var elite_out: Color
			match mod:
				1:  # Shielded – icy blue
					elite_col = Color(0.5, 0.9, 1.0)
					elite_out = Color(0.0, 0.3, 0.5)
				2:  # Splitting – purple
					elite_col = Color(0.85, 0.4, 1.0)
					elite_out = Color(0.3, 0.0, 0.4)
				3:  # Enraged – orange
					elite_col = Color(1.0, 0.55, 0.0)
					elite_out = Color(0.5, 0.15, 0.0)
				_:
					elite_col = Color(1.0, 0.75, 0.0)
					elite_out = Color(0.5, 0.2, 0.0)
			lbl.add_theme_color_override("font_color", elite_col)
			lbl.add_theme_color_override("font_outline_color", elite_out)
			var mod_names := ["", "SHIELDED", "SPLITTING", "ENRAGED"]
			if mod > 0:
				FloatingText.spawn_str(enemy.global_position + Vector2(0.0, -24.0), mod_names[mod], elite_col, get_tree().current_scene)

# ── Floor modifier roll & application ────────────────────────────────────────

func _roll_floor_modifier() -> void:
	var is_boss := GameState.portals_used > 0 and GameState.portals_used % 5 == 4
	var is_shop := GameState.portals_used > 0 and GameState.portals_used % 5 == 0
	GameState.floor_modifier = ""
	if is_boss or is_shop:
		return
	if randf() > 0.55:
		return
	var keys := FLOOR_MODIFIERS.keys()
	GameState.floor_modifier = keys[randi() % keys.size()]

func _apply_floor_modifier_to_enemy(enemy: Node) -> void:
	match GameState.floor_modifier:
		"cursed":
			if "speed" in enemy:
				enemy.speed = enemy.speed * 1.5
			if "move_speed" in enemy:
				enemy.move_speed = enemy.move_speed * 1.5
		"bloodlust":
			if "max_health" in enemy:
				enemy.max_health = maxi(1, enemy.max_health * 2)
		"haunted":
			if "is_elite" in enemy and not enemy.is_elite:
				enemy.is_elite = true
				if "max_health" in enemy:
					enemy.max_health = maxi(1, enemy.max_health * 2)
				if "elite_modifier" in enemy:
					enemy.elite_modifier = randi_range(1, 3)

func _show_modifier_banner() -> void:
	if not GameState.floor_modifier in FLOOR_MODIFIERS:
		return
	var mod: Dictionary = FLOOR_MODIFIERS[GameState.floor_modifier]
	var canvas := CanvasLayer.new()
	canvas.layer = 20
	get_tree().current_scene.add_child(canvas)

	var lbl := Label.new()
	lbl.text = "[ %s ]\n%s" % [mod["name"], mod["desc"]]
	lbl.position = Vector2(440.0, 370.0)
	lbl.size = Vector2(720.0, 80.0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.7, 0.1))
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	lbl.add_theme_constant_override("outline_size", 3)
	canvas.add_child(lbl)

	var tw := lbl.create_tween()
	tw.tween_interval(1.5)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.2)
	tw.tween_callback(canvas.queue_free)

# ── Biome debuffs ──────────────────────────────────────────────────────────────

func _apply_biome_debuffs(enemy: Node) -> void:
	if GameState.biome == 2:  # Ice Cavern — enemies start pre-frozen
		enemy.set("_chill_stacks", 8)
		enemy.set("_frozen", true)
		enemy.set("_frozen_timer", 5.0)
		if not enemy.get("is_elite"):  # elites get their own tint below
			var lbl := enemy.get_node_or_null("AsciiChar")
			if lbl:
				lbl.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
				lbl.add_theme_color_override("font_outline_color", Color(0.1, 0.3, 0.6))

# ── Hazard rooms ──────────────────────────────────────────────────────────────

func _spawn_hazard_rooms(player_room: Rect2i, skip_room: Rect2i) -> void:
	var candidates: Array = []
	for _r in _rooms:
		var room: Rect2i = _r
		if room == player_room or room == skip_room:
			continue
		if room.size.x < 6 or room.size.y < 5:
			continue
		candidates.append(room)
	candidates.shuffle()
	var count := mini(randi_range(1, 2), candidates.size())
	for i in count:
		_make_hazard_room(candidates[i])

func _make_hazard_room(room: Rect2i) -> void:
	var tint := ColorRect.new()
	tint.color = Color(0.7, 0.6, 0.1, 0.18)
	tint.position = Vector2(room.position.x * TILE, room.position.y * TILE)
	tint.size = Vector2(room.size.x * TILE, room.size.y * TILE)
	tint.z_index = -10
	add_child(tint)

	for _i in randi_range(5, 9):
		for _attempt in 10:
			var tx := randi_range(room.position.x + 1, room.position.x + room.size.x - 2)
			var ty := randi_range(room.position.y + 1, room.position.y + room.size.y - 2)
			if _grid[ty][tx] == FLOOR:
				var trap := SPIKE_TRAP_SCENE.instantiate()
				trap.position = _tile_center(Vector2i(tx, ty))
				add_child(trap)
				break

	var bag := LOOT_BAG_SCENE.instantiate()
	bag.position = _tile_center(room.get_center())
	bag.set("items", [ItemDB.random_drop(), ItemDB.random_drop(), ItemDB.random_legendary()])
	add_child(bag)

# ── Challenge room (champion encounter) ───────────────────────────────────────

func _spawn_challenge_room(player_room: Rect2i, skip_room: Rect2i) -> void:
	var candidates: Array = []
	for _r in _rooms:
		var room: Rect2i = _r
		if room == player_room or room == skip_room:
			continue
		if room.size.x < 7 or room.size.y < 6:
			continue
		candidates.append(room)
	if candidates.is_empty():
		return
	candidates.shuffle()
	var room: Rect2i = candidates[0]

	var tint := ColorRect.new()
	tint.color = Color(0.7, 0.05, 0.05, 0.18)
	tint.position = Vector2(room.position.x * TILE, room.position.y * TILE)
	tint.size = Vector2(room.size.x * TILE, room.size.y * TILE)
	tint.z_index = -10
	add_child(tint)

	var type_scenes: Array = [CHASER_SCENE, TANK_SCENE, SHOOTER_SCENE, SNIPER_SCENE]
	var champ_scene: PackedScene = type_scenes[randi() % type_scenes.size()]
	var champion := champ_scene.instantiate()
	champion.position = _tile_center(room.get_center())
	if "max_health" in champion:
		champion.max_health = maxi(1, champion.max_health * 6)
	if "is_elite" in champion:
		champion.is_elite = true
	if "elite_modifier" in champion:
		champion.elite_modifier = 3
	if "_shield_active" in champion:
		champion._shield_active = true
	if "is_champion" in champion:
		champion.is_champion = true
	$Enemies.add_child(champion)
	var lbl := champion.get_node_or_null("AsciiChar")
	if lbl:
		lbl.add_theme_color_override("font_color",      Color(1.0, 0.15, 0.15))
		lbl.add_theme_color_override("font_outline_color", Color(0.4, 0.0, 0.0))
		lbl.add_theme_constant_override("outline_size",  4)
	FloatingText.spawn_str(_tile_center(room.get_center()), "CHAMPION!", Color(1.0, 0.15, 0.15), get_tree().current_scene)

# ── Lava tiles (Lava Rift biome) ───────────────────────────────────────────────

func _spawn_lava_tiles() -> void:
	if GameState.biome != 3:
		return
	var count := randi_range(10, 18)
	var placed := 0
	var shuffled := _rooms.duplicate()
	shuffled.shuffle()
	for _r in shuffled:
		if placed >= count:
			break
		var room: Rect2i = _r
		if room == _rooms[0]:
			continue
		for _attempt in 5:
			var tx := randi_range(room.position.x + 1, room.position.x + room.size.x - 2)
			var ty := randi_range(room.position.y + 1, room.position.y + room.size.y - 2)
			if _grid[ty][tx] == FLOOR:
				var tile: Node = LAVA_TILE_SCRIPT.new()
				tile.position = _tile_center(Vector2i(tx, ty))
				add_child(tile)
				placed += 1
				break

# ── Boss ──────────────────────────────────────────────────────────────────────

func _spawn_boss(room: Rect2i) -> void:
	var boss := BOSS_SCENE.instantiate()
	boss.position = _tile_center(room.get_center())
	var diff := GameState.difficulty
	if "max_health" in boss:
		boss.max_health = int(40.0 * (1.0 + diff * 0.25))
	$Enemies.add_child(boss)

# ── Traps ─────────────────────────────────────────────────────────────────────

func _spawn_traps() -> void:
	var diff := GameState.difficulty
	var trap_count: int = randi_range(1, 2 + int(diff * 0.5))
	var tried := 0
	for _r in _rooms:
		var room: Rect2i = _r
		if room == _rooms[0]:
			continue   # never in player spawn room
		if tried >= trap_count:
			break
		# Place trap near room edge
		for _attempt in 6:
			var tx := randi_range(room.position.x + 1, room.position.x + room.size.x - 2)
			var ty := randi_range(room.position.y + 1, room.position.y + room.size.y - 2)
			if _grid[ty][tx] == FLOOR:
				var trap := SPIKE_TRAP_SCENE.instantiate()
				trap.position = _tile_center(Vector2i(tx, ty))
				add_child(trap)
				tried += 1
				break

# ── Secret rooms ──────────────────────────────────────────────────────────────

func _try_secret_rooms() -> void:
	var candidates := _rooms.duplicate()
	candidates.shuffle()
	var spawned := 0
	for _r in candidates:
		if spawned >= 2:
			break
		var room: Rect2i = _r
		if room == _rooms[0]:
			continue
		if _try_secret_off_room(room):
			spawned += 1

@warning_ignore("integer_division")
func _try_secret_off_room(base: Rect2i) -> bool:
	# Try east side only (simplest, least likely to go OOB)
	var sx := base.position.x + base.size.x + 1
	var sy := base.position.y + base.size.y / 2 - 2
	var sw := 6
	var sh := 5
	var entrance := Vector2i(base.position.x + base.size.x, base.position.y + base.size.y / 2)

	if sx + sw + 1 >= GRID_W or sy < 2 or sy + sh + 1 >= GRID_H:
		return false

	# Make sure all tiles are walls (no overlap)
	for ty in range(sy, sy + sh):
		for tx in range(sx, sx + sw):
			if tx < 0 or tx >= GRID_W or ty < 0 or ty >= GRID_H:
				return false
			if _grid[ty][tx] == FLOOR:
				return false

	# Carve the secret room and a 3-tile-wide entrance
	for ty in range(sy, sy + sh):
		for tx in range(sx, sx + sw):
			_set_floor(tx, ty)
	_set_floor(entrance.x, entrance.y - 1)
	_set_floor(entrance.x, entrance.y)
	_set_floor(entrance.x, entrance.y + 1)

	var loot_tile := Vector2i(sx + sw / 2, sy + sh / 2)
	_secret_door_data.append({"entrance": entrance, "loot_tile": loot_tile})
	return true

func _place_secret_doors() -> void:
	var wall_col: Color = BIOME_WALL_COLORS[GameState.biome]
	for data in _secret_door_data:
		var entrance: Vector2i = data["entrance"]
		var loot_tile: Vector2i = data["loot_tile"]

		var door: Node = SECRET_DOOR_SCENE.instantiate()
		door.set("wall_color", wall_col)
		door.set("loot_world_pos", _tile_center(loot_tile))
		door.set("loot_items", [ItemDB.random_legendary(), ItemDB.random_drop(), ItemDB.random_drop()])
		door.position = _tile_center(entrance)
		add_child(door)

		# Cover the secret room so it can't be seen until the door opens.
		# Room starts 1 tile east of entrance, 2 tiles north — 6×5 tiles.
		var cover := ColorRect.new()
		cover.color = wall_col
		cover.position = Vector2(16.0, -80.0)   # door-local: right edge of entrance, 2 tiles up
		cover.size = Vector2(192.0, 160.0)       # 6×5 tiles
		cover.z_index = 2
		door.add_child(cover)

# ── Enchant table ──────────────────────────────────────────────────────────────

func _spawn_enchant_table(player_room: Rect2i) -> void:
	var table := ENCHANT_TABLE_SCENE.instantiate()
	table.position = _safe_pos_in_room(player_room, 3, 0)
	add_child(table)

# ── Biome banner ──────────────────────────────────────────────────────────────

func _show_biome_banner() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 20
	get_tree().current_scene.add_child(canvas)

	var lbl := Label.new()
	lbl.text = "— " + BIOME_NAMES[GameState.biome] + " —"
	lbl.position = Vector2(540.0, 400.0)
	lbl.size = Vector2(520.0, 48.0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 30)
	lbl.add_theme_color_override("font_color", BIOME_FLOOR_TINTS[GameState.biome].lightened(0.3))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 3)
	canvas.add_child(lbl)

	var tw := lbl.create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.2)
	tw.tween_callback(canvas.queue_free)

# ── Minimap ───────────────────────────────────────────────────────────────────

func _create_minimap() -> void:
	# Build a pixel image from the grid (1 px per tile) then scale it up
	var img := Image.create(GRID_W, GRID_H, false, Image.FORMAT_RGBA8)
	var floor_col := Color(0.28, 0.25, 0.42, 1.0)
	var wall_col  := Color(0.04, 0.04, 0.08, 0.0)  # transparent = background shows
	for y in GRID_H:
		for x in GRID_W:
			img.set_pixel(x, y, floor_col if _grid[y][x] == FLOOR else wall_col)

	var texture := ImageTexture.create_from_image(img)

	var canvas := CanvasLayer.new()
	canvas.layer = 15
	add_child(canvas)

	# Dark surround border
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.06, 0.88)
	bg.position = Vector2(MINIMAP_X - 2.0, MINIMAP_Y - 2.0)
	bg.size = Vector2(MINIMAP_W + 4.0, MINIMAP_H + 4.0)
	canvas.add_child(bg)

	# Floor/corridor map image
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.position = Vector2(MINIMAP_X, MINIMAP_Y)
	sprite.scale = Vector2(MINIMAP_SCALE, MINIMAP_SCALE)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.add_child(sprite)

	# Portal dot (static)
	var portal_dot := ColorRect.new()
	portal_dot.size = Vector2(4.0, 4.0)
	portal_dot.color = Color(0.3, 1.0, 0.3, 0.9)
	portal_dot.position = Vector2(
		MINIMAP_X + float(_portal_tile.x) * MINIMAP_SCALE - 2.0,
		MINIMAP_Y + float(_portal_tile.y) * MINIMAP_SCALE - 2.0)
	canvas.add_child(portal_dot)

	# Biome + floor label
	var biome_lbl := Label.new()
	var gen_tag := " [C]" if _gen_mode == GenMode.CAVE else (" [H]" if _gen_mode == GenMode.HALLS else "")
	var mod_tag := (" [%s]" % GameState.floor_modifier.to_upper()) if GameState.floor_modifier != "" else ""
	biome_lbl.text = BIOME_NAMES[GameState.biome] + "  F" + str(GameState.portals_used + 1) + gen_tag + mod_tag
	biome_lbl.position = Vector2(MINIMAP_X, MINIMAP_Y + MINIMAP_H + 2.0)
	biome_lbl.size = Vector2(MINIMAP_W, 14.0)
	biome_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	biome_lbl.add_theme_font_size_override("font_size", 10)
	biome_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.7))
	canvas.add_child(biome_lbl)

	# Legend
	var legend := Label.new()
	legend.text = "● you   ● portal"
	legend.position = Vector2(MINIMAP_X, MINIMAP_Y + MINIMAP_H + 16.0)
	legend.size = Vector2(MINIMAP_W, 10.0)
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legend.add_theme_font_size_override("font_size", 8)
	legend.add_theme_color_override("font_color", Color(0.38, 0.38, 0.5))
	canvas.add_child(legend)

	# Player dot (position updated in _process)
	_minimap_dot = ColorRect.new()
	_minimap_dot.size = Vector2(4.0, 4.0)
	_minimap_dot.color = Color(0.3, 1.0, 0.9, 1.0)
	canvas.add_child(_minimap_dot)

# ── CRT overlay ───────────────────────────────────────────────────────────────

const CRT_SHADER = preload("res://shaders/crt_overlay.gdshader")

func _spawn_crt_overlay() -> void:
	if get_node_or_null("CRTOverlay") != null:
		return
	var canvas := CanvasLayer.new()
	canvas.name  = "CRTOverlay"
	canvas.layer = 30
	add_child(canvas)
	var overlay := ColorRect.new()
	overlay.name          = "Rect"
	overlay.size          = Vector2(1600.0, 900.0)
	overlay.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = CRT_SHADER
	overlay.material = mat
	canvas.add_child(overlay)

func _apply_crt_state() -> void:
	var existing := get_node_or_null("CRTOverlay")
	if GameState.crt_enabled:
		if existing == null:
			_spawn_crt_overlay()
	else:
		if existing != null:
			existing.queue_free()

func _on_room_cleared() -> void:
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if not is_instance_valid(player):
		return
	FloatingText.spawn_str(player.global_position + Vector2(0.0, -70.0), "ROOM CLEARED!", Color(1.0, 0.92, 0.2), get_tree().current_scene)
	for _i in 4:
		var gold := GOLD_PICKUP_SCENE.instantiate()
		gold.global_position = player.global_position + Vector2(randf_range(-56.0, 56.0), randf_range(-40.0, 40.0))
		gold.value = int(randi_range(4, 10) * GameState.loot_multiplier)
		get_tree().current_scene.add_child(gold)

func _process(delta: float) -> void:
	if _is_test_mode:
		_tick_test_wave(delta)

	if not _room_cleared and not _is_test_mode:
		var enemy_count := get_tree().get_nodes_in_group("enemy").size()
		if not _had_enemies:
			if enemy_count > 0:
				_had_enemies = true
		elif enemy_count == 0:
			_room_cleared = true
			_on_room_cleared()

	if _minimap_dot == null:
		return
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if not is_instance_valid(player):
		return
	var tile_pos: Vector2 = player.global_position / float(TILE)
	_minimap_dot.position = Vector2(
		MINIMAP_X + tile_pos.x * MINIMAP_SCALE - 2.0,
		MINIMAP_Y + tile_pos.y * MINIMAP_SCALE - 2.0
	)
