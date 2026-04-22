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
const BOSS_SCENE         = preload("res://scenes/EnemyBoss.tscn")
const SPIKE_TRAP_SCENE   = preload("res://scenes/SpikeTrap.tscn")
const SECRET_DOOR_SCENE  = preload("res://scenes/SecretDoor.tscn")
const ENCHANT_TABLE_SCENE= preload("res://scenes/EnchantTable.tscn")
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

# ── Secret door tracking ───────────────────────────────────────────────────────
var _secret_door_data: Array = []   # [{tile, loot_tile}]

# ── Minimap ────────────────────────────────────────────────────────────────────
const MINIMAP_SCALE  := 2.0
const MINIMAP_W      := GRID_W * MINIMAP_SCALE   # 144
const MINIMAP_H      := GRID_H * MINIMAP_SCALE   # 112
const MINIMAP_X      := 1642.0 - MINIMAP_W - 50.0
const MINIMAP_Y      := 8.0
var _minimap_dot: ColorRect = null

# ── BSP tree node ─────────────────────────────────────────────────────────────
class BSPNode:
	var rect: Rect2i = Rect2i()
	var room: Rect2i = Rect2i()   # only valid on leaves
	var left  = null               # BSPNode | null
	var right = null               # BSPNode | null

	func is_leaf() -> bool:
		return left == null and right == null

# ── State ─────────────────────────────────────────────────────────────────────
var _grid: Array = []   # [y][x] → FLOOR or WALL
var _rooms: Array = []  # Array of Rect2i (tile coords), order = BSP depth-first

# ── Entry ─────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_init_grid()

	var root_rect := Rect2i(1, 1, GRID_W - 2, GRID_H - 2)
	var root := _bsp_split(root_rect)
	_bsp_place_rooms(root)

	if _rooms.is_empty():
		var fb := Rect2i(4, 4, GRID_W - 8, GRID_H - 8)
		_rooms.append(fb)
		_carve_room(fb)

	_bsp_connect(root)
	_try_secret_rooms()   # carve hidden rooms before walls are built

	_build_floor_visual()
	_build_walls()
	_place_secret_doors() # physical doors on top of open floor tiles

	var player_room: Rect2i = _rooms[0]
	var portal_room: Rect2i = _farthest_room(player_room)
	var player_pos  := _tile_center(player_room.get_center())
	var portal_pos  := _tile_center(portal_room.get_center())

	_spawn_player(player_pos)
	_spawn_portal(portal_pos)

	var is_boss_floor := GameState.portals_used > 0 and GameState.portals_used % 5 == 4
	var is_shop_floor := GameState.portals_used > 0 and GameState.portals_used % 5 == 0

	if is_shop_floor:
		_spawn_sell_chest(portal_pos + Vector2(float(TILE) * 2.5, 0.0))
	if is_boss_floor:
		_spawn_boss(portal_room)
	if GameState.portals_used >= 1:
		_spawn_enchant_table(player_room)

	_spawn_traps()
	_spawn_lava_tiles()
	_spawn_enemies(player_room, portal_room if is_boss_floor else Rect2i())
	_create_minimap()

	# Biome name banner on first frame of a new biome
	if GameState.portals_used > 0 and GameState.portals_used % 3 == 0:
		_show_biome_banner()

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
		var min_w: int = max(6, max_w * 2 / 3)
		var min_h: int = max(5, max_h * 2 / 3)
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
	# Randomly pick one of two L-shapes to add variety
	if randf() < 0.5:
		_carve_h_segment(a.x, b.x, a.y)
		_carve_v_segment(b.x, a.y, b.y)
	else:
		_carve_v_segment(a.x, a.y, b.y)
		_carve_h_segment(a.x, b.x, b.y)

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
	add_child(player)

func _spawn_portal(pos: Vector2) -> void:
	var portal := PORTAL_SCENE.instantiate()
	portal.position = pos
	add_child(portal)

func _spawn_sell_chest(pos: Vector2) -> void:
	var chest := SELL_CHEST_SCENE.instantiate()
	chest.position = pos
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

		for _i in n_chasers:
			_place_enemy(CHASER_SCENE, room, health_mult)
		for _i in n_shooters:
			_place_enemy(SHOOTER_SCENE, room, health_mult)
		for _i in n_enchanters:
			_place_enemy(ENCHANTER_SCENE, room, health_mult)

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

	# Carve the secret room and the entrance tile
	for ty in range(sy, sy + sh):
		for tx in range(sx, sx + sw):
			_set_floor(tx, ty)
	_set_floor(entrance.x, entrance.y)

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
		door.position = _tile_center(entrance)
		add_child(door)

		var bag: Node = preload("res://scenes/LootBag.tscn").instantiate()
		bag.position = _tile_center(loot_tile)
		bag.set("items", [ItemDB.random_legendary(), ItemDB.random_drop(), ItemDB.random_drop()])
		add_child(bag)

# ── Enchant table ──────────────────────────────────────────────────────────────

func _spawn_enchant_table(player_room: Rect2i) -> void:
	var table := ENCHANT_TABLE_SCENE.instantiate()
	var center := player_room.get_center()
	# Offset slightly so it doesn't overlap the player spawn
	table.position = _tile_center(Vector2i(center.x + 3, center.y))
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

	# Biome label below map
	var biome_lbl := Label.new()
	biome_lbl.text = BIOME_NAMES[GameState.biome] + "  F" + str(GameState.portals_used + 1)
	biome_lbl.position = Vector2(MINIMAP_X, MINIMAP_Y + MINIMAP_H + 2.0)
	biome_lbl.size = Vector2(MINIMAP_W, 14.0)
	biome_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	biome_lbl.add_theme_font_size_override("font_size", 10)
	biome_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.7))
	canvas.add_child(biome_lbl)

	# Player dot (position updated in _process)
	_minimap_dot = ColorRect.new()
	_minimap_dot.size = Vector2(4.0, 4.0)
	_minimap_dot.color = Color(0.3, 1.0, 0.9, 1.0)
	canvas.add_child(_minimap_dot)

func _process(_delta: float) -> void:
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
