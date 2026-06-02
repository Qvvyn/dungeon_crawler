class_name MonoFont

# Single source of truth for the project's monospace font. The debug menu
# can cycle through several typefaces via GameState.font_choice so we can
# A/B test ASCII art aesthetics without restarting (takes effect on the
# next FP rig rebuild / scene reload — Label3Ds + HUD labels hold their
# font reference at creation time).
#
# To add a new bundled font: drop the .ttf into res://assets/fonts/ and
# append an entry to FONTS below. Missing files gracefully fall through
# to a SystemFont fallback, so the editor stays runnable even if a TTF
# hasn't been added yet.

const FONTS: Array = [
	{"name": "JetBrains Mono",   "path": "res://assets/fonts/JetBrainsMono-Regular.ttf",   "system": []},
	{"name": "VT323",            "path": "res://assets/fonts/VT323-Regular.ttf",           "system": []},
	{"name": "Special Elite",    "path": "res://assets/fonts/SpecialElite-Regular.ttf",    "system": []},
	{"name": "Cutive Mono",      "path": "res://assets/fonts/CutiveMono-Regular.ttf",      "system": []},
	{"name": "Share Tech Mono",  "path": "res://assets/fonts/ShareTechMono-Regular.ttf",   "system": []},
	{"name": "Major Mono",       "path": "res://assets/fonts/MajorMonoDisplay-Regular.ttf","system": []},
	{"name": "Press Start 2P",   "path": "res://assets/fonts/PressStart2P-Regular.ttf",    "system": []},
	{"name": "Consolas",         "path": "", "system": ["Consolas"]},
	{"name": "Courier New",      "path": "", "system": ["Courier New"]},
]

static var _cached: Font = null
static var _cached_choice: int = -1

static func choice_count() -> int:
	return FONTS.size()

static func choice_name(idx: int) -> String:
	var i: int = clampi(idx, 0, FONTS.size() - 1)
	return String((FONTS[i] as Dictionary).get("name", "?"))

static func current_name() -> String:
	return choice_name(GameState.font_choice)

static func get_font() -> Font:
	var choice: int = clampi(GameState.font_choice, 0, FONTS.size() - 1)
	if _cached != null and _cached_choice == choice:
		return _cached
	var entry: Dictionary = FONTS[choice] as Dictionary
	var path: String = String(entry.get("path", ""))
	var loaded: Font = null
	if path != "" and ResourceLoader.exists(path):
		loaded = load(path) as Font
	if loaded == null:
		var sf := SystemFont.new()
		var sys_names: Array = entry.get("system", []) as Array
		if sys_names.is_empty():
			# Hard fallback so the game never runs fontless.
			sys_names = ["Consolas", "Courier New", "Lucida Console"]
		sf.font_names = PackedStringArray(sys_names)
		loaded = sf
	_cached = loaded
	_cached_choice = choice
	return _cached

# Called by the debug toggle so the next get_font() picks up the new
# choice immediately. Existing Label3Ds / Labels keep their old font
# reference until rebuilt.
static func invalidate() -> void:
	_cached = null
	_cached_choice = -1
