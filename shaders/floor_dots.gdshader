shader_type canvas_item;

// Set this to the actual pixel size of the floor ColorRect from GDScript.
uniform vec2 node_size = vec2(1600.0, 900.0);

void fragment() {
	// Convert UV (0..1) to world pixel coords so dots are fixed to the world.
	vec2 world_px = UV * node_size;

	// Place a dot every 18 pixels.
	vec2 cell = mod(world_px, 18.0);
	float d = length(cell - 9.0);

	// Dot radius 2px — smooth edge with a tiny feather.
	float is_dot = 1.0 - smoothstep(1.8, 2.4, d);

	vec4 floor_col = vec4(0.033, 0.033, 0.060, 1.0);
	vec4 dot_col   = vec4(0.095, 0.095, 0.175, 1.0);

	COLOR = mix(floor_col, dot_col, is_dot);
}
