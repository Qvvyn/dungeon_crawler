extends Area2D

const PROJ_SCENE := preload("res://scenes/Projectile.tscn")

@export var speed: float    = 600.0
@export var lifetime: float = 3.0

# Set by spawner immediately after instantiation
var source: String     = "player"
var direction: Vector2 = Vector2.RIGHT

# Wand stats set by Player._fire()
var damage: int             = 1
var pierce_remaining: int   = 0    # enemies to pass through
var ricochet_remaining: int = 0    # wall bounces remaining
var chain_remaining: int    = 0    # enemy chain-jumps remaining
var apply_freeze: bool      = false
var apply_burn: bool        = false
var apply_shock: bool       = false
var drift_speed: float      = 0.0  # sideways drift px/s (relative to direction)

var _hit_entities: Array = []   # instance IDs already struck (pierce/chain dedup)
var _bounce_cd: float    = 0.0  # brief cooldown to prevent double-bounce

func _ready() -> void:
	rotation = direction.angle()
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	get_tree().create_timer(lifetime).timeout.connect(
		func() -> void:
			if is_instance_valid(self):
				queue_free()
	)

func _physics_process(delta: float) -> void:
	if _bounce_cd > 0.0:
		_bounce_cd -= delta

	if drift_speed != 0.0:
		var perp := direction.rotated(PI * 0.5)
		direction = (direction + perp * drift_speed * delta).normalized()
		rotation = direction.angle()

	var move := direction * speed * delta

	# CCD wall check — raycasts ahead to prevent tunneling at high speeds
	var space := get_world_2d().direct_space_state
	var ray := PhysicsRayQueryParameters2D.create(
		global_position,
		global_position + move + direction * 6.0   # small lookahead
	)
	ray.exclude = [get_rid()]
	var hit := space.intersect_ray(ray)
	if not hit.is_empty() and hit.get("collider") is StaticBody2D:
		if ricochet_remaining > 0 and _bounce_cd <= 0.0:
			ricochet_remaining -= 1
			_bounce_cd = 0.12
			var hit_pos: Vector2 = hit.get("position") as Vector2
			var normal: Vector2  = hit.get("normal")  as Vector2
			global_position = hit_pos - direction * 2.0
			direction = direction.bounce(normal)
			rotation = direction.angle()
		else:
			queue_free()
		return

	global_position += move

func _on_body_entered(body: Node2D) -> void:
	# Source-group self-collision guard
	if source == "player" and body.is_in_group("player"):
		return
	if source == "enemy" and body.is_in_group("enemy"):
		return

	# Wall hit handled by CCD raycast above; fallback for slow projectiles
	if body is StaticBody2D:
		if ricochet_remaining > 0 and _bounce_cd <= 0.0:
			ricochet_remaining -= 1
			_bounce_cd = 0.12
			if abs(direction.x) >= abs(direction.y):
				direction.x = -direction.x
			else:
				direction.y = -direction.y
			rotation = direction.angle()
		else:
			queue_free()
		return

	# Player projectile hits enemy
	if source == "player" and body.is_in_group("enemy"):
		var eid := body.get_instance_id()
		if eid in _hit_entities:
			return
		_hit_entities.append(eid)
		if body.has_method("take_damage"):
			body.take_damage(damage)
			GameState.damage_dealt += damage
		if apply_freeze and body.has_method("apply_status"):
			body.apply_status("freeze_hit", 0.0)
		if apply_burn and body.has_method("apply_status"):
			body.apply_status("burn_hit", 0.0)
		if apply_shock and body.has_method("apply_status"):
			body.apply_status("shock_hit", 0.0)
		if chain_remaining > 0:
			_do_chain()
		if pierce_remaining > 0:
			pierce_remaining -= 1
			return   # keep flying
		queue_free()
		return

	# Enemy projectile hits player
	if source == "enemy" and body.is_in_group("player"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
		queue_free()
		return

	queue_free()

func _do_chain() -> void:
	var best: Node2D = null
	var best_dist := 160.0 * 160.0
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy):
			continue
		if enemy.is_in_group("player"):   # never chain-target the player
			continue
		if enemy.get_instance_id() in _hit_entities:
			continue
		var d := global_position.distance_squared_to(enemy.global_position)
		if d < best_dist:
			best_dist = d
			best = enemy
	if best == null:
		return
	var chain_proj: Node = PROJ_SCENE.instantiate()
	chain_proj.global_position = global_position
	chain_proj.direction       = (best.global_position - global_position).normalized()
	chain_proj.source          = source
	chain_proj.damage          = damage
	chain_proj.chain_remaining = chain_remaining - 1
	chain_proj.apply_freeze    = apply_freeze
	chain_proj.apply_burn      = apply_burn
	chain_proj.apply_shock     = apply_shock
	chain_proj._hit_entities   = _hit_entities.duplicate()
	get_tree().current_scene.add_child(chain_proj)

func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("projectile"):
		return
	if area.is_in_group("gold_pickup"):
		return
	if area.is_in_group("loot_bag"):
		return
	if area.is_in_group("trap"):
		return
	if area.is_in_group("portal"):
		return
	if area.is_in_group("shield"):
		return  # shield's own area_entered handles absorption
	queue_free()
