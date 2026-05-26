class_name ItemDB

# All item definitions. Call ItemDB.random_item() to get a random drop.

# Unified legendary-drop chance — every drop path that can produce a
# legendary uses this. Curve: difficulty × 0.1 percent (1 % at diff 10,
# 5 % at diff 50, 10 % at diff 100). Capped at 50 % so extreme test-mode
# difficulties don't trivialize the legendary pool. Returns 0..1.
static func legendary_drop_chance(diff: float) -> float:
	return clampf(diff * 0.001, 0.0, 0.50)

# Drop-rarity roll. Rolls in order from rarest to most common — first
# success wins. Curves:
#   * LEGENDARY: diff × 0.1 % (capped 50 %).
#   * RARE: diff % at every tier — 1 % at diff 1, 50 % at diff 50,
#     capped at 100 %. No floor gate; rare can drop on a fresh run.
#   * UNCOMMON: 10 % at diff 1, +5 % per +1 diff. Capped at 80 % so
#     deep runs always leave a sliver of common rolls and rare /
#     legendary continue to take the dominant share as they scale up.
#   * COMMON: whatever's left (the implicit fallback).
# Successive rolls instead of a single weighted pick — keeps each tier's
# advertised chance accurate without renormalizing when uncommon's
# 80 % cap bites at high difficulty.
static func roll_drop_rarity() -> int:
	var diff: float = GameState.test_difficulty if GameState.test_mode else GameState.difficulty
	if randf() < legendary_drop_chance(diff):
		return Item.RARITY_LEGENDARY
	var rare_chance: float = clampf(diff * 0.01, 0.0, 1.0)
	if randf() < rare_chance:
		return Item.RARITY_RARE
	var uncommon_chance: float = clampf(0.10 + maxf(0.0, diff - 1.0) * 0.05, 0.0, 0.80)
	if randf() < uncommon_chance:
		return Item.RARITY_UNCOMMON
	return Item.RARITY_COMMON

# Drop-tier roll — primary scaling axis for procedural gear. The tier
# range floats with the active difficulty: at diff 10, drops roll T5–T10;
# at diff 1.x they're always T1. Floor at T1 keeps early-game drops
# meaningful and ceiling = floor(diff) keeps drops from overshooting the
# fight tier they're balanced against.
static func roll_drop_tier() -> int:
	var diff: float = GameState.test_difficulty if GameState.test_mode else GameState.difficulty
	var tier_max: int = maxi(1, int(floor(diff)))
	var tier_min: int = maxi(1, tier_max - 5)
	return randi_range(tier_min, tier_max)

# Tier → stat magnitude multiplier. Same curve shape as the old
# diff_mult so a T5 piece feels roughly equivalent to a diff-5 drop
# under the previous system.
#   T1  → 1.00×    T5  → 2.60×
#   T10 → 5.73×    T20 → 16.85×
#   T50 → 75.7×
static func tier_mult(t: int) -> float:
	var x: float = float(maxi(0, t - 1))
	return 1.0 + x * 0.30 + x * x * 0.025

# Stamps a drop tier on a fixed-stat item that didn't roll one during
# generation (everything from all_items / legendary_items / boss
# signatures / limited-use wands / the gauntlet trophy). Procedural
# items already set their own tier inside generate_gear / generate_wand,
# so this is a no-op for them. Returns the item for chaining.
static func _apply_drop_tier(item: Item) -> Item:
	if item != null and item.tier == 0:
		item.tier = roll_drop_tier()
	return item

# Half-procedural tier curve for fixed legendaries / boss signatures /
# limited-use wands / fixed legendary wands. They have handcrafted base
# stats; we want depth scaling without exploding past procedural rolls.
# Formula: 1.0 + (tier_mult(t) - 1.0) * 0.5
#   T1   → 1.00× (no change)
#   T10  → 3.36×
#   T20  → 8.93×
#   T50  → 38.35×
static func _curated_tier_scale(t: int) -> float:
	if t <= 1:
		return 1.0
	return 1.0 + (tier_mult(t) - 1.0) * 0.5

# Scales fixed-stat items' base values by the curated curve. Used by
# curated legendaries, boss signatures, fixed legendary wands, and
# limited-use wands so they all keep pace with procedural at depth.
# Linear-stat skip list mirrors _apply_drop_rarity / get_stat.
# Wand-internal fields (wand_damage, wand_pierce, wand_ricochet,
# wand_status_stacks) also scale; wand_fire_rate scales DOWN
# (multiplicative — faster shots at higher tier). projectile_count and
# wand_max_charges scale linearly with a small slope so deep-tier
# limited wands stay relevant without going wild.
static func _apply_curated_scaling(item: Item) -> Item:
	if item == null or item.tier <= 1:
		return item
	var sc: float = _curated_tier_scale(item.tier)
	# Stat bonuses
	var new_bonuses: Dictionary = {}
	for key in item.stat_bonuses:
		var val: float = float(item.stat_bonuses[key])
		if key == "fire_rate_reduction" or key == "projectile_count" \
				or (key as String).begins_with("syn_"):
			new_bonuses[key] = val
		else:
			new_bonuses[key] = val * sc
	item.stat_bonuses = new_bonuses
	# Wand-internal scaling
	if item.type == Item.Type.WAND:
		item.wand_damage = int(round(float(item.wand_damage) * sc))
		# Pierce / ricochet / stacks creep up at tier (small bumps so
		# T20 doesn't suddenly grant +20 ricochet).
		var t_extra: int = item.tier - 1
		if item.wand_pierce > 0:
			item.wand_pierce += int(t_extra * 0.25)
		if item.wand_ricochet > 0:
			item.wand_ricochet += int(t_extra * 0.25)
		if item.wand_status_stacks > 1:
			item.wand_status_stacks += int(t_extra * 0.20)
		# Limited-use wands gain charges with tier — scale roughly +5 %
		# per tier point so a T20 Cataclysm Rod with 4 base charges has
		# 4 × 2.0 = 8 charges; T50 → 4 × 3.5 = 14.
		if item.wand_max_charges > 0:
			var new_charges: int = int(round(float(item.wand_max_charges) \
				* (1.0 + float(t_extra) * 0.05)))
			item.wand_max_charges = maxi(item.wand_max_charges, new_charges)
			item.wand_charges = item.wand_max_charges
	return item

# Re-rolls a fixed gear template's rarity per drop and scales its
# stat_bonuses by the rarity multiplier. Common gear templates (Pointed
# Hat, Iron Helm, etc.) act as bases that can drop at any tier from
# common to rare; stat rings (min_rarity=UNCOMMON) drop as uncommon /
# rare instead. Skips fire_rate_reduction / projectile_count / syn_*
# (same exclusion list as the tier bonus — they're non-linear stats).
# Legendary clamps to rare here because LEGENDARY drops route to the
# curated legendary_items pool, not the fixed-gear fallback.
static func _apply_drop_rarity(item: Item, rolled: int) -> Item:
	if item == null:
		return item
	# Only re-roll for equippable gear from the fixed pool. Valuables /
	# potions / wands / synergy legendaries / boss signatures don't
	# rebase per drop.
	var t: int = item.type
	if not (t == Item.Type.HAT or t == Item.Type.ROBES or t == Item.Type.FEET \
			or t == Item.Type.RING or t == Item.Type.NECKLACE):
		return item
	var picked: int = maxi(rolled, item.min_rarity)
	if picked >= Item.RARITY_LEGENDARY:
		picked = Item.RARITY_RARE
	var rmult: float = 1.0
	match picked:
		Item.RARITY_UNCOMMON:  rmult = 1.35
		Item.RARITY_RARE:      rmult = 1.85
	if rmult != 1.0:
		var new_bonuses: Dictionary = {}
		for key in item.stat_bonuses:
			var val: float = float(item.stat_bonuses[key])
			# Skip non-linear stats — same exclusion list the tier
			# bonus uses inside InventoryManager.get_stat.
			if key == "fire_rate_reduction" or key == "projectile_count" \
					or (key as String).begins_with("syn_"):
				new_bonuses[key] = val
			else:
				new_bonuses[key] = val * rmult
		item.stat_bonuses = new_bonuses
	# Rarity-prefix the display name so a rare drop reads "Glowing
	# Pointed Hat" rather than just "Pointed Hat" with a different cell
	# color. Mirrors the procedural prefix pools.
	if picked == Item.RARITY_UNCOMMON:
		item.display_name = _GEAR_PREFIXES_UNCOMMON[randi() % _GEAR_PREFIXES_UNCOMMON.size()] \
			+ " " + item.display_name
	elif picked == Item.RARITY_RARE:
		item.display_name = _GEAR_PREFIXES_RARE[randi() % _GEAR_PREFIXES_RARE.size()] \
			+ " " + item.display_name
	item.rarity = picked
	return item

