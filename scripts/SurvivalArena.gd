extends Node2D

# Themed-room controller that runs a constant-spawn DPS check inside the
# room rect it's handed. Idle (cosmetic only) until the player first
# enters the room — then a timer starts, spawn portals appear at the
# four corners, and waves of biome-appropriate enemies pour out. Survive
# until the timer hits zero to bank a chunky loot bag in the centre and
# unlock. The room visibly tints red while the trial is active so the
# player can see they're locked in.
#
# Set by the caller (World._make_themed_room) before adding to the scene:
#   - room        : Rect2i        — tile rect of the themed room
#   - hp_mult     : float         — base HP multiplier (passed to placed enemies)
#   - theme_color : Color         — accent color for the banner / portal tint

const TILE: int = 32

# Enemy roster — kept light on bullet-hell so the timer is winnable. The
# biome-flavoured override below swaps a couple slots per biome.
const SPIDER_SCENE     = preload("res://scenes/EnemySpider.tscn")
const CHASER_SCENE     = preload("res://scenes/EnemyChaser.tscn")
const SHOOTER_SCENE    = preload("res://scenes/EnemyShooter.tscn")
const ARCHER_SCENE     = preload("res://scenes/EnemyArcher.tscn")
const CHARGER_SCENE    = preload("res://scenes/EnemyCharger.tscn")
const BOMBER_SCENE     = preload("res://scenes/EnemyBomber.tscn")
const PHANTOM_SCENE    = preload("res://scenes/EnemyPhantom.tscn")
const BERSERKER_SCENE  = preload("res://scenes/EnemyBerserker.tscn")
const FROSTSENT_SCENE  = preload("res://scenes/EnemyFrostSentinel.tscn")
const MAGMASLUG_SCENE  = preload("res://scenes/EnemyMagmaSlug.tscn")
const LOOT_BAG_SCENE   = preload("res://scenes/LootBag.tscn")
const GOLD_PICKUP_SCENE = preload("res://scenes/GoldPickup.tscn")

const DURATION_BASE: float    = 45.0   # base trial length in seconds
const SPAWN_INTERVAL_START: float = 1.6
const SPAWN_INTERVAL_END: float   = 0.55  # ramp down: faster spawns over time
const MAX_CONCURRENT: int     = 14   # cap so the room doesn't lock up
const ARM_RADIUS_PX: float    = 80.0  # how close the player needs to be to start

var room: Rect2i      = Rect2i()
var hp_mult: float    = 1.0
var theme_color: Color = Color(1.0, 0.4, 0.3)

var _armed: bool      = false
var _active: bool     = false
var _completed: bool  = false
var _time_left: float = DURATION_BASE
var _spawn_t: float   = 0.0
var _player: Node2D   = null
var _spawn_portals: Array = []   # Array[Node2D]
var _spawned_alive: Array = []   # tracked spawned enemies still alive
var _hud_canvas: CanvasLayer = null
var _hud_label: Label = null
var _tint_rect: ColorRect = null
var _banner_label: Label = null

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	# Visible centre marker so the player knows there's *something* here
	# even before the trial arms. Reuses the room tint colour at low alpha.
	_tint_rect = ColorRect.new()
	_tint_rect.color = Color(theme_color.r, theme_color.g, theme_color.b, 0.08)
	_tint_rect.position = Vector2(room.position.x * TILE, room.position.y * TILE)
	_tint_rect.size = Vector2(room.size.x * TILE, room.size.y * TILE)
	_tint_rect.z_index = -9
	_tint_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tint_rect)
	# Drop spawn-portal markers at the four corners (inset 2 tiles so they
	# don't sit on the wall). Visually tinted "O" glyphs.
	var corners: Array = [
		Vector2i(room.position.x + 2, room.position.y + 2),
		Vector2i(room.position.x + room.size.x - 3, room.position.y + 2),
		Vector2i(room.position.x + 2, room.position.y + room.size.y - 3),
		Vector2i(room.position.x + room.size.x - 3, room.position.y + room.size.y - 3),
	]
	for c in corners:
		var portal := Node2D.new()
		portal.position = _tile_center(c)
		var lbl := Label.new()
		lbl.text = "O"
		lbl.add_theme_font_override("font", MonoFont.get_font())
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.add_theme_color_override("font_color", theme_color)
		lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
		lbl.add_theme_constant_override("outline_size", 2)
		lbl.position = Vector2(-10, -14)
		lbl.size = Vector2(20, 28)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		portal.add_child(lbl)
		add_child(portal)
		_spawn_portals.append(portal)
	# Floor hint
	var hint := Label.new()
	hint.text = "SURVIVE 45s"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", theme_color)
	hint.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	hint.add_theme_constant_override("outline_size", 2)
	hint.position = _tile_center(room.get_center()) + Vector2(-40, -8)
	hint.size = Vector2(80, 18)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)

