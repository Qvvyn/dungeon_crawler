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
const EXIT_PORTAL_SCRIPT = preload("res://scripts/ExitPortal.gd")
const SELL_CHEST_SCENE   = preload("res://scenes/SellChest.tscn")
const FLOOR_SHADER       = preload("res://shaders/floor_dots.gdshader")
const CHASER_SCENE       = preload("res://scenes/EnemyChaser.tscn")
const SHOOTER_SCENE      = preload("res://scenes/EnemyShooter.tscn")
const ENCHANTER_SCENE    = preload("res://scenes/EnemyEnchanter.tscn")
const TANK_SCENE         = preload("res://scenes/EnemyTank.tscn")
const SNIPER_SCENE       = preload("res://scenes/EnemySniper.tscn")
const SUMMONER_SCENE     = preload("res://scenes/EnemySummoner.tscn")
const ARCHER_SCENE       = preload("res://scenes/EnemyArcher.tscn")
const SPIRAL_SCENE       = preload("res://scenes/EnemySpiralMage.tscn")
const GRENADIER_SCENE    = preload("res://scenes/EnemyGrenadier.tscn")
const CHARGER_SCENE      = preload("res://scenes/EnemyCharger.tscn")
const MINELAYER_SCENE    = preload("res://scenes/EnemyMineLayer.tscn")
const BEAMSWEEP_SCENE    = preload("res://scenes/EnemyBeamSweep.tscn")
const MISSILE_SCENE      = preload("res://scenes/EnemyMissileTurret.tscn")
const SPIDER_SCENE       = preload("res://scenes/EnemySpider.tscn")
const WIZARD_SCENE       = preload("res://scenes/EnemyWizard.tscn")
const BOSS_SCENE         = preload("res://scenes/EnemyBoss.tscn")
# New enemies (this pass) — added to the test-arena pool and addressable
# by name from the test-mode spawn-override dropdown.
const BOMBER_SCENE       = preload("res://scenes/EnemyBomber.tscn")
const BERSERKER_SCENE    = preload("res://scenes/EnemyBerserker.tscn")
const PHANTOM_SCENE      = preload("res://scenes/EnemyPhantom.tscn")
const BANSHEE_SCENE      = preload("res://scenes/EnemyBanshee.tscn")
const REFLECTOR_SCENE    = preload("res://scenes/EnemyReflector.tscn")
# Biome-themed (only appear in their biome under normal play; available
# everywhere in the test arena via the override).
const BONEDRAKE_SCENE    = preload("res://scenes/EnemyBoneDrake.tscn")
const FROSTSENT_SCENE    = preload("res://scenes/EnemyFrostSentinel.tscn")
const MAGMASLUG_SCENE    = preload("res://scenes/EnemyMagmaSlug.tscn")
const SPLITTER_SCENE     = preload("res://scenes/EnemySplitter.tscn")
const STALKER_SCENE      = preload("res://scenes/EnemyStalker.tscn")

# Maps the GameState.test_spawn_override key → PackedScene. Players see
# the keys in the pause-menu dropdown (humanized via _humanize_test_key).
# An empty key in the dropdown means "Regular mixed pool".
static func test_spawn_keys() -> Array:
	return [
		"chaser", "shooter", "tank", "sniper", "archer", "spider",
		"charger", "grenadier", "minelayer", "beamsweep", "missileturret",
		"enchanter", "summoner", "spiralmage", "wizard",
		"bomber", "berserker", "phantom", "banshee", "reflector",
		"bonedrake", "frostsentinel", "magmaslug",
		"splitter", "stalker",
	]

func _scene_for_test_key(key: String) -> PackedScene:
	match key:
		"chaser":         return CHASER_SCENE
		"shooter":        return SHOOTER_SCENE
		"tank":           return TANK_SCENE
		"sniper":         return SNIPER_SCENE
		"archer":         return ARCHER_SCENE
		"spider":         return SPIDER_SCENE
		"charger":        return CHARGER_SCENE
		"grenadier":      return GRENADIER_SCENE
		"minelayer":      return MINELAYER_SCENE
		"beamsweep":      return BEAMSWEEP_SCENE
		"missileturret":  return MISSILE_SCENE
		"enchanter":      return ENCHANTER_SCENE
		"summoner":       return SUMMONER_SCENE
		"spiralmage":     return SPIRAL_SCENE
		"wizard":         return WIZARD_SCENE
		"bomber":         return BOMBER_SCENE
		"berserker":      return BERSERKER_SCENE
		"phantom":        return PHANTOM_SCENE
		"banshee":        return BANSHEE_SCENE
		"reflector":      return REFLECTOR_SCENE
		"bonedrake":      return BONEDRAKE_SCENE
		"frostsentinel":  return FROSTSENT_SCENE
		"magmaslug":      return MAGMASLUG_SCENE
		"splitter":       return SPLITTER_SCENE
		"stalker":        return STALKER_SCENE
	return null
