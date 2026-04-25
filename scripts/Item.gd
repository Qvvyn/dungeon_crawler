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

# Wand-specific fields (only meaningful when type == WAND)
var wand_shoot_type: String  = "regular"  # regular/pierce/ricochet/chain/freeze/fire/beam
var wand_damage: int         = 1
var wand_mana_cost: float    = 5.0        # mana per shot (beam: per second)
var wand_fire_rate: float    = 0.20       # seconds between shots
var wand_proj_speed: float   = 600.0
var wand_pierce: int         = 0          # enemies passed through
var wand_ricochet: int       = 0          # wall bounces
var wand_status_stacks: int  = 1          # stacks applied per hit (freeze/fire)
var wand_flaws: Array        = []         # backwards/drift/clunky/mana_guzzle/slow_shots/erratic

## Returns the equipment slot name this item occupies, or "" if not equippable.
func get_equip_slot_name() -> String:
	match type:
		Type.WAND:     return "wand"
		Type.HAT:      return "hat"
		Type.ROBES:    return "robes"
		Type.FEET:     return "feet"
		Type.RING:     return "ring"
		Type.NECKLACE: return "necklace"
		Type.SHIELD:   return "offhand"
		Type.TOME:     return "offhand"
	return ""

func is_equippable() -> bool:
	return get_equip_slot_name() != ""
