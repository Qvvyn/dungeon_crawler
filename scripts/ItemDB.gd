class_name ItemDB

# All item definitions. Call ItemDB.random_item() to get a random drop.

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

		# ── Hats ─────────────────────────────────────────────────────────────
		# HP-bearing items now grant VIT (×5 max-HP each via the stat
		# scaling) so a +2 VIT helm reads as +10 effective HP and gear
		# starts feeling significant rather than incremental.
		_make(Item.Type.HAT, "Pointed Hat",    "+2 VIT.",
			Color(0.3, 0.3, 0.7), "^", 18, {"VIT": 2}),
		_make(Item.Type.HAT, "Iron Helm",      "+4 VIT.",
			Color(0.5, 0.5, 0.6), "^", 30, {"VIT": 4}, Item.RARITY_COMMON, "iron"),
		_make(Item.Type.HAT, "Feathered Cap",  "+15 wisdom.",
			Color(0.7, 0.6, 0.3), "^", 22, {"wisdom": 15.0}, Item.RARITY_COMMON, "swift"),
		_make(Item.Type.HAT, "Arcane Hood",    "+2 VIT, +20 wisdom.",
			Color(0.35, 0.25, 0.65), "^", 32, {"VIT": 2, "wisdom": 20.0}, Item.RARITY_COMMON, "arcane"),
		_make(Item.Type.HAT, "Mage's Cowl",    "+30 wisdom.",
			Color(0.2, 0.4, 0.9), "^", 38, {"wisdom": 30.0}),

		# ── Robes ────────────────────────────────────────────────────────────
		_make(Item.Type.ROBES, "Silk Robes",    "+2 VIT.",
			Color(0.6, 0.2, 0.5), "%", 20, {"VIT": 2}),
		_make(Item.Type.ROBES, "Battle Garb",   "+4 VIT.",
			Color(0.4, 0.4, 0.4), "%", 32, {"VIT": 4}, Item.RARITY_COMMON, "iron"),
		_make(Item.Type.ROBES, "Apprentice Robe", "+18 wisdom.",
			Color(0.25, 0.35, 0.7), "%", 26, {"wisdom": 18.0}, Item.RARITY_COMMON, "arcane"),
		_make(Item.Type.ROBES, "Wizard's Vestment", "+2 VIT, +25 wisdom.",
			Color(0.4, 0.2, 0.8), "%", 40, {"VIT": 2, "wisdom": 25.0}),

		# ── Feet ─────────────────────────────────────────────────────────────
		_make(Item.Type.FEET, "Leather Boots",  "+30 speed.",
			Color(0.5, 0.35, 0.2), "n", 16, {"speed": 30.0}, Item.RARITY_COMMON, "swift"),
		_make(Item.Type.FEET, "Swift Shoes",    "+60 speed.",
			Color(0.2, 0.8, 0.5), "n", 30, {"speed": 60.0}, Item.RARITY_COMMON, "swift"),
		_make(Item.Type.FEET, "Sandals of Focus", "+18 wisdom.",
			Color(0.6, 0.7, 0.9), "n", 22, {"wisdom": 18.0}, Item.RARITY_COMMON, "arcane"),

		# ── Rings ─────────────────────────────────────────────────────────────
		_make(Item.Type.RING, "Fire Ring",      "Shoot faster.",
			Color(1.0, 0.4, 0.1), "o", 24, {"fire_rate_reduction": 0.04}),
		_make(Item.Type.RING, "Speed Ring",     "+25 speed.",
			Color(0.2, 0.9, 0.7), "o", 22, {"speed": 25.0}, Item.RARITY_COMMON, "swift"),
		_make(Item.Type.RING, "Scholar's Ring", "+18 wisdom.",
			Color(0.4, 0.6, 1.0), "o", 24, {"wisdom": 18.0}, Item.RARITY_COMMON, "arcane"),
		_make(Item.Type.RING, "Mana Ring",      "+22 wisdom.",
			Color(0.3, 0.5, 1.0), "o", 28, {"wisdom": 22.0}),
		_make(Item.Type.RING, "Sage's Band",    "+14 wisdom, shoot faster.",
			Color(0.5, 0.7, 1.0), "o", 30, {"wisdom": 14.0, "fire_rate_reduction": 0.02}),

		# ── Stat rings (one per stat, RARE) ───────────────────────────────────
		# Bumped from +3 → +5 each so a stat ring drop feels worth slotting.
		_make(Item.Type.RING, "Bronze Fist Ring",  "+5 VIT.",
			Color(1.0, 0.45, 0.25), "o", 50, {"VIT": 5.0}, Item.RARITY_RARE),
		_make(Item.Type.RING, "Quicksilver Ring",  "+5 DEX.",
			Color(1.0, 0.85, 0.30), "o", 50, {"DEX": 5.0}, Item.RARITY_RARE),
		_make(Item.Type.RING, "Sprinter's Ring",   "+5 AGI.",
			Color(0.50, 1.00, 0.40), "o", 50, {"AGI": 5.0}, Item.RARITY_RARE),
		_make(Item.Type.RING, "Heart Ring",        "+5 VIT.",
			Color(0.85, 0.20, 0.30), "o", 50, {"VIT": 5.0}, Item.RARITY_RARE),
		_make(Item.Type.RING, "Marathon Ring",     "+5 END.",
			Color(0.30, 0.85, 0.55), "o", 50, {"END": 5.0}, Item.RARITY_RARE),
		_make(Item.Type.RING, "Sage's Eye",        "+5 INT.",
			Color(0.45, 0.55, 1.00), "o", 50, {"INT": 5.0}, Item.RARITY_RARE),
		_make(Item.Type.RING, "Mystic Ring",       "+5 WIS.",
			Color(0.20, 0.55, 1.00), "o", 50, {"WIS": 5.0}, Item.RARITY_RARE),
		_make(Item.Type.RING, "Soul Ring",         "+5 SPR.",
			Color(0.85, 0.65, 1.00), "o", 50, {"SPR": 5.0}, Item.RARITY_RARE),
		_make(Item.Type.RING, "Bulwark Ring",      "+5 DEF.",
			Color(0.55, 0.55, 0.65), "o", 50, {"DEF": 5.0}, Item.RARITY_RARE),
		_make(Item.Type.RING, "Lucky Coin Ring",   "+5 LCK.",
			Color(1.00, 0.95, 0.40), "o", 50, {"LCK": 5.0}, Item.RARITY_RARE),

		# ── Necklaces ─────────────────────────────────────────────────────────
		_make(Item.Type.NECKLACE, "Arcane Pendant", "Shoot faster.",
			Color(0.8, 0.4, 1.0), "-", 28, {"fire_rate_reduction": 0.05}, Item.RARITY_COMMON, "arcane"),
		_make(Item.Type.NECKLACE, "Life Cord",      "+3 VIT.",
			Color(0.9, 0.2, 0.3), "-", 28, {"VIT": 3}, Item.RARITY_COMMON, "iron"),
		_make(Item.Type.NECKLACE, "Mana Amulet",    "+24 wisdom.",
			Color(0.2, 0.5, 1.0), "-", 32, {"wisdom": 24.0}),
		_make(Item.Type.NECKLACE, "Wellspring Cord", "+30 wisdom.",
			Color(0.15, 0.6, 1.0), "-", 38, {"wisdom": 30.0}),
		_make(Item.Type.NECKLACE, "Runic Chain",    "+2 VIT, +18 wisdom.",
			Color(0.5, 0.3, 0.9), "-", 36, {"VIT": 2, "wisdom": 18.0}),
		# Warlord's used to be +STR/+VIT; STR was removed so it's now +INT/+VIT
		# (damage + tankiness via the surviving stats).
		_make(Item.Type.NECKLACE, "Warlord's Talisman", "+6 INT, +4 VIT.",
			Color(1.00, 0.30, 0.20), "-", 80, {"INT": 6.0, "VIT": 4.0}, Item.RARITY_LEGENDARY),
		_make(Item.Type.NECKLACE, "Archmage's Sigil",  "+6 INT, +4 WIS.",
			Color(0.40, 0.55, 1.00), "-", 80, {"INT": 6.0, "WIS": 4.0}, Item.RARITY_LEGENDARY),
		_make(Item.Type.NECKLACE, "Trickster's Charm", "+5 LCK, +5 DEX.",
			Color(1.00, 0.85, 0.30), "-", 80, {"LCK": 5.0, "DEX": 5.0}, Item.RARITY_LEGENDARY),

		# ── Shields ───────────────────────────────────────────────────────────
		_make(Item.Type.SHIELD, "Wooden Shield",   "+15 DEF.",
			Color(0.55, 0.38, 0.18), "D", 15, {"DEF": 15.0}),
		_make(Item.Type.SHIELD, "Iron Shield",     "+25 DEF.",
			Color(0.55, 0.55, 0.60), "D", 28, {"DEF": 25.0}, Item.RARITY_COMMON, "iron"),
		_make(Item.Type.SHIELD, "Arcane Ward",     "+20 DEF, +10 wisdom.",
			Color(0.55, 0.20, 0.80), "D", 26, {"DEF": 20.0, "wisdom": 10.0}),

		# ── Tomes ─────────────────────────────────────────────────────────────
		_make(Item.Type.TOME, "Tome of Twins",   "Fire 2 projectiles.",
			Color(0.25, 0.50, 0.90), "=", 18, {"projectile_count": 1}),
		_make(Item.Type.TOME, "Tome of Trident", "Fire 3 projectiles.",
			Color(0.10, 0.80, 0.85), "=", 30, {"projectile_count": 2}),
		_make(Item.Type.TOME, "Tome of Barrage", "Fire 4 projectiles.",
			Color(0.95, 0.55, 0.10), "=", 45, {"projectile_count": 3}),
		_make(Item.Type.TOME, "Tome of Flow",    "+2 projectiles, +12 wisdom.",
			Color(0.30, 0.65, 1.00), "=", 38, {"projectile_count": 1, "wisdom": 12.0}),

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
	# Difficulty-scaled rarity chances. Higher tiers reward better gear so
	# the player keeps pace with the enemy/damage ramp from the per-+1.0
	# difficulty scaling.
	var diff_now: float = GameState.difficulty
	if roll < 10:
		# Wand drop. 15 % chance for a curated limited-use wand, otherwise
		# a procedural wand whose rarity scales with current difficulty.
		if randi() % 100 < 15:
			var lw_pool := limited_use_wands()
			return lw_pool[randi() % lw_pool.size()]
		var r_roll := randi() % 100
		var picked_rarity: int = Item.RARITY_COMMON
		if diff_now >= 4.0:
			if r_roll < 30: picked_rarity = Item.RARITY_LEGENDARY
			elif r_roll < 80: picked_rarity = Item.RARITY_RARE
		elif diff_now >= 2.5:
			if r_roll < 15: picked_rarity = Item.RARITY_LEGENDARY
			elif r_roll < 65: picked_rarity = Item.RARITY_RARE
		elif diff_now >= 1.5:
			if r_roll < 35: picked_rarity = Item.RARITY_RARE
		return generate_wand(picked_rarity)
	elif roll < 50:
		# Offhand items (SHIELD / TOME) are excluded — that slot is disabled
		# for now, so they'd just be unequippable junk in the bag.
		# Difficulty-scaled chance to substitute a legendary gear piece.
		var leg_chance: int = 0
		if diff_now >= 4.0: leg_chance = 35
		elif diff_now >= 3.0: leg_chance = 22
		elif diff_now >= 2.0: leg_chance = 10
		if leg_chance > 0 and randi() % 100 < leg_chance:
			var leg_pool: Array = []
			for it in legendary_items():
				if it.type in [Item.Type.HAT, Item.Type.ROBES, Item.Type.FEET,
						Item.Type.RING, Item.Type.NECKLACE]:
					leg_pool.append(it)
			if not leg_pool.is_empty():
				return leg_pool[randi() % leg_pool.size()]
		# Procedural gear gating now keys off the *player level* — the
		# user's progression milestone — instead of difficulty, so a high-
		# diff Hellpit start doesn't dump procedural pieces at level 1
		# but a level-15 deep run does. Stat magnitudes still scale with
		# difficulty inside generate_gear; only the *chance* of hitting a
		# procedural roll is level-gated.
		var lvl_now: int = GameState.level
		var proc_chance: int = 0
		if lvl_now >= 15: proc_chance = 75
		elif lvl_now >= 10: proc_chance = 55
		elif lvl_now >= 5:  proc_chance = 35
		if proc_chance > 0 and randi() % 100 < proc_chance:
			# Within a procedural roll, *rarity* still keys off difficulty
			# so deep floors push rare/legendary even on a fresh-leveled
			# character.
			var proc_rarity: int = Item.RARITY_COMMON
			var rr: int = randi() % 100
			if diff_now >= 4.0:
				if rr < 25: proc_rarity = Item.RARITY_LEGENDARY
				elif rr < 70: proc_rarity = Item.RARITY_RARE
			elif diff_now >= 2.5:
				if rr < 12: proc_rarity = Item.RARITY_LEGENDARY
				elif rr < 55: proc_rarity = Item.RARITY_RARE
			elif diff_now >= 1.5:
				if rr < 30: proc_rarity = Item.RARITY_RARE
			return generate_gear(proc_rarity)
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
	if pool.is_empty():
		return all[randi() % all.size()]
	return pool[randi() % pool.size()]

