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
# How many status stacks the wand applies per hit (passed via the wand's
# wand_status_stacks). Default 1 keeps non-wand sources working unchanged.
var status_stacks: int      = 1
var drift_speed: float      = 0.0  # sideways drift px/s (relative to direction)

var fire_patch_upgraded: bool = false  # Pyromaniac Sigil: bigger/longer patch
var glacial_bonus: bool       = false  # Glacial Core: bonus dmg to frozen/chilled
var void_lens_active: bool    = false  # Void Lens: 16-shard nova
var assassin_mark: bool       = false  # Assassin's Mark: homing deals 2x damage

var player_intelligence: int = 1    # scales elemental AoE/chain — set by Player._fire()
var arc_target: Vector2      = Vector2.ZERO  # enemy arc shots steer toward this point
var _hit_entities: Array     = []   # instance IDs already struck (pierce/chain dedup)
# Per-collider dedup for wall bounces — replaces the old time-based
# _bounce_cd cooldown. At high projectile speeds (shock at 1.7×, deep-
# diff wand_proj_speed) the time cooldown crossed multiple walls and
# silently queue_freed the projectile when the second wall arrived
# during the cooldown window. Tracking the last-hit collider id is
# geometry-correct: the reflected direction already prevents same-wall
# re-hits in the same arc, and a different collider always allows a
# bounce regardless of how recent the last one was.
var _last_bounce_collider_id: int = 0
# Physics frame the last bounce happened on. Used to distinguish the
# legitimate same-frame body_entered fire that follows a CCD bounce (silent
# skip — same wall, same physics tick) from a later-frame collision that's
# genuinely a new hit (consume ricochet or die).
var _last_bounce_phys_frame: int = -1
# Tracks distance traveled since the last wall bounce. Once we've cleared a
# small margin (~12 px) the dedup ID is wiped, so a projectile that ricochets
# off the same long horizontal wall twice in a row — e.g. bouncing off the
# top then re-hitting the underside after looping back — can re-trigger
# instead of dying. Previously the dedup held until a DIFFERENT body was
# hit, which manifested as "ricochet only works at very specific angles".
var _dist_since_bounce: float = 0.0
var _trail_timer: float      = 0.0
var _base_direction: Vector2 = Vector2.ZERO
var _zigzag_t: float         = 0.0
var _zap_skip: bool          = false  # rebuild ShockZap every other tick to halve cost
var _nova_anim_t: float      = 0.0    # nova glyph swap timer (cycles + ↔ x)
var _homing_target: Node2D   = null  # cached lock-on target
# Fires the freeze AoE only once per projectile lifetime. Without this, a
# pierce/ricochet freeze wand re-triggered the AoE on every pass-through,
# and at high wand_status_stacks the splash would chain-freeze whole
# adjacent rooms before the player even engaged.
var _did_freeze_aoe: bool    = false
# Walls the projectile is already overlapping at spawn (e.g. fired while the
# player is pressed against a wall, so the muzzle clips the wall collision).
# Those walls are ignored until the projectile exits them — otherwise the
# spawn-frame body_entered insta-kills the shot in EVERY direction. New walls
# still collide normally. Populated on the first physics frame.
var _spawn_overlap_walls: Dictionary = {}
var _spawn_overlap_checked: bool = false

