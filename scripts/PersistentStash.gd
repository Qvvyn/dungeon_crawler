extends Node

# Cross-run item bank. Lives at user://stash.json. The Village's Bank node
# reads/writes this; the dungeon-side InventoryManager wipes on death/run-
# end, while anything stashed here persists.
#
# Stored as serialized item dicts (Item has a `to_dict` / `from_dict`
# pair already used by save_run.json). Slot count is hard-capped so the
# stash UI doesn't have to handle infinite scroll.

const SAVE_PATH := "user://stash.json"
const MAX_SLOTS := 60
# Persistent currency — separate from per-run gold which is wiped on
# death / dungeon entry. The Village shop / inn / bank charge from this.
var bank_gold: int = 0
var slots: Array = []   # Array[Item|null], length == MAX_SLOTS

func _ready() -> void:
	for _i in MAX_SLOTS:
		slots.append(null)
	_load()

func deposit(item: Item) -> bool:
	if item == null:
		return false
	for i in slots.size():
		if slots[i] == null:
			slots[i] = item
			_save()
			return true
	return false   # full

func withdraw(idx: int) -> Item:
	if idx < 0 or idx >= slots.size():
		return null
	var it := slots[idx] as Item
	slots[idx] = null
	if it != null:
		_save()
	return it

func first_filled_index() -> int:
	for i in slots.size():
		if slots[i] != null:
			return i
	return -1

func used_count() -> int:
	var n := 0
	for s in slots:
		if s != null:
			n += 1
	return n

func add_gold(amount: int) -> void:
	bank_gold = maxi(0, bank_gold + amount)
	_save()

func spend_gold(amount: int) -> bool:
	if amount > bank_gold:
		return false
	bank_gold -= amount
	_save()
	return true

# ── Persistence ────────────────────────────────────────────────────────────

func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	var serialized: Array = []
	for s in slots:
		if s is Item:
			serialized.append(s.to_dict())
		else:
			serialized.append(null)
	f.store_string(JSON.stringify({
		"slots":     serialized,
		"bank_gold": bank_gold,
	}, "\t"))
	f.close()

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var raw: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (raw is Dictionary):
		return
	bank_gold = int(raw.get("bank_gold", 0))
	var serialized: Array = raw.get("slots", [])
	for i in mini(serialized.size(), MAX_SLOTS):
		var entry: Variant = serialized[i]
		if entry is Dictionary:
			slots[i] = Item.from_dict(entry as Dictionary)
		else:
			slots[i] = null