# ── Procedural gear generator ────────────────────────────────────────────────
# Per-slot stat pools. Each entry is a stat name + a (lo, hi) magnitude
# range for COMMON drops; rare/legendary scale the range upward and roll
# more stats per item.
const _GEAR_TYPE_POOLS := {
	# type → {icon, color, stats: [[name, lo, hi], ...]}
	"hat": {
		"icon": "^",
		"color": Color(0.45, 0.40, 0.85),
		"bases": ["Hat", "Cowl", "Cap", "Hood", "Crown", "Circlet"],
		"stats": [
			["VIT",                 2, 6],
			["wisdom",              10, 25],
			["fire_rate_reduction", 2, 6],   # interpreted as 0.01 each
			["INT",                 2, 5],
			["WIS",                 2, 5],
			["DEF",                 8, 20],
		],
	},
	"robes": {
		"icon": "%",
		"color": Color(0.55, 0.30, 0.75),
		"bases": ["Robe", "Vestment", "Mantle", "Cloak", "Garb"],
		"stats": [
			["VIT",        3, 8],
			["DEF",        12, 30],
			["speed",      18, 40],
			["wisdom",     10, 22],
		],
	},
	"feet": {
		"icon": "n",
		"color": Color(0.45, 0.65, 0.40),
		"bases": ["Boots", "Shoes", "Sandals", "Greaves", "Slippers"],
		"stats": [
			["speed",              25, 60],
			["AGI",                2, 5],
			["fire_rate_reduction", 2, 5],
			["stam_regen",         25, 80],
		],
	},
	"ring": {
		"icon": "o",
		"color": Color(0.85, 0.65, 0.30),
		"bases": ["Ring", "Band", "Loop", "Sigil", "Signet"],
		"stats": [
			["VIT",                 2, 4],
			["fire_rate_reduction", 2, 5],
			["wisdom",              10, 20],
			["DEX",                 2, 5],
			["LCK",                 2, 5],
			["DEF",                 8, 18],
		],
	},
	"necklace": {
		"icon": "-",
		"color": Color(0.70, 0.40, 0.85),
		"bases": ["Pendant", "Amulet", "Talisman", "Cord", "Charm"],
		"stats": [
			["VIT",                 2, 6],
			["wisdom",              15, 32],
			["fire_rate_reduction", 2, 6],
			["INT",                 3, 7],
			["WIS",                 3, 7],
			["LCK",                 3, 7],
		],
	},
}