func _ready() -> void:
	# Homing's "^" glyph natively points up (-Y), so the body needs an
	# extra +PI/2 on top of direction.angle() to put the tip on the
	# heading vector. Other shoot types (pierce ")", missile ">", arc ")"
	# etc.) align with direction.angle() directly because their shape
	# reads as forward-facing at rotation 0.
	if shoot_type == "homing":
		rotation = direction.angle() + PI * 0.5
	else:
		rotation = direction.angle()
	_base_direction = direction
	# Theme A — player stats nudge shot physics. DEX scales projectile
	# speed (snappier shots reward investment), INT scales lifetime so
	# long-range pokes survive longer with a high-INT build. Capped so
	# stacking can't trivially turn every wand into a sniper.
	if source == "player" and GameState != null:
		var dex_pts: int = GameState.get_stat_bonus("DEX")
		var int_pts: int = GameState.get_stat_bonus("INT")
		speed *= 1.0 + clampf(float(dex_pts) * 0.015, 0.0, 0.60)
		lifetime *= 1.0 + clampf(float(int_pts) * 0.015, 0.0, 0.50)
	# Detect both walls (layer 1) and enemies (layer 2 — enemies were moved
	# off layer 1 so they no longer push each other / the player around)
	collision_mask = 3
	# Register so the autoplay bot can scan incoming enemy shots to dodge
	if source == "enemy":
		add_to_group("enemy_projectile")
	if shoot_type == "nova_shard":
		# Shards are numerous but the burst was hard to read when they were
		# invisible — give each one a bright purple glyph + trail so the
		# nova actually looks like a burst.
		_apply_visual()
	elif shoot_type == "shock":
		# Shock flies straight (trajectory handled in _physics_process — no
		# direction modulation) but visually keeps the crackling Line2D
		# lightning body it had before. Hide the AsciiChar so the zap is
		# the only thing visible, then add a Line2D that re-randomizes its
		# midpoints every other tick to look like a moving lightning bolt.
		speed *= 1.7
		var lbl := get_node_or_null("AsciiChar")
		if lbl != null:
			lbl.hide()
		var zap := Line2D.new()
		zap.name = "ShockZap"
		zap.width = 3.0
		zap.default_color = Color(1.0, 0.92, 0.20, 1.0)
		zap.z_index = 1
		add_child(zap)
	else:
		_apply_visual()
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	body_exited.connect(_on_body_exited)
	# Hide the top-down glyph (and the ShockZap line) when in a first-person
	# mode. Projectiles are short-lived so we don't reconnect to the signal —
	# whichever mode is active at spawn dictates the visual for this shot's
	# lifetime, which is fine. The body itself keeps moving + colliding.
	if GameState.render_mode != GameState.RenderMode.TOPDOWN:
		var ascii := get_node_or_null("AsciiChar")
		if ascii != null:
			ascii.visible = false
		var zap := get_node_or_null("ShockZap")
		if zap != null:
			zap.visible = false
		# Player shots leave from below the crosshair — was rendering at
		# chest height (same y as the camera) so every shot appeared dead
		# centered. Lowering further (was 0.30, now 0.22) so the muzzle
		# unmistakably comes from below the screen.
		if source == "player":
			set_meta("fp_height", 0.22)
		# Register with the FP rig so the shot is actually visible in the
		# new viewport. Glyph + color differ by shoot_type so fire / shock /
		# freeze read as distinctly-flavored attacks rather than identical
		# yellow dots. The rig further bumps the font size for "substantial"
		# shoot types to sell them as impact-y.
		if GameState.active_rig != null and is_instance_valid(GameState.active_rig) \
				and GameState.active_rig.has_method("register_entity"):
			var glyph: String
			var color: Color
			if source == "player":
				# Mirror the top-down palette so only shotgun is yellow —
				# regular = white, pierce = steel blue, shock = violet, homing
				# = hot pink. Each type now reads as a distinct color at a
				# glance instead of "another yellow blob" in FP.
				match shoot_type:
					"fire":
						glyph = "@"
						color = Color(1.0, 0.42, 0.08)
					"freeze":
						glyph = "*"
						color = Color(0.55, 0.92, 1.0)
					"shock":
						glyph = "z"
						color = Color(1.0, 0.92, 0.20)
						set_meta("fp_floor_decal", true)
					"pierce":
						glyph = ")"
						color = Color(0.55, 0.85, 1.0)
						set_meta("fp_pixel_size", 0.018)
						set_meta("fp_floor_decal", true)
					"ricochet":
						glyph = "o"
						color = Color(0.20, 1.0, 0.35)
					"shotgun":
						glyph = "#"
						color = Color(0.85, 0.85, 0.85)
					"nova_shard":
						glyph = "+"
						color = Color(0.85, 0.30, 1.0)
					"nova":
						# Animated + ↔ x core. set_meta tells the FP rig
						# to keep live-syncing AsciiChar.text for this
						# projectile (projectiles are normally skipped to
						# protect pierce's ")" glyph from being clobbered).
						glyph = "+"
						color = Color(0.70, 0.0, 1.0)
						set_meta("fp_animate", true)
					"homing":
						glyph = "^"
						color = Color(1.0, 0.40, 0.80)
						set_meta("fp_floor_decal", true)
					"grenade":
						glyph = "O"
						color = Color(1.0, 0.45, 0.15)
					"arc":
						glyph = ")"
						color = Color(1.0, 0.55, 0.15)
					"missile":
						glyph = ">"
						color = Color(1.0, 0.20, 0.10)
					_:
						# Regular + any unmapped type — apostrophe matches
						# the 2D apostrophe label.
						glyph = "'"
						color = Color(0.95, 0.95, 0.95)
				# Single source of truth — the match above sets each type's FP
				# glyph + metas; the palette sets the color so it matches the 2D
				# shot and the trail particle.
				color = _type_color(shoot_type)
			else:
				glyph = "o"
				color = Color(1.0, 0.35, 0.35)
				# Enemy shots read bigger so incoming threats are legible in
				# FP (default projectile size is a near-invisible speck).
				set_meta("fp_pixel_size", 0.008)
			GameState.active_rig.register_entity(self, glyph, color)
			tree_exiting.connect(_unregister_from_rig)
	# Freeze bolts get a short leash — at default lifetime + speed they'd
	# travel ~2000 px through corridor sight lines and pre-freeze enemies
	# in distant rooms before the player ever engaged them. ~1.2 s is enough
	# for in-room shots to land + pierce + AoE, but caps reach at ~2 rooms.
	if shoot_type == "freeze":
		lifetime = minf(lifetime, 1.2)
	get_tree().create_timer(lifetime).timeout.connect(_on_lifetime_expired)

func _on_lifetime_expired() -> void:
	if shoot_type == "grenade":
		_explode_grenade()
	queue_free()

func _unregister_from_rig() -> void:
	if GameState.active_rig != null and is_instance_valid(GameState.active_rig) \
			and GameState.active_rig.has_method("unregister_entity"):
		GameState.active_rig.unregister_entity(self)