func _tile_center(t: Vector2i) -> Vector2:
	return Vector2(float(t.x) + 0.5, float(t.y) + 0.5) * float(TILE)

func _process(delta: float) -> void:
	if _completed:
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if not is_instance_valid(_player):
			return
	if not _armed:
		# Arm when the player crosses into the room rect.
		var p: Vector2 = _player.global_position
		var rmin_x: float = float(room.position.x * TILE)
		var rmax_x: float = float((room.position.x + room.size.x) * TILE)
		var rmin_y: float = float(room.position.y * TILE)
		var rmax_y: float = float((room.position.y + room.size.y) * TILE)
		if p.x >= rmin_x and p.x < rmax_x and p.y >= rmin_y and p.y < rmax_y:
			_arm()
		return
	if not _active:
		return
	# Active phase — count down, spawn waves, update HUD.
	_time_left -= delta
	# Prune dead refs so the concurrent-cap is accurate. The lambda param is
	# left UNTYPED on purpose: the array can hold freed object references, and
	# coercing a freed instance into a typed `Object` param throws
	# ("Cannot convert argument 1 from Object to Object"). Untyped lets
	# is_instance_valid() do its job.
	_spawned_alive = _spawned_alive.filter(func(e):
		return is_instance_valid(e))
	_spawn_t -= delta
	if _spawn_t <= 0.0 and _spawned_alive.size() < MAX_CONCURRENT:
		_spawn_t = _current_spawn_interval()
		_spawn_one()
	if _hud_label != null:
		_hud_label.text = "SURVIVAL: %.1fs   (alive: %d)" % [
			maxf(0.0, _time_left), _spawned_alive.size()]
	if _time_left <= 0.0:
		_complete()

# Spawn cadence accelerates as the timer runs down — gives a satisfying
# crescendo right before the bell rings.
func _current_spawn_interval() -> float:
	var t: float = clampf(1.0 - (_time_left / DURATION_BASE), 0.0, 1.0)
	return lerpf(SPAWN_INTERVAL_START, SPAWN_INTERVAL_END, t)

func _arm() -> void:
	_armed = true
	_active = true
	_time_left = DURATION_BASE
	_spawn_t = 0.6   # first spawn fires almost immediately
	# Strong red tint while active so the player feels the danger.
	_tint_rect.color = Color(theme_color.r, theme_color.g, theme_color.b, 0.28)
	# Add a top-bar HUD label so the timer is always readable.
	_hud_canvas = CanvasLayer.new()
	_hud_canvas.layer = 17
	get_tree().current_scene.add_child(_hud_canvas)
	_hud_label = Label.new()
	_hud_label.anchor_left = 0.5
	_hud_label.anchor_right = 0.5
	_hud_label.offset_left = -180.0
	_hud_label.offset_right = 180.0
	_hud_label.offset_top = 78.0
	_hud_label.offset_bottom = 110.0
	_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_label.add_theme_font_size_override("font_size", 22)
	_hud_label.add_theme_color_override("font_color", theme_color)
	_hud_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_hud_label.add_theme_constant_override("outline_size", 3)
	_hud_canvas.add_child(_hud_label)
	# Banner
	if SoundManager:
		SoundManager.play("boss_roar", 1.15)
	FloatingText.spawn_str(_tile_center(room.get_center()),
		"SURVIVE!", theme_color, get_tree().current_scene)

