extends EnemyBase

# Reflector — slow-tracking enemy with a front-facing reflector arc.
# Player projectiles that enter the arc reverse direction and become
# enemy projectiles, which the player then has to dodge. Forces beam,
# nova, melee, or flanking play. The reflector itself is fragile but
# always faces the player.

const F0 := " /=\\ \n[(O)]\n \\=/ "
const F1 := " /=\\ \n[(o)]\n \\=/ "

const MOVE_SPEED        := 35.0
const REFLECT_RADIUS    := 32.0
const REFLECT_ARC_DEG   := 110.0   # arc width in degrees, centered on facing dir

var _facing_dir: Vector2 = Vector2.RIGHT
var _reflect_area: Area2D = null
var _anim_t: float       = 0.0
var _anim_f: int         = 0

func _on_ready_extra() -> void:
	max_health = 16   # doubled from 8
	health = max_health
	_sight_range = 520.0
	if _lbl:
		_lbl.text = F0
	# Reflector area attached at the body's center; we filter projectiles
	# to "in arc" inside the area_entered handler so it acts as a cone
	# instead of a full circle.
	_reflect_area = Area2D.new()
	_reflect_area.name = "ReflectArc"
	_reflect_area.collision_layer = 0
	_reflect_area.collision_mask = 0  # we filter by group, not layer
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = REFLECT_RADIUS
	cs.shape = shape
	_reflect_area.add_child(cs)
	add_child(_reflect_area)
	_reflect_area.area_entered.connect(_on_reflect_candidate)
	# A faint visual arc so the player can see what's reflective.
	_setup_arc_visual()

func _setup_arc_visual() -> void:
	var ring := Line2D.new()
	ring.width = 2.0
	ring.default_color = Color(0.35, 0.95, 0.85, 0.65)
	# Half-arc from -arc/2 to +arc/2 around the local +X axis (facing dir).
	var half := deg_to_rad(REFLECT_ARC_DEG * 0.5)
	var segs := 18
	for i in segs + 1:
		var a := -half + (half * 2.0) * float(i) / float(segs)
		ring.add_point(Vector2(cos(a), sin(a)) * REFLECT_RADIUS)
	ring.name = "ArcLine"
	add_child(ring)

func _enemy_tick(delta: float) -> void:
	if _frozen or _stun_timer > 0.0:
		velocity = Vector2.ZERO
		return
	if not _has_aggro:
		velocity = Vector2.ZERO
		return
	# Always face the player, but move slowly. The reflector wants to
	# stay at range — projectiles do its work. Movement is just enough
	# to avoid sitting in a single spot.
	if is_instance_valid(_player):
		_facing_dir = (_player.global_position - global_position).normalized()
		# Strafe slowly so the player can't trivially flank.
		var lateral := _facing_dir.rotated(PI * 0.5) * (1.0 if (Time.get_ticks_msec() / 2000) % 2 == 0 else -1.0)
		velocity = lateral * MOVE_SPEED * _speed_multiplier
		# Rotate the visual arc to face the player.
		rotation = _facing_dir.angle()

func _on_reflect_candidate(area: Area2D) -> void:
	# Only reflect player projectiles. Enemy ones we leave alone.
	if not area.is_in_group("projectile"):
		return
	var src: Variant = area.get("source")
	if String(src) != "player":
		return
	# Cone filter — only projectiles inside the front arc bounce. A
	# projectile coming at the back hits the reflector body normally.
	var to_proj: Vector2 = area.global_position - global_position
	if to_proj.length() < 0.001:
		return
	var ang := acos(clampf(to_proj.normalized().dot(_facing_dir), -1.0, 1.0))
	if ang > deg_to_rad(REFLECT_ARC_DEG * 0.5):
		return
	# Bounce: invert direction, retag as enemy. Cap rotation so existing
	# projectile flight code doesn't break.
	if "direction" in area:
		var dir: Vector2 = area.get("direction")
		area.set("direction", -dir)
		if "rotation" in area:
			area.rotation = (-dir).angle()
	area.set("source", "enemy")
	# Visual flash on bounce.
	FloatingText.spawn_str(global_position, "REFLECT!",
		Color(0.30, 1.0, 0.85), get_tree().current_scene)

func _enemy_anim_update(delta: float) -> void:
	_anim_t += delta
	if _anim_t >= 0.40:
		_anim_t = 0.0
		_anim_f = 1 - _anim_f
		if _lbl:
			_lbl.text = F0 if _anim_f == 0 else F1