const _GEAR_PREFIXES_COMMON := ["Worn", "Plain", "Sturdy", "Simple", "Hand", "Old"]
const _GEAR_PREFIXES_RARE   := ["Glowing", "Runed", "Etched", "Honed", "Ancient", "Refined"]
const _GEAR_PREFIXES_LEG    := ["Eternal", "Cosmic", "Voidforged", "Astral", "Sovereign", "Phantasm"]

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
	# Stat count scales with rarity: common = 1, rare = 2, legendary = 3.
	var stat_count: int = 1 if rarity == Item.RARITY_COMMON else (2 if rarity == Item.RARITY_RARE else 3)
	# Difficulty multiplier on stat magnitudes — +20 % per +1.0 above 1,
	# so deep floors roll genuinely stronger gear.
	var diff_extra: float = maxf(0.0, GameState.difficulty - 1.0)
	var diff_mult: float = 1.0 + diff_extra * 0.20
	# Rarity multiplier on top of the base ranges so a rare hat feels
	# rare even at low diff.
	var rarity_mult: float = 1.0
	if rarity == Item.RARITY_RARE:      rarity_mult = 1.6
	elif rarity == Item.RARITY_LEGENDARY: rarity_mult = 2.4
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
	if rarity == Item.RARITY_RARE:
		prefix_pool = _GEAR_PREFIXES_RARE
	elif rarity == Item.RARITY_LEGENDARY:
		prefix_pool = _GEAR_PREFIXES_LEG
	var prefix: String = prefix_pool[randi() % prefix_pool.size()]
	var base_list: Array = pool["bases"]
	var base: String = String(base_list[randi() % base_list.size()])
	item.display_name = "%s %s" % [prefix, base]
	# Sell value scales with stat count + rarity + difficulty. Roughly
	# tracks the value of fixed legendaries at high diff.
	item.sell_value = int(round(20.0 * float(stat_count) * (1.0 + float(rarity) * 0.6) * diff_mult))
	# Color shift toward gold/purple for higher rarities.
	if rarity == Item.RARITY_LEGENDARY:
		item.color = item.color.lerp(Color(1.0, 0.55, 1.0), 0.45)
	elif rarity == Item.RARITY_RARE:
		item.color = item.color.lerp(Color(1.0, 0.92, 0.45), 0.30)
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

	# Base stats by rarity (bumped for the late-game balance pass)
	match rarity:
		Item.RARITY_COMMON:
			item.wand_damage     = randi_range(2, 3)
			item.wand_fire_rate  = randf_range(0.18, 0.32)
			item.wand_mana_cost  = randf_range(2.0, 5.0)
			item.wand_proj_speed = randf_range(500.0, 650.0)
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
	# Legendary tier bonus — pierce + ricochet stack onto whatever shoot
	# type rolled, no extra mana penalty. Makes "this wand is legendary"
	# always feel different from the rare/common version of the same
	# shoot type, even if the headline type is the same.
	if rarity == Item.RARITY_LEGENDARY:
		item.wand_pierce   += randi_range(2, 3)
		item.wand_ricochet += randi_range(2, 3)

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
	var flaw_pool: Array = ["backwards", "clunky", "sloppy", "slow_shots"]
	flaw_pool.shuffle()
	for i in num_flaws:
		item.wand_flaws.append(flaw_pool[i])

	# Difficulty scaling — wands rolled on later floors hit harder, fire faster,
	# and have more pierce/ricochet/stacks. Damage gets the biggest bump so
	# loot keeps pace with the +0.15 enemy HP scaling per difficulty tier.
	var diff: float = maxf(GameState.difficulty - 1.0, 0.0)
	if diff > 0.0:
		var dmg_scale: float = 1.0 + diff * 0.20
		item.wand_damage = int(round(float(item.wand_damage) * dmg_scale))
		item.wand_fire_rate = maxf(0.04, item.wand_fire_rate * (1.0 - diff * 0.04))
		item.wand_proj_speed = item.wand_proj_speed * (1.0 + diff * 0.05)
		# Stacks/pierce/ricochet creep up too at higher floors
		if item.wand_pierce > 0:
			item.wand_pierce += int(diff * 0.5)
		if item.wand_ricochet > 0:
			item.wand_ricochet += int(diff * 0.5)
		if item.wand_status_stacks > 0:
			item.wand_status_stacks += int(diff * 0.4)

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
	match wand.wand_shoot_type:
		"regular":   return Color(0.75, 0.60, 0.35)
		"pierce":    return Color(0.95, 0.95, 0.30)
		"ricochet":  return Color(0.35, 1.00, 0.50)
		"freeze":    return Color(0.30, 0.75, 1.00)
		"fire":      return Color(1.00, 0.40, 0.10)
		"shock":     return Color(0.90, 0.95, 0.30)
		"beam":      return Color(0.30, 1.00, 0.80)
	return Color(0.70, 0.50, 0.20)