func _spawn_one() -> void:
	# Random portal pick — wave appears from a different corner each time
	# so the player can't just camp the opposite side of the room.
	if _spawn_portals.is_empty():
		return
	var portal: Node2D = _spawn_portals[randi() % _spawn_portals.size()] as Node2D
	if not is_instance_valid(portal):
		return
	# Layout stamps may have planted a wall right under the portal tile —
	# spawn position needs to be on FLOOR so the enemy doesn't materialise
	# stuck inside geometry. Snap to the nearest floor tile within a small
	# radius, falling back to the room centre if nothing valid is found.
	var spawn_pos: Vector2 = _floor_pos_near(portal.global_position)
	# Difficulty + time-elapsed pick a slightly tougher mix as the timer
	# runs down. Early waves are mostly fodder; late waves bring chargers
	# / phantoms / bombers depending on biome.
	var t_frac: float = clampf(1.0 - (_time_left / DURATION_BASE), 0.0, 1.0)
	var roster: Array = [SPIDER_SCENE, CHASER_SCENE, SHOOTER_SCENE, ARCHER_SCENE]
	if t_frac > 0.30:
		roster.append(CHARGER_SCENE)
	if t_frac > 0.55:
		roster.append(BERSERKER_SCENE)
		match GameState.biome:
			1: roster.append(PHANTOM_SCENE)
			2: roster.append(FROSTSENT_SCENE)
			3: roster.append(MAGMASLUG_SCENE)
			_: roster.append(BOMBER_SCENE)
	if t_frac > 0.80:
		roster.append(BOMBER_SCENE)
	var scene: PackedScene = roster[randi() % roster.size()] as PackedScene
	var enemy: Node2D = scene.instantiate() as Node2D
	enemy.position = spawn_pos
	if "max_health" in enemy:
		enemy.max_health = maxi(1, int(float(enemy.max_health) * hp_mult * (0.85 + t_frac * 0.6)))
	var enemies_node := get_tree().current_scene.get_node_or_null("Enemies")
	if enemies_node != null:
		enemies_node.add_child(enemy)
	else:
		get_tree().current_scene.add_child(enemy)
	_spawned_alive.append(enemy)
	# Small spawn flash so the portal feels alive.
	FloatingText.spawn_str(portal.global_position + Vector2(0.0, -16.0),
		"!", theme_color, get_tree().current_scene)

# Spiral-searches the world grid around `pos` for the nearest FLOOR tile.
# Falls back to the room centre if every nearby tile is wall (which would
# be exceptional). Used so portal-corner spawns never plant an enemy
# inside a wall stamped by the layout pass.
func _floor_pos_near(pos: Vector2) -> Vector2:
	var world := get_tree().current_scene
	if world == null or not ("_grid" in world):
		return pos
	var grid: Array = world.get("_grid")
	var grid_w: int = int(world.get("GRID_W"))
	var grid_h: int = int(world.get("GRID_H"))
	var tx: int = int(pos.x / float(TILE))
	var ty: int = int(pos.y / float(TILE))
	if tx >= 0 and tx < grid_w and ty >= 0 and ty < grid_h:
		if int((grid[ty] as Array)[tx]) == 0:   # FLOOR
			return pos
	# Ring search outward, radius 1..3
	for r in range(1, 4):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var nx: int = tx + dx
				var ny: int = ty + dy
				if nx < 0 or nx >= grid_w or ny < 0 or ny >= grid_h:
					continue
				if int((grid[ny] as Array)[nx]) == 0:
					return _tile_center(Vector2i(nx, ny))
	return _tile_center(room.get_center())

func _complete() -> void:
	_completed = true
	_active = false
	# Reward drop — chunky bag with three rolls + a pile of gold.
	var bag := LOOT_BAG_SCENE.instantiate()
	bag.position = _tile_center(room.get_center())
	bag.set("items", [ItemDB.random_drop(), ItemDB.random_drop(),
		ItemDB.random_drop()])
	get_tree().current_scene.add_child(bag)
	for i in 8:
		var gold := GOLD_PICKUP_SCENE.instantiate()
		gold.global_position = _tile_center(room.get_center()) + Vector2(
			randf_range(-72.0, 72.0), randf_range(-72.0, 72.0))
		gold.value = int(randi_range(10, 22) * GameState.loot_multiplier)
		get_tree().current_scene.add_child(gold)
	# Banner + sound
	FloatingText.spawn_str(_tile_center(room.get_center()),
		"SURVIVED!", Color(1.0, 0.95, 0.30), get_tree().current_scene)
	if SoundManager:
		SoundManager.play("level_up", 1.0)
	# Fade the tint and free the HUD.
	if is_instance_valid(_tint_rect):
		var tw := _tint_rect.create_tween()
		tw.tween_property(_tint_rect, "modulate:a", 0.0, 1.2)
		tw.tween_callback(_tint_rect.queue_free)
	if is_instance_valid(_hud_canvas):
		_hud_canvas.queue_free()