const SPIKE_TRAP_SCENE   = preload("res://scenes/SpikeTrap.tscn")
const SPIN_TRAP_SCENE    = preload("res://scenes/SpinTrap.tscn")
const BEAM_TRAP_SCENE    = preload("res://scenes/BeamTrap.tscn")
const DOOR_SCENE         = preload("res://scenes/Door.tscn")
const AMBUSH_CONTROLLER_SCENE = preload("res://scenes/AmbushController.tscn")
const SWITCH_SCENE       = preload("res://scenes/Switch.tscn")
const SHRINE_SCENE       = preload("res://scenes/Shrine.tscn")
const SECRET_DOOR_SCENE  = preload("res://scenes/SecretDoor.tscn")
const ENCHANT_TABLE_SCENE= preload("res://scenes/EnchantTable.tscn")
const LOOT_BAG_SCENE     = preload("res://scenes/LootBag.tscn")
const GOLD_PICKUP_SCENE  = preload("res://scenes/GoldPickup.tscn")
const LAVA_TILE_SCRIPT        = preload("res://scripts/LavaTile.gd")
const POISON_CLOUD_SCRIPT     = preload("res://scripts/PoisonCloud.gd")
const ICE_TILE_SCRIPT         = preload("res://scripts/IceTile.gd")
const BREAKABLE_WALL_SCRIPT   = preload("res://scripts/BreakableWall.gd")
const PRESSURE_PLATE_SCRIPT   = preload("res://scripts/PressurePlate.gd")
const TELEPORTER_SCRIPT       = preload("res://scripts/Teleporter.gd")
const ASCII_WALLS_SCRIPT      = preload("res://scripts/AsciiWalls.gd")
const MINIMAP_GLYPHS_SCRIPT   = preload("res://scripts/MinimapGlyphs.gd")
const FIRST_PERSON_RIG_SCRIPT = preload("res://scripts/FirstPersonRig.gd")
const RAYCASTER_RIG_SCRIPT    = preload("res://scripts/RaycasterRig.gd")
const BOSS_ARCHITECT_SCRIPT   = preload("res://scripts/EnemyBossArchitect.gd")
const BOSS_WRAITH_SCRIPT      = preload("res://scripts/EnemyBossWraith.gd")
const BOSS_LICH_SCRIPT        = preload("res://scripts/EnemyBossLich.gd")
const BOSS_DEVOURER_SCRIPT    = preload("res://scripts/EnemyBossDevourer.gd")
const BOSS_MAGMA_SCRIPT       = preload("res://scripts/EnemyBossMagma.gd")
const SURVIVAL_ARENA_SCRIPT   = preload("res://scripts/SurvivalArena.gd")

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
# Per-biome floor color for the FP ground plane — brightened so biome shifts
# are visible under dungeon lighting (original values were too close to grey).
const BIOME_FP_FLOOR_COLORS: Array[Color] = [
	Color(0.28, 0.22, 0.18),   # Dungeon   — warm brown stone
	Color(0.18, 0.28, 0.16),   # Catacombs — mossy green
	Color(0.16, 0.22, 0.36),   # Ice Cavern — steel blue
	Color(0.36, 0.16, 0.10),   # Lava Rift  — burnt orange
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
const TEST_TARGET        := 100
const TEST_REFILL_BATCH  := 100  # full top-off per check — testing arena keeps the room saturated
const TEST_CHECK_INTERVAL := 0.05 # near-frame-rate so kills get replaced immediately
const TEST_CLEANUP_INTERVAL := 2.5

var _is_test_mode: bool        = false
var _test_spawn_queue: Array   = []   # Array[Dictionary] {scene, hp_mult}
# Dungeon enemy spawning is queued and drained over multiple frames to avoid
# the big lag spike that came from instantiating dozens of enemies at once.
var _dungeon_spawn_queue: Array = []   # Array[Dictionary] {scene, room, hp_mult}
const DUNGEON_SPAWN_PER_FAST: int = 14  # healthy-frame spawn budget
const DUNGEON_SPAWN_PER_SLOW: int = 2   # if previous frame was heavy
# First seconds after a level loads, spawn at a far higher rate so the world
# feels populated immediately. Combined with distance-sorting the queue (in
# _spawn_enemies) the rooms the player can actually see fill in ~1 frame.
const DUNGEON_SPAWN_PER_BURST: int = 50
const DUNGEON_SPAWN_BURST_DURATION: float = 1.5
# Hard ceiling on simultaneous regular-spawn dungeon enemies. At very high
# difficulty (≥30) the per-room budget × density_mult × room count combo
# produced 100+ enemies and the room-clear / pathfinding loops bogged the
# frame. Themed-room spawns + summoner minions sit on top of this cap so
# the live count can briefly exceed it, but the bulk regular spawn is
# clipped here.
const MAX_DUNGEON_ENEMIES: int = 35
# Hard ceiling on TOTAL live enemies from ALL sources (initial pass, themed rooms,
# splitters, zombie reanimation, summoners, queued drain). Above the 35 build cap
# so combat can breathe, but bounded so late-game runtime spawners can't explode
# the count and crash the game. Runtime spawners check can_spawn_enemy().
const MAX_LIVE_ENEMIES: int = 45

# True when there's room for another enemy. Checked by every RUNTIME spawn path.
func can_spawn_enemy() -> bool:
	return get_tree().get_nodes_in_group("enemy").size() < MAX_LIVE_ENEMIES

# Ceiling on live loot bags. Late-game kills drop bags faster than the player
# collects them, so they pile up unbounded and tank performance. When exceeded,
# the FARTHEST (non-mega) overflow bags are auto-sold to gold so the player keeps
# the value but the node count stays bounded. Nearby bags are always preserved.
const MAX_LIVE_LOOT_BAGS: int = 12

func enforce_loot_cap() -> void:
	var bags := get_tree().get_nodes_in_group("loot_bag")
	if bags.size() <= MAX_LIVE_LOOT_BAGS:
		return
	var player := get_tree().get_first_node_in_group("player")
	var ppos: Vector2 = (player as Node2D).global_position if player is Node2D else Vector2.ZERO
	var cull: Array = []
	for b in bags:
		if is_instance_valid(b) and b.get("is_mega") != true:
			cull.append(b)
	# Farthest-from-player first, so the player's immediate loot is never culled.
	cull.sort_custom(func(a, c):
		return (a as Node2D).global_position.distance_squared_to(ppos) \
			> (c as Node2D).global_position.distance_squared_to(ppos))
	var to_remove: int = bags.size() - MAX_LIVE_LOOT_BAGS
	var gold_gained: int = 0
	for i in mini(to_remove, cull.size()):
		var b: Node = cull[i]
		if "items" in b:
			for it in (b.get("items") as Array):
				gold_gained += maxi(1, int(it.sell_value))
		b.queue_free()
	if gold_gained > 0:
		GameState.gold += gold_gained
# How many enemies to spawn synchronously inside _spawn_enemies, before any
# frame ticks at all. Avoids the first-frame "empty world" gap; tuned so the
# nearest few rooms are populated before the player even sees the level.
const DUNGEON_SPAWN_INITIAL_DRAIN: int = 24
var _dungeon_spawn_burst_t: float = 0.0
# Periodic cleanup of any enemy that drifted into a wall tile
var _oob_cleanup_t: float = 4.0
var _loot_cap_t: float = 1.0
var _room_check_t: float = 0.0   # throttles the per-frame room-clear enemy scan
var _test_check_timer: float   = 0.0
var _test_cleanup_timer: float = 0.0
var _test_arena_room: Rect2i   = Rect2i()
var _test_wave_label: Label    = null
var _test_boss_active: bool    = false
var _test_kill_threshold: int  = 20

# ── Minimap ────────────────────────────────────────────────────────────────────
# Per-tile cell dimensions in the minimap. The minimap is rendered as ASCII
# glyphs ("." floor / "#" wall) drawn directly into a Node2D so the world's
# visual style is mirrored at small scale. Sized to fit above the HUD stats
# label without overlapping it.
const MINIMAP_CELL_W: float = 2.0
const MINIMAP_CELL_H: float = 2.5
const MINIMAP_SCALE  := MINIMAP_CELL_W   # legacy alias used by tile→pixel math
const MINIMAP_W      := GRID_W * MINIMAP_CELL_W   # 144
const MINIMAP_H      := GRID_H * MINIMAP_CELL_H   # 140
const MINIMAP_X      := 1470.0 - MINIMAP_W        # ~1326 — pulled well in
													# from the right edge so
													# the minimap doesn't clip
													# under window/border
													# scaling on any display
const MINIMAP_Y      := 8.0
var _minimap_dot: ColorRect = null
# Anchored container holding all minimap pieces — kept for reference so
# tweens / future repositions can target it without re-walking the tree.
var _minimap_root: Control = null
var _had_enemies: bool = false
var _room_cleared: bool = false
# Rooms that have been claimed by a themed encounter (spider den, charger pit,
# etc). Skipped by the regular _spawn_enemies pass so the theme stays clean.
var _themed_rooms: Array = []   # Array[Rect2i]

# ── BSP tree node ─────────────────────────────────────────────────────────────
class BSPNode:
	var rect: Rect2i = Rect2i()
	var room: Rect2i = Rect2i()   # only valid on leaves
	var left  = null               # BSPNode | null
	var right = null               # BSPNode | null

	func is_leaf() -> bool:
		return left == null and right == null

# ── Generation mode ───────────────────────────────────────────────────────────
enum GenMode { ROOMS, CAVE, HALLS, ARENA }
var _gen_mode: GenMode = GenMode.ROOMS

# ── State ─────────────────────────────────────────────────────────────────────
var _grid: Array = []   # [y][x] → FLOOR or WALL
var _rooms: Array = []  # Array of Rect2i (tile coords), order = BSP depth-first
var _room_light_levels: Array[int] = []  # parallel to _rooms: 0=NORMAL,1=DARK,2=FLICKER
var _portal_tile: Vector2i = Vector2i.ZERO
var _floor_seed: int = 0   # captured per-floor RNG seed (shown on the minimap)

# First-person rigs — both instantiated at level start, only the one matching
# GameState.render_mode is visible at a time. TOPDOWN hides both. The active
# rig is published on GameState.active_rig so newly-spawned entities (enemies,
# projectiles) can register themselves with the rig from their own _ready.
var _fp_rig: CanvasLayer        = null
var _raycaster_rig: CanvasLayer = null
var _wall_ascii: Node2D         = null   # the AsciiWalls overlay, hidden in FP modes
# 2D top-down vision-radius mask — full-screen ColorRect with a radial
# darkness shader. Visible only in TOPDOWN render mode; the shader's
# `player_px` uniform is pushed each frame from the player's screen pos.
var _vision_overlay: ColorRect  = null
var _vision_mat: ShaderMaterial = null

# ── Entry ─────────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Defensive un-pause: get_tree().paused is GLOBAL and persists across scene
	# changes, so if a level transition ever fires while an interface/pause
	# menu held the tree paused, the next floor would load frozen (every enemy
	# inert). Always start a fresh level running.
	get_tree().paused = false
	# Reset FloatingText's static active-count — floaters mid-animation when the
	# previous floor was freed never fired their release callback.
	FloatingText.reset()
	var _hitbox_canvas := CanvasLayer.new()
	_hitbox_canvas.layer = 50
	_hitbox_canvas.follow_viewport_enabled = false
	var _hitbox_draw: Node2D = preload("res://scripts/HitboxDebugOverlay.gd").new()
	_hitbox_canvas.add_child(_hitbox_draw)
	add_child(_hitbox_canvas)
	_init_grid()
	# Render-mode plumbing — both rigs sit in the tree, only the active one
	# is visible. World owns the toggle so it can also push the live grid to
	# whichever rig the user cycles to and bulk-register existing entities.
	_setup_render_rigs()

	if GameState.test_mode:
		_is_test_mode = true
		_setup_test_arena()
		_apply_render_mode(GameState.render_mode)
		return

	# Capture a seed for this floor and reseed the global RNG so the layout
	# is deterministic — same seed reproduces the same dungeon. The seed is
	# shown on the minimap so a player can replay an interesting floor.
	_floor_seed = randi() & 0x7FFFFFFF
	seed(_floor_seed)

	# Reset the per-floor drop dedup history so every fresh floor's
	# drops are evaluated against a clean slate. Without this, a long
	# session would gradually exhaust the dedup pool and revert to
	# fully-random picks.
	GameState.floor_drop_history.clear()

	_roll_gen_mode()
	_generate_level()

	# On boss floors, sculpt the largest room into a hand-tuned arena (pillars
	# / cover patterns) before walls are built so the changes render properly.
	var is_boss_floor := GameState.portals_used > 0 and GameState.portals_used % 5 == 4
	var is_shop_floor := GameState.portals_used > 0 and GameState.portals_used % 5 == 0
	var is_arena_floor := _gen_mode == GenMode.ARENA
	var boss_arena_room := Rect2i()
	if is_boss_floor:
		boss_arena_room = _carve_boss_arena()

	# Pre-pick spawn / portal so the room-layout pass can skip them — we
	# don't want the player or the portal landing inside a stamped pillar.
	var layout_player_room: Rect2i = _pick_spawn_room(boss_arena_room)
	var layout_portal_room: Rect2i
	if is_boss_floor and boss_arena_room.size.x > 0:
		layout_portal_room = boss_arena_room
	else:
		layout_portal_room = _farthest_room(layout_player_room)

	# Stamp interior layouts into a subset of regular rooms before walls are
	# built so the new wall tiles render through _build_walls / AsciiWalls.
	# Skipped on cave / arena floors (cave is non-rectangular; arena has
	# its own pattern stamped in _gen_arena).
	_apply_room_layouts(layout_player_room, layout_portal_room, boss_arena_room)

	# Re-seal secret entrances to WALL now that connectivity / bridging is done,
	# so the hidden rooms read as solid wall in both 2D and FP until broken.
	_seal_secret_doors()

	_build_floor_visual()
	_build_walls()

	if _gen_mode == GenMode.ROOMS:
		_place_secret_doors()

	var player_room: Rect2i = layout_player_room
	var portal_room: Rect2i = layout_portal_room
	# In ARENA mode there's just one room, so spawn / portal would otherwise
	# overlap at the centre. Offset them to opposite corners of the arena
	# so the player has to traverse the boss + minions to reach the exit.
	var player_pos: Vector2
	var portal_pos: Vector2
	if is_arena_floor:
		var arena := player_room
		player_pos = _tile_center(Vector2i(
			arena.position.x + 3,
			arena.position.y + arena.size.y / 2))
		portal_pos = _tile_center(Vector2i(
			arena.position.x + arena.size.x - 4,
			arena.position.y + arena.size.y / 2))
	else:
		player_pos = _tile_center(player_room.get_center())
		portal_pos = _tile_center(portal_room.get_center())

	_spawn_player(player_pos)
	# Floor-50 gauntlet hijacks the boss-floor flow: skip the pre-spawned
	# portal (the gauntlet watcher spawns the right portal type after all
	# bosses die) and spawn a 3-boss arena instead of the usual single boss.
	var floor_n: int = GameState.portals_used + 1
	var is_gauntlet_floor: bool = (floor_n == 50)
	if not is_gauntlet_floor:
		_spawn_portal(portal_pos)
	# Exit portal at every 10th floor — lets the player bail back to the
	# village with their loot intact instead of risking it for another
	# level. Placed offset from the regular portal so the two portals
	# don't overlap visually / collision-wise. Floor 50 is gauntlet-handled
	# (the watcher decides exit vs continue) so we skip the auto-exit here
	# even though 50 % 10 == 0.
	if floor_n > 0 and floor_n % 10 == 0 and not is_gauntlet_floor:
		_spawn_exit_portal(portal_pos + Vector2(96.0, 0.0))

	if is_shop_floor:
		_spawn_sell_chest(portal_room)
	if is_gauntlet_floor:
		_spawn_boss_gauntlet(portal_room)
	elif is_boss_floor:
		_spawn_boss(portal_room)
	elif is_arena_floor:
		# ARENA floors get a centre-staged boss + the regular portal wizard
		# guarding the exit corner. Skip the mini-boss roll since the
		# arena's already gauntlet-style.
		_spawn_boss(player_room)
		_spawn_portal_wizard(player_room)
	else:
		# Rival wizard in the portal room — guards the exit and drops its
		# wand on death. Skipped on boss floors so the arena fight stays
		# focused on the boss.
		_spawn_portal_wizard(portal_room)
		# Mini-boss surprise on non-boss floors at high difficulty. From
		# diff ≥4 onward there's a chance any regular floor has one of
		# the three boss types (with reduced HP) parked in a far room.
		if GameState.difficulty >= 4.0 and randf() < _mini_boss_chance():
			_spawn_mini_boss(player_room)
	if GameState.portals_used >= 1:
		_spawn_enchant_table(player_room)

	_roll_floor_modifier()
	_spawn_traps()
	_spawn_beam_traps()
	_spawn_doors()
	_spawn_ambush()
	_spawn_switch_alcove()
	_spawn_lava_tiles()
	_spawn_shrine(player_room)
	# Pick themed rooms BEFORE the regular spawn pass — they replace the
	# normal enemy mix in their room with a flavored encounter (spider den,
	# charger pit, etc.) and need to be skipped by _spawn_enemies. Arena
	# floors are a single huge room, so themed sub-rooms don't apply —
	# the arena itself IS the encounter.
	if not is_arena_floor:
		_spawn_themed_rooms(player_room, portal_room if is_boss_floor else Rect2i())
	if is_arena_floor:
		_spawn_arena_enemies(player_room, player_pos)
	else:
		_spawn_enemies(player_room, portal_room if is_boss_floor else Rect2i())
	# _spawn_hazard_rooms removed — the spike-room-with-loot-in-the-middle
	# read as a weird "hidden loot hazard". Dropped per design.
	_spawn_challenge_room(player_room, portal_room if is_boss_floor else Rect2i())
	if _gen_mode == GenMode.ROOMS:
		_spawn_pressure_plates()
		_spawn_teleporters()
	_create_minimap()

	if GameState.portals_used > 0 and GameState.portals_used % 3 == 0:
		_show_biome_banner()
	if GameState.floor_modifier != "":
		_show_modifier_banner()

	if GameState.crt_enabled:
		_spawn_crt_overlay()
	# Apply the persisted render mode now that walls + floor + entities are
	# all in place. _setup_render_rigs was called in _ready before generation,
	# but the rigs need the live _grid for raycasting / wall mesh build.
	_apply_render_mode(GameState.render_mode)

# ── First-person rigs ─────────────────────────────────────────────────────────

func _setup_render_rigs() -> void:
	# Both rigs created up front so cycling is instant. They self-hide; the
	# active one is shown in _apply_render_mode. Layer=1 puts them above the
	# default 2D canvas (walls, floor, entity glyphs) but below any
	# higher-layer UI (test wave label at 18, etc).
	_fp_rig = CanvasLayer.new()
	_fp_rig.set_script(FIRST_PERSON_RIG_SCRIPT)
	_fp_rig.name = "FirstPersonRig"
	add_child(_fp_rig)

	_raycaster_rig = CanvasLayer.new()
	_raycaster_rig.set_script(RAYCASTER_RIG_SCRIPT)
	_raycaster_rig.name = "RaycasterRig"
	add_child(_raycaster_rig)

	if not GameState.render_mode_changed.is_connected(_on_render_mode_changed):
		GameState.render_mode_changed.connect(_on_render_mode_changed)
	_setup_vision_overlay()

# Builds the 2D top-down vision-radius mask. CanvasLayer holds a fullscreen
# ColorRect whose shader paints alpha=0 in a disc around the player and
# fades to ~black at the periphery. _process pushes the player's screen
# position into the shader each frame; _apply_render_mode toggles
# visibility (TOPDOWN only).
func _setup_vision_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "VisionOverlay"
	# Layer 0 keeps the mask above the 2D world (walls/floor/entities) but
	# below the Player.HUD CanvasLayer (default layer 1) — HUD stays crisp.
	layer.layer = 0
	add_child(layer)
	_vision_overlay = ColorRect.new()
	_vision_overlay.anchor_right = 1.0
	_vision_overlay.anchor_bottom = 1.0
	_vision_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vision_overlay.color = Color(0, 0, 0, 1)   # shader writes alpha; base color is opaque black
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/vision_radius.gdshader")
	mat.set_shader_parameter("player_px", Vector2.ZERO)
	# ~11 tiles fully visible, fade to near-black over the next ~7.5 tiles.
	# Tuned so enemies at typical engagement range stay readable; raise
	# both values further if combat still feels too dim.
	mat.set_shader_parameter("radius_px", 360.0)
	mat.set_shader_parameter("fade_px", 240.0)
	mat.set_shader_parameter("max_darkness", 0.88)
	_vision_overlay.material = mat
	_vision_mat = mat
	_vision_overlay.visible = false
	layer.add_child(_vision_overlay)

func _on_render_mode_changed(mode: int) -> void:
	_apply_render_mode(mode)

func _apply_render_mode(mode: int) -> void:
	# Toggle the wall ascii overlay (and any other top-down-only nodes
	# tagged into the group). The base wall colliders + floor shader stay
	# visible because the FP rig overlays on top of them.
	var top_down_visible: bool = (mode == GameState.RenderMode.TOPDOWN)
	if _wall_ascii != null and is_instance_valid(_wall_ascii):
		_wall_ascii.visible = top_down_visible
	for n in get_tree().get_nodes_in_group("topdown_only"):
		if is_instance_valid(n):
			(n as CanvasItem).visible = top_down_visible
	if _vision_overlay != null and is_instance_valid(_vision_overlay):
		_vision_overlay.visible = top_down_visible

	# Show whichever rig matches the mode; hide the other. The shader rig
	# also hosts 3rd-person — we just flip its camera mode before showing.
	var rig_to_show: CanvasLayer = null
	match mode:
		GameState.RenderMode.FIRSTPERSON_SHADER:
			rig_to_show = _fp_rig
			if _fp_rig and _fp_rig.has_method("set_camera_mode"):
				_fp_rig.set_camera_mode("first")
		GameState.RenderMode.THIRD_PERSON:
			rig_to_show = _fp_rig
			if _fp_rig and _fp_rig.has_method("set_camera_mode"):
				_fp_rig.set_camera_mode("third")
		_:
			rig_to_show = null
	for rig in [_fp_rig, _raycaster_rig]:
		if rig != null and is_instance_valid(rig):
			rig.visible = (rig == rig_to_show)
			if rig.has_method("clear_entities"):
				rig.clear_entities()
	GameState.active_rig = rig_to_show
	# Re-apply the sticky FP debug "blinded" vignette so flipping into FP
	# from TOPDOWN doesn't silently reset darkness=0 on the freshly-shown
	# rig. (Newly-built rigs default the uniform to 0.0.)
	if rig_to_show != null and rig_to_show.has_method("set_blinded"):
		rig_to_show.set_blinded(0.7 if GameState.fp_blinded else 0.0)

	# Feed the live grid to the newly-active rig + bulk-register every
	# existing body so entities that spawned before the rig was shown
	# (or that spawned during TOPDOWN play) get a visual representation.
	if rig_to_show != null:
		# Match FP wall color to the active biome's 2D wall color.
		if rig_to_show.has_method("set_wall_color"):
			rig_to_show.set_wall_color(BIOME_WALL_COLORS[GameState.biome])
		if rig_to_show.has_method("set_floor_color"):
			rig_to_show.set_floor_color(BIOME_FP_FLOOR_COLORS[clampi(GameState.biome, 0, BIOME_FP_FLOOR_COLORS.size() - 1)])
		if rig_to_show.has_method("set_grid"):
			rig_to_show.set_grid(_grid, GRID_W, GRID_H)
		# DOOM-style per-room darkness — assign levels once per floor, reuse on
		# subsequent render-mode toggles.
		if rig_to_show.has_method("set_room_lighting"):
			if _room_light_levels.size() != _rooms.size():
				_assign_room_lighting()
			rig_to_show.set_room_lighting(_rooms, _room_light_levels)
		_register_all_entities_with(rig_to_show)

func _register_all_entities_with(rig: Node) -> void:
	if not rig.has_method("register_entity"):
		return
	# Player — register with the full wizard ASCII art + purple tint so the
	# 3rd-person camera mode can render a recognizable body. First-person
	# suppresses the glyph in the rig's _process (the camera sits AT the
	# player so the Label3D would engulf the view). Live-text sync reads
	# the player's AsciiChar each frame so idle animation works in FP too.
	var player: Node = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and player is Node2D:
		# Canonical wizard art. The rig's Label3D uses LEFT alignment +
		# computed bbox-centering offset, so leading-space layout renders
		# the same way as 2D.
		var wizard_glyph: String = "   ^\n__/_\\__\n (*-*)\n /)V(\\|\n /___\\|"
		if "WIZARD_F0" in player:
			wizard_glyph = player.get("WIZARD_F0")
		# Multi-line so the rig's 2D overlay label keeps all 5 lines of the
		# wizard art. The shader pipeline is now bypassed for entities, so
		# pixel_size / outline_size / fp_height aren't needed any more —
		# the overlay Label scales itself by distance and centers on the
		# unprojected screen point. The (now-hidden) Label3D defaults are
		# fine for bookkeeping.
		player.set_meta("fp_multiline", true)
		# Shrink the 3rd-person wizard to 75% of the default body size so he
		# doesn't dominate the screen (default body pixel_size is 0.014).
		player.set_meta("fp_pixel_size", 0.0105)
		rig.register_entity(player, wizard_glyph, GameState.wizard_color)
	# Enemies — iterate the $Enemies node since EnemyBase doesn't auto-add
	# to a group. Both flat enemies and bosses live under here.
	var enemies_node: Node = get_node_or_null("Enemies")
	if enemies_node != null:
		for child in enemies_node.get_children():
			if child is Node2D:
				var tier: int = 0
				if (child as Node).is_in_group("boss"):
					tier = 3
				elif child.get("is_champion") == true:
					tier = 2
				elif child.get("is_elite") == true:
					tier = 1
				var glyph: String = "B" if tier > 0 else "D"
				rig.register_entity(child, glyph, GameState.enemy_fp_color(tier))
	# Everything else (shrines / traps / loot / portals / village shops /
	# floor hazards) self-tags into "fp_visible" via GameState.attach_fp_visual,
	# storing its preferred glyph + color as metadata. One loop handles them all.
	for node in get_tree().get_nodes_in_group("fp_visible"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var g: String = str(node.get_meta("fp_glyph", "?"))
		var c_v: Variant = node.get_meta("fp_color", Color.WHITE)
		var c: Color = c_v if c_v is Color else Color.WHITE
		rig.register_entity(node, g, c)

# ── Test Arena ────────────────────────────────────────────────────────────────

func _setup_test_arena() -> void:
	var room := Rect2i(4, 4, GRID_W - 8, GRID_H - 8)
	_rooms.append(room)
	_carve_room(room)
	_test_arena_room = room

	_build_floor_visual()
	_build_walls()

	var center_pos := _tile_center(room.get_center())
	GameState.test_spawn_pos = center_pos
	_spawn_player(center_pos)
	_create_minimap()
	_setup_test_wave_ui()

	if GameState.crt_enabled:
		_spawn_crt_overlay()

	_start_test_wave()  # arms the spawn timer; enemies stream in via _tick_test_wave
	# Give player best gear on next frame so Player._ready() has finished
	call_deferred("_give_test_gear")

func _give_test_gear() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		return
	if player.has_method("_debug_best_gear"):
		player._debug_best_gear()
	_spawn_test_wand_selection(player.global_position)

func _spawn_test_wand_selection(center: Vector2) -> void:
	# Pre-configured wands in loot bags — pick one up to swap your equipped wand
	var configs: Array[Dictionary] = [
		{"name": "Hellfire Barrage", "type": "fire",      "dmg": 14, "rate": 0.10, "cost": 10.0, "speed": 600.0, "color": Color(1.0, 0.3, 0.05)},
		{"name": "Blizzard Lance",   "type": "freeze",    "dmg": 18, "rate": 0.14, "cost":  8.0, "speed": 820.0, "color": Color(0.5, 0.88, 1.0)},
		{"name": "Chain Storm",      "type": "shock",     "dmg": 12, "rate": 0.09, "cost":  9.0, "speed": 720.0, "color": Color(0.9, 0.95, 0.1)},
		{"name": "Void Cascade",     "type": "nova",      "dmg": 16, "rate": 0.22, "cost": 18.0, "speed": 500.0, "color": Color(0.55, 0.1, 1.0)},
		{"name": "Soul Seeker",      "type": "homing",    "dmg": 22, "rate": 0.16, "cost": 12.0, "speed": 450.0, "color": Color(0.8, 0.2, 1.0)},
		{"name": "Iron Knuckle",     "type": "melee",     "dmg": 50, "rate": 0.75, "cost": 14.0, "speed": 0.0,   "color": Color(0.95, 0.85, 0.3)},
		{"name": "Ricochet Storm",   "type": "ricochet",  "dmg": 20, "rate": 0.13, "cost": 11.0, "speed": 680.0, "color": Color(0.15, 1.0, 0.28), "ricochet": 5},
	]
	var offsets: Array[Vector2] = [
		Vector2(-80, -60), Vector2(80, -60), Vector2(-80, 60), Vector2(80, 60),
		Vector2(0, -90), Vector2(0, 90), Vector2(160, 0),
	]
	for i in configs.size():
		var cfg: Dictionary = configs[i]
		var wand: Item = ItemDB.generate_wand(Item.RARITY_LEGENDARY)
		wand.wand_shoot_type = cfg["type"]
		wand.wand_damage     = cfg["dmg"]
		wand.wand_fire_rate  = cfg["rate"]
		wand.wand_mana_cost  = cfg["cost"]
		wand.wand_proj_speed = cfg["speed"]
		wand.wand_pierce     = 1
		wand.wand_ricochet   = cfg.get("ricochet", 0)
		wand.wand_flaws.clear()
		wand.display_name    = cfg["name"]
		wand.color           = cfg["color"]
		var bag := LOOT_BAG_SCENE.instantiate()
		bag.global_position = center + offsets[i]
		bag.set("items", [wand])
		add_child(bag)

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
	_test_wave_label.text = "TESTING GROUNDS  —  ENEMIES: 0 / %d" % TEST_TARGET
	_test_wave_label.position = Vector2(580, 14)
	_test_wave_label.size = Vector2(440, 32)
	_test_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_test_wave_label.add_theme_font_size_override("font_size", 18)
	_test_wave_label.add_theme_color_override("font_color", Color(0.25, 0.95, 0.85))
	canvas.add_child(_test_wave_label)

func _start_test_wave() -> void:
	_test_spawn_queue.clear()
	_test_check_timer    = 0.0
	_test_cleanup_timer  = 0.0
	GameState.test_difficulty     = 1.0
	_test_boss_active    = false
	_test_kill_threshold = 20

# Wipes every live enemy and the queued spawn list. Called by the test
# pause-menu spawn dropdown right after the override changes so the
# player sees the new enemy type populate immediately instead of
# waiting for old enemies to die off naturally.
func clear_test_arena_enemies() -> void:
	_test_spawn_queue.clear()
	_test_boss_active = false
	for e: Node in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			e.queue_free()
	# Reset the kill-threshold + check timer so wave logic refills cleanly.
	_test_check_timer = 0.0

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
	# Scale movement speed with difficulty
	var spd_mult := 1.0 + (GameState.test_difficulty - 1.0) * 0.15
	if spd_mult > 1.0:
		if "speed" in enemy:
			enemy.speed = enemy.speed * spd_mult
		elif "move_speed" in enemy:
			enemy.move_speed = enemy.move_speed * spd_mult
	$Enemies.add_child(enemy)

func _tick_test_wave(delta: float) -> void:
	# Drain the entire spawn queue every frame — testing arena should never
	# have a visible gap between a kill and the replacement enemy.
	while not _test_spawn_queue.is_empty():
		var data: Dictionary = _test_spawn_queue.pop_front()
		_spawn_test_enemy(data["scene"], float(data.get("hp_mult", 1.0)))

	# Periodic live-count check, queue refill, and boss trigger
	_test_check_timer -= delta
	if _test_check_timer <= 0.0:
		_test_check_timer = TEST_CHECK_INTERVAL
		var live := 0
		for e: Node in get_tree().get_nodes_in_group("enemy"):
			if not e.is_queued_for_deletion():
				live += 1
		var total := live + _test_spawn_queue.size()
		if _test_wave_label and not _test_boss_active:
			_test_wave_label.text = "TESTING GROUNDS  —  ENEMIES: %d / %d  |  x%.1f" % [mini(total, TEST_TARGET), TEST_TARGET, GameState.test_difficulty]
		# Boss every 20 kills
		if not _test_boss_active and GameState.kills >= _test_kill_threshold:
			_test_kill_threshold += 20
			_spawn_test_boss()
		var need := TEST_TARGET - total
		if need > 0:
			# Spawn override — when set, every refill picks the same scene
			# so the player can isolate one enemy type for tuning. Empty
			# string falls through to the mixed default pool.
			var override_key := String(GameState.test_spawn_override)
			if override_key != "":
				var override_scene := _scene_for_test_key(override_key)
				if override_scene != null:
					for _i in mini(need, TEST_REFILL_BATCH):
						_test_spawn_queue.append({
							"scene": override_scene,
							"hp_mult": GameState.test_difficulty,
						})
					return
				# Bad key → fall through to default pool rather than spinning silent.
			var scenes: Array[PackedScene] = [
				CHASER_SCENE, CHASER_SCENE, CHASER_SCENE,
				SHOOTER_SCENE, SHOOTER_SCENE,
				TANK_SCENE, TANK_SCENE,
				SNIPER_SCENE, ENCHANTER_SCENE, SUMMONER_SCENE,
				ARCHER_SCENE, ARCHER_SCENE,
				SPIRAL_SCENE, GRENADIER_SCENE,
				CHARGER_SCENE, CHARGER_SCENE,
				MINELAYER_SCENE, BEAMSWEEP_SCENE, MISSILE_SCENE,
				SPIDER_SCENE, SPIDER_SCENE, SPIDER_SCENE, SPIDER_SCENE, SPIDER_SCENE,
				# New enemies seeded into the default pool too
				BOMBER_SCENE, BERSERKER_SCENE, PHANTOM_SCENE,
				BANSHEE_SCENE, REFLECTOR_SCENE,
				BONEDRAKE_SCENE, FROSTSENT_SCENE, MAGMASLUG_SCENE,
				SPLITTER_SCENE, STALKER_SCENE,
			]
			for _i in mini(need, TEST_REFILL_BATCH):
				_test_spawn_queue.append({"scene": scenes[randi() % scenes.size()], "hp_mult": GameState.test_difficulty})

	# Auto-sweep gold and loot bags so the ground stays clean
	_test_cleanup_timer -= delta
	if _test_cleanup_timer <= 0.0:
		_test_cleanup_timer = TEST_CLEANUP_INTERVAL
		_sweep_test_ground()

func _spawn_test_boss() -> void:
	_test_boss_active = true
	var center := _tile_center(_test_arena_room.get_center())
	var offset := Vector2(randf_range(-96.0, 96.0), randf_range(-96.0, 96.0))
	var diff   := GameState.test_difficulty
	var boss: Node2D
	# Test arena bosses follow the bumped bases too. Magma joined the pool
	# so all four biome signature bosses can be tested without leaving the
	# arena.
	match randi() % 4:
		0:
			boss = BOSS_SCENE.instantiate()
			if "max_health" in boss:
				boss.max_health = int(200.0 * (1.0 + diff * 1.0))
		1:
			boss = BOSS_ARCHITECT_SCRIPT.new()
			boss.max_health = int(260.0 * (1.0 + diff * 1.0))
		2:
			boss = BOSS_WRAITH_SCRIPT.new()
			boss.max_health = int(220.0 * (1.0 + diff * 1.0))
		3:
			boss = BOSS_MAGMA_SCRIPT.new()
			boss.max_health = int(280.0 * (1.0 + diff * 1.0))
	boss.position = center + offset
	boss.tree_exited.connect(_on_test_boss_died)
	$Enemies.add_child(boss)
	if _test_wave_label:
		_test_wave_label.text = "  !! BOSS !!"
		_test_wave_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.8))
	if SoundManager:
		SoundManager.play("boss_roar")

