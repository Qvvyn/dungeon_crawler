extends Node

const GRID_SIZE := 25
# First WAND_SLOTS cells of the grid (indices 0..WAND_SLOTS-1) are
# wand-only. Non-wand items can't be placed there; wands can't be placed
# anywhere else. add_item enforces this on pickup; InventoryUI's drag /
# drop validation enforces it on manual moves.
const WAND_SLOTS := 5
const EQUIP_SLOTS := ["wand", "hat", "robes", "feet", "ring", "necklace"]
# Dedicated health-potion bag — separate from the main grid so the player
# always has guaranteed quick-access pots that don't compete with loot for
# slots. Loot bags fill this on auto-pickup; overflow stays in the world.
const MAX_POTIONS := 10

signal inventory_changed

# 25-slot bag. null = empty.
var grid: Array = []
# Equipment slots. null = nothing equipped. equipped["wand"] is kept
# in sync with grid[_active_wand_slot] so old call sites that read
# `equipped["wand"]` still see the active wand without changes.
var equipped: Dictionary = {}
# Which of the 5 wand slots is currently the active equipped wand. Mouse
# wheel cycles this through non-empty wand slots; equipped["wand"] is
# re-pointed every time it changes.
var _active_wand_slot: int = 0
# Dedicated potion slot — single Item with quantity up to MAX_POTIONS,
# or null when empty. Use add_potions_to_slot / use_potion_from_slot
# rather than touching directly so the cap and signal stay in sync.
var potion_slot: Item = null

# Shared drag state — read by InventoryUI and LootPopup.
var drag_item: Item = null
var drag_source: String = ""   # "grid_N", "equip_SLOT", "loot_N"

func _ready() -> void:
	_init_state()

func _init_state() -> void:
	grid.resize(GRID_SIZE)
	for i in GRID_SIZE:
		grid[i] = null
	for slot in EQUIP_SLOTS:
		equipped[slot] = null
	potion_slot = null
	_active_wand_slot = 0

func reset() -> void:
	_init_state()
	inventory_changed.emit()

# ── Drag helpers ──────────────────────────────────────────────────────────────

func begin_drag(item: Item, source: String) -> void:
	drag_item = item
	drag_source = source

func cancel_drag() -> void:
	if drag_item == null:
		return
	_return_to_source(drag_item, drag_source)
	drag_item = null
	drag_source = ""
	inventory_changed.emit()

func drop_to_grid(index: int) -> void:
	if drag_item == null:
		return
	# Wand-slot rules: wands belong in 0..WAND_SLOTS-1 only; non-wands
	# can't enter those slots. Reject the drop and cancel the drag back
	# to its source rather than swallowing the item.
	var is_wand: bool = drag_item.type == Item.Type.WAND
	if is_wand and not is_wand_slot(index):
		cancel_drag()
		return
	if not is_wand and is_wand_slot(index):
		cancel_drag()
		return
	var displaced: Item = grid[index]
	grid[index] = drag_item
	drag_item = null
	if displaced != null:
		# Put displaced item back at the source
		_return_to_source(displaced, drag_source)
	drag_source = ""
	if is_wand or is_wand_slot(index):
		_sync_active_wand()
	inventory_changed.emit()

func drop_to_equip(slot_name: String) -> void:
	if drag_item == null:
		return
	if drag_item.get_equip_slot_name() != slot_name:
		return          # wrong type — do nothing, keep dragging
	var displaced: Item = equipped[slot_name]
	equipped[slot_name] = drag_item
	drag_item = null
	if displaced != null:
		_return_to_source(displaced, drag_source)
	drag_source = ""
	inventory_changed.emit()

func _return_to_source(item: Item, source: String) -> void:
	if source.begins_with("grid_"):
		var idx := source.substr(5).to_int()
		# If the slot is now occupied (by the item we just dragged), find next free
		if grid[idx] == null:
			grid[idx] = item
		else:
			_add_to_first_free(item)
	elif source.begins_with("equip_"):
		var slot := source.substr(6)
		if equipped[slot] == null:
			equipped[slot] = item
		else:
			_add_to_first_free(item)
	else:
		_add_to_first_free(item)

# ── Public helpers ────────────────────────────────────────────────────────────

