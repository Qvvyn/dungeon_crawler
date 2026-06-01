extends Node2D

# Monster-closet ambush. Stepping into the room seals its doorways (walls rise via
# remote_only Doors) and springs a wave of aggro'd enemies. Clearing the wave —
# or a safety timeout — reopens the seals and drops a reward. First use of the
# trigger primitives (see DOOM_DESIGN.md). Self-clearing: never a softlock.
#
# Set before add_child: room (Rect2i), seal_tiles (Array[Vector2i]), wave_count (int).

const TILE: int = 32
const DOOR_SCENE := preload("res://scenes/Door.tscn")
const LOOT_BAG_SCENE := preload("res://scenes/LootBag.tscn")
const SAFETY_TIMEOUT := 30.0

var room: Rect2i = Rect2i()
var seal_tiles: Array[Vector2i] = []
var wave_count: int = 4

enum State { IDLE, ARMING, ACTIVE, CLEARED }
var _state: State = State.IDLE
var _seals: Array = []     # Door nodes
var _wave: Array = []      # enemy nodes
var _timeout: float = 0.0
var _check_t: float = 0.0
var _tripwire: Area2D = null

func _ready() -> void:
	var scene := get_tree().current_scene
	# Seal doors at each doorway tile — spawned OPEN (passable) into the world.
	for t: Vector2i in seal_tiles:
		var d := DOOR_SCENE.instantiate()
		var ct: Array[Vector2i] = [t]
		d.set("cover_tiles", ct)
		d.set("corridor_axis", 0)
		d.set("remote_only", true)
		d.set("start_open", true)
		d.position = Vector2(float(t.x) * TILE + TILE * 0.5, float(t.y) * TILE + TILE * 0.5)
		scene.add_child(d)
		_seals.append(d)

	# Tripwire over the room interior (local — this node sits at the room center).
	_tripwire = Area2D.new()
	_tripwire.collision_layer = 0
	_tripwire.collision_mask = 1
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(float(maxi(1, room.size.x - 1)) * TILE, float(maxi(1, room.size.y - 1)) * TILE)
	cs.shape = rect
	_tripwire.add_child(cs)
	add_child(_tripwire)
	_tripwire.body_entered.connect(_on_tripwire)

func _on_tripwire(body: Node2D) -> void:
	if _state != State.IDLE or not body.is_in_group("player"):
		return
	# body_entered fires during the physics flush — spawning enemies (which mutate
	# collision/monitoring state) is illegal here. Block re-entry by leaving IDLE
	# now, then arm on the next idle frame via call_deferred.
	_state = State.ARMING
	call_deferred("_arm")

func _arm() -> void:
	_timeout = SAFETY_TIMEOUT
	for d in _seals:
		if is_instance_valid(d):
			d.close()
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("spawn_ambush_wave"):
		_wave = scene.spawn_ambush_wave(room, wave_count)
	FloatingText.spawn_str(global_position, "AMBUSH!", Color(1.0, 0.3, 0.2), scene)
	if SoundManager:
		SoundManager.play("explosion", 0.7)
	# Only now begin the clear-watch — guarantees _wave is populated first.
	_state = State.ACTIVE

func _process(delta: float) -> void:
	if _state != State.ACTIVE:
		return
	_timeout -= delta
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 0.3
		var alive: Array = []
		for e in _wave:
			if is_instance_valid(e) and not (e as Node).is_queued_for_deletion():
				alive.append(e)
		_wave = alive
	if _wave.is_empty() or _timeout <= 0.0:
		_clear()

func _clear() -> void:
	_state = State.CLEARED
	for d in _seals:
		if is_instance_valid(d):
			d.open()
	var scene := get_tree().current_scene
	if scene != null:
		var bag := LOOT_BAG_SCENE.instantiate()
		bag.global_position = global_position
		scene.add_child(bag)
	if is_instance_valid(_tripwire):
		_tripwire.queue_free()

func _exit_tree() -> void:
	# Seals are parented to the world; free them with the controller on floor change.
	for d in _seals:
		if is_instance_valid(d):
			d.queue_free()
