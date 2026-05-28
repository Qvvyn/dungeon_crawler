class_name EnemyVision

# Shared line-of-sight test for ranged enemies. Raycasts from the shooter
# to the target on the wall layer (layer 1); returns false when a wall
# blocks the shot so enemies don't fire blindly through walls. The ray
# excludes the shooter itself.
static func has_los(shooter: Node2D, target_pos: Vector2) -> bool:
	if not is_instance_valid(shooter):
		return false
	var space := shooter.get_world_2d().direct_space_state
	var params := PhysicsRayQueryParameters2D.create(shooter.global_position, target_pos)
	params.collision_mask = 1   # walls / static geometry only
	params.exclude = [shooter.get_rid()]
	var hit := space.intersect_ray(params)
	# Empty hit = clear sightline. A hit means a wall is in the way.
	return hit.is_empty()