static func _wand_icon_for_type(shoot_type: String) -> String:
	# Per-shoot-type glyph. Lets the equip slot tell wands apart at a glance
	# instead of every wand reading as the same `/`. Mirrors the projectile
	# visuals where possible so the in-flight bullet matches the wand icon.
	match shoot_type:
		"pierce":   return "-"
		"ricochet": return "o"
		"shotgun":  return "#"
		"freeze":   return "*"
		"fire":     return "@"
		"shock":    return "~"
		"beam":     return "="
		"homing":   return ">"
		"nova":     return "+"
		"melee":    return "\\"
	return "/"

static func _make_wand(name: String, desc: String, col: Color, sell: int,
		shoot_type: String, damage: int, fire_rate: float, mana_cost: float,
		proj_speed: float) -> Item:
	var item := Item.new()
	item.type = Item.Type.WAND
	item.display_name = name
	item.description = desc
	item.color = col
	item.icon_char = _wand_icon_for_type(shoot_type)
	item.sell_value = sell
	item.rarity = Item.RARITY_LEGENDARY
	item.wand_shoot_type = shoot_type
	item.wand_damage = damage
	item.wand_fire_rate = fire_rate
	item.wand_mana_cost = mana_cost
	item.wand_proj_speed = proj_speed
	return item

# Builds a limited-use wand — high-impact stats, RARE-tier so it lands in the
# normal drop pool, with a finite charge count. Set pierce/ricochet/stacks via
# the optional args so each wand can express its identity (chain shock, big
# nova, etc.) without needing a separate _make call afterward.
static func _make_limited_wand(name: String, desc: String, col: Color, sell: int,
		shoot_type: String, damage: int, fire_rate: float, mana_cost: float,
		proj_speed: float, charges: int, pierce: int = 0, ricochet: int = 0,
		status_stacks: int = 1, projectile_count: int = 0) -> Item:
	var w := Item.new()
	w.type = Item.Type.WAND
	w.icon_char = _wand_icon_for_type(shoot_type)
	w.display_name = name
	w.description = desc
	w.color = col
	w.sell_value = sell
	w.rarity = Item.RARITY_RARE
	w.wand_shoot_type = shoot_type
	w.wand_damage = damage
	w.wand_fire_rate = fire_rate
	w.wand_mana_cost = mana_cost
	w.wand_proj_speed = proj_speed
	w.wand_pierce = pierce
	w.wand_ricochet = ricochet
	w.wand_status_stacks = status_stacks
	w.wand_max_charges = charges
	w.wand_charges = charges
	if projectile_count > 0:
		w.stat_bonuses = {"projectile_count": projectile_count}
	return w

# All limited-use wands as a separate list so the drop table can pick one
# specifically when a "wand" roll comes up. Each is a curated power-fantasy:
# brief but devastating. Charges burn down with every press, then the wand
# auto-unequips and shatters (Player._shatter_wand).
static func limited_use_wands() -> Array[Item]:
	return [
		_make_limited_wand("Cataclysm Rod",
			"Massive nova blast. Use it well.",
			Color(1.00, 0.20, 0.05), 140,
			"nova", 24, 0.32, 0.0, 600.0,
			4, 0, 0, 1, 0),
		_make_limited_wand("Stormcall Staff",
			"Lightning leaps from foe to foe.",
			Color(0.95, 0.95, 0.20), 95,
			"shock", 14, 0.14, 0.0, 750.0,
			8, 0, 6, 4, 0),
		_make_limited_wand("Pyroclasm Wand",
			"Five fiery pellets, scorching patches.",
			Color(1.00, 0.45, 0.10), 110,
			"shotgun", 9, 0.30, 0.0, 600.0,
			6, 1, 0, 4, 0),
		_make_limited_wand("Glacial Bomb",
			"Detonates in a wide, freezing pulse.",
			Color(0.50, 0.85, 1.00), 130,
			"freeze", 18, 0.50, 0.0, 480.0,
			3, 4, 0, 10, 0),
		_make_limited_wand("Hexbolt Singularity",
			"Sixteen-shard volley. One chance.",
			Color(0.55, 0.05, 0.95), 165,
			"pierce", 18, 0.20, 0.0, 850.0,
			1, 6, 0, 1, 15),
		_make_limited_wand("Phantom Volley",
			"Rapid homing barrage. Leave nothing standing.",
			Color(0.70, 0.30, 1.00), 105,
			"homing", 11, 0.10, 0.0, 420.0,
			7, 0, 0, 1, 0),
	]

# Single-stat focus ring helper. Builds a base-rarity-COMMON ring with
# min_rarity=UNCOMMON so the drop logic never spawns it as a common —
# stat rings always drop at uncommon or higher with rarity-scaled values.
static func _stat_ring(name: String, stat_key: String, val: int, col: Color) -> Item:
	var r := _make(Item.Type.RING, name, "+%d %s." % [val, stat_key],
		col, "o", 50, {stat_key: float(val)}, Item.RARITY_COMMON)
	r.min_rarity = Item.RARITY_UNCOMMON
	return r

static func _make(type: Item.Type, name: String, desc: String,
		col: Color, icon: String, sell: int, bonuses: Dictionary = {},
		rarity: int = Item.RARITY_COMMON, set_tag: String = "") -> Item:
	var item := Item.new()
	item.type = type
	item.display_name = name
	item.description = desc
	item.color = col
	item.icon_char = icon
	item.sell_value = sell
	item.rarity = rarity
	item.stat_bonuses = bonuses
	item.set_tag = set_tag
	return item

