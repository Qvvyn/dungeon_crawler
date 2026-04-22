extends Area2D

const PROJ_SCENE := preload("res://scenes/Projectile.tscn")

@export var speed: float    = 600.0
@export var lifetime: float = 3.0

# Set by spawner immediately after instantiation
var source: String     = "player"
var direction: Vector2 = Vector2.RIGHT
var shoot_type: String = "regular"

# Wand stats set by Player._fire()
var damage: int             = 1
var pierce_remaining: int   = 0    # enemies to pass through
var ricochet_remaining: int = 0    # wall bounces remaining
var chain_remaining: int    = 0    # enemy chain-jumps remaining
var apply_freeze: bool      = false
var apply_burn: bool        = false
var apply_shock: bool       = false
var drift_speed: float      = 0.0  # sideways drift px/s (relative to direction)

var _hit_entities: Array    = []   # instance IDs already struck (pierce/chain dedup)
var _bounce_cd: float       = 0.0  # brief cooldown to prevent double-bounce
var _trail_timer: float     = 0.0
var _base_direction: Vector2 = Vector2.ZERO
var _zigzag_t: float        = 0.0

func _ready() -> void:
	rotation = direction.angle()
	_base_direction = direction
	_apply_visual()
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	get_tree().create_timer(lifetime).timeout.connect(
		func() -> void:
			if is_instance_valid(self):
				queue_free()
	)

func _apply_visual() -> void:
	var lbl := get_node_or_null("AsciiChar")
	if lbl == null:
		return
	match shoot_type:
		"regular":
			lbl.text = "*"
			lbl.add_theme_color_override("font_color", Color(1.0, 0.72, 0.08))
		"pierce":
			lbl.text = "-"
			lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.12))
		"ricochet":
			lbl.text = "o"
			lbl.add_theme_color_override("font_color", Color(0.15, 1.0, 0.28))
		"chain":
			lbl.text = "+"
			lbl.add_theme_color_override("font_color", Color(0.18, 0.88, 1.0))
		"freeze":
			lbl.text = "*"
			lbl.add_theme_color_override("font_color", Color(0.55, 0.88, 1.0))
		"fire":
			lbl.text = "@"
			lbl.add_theme_color_override("font_color", Color(1.0, 0.28, 0.04))
		"shock":
			lbl.text = "~"
			lbl.add_theme_color_override("font_color", Color(1.0, 0.98, 0.06))
		"shotgun":
			lbl.text = "#"
			lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
		"homing":
			lbl.text = "o"
			lbl.add_theme_color_override("font_color", Color(0.6, 0.2, 1.0))
		"nova":
			lbl.text = "*"
			lbl.add_theme_color_override("font_color", Color(0.7, 0.0, 1.0))
		_:
			lbl.text = "."
			lbl.add_theme_color_override("font_color", Color(0.72, 0.72, 0.88))

func _physics_process(delta: float) -> void:
	if _bounce_cd > 0.0:
		_bounce_cd -= delta

	if shoot_type == "shock" and _base_direction != Vector2.ZERO:
		_zigzag_t += delta * 12.0
		direction = _base_direction.rotated(sin(_zigzag_t) * deg_to_rad(22.0))
		rotation = direction.angle()

	if shoot_type == "homing":
		var best: Node2D = null
		var best_dist := 400.0 * 400.0
		for e: Node in get_tree().get_nodes_in_group("enemy"):
			if not is_instance_valid(e):
				continue
			var d := global_position.distance_squared_to((e as Node2D).global_position)
			if d < best_dist:
				best_dist = d
				best = e as Node2D
		if best != null:
			var to_target := (best.global_position - global_position).normalized()
			direction = direction.lerp(to_target, 3.5 * delta).normalized()
			rotation = direction.angle()

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

	_trail_timer -= delta
	if _trail_timer <= 0.0:
		_trail_timer = 0.045
		_spawn_trail_marker()

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
		var hit_pos      := body.global_position
		var target_elite: bool = (body.get("is_elite") == true) if "is_elite" in body else false
		if body.has_method("take_damage"):
			body.take_damage(damage)
			GameState.damage_dealt += damage
		_spawn_impact_burst(hit_pos)
		var pnode: Node = get_tree().get_first_node_in_group("player")
		if body.is_queued_for_deletion():
			_spawn_death_pop(hit_pos)
			if pnode:
				if pnode.has_method("start_hit_stop"):
					pnode.start_hit_stop(70 if target_elite else 40)
		if apply_freeze and body.has_method("apply_status"):
			body.apply_status("freeze_hit", 0.0)
		if apply_burn and body.has_method("apply_status"):
			body.apply_status("burn_hit", 0.0)
		if apply_shock and body.has_method("apply_status"):
			body.apply_status("shock_hit", 0.0)
		if chain_remaining > 0:
			_do_chain()
		if ricochet_remaining > 0 and _bounce_cd <= 0.0:
			ricochet_remaining -= 1
			_bounce_cd = 0.14
			var bnormal := (global_position - body.global_position).normalized()
			if bnormal == Vector2.ZERO:
				bnormal = direction.rotated(PI)
			direction = direction.bounce(bnormal)
			rotation = direction.angle()
			return
		if shoot_type == "nova":
			_detonate_nova()
			queue_free()
			return
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
	chain_proj.shoot_type      = shoot_type
	chain_proj._hit_entities   = _hit_entities.duplicate()
	get_tree().current_scene.add_child(chain_proj)

	# Jagged lightning arc visual
	var arc := Line2D.new()
	arc.width = 2.0
	arc.default_color = Color(0.85, 0.95, 1.0, 0.9)
	var arc_steps := 6
	for i in arc_steps + 1:
		var t := float(i) / float(arc_steps)
		var pt := global_position.lerp(best.global_position, t)
		if i > 0 and i < arc_steps:
			var perp := (best.global_position - global_position).normalized().rotated(PI * 0.5)
			pt += perp * randf_range(-14.0, 14.0)
		arc.add_point(pt)
	get_tree().current_scene.add_child(arc)
	var arc_tw := arc.create_tween()
	arc_tw.tween_property(arc, "modulate:a", 0.0, 0.28)
	arc_tw.tween_callback(arc.queue_free)