func _on_test_boss_died() -> void:
	_test_boss_active  = false
	GameState.test_difficulty  += 0.35
	if _test_wave_label:
		_test_wave_label.text = "DIFFICULTY INCREASED  —  x%.1f" % GameState.test_difficulty
		_test_wave_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.1))

func _sweep_test_ground() -> void:
	for node in get_tree().get_nodes_in_group("gold_pickup"):
		if not (node as Node).is_queued_for_deletion():
			if "value" in node:
				GameState.gold += (node as Node).get("value") as int
			node.queue_free()
	for node in get_tree().get_nodes_in_group("loot_bag"):
		if not (node as Node).is_queued_for_deletion():
			node.queue_free()

# ── Grid ──────────────────────────────────────────────────────────────────────
func _init_grid() -> void:
	# Clear secret-door records so a regeneration pass (the <3-rooms fallback)
	# doesn't carry stale entrances that point into the freshly-reset grid.
	_secret_door_data.clear()
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

func _place_l_shape_room(node: BSPNode) -> void:
	var pad := 2
	@warning_ignore("integer_division")
	var mw := randi_range(node.rect.size.x / 2, node.rect.size.x - pad * 2)
	@warning_ignore("integer_division")
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
	@warning_ignore("integer_division")
	var wing_w := randi_range(4, maxi(4, mw / 2))
	@warning_ignore("integer_division")
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

func _subtree_center(node: BSPNode) -> Vector2i:
	if node == null:
		@warning_ignore("integer_division")
		return Vector2i(GRID_W / 2, GRID_H / 2)
	if node.is_leaf():
		if node.room != Rect2i():
			return node.room.get_center()
		return node.rect.get_center()
	if node.left != null and node.right != null:
		var lc := _subtree_center(node.left)
		var rc := _subtree_center(node.right)
		@warning_ignore("integer_division")
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
	# ARENA is rare (~6 %) and only rolls past floor 2 so the player has at
	# least seen a normal dungeon layout before being dropped into a single
	# open killing-field. Catacombs/Lava-Rift biomes get a slight bump to
	# the chance since the theme suits one-room "thunderdome" encounters.
	var floor_n: int = GameState.portals_used + 1
	var arena_chance: float = 0.0
	if floor_n >= 3:
		arena_chance = 0.06
		if GameState.biome == 1 or GameState.biome == 3:
			arena_chance = 0.10
	var r := randf()
	if r < arena_chance:
		_gen_mode = GenMode.ARENA
	elif r < arena_chance + 0.46:
		_gen_mode = GenMode.ROOMS
	elif r < arena_chance + 0.46 + 0.30:
		_gen_mode = GenMode.CAVE
	else:
		_gen_mode = GenMode.HALLS

func _generate_level() -> void:
	match _gen_mode:
		GenMode.ROOMS: _gen_rooms()
		GenMode.CAVE:  _gen_cave()
		GenMode.HALLS: _gen_halls()
		GenMode.ARENA: _gen_arena()
	# ARENA carves a single huge room and uses it as the spawn room, so
	# the usual "need at least 3 rooms" fallback would replace our intent
	# with regular BSP. Bypass that check when the arena succeeded.
	if _rooms.size() < 3 and _gen_mode != GenMode.ARENA:
		_init_grid()
		_rooms.clear()
		_gen_mode = GenMode.ROOMS
		_gen_rooms()
	# Final safety net — BSP/HALLS sometimes leave isolated pockets when a
	# subtree center lands in a wall or an L-shape wing gets clamped away from
	# its main room. Bridge any disconnected floor components into one graph
	# so every tile is reachable from spawn.
	_bridge_disconnected_regions()

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
		@warning_ignore("integer_division")
		var ox := (GRID_W - w) / 2
		@warning_ignore("integer_division")
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

# Walks every floor tile via flood-fill, identifies disconnected components,
# and L-corridors a path between each smaller component and the largest one.
# Used after generation to guarantee the whole map is reachable.
func _bridge_disconnected_regions() -> void:
	var visited: Array = []
	visited.resize(GRID_H)
	for y in GRID_H:
		var row: Array = []
		row.resize(GRID_W)
		row.fill(false)
		visited[y] = row
	var components: Array = []   # Array[Array[Vector2i]]
	for sy in range(1, GRID_H - 1):
		for sx in range(1, GRID_W - 1):
			if _grid[sy][sx] != FLOOR or visited[sy][sx]:
				continue
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
			components.append(region)
	if components.size() <= 1:
		return
	var main_idx := 0
	for i in range(1, components.size()):
		if (components[i] as Array).size() > (components[main_idx] as Array).size():
			main_idx = i
	var main_set: Dictionary = {}
	for p in components[main_idx]:
		main_set[p] = true
	for i in components.size():
		if i == main_idx:
			continue
		var smaller: Array = components[i]
		# Pick a representative tile near the centroid of the smaller component
		var cx := 0
		var cy := 0
		for p in smaller:
			cx += (p as Vector2i).x
			cy += (p as Vector2i).y
		@warning_ignore("integer_division")
		cx = cx / smaller.size()
		@warning_ignore("integer_division")
		cy = cy / smaller.size()
		var src: Vector2i = smaller[0]
		var src_d: int = 1 << 30
		for p in smaller:
			var pp: Vector2i = p
			var d := absi(pp.x - cx) + absi(pp.y - cy)
			if d < src_d:
				src_d = d
				src = pp
		# Find nearest tile in the main component (linear scan — main_set is
		# already iterated only once per smaller component, total work is O(N))
		var dst: Vector2i = src
		var dst_d: int = 1 << 30
		for mp in main_set.keys():
			var mpp: Vector2i = mp
			var d := absi(mpp.x - src.x) + absi(mpp.y - src.y)
			if d < dst_d:
				dst_d = d
				dst = mpp
		_carve_corridor(src, dst)
		# The just-carved corridor and absorbed region join the main component
		# so subsequent bridges can route through them.
		for p in smaller:
			main_set[p] = true

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

func _sample_cave_rooms() -> void:
	var step := 12
	@warning_ignore("integer_division")
	var half := step / 2
	for gy in range(half, GRID_H - half, step):
		for gx in range(half, GRID_W - half, step):
			for _att in 20:
				var tx := randi_range(maxi(1, gx - half), mini(GRID_W - 2, gx + half))
				var ty := randi_range(maxi(1, gy - half), mini(GRID_H - 2, gy + half))
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

func _pick_spawn_room(exclude: Rect2i = Rect2i()) -> Rect2i:
	var eligible: Array = []
	for r in _rooms:
		var room: Rect2i = r
		if room == exclude:
			continue
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
	floor_rect.add_to_group("topdown_only")
	add_child(floor_rect)

# ── Wall building (scanline batch) ────────────────────────────────────────────
func _build_walls() -> void:
	var wall_col: Color = BIOME_WALL_COLORS[GameState.biome]
	# Secret-door tiles are WALL in the grid (so FP renders solid wall) but are
	# excluded from the merged 2D collision strips — the SecretDoor body is the
	# sole 2D collider there, so breaking it (which frees the body) opens the
	# passage without having to surgically split a strip.
	var secret_tiles: Dictionary = {}
	for data in _secret_door_data:
		for t in _secret_door_tiles(data["entrance"]):
			secret_tiles[t] = true
	for y in GRID_H:
		var x_start := -1
		for x in GRID_W:
			if _grid[y][x] == WALL and not secret_tiles.has(Vector2i(x, y)):
				if x_start == -1:
					x_start = x
			else:
				if x_start != -1:
					_make_wall_strip(x_start, y, x - x_start, wall_col)
					x_start = -1
		if x_start != -1:
			_make_wall_strip(x_start, y, GRID_W - x_start, wall_col)
	_build_wall_ascii(wall_col)

# Overlays ASCII glyphs on every wall tile that borders floor and "=" on
# doorway tiles — gives the world a consistent ASCII look while keeping the
# dark wall fill underneath for readability of the playfield.
func _build_wall_ascii(_wall_col: Color) -> void:
	# 2D ASCII wall outlines disabled — too messy, and the visual focus is
	# now FP mode. Walls keep their dark ColorRect fills; we just skip the
	# bordering glyph overlay. (_wall_ascii stays null; the render-mode
	# toggle null-checks it.)
	pass

# A doorway is a floor tile sitting just outside a room rect on a side where
# a corridor punches through the wall. We scan each room's perimeter and
# mark the floor tiles immediately past the boundary.
func _collect_doorway_tiles() -> Array:
	var seen: Dictionary = {}
	var tiles: Array = []
	for r in _rooms:
		var room: Rect2i = r
		# Skip degenerate (single-tile) sample rooms used by cave gen
		if room.size.x < 4 or room.size.y < 4:
			continue
		# Top/bottom edges
		for x in range(room.position.x, room.position.x + room.size.x):
			var top_y: int = room.position.y - 1
			if top_y >= 0 and x >= 0 and x < GRID_W:
				if int((_grid[top_y] as Array)[x]) == FLOOR:
					var tile := Vector2i(x, top_y)
					if not seen.has(tile):
						seen[tile] = true
						tiles.append(tile)
			var bot_y: int = room.position.y + room.size.y
			if bot_y < GRID_H and x >= 0 and x < GRID_W:
				if int((_grid[bot_y] as Array)[x]) == FLOOR:
					var tile := Vector2i(x, bot_y)
					if not seen.has(tile):
						seen[tile] = true
						tiles.append(tile)
		# Left/right edges
		for y in range(room.position.y, room.position.y + room.size.y):
			var left_x: int = room.position.x - 1
			if left_x >= 0 and y >= 0 and y < GRID_H:
				if int((_grid[y] as Array)[left_x]) == FLOOR:
					var tile := Vector2i(left_x, y)
					if not seen.has(tile):
						seen[tile] = true
						tiles.append(tile)
			var right_x: int = room.position.x + room.size.x
			if right_x < GRID_W and y >= 0 and y < GRID_H:
				if int((_grid[y] as Array)[right_x]) == FLOOR:
					var tile := Vector2i(right_x, y)
					if not seen.has(tile):
						seen[tile] = true
						tiles.append(tile)
	return tiles

func _make_wall_strip(tx: int, ty: int, tw: int, wall_col: Color = Color(0.12, 0.10, 0.18)) -> void:
	var pw := float(tw * TILE)
	var ph := float(TILE)
	var cx := float(tx * TILE) + pw * 0.5
	var cy := float(ty * TILE) + ph * 0.5

	# Breakable-wall conversion — only short interior strips. Skip if any tile
	# touches the map perimeter, otherwise breaking that segment opens a hole
	# directly out of the playable area and the player can wander into the
	# void grid past GRID_W / GRID_H.
	var on_edge: bool = (ty <= 0 or ty >= GRID_H - 1
		or tx <= 0 or tx + tw - 1 >= GRID_W - 1)
	if tw <= 3 and not on_edge and randf() < 0.06:
		var bw := BREAKABLE_WALL_SCRIPT.new()
		add_child(bw)
		bw.setup(Vector2(cx, cy), Vector2(pw, ph), wall_col)
		return

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

func _spawn_pressure_plates() -> void:
	if _rooms.size() < 3:
		return
	var candidates: Array = _rooms.duplicate()
	candidates.shuffle()
	var spawned := 0
	for room in candidates:
		if spawned >= 2:
			break
		var pos := _random_pos_in_room(room)
		var plate := PRESSURE_PLATE_SCRIPT.new()
		add_child(plate)
		plate.setup(pos)
		spawned += 1

func _spawn_teleporters() -> void:
	if _rooms.size() < 2:
		return
	var candidates: Array = _rooms.duplicate()
	candidates.shuffle()
	var pos_a := _random_pos_in_room(candidates[0])
	var pos_b := _random_pos_in_room(candidates[mini(1, candidates.size() - 1)])
	var tp_a := TELEPORTER_SCRIPT.new()
	var tp_b := TELEPORTER_SCRIPT.new()
	add_child(tp_a)
	add_child(tp_b)
	tp_a.setup(pos_a)
	tp_b.setup(pos_b)
	tp_a.link(tp_b)
	tp_b.link(tp_a)

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

# Sweeps the enemy group: any enemy whose tile is a wall or out-of-bounds
# gets relocated to the nearest floor tile, or queue_freed if there isn't one
# nearby. Prevents wall-stuck enemies the bot can never reach.
func _cleanup_oob_enemies() -> void:
	if _grid.is_empty():
		return
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var pos: Vector2 = (e as Node2D).global_position
		var tx: int = int(pos.x / float(TILE))
		var ty: int = int(pos.y / float(TILE))
		var oob: bool = tx < 0 or tx >= GRID_W or ty < 0 or ty >= GRID_H
		if oob:
			(e as Node).queue_free()
			continue
		if int((_grid[ty] as Array)[tx]) != FLOOR:
			var nearest := _nearest_floor_tile(tx, ty)
			if nearest.x >= 0:
				(e as Node2D).global_position = _tile_center(nearest)
			else:
				(e as Node).queue_free()

# Spiral-search outward for the nearest FLOOR tile within ~7 rings
func _nearest_floor_tile(tx: int, ty: int) -> Vector2i:
	for r in range(1, 8):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue   # only check the perimeter of this ring
				var nx: int = tx + dx
				var ny: int = ty + dy
				if nx < 0 or nx >= GRID_W or ny < 0 or ny >= GRID_H:
					continue
				if int((_grid[ny] as Array)[nx]) == FLOOR:
					return Vector2i(nx, ny)
	return Vector2i(-1, -1)

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

func _spawn_exit_portal(pos: Vector2) -> void:
	var ex := Area2D.new()
	ex.set_script(EXIT_PORTAL_SCRIPT)
	ex.position = pos
	add_child(ex)

# Lava Rift "eruption" event — picks a floor tile within a few tiles of
# the player, shows a 3-second telegraph (pulsing red ASCII glyph), then
# spawns a real LavaTile at that spot.
func _spawn_eruption_near_player() -> void:
	var ply := get_tree().get_first_node_in_group("player")
	if ply == null:
		return
	var ply_tile := Vector2i(int(ply.global_position.x / float(TILE)),
		int(ply.global_position.y / float(TILE)))
	# Try up to 8 nearby tiles; pick the first one that's actually on a
	# floor (not a wall, not already a hazard cell).
	var candidates: Array = []
	for _i in 12:
		var dx := randi_range(-5, 5)
		var dy := randi_range(-5, 5)
		if dx * dx + dy * dy < 4:
			continue   # too close to the player — would feel unfair
		var t := ply_tile + Vector2i(dx, dy)
		if t.y < 0 or t.y >= _grid.size():
			continue
		if t.x < 0 or t.x >= (_grid[t.y] as Array).size():
			continue
		if int((_grid[t.y] as Array)[t.x]) != 0:   # FLOOR == 0
			continue
		candidates.append(t)
	if candidates.is_empty():
		return
	var tile: Vector2i = candidates[randi() % candidates.size()]
	var pos := _tile_center(tile)

	# Telegraph — just the impact-footprint ring (the "(!)" glyph was
	# removed per design: it read as a confusing "spawn" marker). The ring
	# still gives a fair tell that lava is about to erupt here.
	if GameState.active_rig != null and is_instance_valid(GameState.active_rig) \
			and GameState.active_rig.has_method("spawn_ring_2d"):
		GameState.active_rig.spawn_ring_2d(pos, "x",
			Color(1.0, 0.30, 0.05, 0.85), 0.40, 0.40, 16, 3.0, 0.009, 0.05)

	# Spawn the actual lava tile after the telegraph completes. Reuses
	# the same script-instantiation pattern the static hazard pass uses.
	var t := get_tree().create_timer(3.0)
	t.timeout.connect(func() -> void:
		if not is_instance_valid(self):
			return
		var lava: Node = LAVA_TILE_SCRIPT.new()
		lava.position = pos
		lava.set("lifetime", 10.0)
		add_child(lava))

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

# One rival wizard sentry per portal room — uses the player's "(o)" silhouette
# in a randomized robe color and fires a real, lootable wand. Stationed on
# the opposite side of the room from the portal so the player has to engage
# rather than dance straight through.
func _spawn_portal_wizard(room: Rect2i) -> void:
	var wiz := WIZARD_SCENE.instantiate()
	# Offset away from the portal tile so the wizard isn't standing on the
	# portal itself. Portal sits at room center; nudge the wizard a couple
	# tiles aside, _safe_pos_in_room snaps it back to a floor tile if the
	# offset lands on a wall.
	var dx := -2 if randf() > 0.5 else 2
	var dy := -2 if randf() > 0.5 else 2
	wiz.position = _safe_pos_in_room(room, dx, dy)
	# Portal lock — Portal.gd treats this group as a gate, same as bosses.
	# Other wizards spawned by random encounters don't get this group, so
	# only the sentinel-wizard at the portal blocks progress.
	wiz.add_to_group("portal_wizard")
	$Enemies.add_child(wiz)

