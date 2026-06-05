class_name Item
extends RefCounted

enum Type { WAND, HAT, ROBES, FEET, RING, NECKLACE, SHIELD, TOME, VALUABLE, POTION }

# Wand flaws are disabled for now (straying from the mechanic). One flag gates
# both generation (ItemDB.generate_wand) and loading (from_dict below), so new,
# banked, and saved wands all come through flawless. Flip to re-enable.
const WAND_FLAWS_ENABLED := false

# Ordered ascending so `item.rarity > other.rarity` still means "better."
# Renumbering note: rare and legendary moved up by 1 to make room for
# uncommon. Save files written before this change get silently down-
# shifted (an old "rare" saved as 1 will load as "uncommon"). Acceptable
# churn for a one-time loot-rule change; if a stronger migration is
# needed later, add a version key to to_dict / from_dict.
const RARITY_COMMON    := 0
const RARITY_UNCOMMON  := 1
const RARITY_RARE      := 2
const RARITY_LEGENDARY := 3

var type: Type
var display_name: String
var description: String
var color: Color
var icon_char: String = "?"
var sell_value: int = 5
var rarity: int = RARITY_COMMON
# Lowest rarity this item can drop at. Drop logic re-rolls every fixed
# gear template's rarity per drop (the +4 VIT Pointed Hat is a base
# template; the actual drop rolls common/uncommon/rare and scales stats
# by the rarity multiplier). min_rarity puts a floor on that roll —
# stat rings use UNCOMMON so they never drop as common.
var min_rarity: int = RARITY_COMMON
# Item tier — primary scaling axis for procedurally generated gear. Set
# by ItemDB.generate_gear / generate_wand from a roll keyed off the
# floor's difficulty (between max(1, floor(diff) - 5) and floor(diff)).
# Tier drives the stat magnitude curve; rarity is a separate axis that
# determines stat COUNT and a flat magnitude bump on top.
# Tier 0 = static / unscaled item (fixed legendaries, valuables, potions).
var tier: int = 0
# Flat bonuses applied while equipped. Keys: "speed", "max_health", "fire_rate_reduction", "DEF", "projectile_count"
var stat_bonuses: Dictionary = {}
var set_tag: String = ""   # "arcane" | "iron" | "swift" | ""
# Stack count for stackable items (potions, valuables). Always 1 for
# non-stackable types. InventoryManager.add_item folds an incoming
# stackable into an existing stack of the same kind, capped at STACK_CAP
# per slot before overflowing into a new slot.
var quantity: int = 1

# Per-slot stack ceiling. Anything past this rolls into a fresh slot so
# the bag isn't a single 999-deep pile that obscures inventory pressure.
const STACK_CAP: int = 10

# Items that fold into a single inventory slot when picked up. Potions
# stack because consumables shouldn't bloat the bag; valuables (gems,
# coins, crystals) stack because they're functionally currency. Gear /
# wands stay distinct since they carry per-instance state (rolled stats,
# affixes, charges).
func is_stackable() -> bool:
	return type == Type.POTION or type == Type.VALUABLE

# Wand-specific fields (only meaningful when type == WAND)
var wand_shoot_type: String  = "regular"  # regular/pierce/ricochet/chain/freeze/fire/beam
var wand_damage: int         = 1
var wand_mana_cost: float    = 5.0        # mana per shot (beam: per second)
var wand_fire_rate: float    = 0.20       # seconds between shots
var wand_proj_speed: float   = 600.0
var wand_pierce: int         = 0          # enemies passed through
var wand_ricochet: int       = 0          # wall bounces
var wand_status_stacks: int  = 1          # stacks applied per hit (freeze/fire)
var wand_flaws: Array        = []         # backwards/clunky/sloppy/mana_guzzle/slow_shots/erratic (drift currently disabled)
# Limited-use wands carry a finite charge count and shatter when they hit
# zero. wand_max_charges == 0 means unlimited (the regular case). Each fire
# decrements wand_charges; when it reaches 0 the wand auto-unequips. Used to
# create high-power "consumable" wands on the drop table.
var wand_max_charges: int    = 0
var wand_charges: int        = 0
# Number of times this wand has been forged at the enchanting table.
# Each subsequent forge costs 1.5× the previous so chain-forging the
# same wand into a god-roll has a visible escalating price tag.
var wand_forge_count: int    = 0