func _apply_visual() -> void:
	var lbl := get_node_or_null("AsciiChar")
	if lbl == null:
		return
	# Palette is split so only shotgun reads yellow. Regular = white,
	# pierce = steel blue, shock = violet (was all yellow and indistinguishable),
	# homing = hot pink (was purple, conflicted with nova).
	match shoot_type:
		"regular":
			lbl.text = "'"
			lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
		"pierce":
			# Wide forward arc — ")" naturally has convex on the right side,
			# so under the Area2D's direction-aligned rotation the curve
			# always points along the flight direction (right→forward,
			# up→up, etc) for any 360° heading. No extra local rotation
			# needed; "(" with rotation only put the curve on top/bottom,
			# not forward.
			lbl.text = ")"
			lbl.add_theme_font_size_override("font_size", 36)
			lbl.offset_left   = -18.0
			lbl.offset_top    = -18.0
			lbl.offset_right  =  18.0
			lbl.offset_bottom =  18.0
			lbl.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
			# Give pierce its own shape instance rather than mutating the shared
			# sub-resource (which would bleed 24×24 into every subsequent shot).
			# Wide perpendicular to travel (24) but shorter forward reach (12).
			var cshape := get_node_or_null("CollisionShape2D") as CollisionShape2D
			if cshape != null:
				var s := RectangleShape2D.new()
				s.size = Vector2(12, 24)
				cshape.shape = s
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
			lbl.add_theme_color_override("font_color", Color(0.70, 0.40, 1.0))
		"shotgun":
			lbl.text = "#"
			lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		"homing":
			lbl.text = "^"
			lbl.add_theme_color_override("font_color", Color(1.0, 0.40, 0.80))
		"nova":
			# Animated between "+" and "x" in _physics_process for the
			# "spinning energy core" feel.
			lbl.text = "+"
			lbl.add_theme_color_override("font_color", Color(0.7, 0.0, 1.0))
		"nova_shard":
			lbl.text = "✦"
			lbl.add_theme_font_size_override("font_size", 18)
			lbl.add_theme_color_override("font_color", Color(0.95, 0.55, 1.0))
			lbl.add_theme_color_override("font_outline_color", Color(0.4, 0.0, 0.6))
			lbl.add_theme_constant_override("outline_size", 3)
		"arc":
			lbl.text = ")"
			lbl.add_theme_color_override("font_color", Color(1.0, 0.45, 0.0))
		"grenade":
			lbl.text = "O"
			lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.05))
		"missile":
			lbl.text = ">"
		_:
			lbl.text = "."
	# Single source of truth for the glyph color so the 2D shot, FP shot, and
	# trail particle all share the per-type palette (the match above only sets
	# each type's glyph + sizing now).
	lbl.add_theme_color_override("font_color", _type_color(shoot_type))