func add_item(item: Item) -> bool:
	# Stackable items (potions, valuables) fold into existing stacks of
	# the same kind, capped at Item.STACK_CAP per slot. Anything past the
	# cap overflows into the next stack with room (and finally into fresh
	# empty slots). Identity check is name+type so health potions stack
	# with each other but not with anything else even if they shared a
	# type tag.
	if item.is_stackable():
		var remaining: int = item.quantity
		for i in GRID_SIZE:
			if remaining <= 0:
				break
			var existing: Item = grid[i]
			if existing == null \
					or not existing.is_stackable() \
					or existing.type != item.type \
					or existing.display_name != item.display_name:
				continue
			var room: int = Item.STACK_CAP - existing.quantity
			if room <= 0:
				continue
			var moved: int = mini(room, remaining)
			existing.quantity += moved
			remaining -= moved
		# Whatever didn't fit into existing stacks lands in fresh slots,
		# again capped at STACK_CAP per slot. Reuse the incoming item for
		# the first overflow slot to preserve identity (name/color/icon)
		# without re-cloning the template.
		if remaining > 0:
			item.quantity = mini(Item.STACK_CAP, remaining)
			remaining -= item.quantity
			if not _add_to_first_free(item):
				return false
			while remaining > 0:
				var overflow := Item.from_dict(item.to_dict())
				overflow.quantity = mini(Item.STACK_CAP, remaining)
				remaining -= overflow.quantity
				if not _add_to_first_free(overflow):
					return false
		else:
			inventory_changed.emit()
		return true
	return _add_to_first_free(item)

func _add_to_first_free(item: Item) -> bool:
	# Wand-vs-non-wand slot routing:
	#   * Wands → only slots 0..WAND_SLOTS-1, capped at WAND_SLOTS total.
	#     If all five wand slots are full, the wand is rejected (the
	#     player has to discard or equip-swap to make room).
	#   * Non-wands → only slots WAND_SLOTS..GRID_SIZE-1. Wand slots
	#     stay reserved even when bag is otherwise full.
	if item.type == Item.Type.WAND:
		for i in WAND_SLOTS:
			if grid[i] == null:
				grid[i] = item
				_sync_active_wand()
				inventory_changed.emit()
				return true
		return false   # all 5 wand slots taken
	for i in range(WAND_SLOTS, GRID_SIZE):
		if grid[i] == null:
			grid[i] = item
			inventory_changed.emit()
			return true
	return false   # non-wand bag full

# Returns true if `idx` is one of the wand-only slots.
func is_wand_slot(idx: int) -> bool:
	return idx >= 0 and idx < WAND_SLOTS

# Returns the highest-rarity-not-quite-the-right-name version of which
# wand slot is currently equipped. Mouse-wheel scrolling rotates this.
func active_wand_slot() -> int:
	return _active_wand_slot

# Number of wands currently held in the wand-slot row. Capped at WAND_SLOTS.
func wand_count() -> int:
	var n: int = 0
	for i in WAND_SLOTS:
		if grid[i] != null:
			n += 1
	return n

# Re-points equipped["wand"] at grid[_active_wand_slot]. If that slot is
# empty, scan forward for the next non-empty wand slot and use that
# instead (so cycling doesn't get stuck on an empty cell). Falls back to
# null if every wand slot is empty.
func _sync_active_wand() -> void:
	if grid[_active_wand_slot] == null:
		for offset in WAND_SLOTS:
			var idx: int = (_active_wand_slot + offset) % WAND_SLOTS
			if grid[idx] != null:
				_active_wand_slot = idx
				break
	equipped["wand"] = grid[_active_wand_slot] as Item

# Plops `wand` into the active wand slot, overwriting whatever was there.
# Used by debug commands and the autoplay's auto-equip path (when the
# bot picks up a strict upgrade from a loot bag). The displaced wand is
# discarded — callers that need to preserve it must save the reference
# before calling this. Pass null to clear the active slot.
func set_active_wand(wand: Item) -> void:
	if wand != null and wand.type != Item.Type.WAND:
		return
	grid[_active_wand_slot] = wand
	_sync_active_wand()
	inventory_changed.emit()

# Rotates the active wand slot through non-empty wand slots. dir = +1
# cycles forward (e.g., wheel-down), -1 backward. No-op when zero or
# one wands are held. Re-syncs equipped["wand"] and emits the change.
func cycle_active_wand(dir: int) -> void:
	if dir == 0:
		return
	var held: int = wand_count()
	if held <= 1:
		return
	var idx: int = _active_wand_slot
	for _i in WAND_SLOTS:
		idx = posmod(idx + dir, WAND_SLOTS)
		if grid[idx] != null:
			_active_wand_slot = idx
			break
	_sync_active_wand()
	inventory_changed.emit()