static func all_items() -> Array[Item]:
	var items: Array[Item] = [
		# ── Wands (procedurally generated) ───────────────────────────────────
		generate_wand(Item.RARITY_COMMON),
		generate_wand(Item.RARITY_COMMON),
		generate_wand(Item.RARITY_COMMON),
		generate_wand(Item.RARITY_COMMON),
		generate_wand(Item.RARITY_RARE),
		generate_wand(Item.RARITY_RARE),

		# ── Hats — wisdom (regen) + MIND (mana pool) focus ────────────────────
		# Pointed Cap is the only hat with a non-caster identity (raw VIT
		# bump). Everything else trades VIT for wisdom / MIND so the slot
		# reliably feels mage-y. Wisdom values are scaled DOWN from the
		# pre-MIND era — back when WIS gave both regen and pool, +30 made
		# sense. Now WIS is regen-only, so 4-8 is in line with the other
		# stat pools.
		_make(Item.Type.HAT, "Pointed Hat",    "+4 VIT.",
			Color(0.3, 0.3, 0.7), "^", 18, {"VIT": 4}),
		_make(Item.Type.HAT, "Iron Helm",      "+4 DEF.",
			Color(0.5, 0.5, 0.6), "^", 30, {"DEF": 4.0}, Item.RARITY_COMMON, "iron"),
		_make(Item.Type.HAT, "Feathered Cap",  "+6 wisdom, +3 MIND.",
			Color(0.7, 0.6, 0.3), "^", 22, {"wisdom": 6.0, "MIND": 3.0}, Item.RARITY_COMMON, "swift"),
		_make(Item.Type.HAT, "Arcane Hood",    "+2 VIT, +5 wisdom, +3 MIND.",
			Color(0.35, 0.25, 0.65), "^", 32, {"VIT": 2, "wisdom": 5.0, "MIND": 3.0}, Item.RARITY_COMMON, "arcane"),
		_make(Item.Type.HAT, "Mage's Cowl",    "+8 wisdom, +5 MIND.",
			Color(0.2, 0.4, 0.9), "^", 38, {"wisdom": 8.0, "MIND": 5.0}),
		_make(Item.Type.HAT, "Druid's Crown",  "+3 VIT, +3 wisdom, +3 MIND.",
			Color(0.45, 0.65, 0.30), "^", 28, {"VIT": 3, "wisdom": 3.0, "MIND": 3.0}),
		_make(Item.Type.HAT, "Inquisitor's Hood", "+3 VIT, +3 INT, +2 DEF.",
			Color(0.55, 0.20, 0.20), "^", 30, {"VIT": 3, "INT": 3, "DEF": 2.0}),

		# ── Robes — VIT + DEF focus, with a caster lane via the arcane set ───
		_make(Item.Type.ROBES, "Silk Robes",    "+10 VIT, +5 DEF.",
			Color(0.6, 0.2, 0.5), "%", 20, {"VIT": 10, "DEF": 5.0}),
		_make(Item.Type.ROBES, "Battle Garb",   "+10 DEF, +5 VIT.",
			Color(0.4, 0.4, 0.4), "%", 32, {"DEF": 10.0, "VIT": 5}, Item.RARITY_COMMON, "iron"),
		# Caster robes keep their wisdom identity but pick up MIND so the
		# arcane set actually expands the mana pool, not just the regen.
		_make(Item.Type.ROBES, "Apprentice Robe", "+6 wisdom, +3 MIND.",
			Color(0.25, 0.35, 0.7), "%", 26, {"wisdom": 6.0, "MIND": 3.0}, Item.RARITY_COMMON, "arcane"),
		_make(Item.Type.ROBES, "Wizard's Vestment", "+2 VIT, +5 wisdom, +5 MIND.",
			Color(0.4, 0.2, 0.8), "%", 40, {"VIT": 2, "wisdom": 5.0, "MIND": 5.0}),
		_make(Item.Type.ROBES, "Templar Mantle", "+8 DEF, +6 VIT.",
			Color(0.60, 0.55, 0.30), "%", 30, {"DEF": 8.0, "VIT": 6}),
		_make(Item.Type.ROBES, "Vagabond Cloak", "+6 VIT, +20 speed.",
			Color(0.45, 0.35, 0.50), "%", 28, {"VIT": 6, "speed": 20.0}, Item.RARITY_COMMON, "swift"),

		# ── Feet — speed + AGI focus ─────────────────────────────────────────
		# AGI scaling is +1 base stat per point; combined with raw speed
		# values the slot owns mobility. Wisdom moved off the feet pool
		# entirely so caster builds use hats / robes / accessories for
		# magic stats and pick footwear for kiting.
		_make(Item.Type.FEET, "Leather Boots",  "+30 speed, +2 AGI.",
			Color(0.5, 0.35, 0.2), "n", 16, {"speed": 30.0, "AGI": 2}, Item.RARITY_COMMON, "swift"),
		_make(Item.Type.FEET, "Swift Shoes",    "+60 speed, +3 AGI.",
			Color(0.2, 0.8, 0.5), "n", 30, {"speed": 60.0, "AGI": 3}, Item.RARITY_COMMON, "swift"),
		_make(Item.Type.FEET, "Sandals of Focus", "+25 speed, +4 AGI.",
			Color(0.6, 0.7, 0.9), "n", 22, {"speed": 25.0, "AGI": 4}, Item.RARITY_COMMON, "arcane"),
		_make(Item.Type.FEET, "Hunter Greaves", "+40 speed, +3 AGI, +20 stam_regen.",
			Color(0.40, 0.30, 0.20), "n", 26, {"speed": 40.0, "AGI": 3, "stam_regen": 20.0}),
		_make(Item.Type.FEET, "Stealth Slippers", "+35 speed, +5 AGI.",
			Color(0.20, 0.20, 0.35), "n", 24, {"speed": 35.0, "AGI": 5}),

		# ── Rings ─────────────────────────────────────────────────────────────
		_make(Item.Type.RING, "Fire Ring",      "Shoot faster.",
			Color(1.0, 0.4, 0.1), "o", 24, {"fire_rate_reduction": 0.04}),
		_make(Item.Type.RING, "Speed Ring",     "+25 speed.",
			Color(0.2, 0.9, 0.7), "o", 22, {"speed": 25.0}, Item.RARITY_COMMON, "swift"),
		_make(Item.Type.RING, "Scholar's Ring", "+5 wisdom, +3 MIND.",
			Color(0.4, 0.6, 1.0), "o", 24, {"wisdom": 5.0, "MIND": 3}, Item.RARITY_COMMON, "arcane"),
		_make(Item.Type.RING, "Mana Ring",      "+6 wisdom, +4 MIND.",
			Color(0.3, 0.5, 1.0), "o", 28, {"wisdom": 6.0, "MIND": 4}),
		_make(Item.Type.RING, "Sage's Band",    "+4 wisdom, +3 MIND, shoot faster.",
			Color(0.5, 0.7, 1.0), "o", 30, {"wisdom": 4.0, "MIND": 3, "fire_rate_reduction": 0.02}),
		_make(Item.Type.RING, "Iron Band",      "+3 VIT, +3 DEF.",
			Color(0.55, 0.55, 0.60), "o", 22, {"VIT": 3, "DEF": 3.0}),
		_make(Item.Type.RING, "Hunter's Loop",  "+3 DEX, +3 LCK.",
			Color(0.85, 0.65, 0.30), "o", 26, {"DEX": 3, "LCK": 3}),

		# ── Stat rings (one per stat, base rarity COMMON for templates;
		#     min_rarity=UNCOMMON so the actual drop floor is uncommon).
		# Each ring is a +5-of-one-stat focus item. The drop logic
		# re-rolls rarity per drop and scales stats by the rarity
		# multiplier — uncommon → +6.75, rare → +9.25.
		_stat_ring("Bronze Fist Ring",  "VIT", 5, Color(1.0, 0.45, 0.25)),
		_stat_ring("Quicksilver Ring",  "DEX", 5, Color(1.0, 0.85, 0.30)),
		_stat_ring("Sprinter's Ring",   "AGI", 5, Color(0.50, 1.00, 0.40)),
		_stat_ring("Heart Ring",        "VIT", 5, Color(0.85, 0.20, 0.30)),
		_stat_ring("Marathon Ring",     "END", 5, Color(0.30, 0.85, 0.55)),
		_stat_ring("Sage's Eye",        "INT", 5, Color(0.45, 0.55, 1.00)),
		_stat_ring("Mystic Ring",       "WIS", 5, Color(0.20, 0.55, 1.00)),
		_stat_ring("Soul Ring",         "SPR", 5, Color(0.85, 0.65, 1.00)),
		_stat_ring("Bulwark Ring",      "DEF", 5, Color(0.55, 0.55, 0.65)),
		_stat_ring("Lucky Coin Ring",   "LCK", 5, Color(1.00, 0.95, 0.40)),

		# ── Necklaces — flexible slot, common values aligned with new pool ───
		# Wisdom scaled DOWN (was 18-30; new pool maxes at 12) so commons
		# don't outclass legendary necklaces. Each adds MIND so the slot
		# also expands the mana pool.
		_make(Item.Type.NECKLACE, "Arcane Pendant", "Shoot faster.",
			Color(0.8, 0.4, 1.0), "-", 28, {"fire_rate_reduction": 0.05}, Item.RARITY_COMMON, "arcane"),
		_make(Item.Type.NECKLACE, "Life Cord",      "+5 VIT.",
			Color(0.9, 0.2, 0.3), "-", 28, {"VIT": 5}, Item.RARITY_COMMON, "iron"),
		_make(Item.Type.NECKLACE, "Mana Amulet",    "+5 wisdom, +3 MIND.",
			Color(0.2, 0.5, 1.0), "-", 32, {"wisdom": 5.0, "MIND": 3.0}),
		_make(Item.Type.NECKLACE, "Wellspring Cord", "+8 wisdom, +5 MIND.",
			Color(0.15, 0.6, 1.0), "-", 38, {"wisdom": 8.0, "MIND": 5.0}),
		_make(Item.Type.NECKLACE, "Runic Chain",    "+2 VIT, +5 wisdom, +3 MIND.",
			Color(0.5, 0.3, 0.9), "-", 36, {"VIT": 2, "wisdom": 5.0, "MIND": 3.0}),
		_make(Item.Type.NECKLACE, "Wolf Tooth Charm", "+4 DEX, +3 AGI.",
			Color(0.65, 0.50, 0.30), "-", 28, {"DEX": 4, "AGI": 3}),
		_make(Item.Type.NECKLACE, "Star Pendant",     "+4 INT, +3 WIS.",
			Color(0.30, 0.35, 0.85), "-", 30, {"INT": 4, "WIS": 3}),
		# Legendary necklaces — bumped substantially so they outclass
		# commons + dual-stat rares the way a legendary should. Were
		# previously weaker than common +30-wisdom necklaces.
		_make(Item.Type.NECKLACE, "Warlord's Talisman", "+8 INT, +6 VIT, +4 DEX.",
			Color(1.00, 0.30, 0.20), "-", 120, {"INT": 8, "VIT": 6, "DEX": 4}, Item.RARITY_LEGENDARY),
		_make(Item.Type.NECKLACE, "Archmage's Sigil",  "+8 INT, +6 WIS, +6 MIND.",
			Color(0.40, 0.55, 1.00), "-", 120, {"INT": 8, "WIS": 6, "MIND": 6}, Item.RARITY_LEGENDARY),
		_make(Item.Type.NECKLACE, "Trickster's Charm", "+8 LCK, +8 DEX, +5 AGI.",
			Color(1.00, 0.85, 0.30), "-", 120, {"LCK": 8, "DEX": 8, "AGI": 5}, Item.RARITY_LEGENDARY),

		# Shields / Tomes were here — removed since the offhand slot was
		# dropped. The Item.Type.SHIELD / TOME enum values stay so old
		# saves don't choke; they're just unreachable in new drops.

		# ── Valuables ─────────────────────────────────────────────────────────
		_make(Item.Type.VALUABLE, "Gem",          "Sell for gold.",
			Color(0.2, 0.9, 0.5), "*", 25),
		_make(Item.Type.VALUABLE, "Ancient Coin", "Sell for gold.",
			Color(0.9, 0.8, 0.2), "*", 15),
		_make(Item.Type.VALUABLE, "Magic Crystal","Sell for gold.",
			Color(0.5, 0.7, 1.0), "*", 30),

		# ── Potions ───────────────────────────────────────────────────────────
		_make(Item.Type.POTION, "Health Potion", "Restores 30% of max HP.",
			Color(0.9, 0.1, 0.2), "!", 8),
	]
	# Note: limited-use wands are NOT in this list anymore. random_drop()
	# pulls them from limited_use_wands() with a smaller sub-chance so they
	# feel like a treat instead of dominating wand drops.
	return items

