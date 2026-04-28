class_name EnflameOverlay
extends Label

# Visual overlay attached to an ENFLAMED enemy. Replaces the old ground
# FirePatch — flames now stick to the burning entity itself so the player
# can read who's currently on fire at a glance instead of trying to map
# patches back to enemies.
#
# Damage-over-time is still ticked by the host's `_tick_status` (each enemy
# script already does that). This node is visual + serves as the helper
# for the "fire hit on already-enflamed target = refresh + AoE" flare
# behavior via the static refresh_pulse() entry point.

const FLAME_F0 := " ( "
const FLAME_F1 := "((("
const FLAME_F2 := ") ("
const FLAME_F3 := "(*)"

# AoE flare when a burn_hit lands on an already-enflamed target. Pulses
# damage + burn stacks to enemies in range and adds 1 s to the host's
# enflame timer (handled by the caller).
const REFRESH_RADIUS      := 80.0
const REFRESH_DAMAGE_BASE := 4
const REFRESH_BURN_STACKS := 2
const REFRESH_TIMER_BONUS := 1.0

static var _shared_font: Font = null

var _anim_t: float = 0.0
var _frame: int    = 0

# Mount/free helper. Idempotent on no-op frames — only allocates when the
# enflame state actually flipped.
static func sync_to(host: Node, enflamed: bool) -> void:
	if not is_instance_valid(host):
		return
	var existing := host.get_node_or_null("EnflameOverlay") as Label
	var existing_ring := host.get_node_or_null("FireAoeRing")
	if enflamed:
		if existing == null:
			var ov := EnflameOverlay.new()
			ov.name = "EnflameOverlay"
			host.add_child(ov)
		if existing_ring == null:
			var ring := FireAoeRing.new()
			ring.name = "FireAoeRing"
			host.add_child(ring)
	else:
		if existing != null:
			existing.queue_free()
		if existing_ring != null:
			existing_ring.queue_free()

# Burn-on-burn flare: re-igniting an already-enflamed target adds time to
# their burn and splashes fire to neighbors. Reads/writes _enflame_timer
# via reflection so it works with every enemy script.
static func refresh_pulse(host: Node) -> void:
	if not is_instance_valid(host):
		return
	if "_enflame_timer" in host:
		host.set("_enflame_timer", float(host.get("_enflame_timer")) + REFRESH_TIMER_BONUS)
	var ring := host.get_node_or_null("FireAoeRing")
	if ring != null and ring.has_method("pulse"):
		ring.call("pulse")
	if not (host is Node2D):
		return
	var tree := host.get_tree()
	if tree == null:
		return
	var center: Vector2 = (host as Node2D).global_position
	var int_bonus: int = GameState.get_stat_bonus("INT")
	var dmg: int = REFRESH_DAMAGE_BASE + maxi(0, int_bonus)
	for enemy in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy) or enemy == host:
			continue
		if not (enemy is Node2D):
			continue
		if center.distance_to((enemy as Node2D).global_position) > REFRESH_RADIUS:
			continue
		if enemy.has_method("take_damage"):
			enemy.take_damage(dmg)
			GameState.damage_dealt += dmg
			GameState.record_weapon_damage("fire", dmg)
			if is_instance_valid(enemy) and (enemy as Node).is_queued_for_deletion():
				GameState.record_weapon_kill("fire")
		# Use _add_burn_stacks (caps at 9, no enflame proc) instead of
		# apply_status("burn_hit") for the splash. apply_status would
		# re-enter refresh_pulse on any neighbor that's already enflamed,
		# and a tightly clustered burning pack would recurse infinitely.
		if is_instance_valid(enemy) and enemy.has_method("_add_burn_stacks"):
			enemy._add_burn_stacks(REFRESH_BURN_STACKS)
	FloatingText.spawn_str(center, "FLARE!", Color(1.0, 0.55, 0.1), tree.current_scene)

func _ready() -> void:
	if _shared_font == null:
		_shared_font = MonoFont.get_font()
	add_theme_font_override("font", _shared_font)
	add_theme_font_size_override("font_size", 14)
	add_theme_color_override("font_color", Color(1.0, 0.45, 0.05))
	add_theme_color_override("font_outline_color", Color(0.45, 0.05, 0.0))
	add_theme_constant_override("outline_size", 2)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	# Sit above the entity's head — same vertical band the ElectricBolt
	# overlay uses, so the stack of "what's afflicting this thing" reads
	# in a consistent place.
	offset_left   = -22.0
	offset_top    = -42.0
	offset_right  =  22.0
	offset_bottom = -16.0
	text = FLAME_F0
	z_index = 3
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_anim_t += delta
	if _anim_t >= 0.10:
		_anim_t = 0.0
		_frame = (_frame + 1) % 4
		match _frame:
			0: text = FLAME_F0
			1: text = FLAME_F1
			2: text = FLAME_F2
			3: text = FLAME_F3
	# Flicker — quick brightness oscillation on the orange channel so the
	# flames feel alive rather than a static decal.
	var flicker := sin(Time.get_ticks_msec() * 0.025) * 0.12 + 0.88
	modulate = Color(1.0, flicker * 0.7, 0.05)