func _physics_process(delta: float) -> void:
	# Nova glyph cycle — swap "+" / "x" every 100 ms. The FP rig live-syncs
	# AsciiChar.text for any projectile with fp_animate meta, so this
	# updates both views.
	if shoot_type == "nova":
		_nova_anim_t += delta
		if _nova_anim_t >= 0.10:
			_nova_anim_t = 0.0
			var nlbl := get_node_or_null("AsciiChar") as Label
			if nlbl != null:
				nlbl.text = "x" if nlbl.text == "+" else "+"

	# Fire bolts arc gently — flames feel like they're flickering and
	# curling toward the target. Tightened from ±22° / 12 rad/s to ±10° /
	# 16 rad/s so the lateral deviation stays inside ~25 px and the bot
	# can actually hit moving targets at range. Shock flies straight (no
	# direction modulation) — its zigzag is purely visual via the
	# ShockZap Line2D below.
	if shoot_type == "fire" and _base_direction != Vector2.ZERO:
		_zigzag_t += delta * 16.0
		direction = _base_direction.rotated(sin(_zigzag_t) * deg_to_rad(10.0))
		rotation = direction.angle()

	if shoot_type == "shock":
		# Crackling lightning body — regenerated every other tick to halve the
		# Line2D rebuild cost when many shock projectiles are on screen. The
		# zap rides along with the bullet's straight trajectory; only the
		# visual jitters, not the actual motion.
		_zap_skip = not _zap_skip
		if not _zap_skip:
			var in_topdown: bool = GameState.render_mode == GameState.RenderMode.TOPDOWN
			# In FP mode the 2D ShockZap Line2D is invisible anyway, so skip
			# the rebuild entirely — it's per-tick busywork.
			if in_topdown:
				var zap := get_node_or_null("ShockZap") as Line2D
				if zap:
					zap.clear_points()
					for i in 7:
						var t := float(i) / 6.0
						var px := -12.0 + 24.0 * t
						var py := 0.0 if i == 0 or i == 6 else randf_range(-5.5, 5.5)
						zap.add_point(Vector2(px, py))
			else:
				# FP fire-and-forget zap line inside the SubViewport.
				if GameState.active_rig != null and is_instance_valid(GameState.active_rig) \
						and GameState.active_rig.has_method("spawn_shock_zap"):
					GameState.active_rig.spawn_shock_zap(global_position, direction,
						Color(1.0, 0.92, 0.20))

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
			# +PI/2 so "^"'s native upward tip rotates to face along
			# direction. See _ready comment.
			rotation = direction.angle() + PI * 0.5

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
		if shoot_type == "homing":
			rotation = direction.angle() + PI * 0.5
		else:
			rotation = direction.angle()

	# Capture walls overlapping at spawn (once) so a shot fired while
	# clipping a wall can escape it instead of insta-dying.
	if not _spawn_overlap_checked:
		_spawn_overlap_checked = true
		for b in get_overlapping_bodies():
			if b is StaticBody2D:
				_spawn_overlap_walls[b.get_instance_id()] = true

	var move := direction * speed * delta

	# CCD wall check — raycasts ahead to prevent tunneling at high speeds.
	# Restricted to layer 1 (walls / static geometry) so the ray ignores
	# enemies. Without the mask, the ray returned the closest collider of
	# any kind, and a wall hidden behind a body returned a CharacterBody2D
	# instead — which the `is StaticBody2D` check below rejected, so the
	# wall bounce never fired and ricochet shots silently passed into walls.
	var space := get_world_2d().direct_space_state
	var ray := PhysicsRayQueryParameters2D.create(
		global_position,
		global_position + move + direction * 6.0   # small lookahead
	)
	ray.exclude = [get_rid()]
	ray.collision_mask = 1
	var hit := space.intersect_ray(ray)
	if not hit.is_empty() and hit.get("collider") is StaticBody2D \
			and not _spawn_overlap_walls.has((hit.get("collider") as Object).get_instance_id()):
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
		# CCD runs once per physics frame, so a same-wall hit here is always
		# a new tick (we already bounced off this wall on a previous frame
		# and didn't escape, OR we're hitting it for the first time). Treat
		# both as a normal collision: bounce if ricochet remains, else die.
		# The "stuck against the wall" case dies naturally when ricochet
		# runs out instead of looping silently in place.
		var wall_id: int = wall_c.get_instance_id()
		if ricochet_remaining > 0:
			ricochet_remaining -= 1
			_last_bounce_collider_id = wall_id
			_last_bounce_phys_frame = Engine.get_physics_frames()
			_dist_since_bounce = 0.0
			var hit_pos: Vector2 = hit.get("position") as Vector2
			var normal: Vector2  = hit.get("normal")  as Vector2
			# Godot returns a zero-length normal when the ray starts inside
			# a body (e.g. projectile tunneled into a wall). Vector2.bounce
			# requires a unit-length normal — fall back to -direction so the
			# bounce flips the heading instead of crashing.
			if normal.length_squared() < 0.0001:
				normal = -direction.normalized()
			else:
				normal = normal.normalized()
			var push: float = maxf(16.0, speed * delta * 0.75)
			global_position = hit_pos + normal * push
			direction = direction.bounce(normal)
			rotation = direction.angle()
			_hit_entities.clear()
		else:
			queue_free()
		return

	global_position += move

	# Travel-based dedup clearing — after 12 px the bullet has moved clear
	# enough that a future hit on the same wall body must be a NEW genuine
	# collision (e.g. ricocheting off two perpendicular walls and clipping
	# the first wall on the way back). Without this, long horizontal walls
	# allowed only the first bounce; subsequent same-wall grazes died.
	if _last_bounce_collider_id != 0:
		_dist_since_bounce += move.length()
		if _dist_since_bounce > 12.0:
			_last_bounce_collider_id = 0

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
		# Ignore walls the shot spawned inside (fired while pressed against
		# a wall) until it exits them — otherwise the shot dies instantly in
		# every direction. Cleared in _on_body_exited.
		if _spawn_overlap_walls.has(body.get_instance_id()):
			return
		# A wall overlapping at spawn emits body_entered at the END of the spawn
		# frame — BEFORE the projectile's first _physics_process runs (which is
		# where get_overlapping_bodies could see it). Until that first process
		# flips _spawn_overlap_checked, ANY wall we're already touching is a
		# muzzle clip (fired while pressed against a wall), not a real hit — so
		# exclude it and let the shot escape in every direction. Far walls reached
		# later can't fire body_entered until after the shot has moved, by which
		# point _spawn_overlap_checked is true and they block normally.
		if not _spawn_overlap_checked:
			_spawn_overlap_walls[body.get_instance_id()] = true
			return
		if shoot_type == "grenade":
			_explode_grenade()
			queue_free()
			return
		if body.is_in_group("breakable_wall"):
			if body.has_method("take_damage"):
				body.take_damage(damage)
			queue_free()
			return
		# body_entered fires AFTER physics integration. The most common case
		# is: CCD bounced this wall this frame, physics integration noticed
		# the new overlap, body_entered fires for the *same* wall in the
		# *same* physics frame. That should silently skip (the bounce
		# already happened). Different-frame same-wall hits are real
		# collisions — fall through to bounce-or-die.
		var wall_id: int = body.get_instance_id()
		if wall_id == _last_bounce_collider_id \
				and Engine.get_physics_frames() == _last_bounce_phys_frame:
			return
		if ricochet_remaining > 0:
			ricochet_remaining -= 1
			_last_bounce_collider_id = wall_id
			_last_bounce_phys_frame = Engine.get_physics_frames()
			_dist_since_bounce = 0.0
			var wall_normal := _normal_for_wall(body)
			global_position += wall_normal * 16.0
			direction = direction.bounce(wall_normal)
			rotation = direction.angle()
			_hit_entities.clear()
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
			actual_dmg = int(round(float(actual_dmg) * GameState.crit_damage_mult()))
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
		# Per-enemy hitsplat throttle — spongy enemies that take dozens of
		# hits/sec used to spawn N nodes per impact and tank performance.
		# Cap to one burst per 80 ms per enemy; damage + floating text still
		# fire every hit, only the particle visual is debounced.
		var now_ms: int = Time.get_ticks_msec()
		var last_burst_ms: int = int(body.get_meta("_last_burst_ms", -999))
		if now_ms - last_burst_ms >= 80:
			body.set_meta("_last_burst_ms", now_ms)
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
		# Status stacks pass-through. The duration arg is being repurposed
		# as "how many stacks to apply per hit" — wand_status_stacks finally
		# means something for freeze/shock (was previously hardcoded to 1).
		if apply_freeze and body.has_method("apply_status"):
			body.apply_status("freeze_hit", float(status_stacks))
			if shoot_type == "freeze" and not _did_freeze_aoe:
				_did_freeze_aoe = true
				_do_freeze_aoe(body)
		if apply_burn and body.has_method("apply_status"):
			body.apply_status("burn_hit", float(status_stacks))
		if apply_shock and body.has_method("apply_status"):
			body.apply_status("shock_hit", float(status_stacks))
			if shoot_type == "shock":
				_do_shock_chain(body)
		# SHATTER — pierce / ricochet / shock hitting a frozen target
		# detonates the freeze for bonus damage. Reads the target's
		# `_frozen` field via reflection so it works for every enemy
		# script without needing a shared base.
		if shoot_type in ["pierce", "ricochet", "shock"] and "_frozen" in body and bool(body.get("_frozen")):
			var shatter_dmg: int = maxi(damage, int(round(float(damage) * 1.5)))
			if body.has_method("take_damage"):
				body.take_damage(shatter_dmg)
				GameState.damage_dealt += shatter_dmg
				GameState.record_weapon_damage(shoot_type, shatter_dmg)
			# Drop the freeze so subsequent hits can re-stack toward another
			# shatter; otherwise the target stays glued at "_frozen = true"
			# until 4.5 s and the player has no way to exploit it again.
			body.set("_frozen", false)
			body.set("_chill_stacks", 0)
			if "_frozen_timer" in body:
				body.set("_frozen_timer", 0.0)
			FloatingText.spawn_str(body.global_position, "SHATTER %d" % shatter_dmg,
				Color(0.78, 0.92, 1.0), get_tree().current_scene)
			if SoundManager:
				SoundManager.play("crit", randf_range(0.85, 1.0))
		# Order: pierce charges spend FIRST, then ricochet kicks in once
		# pierce is exhausted. A wand with both stats now genuinely punches
		# through N enemies before bouncing — used to ricochet on the very
		# first enemy hit and waste pierce entirely. Walls also consume a
		# ricochet charge (handled in the CCD wall block above).
		if shoot_type == "nova":
			_detonate_nova()
			queue_free()
			return
		if pierce_remaining > 0:
			pierce_remaining -= 1
			damage += 1  # growing damage — each pierce hit is stronger
			return
		if ricochet_remaining > 0:
			ricochet_remaining -= 1
			# Bounce direction = away from enemy center; push the projectile
			# clear of the enemy so the area shapes don't re-trigger this
			# tick. Position offset scales with enemy size (~20 px collision
			# radius for most foes) plus per-frame travel.
			var bnormal := (global_position - body.global_position).normalized()
			if bnormal == Vector2.ZERO:
				bnormal = direction.rotated(PI)
			global_position = body.global_position + bnormal * 26.0
			direction = direction.bounce(bnormal)
			rotation = direction.angle()
			# Allow this projectile to re-hit the same enemy after the bounce.
			# Without clearing the per-hit tracker, a bounced ricochet can
			# never damage an enemy it's already passed through, which makes
			# tight pierce+ricochet rooms feel dead.
			_hit_entities.clear()
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