static func random_item() -> Item:
	var pool := all_items()
	return pool[randi() % pool.size()]

static func random_drop() -> Item:
	# Weighted: 10% wand, 40% gear, 30% valuable, 20% potion
	# Legendaries are gated out of the standard table — they only come from
	# dedicated paths (SellChest etc), never from regular drops.
	var roll := randi() % 100
	var pool: Array = []
	var all: Array[Item] = []
	for it in all_items():
		if it.rarity != Item.RARITY_LEGENDARY:
			all.append(it)
	# Rarity is now resolved by a single curve in roll_drop_rarity (see
	# header). Wand and gear paths both sample it.
	if roll < 10:
		# Wand drop. 15 % chance for a curated limited-use wand, otherwise
		# a procedural wand whose rarity comes from the unified curve.
		if randi() % 100 < 15:
			var lw_pool := limited_use_wands()
			return _apply_curated_scaling(_apply_drop_tier(
				lw_pool[randi() % lw_pool.size()]))
		return generate_wand(roll_drop_rarity())   # generate_wand sets tier
	elif roll < 50:
		# Gear drop. SHIELD / TOME excluded — the offhand slot was removed.
		# Roll the unified rarity curve once. If LEGENDARY, return a fixed
		# legendary from the curated pool; otherwise generate a procedural
		# gear piece at the rolled rarity.
		var picked: int = roll_drop_rarity()
		if picked == Item.RARITY_LEGENDARY:
			var leg_pool: Array = []
			for it in legendary_items():
				if it.type in [Item.Type.HAT, Item.Type.ROBES, Item.Type.FEET,
						Item.Type.RING, Item.Type.NECKLACE]:
					leg_pool.append(it)
			if not leg_pool.is_empty():
				return _apply_curated_scaling(_apply_drop_tier(
					leg_pool[randi() % leg_pool.size()]))
		# Procedural gear gating keys off the player level — a high-diff
		# Hellpit start doesn't dump procedural pieces at level 1 but a
		# level-15 deep run does. Stat magnitudes still scale with tier
		# inside generate_gear.
		var lvl_now: int = GameState.level
		var proc_chance: int = 0
		if lvl_now >= 15: proc_chance = 75
		elif lvl_now >= 10: proc_chance = 55
		elif lvl_now >= 5:  proc_chance = 35
		if proc_chance > 0 and randi() % 100 < proc_chance:
			return generate_gear(picked)   # generate_gear sets tier
		# Below the proc-gen level gate — hand out a fixed common from the
		# static pool so low-level players still see drops, just less varied.
		for item in all:
			if item.type in [Item.Type.HAT, Item.Type.ROBES, Item.Type.FEET,
					Item.Type.RING, Item.Type.NECKLACE]:
				pool.append(item)
	elif roll < 80:
		for item in all:
			if item.type == Item.Type.VALUABLE:
				pool.append(item)
	else:
		for item in all:
			if item.type == Item.Type.POTION:
				pool.append(item)
	# Final fallback paths — fixed items pulled from the static pool.
	# _apply_drop_rarity re-rolls gear's displayed rarity. Valuables /
	# potions pass through unchanged. _apply_drop_tier stamps a tier.
	# Drop dedup: if any pool entries are missing from this floor's
	# drop history, prefer those; the same Pointed Hat doesn't show up
	# three times in a single floor.
	var fallback_rarity: int = roll_drop_rarity()
	var picked_item: Item = _pick_with_dedup(pool if not pool.is_empty() else all)
	if picked_item == null:
		return null
	GameState.floor_drop_history[picked_item.display_name] = true
	return _apply_drop_tier(_apply_drop_rarity(picked_item, fallback_rarity))

# Picks an item from `pool`, preferring entries whose display_name isn't
# already in GameState.floor_drop_history. Falls back to the full pool
# if every entry has already dropped this floor (which only happens on
# very long single-floor stays).
static func _pick_with_dedup(pool: Array) -> Item:
	if pool.is_empty():
		return null
	var unseen: Array = []
	for it in pool:
		var name: String = (it as Item).display_name
		if not GameState.floor_drop_history.has(name):
			unseen.append(it)
	if not unseen.is_empty():
		return unseen[randi() % unseen.size()] as Item
	return pool[randi() % pool.size()] as Item

