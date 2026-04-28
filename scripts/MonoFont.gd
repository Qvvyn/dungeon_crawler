class_name MonoFont

# Single source of truth for the project's monospace font. Bundled inside
# the project so web exports render box-drawing glyphs and ASCII art
# correctly even on machines that lack Consolas / Courier New.
#
# Drop the .ttf at FONT_PATH; the helper lazy-loads and caches it. If the
# file is missing the helper falls back to SystemFont so the editor still
# parses + runs (useful while the font is being added).

const FONT_PATH := "res://assets/fonts/JetBrainsMono-Regular.ttf"

static var _cached: Font = null

static func get_font() -> Font:
	if _cached != null:
		return _cached
	if ResourceLoader.exists(FONT_PATH):
		_cached = load(FONT_PATH) as Font
	if _cached == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Consolas", "Courier New", "Lucida Console"])
		_cached = sf
	return _cached