@warning_ignore("integer_division")
func _spawn_enemies(player_room: Rect2i, skip_room: Rect2i = Rect2i()) -> void:
	var diff        := GameState.difficulty
	# Higher difficulty: fewer but bulkier enemies. Health scales hard so each
	# foe is a real threat, while density falls off so rooms don't get crowded.
	# Damage scaling is applied separately in Player.take_damage.
	# HP multiplier per difficulty tier. Bumped 0.70 → 1.0 — the bot's wand
	# damage scales hard with INT/level/rarity, so HP needs to keep up.
	# Spiders/chasers stay poppy because their base HP is small (5–7); the
	# multiplier separates feels-tankier vs feels-fragile by the *base*,
	# not the multiplier itself.
	# Regular-enemy HP scaling — gentler (0.5 slope) than the old 1.0
	# slope. Combined with the doubled base HP across the regular roster,
	# this gives chunkier-feeling enemies up front and a more predictable
	# HP curve at deep difficulty (instead of HP exploding linearly).
	var health_mult := 1.0 + diff * 0.5
	var player_center := _tile_center(player_room.get_center())
	# Density peaks near diff=1 and falls off sharply — bulk + damage carry the
	# Spawn density grows with difficulty (each +1.0 = +25 %), but capped at
	# 2.0× so very-high-tier floors stay traversable. Past ~150 enemies the
	# room-clear loop becomes a slog regardless of player power.
	var density_mult: float = clampf(1.0 + maxf(0.0, diff - 1.0) * 0.25, 0.50, 2.0)

	for _r in _rooms:
		var room: Rect2i = _r
		if room == player_room or room == skip_room:
			continue
		if _themed_rooms.has(room):
			continue   # themed encounter already populated this room
		if room.size.x < 4 or room.size.y < 4:
			continue

		# Proximity penalty — rooms close to spawn get fewer enemies on low diff
		var room_center := _tile_center(room.get_center())
		var dist_to_player := player_center.distance_to(room_center)
		var prox_mult: float = 1.0
		if dist_to_player < 320.0:
			# Adjacent / near rooms — heavily reduce on low diff, full on high
			prox_mult = clampf(0.10 + (diff - 1.0) * 0.45, 0.0, 1.0)
		elif dist_to_player < 600.0:
			prox_mult = clampf(0.45 + (diff - 1.0) * 0.30, 0.0, 1.0)
		# Skip nearby rooms entirely on lowest difficulties
		if diff < 1.4 and dist_to_player < 320.0:
			continue

		var area: int   = room.size.x * room.size.y
		# Per-room budget no longer adds raw +diff — density_mult is the only
		# difficulty knob on count so higher tiers actually spawn fewer enemies.
		@warning_ignore("integer_division")
		var raw_budget: int = max(1, area / 18 + 1)
		var budget: int = max(0, int(round(float(raw_budget) * density_mult * prox_mult)))
		if budget <= 0:
			continue

		# Biome-themed enemy weighting: each biome favours a flavour of foe.
		# Multipliers ≥ 1 — the cap on each count line below clamps the actual
		# spawn so this just nudges the *odds* per type rather than blowing up
		# the total budget.
		var w_chaser:    float = 1.0
		var w_shooter:   float = 1.0
		var w_tank:      float = 1.0
		var w_sniper:    float = 1.0
		var w_summoner:  float = 1.0
		var w_enchanter: float = 1.0
		var w_archer:    float = 1.0
		var w_spiral:    float = 1.0
		var w_grenadier: float = 1.0
		var w_charger:   float = 1.0
		var w_minelayer: float = 1.0
		var w_beam:      float = 1.0
		var w_missile:   float = 1.0
		var w_spider:    float = 1.0
		match GameState.biome:
			1:   # Catacombs — undead/poison: more summons & enchantments
				w_summoner  = 2.2
				w_enchanter = 2.0
				w_spider    = 1.6   # creepy crawlies
			2:   # Ice Cavern — long-range/precision
				w_sniper    = 2.2
				w_archer    = 1.8
				w_beam      = 1.6
				w_chaser    = 0.6   # slow biome — fewer rushers
			3:   # Lava Rift — aggressive/explosive
				w_grenadier = 2.4
				w_charger   = 2.2
				w_minelayer = 1.8
				w_spiral    = 1.4
				w_sniper    = 0.6
			_:   # Dungeon — balanced mix (default weights)
				pass

		var n_chasers: int    = randi_range(0, min(budget, int(round((3 + int(diff)) * w_chaser))))
		budget = max(0, budget - n_chasers)
		var n_shooters: int   = randi_range(0, min(budget, int(round((2 + int(diff * 0.5)) * w_shooter))))
		budget = max(0, budget - n_shooters)
		var n_enchanters: int = randi_range(0, min(budget, int(round((1 + int(diff * 0.3)) * w_enchanter))))
		budget = max(0, budget - n_enchanters)
		var n_tanks: int      = randi_range(0, min(budget, int(round((1 + int(diff * 0.3)) * w_tank))))
		budget = max(0, budget - n_tanks)
		var n_snipers: int    = randi_range(0, min(budget, int(round((1 + int(diff * 0.3)) * w_sniper))))
		budget = max(0, budget - n_snipers)
		var n_summoners: int  = randi_range(0, min(budget, int(round((1 + int(diff * 0.2)) * w_summoner))))
		budget = max(0, budget - n_summoners)
		var n_archers: int    = randi_range(0, min(budget, int(round((1 + int(diff * 0.3)) * w_archer))))
		budget = max(0, budget - n_archers)
		var n_spirals: int    = randi_range(0, min(budget, int(round((1 + int(diff * 0.2)) * w_spiral))))
		budget = max(0, budget - n_spirals)
		var n_grenadiers: int = randi_range(0, min(budget, int(round((1 + int(diff * 0.25)) * w_grenadier))))
		budget = max(0, budget - n_grenadiers)
		var n_chargers: int   = randi_range(0, min(budget, int(round((1 + int(diff * 0.3)) * w_charger))))
		budget = max(0, budget - n_chargers)
		var n_minelayers: int = randi_range(0, min(budget, int(round((1 + int(diff * 0.2)) * w_minelayer))))
		budget = max(0, budget - n_minelayers)
		var n_beams: int      = randi_range(0, min(budget, int(round((1 + int(diff * 0.15)) * w_beam))))
		budget = max(0, budget - n_beams)
		var n_missiles: int   = randi_range(0, min(budget, int(round((1 + int(diff * 0.2)) * w_missile))))
		budget = max(0, budget - n_missiles)
		# Spiders come in swarms — capped by the remaining room budget so they
		# can't bypass other types and explode in count at high difficulty.
		var spider_min: int = 0 if diff < 2.0 else 1
		var spider_max: int = mini(budget, 3 + int(diff * 0.15))
		spider_max = maxi(spider_min, int(round(float(spider_max) * prox_mult * w_spider)))
		var n_spiders: int    = randi_range(spider_min, maxi(spider_min, spider_max))

		_queue_enemy(CHASER_SCENE,    room, health_mult, n_chasers)
		_queue_enemy(SHOOTER_SCENE,   room, health_mult, n_shooters)
		_queue_enemy(ENCHANTER_SCENE, room, health_mult, n_enchanters)
		_queue_enemy(TANK_SCENE,      room, health_mult, n_tanks)
		_queue_enemy(SNIPER_SCENE,    room, health_mult, n_snipers)
		_queue_enemy(SUMMONER_SCENE,  room, health_mult, n_summoners)
		_queue_enemy(ARCHER_SCENE,    room, health_mult, n_archers)
		_queue_enemy(SPIRAL_SCENE,    room, health_mult, n_spirals)
		_queue_enemy(GRENADIER_SCENE, room, health_mult, n_grenadiers)
		_queue_enemy(CHARGER_SCENE,   room, health_mult, n_chargers)
		_queue_enemy(MINELAYER_SCENE, room, health_mult, n_minelayers)
		_queue_enemy(BEAMSWEEP_SCENE, room, health_mult, n_beams)
		_queue_enemy(MISSILE_SCENE,   room, health_mult, n_missiles)
		_queue_enemy(SPIDER_SCENE,    room, health_mult, n_spiders)

		# New-enemy seeding — small per-room counts so they show up as
		# unusual surprises, not the dominant fill. Skipped on the
		# starter room so the very first encounters stay readable.
		if room != _rooms[0]:
			var n_bombers: int    = randi_range(0, 1) if diff >= 1.5 else 0
			var n_berserkers: int = randi_range(0, 1) if diff >= 2.0 else 0
			var n_phantoms: int   = randi_range(0, 1) if diff >= 2.5 else 0
			var n_banshees: int   = 1 if diff >= 3.0 and randf() < 0.30 else 0
			var n_reflectors: int = 1 if diff >= 3.5 and randf() < 0.25 else 0
			_queue_enemy(BOMBER_SCENE,    room, health_mult, n_bombers)
			_queue_enemy(BERSERKER_SCENE, room, health_mult, n_berserkers)
			_queue_enemy(PHANTOM_SCENE,   room, health_mult, n_phantoms)
			_queue_enemy(BANSHEE_SCENE,   room, health_mult, n_banshees)
			_queue_enemy(REFLECTOR_SCENE, room, health_mult, n_reflectors)
			# Splitter (low frequency, any difficulty) + Stalker (rare,
			# higher diff). Stalker's hide-then-rush pattern requires a
			# bit of arena to read — gate behind diff 2.5.
			var n_splitters: int = 1 if randf() < 0.35 else 0
			var n_stalkers: int  = 1 if diff >= 2.5 and randf() < 0.20 else 0
			_queue_enemy(SPLITTER_SCENE, room, health_mult, n_splitters)
			_queue_enemy(STALKER_SCENE,  room, health_mult, n_stalkers)
			# Biome-specific enemies — Catacombs / Ice Cavern / Lava Rift
			# each get one signature creature in addition to the generic
			# pool, so the biome flavor reads at the enemy level too.
			match GameState.biome:
				1:  # Catacombs
					_queue_enemy(BONEDRAKE_SCENE, room, health_mult,
						randi_range(0, 1) if diff >= 1.5 else 0)
				2:  # Ice Cavern
					_queue_enemy(FROSTSENT_SCENE, room, health_mult,
						1 if diff >= 2.0 and randf() < 0.40 else 0)
				3:  # Lava Rift
					_queue_enemy(MAGMASLUG_SCENE, room, health_mult,
						randi_range(0, 1) if diff >= 1.5 else 0)

	# Spawn closer rooms first so what the player can actually see populates
	# immediately, while distant rooms drain in the background. Cuts perceived
	# spawn lag dramatically without changing total work.
	var anchor: Vector2 = player_center
	_dungeon_spawn_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra: Rect2i = a["room"]
		var rb: Rect2i = b["room"]
		var ca: Vector2 = _tile_center(ra.get_center())
		var cb: Vector2 = _tile_center(rb.get_center())
		return ca.distance_squared_to(anchor) < cb.distance_squared_to(anchor))
	# Cap total queue size after the sort. Themed rooms have already placed
	# their spawns synchronously (flat, hand-tuned counts), so subtract those
	# from the budget and trim the *far* end of the queue — the closest
	# rooms keep their full population and faraway rooms thin out instead.
	var existing_count: int = get_tree().get_nodes_in_group("enemy").size()
	var remaining_budget: int = maxi(0, MAX_DUNGEON_ENEMIES - existing_count)
	if _dungeon_spawn_queue.size() > remaining_budget:
		_dungeon_spawn_queue.resize(remaining_budget)
	# Drain the front of the queue synchronously — these are the rooms
	# closest to the player after the distance sort, so they end up
	# populated *before* the first frame renders. Avoids the noticeable gap
	# between entering the level and the first enemy showing up.
	for _i in mini(DUNGEON_SPAWN_INITIAL_DRAIN, _dungeon_spawn_queue.size()):
		var data: Dictionary = _dungeon_spawn_queue.pop_front()
		_place_enemy(data["scene"] as PackedScene,
			data["room"] as Rect2i,
			float(data["hp_mult"]))
	# Front-load the per-frame spawn rate for ~1.5 seconds after that.
	_dungeon_spawn_burst_t = DUNGEON_SPAWN_BURST_DURATION

func _queue_enemy(scene: PackedScene, room: Rect2i, health_mult: float, count: int) -> void:
	for _i in count:
		_dungeon_spawn_queue.append({"scene": scene, "room": room, "hp_mult": health_mult})

func _place_enemy(scene: PackedScene, room: Rect2i, health_mult: float) -> Node:
	var enemy := scene.instantiate()
	enemy.position = _random_pos_in_room(room)
	if health_mult != 1.0 and "max_health" in enemy:
		enemy.max_health = maxi(1, int(enemy.max_health * health_mult))
	# Higher tiers also speed enemies up, capped so they stay catchable
	var spd_mult: float = clampf(1.0 + maxf(0.0, GameState.difficulty - 1.0) * 0.06, 1.0, 1.40)
	if spd_mult > 1.0:
		if "speed" in enemy:
			enemy.speed = enemy.speed * spd_mult
		if "move_speed" in enemy:
			enemy.move_speed = enemy.move_speed * spd_mult

	# 15% chance of elite: doubled HP, random modifier
	# Elite chance climbs with difficulty: 15 % base, +5 % per +1.0 diff,
	# capped at 45 % so floors don't become uniformly elite.
	var elite_chance: float = clampf(0.15 + maxf(0.0, GameState.difficulty - 1.0) * 0.05, 0.15, 0.45)
	if randf() < elite_chance and "is_elite" in enemy:
		enemy.is_elite = true
		if "max_health" in enemy:
			enemy.max_health = maxi(1, enemy.max_health * 2)
		if "elite_modifier" in enemy:
			var mod := randi_range(1, 5)
			enemy.elite_modifier = mod
			if mod == 2 and "_split_scene" in enemy:
				enemy._split_scene = scene
			if mod == 4 and "speed" in enemy:
				enemy.speed = enemy.speed * 1.6
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
				4:  # Haste – bright green
					elite_col = Color(0.3, 1.0, 0.4)
					elite_out = Color(0.0, 0.35, 0.05)
				5:  # Volatile – deep orange
					elite_col = Color(1.0, 0.45, 0.0)
					elite_out = Color(0.45, 0.10, 0.0)
				_:
					elite_col = Color(1.0, 0.75, 0.0)
					elite_out = Color(0.5, 0.2, 0.0)
			lbl.add_theme_color_override("font_color", elite_col)
			lbl.add_theme_color_override("font_outline_color", elite_out)
			var mod_names := ["", "SHIELDED", "SPLITTING", "ENRAGED", "HASTE", "VOLATILE"]
			if mod > 0:
				FloatingText.spawn_str(enemy.global_position + Vector2(0.0, -24.0), mod_names[mod], elite_col, get_tree().current_scene)
	return enemy

# ── Floor modifier roll & application ────────────────────────────────────────

func _roll_floor_modifier() -> void:
	var is_boss := GameState.portals_used > 0 and GameState.portals_used % 5 == 4
	var is_shop := GameState.portals_used > 0 and GameState.portals_used % 5 == 0
	GameState.floor_modifier = ""
	GameState.floor_modifiers = []
	if is_boss or is_shop:
		return
	# Trigger and stack count escalate with difficulty:
	#   diff <4: 55 % chance for 1 modifier (legacy behavior).
	#   diff ≥4: always 1 modifier.
	#   diff ≥6: always 2 stacked modifiers (no duplicates).
	var diff := GameState.difficulty
	var force_one: bool = diff >= 4.0
	var stack_two: bool = diff >= 6.0
	if not force_one and randf() > 0.55:
		return
	var keys := FLOOR_MODIFIERS.keys()
	if keys.is_empty():
		return
	keys.shuffle()
	GameState.floor_modifiers.append(String(keys[0]))
	if stack_two and keys.size() > 1:
		GameState.floor_modifiers.append(String(keys[1]))
	# Keep legacy field in sync with the primary modifier.
	GameState.floor_modifier = GameState.floor_modifiers[0]

func _apply_floor_modifier_to_enemy(enemy: Node) -> void:
	# Iterate every active modifier so stacked floors apply both effects.
	for mod in GameState.floor_modifiers:
		_apply_one_floor_modifier_to_enemy(enemy, String(mod))

func _apply_one_floor_modifier_to_enemy(enemy: Node, mod_name: String) -> void:
	# Modifier intensity ramps up with difficulty so a CURSED floor at diff 6
	# is meaningfully scarier than at diff 1. Each 1.0 of difficulty above
	# the start adds another step of effect strength.
	var diff_step: float = maxf(0.0, GameState.difficulty - 1.0)
	match mod_name:
		"cursed":
			# 1.5× → 1.5 + 0.10*diff_step (e.g. diff 4 → 1.80×, diff 6 → 2.00×)
			var mult := 1.5 + 0.10 * diff_step
			if "speed" in enemy:
				enemy.speed = enemy.speed * mult
			if "move_speed" in enemy:
				enemy.move_speed = enemy.move_speed * mult
		"bloodlust":
			# 2× → 2 + 0.25*diff_step (diff 4 → 2.75×, diff 6 → 3.25×)
			var mult := 2.0 + 0.25 * diff_step
			if "max_health" in enemy:
				enemy.max_health = maxi(1, int(round(float(enemy.max_health) * mult)))
		"haunted":
			# Already turns every enemy into an elite. Add +1 max_health step
			# per difficulty so high-diff haunted floors hit harder than
			# regular elites would.
			if "is_elite" in enemy and not enemy.is_elite:
				enemy.is_elite = true
				if "max_health" in enemy:
					var mult := 2.0 + 0.20 * diff_step
					enemy.max_health = maxi(1, int(round(float(enemy.max_health) * mult)))
				if "elite_modifier" in enemy:
					enemy.elite_modifier = randi_range(1, 3)

# Spawns a wave of aggro'd enemies inside `room` for an ambush. Returns the
# spawned nodes so the controller can watch for "all dead". Reuses _place_enemy.
func spawn_ambush_wave(room: Rect2i, count: int) -> Array:
	var pool: Array[PackedScene] = [CHASER_SCENE, SHOOTER_SCENE, ARCHER_SCENE]
	var hp_mult: float = 1.0 + clampf(maxf(0.0, GameState.difficulty - 1.0) * 0.10, 0.0, 1.0)
	var spawned: Array = []
	for i in count:
		var scene: PackedScene = pool[randi() % pool.size()]
		var e: Node = _place_enemy(scene, room, hp_mult)
		if e != null:
			if "_has_aggro" in e:
				e.set("_has_aggro", true)
			spawned.append(e)
	return spawned

# DOOM-style sector lighting: tag a minority of rooms DARK (torch-only) or
# FLICKER (broken light). The spawn room (index 0) stays NORMAL so the player
# isn't dropped into darkness. Assigned once per floor.
func _assign_room_lighting() -> void:
	_room_light_levels = []
	for i in _rooms.size():
		if i == 0:
			_room_light_levels.append(0)   # spawn room always lit
			continue
		var r := randf()
		if r < 0.16:
			_room_light_levels.append(1)   # DARK
		elif r < 0.24:
			_room_light_levels.append(2)   # FLICKER
		else:
			_room_light_levels.append(0)   # NORMAL