# One-shot bag tidy. Stack-merges potions of the same name, then groups
# items by type (potions → wands → hats/robes/feet → rings/necklaces →
# tomes/shields → valuables → anything else) and sorts each group by
# rarity (legendary > rare > common) then by display name. Empty slots
# collapse to the end so the bag reads top-to-bottom in priority order.
func sort_grid() -> void:
	# 1. Snapshot non-null items.
	var items: Array = []
	for i in GRID_SIZE:
		if grid[i] != null:
			items.append(grid[i])
	# 2. Stack-merge stackables (potions, valuables). Each merge respects
	#    Item.STACK_CAP — once a stack hits the cap, the next item of the
	#    same kind starts a new stack. Without the cap check, sort would
	#    collapse all coins/gems into a single 999-deep slot regardless
	#    of the bag-side cap users see when picking items up.
	var stack_chains: Dictionary = {}   # key → Array[Item] of open-or-full stacks
	var keep: Array = []
	for it in items:
		var item: Item = it as Item
		if item.is_stackable():
			var key: String = "%d|%s" % [int(item.type), item.display_name]
			var chain: Array = stack_chains.get(key, [])
			# Try to fold this item's quantity into any open stacks first.
			var remaining: int = item.quantity
			for primary in chain:
				if remaining <= 0:
					break
				var room: int = Item.STACK_CAP - (primary as Item).quantity
				if room <= 0:
					continue
				var moved: int = mini(room, remaining)
				(primary as Item).quantity += moved
				remaining -= moved
			if remaining <= 0:
				continue   # fully merged, drop this duplicate
			# Whatever's left starts new stacks at the cap.
			item.quantity = mini(Item.STACK_CAP, remaining)
			remaining -= item.quantity
			chain.append(item)
			stack_chains[key] = chain
			keep.append(item)
			while remaining > 0:
				var overflow := Item.from_dict(item.to_dict())
				overflow.quantity = mini(Item.STACK_CAP, remaining)
				remaining -= overflow.quantity
				chain.append(overflow)
				keep.append(overflow)
			continue
		keep.append(item)
	# 3. Split wands from non-wands so the wand-only row stays valid.
	#    Within each subgroup, sort by rarity desc then name.
	var wands: Array = []
	var others: Array = []
	for it in keep:
		if (it as Item).type == Item.Type.WAND:
			wands.append(it)
		else:
			others.append(it)
	var rarity_then_name := func(a: Item, b: Item) -> bool:
		if a.rarity != b.rarity:
			return a.rarity > b.rarity
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0
	wands.sort_custom(rarity_then_name)
	others.sort_custom(func(a: Item, b: Item) -> bool:
		var ga: int = _sort_group(a)
		var gb: int = _sort_group(b)
		if ga != gb:
			return ga < gb
		return rarity_then_name.call(a, b))
	# 4. Refill: wands occupy slots 0..WAND_SLOTS-1 (one per cell, no
	#    overflow possible since add_item caps at WAND_SLOTS), others
	#    fill from WAND_SLOTS onward. Empty cells become null.
	for i in GRID_SIZE:
		grid[i] = null
	for i in mini(wands.size(), WAND_SLOTS):
		grid[i] = wands[i]
	for i in others.size():
		var dst: int = WAND_SLOTS + i
		if dst >= GRID_SIZE:
			break
		grid[dst] = others[i]
	_sync_active_wand()
	inventory_changed.emit()

# Group ordering used by sort_grid. Lower number = higher in the bag.
# Potions on top because the player needs them quickly; wands next so
# the equip-from-bag flow finds them; gear by slot; valuables sink to
# the bottom since they only matter at the SellChest.
func _sort_group(it: Item) -> int:
	match it.type:
		Item.Type.POTION:   return 0
		Item.Type.WAND:     return 1
		Item.Type.HAT:      return 2
		Item.Type.ROBES:    return 3
		Item.Type.FEET:     return 4
		Item.Type.RING:     return 5
		Item.Type.NECKLACE: return 6
		Item.Type.SHIELD:   return 7
		Item.Type.TOME:     return 8
		Item.Type.VALUABLE: return 9
	return 10

