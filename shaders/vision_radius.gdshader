shader_type canvas_item;

// 2D top-down vision-radius mask. Paints a screen-space ColorRect with
// alpha = 0 in a circle around the player's screen position and
// smooth-step ramping to `max_darkness` past the radius. World.gd writes
// `player_px` each frame and toggles ColorRect.visible based on render
// mode (TOPDOWN only).

uniform vec2  player_px    = vec2(0.0);   // player's screen pixel position
uniform float radius_px    = 220.0;       // fully-visible inner radius (px)
uniform float fade_px      = 140.0;       // soft falloff width past the radius
uniform float max_darkness = 0.92;        // alpha clamp at the periphery

void fragment() {
	float d = distance(FRAGCOORD.xy, player_px);
	float t = clamp((d - radius_px) / max(fade_px, 1.0), 0.0, 1.0);
	// smoothstep-style ease for a less harsh edge.
	float a = t * t * (3.0 - 2.0 * t) * max_darkness;
	COLOR = vec4(0.0, 0.0, 0.0, a);
}