# Doorway tiles for a single room — floor tiles just outside its perimeter where
# a corridor punches through. Single-room version of _collect_doorway_tiles().
func _room_doorway_tiles(room: Rect2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for x in range(room.position.x, room.position.x + room.size.x):
		var top_y: int = room.position.y - 1
		if top_y >= 0 and x >= 0 and x < GRID_W and int((_grid[top_y] as Array)[x]) == FLOOR:
			tiles.append(Vector2i(x, top_y))
		var bot_y: int = room.position.y + room.size.y
		if bot_y < GRID_H and x >= 0 and x < GRID_W and int((_grid[bot_y] as Array)[x]) == FLOOR:
			tiles.append(Vector2i(x, bot_y))
	for y in range(room.position.y, room.position.y + room.size.y):
		var left_x: int = room.position.x - 1
		if left_x >= 0 and y >= 0 and y < GRID_H and int((_grid[y] as Array)[left_x]) == FLOOR:
			tiles.append(Vector2i(left_x, y))
		var right_x: int = room.position.x + room.size.x
		if right_x < GRID_W and y >= 0 and y < GRID_H and int((_grid[y] as Array)[right_x]) == FLOOR:
			tiles.append(Vector2i(right_x, y))
	return tiles

# Places one ambush room per floor (from floor 2): a room with 1-2 doorways that
# seals + springs a wave when entered, reopening on clear. Graceful skip if none fit.
func _spawn_ambush() -> void:
	if GameState.portals_used < 1:
		return
	var choices: Array[Rect2i] = []
	for i in range(1, _rooms.size()):   # skip the player spawn room (index 0)
		var room: Rect2i = _rooms[i]
		# Skip tiny sample rooms and huge boss-arena-scale rooms.
		if room.size.x < 5 or room.size.y < 5 or room.size.x > 16 or room.size.y > 16:
			continue
		var dn: int = _room_doorway_tiles(room).size()
		if dn >= 1 and dn <= 2:
			choices.append(room)
	if choices.is_empty():
		return
	var pick: Rect2i = choices[randi() % choices.size()]
	var ambush := AMBUSH_CONTROLLER_SCENE.instantiate()
	ambush.set("room", pick)
	ambush.set("seal_tiles", _room_doorway_tiles(pick))
	ambush.set("wave_count", mini(3 + int(GameState.difficulty * 0.5), 7))
	ambush.position = _tile_center(pick.get_center())
	add_child(ambush)

# Places one shootable switch wired to a door sealing a dead-end loot alcove.
# Optional reward path — never gates the main route. Graceful skip if no dead-end.
func _spawn_switch_alcove() -> void:
	if GameState.portals_used < 1:
		return
	# Find a dead-end corridor tile: FLOOR with exactly one FLOOR 4-neighbour,
	# outside any room, away from the player spawn.
	var spawn_center := _tile_center(_rooms[0].get_center()) if _rooms.size() > 0 else Vector2.ZERO
	var ends: Array[Vector2i] = []
	for ty in range(2, GRID_H - 2):
		for tx in range(2, GRID_W - 2):
			if _grid[ty][tx] != FLOOR or _in_any_room(tx, ty):
				continue
			var nbrs: Array[Vector2i] = []
			if _grid[ty - 1][tx] == FLOOR: nbrs.append(Vector2i(tx, ty - 1))
			if _grid[ty + 1][tx] == FLOOR: nbrs.append(Vector2i(tx, ty + 1))
			if _grid[ty][tx - 1] == FLOOR: nbrs.append(Vector2i(tx - 1, ty))
			if _grid[ty][tx + 1] == FLOOR: nbrs.append(Vector2i(tx + 1, ty))
			if nbrs.size() != 1:
				continue
			if _tile_center(Vector2i(tx, ty)).distance_to(spawn_center) < 200.0:
				continue
			ends.append(Vector2i(tx, ty))
	if ends.is_empty():
		return
	var dead: Vector2i = ends[randi() % ends.size()]
	# The single neighbour is the mouth of the alcove — seal it with a closed door.
	var mouth := dead
	if _grid[dead.y - 1][dead.x] == FLOOR: mouth = Vector2i(dead.x, dead.y - 1)
	elif _grid[dead.y + 1][dead.x] == FLOOR: mouth = Vector2i(dead.x, dead.y + 1)
	elif _grid[dead.y][dead.x - 1] == FLOOR: mouth = Vector2i(dead.x - 1, dead.y)
	elif _grid[dead.y][dead.x + 1] == FLOOR: mouth = Vector2i(dead.x + 1, dead.y)

	# The switch must sit on a reachable FLOOR tile past the mouth, else the loot
	# would be sealed forever. Require it before committing the alcove.
	var dir := mouth - dead
	var back := mouth + dir * 2
	if not _is_floor_in_bounds(back):
		back = mouth + dir
	if not _is_floor_in_bounds(back) or back == mouth:
		return   # no valid switch spot — skip this alcove

	# Loot in the dead-end.
	var bag := LOOT_BAG_SCENE.instantiate()
	bag.global_position = _tile_center(dead)
	add_child(bag)
	# Closed remote-only door at the mouth.
	var door := DOOR_SCENE.instantiate()
	var ct: Array[Vector2i] = [mouth]
	door.set("cover_tiles", ct)
	door.set("corridor_axis", 0)
	door.set("remote_only", true)
	door.position = _tile_center(mouth)
	add_child(door)
	# Switch in the open corridor, wired to the alcove door.
	var sw := SWITCH_SCENE.instantiate()
	sw.set("_target", door)
	sw.position = _tile_center(back)
	add_child(sw)

func _is_floor_in_bounds(t: Vector2i) -> bool:
	return t.x >= 0 and t.x < GRID_W and t.y >= 0 and t.y < GRID_H \
		and int((_grid[t.y] as Array)[t.x]) == FLOOR

func _show_modifier_banner() -> void:
	if GameState.floor_modifiers.is_empty():
		return
	var canvas := CanvasLayer.new()
	canvas.layer = 20
	get_tree().current_scene.add_child(canvas)

	# Show every active modifier joined into one banner so stacked floors
	# read clearly: "[ CURSED + BLOODLUST ]\nfaster + tankier".
	var names: Array = []
	var descs: Array = []
	for m in GameState.floor_modifiers:
		if m in FLOOR_MODIFIERS:
			var entry: Dictionary = FLOOR_MODIFIERS[m]
			names.append(String(entry["name"]))
			descs.append(String(entry["desc"]))
	if names.is_empty():
		canvas.queue_free()
		return
	var lbl := Label.new()
	lbl.text = "[ %s ]\n%s" % [" + ".join(names), " · ".join(descs)]
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
	if SoundManager:
		SoundManager.play("boss_phase", randf_range(0.85, 1.0))

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
	bag.position = _safe_loot_pos(_tile_center(room.get_center()), room)
	bag.set("items", [ItemDB.random_drop(), ItemDB.random_drop(), ItemDB.random_drop()])
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
	# Spawn an extra champion on harder floors. Each champion uses its own
	# room from the candidate list so the encounter spaces out instead of
	# stacking two giants in the same square.
	var champ_count: int = 1
	if GameState.difficulty >= 4.0:
		champ_count = 2
	for ci in mini(champ_count, candidates.size()):
		_spawn_one_champion(candidates[ci])
	return

# Champion-room body extracted so we can spawn multiple on high-tier floors.
func _spawn_one_champion(room: Rect2i) -> void:
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

# ── Themed rooms ─────────────────────────────────────────────────────────────
# Hand-curated single-flavor encounters: spider dens, sniper alleys, charger
# pits, etc. Replaces the regular enemy mix in 1-2 rooms per floor so walking
# in feels like stumbling into a *thing* rather than another generic room.
# Each theme is meant to be mean — the loot bag in the centre is the carrot.

# Arena floors fill the single big room with a varied minion mix in
# addition to the centre-staged boss + wizard. Spawns are biased away
# from the player's corner so the bot has a beat to assess before being
# rushed. Density scales with difficulty using the same slope as the
# regular spawn pass.
func _spawn_arena_enemies(arena: Rect2i, player_pos: Vector2) -> void:
	var diff: float = GameState.difficulty
	var health_mult: float = 1.0 + diff * 0.5
	# Roster — biome-aware mix, slightly weighted toward melee + ranged
	# mid-tiers so the arena reads as a "everything at once" brawl.
	var roster: Array = [CHASER_SCENE, SHOOTER_SCENE, ARCHER_SCENE,
		SNIPER_SCENE, CHARGER_SCENE, TANK_SCENE, SPIDER_SCENE,
		ENCHANTER_SCENE, GRENADIER_SCENE]
	match GameState.biome:
		1:   # Catacombs
			roster.append(PHANTOM_SCENE)
			roster.append(BANSHEE_SCENE)
			roster.append(SUMMONER_SCENE)
		2:   # Ice Cavern
			roster.append(FROSTSENT_SCENE)
			roster.append(BEAMSWEEP_SCENE)
		3:   # Lava Rift
			roster.append(MAGMASLUG_SCENE)
			roster.append(BOMBER_SCENE)
			roster.append(BERSERKER_SCENE)
	# Total minion count scales with arena area + difficulty.
	var base_count: int = clampi(int(arena.size.x * arena.size.y / 70), 14, 28)
	var count: int = int(base_count * clampf(1.0 + (diff - 1.0) * 0.20, 0.7, 1.8))
	var placed: int = 0
	for _i in count * 3:   # generous attempts since we filter by distance
		if placed >= count:
			break
		var tx: int = randi_range(arena.position.x + 2,
			arena.position.x + arena.size.x - 3)
		var ty: int = randi_range(arena.position.y + 2,
			arena.position.y + arena.size.y - 3)
		if _grid[ty][tx] != FLOOR:
			continue
		var p: Vector2 = _tile_center(Vector2i(tx, ty))
		# Keep a 6-tile breathing radius around the player's spawn corner so
		# the player doesn't get instantly surrounded the moment the floor
		# loads.
		if p.distance_to(player_pos) < float(TILE) * 6.0:
			continue
		var scene: PackedScene = roster[randi() % roster.size()] as PackedScene
		var enemy := scene.instantiate()
		enemy.position = p
		if "max_health" in enemy:
			enemy.max_health = maxi(1, int(enemy.max_health * health_mult))
		$Enemies.add_child(enemy)
		placed += 1
	# Banner — make it clear the floor is a planned brawl.
	BossIntro.show_for(get_tree().current_scene,
		"OPEN ARENA", Color(1.0, 0.55, 0.20))

func _spawn_themed_rooms(player_room: Rect2i, skip_room: Rect2i) -> void:
	var candidates: Array = []
	for _r in _rooms:
		var room: Rect2i = _r
		if room == player_room or room == skip_room:
			continue
		# Themes need a bit of breathing room so the encounter reads clearly.
		if room.size.x < 8 or room.size.y < 7:
			continue
		# Don't trample rooms that already host special content (we run before
		# hazard/challenge but check anyway to be safe if someone reorders).
		candidates.append(room)
	if candidates.is_empty():
		return
	candidates.shuffle()
	# Themed-room count climbs with difficulty: 1 base, 2 at ≥1.6, 3 at
	# ≥3.0, 4 at ≥5.0. Caps at the number of qualifying candidate rooms.
	var max_themes: int = 1
	if GameState.difficulty >= 5.0:
		max_themes = 4
	elif GameState.difficulty >= 3.0:
		max_themes = 3
	elif GameState.difficulty >= 1.6:
		max_themes = 2
	var count := mini(randi_range(1, max_themes), candidates.size())
	for i in count:
		var room: Rect2i = candidates[i]
		_themed_rooms.append(room)
		_make_themed_room(room)

# Themes — each one is a small recipe stamped into a room. Counts and HP
# multipliers are intentionally a notch above the regular spawn pass so the
# theme actually feels different (and dangerous). All themes drop a 2-item
# loot bag in the centre as a reward for clearing.
func _make_themed_room(room: Rect2i) -> void:
	var diff := GameState.difficulty
	# Themed rooms use the same regular-mob slope as the rest of the
	# floor (0.5) so a "Charger Pit" doesn't feel out of step with the
	# surrounding population.
	var hp_mult: float = 1.0 + diff * 0.5
	var themes: Array = [
		{"name": "SPIDER DEN",     "tint": Color(0.40, 0.05, 0.45, 0.20), "color": Color(1.0, 0.55, 1.0)},
		{"name": "SNIPER ALLEY",   "tint": Color(0.05, 0.30, 0.70, 0.20), "color": Color(0.6, 0.85, 1.0)},
		{"name": "CHARGER PIT",    "tint": Color(0.80, 0.20, 0.05, 0.22), "color": Color(1.0, 0.55, 0.25)},
		{"name": "MINEFIELD",      "tint": Color(0.55, 0.45, 0.10, 0.22), "color": Color(1.0, 0.85, 0.35)},
		{"name": "BEAM CROSSFIRE", "tint": Color(0.05, 0.55, 0.55, 0.22), "color": Color(0.45, 1.0, 1.0)},
		{"name": "SUMMONER NEST",  "tint": Color(0.30, 0.05, 0.55, 0.22), "color": Color(0.85, 0.55, 1.0)},
		{"name": "SPIRAL CHOIR",   "tint": Color(0.55, 0.05, 0.55, 0.22), "color": Color(1.0, 0.45, 1.0)},
		{"name": "GRENADE GAUNTLET", "tint": Color(0.65, 0.30, 0.05, 0.22), "color": Color(1.0, 0.65, 0.25)},
		{"name": "ENCHANTED HALL", "tint": Color(0.10, 0.45, 0.15, 0.22), "color": Color(0.55, 1.0, 0.65)},
		# ── New themes ─────────────────────────────────────────────────────
		{"name": "TANK YARD",      "tint": Color(0.35, 0.30, 0.10, 0.22), "color": Color(0.95, 0.85, 0.30)},
		{"name": "PHANTOM HALL",   "tint": Color(0.20, 0.30, 0.55, 0.22), "color": Color(0.65, 0.80, 1.0)},
		{"name": "BOMBER COVE",    "tint": Color(0.65, 0.35, 0.10, 0.22), "color": Color(1.0, 0.50, 0.15)},
		{"name": "FROST CAVERN",   "tint": Color(0.10, 0.30, 0.55, 0.22), "color": Color(0.65, 0.90, 1.0)},
		{"name": "REFLECTOR LAB",  "tint": Color(0.10, 0.50, 0.45, 0.22), "color": Color(0.55, 1.0, 0.85)},
		{"name": "BERSERKER ARENA", "tint": Color(0.75, 0.10, 0.05, 0.22), "color": Color(1.0, 0.35, 0.20)},
		# Survival arena — DPS check. Doesn't pre-spawn enemies; instead
		# the room itself becomes a hostile encounter (constant waves)
		# until the timer expires. Handled by SurvivalArena.gd which we
		# instantiate below instead of running the normal _place_enemy path.
		{"name": "SURVIVAL ARENA", "tint": Color(0.55, 0.10, 0.10, 0.30), "color": Color(1.0, 0.40, 0.30)},
	]
	var theme: Dictionary = themes[randi() % themes.size()]

	match String(theme["name"]):
		"SPIDER DEN":
			# Swarm. Spiders + a bulkier "matriarch", traps to punish kiting.
			# Counts trimmed (was 8-12 + 2) to keep the swarm readable and avoid
			# the high-difficulty frame stalls from oversized clusters.
			for _i in randi_range(5, 7):
				_place_enemy(SPIDER_SCENE, room, hp_mult)
			_place_enemy(SPIDER_SCENE, room, hp_mult * 2.2)
			_sprinkle_traps(room, randi_range(2, 4))
		"SNIPER ALLEY":
			# Pure ranged pressure — snipers + archers with no melee filler.
			for _i in randi_range(3, 4):
				_place_enemy(SNIPER_SCENE, room, hp_mult)
			for _i in randi_range(2, 3):
				_place_enemy(ARCHER_SCENE, room, hp_mult)
		"CHARGER PIT":
			# Concentrated melee rush — deliberately mean if you don't have
			# good kiting tools.
			for _i in randi_range(4, 6):
				_place_enemy(CHARGER_SCENE, room, hp_mult * 1.15)
			for _i in 2:
				_place_enemy(CHASER_SCENE, room, hp_mult)
		"MINEFIELD":
			# Movement is dangerous on its own — minelayers keep replenishing.
			for _i in randi_range(2, 3):
				_place_enemy(MINELAYER_SCENE, room, hp_mult * 1.2)
			for _i in randi_range(1, 2):
				_place_enemy(GRENADIER_SCENE, room, hp_mult)
			_sprinkle_traps(room, randi_range(3, 5))
		"BEAM CROSSFIRE":
			# Few enemies but each one paints a deadly arc — the room becomes
			# a moving puzzle of lasers.
			for _i in randi_range(2, 4):
				_place_enemy(BEAMSWEEP_SCENE, room, hp_mult * 1.4)
		"SUMMONER NEST":
			# Two summoners + an enchanter buffing them: pressure compounds
			# fast if you don't focus the support immediately.
			for _i in randi_range(2, 3):
				_place_enemy(SUMMONER_SCENE, room, hp_mult * 1.3)
			for _i in randi_range(1, 2):
				_place_enemy(ENCHANTER_SCENE, room, hp_mult)
			_sprinkle_traps(room, randi_range(2, 4))
		"SPIRAL CHOIR":
			# Bullet-hell room — overlapping spiral patterns force constant
			# motion through narrow gaps.
			for _i in randi_range(3, 4):
				_place_enemy(SPIRAL_SCENE, room, hp_mult * 1.2)
		"GRENADE GAUNTLET":
			for _i in randi_range(3, 5):
				_place_enemy(GRENADIER_SCENE, room, hp_mult * 1.15)
			for _i in 1:
				_place_enemy(MINELAYER_SCENE, room, hp_mult)
		"ENCHANTED HALL":
			# Mid-tier mix all wearing buffs — every enemy feels harder than
			# its base stat block suggests.
			var roster := [SHOOTER_SCENE, ARCHER_SCENE, TANK_SCENE, CHARGER_SCENE]
			for _i in randi_range(4, 5):
				_place_enemy(roster[randi() % roster.size()] as PackedScene, room, hp_mult * 1.4)
			for _i in randi_range(2, 3):
				_place_enemy(ENCHANTER_SCENE, room, hp_mult)
		"TANK YARD":
			# Heavy armour line — 3-4 Tanks with a Shooter back-row. Each
			# Tank is a damage sponge so the room rewards focused fire and
			# proper positioning.
			for _i in randi_range(3, 4):
				_place_enemy(TANK_SCENE, room, hp_mult * 1.25)
			for _i in randi_range(2, 3):
				_place_enemy(SHOOTER_SCENE, room, hp_mult)
		"PHANTOM HALL":
			# Wraith-themed room — Phantoms slip in and out of cover, Banshees
			# scream stunlocks. Light traps trip on careless dashes.
			for _i in randi_range(3, 4):
				_place_enemy(PHANTOM_SCENE, room, hp_mult * 1.15)
			for _i in randi_range(2, 3):
				_place_enemy(BANSHEE_SCENE, room, hp_mult)
			_sprinkle_traps(room, randi_range(1, 3))
		"BOMBER COVE":
			# Stand-off threat — Bombers detonate close-range. Mix in a
			# Reflector so beam-spam doesn't trivialise the room.
			for _i in randi_range(3, 4):
				_place_enemy(BOMBER_SCENE, room, hp_mult * 1.15)
			for _i in 1:
				_place_enemy(REFLECTOR_SCENE, room, hp_mult * 1.2)
		"FROST CAVERN":
			# Ice-themed pocket inside any biome — slow-aim turrets +
			# Frost Sentinels that radiate chill. Plays best in non-Ice
			# biomes where the mechanic is unexpected.
			for _i in randi_range(2, 3):
				_place_enemy(FROSTSENT_SCENE, room, hp_mult * 1.25)
			for _i in randi_range(2, 3):
				_place_enemy(SNIPER_SCENE, room, hp_mult)
		"REFLECTOR LAB":
			# Anti-cheese room — multiple Reflectors that bounce projectiles
			# back. Forces the player to switch off pierce/ricochet wands
			# or eat their own DPS.
			for _i in randi_range(2, 3):
				_place_enemy(REFLECTOR_SCENE, room, hp_mult * 1.2)
			for _i in randi_range(2, 3):
				_place_enemy(ENCHANTER_SCENE, room, hp_mult)
		"BERSERKER ARENA":
			# All-in melee chaos — Berserkers with low cooldowns + a
			# Splitter or two so the pool keeps growing as kills happen.
			for _i in randi_range(3, 5):
				_place_enemy(BERSERKER_SCENE, room, hp_mult * 1.20)
			for _i in randi_range(1, 2):
				_place_enemy(SPLITTER_SCENE, room, hp_mult)
		"SURVIVAL ARENA":
			# Doesn't pre-spawn anything — the SurvivalArena node manages
			# its own wave timer and spawn-portal markers at room corners.
			# When the timer expires it drops a fat loot bag in the centre
			# and unlocks. Early-return so the shared loot-bag drop below
			# isn't placed redundantly.
			var sa: Node = SURVIVAL_ARENA_SCRIPT.new()
			sa.set("room", room)
			sa.set("hp_mult", hp_mult)
			sa.set("theme_color", theme["color"] as Color)
			get_tree().current_scene.add_child(sa)
			# Banner + early return — survival arena writes its own loot.
			FloatingText.spawn_str(_tile_center(room.get_center()) + Vector2(0.0, -36.0),
				String(theme["name"]),
				theme["color"] as Color,
				get_tree().current_scene)
			if SoundManager:
				SoundManager.play("summon", randf_range(0.85, 1.0))
			return

	# Shared reward — themed rooms always drop a centred bag with two items
	# so the player has a tangible payoff for clearing them. _safe_loot_pos
	# nudges the bag away from any shrine / enchant table / sell chest
	# already placed in the same room so the loot doesn't smother the
	# interactable's hint label.
	var bag := LOOT_BAG_SCENE.instantiate()
	bag.position = _safe_loot_pos(_tile_center(room.get_center()), room)
	bag.set("items", [ItemDB.random_drop(), ItemDB.random_drop()])
	add_child(bag)

	# Floating banner so the player immediately knows what kind of room they
	# walked into. Uses the theme's accent color.
	FloatingText.spawn_str(_tile_center(room.get_center()) + Vector2(0.0, -36.0),
		String(theme["name"]),
		theme["color"] as Color,
		get_tree().current_scene)
	if SoundManager:
		SoundManager.play("summon", randf_range(0.85, 1.0))

func _sprinkle_traps(room: Rect2i, count: int) -> void:
	for _i in count:
		for _attempt in 10:
			var tx := randi_range(room.position.x + 1, room.position.x + room.size.x - 2)
			var ty := randi_range(room.position.y + 1, room.position.y + room.size.y - 2)
			if _grid[ty][tx] == FLOOR:
				var trap := SPIKE_TRAP_SCENE.instantiate()
				trap.position = _tile_center(Vector2i(tx, ty))
				add_child(trap)
				break

# ── Biome hazards ─────────────────────────────────────────────────────────────
# Each non-Dungeon biome has its own floor hazard:
#   1 Catacombs   → poison clouds (apply poison + small dmg ticks)
#   2 Ice Cavern  → ice patches (slow the player)
#   3 Lava Rift   → lava tiles (burn dmg ticks)

func _spawn_lava_tiles() -> void:
	if GameState.biome == 0:
		return   # Dungeon — no biome hazard
	var hazard_script
	var count: int
	match GameState.biome:
		1:
			hazard_script = POISON_CLOUD_SCRIPT
			count = randi_range(8, 14)
		2:
			hazard_script = ICE_TILE_SCRIPT
			count = randi_range(12, 22)
		3:
			hazard_script = LAVA_TILE_SCRIPT
			count = randi_range(10, 18)
		_:
			return
	# Density scales with difficulty — +20 % hazards per +1.0 difficulty
	# (capped at +160 % so floors aren't pure damage tiles).
	var diff_mult: float = 1.0 + clampf(maxf(0.0, GameState.difficulty - 1.0) * 0.20, 0.0, 1.6)
	count = int(round(float(count) * diff_mult))
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
				var tile: Node = hazard_script.new()
				tile.position = _tile_center(Vector2i(tx, ty))
				add_child(tile)
				placed += 1
				break

# ── Boss ──────────────────────────────────────────────────────────────────────

# Picks the largest room and stamps a hand-tuned obstacle pattern into it for
# boss fights. The chosen room is *expanded outward* into the surrounding
# walls/corridors so the fight has somewhere grand to play out — bosses are
# big and they need elbow room. Returns the new (expanded) rect.
# Layouts vary by floor index so successive boss floors feel distinct.
@warning_ignore("integer_division")
func _carve_boss_arena() -> Rect2i:
	var best: Rect2i = Rect2i()
	var best_area := 0
	for r in _rooms:
		var room: Rect2i = r
		var area := room.size.x * room.size.y
		if area > best_area and room.size.x >= 14 and room.size.y >= 10:
			best_area = area
			best = room
	if best_area == 0:
		return Rect2i()
	# Expand outward by EXPAND tiles each side, clamped to grid edges. Walls
	# inside the expanded region are converted to floor — corridors / small
	# adjacent rooms get absorbed into the arena, which is the intent. The
	# bosses themselves are physically larger now (collision radius up to
	# 34 px / ~1 tile), so the arena needs proportionally more open space
	# for kiting and sight-line management — bumped 6 → 11.
	const EXPAND: int = 11
	var nx: int = maxi(2, best.position.x - EXPAND)
	var ny: int = maxi(2, best.position.y - EXPAND)
	var nx_end: int = mini(GRID_W - 2, best.position.x + best.size.x + EXPAND)
	var ny_end: int = mini(GRID_H - 2, best.position.y + best.size.y + EXPAND)
	for y in range(ny, ny_end):
		for x in range(nx, nx_end):
			_grid[y][x] = FLOOR
	best.position = Vector2i(nx, ny)
	best.size = Vector2i(nx_end - nx, ny_end - ny)
	# Pick a layout based on which boss floor this is
	@warning_ignore("integer_division")
	var layout: int = (GameState.portals_used / 5) % 3
	match layout:
		0: _arena_layout_pillars(best)
		1: _arena_layout_cross(best)
		2: _arena_layout_corners(best)
	return best

# Four 2×2 pillar walls at quartile positions — classic cover-shooter feel.
func _arena_layout_pillars(room: Rect2i) -> void:
	@warning_ignore("integer_division")
	var px_l := room.position.x + room.size.x / 4
	@warning_ignore("integer_division")
	var px_r := room.position.x + 3 * room.size.x / 4
	@warning_ignore("integer_division")
	var py_t := room.position.y + room.size.y / 4
	@warning_ignore("integer_division")
	var py_b := room.position.y + 3 * room.size.y / 4
	for cx in [px_l, px_r]:
		for cy in [py_t, py_b]:
			_stamp_wall_block(cx, cy, 2, 2)

# Plus-shaped wall barricades that block long sight lines through the centre.
func _arena_layout_cross(room: Rect2i) -> void:
	@warning_ignore("integer_division")
	var cx: int = room.position.x + room.size.x / 2
	@warning_ignore("integer_division")
	var cy: int = room.position.y + room.size.y / 2
	# Horizontal arm — leave 2-tile gaps either side of the centre
	@warning_ignore("integer_division")
	var arm_w: int = room.size.x / 3
	for x in range(cx - arm_w, cx - 1):
		_grid[cy][x] = WALL
	for x in range(cx + 2, cx + arm_w):
		_grid[cy][x] = WALL
	# Vertical arm
	@warning_ignore("integer_division")
	var arm_h: int = room.size.y / 3
	for y in range(cy - arm_h, cy - 1):
		_grid[y][cx] = WALL
	for y in range(cy + 2, cy + arm_h):
		_grid[y][cx] = WALL

# Diagonal blocks tucked into each corner — opens the centre, forces fights
# to spill outward toward cover.
@warning_ignore("integer_division")
func _arena_layout_corners(room: Rect2i) -> void:
	var inset := 3
	for corner in [
			Vector2i(room.position.x + inset, room.position.y + inset),
			Vector2i(room.position.x + room.size.x - inset - 3, room.position.y + inset),
			Vector2i(room.position.x + inset, room.position.y + room.size.y - inset - 3),
			Vector2i(room.position.x + room.size.x - inset - 3, room.position.y + room.size.y - inset - 3)]:
		_stamp_wall_block(corner.x, corner.y, 3, 3)

# Stamps a w×h wall rectangle, but skips tiles that would solidify the room
# centre — boss spawns there and we don't want it stuck inside a pillar.
@warning_ignore("integer_division")
func _stamp_wall_block(tx: int, ty: int, w: int, h: int) -> void:
	for dy in h:
		for dx in w:
			var x: int = tx + dx
			var y: int = ty + dy
			if x < 0 or x >= GRID_W or y < 0 or y >= GRID_H:
				continue
			_grid[y][x] = WALL

# ── ARENA generator — single huge open room ───────────────────────────────────
# Carves one massive rectangle (~52×38, randomised ± a few tiles) centred
# on the map. Used for the "thunderdome" floor type where the player is
# dropped into a boss + wizard + minion melee in wide-open space. Adds the
# arena rect to _rooms so spawn / portal selection and the regular enemy
# spawn pass all just work.
@warning_ignore("integer_division")
func _gen_arena() -> void:
	var w: int = randi_range(48, 56)
	var h: int = randi_range(34, 42)
	w = mini(w, GRID_W - 6)
	h = mini(h, GRID_H - 6)
	var x: int = (GRID_W - w) / 2 + randi_range(-2, 2)
	var y: int = (GRID_H - h) / 2 + randi_range(-2, 2)
	x = clampi(x, 3, GRID_W - w - 3)
	y = clampi(y, 3, GRID_H - h - 3)
	var arena := Rect2i(x, y, w, h)
	_carve_room(arena)
	_rooms.append(arena)
	# Scatter a handful of cover stamps so the arena isn't a billiard table.
	# Layout choice rotates with floor index so consecutive arena rolls
	# don't read identically.
	@warning_ignore("integer_division")
	var pat: int = (GameState.portals_used / 3) % 4
	match pat:
		0: _arena_layout_pillars(arena)
		1: _arena_layout_cross(arena)
		2: _arena_layout_corners(arena)
		3: _layout_scatter_pillars(arena, randi_range(6, 10), 2)

# ── Per-room interior layouts ────────────────────────────────────────────────
# Applied to a subset of regular rooms above 10×8 during generation, before
# walls are built. Each function stamps a wall pattern that gives the room
# a distinctive silhouette without breaking pathing — clearance for the bot
# is preserved via _layout_pinch_safe (skips stamps that would seal the
# room's only entrance or trap a tile against a wall).
#
# Stamps are budget-limited: low-tile-count patterns on small rooms, more
# expressive patterns reserved for big rooms. Every layout leaves a 1-tile
# clear ring against the room border so corridor doorways stay reachable.
const ROOM_LAYOUT_MIN_W: int = 10
const ROOM_LAYOUT_MIN_H: int = 8

# Picks a layout function appropriate to the room's size and stamps it.
# Caller is expected to gate eligibility (skip player/portal/themed/arena
# rooms) before invoking. ~40 % of eligible rooms get a layout — the rest
# stay empty for pacing variety.
@warning_ignore("integer_division")
func _stamp_room_layout(room: Rect2i) -> void:
	if room.size.x < ROOM_LAYOUT_MIN_W or room.size.y < ROOM_LAYOUT_MIN_H:
		return
	# Eight layout buckets; bigger rooms unlock the wider ones.
	var pool: Array = ["pillars_small", "diagonals", "alcoves",
		"scatter", "zigzag", "ring", "split_wall", "rubble"]
	# Tighten the pool on very-large rooms so they pick the spacier layouts.
	if room.size.x >= 16 and room.size.y >= 12:
		pool = ["scatter", "zigzag", "ring", "split_wall", "alcoves", "rubble"]
	var pick: String = pool[randi() % pool.size()]
	match pick:
		"pillars_small": _layout_pillars_small(room)
		"diagonals":     _layout_diagonals(room)
		"alcoves":       _layout_alcoves(room)
		"scatter":       _layout_scatter_pillars(room, randi_range(3, 5), 1)
		"zigzag":        _layout_zigzag(room)
		"ring":          _layout_ring(room)
		"split_wall":    _layout_split_wall(room)
		"rubble":        _layout_rubble(room)

# True when stamping `(x,y)` would leave (x,y) inside the room interior
# and at least one adjacent tile clear. Used by stamp passes to avoid
# pinching corridor doorways.
func _layout_pinch_safe(room: Rect2i, x: int, y: int) -> bool:
	# Keep a 1-tile ring next to the room border untouched so doorways
	# / wall-adjacent corridors stay open.
	if x <= room.position.x or x >= room.position.x + room.size.x - 1:
		return false
	if y <= room.position.y or y >= room.position.y + room.size.y - 1:
		return false
	return true

# 4 single-tile pillars at quartile positions — minimum cover.
@warning_ignore("integer_division")
func _layout_pillars_small(room: Rect2i) -> void:
	var px_l: int = room.position.x + room.size.x / 4
	var px_r: int = room.position.x + 3 * room.size.x / 4
	var py_t: int = room.position.y + room.size.y / 4
	var py_b: int = room.position.y + 3 * room.size.y / 4
	for cx in [px_l, px_r]:
		for cy in [py_t, py_b]:
			if _layout_pinch_safe(room, cx, cy):
				_grid[cy][cx] = WALL

# Two short diagonal wall strips angling into the room — biased cover.
@warning_ignore("integer_division")
func _layout_diagonals(room: Rect2i) -> void:
	var ax: int = room.position.x + 2
	var ay: int = room.position.y + 2
	var bx: int = room.position.x + room.size.x - 3
	var by: int = room.position.y + room.size.y - 3
	var length: int = mini(room.size.x, room.size.y) / 3
	for i in length:
		if _layout_pinch_safe(room, ax + i, ay + i):
			_grid[ay + i][ax + i] = WALL
		if _layout_pinch_safe(room, bx - i, by - i):
			_grid[by - i][bx - i] = WALL

# 1-tile-deep alcove notches on each long wall — minor sight blockers
# without big footprint. Carved INTO the room's interior at the edges.
@warning_ignore("integer_division")
func _layout_alcoves(room: Rect2i) -> void:
	var cx: int = room.position.x + room.size.x / 2
	var cy: int = room.position.y + room.size.y / 2
	# Top + bottom — 3-tile wide alcove protrusions
	for dx in range(-1, 2):
		var tx: int = cx + dx
		if _layout_pinch_safe(room, tx, room.position.y + 1):
			_grid[room.position.y + 1][tx] = WALL
		if _layout_pinch_safe(room, tx, room.position.y + room.size.y - 2):
			_grid[room.position.y + room.size.y - 2][tx] = WALL

# N random 1×1 (or 2×2 if size>1) pillars scattered inside the room.
# Used both by per-room layouts and by ARENA's pattern 3.
@warning_ignore("integer_division")
func _layout_scatter_pillars(room: Rect2i, count: int, size: int) -> void:
	for _i in count:
		for _attempt in 6:
			var tx: int = randi_range(room.position.x + 2,
				room.position.x + room.size.x - 2 - size)
			var ty: int = randi_range(room.position.y + 2,
				room.position.y + room.size.y - 2 - size)
			if not _layout_pinch_safe(room, tx, ty):
				continue
			# Don't double-stamp on a tile that's already wall (overlap).
			if _grid[ty][tx] == WALL:
				continue
			for dx in size:
				for dy in size:
					if _layout_pinch_safe(room, tx + dx, ty + dy):
						_grid[ty + dy][tx + dx] = WALL
			break

# Two staggered partial walls forming a zigzag — forces serpentine kiting.
@warning_ignore("integer_division")
func _layout_zigzag(room: Rect2i) -> void:
	var y_top: int = room.position.y + room.size.y / 3
	var y_bot: int = room.position.y + 2 * room.size.y / 3
	var wall_len: int = (room.size.x * 2) / 3
	var x_start_top: int = room.position.x + 1
	var x_start_bot: int = room.position.x + room.size.x - 1 - wall_len
	for i in wall_len:
		if _layout_pinch_safe(room, x_start_top + i, y_top):
			_grid[y_top][x_start_top + i] = WALL
		if _layout_pinch_safe(room, x_start_bot + i, y_bot):
			_grid[y_bot][x_start_bot + i] = WALL

# A 1-tile-thick rectangular ring around the room centre with one gap on
# each side, like a small inner courtyard with archways.
@warning_ignore("integer_division")
func _layout_ring(room: Rect2i) -> void:
	var inset: int = 3
	var rx: int = room.position.x + inset
	var ry: int = room.position.y + inset
	var rw: int = room.size.x - inset * 2
	var rh: int = room.size.y - inset * 2
	if rw < 4 or rh < 4:
		return
	# Horizontal segments
	for x in range(rx, rx + rw):
		# Skip a 2-tile gap in the centre of each side
		if absi(x - (rx + rw / 2)) <= 1:
			continue
		if _layout_pinch_safe(room, x, ry):
			_grid[ry][x] = WALL
		if _layout_pinch_safe(room, x, ry + rh - 1):
			_grid[ry + rh - 1][x] = WALL
	# Vertical segments
	for y in range(ry, ry + rh):
		if absi(y - (ry + rh / 2)) <= 1:
			continue
		if _layout_pinch_safe(room, rx, y):
			_grid[y][rx] = WALL
		if _layout_pinch_safe(room, rx + rw - 1, y):
			_grid[y][rx + rw - 1] = WALL

# A single bisecting wall with one 3-tile gap — splits the room into two
# halves but leaves a clean choke. Direction depends on aspect ratio.
@warning_ignore("integer_division")
func _layout_split_wall(room: Rect2i) -> void:
	if room.size.x >= room.size.y:
		# Vertical wall splitting left/right
		var sx: int = room.position.x + room.size.x / 2
		var gap_y: int = room.position.y + room.size.y / 2
		for y in range(room.position.y + 1, room.position.y + room.size.y - 1):
			if absi(y - gap_y) <= 1:
				continue
			if _layout_pinch_safe(room, sx, y):
				_grid[y][sx] = WALL
	else:
		# Horizontal wall splitting top/bottom
		var sy: int = room.position.y + room.size.y / 2
		var gap_x: int = room.position.x + room.size.x / 2
		for x in range(room.position.x + 1, room.position.x + room.size.x - 1):
			if absi(x - gap_x) <= 1:
				continue
			if _layout_pinch_safe(room, x, sy):
				_grid[sy][x] = WALL

# Many 1×1 pillars scattered randomly — "broken rubble" feel.
@warning_ignore("integer_division")
func _layout_rubble(room: Rect2i) -> void:
	var area: int = room.size.x * room.size.y
	var count: int = clampi(area / 14, 5, 18)
	for _i in count:
		var tx: int = randi_range(room.position.x + 2,
			room.position.x + room.size.x - 3)
		var ty: int = randi_range(room.position.y + 2,
			room.position.y + room.size.y - 3)
		if not _layout_pinch_safe(room, tx, ty):
			continue
		if _grid[ty][tx] == WALL:
			continue
		# Keep at least one orthogonal neighbour open so we don't form
		# 2-wide wall clusters that re-emerge as solid blocks.
		var floor_neighbors: int = 0
		for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			if _grid[ty + d.y][tx + d.x] == FLOOR:
				floor_neighbors += 1
		if floor_neighbors < 3:
			continue
		_grid[ty][tx] = WALL

# Walks `_rooms` and stamps an interior layout into ~40 % of eligible ones.
# Eligibility: room is large enough, isn't the player spawn, isn't the
# portal room, isn't a boss arena, isn't already themed. Run AFTER
# _carve_boss_arena (which has its own dedicated layouts) but BEFORE
# _build_walls so the new wall tiles render properly.
func _apply_room_layouts(player_room: Rect2i, portal_room: Rect2i,
		boss_arena_room: Rect2i) -> void:
	if _gen_mode == GenMode.CAVE or _gen_mode == GenMode.ARENA:
		return   # cave-style rooms aren't axis-aligned, arena has its own
	for r in _rooms:
		var room: Rect2i = r
		if room == player_room or room == portal_room:
			continue
		if boss_arena_room.size.x > 0 and room == boss_arena_room:
			continue
		# Skip degenerate sample rooms used by cave-gen.
		if room.size.x < ROOM_LAYOUT_MIN_W or room.size.y < ROOM_LAYOUT_MIN_H:
			continue
		# 40 % chance per eligible room — keeps half the floor blank for
		# straightforward combat encounters.
		if randf() > 0.40:
			continue
		_stamp_room_layout(room)

func _spawn_boss(room: Rect2i) -> void:
	var diff := GameState.difficulty
	var pos := _tile_center(room.get_center())
	# Each biome has a signature boss for early floors so the player learns
	# one boss per biome and the legendary drop reads as "earned in this
	# biome." Deep floors (20+) open the pool so all five bosses are on
	# the table for variety.
	#   biome 0 Dungeon     → Brute (signature: Brutehammer shotgun)
	#   biome 1 Catacombs   → Wraith (signature: Wraithcaster shock)
	#   biome 2 Ice Cavern  → Architect (signature: Compass homing)
	#   biome 3 Lava Rift   → Magma Tyrant (signature: Magmaspitter fire-nova)
	var floor_n: int = GameState.portals_used + 1
	var boss: Node2D
	if floor_n < 20:
		boss = _instantiate_biome_boss(GameState.biome, diff)
	else:
		# Deep-floor pool: biome boss + the two universal advanced bosses
		# (Lich, Devourer) so each biome still has its themed boss in rotation.
		match randi() % 3:
			0: boss = _instantiate_biome_boss(GameState.biome, diff)
			1:
				boss = BOSS_LICH_SCRIPT.new()
				boss.max_health = int(280.0 * (1.0 + diff * 1.0))
			2:
				boss = BOSS_DEVOURER_SCRIPT.new()
				boss.max_health = int(600.0 * (1.0 + diff * 1.0))
	boss.position = pos
	$Enemies.add_child(boss)

# Floor-50 gauntlet — spawns 3 unique bosses around the arena center
# at once, then watches them. When the last boss dies the watcher drops
# the Crown of Conquest and spawns either an ExitPortal (back to village)
# or a regular Portal (continue deeper) depending on whether the player's
# difficulty is above 50 (the user-configurable "endless mode" threshold).
# Bosses get +HP scaling like the regular boss spawn so deeper-tier
# starts (Hellpit) hit floor 50 with proportionally tougher bosses.
func _spawn_boss_gauntlet(arena_room: Rect2i) -> void:
	var diff := GameState.difficulty
	var center: Vector2 = _tile_center(arena_room.get_center())

	# Pick 3 distinct boss types from the full pool of 4 biome signatures
	# so the gauntlet rolls a different mix each visit (Brute / Wraith /
	# Architect / Magma).
	var pool: Array = [0, 1, 2, 3]
	pool.shuffle()
	var picks: Array = pool.slice(0, 3)

	# Spread the bosses around the center on a triangle so the player
	# can't AoE all three before any of them moves. Distance scales
	# with arena size to avoid clipping into walls on smaller arenas.
	# Cap raised alongside the arena EXPAND bump — larger arenas give the
	# fight more room to breathe, and the bigger boss sprites need the
	# extra spacing so they don't overlap each other at spawn.
	var ring: float = minf(280.0, float(mini(arena_room.size.x, arena_room.size.y)) * float(TILE) * 0.32)
	var watcher: Node = Node.new()
	watcher.name = "GauntletWatcher"
	watcher.set_meta("alive", picks.size())
	watcher.set_meta("portal_pos", center)
	add_child(watcher)
	for i in picks.size():
		var ang: float = (TAU / float(picks.size())) * float(i) - PI * 0.5
		var pos: Vector2 = center + Vector2(cos(ang), sin(ang)) * ring
		var boss: Node2D = _instantiate_biome_boss(int(picks[i]), diff)
		# Trim per-boss HP so the gauntlet doesn't multiply total HP by 3 —
		# instead each boss has ~70% of its solo HP, summing to ~2.1× a
		# normal boss-floor encounter. Tense, not interminable.
		if "max_health" in boss:
			boss.max_health = int(boss.max_health * 0.70)
		boss.position = pos
		boss.tree_exited.connect(_on_gauntlet_boss_died.bind(watcher))
		$Enemies.add_child(boss)

	# Banner so the player understands what they walked into.
	BossIntro.show_for(get_tree().current_scene,
		"FLOOR 50 — GAUNTLET",
		Color(1.0, 0.85, 0.30))

func _on_gauntlet_boss_died(watcher: Node) -> void:
	if not is_instance_valid(watcher):
		return
	var alive: int = int(watcher.get_meta("alive", 0)) - 1
	watcher.set_meta("alive", alive)
	if alive > 0:
		FloatingText.spawn_str(Vector2(800, 120),
			"%d BOSS%s REMAINING" % [alive, "" if alive == 1 else "ES"],
			Color(1.0, 0.85, 0.30), get_tree().current_scene)
		return
	# All down — spawn the trophy and the appropriate portal.
	var pos: Vector2 = watcher.get_meta("portal_pos", Vector2.ZERO)
	_spawn_gauntlet_reward(pos)
	# Continue deeper at extreme difficulty (the user's "endless mode"
	# threshold); otherwise drop back to the village with the trophy.
	if GameState.difficulty > 50.0:
		_spawn_portal(pos + Vector2(0.0, 64.0))
		FloatingText.spawn_str(pos + Vector2(0.0, -60.0),
			"DEEPER STILL...", Color(1.0, 0.40, 0.40),
			get_tree().current_scene)
	else:
		_spawn_exit_portal(pos + Vector2(0.0, 64.0))
		FloatingText.spawn_str(pos + Vector2(0.0, -60.0),
			"RETURN VICTORIOUS", Color(0.55, 1.0, 0.65),
			get_tree().current_scene)
	watcher.queue_free()

func _spawn_gauntlet_reward(pos: Vector2) -> void:
	# Special loot bag — Crown of Conquest plus a guaranteed legendary
	# wand and a couple random drops. Loot table is deliberately sparse
	# until the wider drop pool gets iterated; the Crown alone justifies
	# the run.
	var bag := LOOT_BAG_SCENE.instantiate()
	bag.global_position = pos
	bag.items = [ItemDB.crown_of_conquest(),
		ItemDB.generate_wand(Item.RARITY_LEGENDARY),
		ItemDB.random_drop(),
		ItemDB.random_drop()]
	get_tree().current_scene.call_deferred("add_child", bag)
	# Bonus gold pile so the moment of victory has a visceral payoff.
	for i in 12:
		var gold := GOLD_PICKUP_SCENE.instantiate()
		gold.global_position = pos + Vector2(
			randf_range(-90.0, 90.0), randf_range(-90.0, 90.0))
		gold.value = int(randi_range(20, 40) * GameState.loot_multiplier)
		get_tree().current_scene.call_deferred("add_child", gold)
	if SoundManager:
		SoundManager.play("crystal", 0.95)

# Returns a position inside `room` that's at least LOOT_MIN_DIST_PX away
# from any interactable (shrine / enchant table / sell chest / etc.) and
# from already-placed loot bags. If the preferred position is already
# clear it's returned untouched; otherwise we sample a handful of random
# floor tiles in the room and pick the first that clears. Final fallback
# is the original — prefer a slightly overlapping bag to no bag at all.
const LOOT_MIN_DIST_PX: float = 96.0   # ~3 tiles

func _safe_loot_pos(preferred: Vector2, room: Rect2i) -> Vector2:
	if _loot_pos_clear(preferred):
		return preferred
	for _attempt in 12:
		var tx := randi_range(room.position.x + 1, room.position.x + room.size.x - 2)
		var ty := randi_range(room.position.y + 1, room.position.y + room.size.y - 2)
		if _grid[ty][tx] != FLOOR:
			continue
		var p: Vector2 = _tile_center(Vector2i(tx, ty))
		if _loot_pos_clear(p):
			return p
	return preferred

func _loot_pos_clear(p: Vector2) -> bool:
	var d2: float = LOOT_MIN_DIST_PX * LOOT_MIN_DIST_PX
	for n in get_tree().get_nodes_in_group("interactable"):
		if not is_instance_valid(n):
			continue
		var n2: Node2D = n as Node2D
		if n2 == null:
			continue
		if n2.global_position.distance_squared_to(p) < d2:
			return false
	for n in get_tree().get_nodes_in_group("loot_bag"):
		if not is_instance_valid(n):
			continue
		var n2: Node2D = n as Node2D
		if n2 == null:
			continue
		if n2.global_position.distance_squared_to(p) < d2:
			return false
	return true

func _instantiate_biome_boss(biome: int, diff: float) -> Node2D:
	var boss: Node2D
	match biome:
		1:   # Catacombs → Wraith (ghosts in tombs)
			boss = BOSS_WRAITH_SCRIPT.new()
			boss.max_health = int(220.0 * (1.0 + diff * 1.0))
		2:   # Ice Cavern → Architect (cold mechanical turret)
			boss = BOSS_ARCHITECT_SCRIPT.new()
			boss.max_health = int(260.0 * (1.0 + diff * 1.0))
		3:   # Lava Rift → Magma Tyrant
			boss = BOSS_MAGMA_SCRIPT.new()
			boss.max_health = int(280.0 * (1.0 + diff * 1.0))
		_:   # 0 Dungeon (and any unknown biome) → Brute
			boss = BOSS_SCENE.instantiate()
			if "max_health" in boss:
				boss.max_health = int(200.0 * (1.0 + diff * 1.0))
	return boss

# Probability that a non-boss floor at high difficulty hosts a mini-boss.
# Climbs from 0 % at diff 4 to ~40 % at diff 6+.
func _mini_boss_chance() -> float:
	return clampf((GameState.difficulty - 4.0) * 0.20, 0.0, 0.40)

# Plants a single boss-type enemy at reduced HP into a far-from-spawn room.
# Doesn't claim the portal (this isn't a true boss floor) so the player can
# still progress without killing it — but the rewards for doing so are real.
@warning_ignore("integer_division")
func _spawn_mini_boss(player_room: Rect2i) -> void:
	var room: Rect2i = _farthest_room(player_room)
	if room.size.x < 8 or room.size.y < 6:
		return
	var diff := GameState.difficulty
	# Mini-boss is the current biome's themed boss at 60% HP — keeps the
	# encounter on-theme with the rest of the floor instead of spawning a
	# random boss that may not match the visual/mechanical setting.
	var boss: Node2D = _instantiate_biome_boss(GameState.biome, diff)
	if "max_health" in boss:
		boss.max_health = int(boss.max_health * 0.6)
	boss.position = _tile_center(room.get_center())
	$Enemies.add_child(boss)
	if SoundManager:
		SoundManager.play("boss_roar", randf_range(1.05, 1.18))
	FloatingText.spawn_str(boss.position, "MINI-BOSS",
		Color(1.0, 0.4, 0.3), get_tree().current_scene)

# ── Traps ─────────────────────────────────────────────────────────────────────

func _spawn_shrine(player_room: Rect2i) -> void:
	# 60% chance per floor for one shrine in a random non-player room
	if randf() > 0.6:
		return
	var candidates: Array = []
	for r in _rooms:
		var cr: Rect2i = r
		if cr == player_room:
			continue
		if cr.size.x < 4 or cr.size.y < 4:
			continue
		candidates.append(cr)
	if candidates.is_empty():
		return
	var room: Rect2i = candidates[randi() % candidates.size()]
	for _attempt in 8:
		var tx := randi_range(room.position.x + 1, room.position.x + room.size.x - 2)
		var ty := randi_range(room.position.y + 1, room.position.y + room.size.y - 2)
		if _grid[ty][tx] == FLOOR:
			var shrine := SHRINE_SCENE.instantiate()
			shrine.position = _tile_center(Vector2i(tx, ty))
			add_child(shrine)
			return

func _spawn_traps() -> void:
	var diff := GameState.difficulty
	# Trap count grows with difficulty similar to hazard tiles — base
	# range scaled by 1 + (diff-1) × 0.20, capped at +160 %.
	var diff_mult: float = 1.0 + clampf(maxf(0.0, diff - 1.0) * 0.20, 0.0, 1.6)
	var trap_count: int = randi_range(1, 2 + int(diff * 0.5))
	trap_count = int(round(float(trap_count) * diff_mult))
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
				var scene: PackedScene = SPIN_TRAP_SCENE if randf() < 0.4 else SPIKE_TRAP_SCENE
				var trap := scene.instantiate()
				trap.position = _tile_center(Vector2i(tx, ty))
				add_child(trap)
				tried += 1
				break

# ── Breakable walls ───────────────────────────────────────────────────────────

# Called by BreakableWall on destruction. Clears the covered tiles from the
# shared grid so the FP rig's occlusion raycast and wall mesh both update.
func notify_wall_destroyed(tiles: Array[Vector2i]) -> void:
	for t in tiles:
		if t.y >= 0 and t.y < GRID_H and t.x >= 0 and t.x < GRID_W:
			(_grid[t.y] as Array)[t.x] = FLOOR
	if GameState.active_rig != null and is_instance_valid(GameState.active_rig) \
			and GameState.active_rig.has_method("rebuild_walls"):
		GameState.active_rig.rebuild_walls()

# ── Beam traps ────────────────────────────────────────────────────────────────

func _in_any_room(tx: int, ty: int) -> bool:
	for r in _rooms:
		var room: Rect2i = r
		if room.has_point(Vector2i(tx, ty)):
			return true
	return false

func _spawn_beam_traps() -> void:
	# Only place beam traps from floor 2 onward so players learn controls first.
	if GameState.portals_used < 1:
		return
	var beam_count: int = mini(1 + int(GameState.difficulty * 0.4), 3)
	var candidates: Array[Dictionary] = []

	for ty in range(3, GRID_H - 3):
		for tx in range(3, GRID_W - 3):
			if _grid[ty][tx] != FLOOR:
				continue
			if _in_any_room(tx, ty):
				continue

			# N-S beam in E-W corridor: walls at ty±2, floors at ty±1 and tx±1
			if _grid[ty - 1][tx] == FLOOR and _grid[ty + 1][tx] == FLOOR \
					and _grid[ty - 2][tx] == WALL and _grid[ty + 2][tx] == WALL \
					and _grid[ty][tx - 1] == FLOOR and _grid[ty][tx + 1] == FLOOR:
				candidates.append({"tx": tx, "ty": ty, "axis": 0})

			# E-W beam in N-S corridor: walls at tx±2, floors at tx±1 and ty±1
			elif _grid[ty][tx - 1] == FLOOR and _grid[ty][tx + 1] == FLOOR \
					and _grid[ty][tx - 2] == WALL and _grid[ty][tx + 2] == WALL \
					and _grid[ty - 1][tx] == FLOOR and _grid[ty + 1][tx] == FLOOR:
				candidates.append({"tx": tx, "ty": ty, "axis": 1})

	candidates.shuffle()
	var placed: Array[Vector2i] = []
	for c in candidates:
		if placed.size() >= beam_count:
			break
		var tx: int = int(c["tx"])
		var ty: int = int(c["ty"])
		# Enforce minimum spacing between beam traps.
		var too_close := false
		for prev: Vector2i in placed:
			if abs(prev.x - tx) + abs(prev.y - ty) < 6:
				too_close = true
				break
		if too_close:
			continue

		var trap := BEAM_TRAP_SCENE.instantiate()
		trap.set("beam_axis", int(c["axis"]))
		trap.set("beam_half_width", 48.0)
		trap.set("low_beam", randf() < 0.30)
		trap.position = _tile_center(Vector2i(tx, ty))
		add_child(trap)
		placed.append(Vector2i(tx, ty))

# ── Doors ─────────────────────────────────────────────────────────────────────
# Auto-opening doors that span a 3-wide corridor cross-section. Reuses the same
# corridor-detection as beam traps. First use of the FP rig's animated
# wall-segment primitive (see DOOM_DESIGN.md).
func _spawn_doors() -> void:
	var door_count: int = mini(1 + int(GameState.difficulty * 0.3), 2)
	var candidates: Array[Dictionary] = []
	for ty in range(3, GRID_H - 3):
		for tx in range(3, GRID_W - 3):
			if _grid[ty][tx] != FLOOR or _in_any_room(tx, ty):
				continue
			# N-S beam / E-W corridor: 3-wide in Y, walls at ty±2.
			if _grid[ty - 1][tx] == FLOOR and _grid[ty + 1][tx] == FLOOR \
					and _grid[ty - 2][tx] == WALL and _grid[ty + 2][tx] == WALL \
					and _grid[ty][tx - 1] == FLOOR and _grid[ty][tx + 1] == FLOOR:
				candidates.append({"tx": tx, "ty": ty, "axis": 0})
			# E-W beam / N-S corridor: 3-wide in X, walls at tx±2.
			elif _grid[ty][tx - 1] == FLOOR and _grid[ty][tx + 1] == FLOOR \
					and _grid[ty][tx - 2] == WALL and _grid[ty][tx + 2] == WALL \
					and _grid[ty - 1][tx] == FLOOR and _grid[ty + 1][tx] == FLOOR:
				candidates.append({"tx": tx, "ty": ty, "axis": 1})

	candidates.shuffle()
	var placed: Array[Vector2i] = []
	for c in candidates:
		if placed.size() >= door_count:
			break
		var tx: int = int(c["tx"])
		var ty: int = int(c["ty"])
		var axis: int = int(c["axis"])
		# Door-to-door spacing.
		var too_close := false
		for prev: Vector2i in placed:
			if abs(prev.x - tx) + abs(prev.y - ty) < 8:
				too_close = true
				break
		if too_close:
			continue
		# Keep doors clear of existing hazards (beam/spike/spin traps).
		var center := _tile_center(Vector2i(tx, ty))
		for hz in get_tree().get_nodes_in_group("trap"):
			if is_instance_valid(hz) and (hz as Node2D).global_position.distance_to(center) < 96.0:
				too_close = true
				break
		if too_close:
			continue

		# Cover tiles = the 3 corridor cross-section tiles, perpendicular to travel.
		var cover: Array[Vector2i] = []
		if axis == 0:
			cover = [Vector2i(tx, ty - 1), Vector2i(tx, ty), Vector2i(tx, ty + 1)]
		else:
			cover = [Vector2i(tx - 1, ty), Vector2i(tx, ty), Vector2i(tx + 1, ty)]

		var door := DOOR_SCENE.instantiate()
		door.set("cover_tiles", cover)
		door.set("corridor_axis", axis)
		door.position = center
		add_child(door)
		placed.append(Vector2i(tx, ty))

# ── Secret rooms ──────────────────────────────────────────────────────────────

func _try_secret_rooms() -> void:
	var candidates := _rooms.duplicate()
	candidates.shuffle()
	# Secret room cap scales with difficulty: 2 base, 3 at ≥3.0, 4 at ≥5.0.
	# More hidden rewards to compensate for the harder fights / hazard load.
	var max_secrets: int = 2
	if GameState.difficulty >= 5.0:
		max_secrets = 4
	elif GameState.difficulty >= 3.0:
		max_secrets = 3
	var spawned := 0
	for _r in candidates:
		if spawned >= max_secrets:
			break
		var room: Rect2i = _r
		if room == _rooms[0]:
			continue
		if _try_secret_off_room(room):
			spawned += 1

func _try_secret_off_room(base: Rect2i) -> bool:
	# Try east side only (simplest, least likely to go OOB)
	var sx := base.position.x + base.size.x + 1
	@warning_ignore("integer_division")
	var sy := base.position.y + base.size.y / 2 - 3
	var sw := 7
	var sh := 7
	@warning_ignore("integer_division")
	var entrance := Vector2i(base.position.x + base.size.x, base.position.y + base.size.y / 2)

	if sx + sw + 1 >= GRID_W or sy < 2 or sy + sh + 1 >= GRID_H:
		return false

	# Make sure the room AND a 1-tile border ring are all walls. Checking
	# only the room interior (the old behaviour) let the carved room open
	# straight into an adjacent corridor/room whenever one happened to abut
	# the secret room's far side — the "gaping hole leading to the rest of
	# the level". Requiring the surrounding ring to be solid wall (the
	# entrance column on the west is still wall at this point and gets
	# carved afterwards) guarantees the room is sealed except via the door.
	for ty in range(sy - 1, sy + sh + 1):
		for tx in range(sx - 1, sx + sw + 1):
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

	@warning_ignore("integer_division")
	var loot_tile := Vector2i(sx + sw / 2, sy + sh / 2)
	# The entrance is carved to FLOOR here so the level-connectivity /
	# region-bridging passes treat the secret room as reachable and don't
	# tunnel a second way in. It gets RE-SEALED to WALL in _seal_secret_doors()
	# (after bridging, before walls are built) so the room is genuinely hidden
	# behind solid wall geometry — in both 2D and FP — until the player breaks
	# through and open_secret_passage() carves it back open for real.
	_secret_door_data.append({"entrance": entrance, "loot_tile": loot_tile})
	return true

# The three vertical tiles a secret door occupies (matches the door body's
# 32×96 collision: one column, three rows centered on the entrance).
func _secret_door_tiles(entrance: Vector2i) -> Array:
	return [
		Vector2i(entrance.x, entrance.y - 1),
		Vector2i(entrance.x, entrance.y),
		Vector2i(entrance.x, entrance.y + 1),
	]

# Re-seal every secret entrance back to WALL after region bridging but before
# walls/floor are built, so the secret room reads as solid wall everywhere.
func _seal_secret_doors() -> void:
	for data in _secret_door_data:
		for t in _secret_door_tiles(data["entrance"]):
			if t.y >= 0 and t.y < GRID_H and t.x >= 0 and t.x < GRID_W:
				_grid[t.y][t.x] = WALL

# Called by SecretDoor when broken: carve the entrance back to FLOOR and
# refresh the active rig's geometry so the opening appears in FP / 3rd person.
# (2D collision is the door body itself, which frees on break.)
func open_secret_passage(entrance: Vector2i) -> void:
	for t in _secret_door_tiles(entrance):
		if t.y >= 0 and t.y < GRID_H and t.x >= 0 and t.x < GRID_W:
			_grid[t.y][t.x] = FLOOR
	var rig: Node = GameState.active_rig
	if rig != null and is_instance_valid(rig) and rig.has_method("set_grid"):
		rig.set_grid(_grid, GRID_W, GRID_H)

func _place_secret_doors() -> void:
	var wall_col: Color = BIOME_WALL_COLORS[GameState.biome]
	for data in _secret_door_data:
		var entrance: Vector2i = data["entrance"]
		var loot_tile: Vector2i = data["loot_tile"]

		var door: Node = SECRET_DOOR_SCENE.instantiate()
		door.set("wall_color", wall_col)
		# Grid coords so the door can carve the passage open (geometry change)
		# when broken, rebuilding the FP wall mesh.
		door.set("entrance_tile", entrance)
		door.set("loot_world_pos", _tile_center(loot_tile))
		door.set("loot_items", [ItemDB.random_drop(), ItemDB.random_drop(), ItemDB.random_drop()])
		# 5 % roll for an ambush boss inside the secret room. SecretDoor
		# spawns the boss alongside the loot when opened, so the player
		# fights for what they thought was a free pile.
		if randf() < 0.05:
			door.set("spawn_boss_biome", GameState.biome)
		door.position = _tile_center(entrance)
		add_child(door)

		# Cover the secret room AND its surrounding wall ring so the room
		# doesn't telegraph its existence through the ASCII border glyphs
		# that AsciiWalls draws on every wall tile facing a floor — those
		# glyphs render at the wall/floor boundary just outside the
		# previous (interior-only) cover. Extending the cover one tile
		# (32 px) on the N / E / S sides hides those glyphs as well as the
		# rectangular protrusion of "extra" wall area east of the parent
		# room. West stays flush with the door body so the door visual
		# itself reads as the wall surface the player approaches.
		var cover := ColorRect.new()
		cover.color = wall_col
		# Room interior is 7×7 (224×224 px). Extend the cover one extra tile
		# (32 px) on N / E / S to bury the AsciiWalls border glyphs that
		# would otherwise reveal the room's outline. West stays flush with
		# the door so the door visual reads as the wall surface.
		cover.position = Vector2(16.0, -144.0)
		cover.size = Vector2(256.0, 288.0)
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
	var canvas := CanvasLayer.new()
	canvas.layer = 15
	add_child(canvas)

	# Anchored container — pins the entire minimap (and its labels) to the
	# top-right corner of the viewport so window resizes don't push it off
	# screen. All child positions are RELATIVE to this Control's origin
	# (the minimap's top-left, including the 2 px border padding).
	var mini_root := Control.new()
	mini_root.name = "MinimapRoot"
	mini_root.anchor_left = 1.0
	mini_root.anchor_right = 1.0
	mini_root.anchor_top = 0.0
	mini_root.anchor_bottom = 0.0
	# Match the HUD column's right tightening (Player.gd _RIGHT_HUD_TIGHTEN)
	# so the minimap's right edge lines up with the stats / wand-info /
	# autoplay panels below it instead of floating ~108 px further inboard.
	const _MINIMAP_RIGHT_TIGHTEN: float = 110.0
	var right_margin: float = maxf(0.0,
		1600.0 - (MINIMAP_X + MINIMAP_W + 2.0) - _MINIMAP_RIGHT_TIGHTEN)
	var full_w: float = MINIMAP_W + 4.0
	var full_h: float = MINIMAP_H + 30.0
	mini_root.offset_left = -(full_w + right_margin)
	mini_root.offset_right = -right_margin
	mini_root.offset_top = MINIMAP_Y - 2.0
	mini_root.offset_bottom = MINIMAP_Y - 2.0 + full_h
	mini_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(mini_root)
	_minimap_root = mini_root

	# Dark surround border (relative to mini_root: top-left of the box).
	# Dropped from alpha 0.88 → 0.32 so world content (enemies in the
	# top-right corner of the viewport) shows through the minimap. The
	# tile glyphs themselves are also alpha-thinned in MinimapGlyphs.
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.06, 0.32)
	bg.position = Vector2(0.0, 0.0)
	bg.size = Vector2(MINIMAP_W + 4.0, MINIMAP_H + 4.0)
	mini_root.add_child(bg)

	# ASCII glyph layer — draws "." for floor and "#" for wall via _draw().
	# Inset 2 px so it sits inside the border.
	var glyph_overlay := Node2D.new()
	glyph_overlay.set_script(MINIMAP_GLYPHS_SCRIPT)
	glyph_overlay.position = Vector2(2.0, 2.0)
	mini_root.add_child(glyph_overlay)
	glyph_overlay.setup(_grid, GRID_W, GRID_H, MINIMAP_CELL_W, MINIMAP_CELL_H)

	# Portal dot — relative to glyph_overlay's origin (which is the inner
	# top-left of the map area).
	var portal_dot := ColorRect.new()
	portal_dot.size = Vector2(4.0, 4.0)
	portal_dot.color = Color(0.3, 1.0, 0.3, 0.9)
	portal_dot.position = Vector2(
		2.0 + float(_portal_tile.x) * MINIMAP_CELL_W - 2.0,
		2.0 + float(_portal_tile.y) * MINIMAP_CELL_H - 2.0)
	mini_root.add_child(portal_dot)

	# Biome + floor label — moved OUT of the minimap container. Sits as a
	# standalone left-anchored Control near the top-left of the screen so
	# the dungeon name + modifier tags ("Dungeon F3 [HASTE+CURSED]") don't
	# get squished under the right-hugging minimap. Anchors to top-left
	# and uses left-aligned text so it reads cleanly.
	var biome_lbl := Label.new()
	var gen_tag := " [C]" if _gen_mode == GenMode.CAVE else (" [H]" if _gen_mode == GenMode.HALLS else "")
	var mod_tag := ""
	if not GameState.floor_modifiers.is_empty():
		var upper_mods: Array = []
		for m in GameState.floor_modifiers:
			upper_mods.append(String(m).to_upper())
		mod_tag = " [%s]" % "+".join(upper_mods)
	biome_lbl.text = "%s  F%d%s%s  seed:%d" % [
		BIOME_NAMES[GameState.biome], GameState.portals_used + 1,
		gen_tag, mod_tag, _floor_seed]
	# Sits below the gold label (y=32-50) so the dungeon name + modifier
	# tags don't overlap the gold readout. y=58 leaves a comfortable gap
	# below the gold text without stepping on the stamina bar's column.
	biome_lbl.position = Vector2(220.0, 58.0)
	biome_lbl.size = Vector2(620.0, 14.0)
	biome_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	biome_lbl.add_theme_font_size_override("font_size", 10)
	biome_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.7))
	canvas.add_child(biome_lbl)

	# Legend — sits directly under the minimap now that the biome label has
	# moved to the top-left HUD column.
	var legend := Label.new()
	legend.text = "● you   ● portal"
	legend.position = Vector2(2.0, MINIMAP_H + 6.0)
	legend.size = Vector2(MINIMAP_W, 10.0)
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legend.add_theme_font_size_override("font_size", 8)
	legend.add_theme_color_override("font_color", Color(0.38, 0.38, 0.5))
	mini_root.add_child(legend)

	# Player dot (position updated in _process). Lives inside mini_root
	# so its position is in minimap-local space.
	_minimap_dot = ColorRect.new()
	_minimap_dot.size = Vector2(4.0, 4.0)
	_minimap_dot.color = Color(0.3, 1.0, 0.9, 1.0)
	mini_root.add_child(_minimap_dot)

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
	# Cache the scene root once. `get_tree().current_scene` can return null
	# briefly during scene transitions — caching here keeps every add_child
	# below using the same handle and lets us bail cleanly if it's already
	# gone (e.g. player tabbed through the portal mid-room-clear).
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	FloatingText.spawn_str(player.global_position + Vector2(0.0, -70.0), "ROOM CLEARED!", Color(1.0, 0.92, 0.2), scene_root)
	if SoundManager:
		SoundManager.play("room_clear")
	for _i in 4:
		var gold := GOLD_PICKUP_SCENE.instantiate()
		gold.global_position = player.global_position + Vector2(randf_range(-56.0, 56.0), randf_range(-40.0, 40.0))
		gold.value = int(randi_range(4, 10) * GameState.loot_multiplier)
		scene_root.add_child(gold)
	# Animate every uncollected loot bag toward the merge point and replace
	# the cluster with a single fancy "mega bag" once the animation
	# finishes. Cuts the visual clutter of 30+ scattered bags AND gives
	# the room-clear payoff a satisfying convergence beat.
	var merge_target: Vector2 = player.global_position + Vector2(0.0, 36.0)
	var merged_items: Array = []
	var merged_bag_count: int = 0
	for b in get_tree().get_nodes_in_group("loot_bag"):
		if not is_instance_valid(b):
			continue
		if "items" in b:
			for it in (b.get("items") as Array):
				merged_items.append(it)
			# Empty the bag's items so its own pickup paths can't double
			# up on the same loot mid-animation.
			b.set("items", [])
		merged_bag_count += 1
		var bag_node := b as Node2D
		# Slide the sprite toward the merge target, then free it. Quad-in
		# easing makes them lurch outward briefly before snapping in,
		# which reads as "all the loot is collapsing onto the player".
		var tw := bag_node.create_tween()
		tw.tween_property(bag_node, "global_position", merge_target, 0.45) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(bag_node.queue_free)
	# Cap the mega bag — a heavily-farmed high-difficulty floor was merging
	# into 1000+ item bags (huge popup, absurd hoard). Keep the best items by
	# rarity then sell value; convert the overflow into bonus gold so the
	# player isn't robbed of the value, just the clutter.
	const MEGA_BAG_MAX_ITEMS: int = 40
	if merged_items.size() > MEGA_BAG_MAX_ITEMS:
		merged_items.sort_custom(func(a, b):
			if a.rarity != b.rarity:
				return a.rarity > b.rarity
			return a.sell_value > b.sell_value)
		var overflow_gold: int = 0
		for k in range(MEGA_BAG_MAX_ITEMS, merged_items.size()):
			overflow_gold += maxi(1, int(merged_items[k].sell_value))
		merged_items = merged_items.slice(0, MEGA_BAG_MAX_ITEMS)
		GameState.gold += overflow_gold
		FloatingText.spawn_str(player.global_position + Vector2(0.0, -92.0),
			"+%dg (excess loot sold)" % overflow_gold, Color(1.0, 0.92, 0.30), scene_root)
	if not merged_items.is_empty():
		# Wait for the converge animation, then drop one fancy mega bag.
		# scene_root captured up top — but the timer fires 0.5 s later and
		# the scene may have changed (portal entered mid-animation), so
		# re-check via is_instance_valid before parenting the new bag.
		var loot_scene: PackedScene = LOOT_BAG_SCENE
		var bag_count_announce: int = merged_bag_count
		var scene_root_ref: Node = scene_root
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			if not is_instance_valid(scene_root_ref) or not scene_root_ref.is_inside_tree():
				return
			var bag := loot_scene.instantiate()
			bag.position = merge_target
			bag.set("items", merged_items)
			bag.set("is_mega", true)
			scene_root_ref.add_child(bag)
			FloatingText.spawn_str(merge_target + Vector2(0.0, -56.0),
				"MEGA BAG (×%d merged)" % bag_count_announce,
				Color(1.0, 0.85, 0.25), scene_root_ref))

