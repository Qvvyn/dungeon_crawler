class_name ItemDB

# All item definitions. Call ItemDB.random_item() to get a random drop.

static func _make_wand(name: String, desc: String, col: Color, sell: int,
		shoot_type: String, damage: int, fire_rate: float, mana_cost: float,
		proj_speed: float) -> Item:
	var item := Item.new()
	item.type = Item.Type.WAND
	item.display_name = name
	item.description = desc
	item.color = col
	item.icon_char = "/"
	item.sell_value = sell
	item.rarity = Item.RARITY_LEGENDARY
	item.wand_shoot_type = shoot_type
	item.wand_damage = damage
	item.wand_fire_rate = fire_rate
	item.wand_mana_cost = mana_cost
	item.wand_proj_speed = proj_speed
	return item

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
	return [
		# ── Wands (procedurally generated) ───────────────────────────────────
		generate_wand(Item.RARITY_COMMON),
		generate_wand(Item.RARITY_COMMON),
		generate_wand(Item.RARITY_RARE),

		# ── Hats ─────────────────────────────────────────────────────────────
		_make(Item.Type.HAT, "Pointed Hat",    "+1 HP.",
			Color(0.3, 0.3, 0.7), "^", 12, {"max_health": 1}),
		_make(Item.Type.HAT, "Iron Helm",      "+2 HP.",
			Color(0.5, 0.5, 0.6), "^", 20, {"max_health": 2}, Item.RARITY_COMMON, "iron"),
		_make(Item.Type.HAT, "Feathered Cap",  "+8 wisdom.",
			Color(0.7, 0.6, 0.3), "^", 14, {"wisdom": 8.0}, Item.RARITY_COMMON, "swift"),
		_make(Item.Type.HAT, "Arcane Hood",    "+1 HP, +12 wisdom.",
			Color(0.35, 0.25, 0.65), "^", 22, {"max_health": 1, "wisdom": 12.0}, Item.RARITY_COMMON, "arcane"),
		_make(Item.Type.HAT, "Mage's Cowl",    "+18 wisdom.",
			Color(0.2, 0.4, 0.9), "^", 26, {"wisdom": 18.0}),

		# ── Robes ────────────────────────────────────────────────────────────
		_make(Item.Type.ROBES, "Silk Robes",    "+1 HP.",
			Color(0.6, 0.2, 0.5), "%", 14, {"max_health": 1}),
		_make(Item.Type.ROBES, "Battle Garb",   "+2 HP.",
			Color(0.4, 0.4, 0.4), "%", 22, {"max_health": 2}, Item.RARITY_COMMON, "iron"),
		_make(Item.Type.ROBES, "Apprentice Robe", "+10 wisdom.",
			Color(0.25, 0.35, 0.7), "%", 18, {"wisdom": 10.0}, Item.RARITY_COMMON, "arcane"),
		_make(Item.Type.ROBES, "Wizard's Vestment", "+1 HP, +15 wisdom.",
			Color(0.4, 0.2, 0.8), "%", 28, {"max_health": 1, "wisdom": 15.0}),

		# ── Feet ─────────────────────────────────────────────────────────────
		_make(Item.Type.FEET, "Leather Boots",  "+20 speed.",
			Color(0.5, 0.35, 0.2), "n", 12, {"speed": 20.0}, Item.RARITY_COMMON, "swift"),
		_make(Item.Type.FEET, "Swift Shoes",    "+40 speed.",
			Color(0.2, 0.8, 0.5), "n", 24, {"speed": 40.0}, Item.RARITY_COMMON, "swift"),
		_make(Item.Type.FEET, "Sandals of Focus", "+12 wisdom.",
			Color(0.6, 0.7, 0.9), "n", 16, {"wisdom": 12.0}, Item.RARITY_COMMON, "arcane"),

		# ── Rings ─────────────────────────────────────────────────────────────
		_make(Item.Type.RING, "Fire Ring",      "Shoot faster.",
			Color(1.0, 0.4, 0.1), "o", 18, {"fire_rate_reduction": 0.02}),
		_make(Item.Type.RING, "Speed Ring",     "+15 speed.",
			Color(0.2, 0.9, 0.7), "o", 16, {"speed": 15.0}, Item.RARITY_COMMON, "swift"),
		_make(Item.Type.RING, "Scholar's Ring", "+10 wisdom.",
			Color(0.4, 0.6, 1.0), "o", 18, {"wisdom": 10.0}, Item.RARITY_COMMON, "arcane"),
		_make(Item.Type.RING, "Mana Ring",      "+14 wisdom.",
			Color(0.3, 0.5, 1.0), "o", 20, {"wisdom": 14.0}),
		_make(Item.Type.RING, "Sage's Band",    "+8 wisdom, shoot faster.",
			Color(0.5, 0.7, 1.0), "o", 24, {"wisdom": 8.0, "fire_rate_reduction": 0.01}),

		# ── Stat rings (one per stat, RARE) ───────────────────────────────────
		_make(Item.Type.RING, "Bronze Fist Ring",  "+3 STR.",
			Color(1.0, 0.45, 0.25), "o", 36, {"STR": 3.0}, Item.RARITY_RARE),
		_make(Item.Type.RING, "Quicksilver Ring",  "+3 DEX.",
			Color(1.0, 0.85, 0.30), "o", 36, {"DEX": 3.0}, Item.RARITY_RARE),
		_make(Item.Type.RING, "Sprinter's Ring",   "+3 AGI.",
			Color(0.50, 1.00, 0.40), "o", 36, {"AGI": 3.0}, Item.RARITY_RARE),
		_make(Item.Type.RING, "Heart Ring",        "+3 VIT.",
			Color(0.85, 0.20, 0.30), "o", 36, {"VIT": 3.0}, Item.RARITY_RARE),
		_make(Item.Type.RING, "Marathon Ring",     "+3 END.",
			Color(0.30, 0.85, 0.55), "o", 36, {"END": 3.0}, Item.RARITY_RARE),
		_make(Item.Type.RING, "Sage's Eye",        "+3 INT.",
			Color(0.45, 0.55, 1.00), "o", 36, {"INT": 3.0}, Item.RARITY_RARE),
		_make(Item.Type.RING, "Mystic Ring",       "+3 WIS.",
			Color(0.20, 0.55, 1.00), "o", 36, {"WIS": 3.0}, Item.RARITY_RARE),
		_make(Item.Type.RING, "Soul Ring",         "+3 SPR.",
			Color(0.85, 0.65, 1.00), "o", 36, {"SPR": 3.0}, Item.RARITY_RARE),
		_make(Item.Type.RING, "Bulwark Ring",      "+3 DEF.",
			Color(0.55, 0.55, 0.65), "o", 36, {"DEF": 3.0}, Item.RARITY_RARE),
		_make(Item.Type.RING, "Lucky Coin Ring",   "+3 LCK.",
			Color(1.00, 0.95, 0.40), "o", 36, {"LCK": 3.0}, Item.RARITY_RARE),

		# ── Necklaces ─────────────────────────────────────────────────────────
		_make(Item.Type.NECKLACE, "Arcane Pendant", "Shoot faster.",
			Color(0.8, 0.4, 1.0), "-", 20, {"fire_rate_reduction": 0.03}, Item.RARITY_COMMON, "arcane"),
		_make(Item.Type.NECKLACE, "Life Cord",      "+1 HP.",
			Color(0.9, 0.2, 0.3), "-", 16, {"max_health": 1}, Item.RARITY_COMMON, "iron"),
		_make(Item.Type.NECKLACE, "Mana Amulet",    "+15 wisdom.",
			Color(0.2, 0.5, 1.0), "-", 22, {"wisdom": 15.0}),
		_make(Item.Type.NECKLACE, "Wellspring Cord", "+20 wisdom.",
			Color(0.15, 0.6, 1.0), "-", 28, {"wisdom": 20.0}),
		_make(Item.Type.NECKLACE, "Runic Chain",    "+1 HP, +12 wisdom.",
			Color(0.5, 0.3, 0.9), "-", 24, {"max_health": 1, "wisdom": 12.0}),
		_make(Item.Type.NECKLACE, "Warlord's Talisman", "+6 STR, +4 VIT.",
			Color(1.00, 0.30, 0.20), "-", 80, {"STR": 6.0, "VIT": 4.0}, Item.RARITY_LEGENDARY),
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
		_make(Item.Type.POTION, "Health Potion", "Restores 3 HP.",
			Color(0.9, 0.1, 0.2), "!", 8),
	]

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
	if roll < 10:
		for item in all:
			if item.type == Item.Type.WAND:
				pool.append(item)
	elif roll < 50:
		for item in all:
			if item.type in [Item.Type.HAT, Item.Type.ROBES, Item.Type.FEET,
					Item.Type.RING, Item.Type.NECKLACE,
					Item.Type.SHIELD, Item.Type.TOME]:
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

