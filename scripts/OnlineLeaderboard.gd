extends Node

# Talks to the Cloudflare Worker that holds the global top-10 board.
# Registered as an autoload (singleton) — see project.godot.
#
# Submits are fire-and-forget: the player's local Leaderboard already
# tracks their personal best, so a transient network failure here
# silently drops the global submission rather than blocking the death
# screen or showing an error popup. Fetches surface failures via the
# `scores_failed` signal so the UI can fall back gracefully.

# Set this to whatever Wrangler prints after `wrangler deploy`. Until it
# is set the autoload short-circuits — the game still runs offline, just
# without the global board.
const WORKER_URL := "https://wizardwalk-leaderboard.YOUR-SUBDOMAIN.workers.dev"

signal scores_received(scores: Dictionary)
signal scores_failed(reason: String)

func is_configured() -> bool:
	return not WORKER_URL.contains("YOUR-SUBDOMAIN")

func submit(player_name: String, portals: int, gold: int, damage: int) -> void:
	if not is_configured():
		return
	var clean_name: String = player_name.strip_edges().substr(0, 16)
	if clean_name.is_empty():
		return
	var payload := {
		"name":    clean_name,
		"portals": portals,
		"gold":    gold,
		"damage":  damage,
	}
	var req := HTTPRequest.new()
	add_child(req)
	# Free the node when the request finishes (success or failure).
	req.request_completed.connect(func(_r, _c, _h, _b) -> void: req.queue_free())
	var err: Error = req.request(
		WORKER_URL + "/submit",
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		JSON.stringify(payload))
	if err != OK:
		req.queue_free()

func fetch_scores() -> void:
	if not is_configured():
		scores_failed.emit("Leaderboard URL not configured")
		return
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(_on_scores_completed.bind(req))
	var err: Error = req.request(WORKER_URL + "/scores")
	if err != OK:
		req.queue_free()
		scores_failed.emit("HTTPRequest start failed: %d" % err)

func _on_scores_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, req: HTTPRequest) -> void:
	req.queue_free()
	if response_code != 200:
		scores_failed.emit("HTTP %d" % response_code)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary:
		scores_received.emit(parsed)
	else:
		scores_failed.emit("Bad JSON")