# Once the shot leaves a wall it spawned inside, that wall counts as a real
# obstacle again (so it can't tunnel back through the same wall later).
func _on_body_exited(body: Node2D) -> void:
	if body is StaticBody2D:
		_spawn_overlap_walls.erase(body.get_instance_id())

# Reconstructs a wall normal from the projectile's position relative to the
# wall's RectangleShape2D — used when body_entered fires (no normal carried
# by the signal). Compares the projectile's penetration depth along each
# axis and reflects off the axis with the smaller penetration (the edge
# the projectile just crossed). Falls back to inbound-axis flip if the
# wall has no recognizable rect shape.
func _normal_for_wall(body: Node) -> Vector2:
	# Fallback when we can't reconstruct geometry — reflect back along the
	# inbound direction. Direction is always non-zero (set in _ready) so
	# this never returns Vector2.ZERO into Vector2.bounce.
	var fallback: Vector2 = -direction.normalized()
	if not (body is Node2D):
		return fallback
	var body2d := body as Node2D
	var to_wall := body2d.global_position - global_position
	var cshape := body2d.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cshape != null and cshape.shape is RectangleShape2D:
		var size: Vector2 = (cshape.shape as RectangleShape2D).size
		var x_pen: float = size.x * 0.5 - absf(to_wall.x)
		var y_pen: float = size.y * 0.5 - absf(to_wall.y)
		var sx: float = signf(to_wall.x)
		var sy: float = signf(to_wall.y)
		if x_pen < y_pen and sx != 0.0:
			return Vector2(-sx, 0.0)
		if sy != 0.0:
			return Vector2(0.0, -sy)
		# Degenerate (projectile exactly at wall center) — use fallback.
		return fallback
	# Unknown shape — best effort.
	if absf(to_wall.x) > absf(to_wall.y) and signf(to_wall.x) != 0.0:
		return Vector2(-signf(to_wall.x), 0.0)
	if signf(to_wall.y) != 0.0:
		return Vector2(0.0, -signf(to_wall.y))
	return fallback

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
	# FP shockwave — ring of '*' chars expanding to the actual radius
	# (70 px in 2D = ~2.2 wu). Plus a forward-cone of debris so close-up
	# detonations feel forceful even when the ring rim has passed the
	# camera.
	var col := Color(1.0, 0.50, 0.10)
	# 32.0 = FirstPersonRig.TILE_PX — the rig's 2D-px-per-world-unit factor.
	# Hardcoded here because Projectile doesn't share the rig's const block.
	_fp_ring(global_position, "*", col, 0.30, radius / 32.0, 20, 0.30, 0.011, 0.20)
	_fp_burst(global_position, "*", col, 6, 0.7, 0.30, Vector2.ZERO, TAU, 0.010, 0.40)

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
		hop_dmg = int(round(float(hop_dmg) * GameState.crit_damage_mult()))
	if best.has_method("take_damage"):
		best.take_damage(hop_dmg)
		GameState.damage_dealt += hop_dmg
		GameState.record_weapon_damage(shoot_type, hop_dmg)
		if best.is_queued_for_deletion():
			GameState.record_weapon_kill(shoot_type)
	if hop_crit:
		FloatingText.spawn_str(best.global_position, "CRIT %d" % hop_dmg, Color(1.0, 0.85, 0.1), get_tree().current_scene)
	if apply_freeze and best.has_method("apply_status"):
		best.apply_status("freeze_hit", float(status_stacks))
	if apply_burn and best.has_method("apply_status"):
		best.apply_status("burn_hit", float(status_stacks))
	if apply_shock and best.has_method("apply_status"):
		best.apply_status("shock_hit", float(status_stacks))
	# Lightning arc visual only
	var arc := Line2D.new()
	arc.width = 2.0
	var arc_color := Color(0.85, 0.95, 1.0, 0.9)
	arc.default_color = arc_color
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
	# FP chain arc — jagged glyphs spanning the hop. Bright cyan so the
	# arc pops against the dim FP background; the rig's defaults handle
	# segment count, jitter and lifetime (boosted for visibility).
	_fp_chain(from_pos, best.global_position, Color(0.70, 1.0, 1.0))
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
	_spawn_nova_burst_flash(global_position)

