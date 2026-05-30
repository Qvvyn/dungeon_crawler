class_name EnflameOverlay
extends Label

# Visual overlay attached to an ENFLAMED enemy. Mounts ASCII flames on the
# host so the player can read who's currently on fire at a glance.
#
# Damage-over-time is still ticked by the host's `_tick_status` (each enemy
# script already does that). This node is visual + serves as the helper
# for the "fire hit on already-enflamed target = refresh + AoE" flare
# behavior via the static refresh_pulse() entry point.

const FLAME_F0 := " ))\n((("
const FLAME_F1 := " ((\n)))"

const FIRE_PATCH_SCRIPT := preload("res://scripts/FirePatch.gd")

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

# Drops a ground-fire patch at `host`'s current position. Used by both the
# initial enflame proc and the every-2-burn-hits re-trigger. Free function
# so every enemy script (base + the 5 boss classes) can call it without
# duplicating the spawn boilerplate.
static func spawn_patch(host: Node) -> void:
	if not is_instance_valid(host) or not (host is Node2D):
		return
	var tree := (host as Node).get_tree()
	if tree == null or tree.current_scene == null:
		return
	var patch := Node2D.new()
	patch.set_script(FIRE_PATCH_SCRIPT)
	patch.global_position = (host as Node2D).global_position
	tree.current_scene.add_child(patch)

# Centralised "every 2 burn-hits while ENFLAMED → drop a fresh ground patch"
# counter. Caller passes the burn-hit stack count; this fold-in returns true
# whenever the cumulative count crosses a multiple of 2 so the caller can
# also do its own bookkeeping (FloatingText, sound, etc.) alongside the
# patch spawn.
const _PATCH_TRIGGER_HITS := 2
static func register_extra_burn(host: Node, stacks: int) -> bool:
	if not is_instance_valid(host):
		return false
	var hits: int = 0
	if "_enflame_extra_hits" in host:
		hits = int(host.get("_enflame_extra_hits")) + maxi(1, stacks)
	else:
		hits = int(host.get_meta("enflame_extra_hits", 0)) + maxi(1, stacks)
	var triggered: bool = hits >= _PATCH_TRIGGER_HITS
	if triggered:
		hits = 0
	if "_enflame_extra_hits" in host:
		host.set("_enflame_extra_hits", hits)
	else:
		host.set_meta("enflame_extra_hits", hits)
	if triggered:
		spawn_patch(host)
	return triggered

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
	add_theme_font_size_override("font_size", 10)
	add_theme_constant_override("line_separation", -2)
	add_theme_color_override("font_color", Color(1.0, 0.45, 0.05))
	add_theme_color_override("font_outline_color", Color(0.45, 0.05, 0.0))
	add_theme_constant_override("outline_size", 2)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	# Two-line compact flame sits just above the enemy's head.
	offset_left   = -18.0
	offset_top    = -48.0
	offset_right  =  18.0
	offset_bottom = -16.0
	text = FLAME_F0
	z_index = 3
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_anim_t += delta
	if _anim_t >= 0.14:
		_anim_t = 0.0
		_frame = 1 - _frame
		text = FLAME_F0 if _frame == 0 else FLAME_F1
	var flicker := sin(Time.get_ticks_msec() * 0.025) * 0.12 + 0.88
	modulate = Color(1.0, flicker * 0.7, 0.05)
