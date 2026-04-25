extends Area2D

const PROJ_SCENE        := preload("res://scenes/Projectile.tscn")
const NOVA_SPAWNER_SCR  := preload("res://scripts/NovaSpawner.gd")

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
var apply_freeze: bool      = false
var apply_burn: bool        = false
var apply_shock: bool       = false
var drift_speed: float      = 0.0  # sideways drift px/s (relative to direction)

var fire_patch_upgraded: bool = false  # Pyromaniac Sigil: bigger/longer patch
var glacial_bonus: bool       = false  # Glacial Core: bonus dmg to frozen/chilled
var void_lens_active: bool    = false  # Void Lens: 16-shard nova
var assassin_mark: bool       = false  # Assassin's Mark: homing deals 2x damage

var player_intelligence: int = 1    # scales elemental AoE/chain — set by Player._fire()
var arc_target: Vector2      = Vector2.ZERO  # enemy arc shots steer toward this point
var _hit_entities: Array     = []   # instance IDs already struck (pierce/chain dedup)
var _bounce_cd: float        = 0.0  # brief cooldown to prevent double-bounce
var _trail_timer: float      = 0.0
var _base_direction: Vector2 = Vector2.ZERO
var _zigzag_t: float         = 0.0
var _zap_skip: bool          = false  # rebuild ShockZap every other tick to halve cost
var _homing_target: Node2D   = null  # cached lock-on target