# Big purple shockwave ring that expands and fades at the nova detonation
# point. Reads as an explosion outline before the shards have spread far
# enough to define the burst on their own.
func _spawn_nova_burst_flash(pos: Vector2) -> void:
	var holder := Node2D.new()
	holder.global_position = pos
	holder.z_index = 5
	var ring := Line2D.new()
	ring.width = 4.0
	ring.default_color = Color(0.95, 0.55, 1.0, 0.95)
	var segs := 28
	for i in segs + 1:
		var ang := (TAU / float(segs)) * float(i)
		ring.add_point(Vector2(cos(ang), sin(ang)) * 14.0)
	holder.add_child(ring)
	var inner := Line2D.new()
	inner.width = 2.0
	inner.default_color = Color(1.0, 0.85, 1.0, 0.85)
	for i in segs + 1:
		var ang2 := (TAU / float(segs)) * float(i)
		inner.add_point(Vector2(cos(ang2), sin(ang2)) * 14.0)
	holder.add_child(inner)
	get_tree().current_scene.add_child(holder)
	var tw := holder.create_tween()
	tw.tween_property(holder, "scale", Vector2(7.0, 7.0), 0.45)
	tw.parallel().tween_property(ring,  "modulate:a", 0.0, 0.45)
	tw.parallel().tween_property(inner, "modulate:a", 0.0, 0.32)
	tw.tween_callback(holder.queue_free)
	# FP intentionally skips the nova rings — the 16 shard projectiles
	# spawned by _detonate_nova are the FP feedback. The 2D rings above
	# still play for the top-down view.

func _do_shock_chain(from_enemy: Node2D) -> void:
	# Reuse _chain_hop — shock chains to player_intelligence additional targets
	_chain_hop(from_enemy.global_position, player_intelligence)

func _do_freeze_aoe(from_enemy: Node2D) -> void:
	# Tightened from `90 + INT*15` (which sprayed across most of a room at
	# high INT) to a small splash around the direct hit. Range is now
	# ~1.5–3 tiles depending on INT, so adjacent foes still get clipped
	# but distant enemies don't get caught in the freeze chain.
	var radius := 48.0 + float(player_intelligence) * 6.0
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy):
			continue
		if enemy.get_instance_id() == from_enemy.get_instance_id():
			continue
		if (enemy as Node2D).global_position.distance_to(from_enemy.global_position) > radius:
			continue
		if enemy.has_method("apply_status"):
			# 1 stack per adjacent enemy (was 3) — still helps build chill
			# but no longer hard-freezes whole packs from a single shot.
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
	if area.is_in_group("mine"):
		return  # Architect bombs / minelayer mines should not eat shots —
				# they detonate on the player, not on every projectile that
				# happens to pass through their detection radius
	if area.is_in_group("hazard"):
		return  # ice / lava / poison-cloud floor tiles must not eat shots
				# the player is firing across them
	if area.is_in_group("pressure_plate"):
		return  # plates trigger off the player, not projectiles passing over
	if area.is_in_group("interactable"):
		return  # shrines / shops / enchant table / sell chest / bank / quest
				# board / descend portal — never eat shots. The player should
				# be able to fire across the village or past a shrine without
				# the projectile dying mid-flight.
	queue_free()

# ── Visual helpers ────────────────────────────────────────────────────────────

