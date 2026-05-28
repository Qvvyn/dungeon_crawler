class_name BossGate

# Theme C — HP threshold gates for all bosses. Each gate is a brief
# damage-resistant window that engages when incoming damage would push
# HP past one of the thresholds at 75 / 50 / 25 %. Chip damage during a
# gate is capped at CHIP_FRAC of max_hp; only a single hit ≥ BREAK_FRAC
# of max_hp will punch through. Encourages crit-fishing / burst commits
# over passive sustained DPS during dramatic moments.
#
# Usage from a boss script:
#   var _gate := BossGate.new()
#   ...
#   _gate.tick(delta)
#   ...
#   in take_damage(amount):
#     var r := _gate.apply(amount, health, max_health)
#     if r.blocked:
#         # boss should spawn floating text "GATE!" + flash + return
#         return
#     # apply r.actual to health, fall through to death check

const DURATION: float    = 0.7
const CHIP_FRAC: float   = 0.04
const BREAK_FRAC: float  = 0.18
const GATES: Array       = [0.75, 0.50, 0.25]

var active: bool          = false
var t: float              = 0.0
var threshold_idx: int    = 0
var held_at: int          = 0

func tick(delta: float) -> void:
	if active:
		t -= delta
		if t <= 0.0:
			active = false

func _next_pct() -> float:
	if threshold_idx >= GATES.size():
		return -1.0
	return GATES[threshold_idx]

# Returns a dictionary describing how the gate handled this damage hit:
#   blocked:    true → boss should NOT apply damage / show normal floating
#               text. Caller should spawn a "GATE!" or chip indicator and
#               return early from take_damage.
#   actual:     damage value to use for floating text / animations when
#               the hit either broke through or wasn't gated.
#   new_hp:     the HP value the boss should set if blocked == true.
#   triggered:  this hit just opened a new gate (first frame of it).
#   broke:      this hit broke through an active gate (gate cleared).
func apply(amount: int, current_hp: int, max_hp: int) -> Dictionary:
	if active:
		var break_thresh: int = maxi(1, int(float(max_hp) * BREAK_FRAC))
		if amount >= break_thresh:
			active = false
			t = 0.0
			return {"blocked": false, "actual": amount, "new_hp": current_hp - amount, "triggered": false, "broke": true}
		var chip_cap: int = maxi(1, int(float(max_hp) * CHIP_FRAC))
		var capped: int = mini(amount, chip_cap)
		var new_hp: int = maxi(held_at, current_hp - capped)
		return {"blocked": true, "actual": capped, "new_hp": new_hp, "triggered": false, "broke": false}

	var gate_pct: float = _next_pct()
	if gate_pct <= 0.0:
		return {"blocked": false, "actual": amount, "new_hp": current_hp - amount, "triggered": false, "broke": false}
	var gate_hp: int = int(float(max_hp) * gate_pct)
	if current_hp > gate_hp and current_hp - amount <= gate_hp:
		held_at = gate_hp
		active = true
		t = DURATION
		threshold_idx += 1
		return {"blocked": true, "actual": amount, "new_hp": gate_hp, "triggered": true, "broke": false}
	return {"blocked": false, "actual": amount, "new_hp": current_hp - amount, "triggered": false, "broke": false}