func _ready() -> void:
	rotation = direction.angle()
	_base_direction = direction
	# Detect both walls (layer 1) and enemies (layer 2 — enemies were moved
	# off layer 1 so they no longer push each other / the player around)
	collision_mask = 3
	# Register so the autoplay bot can scan incoming enemy shots to dodge
	if source == "enemy":
		add_to_group("enemy_projectile")
	if shoot_type == "nova_shard":
		# Shards are numerous and short-lived — skip font rendering and trail
		var lbl := get_node_or_null("AsciiChar")
		if lbl != null:
			lbl.hide()
		_trail_timer = 999.0
	elif shoot_type == "shock":
		# Lightning bullet: hide char, draw a crackling Line2D zap instead
		var lbl := get_node_or_null("AsciiChar")
		if lbl != null:
			lbl.hide()
		var zap := Line2D.new()
		zap.name = "ShockZap"
		zap.width = 3.0
		zap.default_color = Color(0.55, 0.85, 1.0, 1.0)
		zap.z_index = 1
		add_child(zap)
	else:
		_apply_visual()
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	get_tree().create_timer(lifetime).timeout.connect(
		func() -> void:
			if not is_instance_valid(self): return
			if shoot_type == "grenade":
				_explode_grenade()
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
		"arc":
			lbl.text = ")"
			lbl.add_theme_color_override("font_color", Color(1.0, 0.45, 0.0))
		"grenade":
			lbl.text = "O"
			lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.05))
		"missile":
			lbl.text = ">"
			lbl.add_theme_color_override("font_color", Color(1.0, 0.25, 0.15))
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
		# Crackling lightning body — regenerated every other tick to halve the
		# Line2D rebuild cost when many shock projectiles are on screen.
		_zap_skip = not _zap_skip
		if not _zap_skip:
			var zap := get_node_or_null("ShockZap") as Line2D
			if zap:
				zap.clear_points()
				for i in 7:
					var t := float(i) / 6.0
					var px := -12.0 + 24.0 * t
					var py := 0.0 if i == 0 or i == 6 else randf_range(-5.5, 5.5)
					zap.add_point(Vector2(px, py))

	if shoot_type == "homing":
		if not is_instance_valid(_homing_target):
			_homing_target = null
			var best_dist := 700.0 * 700.0
			for e: Node in get_tree().get_nodes_in_group("enemy"):
				if not is_instance_valid(e):
					continue
				var d := global_position.distance_squared_to((e as Node2D).global_position)
				if d < best_dist:
					best_dist = d
					_homing_target = e as Node2D
		if _homing_target != null:
			var to_target := (_homing_target.global_position - global_position).normalized()
			var turn_rate := 5.5 + player_intelligence * 0.8   # 6.3 at int=1, 11.9 at int=8
			direction = direction.lerp(to_target, turn_rate * delta).normalized()
			rotation = direction.angle()

	if (shoot_type == "arc" or shoot_type == "grenade") and arc_target != Vector2.ZERO:
		var to_tgt := (arc_target - global_position).normalized()
		direction = direction.lerp(to_tgt, 2.5 * delta).normalized()
		rotation = direction.angle()

	if shoot_type == "missile":
		if not is_instance_valid(_homing_target):
			_homing_target = get_tree().get_first_node_in_group("player") as Node2D
		if _homing_target != null:
			var to_p := (_homing_target.global_position - global_position).normalized()
			direction = direction.lerp(to_p, 1.8 * delta).normalized()
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
		var wall_c = hit.get("collider")
		if shoot_type == "grenade":
			_explode_grenade()
			queue_free()
			return
		if wall_c.is_in_group("breakable_wall"):
			if wall_c.has_method("take_damage"):
				wall_c.take_damage(damage)
			queue_free()
			return
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
		if shoot_type == "grenade":
			_explode_grenade()
			queue_free()
			return
		if body.is_in_group("breakable_wall"):
			if body.has_method("take_damage"):
				body.take_damage(damage)
			queue_free()
			return
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
		var hit_pos := body.global_position
		var target_elite: bool = (body.get("is_elite") == true) if "is_elite" in body else false
		var actual_dmg := damage
		if assassin_mark and shoot_type == "homing":
			actual_dmg *= 2
		if glacial_bonus and (body.get("_frozen") == true or (body.get("_chill_stacks") as int) > 0):
			actual_dmg += damage
		var is_crit := GameState.roll_crit()
		if is_crit:
			actual_dmg *= 2
		if body.has_method("take_damage"):
			body.take_damage(actual_dmg)
			GameState.damage_dealt += actual_dmg
			GameState.record_weapon_damage(shoot_type, actual_dmg)
		if is_crit:
			FloatingText.spawn_str(hit_pos, "CRIT %d" % actual_dmg, Color(1.0, 0.85, 0.1), get_tree().current_scene)
			if SoundManager:
				SoundManager.play("crit", randf_range(0.95, 1.08))
		if SoundManager:
			SoundManager.play("hit", randf_range(0.88, 1.12))
		_spawn_impact_burst(hit_pos)
		if body.is_queued_for_deletion():
			GameState.record_weapon_kill(shoot_type)
			_spawn_death_pop(hit_pos)
			if SoundManager:
				SoundManager.play("enemy_death", randf_range(0.85, 1.15))
			if not GameState.test_mode:
				var pnode: Node = get_tree().get_first_node_in_group("player")
				if pnode and pnode.has_method("start_hit_stop"):
					pnode.start_hit_stop(70 if target_elite else 40)
		if apply_freeze and body.has_method("apply_status"):
			body.apply_status("freeze_hit", 0.0)
			if shoot_type == "freeze":
				_do_freeze_aoe(body)
		if apply_burn and body.has_method("apply_status"):
			body.apply_status("burn_hit", 0.0)
			# Patch is now spawned by the ENFLAMED proc (10 stacks), not on every hit
		if apply_shock and body.has_method("apply_status"):
			body.apply_status("shock_hit", 0.0)
			if shoot_type == "shock":
				_do_shock_chain(body)
		if ricochet_remaining > 0:
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
			damage += 1  # growing damage — each pierce hit is stronger
			return
		queue_free()
		return

	# Enemy projectile hits player
	if source == "enemy" and body.is_in_group("player"):
		if shoot_type == "grenade":
			_explode_grenade()
		elif body.has_method("take_damage"):
			body.take_damage(damage)
		queue_free()
		return

	queue_free()

