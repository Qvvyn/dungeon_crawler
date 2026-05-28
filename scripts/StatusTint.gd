class_name StatusTint

# Shared status-tint colors for enemies. Centralizes the frozen + shock/stun
# flashes so every enemy script (EnemyBase + the bosses and the
# CharacterBody2D-direct family that each duplicate _get_status_modulate)
# reads from one source.

# Frozen — flash between a saturated icy blue and white so the enemy reads
# as actively iced over rather than a static blue tint.
static func frozen() -> Color:
	var fz := sin(Time.get_ticks_msec() * 0.013) * 0.5 + 0.5
	return Color(0.55, 0.85, 1.0).lerp(Color(1.0, 1.0, 1.0), fz)

# Shocked / stunned — flash between yellow and white (was a static pale
# yellow that read as plain white).
static func stun() -> Color:
	var sf := sin(Time.get_ticks_msec() * 0.018) * 0.5 + 0.5
	return Color(1.0, 1.0, 0.25).lerp(Color(1.0, 1.0, 1.0), sf)