# ── Procedural gear generator ────────────────────────────────────────────────
# Per-slot stat pools. Each entry is a stat name + a (lo, hi) magnitude
# range for COMMON drops; rare/legendary scale the range upward and roll
# more stats per item.
const _GEAR_TYPE_POOLS := {
	# Per-slot stat pools. Slot identities now strict:
	#   * HAT      — caster: wisdom (regen), MIND (pool), INT, WIS, small VIT
	#   * ROBES    — armor: VIT, DEF, speed
	#   * FEET     — mobility: speed, AGI, stam_regen
	#   * RING     — flex: VIT, DEF, wisdom, MIND, DEX, LCK, AGI, INT, fire_rate_reduction
	#   * NECKLACE — flex: VIT, wisdom, MIND, INT, WIS, LCK, AGI, fire_rate_reduction
	# fire_rate_reduction is intentionally restricted to ring / necklace
	# only so attack-speed is an accessory build choice, not a free roll
	# on every gear slot.
	"hat": {
		"icon": "^",
		"color": Color(0.45, 0.40, 0.85),
		"bases": ["Hat", "Cowl", "Cap", "Hood", "Crown", "Circlet"],
		"stats": [
			["VIT",     2, 4],
			["wisdom",  3, 8],
			["MIND",    2, 5],
			["INT",     2, 5],
			["WIS",     2, 5],
		],
	},
	"robes": {
		"icon": "%",
		"color": Color(0.55, 0.30, 0.75),
		"bases": ["Robe", "Vestment", "Mantle", "Cloak", "Garb"],
		"stats": [
			["VIT",   4, 10],
			["DEF",   6, 14],
			["speed", 18, 40],
		],
	},
	"feet": {
		"icon": "n",
		"color": Color(0.45, 0.65, 0.40),
		"bases": ["Boots", "Shoes", "Sandals", "Greaves", "Slippers"],
		"stats": [
			["speed",      25, 60],
			["AGI",        2, 5],
			["stam_regen", 25, 80],
		],
	},
	"ring": {
		"icon": "o",
		"color": Color(0.85, 0.65, 0.30),
		"bases": ["Ring", "Band", "Loop", "Sigil", "Signet"],
		"stats": [
			["VIT",                 2, 4],
			["fire_rate_reduction", 2, 5],
			["wisdom",              4, 10],
			["MIND",                2, 4],
			["DEX",                 2, 5],
			["LCK",                 2, 5],
			["AGI",                 2, 4],
			["INT",                 2, 4],
			["DEF",                 5, 12],
		],
	},
	"necklace": {
		"icon": "-",
		"color": Color(0.70, 0.40, 0.85),
		"bases": ["Pendant", "Amulet", "Talisman", "Cord", "Charm"],
		"stats": [
			["VIT",                 3, 6],
			["wisdom",              5, 12],
			["MIND",                3, 6],
			["fire_rate_reduction", 3, 7],
			["INT",                 3, 7],
			["WIS",                 3, 7],
			["LCK",                 3, 7],
			["AGI",                 3, 6],
		],
	},
}

const _GEAR_PREFIXES_COMMON   := ["Worn", "Plain", "Sturdy", "Simple", "Hand", "Old"]
const _GEAR_PREFIXES_UNCOMMON := ["Polished", "Tempered", "Quality", "Reinforced", "Keen", "Sharp"]
const _GEAR_PREFIXES_RARE     := ["Glowing", "Runed", "Etched", "Honed", "Ancient", "Refined"]
const _GEAR_PREFIXES_LEG      := ["Eternal", "Cosmic", "Voidforged", "Astral", "Sovereign", "Phantasm"]

# Builds a procedural gear item with random stats scaled by difficulty.
# Drives the late-game loot variety: instead of cycling 15 fixed pieces,
# each drop has rolled affixes that climb in magnitude with the floor.
static func generate_gear(rarity: int = Item.RARITY_COMMON) -> Item:
	var keys := (_GEAR_TYPE_POOLS as Dictionary).keys()
	var slot_key: String = String(keys[randi() % keys.size()])
	var pool: Dictionary = _GEAR_TYPE_POOLS[slot_key]
	var item := Item.new()
	match slot_key:
		"hat":      item.type = Item.Type.HAT
		"robes":    item.type = Item.Type.ROBES
		"feet":     item.type = Item.Type.FEET
		"ring":     item.type = Item.Type.RING
		"necklace": item.type = Item.Type.NECKLACE
	item.icon_char = String(pool["icon"])
	item.color     = pool["color"] as Color
	item.rarity    = rarity
	# Stat count scales with rarity:
	#   common    = 1   (single affix)
	#   uncommon  = 2   (mid tier — same count as rare but lower magnitude)
	#   rare      = 2
	#   legendary = 3
	var stat_count: int = 1
	match rarity:
		Item.RARITY_UNCOMMON:  stat_count = 2
		Item.RARITY_RARE:      stat_count = 2
		Item.RARITY_LEGENDARY: stat_count = 3
	# Tier-driven stat magnitude. Tier is the primary scaling axis now;
	# rolled in [max(1, floor(diff) - 5), floor(diff)] so a deep run
	# pulls a band of close-to-current-difficulty tiers (and the player
	# can still see lower-tier drops for stragglers / catch-up). Stored
	# on the item so the UI can show the badge and the player can read
	# the curve at a glance.
	item.tier = roll_drop_tier()
	var diff_mult: float = tier_mult(item.tier)
	# Rarity multiplier on top of the base ranges so a rare hat feels
	# rare even at low diff. Bumped slightly to widen the gap between
	# common, uncommon, rare, and legendary at every difficulty.
	var rarity_mult: float = 1.0
	match rarity:
		Item.RARITY_UNCOMMON:  rarity_mult = 1.35   # between common and rare
		Item.RARITY_RARE:      rarity_mult = 1.85
		Item.RARITY_LEGENDARY: rarity_mult = 2.7
	var stat_choices: Array = (pool["stats"] as Array).duplicate()
	stat_choices.shuffle()
	var bonuses: Dictionary = {}
	for i in mini(stat_count, stat_choices.size()):
		var entry: Array = stat_choices[i]
		var stat_name: String = String(entry[0])
		var lo: int = int(entry[1])
		var hi: int = int(entry[2])
		var raw: float = float(randi_range(lo, hi)) * rarity_mult * diff_mult
		# fire_rate_reduction is in seconds; the range entries are stored
		# in 0.01 s units to keep lo/hi as small integers. Convert back.
		if stat_name == "fire_rate_reduction":
			bonuses[stat_name] = raw * 0.01
		else:
			bonuses[stat_name] = raw
	item.stat_bonuses = bonuses
	# Name: Prefix + Base. Prefixes drawn from rarity-tier pools so the
	# label hints at the item's tier even before reading stats.
	var prefix_pool: Array = _GEAR_PREFIXES_COMMON
	match rarity:
		Item.RARITY_UNCOMMON:  prefix_pool = _GEAR_PREFIXES_UNCOMMON
		Item.RARITY_RARE:      prefix_pool = _GEAR_PREFIXES_RARE
		Item.RARITY_LEGENDARY: prefix_pool = _GEAR_PREFIXES_LEG
	var prefix: String = prefix_pool[randi() % prefix_pool.size()]
	var base_list: Array = pool["bases"]
	var base: String = String(base_list[randi() % base_list.size()])
	item.display_name = "%s %s" % [prefix, base]
	# Sell value scales with stat count + rarity + tier (via diff_mult,
	# which is now tier-driven). A T10 legendary sells for roughly the
	# same as a fixed legendary at high diff.
	item.sell_value = int(round(20.0 * float(stat_count) * (1.0 + float(rarity) * 0.6) * diff_mult))
	# Color shift toward green/gold/purple for higher rarities. Uncommon
	# uses a green tint (the classic ARPG convention) so it reads
	# instantly as "better than common but not rare-tier."
	match rarity:
		Item.RARITY_LEGENDARY:
			item.color = item.color.lerp(Color(1.0, 0.55, 1.0), 0.45)
		Item.RARITY_RARE:
			item.color = item.color.lerp(Color(1.0, 0.92, 0.45), 0.30)
		Item.RARITY_UNCOMMON:
			item.color = item.color.lerp(Color(0.45, 1.0, 0.55), 0.25)
	return item

