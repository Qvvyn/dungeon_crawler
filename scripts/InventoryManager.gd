extends Node

const GRID_SIZE := 25
const EQUIP_SLOTS := ["wand", "hat", "robes", "feet", "ring", "necklace", "offhand"]

signal inventory_changed

# 25-slot bag. null = empty.
var grid: Array = []
# Equipment slots. null = nothing equipped.
var equipped: Dictionary = {}

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
	var displaced: Item = grid[index]
	grid[index] = drag_item
	drag_item = null
	if displaced != null:
		# Put displaced item back at the source
		_return_to_source(displaced, drag_source)
	drag_source = ""
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
	return _add_to_first_free(item)

func _add_to_first_free(item: Item) -> bool:
	for i in GRID_SIZE:
		if grid[i] == null:
			grid[i] = item
			inventory_changed.emit()
			return true
	return false   # bag full

func get_stat(stat_name: String) -> float:
	var total := 0.0
	for slot in EQUIP_SLOTS:
		var item: Item = equipped.get(slot)
		if item:
			total += item.stat_bonuses.get(stat_name, 0.0)
	return total

func use_potion_at(grid_index: int) -> bool:
	var item: Item = grid[grid_index]
	if item == null or item.type != Item.Type.POTION:
		return false
	var player := _get_player()
	if player == null or not player.has_method("heal"):
		return false
	player.heal(3)
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