var _eruption_t: float = 5.0   # first eruption ~5 s after entering a Lava Rift floor

func _process(delta: float) -> void:
	# 2D top-down vision-radius mask — push the player's current screen-pixel
	# position into the shader so the visibility disc tracks the player as
	# the Camera2D slides. Only updated while the overlay is actually visible
	# (TOPDOWN mode); skip the work otherwise.
	if _vision_overlay != null and _vision_overlay.visible and _vision_mat != null:
		var player := get_tree().get_first_node_in_group("player")
		if is_instance_valid(player) and player is Node2D:
			var p2d: Node2D = player as Node2D
			var screen_pos: Vector2 = p2d.get_global_transform_with_canvas().get_origin()
			_vision_mat.set_shader_parameter("player_px", screen_pos)
	if _is_test_mode:
		_tick_test_wave(delta)
	# Lava Rift biome mechanic — periodic eruptions near the player.
	# Telegraph for 3 s, then drop a LavaTile that lingers like the
	# baseline biome-hazard tiles. Adds positional pressure during
	# combat without feeling random across the whole map.
	if GameState.biome == 3:
		_eruption_t -= delta
		if _eruption_t <= 0.0:
			_eruption_t = randf_range(7.0, 10.0)
			_spawn_eruption_near_player()
	# Drain queued dungeon-mode spawns over time. Burst hard for the first
	# second after a level loads (so the world feels populated immediately),
	# then drop to the steady fast/slow rates. Slow rate kicks in only when
	# the previous frame was already heavy so we don't compound bad frames.
	if _dungeon_spawn_burst_t > 0.0:
		_dungeon_spawn_burst_t -= delta
	if not _dungeon_spawn_queue.is_empty() and can_spawn_enemy():
		var per_frame: int
		if delta >= 0.025:
			per_frame = DUNGEON_SPAWN_PER_SLOW
		elif _dungeon_spawn_burst_t > 0.0:
			per_frame = DUNGEON_SPAWN_PER_BURST
		else:
			per_frame = DUNGEON_SPAWN_PER_FAST
		for _i in mini(per_frame, _dungeon_spawn_queue.size()):
			var data: Dictionary = _dungeon_spawn_queue.pop_front()
			_place_enemy(data["scene"] as PackedScene,
				data["room"] as Rect2i,
				float(data["hp_mult"]))
	# Periodic OOB enemy cleanup — removes enemies that drifted into walls
	_oob_cleanup_t -= delta
	if _oob_cleanup_t <= 0.0:
		_oob_cleanup_t = 4.0
		_cleanup_oob_enemies()
	# Periodic loot-bag cap — keeps the live bag count bounded during fast kills.
	_loot_cap_t -= delta
	if _loot_cap_t <= 0.0:
		_loot_cap_t = 1.0
		enforce_loot_cap()

	# Room-clear detection — sampled ~4×/sec instead of every frame (the scan
	# allocates an enemy-group array; clear-detection a quarter-second late is
	# imperceptible behind the converge animation).
	if not _room_cleared and not _is_test_mode:
		_room_check_t -= delta
		if _room_check_t <= 0.0:
			_room_check_t = 0.25
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
	# Player dot lives inside the anchored mini_root container, so its
	# position is now in minimap-local space (top-left of the inner map
	# area is at (2, 2) inside the container).
	_minimap_dot.position = Vector2(
		2.0 + tile_pos.x * MINIMAP_CELL_W - 2.0,
		2.0 + tile_pos.y * MINIMAP_CELL_H - 2.0
	)