# FP shorthand — no-op when no FP rig is active or rig isn't visible. Keeps
# the impact / burst code below from re-checking the rig pointer at every
# call site.
func _fp_burst(pos: Vector2, glyph: String, color: Color, count: int,
		spread: float = 0.25, lifetime: float = 0.18,
		direction: Vector2 = Vector2.ZERO, cone: float = TAU,
		pixel_size: float = 0.003, y: float = 0.05) -> void:
	# Defaults are deliberately small + floor-level so impact bursts read
	# AT the enemy's feet on the 3D floor, NOT as central screen-filling
	# flashes. Spread tight so sparks stay grouped near the hit point.
	if GameState.active_rig != null and is_instance_valid(GameState.active_rig) \
			and GameState.active_rig.has_method("spawn_burst_2d"):
		GameState.active_rig.spawn_burst_2d(pos, glyph, color, count, spread,
			lifetime, direction, cone, pixel_size, y)

func _fp_streak(pos: Vector2, dir: Vector2, glyph: String, color: Color, count: int,
		length: float = 0.7, lifetime: float = 0.18,
		pixel_size: float = 0.010, y: float = 0.50) -> void:
	if GameState.active_rig != null and is_instance_valid(GameState.active_rig) \
			and GameState.active_rig.has_method("spawn_streak_2d"):
		GameState.active_rig.spawn_streak_2d(pos, dir, glyph, color, count,
			length, lifetime, pixel_size, y)

func _fp_ring(pos: Vector2, glyph: String, color: Color,
		start_radius: float, end_radius: float,
		segments: int = 16, lifetime: float = 0.30,
		pixel_size: float = 0.009, y: float = 0.40) -> void:
	if GameState.active_rig != null and is_instance_valid(GameState.active_rig) \
			and GameState.active_rig.has_method("spawn_ring_2d"):
		GameState.active_rig.spawn_ring_2d(pos, glyph, color, start_radius, end_radius,
			segments, lifetime, pixel_size, y)

func _fp_chain(from_2d: Vector2, to_2d: Vector2, color: Color,
		lifetime: float = 0.35) -> void:
	# The rig now draws chain arcs as a 3D box stretched between the two
	# points (the ASCII post-shader pixelates it into a line). Only color
	# + lifetime matter at the wrapper layer; segment/glyph args are
	# vestigial and left out for clarity.
	if GameState.active_rig != null and is_instance_valid(GameState.active_rig) \
			and GameState.active_rig.has_method("spawn_chain_arc_2d"):
		GameState.active_rig.spawn_chain_arc_2d(from_2d, to_2d, color, 0, lifetime)

# Canonical per-shoot-type color. SINGLE source of truth shared by the 2D
# glyph (_apply_visual), the FP billboard (registration), and the trail/impact
# particles (_get_proj_color) so a type's trail always matches its projectile.
func _type_color(stype: String) -> Color:
	match stype:
		"regular":    return Color(0.95, 0.95, 0.95)
		"pierce":     return Color(0.55, 0.85, 1.0)
		"ricochet":   return Color(0.20, 1.0, 0.35)
		"freeze":     return Color(0.55, 0.92, 1.0)
		"fire":       return Color(1.0, 0.42, 0.08)
		"shock":      return Color(1.0, 0.92, 0.20)
		"beam":       return Color(0.3, 1.0, 0.8)
		"shotgun":    return Color(0.85, 0.85, 0.85)
		"homing":     return Color(1.0, 0.40, 0.80)
		"nova":       return Color(0.70, 0.0, 1.0)
		"nova_shard": return Color(0.85, 0.30, 1.0)
		"arc":        return Color(1.0, 0.55, 0.15)
		"grenade":    return Color(1.0, 0.45, 0.15)
		"missile":    return Color(1.0, 0.20, 0.10)
	return Color(0.72, 0.72, 0.88)

func _get_proj_color() -> Color:
	# Trail/impact particles use the same palette as the projectile so each
	# attack type's trail matches its shot.
	return _type_color(shoot_type)

func _spawn_trail_marker() -> void:
	if not is_inside_tree():
		return
	var col := _get_proj_color()
	var fade := 0.15 if shoot_type in ["fire", "freeze", "homing"] else 0.1
	if GameState.render_mode == GameState.RenderMode.TOPDOWN:
		var dot := ColorRect.new()
		dot.size = Vector2(4.0, 4.0)
		dot.color = Color(col.r, col.g, col.b, 0.55)
		dot.position = global_position - Vector2(2.0, 2.0)
		get_tree().current_scene.add_child(dot)
		var tw := dot.create_tween()
		tw.tween_property(dot, "modulate:a", 0.0, fade)
		tw.tween_callback(dot.queue_free)
	else:
		# FP trail — one tiny billboard per emission, no drift, fades in
		# place. Spawned at fp_height (matches player projectile height)
		# so the trail strings along below the crosshair. All shoot types
		# use the same "." trail glyph so shock no longer reads visually
		# different from the others (color still distinguishes it).
		if GameState.active_rig != null and is_instance_valid(GameState.active_rig) \
				and GameState.active_rig.has_method("spawn_burst_2d"):
			var trail_y: float = 0.22 if source == "player" else 0.50
			GameState.active_rig.spawn_burst_2d(global_position, ".",
				Color(col.r, col.g, col.b, 0.55), 1, 0.0, fade,
				Vector2.ZERO, TAU, 0.006, trail_y)

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
	for i in 2:
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
	_fp_burst(pos, ".", col.lightened(0.25), 2, 0.6, 0.18)

func _impact_pierce(pos: Vector2) -> void:
	var col := Color(0.25, 0.60, 1.0)
	var perp := direction.rotated(PI * 0.5)
	for i in 2:
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
	# FP streak glyph matches the pierce projectile ")".
	_fp_streak(pos, direction, ")", col, 2, 0.9, 0.18, 0.008, 0.10)