func get_stat(stat_name: String) -> float:
	var total := 0.0
	# Tier bonus skips these — they're not linear stat values:
	#   * fire_rate_reduction: stored in seconds (0.04 = 40 ms). Adding
	#     tier directly would give multi-second reductions and break
	#     attack-speed math entirely.
	#   * projectile_count: discrete integer, +1 already significant.
	#     Tier-scaling would give +50 projectiles at deep tiers.
	#   * syn_*: synergy flags, treated as booleans.
	var skip_tier_bonus: bool = stat_name == "fire_rate_reduction" \
		or stat_name == "projectile_count" \
		or stat_name.begins_with("syn_")
	for slot in EQUIP_SLOTS:
		var item: Item = equipped.get(slot)
		if item == null:
			continue
		var base: float = float(item.stat_bonuses.get(stat_name, 0.0))
		total += base
		# Tier-based stat bonus — every procedural piece adds extra to
		# the stats it already carries based on its tier and rarity:
		#   common    × 0.40
		#   uncommon  × 0.60
		#   rare      × 0.80
		#   legendary × 1.00
		# So a T10 common +5 VIT helm contributes 5 + (10 × 0.4) = 9 VIT,
		# while a T10 legendary +10 VIT necklace gives 10 + 10 = 20 VIT.
		# Fixed items (tier = 0) and stats the item doesn't actually
		# carry (base == 0) skip the bonus — only "the relevant stats"
		# on each piece get the boost.
		if not skip_tier_bonus and base != 0.0 and item.tier > 0:
			total += float(item.tier) * _tier_stat_mult(item.rarity)
	return total

# Per-rarity multiplier for the tier-based stat bonus (see get_stat).
# Higher rarity = larger bonus per tier point, so a legendary at the
# same tier as a common feels meaningfully stronger.
func _tier_stat_mult(rarity: int) -> float:
	match rarity:
		Item.RARITY_LEGENDARY: return 1.00
		Item.RARITY_RARE:      return 0.80
		Item.RARITY_UNCOMMON:  return 0.60
		Item.RARITY_COMMON:    return 0.40
	return 0.0

# Potion-slot helpers — expose the dedicated bag's count and remaining
# room so LootBag's auto-pickup can decide whether to grab anything.
func potion_count() -> int:
	return 0 if potion_slot == null else potion_slot.quantity

func potion_slot_room() -> int:
	return MAX_POTIONS - potion_count()

# Fills the dedicated potion slot from `template` up to MAX_POTIONS.
# Returns the actual count moved so the caller (LootBag) can leave
# overflow in the world. `template` only supplies the visual identity
# (display_name, color, icon, sell_value); quantity comes from `requested`.
func add_potions_to_slot(template: Item, requested: int) -> int:
	if template == null or template.type != Item.Type.POTION:
		return 0
	if requested <= 0:
		return 0
	var room: int = potion_slot_room()
	if room <= 0:
		return 0
	var added: int = mini(requested, room)
	if potion_slot == null:
		# Clone template so the slot's identity isn't shared with the
		# loot bag's reference.
		potion_slot = Item.from_dict(template.to_dict())
		potion_slot.quantity = added
	else:
		potion_slot.quantity += added
	inventory_changed.emit()
	return added

# Drinks one potion from the dedicated slot. Returns false if the slot
# is empty so the caller can fall back to the legacy grid-potion path.
func use_potion_from_slot() -> bool:
	if potion_slot == null or potion_slot.quantity <= 0:
		return false
	var player := _get_player()
	if player == null or not player.has_method("heal"):
		return false
	var max_hp: int = 10
	if player.has_method("_max_hp"):
		max_hp = int(player.call("_max_hp"))
	var heal_amount: int = maxi(1, int(round(float(max_hp) * 0.30)))
	player.heal(heal_amount)
	potion_slot.quantity -= 1
	if potion_slot.quantity <= 0:
		potion_slot = null
	inventory_changed.emit()
	return true

func use_potion_at(grid_index: int) -> bool:
	var item: Item = grid[grid_index]
	if item == null or item.type != Item.Type.POTION:
		return false
	var player := _get_player()
	if player == null or not player.has_method("heal"):
		return false
	# Health potions restore 30% of max HP — scales with VIT investment so
	# late-game potions stay relevant instead of being a flat trickle heal.
	var max_hp: int = 10
	if player.has_method("_max_hp"):
		max_hp = int(player.call("_max_hp"))
	var heal_amount: int = maxi(1, int(round(float(max_hp) * 0.30)))
	player.heal(heal_amount)
	# Decrement stack — only clear the slot when the last potion is used.
	item.quantity -= 1
	if item.quantity <= 0:
		grid[grid_index] = null
	inventory_changed.emit()
	return true

func _get_player() -> Node:
	# Autoloads don't have get_tree() easily; use the scene tree via a workaround.
	# We store the player reference when InventoryUI initialises.
	return _player_ref

var _player_ref: Node = null

func register_player(p: Node) -> void:
	_player_ref = p