# ── Boss signature wands ─────────────────────────────────────────────────────
# Each boss type guarantees a hand-tuned legendary wand on death so floor-5
# milestones have a clear chase. Stats are generous on purpose — these are
# end-of-arc rewards. Damage scales softly with floor difficulty so a deep
# Hellpit boss drops a meaningfully stronger version than the first arena.
static func boss_signature_brute() -> Item:
	# Brutehammer — heavy shotgun cone. Slow but lethal at point blank.
	var diff_extra: int = int(maxf(0.0, GameState.difficulty - 1.0) * 1.5)
	var w := _make_wand("Brutehammer",
		"Brute boss legacy. Five-shot cone. Crushes elites at point blank.",
		Color(1.0, 0.45, 0.10), 320, "shotgun",
		6 + diff_extra, 0.32, 12.0, 580.0)
	w.wand_pierce   = 1
	w.wand_ricochet = 1
	return w

static func boss_signature_architect() -> Item:
	# Architect's Compass — homing wand with extra pierce, finds its target.
	var diff_extra: int = int(maxf(0.0, GameState.difficulty - 1.0) * 1.5)
	var w := _make_wand("Architect's Compass",
		"Architect boss legacy. Homing bolts with deep pierce — distance is irrelevant.",
		Color(0.55, 0.30, 1.00), 340, "homing",
		7 + diff_extra, 0.18, 10.0, 380.0)
	w.wand_pierce   = 3
	w.wand_ricochet = 1
	return w