func _impact_ricochet(pos: Vector2) -> void:
	var col := Color(0.35, 1.0, 0.50)
	for i in 3:
		var c := ColorRect.new()
		c.size = Vector2(3.0, 3.0)
		c.color = col
		c.position = pos
		get_tree().current_scene.add_child(c)
		var angle := (TAU / 3.0) * float(i)
		var target := pos + Vector2(cos(angle), sin(angle)) * 22.0
		var tw := c.create_tween()
		tw.tween_property(c, "position", target, 0.22)
		tw.parallel().tween_property(c, "modulate:a", 0.0, 0.22)
		tw.tween_callback(c.queue_free)
	_fp_burst(pos, "o", col, 2, 0.7, 0.20, Vector2.ZERO, TAU, 0.008, 0.30)

func _impact_freeze(pos: Vector2) -> void:
	var col := Color(0.65, 0.92, 1.0)
	for i in 3:
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
	_fp_burst(pos, "*", col, 2, 0.75, 0.24, Vector2.ZERO, TAU, 0.008, 0.30)

func _impact_fire(pos: Vector2) -> void:
	# 2D: brief flame frame on the enemy (was 3 scattered chars). FP: a
	# single "(((" flame frame at chest height so the hit reads as "this
	# thing just ignited" instead of generic spark noise.
	var col := Color(1.0, 0.4, 0.05)
	var flame_lbl := Label.new()
	flame_lbl.text = "(((\n) ("
	flame_lbl.add_theme_color_override("font_color", col)
	flame_lbl.add_theme_color_override("font_outline_color", Color(0.45, 0.05, 0.0))
	flame_lbl.add_theme_constant_override("outline_size", 2)
	flame_lbl.add_theme_font_size_override("font_size", 14)
	flame_lbl.add_theme_constant_override("line_separation", -3)
	flame_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flame_lbl.size = Vector2(32.0, 28.0)
	flame_lbl.position = pos + Vector2(-16.0, -22.0)
	get_tree().current_scene.add_child(flame_lbl)
	var flame_tw := flame_lbl.create_tween()
	flame_tw.tween_property(flame_lbl, "modulate:a", 0.0, 0.30)
	flame_tw.tween_callback(flame_lbl.queue_free)
	# Glyph matches the fire projectile (@) so all fire feedback reads
	# consistently. Was "(((". One label per impact + smaller pixel_size
	# keeps the visual subtle when many shots land in quick succession.
	_fp_burst(pos, "@", col, 1, 0.0, 0.26, Vector2.ZERO, TAU, 0.009, 0.40)

func _impact_shock(pos: Vector2) -> void:
	# Lightning fork — 2 jagged arcs (was 3) branching out. Yellow to match
	# the recolored shock projectile.
	var fp_col := Color(1.0, 0.92, 0.20)
	for i in 2:
		var arc := Line2D.new()
		arc.width = 2.0
		arc.default_color = Color(1.0, 0.92, 0.20, 1.0)
		var angle := (TAU / 2.0) * float(i) + randf_range(-0.5, 0.5)
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
		_fp_chain(pos, end_pt, fp_col)

func _impact_shotgun(pos: Vector2) -> void:
	var col := Color(1.0, 0.85, 0.10)
	for i in 3:
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
	_fp_burst(pos, "#", col, 2, 0.85, 0.16, direction, deg_to_rad(80.0), 0.008, 0.20)

func _impact_homing(pos: Vector2) -> void:
	# Pulse ring — expanding circle outline. Updated palette: homing is hot
	# pink, not purple (purple now means shock/nova).
	var col := Color(1.0, 0.40, 0.80)
	var holder := Node2D.new()
	holder.global_position = pos
	var ring := Line2D.new()
	ring.width = 2.0
	ring.default_color = col
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
	# Homing's projectile glyph is "^"; mirror it on impact.
	_fp_ring(pos, "^", col, 0.20, 0.6, 10, 0.24, 0.008, 0.20)

func _impact_nova(pos: Vector2) -> void:
	# 4-directional sparks (halved from 8 for perf). 2D only — FP skips the
	# extra burst because the 16 shard projectiles spawned by _detonate_nova
	# carry the visual punch on their own.
	var col := Color(0.85, 0.30, 1.0)
	for i in 4:
		var c := ColorRect.new()
		c.size = Vector2(3.0, 3.0)
		c.color = col
		c.position = pos
		get_tree().current_scene.add_child(c)
		var angle := (TAU / 4.0) * float(i)
		var target := pos + Vector2(cos(angle), sin(angle)) * 18.0
		var tw := c.create_tween()
		tw.tween_property(c, "position", target, 0.20)
		tw.parallel().tween_property(c, "modulate:a", 0.0, 0.20)
		tw.tween_callback(c.queue_free)

func _spawn_death_pop(pos: Vector2) -> void:
	if not is_inside_tree():
		return
	var col := _get_proj_color()
	for i in 2:
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
	# FP mirror — single "x_x" in black at chest height to replace the
	# enemy character on death. Matches EffectFx.spawn_death_pop's marker.
	if GameState.active_rig != null and is_instance_valid(GameState.active_rig) \
			and GameState.active_rig.has_method("spawn_burst_2d"):
		GameState.active_rig.spawn_burst_2d(pos, "x_x", Color(0, 0, 0), 1, 0.0, 0.30,
			Vector2.ZERO, TAU, 0.011, 0.55)