func _explode_grenade() -> void:
	var radius := 70.0
	var ply := get_tree().get_first_node_in_group("player")
	if is_instance_valid(ply) and (ply as Node2D).global_position.distance_to(global_position) <= radius:
		if ply.has_method("take_damage"):
			ply.take_damage(damage)
	if SoundManager:
		SoundManager.play("explosion", randf_range(0.92, 1.08))
	# Visual: expanding shockwave ring
	if not is_inside_tree(): return
	var holder := Node2D.new()
	holder.global_position = global_position
	get_tree().current_scene.add_child(holder)
	var ring := Line2D.new()
	ring.width = 4.0
	ring.default_color = Color(1.0, 0.5, 0.05, 0.95)
	var segs := 24
	for i in segs + 1:
		var ang := (TAU / float(segs)) * float(i)
		ring.add_point(Vector2(cos(ang), sin(ang)) * radius * 0.5)
	holder.add_child(ring)
	var tw := holder.create_tween()
	tw.tween_property(holder, "scale", Vector2(2.2, 2.2), 0.30)
	tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.30)
	tw.tween_callback(holder.queue_free)

func _chain_hop(from_pos: Vector2, hops_left: int) -> void:
	if hops_left <= 0:
		return
	var best: Node2D = null
	var best_dist := 160.0 * 160.0
	for enemy: Node in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy):
			continue
		if enemy.is_in_group("player"):
			continue
		if enemy.get_instance_id() in _hit_entities:
			continue
		var d := from_pos.distance_squared_to((enemy as Node2D).global_position)
		if d < best_dist:
			best_dist = d
			best = enemy as Node2D
	if best == null:
		return
	var eid := best.get_instance_id()
	_hit_entities.append(eid)
	# Deal damage and status effects
	var hop_dmg := damage
	var hop_crit := GameState.roll_crit()
	if hop_crit:
		hop_dmg *= 2
	if best.has_method("take_damage"):
		best.take_damage(hop_dmg)
		GameState.damage_dealt += hop_dmg
		GameState.record_weapon_damage(shoot_type, hop_dmg)
		if best.is_queued_for_deletion():
			GameState.record_weapon_kill(shoot_type)
	if hop_crit:
		FloatingText.spawn_str(best.global_position, "CRIT %d" % hop_dmg, Color(1.0, 0.85, 0.1), get_tree().current_scene)
	if apply_freeze and best.has_method("apply_status"):
		best.apply_status("freeze_hit", 0.0)
	if apply_burn and best.has_method("apply_status"):
		best.apply_status("burn_hit", 0.0)
	if apply_shock and best.has_method("apply_status"):
		best.apply_status("shock_hit", 0.0)
	# Lightning arc visual only
	var arc := Line2D.new()
	arc.width = 2.0
	arc.default_color = Color(0.85, 0.95, 1.0, 0.9)
	for i in 7:
		var t := float(i) / 6.0
		var pt := from_pos.lerp(best.global_position, t)
		if i > 0 and i < 6:
			var perp := (best.global_position - from_pos).normalized().rotated(PI * 0.5)
			pt += perp * randf_range(-14.0, 14.0)
		arc.add_point(pt)
	get_tree().current_scene.add_child(arc)
	var arc_tw := arc.create_tween()
	arc_tw.tween_property(arc, "modulate:a", 0.0, 0.28)
	arc_tw.tween_callback(arc.queue_free)
	# Next hop
	_chain_hop(best.global_position, hops_left - 1)

func _detonate_nova() -> void:
	var count := 16 if void_lens_active else 8
	var spawner := Node2D.new()
	spawner.set_script(NOVA_SPAWNER_SCR)
	spawner._spawn_pos   = global_position
	spawner._source      = source
	spawner._damage      = damage
	spawner._shoot_type  = "nova_shard"
	spawner._pierce      = 1
	for i in count:
		var angle := (TAU / float(count)) * float(i)
		spawner._queue.append(Vector2(cos(angle), sin(angle)))
	get_tree().current_scene.add_child(spawner)

func _do_shock_chain(from_enemy: Node2D) -> void:
	# Reuse _chain_hop — shock chains to player_intelligence additional targets
	_chain_hop(from_enemy.global_position, player_intelligence)

func _do_freeze_aoe(from_enemy: Node2D) -> void:
	var radius := 90.0 + player_intelligence * 15.0
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy):
			continue
		if enemy.get_instance_id() == from_enemy.get_instance_id():
			continue
		if (enemy as Node2D).global_position.distance_to(from_enemy.global_position) > radius:
			continue
		if enemy.has_method("apply_status"):
			enemy.apply_status("freeze_hit", 0.0)
			enemy.apply_status("freeze_hit", 0.0)
			enemy.apply_status("freeze_hit", 0.0)

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
		"freeze":   return Color(0.55, 0.88, 1.0)
		"fire":     return Color(1.0, 0.28, 0.04)
		"shock":    return Color(0.55, 0.85, 1.0)
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