# ── Procedural wand generator ─────────────────────────────────────────────────

static func generate_wand(rarity: int = Item.RARITY_COMMON) -> Item:
	var item := Item.new()
	item.type = Item.Type.WAND
	# Real glyph is set after shoot_type rolls, via _wand_icon_for_type.
	item.icon_char = "/"
	item.rarity = rarity

	# Pick shoot type by rarity weight. "regular" is disabled — every wand
	# now rolls a flavored shoot type so the player always has something
	# more interesting than the default arrow.
	var shoot_types: Array
	match rarity:
		Item.RARITY_COMMON:
			shoot_types = ["pierce", "ricochet", "shotgun", "freeze", "fire", "shock"]
		Item.RARITY_UNCOMMON:
			# Same pool as common, plus homing — slightly broader so
			# uncommon feels distinct without needing a unique shoot type.
			shoot_types = ["pierce", "ricochet", "shotgun", "freeze", "fire", "shock", "homing"]
		Item.RARITY_RARE:
			shoot_types = ["pierce", "ricochet", "freeze", "fire", "shock", "shotgun", "homing"]
		Item.RARITY_LEGENDARY:
			# Legendary wands no longer roll pierce/ricochet as their
			# shoot type — those are too samey at the top tier. Instead
			# every legendary gets pierce + ricochet *bonuses* on top
			# of whatever flavored type rolled (see below).
			shoot_types = ["freeze", "fire", "shock", "beam", "homing", "nova"]
		_:
			shoot_types = ["pierce"]
	item.wand_shoot_type = shoot_types[randi() % shoot_types.size()]
	item.icon_char = _wand_icon_for_type(item.wand_shoot_type)

	# Base stats by rarity (bumped for the late-game balance pass).
	# Uncommon sits between common and rare on every axis.
	match rarity:
		Item.RARITY_COMMON:
			item.wand_damage     = randi_range(2, 3)
			item.wand_fire_rate  = randf_range(0.18, 0.32)
			item.wand_mana_cost  = randf_range(2.0, 5.0)
			item.wand_proj_speed = randf_range(500.0, 650.0)
		Item.RARITY_UNCOMMON:
			item.wand_damage     = randi_range(2, 4)
			item.wand_fire_rate  = randf_range(0.16, 0.28)
			item.wand_mana_cost  = randf_range(3.0, 6.5)
			item.wand_proj_speed = randf_range(540.0, 700.0)
		Item.RARITY_RARE:
			item.wand_damage     = randi_range(3, 5)
			item.wand_fire_rate  = randf_range(0.12, 0.24)
			item.wand_mana_cost  = randf_range(4.0, 8.5)
			item.wand_proj_speed = randf_range(580.0, 750.0)
		Item.RARITY_LEGENDARY:
			item.wand_damage     = randi_range(5, 10)
			item.wand_fire_rate  = randf_range(0.08, 0.16)
			item.wand_mana_cost  = randf_range(7.0, 14.0)
			item.wand_proj_speed = randf_range(650.0, 900.0)

	# Shoot-type specific adjustments
	match item.wand_shoot_type:
		"pierce":
			item.wand_pierce    = randi_range(1, 2 + (rarity))
			item.wand_mana_cost *= 1.3
		"ricochet":
			item.wand_ricochet  = randi_range(1, 2 + rarity)
			item.wand_mana_cost *= 1.2
		"freeze", "fire", "shock":
			item.wand_status_stacks = randi_range(1, 1 + rarity)
			item.wand_mana_cost *= 1.2
		"beam":
			item.wand_damage    = randi_range(2, 3 + rarity)
			item.wand_mana_cost = randf_range(11.0, 22.0)   # per second
	# Legendary tier bonus — ricochet stacks onto every shoot type;
	# pierce is now restricted to the pierce + beam wands themselves
	# (other types get only ricochet on legendary).
	if rarity == Item.RARITY_LEGENDARY:
		if item.wand_shoot_type in ["pierce", "beam"]:
			item.wand_pierce   += randi_range(2, 3)
		item.wand_ricochet += randi_range(2, 3)
	# Strip wand_pierce from any non-pierce / non-beam wand — pierce is now
	# the pierce-wand's signature stat (and beam's, since beam is already
	# a piercing line). Other shoot types had it bolted on by the random
	# affix path above; zeroing here ensures only the intended types pierce.
	if not item.wand_shoot_type in ["pierce", "beam"]:
		item.wand_pierce = 0

	# Power score → flaw count
	var power: float = float(item.wand_damage) * (1.0 / maxf(item.wand_fire_rate, 0.01))
	power += float(item.wand_pierce) * 3.0
	power += float(item.wand_ricochet) * 2.0
	if item.wand_shoot_type == "beam":
		power += 15.0
	if item.wand_shoot_type in ["freeze", "fire", "shock"]:
		power += 5.0

	var num_flaws := 0
	if power >= 20.0:
		num_flaws = 3
	elif power >= 14.0:
		num_flaws = 2
	elif power >= 8.0:
		num_flaws = 1

	# Disabled flaws: "drift" (swirly), "mana_guzzle" (2× cost / 2× dmg),
	# "erratic" (±40° random spread — too unfun, bot couldn't aim it).
	# "clunky" now means 0.5× rate / 1.5× damage (instead of pure penalty).
	# "sloppy" is the lighter accuracy-trading flaw — 1.5× rate / ±13° aim arc.
	# "backwards" is disabled for now — even with the autoplay-skip in
	# _fire, manual play with a backwards wand reads as "wand is broken,
	# why am I shooting myself" more than as a flaw to play around. Pool
	# kept as a reference so re-enabling is one line.
	var flaw_pool: Array = ["clunky", "sloppy", "slow_shots"]
	flaw_pool.shuffle()
	for i in num_flaws:
		item.wand_flaws.append(flaw_pool[i])

	# Tier-driven scaling — same axis as generate_gear so wands and gear
	# read off a single power number. Also stored on the item for the
	# inventory / loot-bag tier badge.
	item.tier = roll_drop_tier()
	var t: int = item.tier
	var dmg_scale: float = tier_mult(t)
	if t > 1:
		item.wand_damage = int(round(float(item.wand_damage) * dmg_scale))
		# Fire-rate / projectile-speed creep also keys off tier; the
		# old curves were diff-driven, now they're tier-driven for
		# parity with the magnitude curve.
		var t_extra: float = float(t - 1)
		item.wand_fire_rate = maxf(0.04, item.wand_fire_rate * (1.0 - t_extra * 0.04))
		item.wand_proj_speed = item.wand_proj_speed * (1.0 + t_extra * 0.05)
		# Stacks/pierce/ricochet creep up too at higher tiers
		if item.wand_pierce > 0:
			item.wand_pierce += int(t_extra * 0.5)
		if item.wand_ricochet > 0:
			item.wand_ricochet += int(t_extra * 0.5)
		if item.wand_status_stacks > 0:
			item.wand_status_stacks += int(t_extra * 0.4)

	item.display_name = _wand_name(item)
	item.description  = _wand_desc(item)
	item.color        = _wand_color(item)
	item.sell_value   = int(power * 8.0) + 10
	return item