# ── Procedural wand generator ─────────────────────────────────────────────────

static func generate_wand(rarity: int = Item.RARITY_COMMON) -> Item:
	var item := Item.new()
	item.type = Item.Type.WAND
	item.icon_char = "/"
	item.rarity = rarity

	# Pick shoot type by rarity weight
	var shoot_types: Array
	match rarity:
		Item.RARITY_COMMON:
			shoot_types = ["regular", "regular", "regular", "pierce", "ricochet"]
		Item.RARITY_RARE:
			shoot_types = ["regular", "pierce", "ricochet", "freeze", "fire", "shock"]
		Item.RARITY_LEGENDARY:
			shoot_types = ["freeze", "fire", "shock", "beam", "pierce", "ricochet"]
		_:
			shoot_types = ["regular"]
	item.wand_shoot_type = shoot_types[randi() % shoot_types.size()]

	# Base stats by rarity (bumped for the late-game balance pass)
	match rarity:
		Item.RARITY_COMMON:
			item.wand_damage     = randi_range(2, 3)
			item.wand_fire_rate  = randf_range(0.18, 0.32)
			item.wand_mana_cost  = randf_range(3.0, 7.0)
			item.wand_proj_speed = randf_range(500.0, 650.0)
		Item.RARITY_RARE:
			item.wand_damage     = randi_range(3, 5)
			item.wand_fire_rate  = randf_range(0.12, 0.24)
			item.wand_mana_cost  = randf_range(6.0, 12.0)
			item.wand_proj_speed = randf_range(580.0, 750.0)
		Item.RARITY_LEGENDARY:
			item.wand_damage     = randi_range(5, 10)
			item.wand_fire_rate  = randf_range(0.08, 0.16)
			item.wand_mana_cost  = randf_range(10.0, 20.0)
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
			item.wand_mana_cost = randf_range(15.0, 30.0)   # per second

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

	var flaw_pool: Array = ["backwards", "drift", "clunky", "mana_guzzle", "slow_shots", "erratic"]
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
			"+6 HP. +20 DEF. Absolute authority.",
			Color(0.9, 0.75, 0.0), "^", 200,
			{"max_health": 6, "DEF": 20.0},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.HAT, "Mindweave Circlet",
			"+60 wisdom. Mana practically infinite.",
			Color(0.2, 0.5, 1.0), "^", 220,
			{"wisdom": 60.0},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.HAT, "Tiara of the Arcane Sea",
			"+3 HP, +45 wisdom. The ocean remembers.",
			Color(0.1, 0.7, 0.9), "^", 215,
			{"max_health": 3, "wisdom": 45.0},
			Item.RARITY_LEGENDARY),

		# ── Legendary Robes ────────────────────────────────────────────────────
		_make(Item.Type.ROBES, "Shroud of the Undying",
			"+1000 HP, +15 DEF, move faster.",
			Color(0.1, 0.55, 0.35), "%", 190,
			{"max_health": 1000, "DEF": 15.0, "speed": 15.0},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.ROBES, "Phantom Wrap",
			"Ghost-silk. Near impossible to hit.",
			Color(0.5, 0.2, 0.8), "%", 170,
			{"speed": 70.0, "DEF": 25.0},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.ROBES, "Robes of the Eternal Mage",
			"+2 HP, +55 wisdom, +10 DEF.",
			Color(0.15, 0.3, 0.85), "%", 230,
			{"max_health": 2, "wisdom": 55.0, "DEF": 10.0},
			Item.RARITY_LEGENDARY),

		# ── Legendary Feet ─────────────────────────────────────────────────────
		_make(Item.Type.FEET, "Boots of the Tempest",
			"+100 speed. The ground barely notices.",
			Color(0.9, 0.95, 1.0), "n", 155,
			{"speed": 100.0, "fire_rate_reduction": 0.06},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.FEET, "Slippers of the Archmage",
			"+50 wisdom, +20 speed.",
			Color(0.3, 0.5, 1.0), "n", 180,
			{"wisdom": 50.0, "speed": 20.0},
			Item.RARITY_LEGENDARY),

		# ── Legendary Rings ────────────────────────────────────────────────────
		_make(Item.Type.RING, "Ring of the Cosmos",
			"+2 proj, faster fire, +2 HP.",
			Color(0.1, 0.5, 1.0), "o", 175,
			{"projectile_count": 2, "fire_rate_reduction": 0.05, "max_health": 2},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.RING, "Ouroboros Sigil",
			"+4 HP. +30 DEF. Eternal.",
			Color(0.85, 0.6, 0.05), "o", 165,
			{"max_health": 4, "DEF": 30.0},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.RING, "Ring of Infinite Flow",
			"+50 wisdom. Mana never runs dry.",
			Color(0.2, 0.6, 1.0), "o", 185,
			{"wisdom": 50.0},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.RING, "Resonance Loop",
			"+35 wisdom, shoot faster.",
			Color(0.4, 0.7, 1.0), "o", 175,
			{"wisdom": 35.0, "fire_rate_reduction": 0.04},
			Item.RARITY_LEGENDARY),

		# ── Legendary Necklaces ────────────────────────────────────────────────
		_make(Item.Type.NECKLACE, "Amulet of the Abyss",
			"Every stat. A bargain with darkness.",
			Color(0.1, 0.05, 0.2), "-", 220,
			{"max_health": 2, "speed": 20.0, "fire_rate_reduction": 0.04,
			 "DEF": 10.0, "projectile_count": 1, "wisdom": 20.0},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.NECKLACE, "Soulstone Pendant",
			"+8 HP. +25 DEF. Pulsates with life.",
			Color(0.9, 0.1, 0.35), "-", 210,
			{"max_health": 8, "DEF": 25.0},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.NECKLACE, "Archmage's Pendant",
			"Wisdom flows through it. Mana floods back.",
			Color(0.1, 0.3, 0.9), "-", 200,
			{"wisdom": 60.0, "max_health": 2},
			Item.RARITY_LEGENDARY),
		_make(Item.Type.NECKLACE, "Wellspring of the Cosmos",
			"+80 wisdom. +120 stamina regen. Mana and stamina are a formality.",
			Color(0.05, 0.5, 1.0), "-", 260,
			{"wisdom": 80.0, "stam_regen": 120.0},
			Item.RARITY_LEGENDARY),

		# ── Legendary Shields ──────────────────────────────────────────────────
		_make(Item.Type.SHIELD, "Void Aegis",
			"+50 DEF. +3 HP. Drinks strikes whole.",
			Color(0.0, 0.05, 0.3), "D", 180,
			{"DEF": 50.0, "max_health": 3},
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