func _spawn_impact_burst(pos: Vector2) -> void:
	if not is_inside_tree():
		return
	match shoot_type:
		"pierce":   _impact_pierce(pos)
		"ricochet": _impact_ricochet(pos)
		"freeze":   _impact_freeze(pos)
		"fire":     _impact_fire(pos)
		"shock":    _impact_shock(pos)
		"shotgun":  _impact_shotgun(pos)
		"homing":   _impact_homing(pos)
		"nova":     _impact_nova(pos)
		_:          _impact_default(pos)

func _impact_default(pos: Vector2) -> void:
	var col := _get_proj_color()
	for i in 3:
		var c := ColorRect.new()
		c.size  = Vector2(3.0, 3.0)
		c.color = col.lightened(0.25)
		c.position = pos + Vector2(randf_range(-5.0, 5.0), randf_range(-5.0, 5.0))
		get_tree().current_scene.add_child(c)
		var drift := Vector2(randf_range(-28.0, 28.0), randf_range(-42.0, -4.0))
		var tw := c.create_tween()
		tw.tween_property(c, "position", c.position + drift, 0.18)
		tw.parallel().tween_property(c, "modulate:a", 0.0, 0.18)
		tw.tween_callback(c.queue_free)

func _impact_pierce(pos: Vector2) -> void:
	# Forward streaks — drilling through
	var col := Color(0.95, 0.95, 0.30)
	var perp := direction.rotated(PI * 0.5)
	for i in 4:
		var streak := ColorRect.new()
		streak.size = Vector2(10.0, 1.5)
		streak.color = col
		streak.position = pos + perp * randf_range(-6.0, 6.0)
		streak.rotation = direction.angle()
		get_tree().current_scene.add_child(streak)
		var target := streak.position + direction * randf_range(22.0, 38.0)
		var tw := streak.create_tween()
		tw.tween_property(streak, "position", target, 0.18)
		tw.parallel().tween_property(streak, "modulate:a", 0.0, 0.18)
		tw.tween_callback(streak.queue_free)

func _impact_ricochet(pos: Vector2) -> void:
	# Ring shatter — even radial fragments
	var col := Color(0.35, 1.0, 0.50)
	for i in 6:
		var c := ColorRect.new()
		c.size = Vector2(3.0, 3.0)
		c.color = col
		c.position = pos
		get_tree().current_scene.add_child(c)
		var angle := (TAU / 6.0) * float(i)
		var target := pos + Vector2(cos(angle), sin(angle)) * 22.0
		var tw := c.create_tween()
		tw.tween_property(c, "position", target, 0.22)
		tw.parallel().tween_property(c, "modulate:a", 0.0, 0.22)
		tw.tween_callback(c.queue_free)

func _impact_freeze(pos: Vector2) -> void:
	# Crystalline shards
	var col := Color(0.65, 0.92, 1.0)
	for i in 7:
		var lbl := Label.new()
		lbl.text = "*"
		lbl.add_theme_color_override("font_color", col)
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.position = pos + Vector2(-4.0, -8.0)
		get_tree().current_scene.add_child(lbl)
		var angle := randf() * TAU
		var dist := randf_range(14.0, 26.0)
		var target := lbl.position + Vector2(cos(angle), sin(angle)) * dist
		var tw := lbl.create_tween()
		tw.tween_property(lbl, "position", target, 0.28)
		tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.28)
		tw.tween_callback(lbl.queue_free)

func _impact_fire(pos: Vector2) -> void:
	# Flame bloom — flame chars expanding outward
	var chars := ["(", ")", "*"]
	for i in 6:
		var lbl := Label.new()
		lbl.text = chars[i % 3]
		lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.05))
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.position = pos + Vector2(-4.0, -8.0)
		get_tree().current_scene.add_child(lbl)
		var angle := (TAU / 6.0) * float(i) + randf_range(-0.3, 0.3)
		var dist := randf_range(12.0, 22.0)
		var target := lbl.position + Vector2(cos(angle), sin(angle)) * dist
		var tw := lbl.create_tween()
		tw.tween_property(lbl, "position", target, 0.22)
		tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.22)
		tw.tween_callback(lbl.queue_free)