static func _wand_name(wand: Item) -> String:
	var bases: Dictionary = {
		"regular":  ["Wand", "Rod", "Stick"],
		"pierce":   ["Piercing Rod", "Needle Wand", "Skewer Staff"],
		"ricochet": ["Bouncing Rod", "Ricochet Wand", "Echo Staff"],
		"freeze":   ["Frost Wand", "Ice Rod", "Chill Staff"],
		"fire":     ["Ember Rod", "Fire Wand", "Blaze Staff"],
		"shock":    ["Thunder Rod", "Shock Wand", "Storm Staff"],
		"beam":     ["Beam Staff", "Ray Wand", "Laser Rod"],
	}
	var prefixes: Array = ["Ancient", "Cracked", "Glowing", "Cursed",
						   "Twisted", "Spectral", "Runed", "Bone", "Gnarled"]
	var base_list: Array = bases.get(wand.wand_shoot_type, ["Wand"])
	return prefixes[randi() % prefixes.size()] + " " + base_list[randi() % base_list.size()]

static func _wand_desc(wand: Item) -> String:
	var parts: Array = []
	match wand.wand_shoot_type:
		"regular":   parts.append("Basic shot")
		"pierce":    parts.append("Pierces %d enemi%s" % [wand.wand_pierce, "es" if wand.wand_pierce > 1 else ""])
		"ricochet":  parts.append("Bounces %d time%s" % [wand.wand_ricochet, "s" if wand.wand_ricochet > 1 else ""])
		"freeze":    parts.append("Stacks chill → FROZEN")
		"fire":      parts.append("Stacks burn → ENFLAMED")
		"shock":     parts.append("Stacks shock → ELECTRIFIED")
		"beam":      parts.append("Continuous beam attack")
	if not wand.wand_flaws.is_empty():
		parts.append("FLAW: " + ", ".join(wand.wand_flaws))
	return ". ".join(parts)

static func _wand_color(wand: Item) -> Color:
	# Wand inventory tint mirrors the projectile palette in Projectile.gd —
	# yellow is reserved for shotgun so the wand glyph the player carries
	# matches the bullets it spits out.
	match wand.wand_shoot_type:
		"regular":   return Color(0.95, 0.95, 0.95)
		"pierce":    return Color(0.25, 0.60, 1.00)
		"ricochet":  return Color(0.20, 1.00, 0.35)
		"freeze":    return Color(0.55, 0.92, 1.00)
		"fire":      return Color(1.00, 0.40, 0.10)
		"shock":     return Color(0.70, 0.40, 1.00)
		"beam":      return Color(0.30, 1.00, 0.80)
		"shotgun":   return Color(1.00, 0.85, 0.10)
		"homing":    return Color(1.00, 0.40, 0.80)
		"nova":      return Color(0.85, 0.40, 1.00)
	return Color(0.95, 0.95, 0.95)

# ── Boss signature wands ─────────────────────────────────────────────────────
# Each boss type guarantees a hand-tuned legendary wand on death so floor-5
# milestones have a clear chase. Stats are generous on purpose — these are
# end-of-arc rewards. Damage scales softly with floor difficulty so a deep
# Hellpit boss drops a meaningfully stronger version than the first arena.
static func boss_signature_brute() -> Item:
	# Brutehammer — heavy shotgun cone. Slow but lethal at point blank.
	# Scaling: base damage + _apply_curated_scaling on the tier roll (was
	# diff-driven `+ diff_extra * 1.5`). Tier already encodes difficulty
	# so the old per-call diff bump is redundant.
	var w := _make_wand("Brutehammer",
		"Brute boss legacy. Five-shot cone. Crushes elites at point blank.",
		Color(1.0, 0.45, 0.10), 320, "shotgun",
		6, 0.32, 12.0, 580.0)
	w.wand_pierce   = 1
	w.wand_ricochet = 1
	return _apply_curated_scaling(_apply_drop_tier(w))

static func boss_signature_architect() -> Item:
	# Architect's Compass — homing wand with extra pierce.
	var w := _make_wand("Architect's Compass",
		"Architect boss legacy. Homing bolts with deep pierce — distance is irrelevant.",
		Color(0.55, 0.30, 1.00), 340, "homing",
		7, 0.18, 10.0, 380.0)
	w.wand_pierce   = 3
	w.wand_ricochet = 1
	return _apply_curated_scaling(_apply_drop_tier(w))

static func boss_signature_wraith() -> Item:
	# Wraithcaster — high-stack shock wand. Stacks fly in fast for chain procs.
	var w := _make_wand("Wraithcaster",
		"Wraith boss legacy. Three-stack shock per hit. Chain lightning ramps fast.",
		Color(0.75, 0.95, 1.00), 320, "shock",
		5, 0.14, 9.0, 720.0)
	w.wand_status_stacks = 3
	w.wand_ricochet      = 2
	return _apply_curated_scaling(_apply_drop_tier(w))

# Floor-50 gauntlet trophy. Placeholder reward — currently a high-value
# valuable so it converts to bank gold at the SellChest. Loot table will
# be iterated later (likely a stat-bearing necklace or a unique +1
# starting tier unlock token).
static func crown_of_conquest() -> Item:
	var c := _make(Item.Type.VALUABLE,
		"Crown of Conquest",
		"Floor-50 gauntlet trophy. Sells for a king's ransom.",
		Color(1.00, 0.85, 0.20), "♛", 5000,
		{}, Item.RARITY_LEGENDARY)
	return _apply_drop_tier(c)

static func boss_signature_magma() -> Item:
	# Magmaspitter — fire nova wand.
	var w := _make_wand("Magmaspitter",
		"Magma Tyrant boss legacy. Detonating fire nova. Stacks ENFLAME quickly.",
		Color(1.00, 0.40, 0.05), 340, "nova",
		8, 0.30, 13.0, 520.0)
	w.wand_status_stacks = 4
	w.wand_pierce        = 1
	return _apply_curated_scaling(_apply_drop_tier(w))

