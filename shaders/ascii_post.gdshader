shader_type canvas_item;

// Converts the SubViewport's low-res raster into a cell-aligned ASCII-density
// pattern. For each output fragment:
//   1. Determine which character cell it belongs to
//   2. Sample the brightness of that cell from the source viewport
//   3. Draw a procedural glyph whose density matches that brightness
//
// v1 uses procedural glyph patterns (dots / crosses / hashes / blocks) keyed
// by brightness — readable as "ASCII" without needing a font-atlas texture.
// A future polish pass can swap this for atlas sampling from JetBrains Mono.

uniform float cell_px = 8.0;
uniform vec2  viewport_size = vec2(200.0, 80.0);
// Radial "blinded" vignette — 0.0 means no darkening, 1.0 means full
// darkness everywhere except a tight center disk. Drives the periphery
// fade-to-black when a status effect (or in-world hazard) blinds the
// player. FirstPersonRig.set_blinded(amount) writes this.
uniform float darkness = 0.0;

float brightness_of(vec4 c) {
	return dot(c.rgb, vec3(0.299, 0.587, 0.114));
}

// Returns a 0..1 mask for the procedural glyph at this cell-local uv,
// shaped by the brightness bucket.
float glyph_mask(vec2 cell_uv, float b) {
	if (b < 0.06) {
		// Space — empty.
		return 0.0;
	} else if (b < 0.18) {
		// Single low pixel — like '.'
		float dx = abs(cell_uv.x - 0.5);
		float dy = abs(cell_uv.y - 0.85);
		return step(max(dx, dy), 0.10);
	} else if (b < 0.32) {
		// ':' — two stacked dots
		float dx = abs(cell_uv.x - 0.5);
		float dy1 = abs(cell_uv.y - 0.35);
		float dy2 = abs(cell_uv.y - 0.75);
		return step(max(dx, min(dy1, dy2)), 0.12);
	} else if (b < 0.48) {
		// '+' — small cross
		float h = step(abs(cell_uv.y - 0.5), 0.1) * step(abs(cell_uv.x - 0.5), 0.32);
		float v = step(abs(cell_uv.x - 0.5), 0.1) * step(abs(cell_uv.y - 0.5), 0.32);
		return clamp(h + v, 0.0, 1.0);
	} else if (b < 0.65) {
		// 'x' — diagonals
		vec2 c = cell_uv - 0.5;
		float d1 = abs(c.x + c.y);
		float d2 = abs(c.x - c.y);
		return step(min(d1, d2), 0.10) * step(max(abs(c.x), abs(c.y)), 0.42);
	} else if (b < 0.82) {
		// '#' — grid hash
		float h1 = step(abs(cell_uv.y - 0.33), 0.07);
		float h2 = step(abs(cell_uv.y - 0.66), 0.07);
		float v1 = step(abs(cell_uv.x - 0.33), 0.07);
		float v2 = step(abs(cell_uv.x - 0.66), 0.07);
		return clamp(h1 + h2 + v1 + v2, 0.0, 1.0);
	}
	// Brightest — denser '#' hash with thicker strokes but visible gutters.
	// Previously a solid block which read as blinding white once light + src
	// color compounded. Keeping cells character-shaped at max brightness
	// preserves the ASCII feel even right next to a torch / emissive entity.
	float h1 = step(abs(cell_uv.y - 0.28), 0.11);
	float h2 = step(abs(cell_uv.y - 0.72), 0.11);
	float v1 = step(abs(cell_uv.x - 0.28), 0.11);
	float v2 = step(abs(cell_uv.x - 0.72), 0.11);
	return clamp(h1 + h2 + v1 + v2, 0.0, 1.0);
}

void fragment() {
	// Screen position of this fragment in pixels.
	vec2 screen_px = FRAGCOORD.xy;
	vec2 cell_xy = floor(screen_px / cell_px);
	vec2 cell_uv = fract(screen_px / cell_px);

	// How many cells fit on the screen at this cell size.
	vec2 cells_total = floor(1.0 / SCREEN_PIXEL_SIZE / cell_px);
	// Map the cell index to a UV inside the source viewport.
	vec2 sample_uv = (cell_xy + 0.5) / cells_total;
	sample_uv = clamp(sample_uv, vec2(0.0), vec2(1.0));

	vec4 src = texture(TEXTURE, sample_uv);
	// Soft-clamp the source so emission + point light can't push pixels
	// past visible-spectrum white. Without this, walls right next to the
	// player's torch read as blinding solid blocks even with a perfect
	// glyph pattern underneath.
	src.rgb = min(src.rgb, vec3(0.85));
	float b = clamp(brightness_of(src), 0.0, 0.95);
	float mask = glyph_mask(cell_uv, b);

	// Tint the glyph by the source color (lit walls keep their warmth,
	// emissive enemies project their assigned color). Final clamp keeps
	// individual channels from saturating to pure white on the brightest
	// emissive overlap.
	vec3 col = clamp(src.rgb * mask, vec3(0.0), vec3(0.88));
	// Blinded vignette — radial darkness from screen center. At
	// darkness=0 the multiplier is 1.0 everywhere; at darkness=1 only a
	// small disk near the center survives, the rest fades to black.
	if (darkness > 0.0) {
		vec2 ndc = SCREEN_UV - vec2(0.5);
		ndc.x *= viewport_size.x / viewport_size.y;
		float r = length(ndc);
		// Inner safe radius shrinks as darkness grows; outer goes to 0.
		float inner = mix(0.55, 0.08, darkness);
		float outer = mix(0.95, 0.18, darkness);
		float vignette = 1.0 - smoothstep(inner, outer, r);
		col *= vignette;
	}
	COLOR = vec4(col, 1.0);
}