func _impact_shock(pos: Vector2) -> void:
	# Lightning fork — 3 jagged arcs branching out
	for i in 3:
		var arc := Line2D.new()
		arc.width = 2.0
		arc.default_color = Color(0.55, 0.85, 1.0, 1.0)
		var angle := (TAU / 3.0) * float(i) + randf_range(-0.5, 0.5)
		var len := randf_range(20.0, 32.0)
		var end_pt := pos + Vector2(cos(angle), sin(angle)) * len
		for j in 5:
			var t := float(j) / 4.0
			var pt := pos.lerp(end_pt, t)
			if j > 0 and j < 4:
				var perp := (end_pt - pos).normalized().rotated(PI * 0.5)
				pt += perp * randf_range(-4.0, 4.0)
			arc.add_point(pt)
		get_tree().current_scene.add_child(arc)
		var tw := arc.create_tween()
		tw.tween_property(arc, "modulate:a", 0.0, 0.22)
		tw.tween_callback(arc.queue_free)

func _impact_shotgun(pos: Vector2) -> void:
	# Buckshot scatter — forward cone of small dots
	var col := Color(1.0, 0.85, 0.10)
	for i in 7:
		var c := ColorRect.new()
		c.size = Vector2(2.5, 2.5)
		c.color = col
		c.position = pos
		get_tree().current_scene.add_child(c)
		var spread := direction.rotated(randf_range(-0.7, 0.7))
		var target := pos + spread * randf_range(15.0, 32.0)
		var tw := c.create_tween()
		tw.tween_property(c, "position", target, 0.18)
		tw.parallel().tween_property(c, "modulate:a", 0.0, 0.18)
		tw.tween_callback(c.queue_free)

func _impact_homing(pos: Vector2) -> void:
	# Pulse ring — expanding circle outline
	var holder := Node2D.new()
	holder.global_position = pos
	var ring := Line2D.new()
	ring.width = 2.0
	ring.default_color = Color(0.75, 0.30, 1.0, 1.0)
	var segments := 14
	for j in segments + 1:
		var ang := (TAU / float(segments)) * float(j)
		ring.add_point(Vector2(cos(ang), sin(ang)) * 6.0)
	holder.add_child(ring)
	get_tree().current_scene.add_child(holder)
	var tw := holder.create_tween()
	tw.tween_property(holder, "scale", Vector2(3.2, 3.2), 0.28)
	tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.28)
	tw.tween_callback(holder.queue_free)

func _impact_nova(pos: Vector2) -> void:
	# 8-directional sparks
	var col := Color(0.85, 0.30, 1.0)
	for i in 8:
		var c := ColorRect.new()
		c.size = Vector2(3.0, 3.0)
		c.color = col
		c.position = pos
		get_tree().current_scene.add_child(c)
		var angle := (TAU / 8.0) * float(i)
		var target := pos + Vector2(cos(angle), sin(angle)) * 18.0
		var tw := c.create_tween()
		tw.tween_property(c, "position", target, 0.20)
		tw.parallel().tween_property(c, "modulate:a", 0.0, 0.20)
		tw.tween_callback(c.queue_free)

func _spawn_death_pop(pos: Vector2) -> void:
	if not is_inside_tree():
		return
	var col := _get_proj_color()
	for i in 4:
		var c := ColorRect.new()
		c.size  = Vector2(5.0, 5.0)
		c.color = Color(col.r, col.g, col.b, 1.0)
		var angle := (TAU / 4.0) * float(i) + randf_range(-0.3, 0.3)
		var dist := randf_range(12.0, 26.0)
		var target := pos + Vector2(cos(angle), sin(angle)) * dist
		c.position = pos
		get_tree().current_scene.add_child(c)
		var tw := c.create_tween()
		tw.tween_property(c, "position", target, 0.30)
		tw.parallel().tween_property(c, "modulate:a", 0.0, 0.30)
		tw.tween_callback(c.queue_free)