# ── Legendary items — NOT on normal drop tables ────────────────────────────────
static func legendary_items() -> Array[Item]:
	return [
		# ── Legendary Wands (generated) ────────────────────────────────────────
		generate_wand(Item.RARITY_LEGENDARY),
		generate_wand(Item.RARITY_LEGENDARY),
		# ── Fixed Legendary Wands with custom shoot types ─────────────────────
		_make_wand("Thunderclap",
			"Five-shot cone blast. One pull, five wounds.",
			Color(1.0, 0.85, 0.1), 210, "shotgun", 3, 0.3, 10.0, 600.0),
		_make_wand("Seeker's Staff",
			"Hunts its target down. Distance means nothing.",
			Color(0.5, 0.2, 1.0), 195, "homing", 4, 0.2, 9.0, 350.0),
		_make_wand("Voidcaster",
			"Detonates on contact. Eight radial shards.",
			Color(0.15, 0.0, 0.35), 230, "nova", 3, 0.22, 12.0, 500.0),
		# ── Fixed Legendary Wands ──────────────────────────────────────────────
		_make(Item.Type.WAND, "Ecliptic Staff",
			"Fires 4 bolts. Faster than thought.",
			Color(0.65, 0.0, 1.0), "/", 180,
			{"projectile_count": 3, "fire_rate_reduction": 0.08},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.WAND, "Wand of Oblivion",
			"Void energy. Erases what it touches.",
			Color(0.05, 0.0, 0.15), "/", 160,
			{"projectile_count": 2, "fire_rate_reduction": 0.12},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.WAND, "Sundering Rod",
			"Triple shot at blistering speed.",
			Color(1.0, 0.55, 0.0), "/", 145,
			{"projectile_count": 2, "fire_rate_reduction": 0.09, "speed": 20.0},
			Item.RARITY_LEGENDARY),

		# ── Legendary Hats ─────────────────────────────────────────────────────
		_make(Item.Type.HAT, "Crown of Dominion",
			"+10 VIT, +30 DEF. Absolute authority.",
			Color(0.9, 0.75, 0.0), "^", 240,
			{"VIT": 10, "DEF": 30.0},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.HAT, "Mindweave Circlet",
			"+12 wisdom, +12 MIND, +8 INT. Mana practically infinite.",
			Color(0.2, 0.5, 1.0), "^", 260,
			{"wisdom": 12.0, "MIND": 12, "INT": 8},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.HAT, "Tiara of the Arcane Sea",
			"+5 VIT, +10 wisdom, +10 MIND. The ocean remembers.",
			Color(0.1, 0.7, 0.9), "^", 255,
			{"VIT": 5, "wisdom": 10.0, "MIND": 10},
			Item.RARITY_LEGENDARY),

		# ── Legendary Robes ────────────────────────────────────────────────────
		_make(Item.Type.ROBES, "Shroud of the Undying",
			"+30 VIT, +25 DEF, move faster.",
			Color(0.1, 0.55, 0.35), "%", 230,
			{"VIT": 30, "DEF": 25.0, "speed": 25.0},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.ROBES, "Phantom Wrap",
			"+90 speed, +35 DEF. Ghost-silk. Near impossible to hit.",
			Color(0.5, 0.2, 0.8), "%", 210,
			{"speed": 90.0, "DEF": 35.0},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.ROBES, "Robes of the Eternal Mage",
			"+4 VIT, +12 wisdom, +10 MIND, +20 DEF.",
			Color(0.15, 0.3, 0.85), "%", 270,
			{"VIT": 4, "wisdom": 12.0, "MIND": 10, "DEF": 20.0},
			Item.RARITY_LEGENDARY),

		# ── Legendary Feet ─────────────────────────────────────────────────────
		# fire_rate_reduction stripped — that stat now lives on rings /
		# necklaces only. Replaced with extra speed + AGI for slot identity.
		_make(Item.Type.FEET, "Boots of the Tempest",
			"+200 speed, +6 AGI. The ground barely notices.",
			Color(0.9, 0.95, 1.0), "n", 200,
			{"speed": 200.0, "AGI": 6},
			Item.RARITY_LEGENDARY),
		# Slippers retain their caster identity but trade huge wisdom for
		# wisdom + MIND so the mana pool grows alongside regen.
		_make(Item.Type.FEET, "Slippers of the Archmage",
			"+12 wisdom, +8 MIND, +50 speed, +5 INT.",
			Color(0.3, 0.5, 1.0), "n", 220,
			{"wisdom": 12.0, "MIND": 8, "speed": 50.0, "INT": 5},
			Item.RARITY_LEGENDARY),

		# ── Legendary Rings ────────────────────────────────────────────────────
		_make(Item.Type.RING, "Ring of the Cosmos",
			"+3 proj, faster fire, +5 VIT.",
			Color(0.1, 0.5, 1.0), "o", 220,
			{"projectile_count": 3, "fire_rate_reduction": 0.07, "VIT": 5},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.RING, "Ouroboros Sigil",
			"+10 VIT, +40 DEF. Eternal.",
			Color(0.85, 0.6, 0.05), "o", 210,
			{"VIT": 10, "DEF": 40.0},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.RING, "Ring of Infinite Flow",
			"+12 wisdom, +10 MIND, +6 WIS. Mana never runs dry.",
			Color(0.2, 0.6, 1.0), "o", 230,
			{"wisdom": 12.0, "MIND": 10, "WIS": 6},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.RING, "Resonance Loop",
			"+10 wisdom, +8 MIND, shoot much faster.",
			Color(0.4, 0.7, 1.0), "o", 220,
			{"wisdom": 10.0, "MIND": 8, "fire_rate_reduction": 0.07},
			Item.RARITY_LEGENDARY),

		# ── Legendary Necklaces — substantially buffed ────────────────────────
		# Per the rework, common necklaces dropped to wisdom 5-8 / VIT 5
		# range. Legendaries previously rolled around the same numbers
		# (Trickster's +5/+5, Soulstone +15 VIT) which made them feel
		# weaker than the bigger commons. New magnitudes target ~2-3×
		# what a comparable common provides, with multi-stat coverage.
		_make(Item.Type.NECKLACE, "Amulet of the Abyss",
			"Every stat. A bargain with darkness.",
			Color(0.1, 0.05, 0.2), "-", 320,
			{"VIT": 10, "speed": 50.0, "fire_rate_reduction": 0.08,
			 "DEF": 25.0, "projectile_count": 2, "wisdom": 12.0, "MIND": 8},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.NECKLACE, "Soulstone Pendant",
			"+25 VIT, +50 DEF, +5 SPR. Pulsates with life.",
			Color(0.9, 0.1, 0.35), "-", 300,
			{"VIT": 25, "DEF": 50.0, "SPR": 5},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.NECKLACE, "Archmage's Pendant",
			"+15 wisdom, +12 MIND, +8 INT, +5 VIT. Mana floods back.",
			Color(0.1, 0.3, 0.9), "-", 300,
			{"wisdom": 15.0, "MIND": 12, "INT": 8, "VIT": 5},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.NECKLACE, "Wellspring of the Cosmos",
			"+15 wisdom, +12 MIND, +150 stamina regen, +6 WIS. Mana / stamina formalities.",
			Color(0.05, 0.5, 1.0), "-", 300,
			{"wisdom": 15.0, "MIND": 12, "stam_regen": 150.0, "WIS": 6},
			Item.RARITY_LEGENDARY),

		# Legendary shields / tomes (Void Aegis, Manaweave Buckler,
		# Grimoire of the Apocalypse, Codex of Unending Mana) were here —
		# removed when the offhand slot was dropped.

		# ── Synergy Legendaries ────────────────────────────────────────────────
		# Each carries a raw stat block thematically aligned with the
		# synergy effect, so equipping outside the matching build is no
		# longer a strict downgrade — the synergy is the cherry on top.
		_make(Item.Type.RING, "Pyromaniac Sigil",
			"+8 INT, +6 MIND. Fire bolts leave larger, longer-lasting patches.",
			Color(1.0, 0.3, 0.05), "o", 195,
			{"INT": 8, "MIND": 6, "syn_pyromaniac": 1.0},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.NECKLACE, "Glacial Core",
			"+8 WIS, +6 MIND, +4 INT. Freeze bolts deal bonus damage to chilled foes.",
			Color(0.5, 0.85, 1.0), "-", 200,
			{"WIS": 8, "MIND": 6, "INT": 4, "syn_glacial": 1.0},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.HAT, "Arc Conductor",
			"+8 INT, +6 DEX. Shock bolts pierce once, auto-chaining from each hit.",
			Color(0.9, 0.95, 0.1), "^", 205,
			{"INT": 8, "DEX": 6, "syn_arc_conductor": 1.0},
			Item.RARITY_LEGENDARY),
		# Void Lens was a Tome (the offhand-tied nova synergy). Re-typed
		# as a NECKLACE so the syn_void_lens build stays in the game with
		# the Tome type itself gone.
		_make(Item.Type.NECKLACE, "Void Lens",
			"+8 INT, +8 MIND. Nova detonates into 16 piercing shards.",
			Color(0.5, 0.0, 0.9), "-", 210,
			{"INT": 8, "MIND": 8, "syn_void_lens": 1.0},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.FEET, "Assassin's Mark",
			"+8 AGI, +6 DEX, +4 LCK. Homing bolts strike for double damage.",
			Color(0.6, 0.1, 0.8), "n", 200,
			{"AGI": 8, "DEX": 6, "LCK": 4, "syn_assassin_mark": 1.0},
			Item.RARITY_LEGENDARY),
	]

static func random_legendary() -> Item:
	var pool := legendary_items()
	return pool[randi() % pool.size()]
