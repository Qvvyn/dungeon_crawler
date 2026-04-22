shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear;
uniform float scanline_opacity : hint_range(0.0, 0.5) = 0.13;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.30;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec4 col = texture(SCREEN_TEXTURE, uv);

	// Alternating scanlines every other pixel row
	float scan = mod(floor(uv.y * 900.0), 2.0);
	col.rgb *= 1.0 - scan * scanline_opacity * 2.0;

	// Soft vignette
	vec2 vig = uv * 2.0 - 1.0;
	float vignette = 1.0 - dot(vig * 0.5, vig * 0.5) * vignette_strength;
	col.rgb *= clamp(vignette, 0.0, 1.0);

	COLOR = col;
}