func _detonate_nova() -> void:
	for i in 8:
		var angle := (TAU / 8.0) * float(i)
		var nova_proj: Node = PROJ_SCENE.instantiate()
		nova_proj.global_position = global_position
		nova_proj.set("direction", Vector2(cos(angle), sin(angle)))
		nova_proj.set("source", source)
		nova_proj.set("damage", damage)
		nova_proj.set("shoot_type", "regular")
		get_tree().current_scene.add_child(nova_proj)

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

# ── Visual helpers ────────────────────────────────────────────────────────────

func _get_proj_color() -> Color:
	match shoot_type:
		"regular":  return Color(1.0, 0.72, 0.08)
		"pierce":   return Color(0.95, 0.95, 0.12)
		"ricochet": return Color(0.15, 1.0, 0.28)
		"chain":    return Color(0.18, 0.88, 1.0)
		"freeze":   return Color(0.55, 0.88, 1.0)
		"fire":     return Color(1.0, 0.28, 0.04)
		"shock":    return Color(0.9, 0.95, 0.3)
		"beam":     return Color(0.3, 1.0, 0.8)
		"shotgun":  return Color(1.0, 0.85, 0.1)
		"homing":   return Color(0.6, 0.2, 1.0)
		"nova":     return Color(0.7, 0.0, 1.0)
	return Color(0.72, 0.72, 0.88)

func _spawn_trail_marker() -> void:
	if not is_inside_tree():
		return
	var col := _get_proj_color()
	var dot := ColorRect.new()
	dot.size = Vector2(4.0, 4.0)
	dot.color = Color(col.r, col.g, col.b, 0.55)
	dot.position = global_position - Vector2(2.0, 2.0)
	get_tree().current_scene.add_child(dot)
	var fade := 0.15 if shoot_type in ["fire", "freeze", "homing"] else 0.1
	var tw := dot.create_tween()
	tw.tween_property(dot, "modulate:a", 0.0, fade)
	tw.tween_callback(dot.queue_free)

func _get_burst_char() -> String:
	match shoot_type:
		"fire":    return "@"
		"freeze":  return "*"
		"shock":   return "~"
		"chain":   return "+"
		"ricochet": return "o"
		"pierce":  return "-"
		"shotgun": return "#"
		"nova":    return "o"
		"homing":  return "*"
	return "."

func _spawn_impact_burst(pos: Vector2) -> void:
	if not is_inside_tree():
		return
	var col := _get_proj_color()
	var burst_char := _get_burst_char()
	var count := 3 if shoot_type in ["regular", "pierce", "homing"] else 4
	for i in count:
		var c := Label.new()
		c.text = burst_char
		c.add_theme_font_size_override("font_size", 9)
		c.add_theme_color_override("font_color", col.lightened(0.2))
		c.position = pos + Vector2(randf_range(-5.0, 5.0), randf_range(-5.0, 5.0))
		get_tree().current_scene.add_child(c)
		var drift := Vector2(randf_range(-30.0, 30.0), randf_range(-50.0, -4.0))
		var tw := c.create_tween()
		tw.tween_property(c, "position", c.position + drift, 0.22)
		tw.parallel().tween_property(c, "modulate:a", 0.0, 0.22)
		tw.tween_callback(c.queue_free)

func _spawn_death_pop(pos: Vector2) -> void:
	if not is_inside_tree():
		return
	var col := _get_proj_color()
	var pop_chars := ["*", "+", "x", "*", "o"]
	for i in 5:
		var c := Label.new()
		c.text = pop_chars[i]
		c.add_theme_font_size_override("font_size", 13)
		c.add_theme_color_override("font_color", Color(col.r, col.g, col.b, 1.0))
		var angle := (TAU / 5.0) * float(i) + randf_range(-0.25, 0.25)
		var dist := randf_range(14.0, 30.0)
		var target := pos + Vector2(cos(angle), sin(angle)) * dist
		c.position = pos + Vector2(-4.0, -6.0)
		get_tree().current_scene.add_child(c)
		var tw := c.create_tween()
		tw.tween_property(c, "position", target + Vector2(-4.0, -6.0), 0.32)
		tw.parallel().tween_property(c, "modulate:a", 0.0, 0.32)
		tw.tween_callback(c.queue_free)