func is_limited_use() -> bool:
	return wand_max_charges > 0

## Returns the equipment slot name this item occupies, or "" if not equippable.
## SHIELD / TOME items return "" — the offhand slot was removed, but the
## item types still exist (drops, sell value, fusion) so they round-trip
## through the bag. They just can't be equipped.
func get_equip_slot_name() -> String:
	match type:
		Type.WAND:     return "wand"
		Type.HAT:      return "hat"
		Type.ROBES:    return "robes"
		Type.FEET:     return "feet"
		Type.RING:     return "ring"
		Type.NECKLACE: return "necklace"
	return ""

func is_equippable() -> bool:
	return get_equip_slot_name() != ""

# ── Serialization (for save/load) ──────────────────────────────────────────
# Items are RefCounted with no native JSON support, so persist them through
# plain Dictionaries. Round-trips every gameplay-relevant field including
# the recently-added wand_charges, wand_max_charges, and quantity.
func to_dict() -> Dictionary:
	return {
		"type":              int(type),
		"display_name":      display_name,
		"description":       description,
		"color":             [color.r, color.g, color.b, color.a],
		"icon_char":         icon_char,
		"sell_value":        sell_value,
		"rarity":            rarity,
		"stat_bonuses":      stat_bonuses.duplicate(),
		"set_tag":           set_tag,
		"wand_shoot_type":   wand_shoot_type,
		"wand_damage":       wand_damage,
		"wand_mana_cost":    wand_mana_cost,
		"wand_fire_rate":    wand_fire_rate,
		"wand_proj_speed":   wand_proj_speed,
		"wand_pierce":       wand_pierce,
		"wand_ricochet":     wand_ricochet,
		"wand_status_stacks": wand_status_stacks,
		"wand_flaws":        (wand_flaws as Array).duplicate(),
		"wand_max_charges":  wand_max_charges,
		"wand_charges":      wand_charges,
		"wand_forge_count":  wand_forge_count,
		"tier":              tier,
		"min_rarity":        min_rarity,
		"quantity":          quantity,
	}

static func from_dict(d: Dictionary) -> Item:
	if d == null or d.is_empty():
		return null
	var it := Item.new()
	it.type              = int(d.get("type", 0)) as Type
	it.display_name      = String(d.get("display_name", ""))
	it.description       = String(d.get("description", ""))
	var col: Array       = d.get("color", [1.0, 1.0, 1.0, 1.0])
	it.color             = Color(float(col[0]), float(col[1]), float(col[2]), float(col[3]))
	it.icon_char         = String(d.get("icon_char", "?"))
	it.sell_value        = int(d.get("sell_value", 5))
	it.rarity            = int(d.get("rarity", RARITY_COMMON))
	it.stat_bonuses      = (d.get("stat_bonuses", {}) as Dictionary).duplicate()
	it.set_tag           = String(d.get("set_tag", ""))
	it.wand_shoot_type   = String(d.get("wand_shoot_type", "regular"))
	it.wand_damage       = int(d.get("wand_damage", 1))
	it.wand_mana_cost    = float(d.get("wand_mana_cost", 5.0))
	it.wand_fire_rate    = float(d.get("wand_fire_rate", 0.20))
	it.wand_proj_speed   = float(d.get("wand_proj_speed", 600.0))
	it.wand_pierce       = int(d.get("wand_pierce", 0))
	it.wand_ricochet     = int(d.get("wand_ricochet", 0))
	it.wand_status_stacks = int(d.get("wand_status_stacks", 1))
	it.wand_flaws        = (d.get("wand_flaws", []) as Array).duplicate() if WAND_FLAWS_ENABLED else []
	it.wand_max_charges  = int(d.get("wand_max_charges", 0))
	it.wand_charges      = int(d.get("wand_charges", 0))
	it.wand_forge_count  = int(d.get("wand_forge_count", 0))
	it.tier              = int(d.get("tier", 0))
	it.min_rarity        = int(d.get("min_rarity", RARITY_COMMON))
	it.quantity          = int(d.get("quantity", 1))
	return it