static func boss_signature_wraith() -> Item:
	# Wraithcaster — high-stack shock wand. Stacks fly in fast for chain procs.
	var diff_extra: int = int(maxf(0.0, GameState.difficulty - 1.0) * 1.5)
	var w := _make_wand("Wraithcaster",
		"Wraith boss legacy. Three-stack shock per hit. Chain lightning ramps fast.",
		Color(0.75, 0.95, 1.00), 320, "shock",
		5 + diff_extra, 0.14, 9.0, 720.0)
	w.wand_status_stacks = 3
	w.wand_ricochet      = 2
	return w

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
			"+80 wisdom, +6 INT. Mana practically infinite.",
			Color(0.2, 0.5, 1.0), "^", 260,
			{"wisdom": 80.0, "INT": 6.0},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.HAT, "Tiara of the Arcane Sea",
			"+5 VIT, +60 wisdom. The ocean remembers.",
			Color(0.1, 0.7, 0.9), "^", 255,
			{"VIT": 5, "wisdom": 60.0},
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
			"+4 VIT, +75 wisdom, +20 DEF.",
			Color(0.15, 0.3, 0.85), "%", 270,
			{"VIT": 4, "wisdom": 75.0, "DEF": 20.0},
			Item.RARITY_LEGENDARY),

		# ── Legendary Feet ─────────────────────────────────────────────────────
		_make(Item.Type.FEET, "Boots of the Tempest",
			"+150 speed, faster fire. The ground barely notices.",
			Color(0.9, 0.95, 1.0), "n", 200,
			{"speed": 150.0, "fire_rate_reduction": 0.10},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.FEET, "Slippers of the Archmage",
			"+70 wisdom, +35 speed, +5 INT.",
			Color(0.3, 0.5, 1.0), "n", 220,
			{"wisdom": 70.0, "speed": 35.0, "INT": 5.0},
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
			"+70 wisdom, +6 WIS. Mana never runs dry.",
			Color(0.2, 0.6, 1.0), "o", 230,
			{"wisdom": 70.0, "WIS": 6.0},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.RING, "Resonance Loop",
			"+50 wisdom, shoot much faster.",
			Color(0.4, 0.7, 1.0), "o", 220,
			{"wisdom": 50.0, "fire_rate_reduction": 0.07},
			Item.RARITY_LEGENDARY),

		# ── Legendary Necklaces ────────────────────────────────────────────────
		_make(Item.Type.NECKLACE, "Amulet of the Abyss",
			"Every stat. A bargain with darkness.",
			Color(0.1, 0.05, 0.2), "-", 280,
			{"VIT": 5, "speed": 30.0, "fire_rate_reduction": 0.06,
			 "DEF": 18.0, "projectile_count": 2, "wisdom": 30.0},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.NECKLACE, "Soulstone Pendant",
			"+15 VIT, +35 DEF. Pulsates with life.",
			Color(0.9, 0.1, 0.35), "-", 260,
			{"VIT": 15, "DEF": 35.0},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.NECKLACE, "Archmage's Pendant",
			"+80 wisdom, +5 VIT. Mana floods back.",
			Color(0.1, 0.3, 0.9), "-", 250,
			{"wisdom": 80.0, "VIT": 5},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.NECKLACE, "Wellspring of the Cosmos",
			"+80 wisdom. +120 stamina regen. Mana and stamina are a formality.",
			Color(0.05, 0.5, 1.0), "-", 260,
			{"wisdom": 80.0, "stam_regen": 120.0},
			Item.RARITY_LEGENDARY),

		# ── Legendary Shields ──────────────────────────────────────────────────
		_make(Item.Type.SHIELD, "Void Aegis",
			"+50 DEF, +5 VIT. Drinks strikes whole.",
			Color(0.0, 0.05, 0.3), "D", 220,
			{"DEF": 50.0, "VIT": 5},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.SHIELD, "Manaweave Buckler",
			"+30 DEF, +40 wisdom.",
			Color(0.2, 0.4, 0.9), "D", 190,
			{"DEF": 30.0, "wisdom": 40.0},
			Item.RARITY_LEGENDARY),

		# ── Legendary Tomes ────────────────────────────────────────────────────
		_make(Item.Type.TOME, "Grimoire of the Apocalypse",
			"Fire 6 bolts. Faster. Forever.",
			Color(0.8, 0.0, 0.05), "=", 200,
			{"projectile_count": 5, "fire_rate_reduction": 0.10},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.TOME, "Codex of Unending Mana",
			"+4 proj, +45 wisdom. Cast without cost.",
			Color(0.2, 0.5, 1.0), "=", 240,
			{"projectile_count": 3, "wisdom": 45.0, "fire_rate_reduction": 0.06},
			Item.RARITY_LEGENDARY),

		# ── Synergy Legendaries ────────────────────────────────────────────────
		_make(Item.Type.RING, "Pyromaniac Sigil",
			"Fire bolts leave larger, longer-lasting patches.",
			Color(1.0, 0.3, 0.05), "o", 195,
			{"syn_pyromaniac": 1.0},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.NECKLACE, "Glacial Core",
			"Freeze bolts deal bonus damage to chilled foes.",
			Color(0.5, 0.85, 1.0), "-", 200,
			{"syn_glacial": 1.0},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.HAT, "Arc Conductor",
			"Shock bolts pierce once, auto-chaining from each hit.",
			Color(0.9, 0.95, 0.1), "^", 205,
			{"syn_arc_conductor": 1.0},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.TOME, "Void Lens",
			"Nova detonates into 16 piercing shards.",
			Color(0.5, 0.0, 0.9), "=", 210,
			{"syn_void_lens": 1.0},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.FEET, "Assassin's Mark",
			"Homing bolts strike for double damage.",
			Color(0.6, 0.1, 0.8), "n", 200,
			{"syn_assassin_mark": 1.0},
			Item.RARITY_LEGENDARY),
	]

static func random_legendary() -> Item:
	var pool := legendary_items()
	return pool[randi() % pool.size()]
