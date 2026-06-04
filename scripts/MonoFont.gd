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
	{"name": "VT323",            "path": "res://assets/fonts/VT323-Regular.ttf",           "system": []},
	{"name": "Major Mono",       "path": "res://assets/fonts/MajorMonoDisplay-Regular.ttf","system": []},
	{"name": "Press Start 2P",   "path": "res://assets/fonts/PressStart2P-Regular.ttf",    "system": []},
	# ── 8-bit / pixel MONOSPACE picks (crunchy like Press Start 2P + VT323, but
	# narrower so complex multi-line art stays readable). Each lights up the
	# moment its .ttf is dropped into res://assets/fonts/ with the exact filename
	# below; until then MonoFont falls back to a system mono so nothing breaks.
	#   Departure Mono  - departuremono.com (free) — purpose-built pixel monospace
	#   Pixel Operator  - dafont "Pixel Operator" (free) — use the Mono variant
	{"name": "Departure Mono",   "path": "res://assets/fonts/DepartureMono-Regular.otf",   "system": []},
	{"name": "Pixel Operator Mono","path": "res://assets/fonts/PixelOperatorMono.ttf",     "system": []},
	{"name": "Spleen 8x16",      "path": "res://assets/fonts/spleen-8x16.otf",             "system": []},
	{"name": "Cozette",          "path": "res://assets/fonts/CozetteVector.ttf",           "system": []},
	{"name": "Consolas",         "path": "", "system": ["Consolas"]},
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

# Called by the debug font-cycle so the next get_font() picks up the new
# choice immediately AND any existing Label / Button / RichTextLabel /
# Label3D currently holding the old cached font reference is rewritten on
# the spot. Previously the comment here said "existing labels keep their
# old font until rebuilt" — that meant the debug cycle had no visible
# effect until F1 rebuilt the rig. Walking the scene tree once per font
# swap is cheap (we only touch nodes whose stored font is == the previous
# cached one, so labels with a deliberate non-MonoFont stay untouched).
static func invalidate() -> void:
	var old_font: Font = _cached
	_cached = null
	_cached_choice = -1
	if old_font == null:
		return
	var new_font: Font = get_font()   # rebuilds and re-caches under the new GameState.font_choice
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	_propagate(tree.root, old_font, new_font)

# Recursive walk — swaps the font on any node whose stored/overridden font
# is the prior cached MonoFont. Labels with a non-MonoFont (e.g. a per-
# character override) keep their own font.
static func _propagate(n: Node, old_font: Font, new_font: Font) -> void:
	if n is Control:
		var c := n as Control
		# Common font-override slot names actually used in this project.
		# add_theme_font_override("font", ...) is the universal one; the
		# rest cover RichTextLabel and any future variants.
		for fn in ["font", "normal_font", "bold_font", "italics_font", "bold_italics_font", "mono_font"]:
			# Control has no get_theme_font_override(); check the override exists
			# then resolve it (get_theme_font returns the override when present).
			if c.has_theme_font_override(fn) and c.get_theme_font(fn) == old_font:
				c.add_theme_font_override(fn, new_font)
	elif n is Label3D:
		if (n as Label3D).font == old_font:
			(n as Label3D).font = new_font
	for child in n.get_children():
		_propagate(child, old_font, new_font)
