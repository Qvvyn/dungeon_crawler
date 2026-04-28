class_name Item
extends RefCounted

enum Type { WAND, HAT, ROBES, FEET, RING, NECKLACE, SHIELD, TOME, VALUABLE, POTION }

const RARITY_COMMON    := 0
const RARITY_RARE      := 1
const RARITY_LEGENDARY := 2

var type: Type
var display_name: String
var description: String
var color: Color
var icon_char: String = "?"
var sell_value: int = 5
var rarity: int = RARITY_COMMON
# Flat bonuses applied while equipped. Keys: "speed", "max_health", "fire_rate_reduction", "DEF", "projectile_count"
var stat_bonuses: Dictionary = {}
var set_tag: String = ""   # "arcane" | "iron" | "swift" | ""
# Stack count for stackable items (potions). Always 1 for non-stackable types.
# InventoryManager.add_item folds an incoming stackable into an existing
# stack of the same kind instead of consuming a fresh grid slot.
var quantity: int = 1

# Items that fold into a single inventory slot when picked up. Currently
# limited to potions — gear / wands / valuables stay distinct since they
# carry per-instance state (charges, rolled stats, etc.).
func is_stackable() -> bool:
	return type == Type.POTION

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

func is_limited_use() -> bool:
	return wand_max_charges > 0

## Returns the equipment slot name this item occupies, or "" if not equippable.
## Offhand items (SHIELD / TOME) are intentionally unequippable for now —
## the offhand slot and its projectile-count tomes are disabled.
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
	it.wand_flaws        = (d.get("wand_flaws", []) as Array).duplicate()
	it.wand_max_charges  = int(d.get("wand_max_charges", 0))
	it.wand_charges      = int(d.get("wand_charges", 0))
	it.quantity          = int(d.get("quantity", 1))
	return it
