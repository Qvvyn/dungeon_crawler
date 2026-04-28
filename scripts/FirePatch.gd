extends Node2D

# Spawned by ENFLAMED proc (10 burn stacks). Sits on the ground for a few
# seconds, ticking damage to any enemy in radius.

const DURATION  := 4.0
const TICK_RATE := 0.8
# Base tick damage. Final per-tick damage = TICK_DMG_BASE + INT × TICK_DMG_PER_INT,
# captured once at spawn time so the patch's payoff scales with the player's
# investment in INT instead of being a flat +4 forever.
const TICK_DMG_BASE    := 4
const TICK_DMG_PER_INT := 1

const FLAME_F0 := " )( )( ,(\n((()(())\n)(())(((\n  ()((\n   ))"
const FLAME_F1 := " ,) )(  )\n)(()(()\n((((())(\n  (()((\n   ((  "

var _life: float   = DURATION
var _tick_t: float = 0.0
var _radius: float = 36.0
var _patch: Label  = null
var _anim_t: float = 0.0
var _anim_f: int   = 0
# Per-tick damage captured at spawn — INT scaling uses the player's INT at
# the moment the patch lands, not at each tick, so a wand-fired patch keeps
# its potency even if INT changes mid-floor.
var _tick_dmg: int = TICK_DMG_BASE

static var _shared_font: Font = null

func _ready() -> void:
	# Scale radius with player level (mirrors Player._fire intelligence calc).
	# Tightened — was `28 + INT*5` (33→68 px) which sprayed across most of
	# a tile cluster; now `18 + INT*3` (21→42 px) so the patch reads as a
	# localized burning spot under the enflamed enemy.
	var intel: int = clampi(1 + (GameState.level - 1) / 2, 1, 8)
	_radius = 18.0 + float(intel) * 3.0
	# Per-tick damage scales with the player's actual INT bonus (level + gear
	# + run shrines). Floor of TICK_DMG_BASE keeps the patch meaningful even
	# at base INT, and each invested point compounds with the existing
	# enflame proc damage to make INT a real fire-build axis.
	var int_bonus: int = GameState.get_stat_bonus("INT")
	_tick_dmg = TICK_DMG_BASE + maxi(0, int_bonus) * TICK_DMG_PER_INT

	if _shared_font == null:
		_shared_font = MonoFont.get_font()

	_patch = Label.new()
	_patch.text = FLAME_F0
	_patch.add_theme_font_override("font", _shared_font)
	_patch.add_theme_color_override("font_color", Color(1.0, 0.45, 0.05))
	_patch.add_theme_color_override("font_outline_color", Color(0.45, 0.05, 0.0))
	_patch.add_theme_constant_override("outline_size", 2)
	_patch.add_theme_constant_override("line_separation", -3)
	_patch.add_theme_font_size_override("font_size", maxi(11, int(_radius * 0.45)))
	_patch.size = Vector2(_radius * 2.4, _radius * 2.4)
	_patch.position = Vector2(-_radius * 1.2, -_radius * 1.2)
	_patch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_patch.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_patch.modulate = Color(1.0, 1.0, 1.0, 0.85)
	_patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_patch)

func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	# Fade in last 30% of life
	if _life < DURATION * 0.3:
		_patch.modulate.a = clampf(_life / (DURATION * 0.3), 0.0, 1.0) * 0.85
	# Frame swap for flicker
	_anim_t += delta
	if _anim_t >= 0.16:
		_anim_t = 0.0
		_anim_f = 1 - _anim_f
		_patch.text = FLAME_F0 if _anim_f == 0 else FLAME_F1
	# Damage tick
	_tick_t -= delta
	if _tick_t <= 0.0:
		_tick_t = TICK_RATE
		_do_damage()

func _do_damage() -> void:
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy):
			continue
		if (enemy as Node2D).global_position.distance_to(global_position) <= _radius:
			if enemy.has_method("take_damage"):
				enemy.take_damage(_tick_dmg)
				GameState.damage_dealt += _tick_dmg
				GameState.record_weapon_damage("fire", _tick_dmg)
				if enemy.is_queued_for_deletion():
					GameState.record_weapon_kill("fire")
