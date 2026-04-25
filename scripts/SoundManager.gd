extends Node

const SAMPLE_RATE := 22050
const POOL_SIZE   := 12

var _sounds: Dictionary = {}
var _sfx_pool: Array    = []
var _music_player: AudioStreamPlayer = null

func _ready() -> void:
	_build_sounds()
	_setup_sfx_pool()
	_start_music()

# ── Public API ────────────────────────────────────────────────────────────────

func play(name: String, pitch: float = 1.0) -> void:
	if name not in _sounds:
		return
	for p in _sfx_pool:
		if not p.playing:
			p.stream = _sounds[name]
			p.pitch_scale = pitch
			p.play()
			return
	_sfx_pool[0].stream = _sounds[name]
	_sfx_pool[0].pitch_scale = pitch
	_sfx_pool[0].play()

# ── Setup ─────────────────────────────────────────────────────────────────────

func _setup_sfx_pool() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.volume_db = -4.0
		p.bus = "Master"
		add_child(p)
		_sfx_pool.append(p)

func _start_music() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.stream = _sounds.get("music")
	_music_player.volume_db = -14.0
	_music_player.bus = "Master"
	add_child(_music_player)
	if _music_player.stream != null:
		_music_player.play()

# ── Sound library ─────────────────────────────────────────────────────────────

func _build_sounds() -> void:
	_sounds["shoot"]       = _gen_zap()
	_sounds["hit"]         = _gen_dual(260.0, 278.0, 0.09, 0.25, 7.0)
	_sounds["enemy_death"] = _gen_sweep(480.0, 90.0,  0.20, 0.35)
	_sounds["player_hurt"] = _gen_buzz(150.0, 0.22, 0.42)
	_sounds["boss_roar"]   = _gen_boss_roar()
	_sounds["boss_phase"]  = _gen_sweep(360.0, 720.0, 0.3, 0.32)
	_sounds["room_clear"]  = _gen_arpeggio([523.3, 659.3, 784.0], 0.10, 0.30)
	_sounds["teleport"]    = _gen_sweep(180.0, 1400.0, 0.26, 0.28)
	_sounds["gold"]        = _gen_tone(1380.0, 0.045, 0.32, 20.0)
	_sounds["music"]       = _gen_music_loop()
	_sounds["punch"]       = _gen_punch()
	_sounds["explosion"]   = _gen_explosion()
	_sounds["whoosh"]      = _gen_whoosh()
	_sounds["beam_charge"] = _gen_sweep(120.0, 460.0, 0.42, 0.30)
	_sounds["missile"]     = _gen_missile()
	_sounds["thud"]        = _gen_tone(82.0, 0.10, 0.55, 18.0)
	_sounds["summon"]      = _gen_arpeggio([220.0, 277.2, 329.6, 415.3], 0.075, 0.28)
	_sounds["enchant"]     = _gen_sweep(220.0, 660.0, 0.32, 0.32)
	_sounds["crit"]        = _gen_dual(740.0, 1108.7, 0.10, 0.30, 9.0)
	# Per-wand-type fire sounds — all short so rapid fire doesn't stutter
	_sounds["shoot_pierce"]   = _gen_sweep(900.0, 350.0, 0.08, 0.32)
	_sounds["shoot_ricochet"] = _gen_dual(450.0, 720.0, 0.09, 0.28, 8.0)
	_sounds["shoot_freeze"]   = _gen_sweep(720.0, 220.0, 0.12, 0.28)
	_sounds["shoot_fire"]     = _gen_buzz(180.0, 0.10, 0.36)
	_sounds["shoot_shock"]    = _gen_dual(380.0, 950.0, 0.09, 0.32, 7.0)
	_sounds["shoot_shotgun"]  = _gen_buzz(120.0, 0.14, 0.55)
	_sounds["shoot_homing"]   = _gen_sweep(220.0, 540.0, 0.12, 0.28)
	_sounds["shoot_nova"]     = _gen_arpeggio([523.3, 698.5, 880.0], 0.04, 0.30)
	_sounds["beam_hum"]       = _gen_dual(180.0, 270.0, 0.34, 0.30, 0.4)
	_sounds["punch_hit"]      = _gen_tone(60.0, 0.13, 0.65, 14.0)

# ── Generators ────────────────────────────────────────────────────────────────

func _gen_tone(freq: float, duration: float, vol: float, decay: float) -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(SAMPLE_RATE)
		var env := exp(-decay * t / duration)
		var s := int(clampf(sin(TAU * freq * t) * vol * env, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, s)
	return _make_wav(data)

func _gen_dual(f1: float, f2: float, duration: float, vol: float, decay: float) -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(SAMPLE_RATE)
		var env := exp(-decay * t / duration)
		var sample := (sin(TAU * f1 * t) + sin(TAU * f2 * t)) * 0.5 * vol * env
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	return _make_wav(data)

func _gen_sweep(f_start: float, f_end: float, duration: float, vol: float) -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var progress := float(i) / float(n)
		var freq := lerpf(f_start, f_end, progress)
		phase += TAU * freq / float(SAMPLE_RATE)
		var env := 1.0 - progress
		var s := int(clampf(sin(phase) * vol * env, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, s)
	return _make_wav(data)

func _gen_buzz(freq: float, duration: float, vol: float) -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(SAMPLE_RATE)
		var vibrato := sin(TAU * 18.0 * t) * 0.12
		var env := exp(-3.5 * t / duration)
		var sample := sin(TAU * freq * (1.0 + vibrato) * t) * vol * env
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	return _make_wav(data)

func _gen_boss_roar() -> AudioStreamWAV:
	var duration := 0.55
	var n := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(SAMPLE_RATE)
		var progress := float(i) / float(n)
		var attack := minf(progress / 0.15, 1.0)
		var env := attack * (1.0 - progress * 0.6)
		var sample := (sin(TAU * 88.0 * t) * 0.5
			+ sin(TAU * 176.0 * t) * 0.28
			+ sin(TAU * 264.0 * t) * 0.14) * 0.38 * env
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	return _make_wav(data)

func _gen_arpeggio(freqs: Array, note_dur: float, vol: float) -> AudioStreamWAV:
	var total := note_dur * freqs.size()
	var n := int(SAMPLE_RATE * total)
	var data := PackedByteArray()
	data.resize(n * 2)
	for note_idx in freqs.size():
		var freq := freqs[note_idx] as float
		var i_start := int(note_idx * note_dur * SAMPLE_RATE)
		var i_end   := int((note_idx + 1) * note_dur * SAMPLE_RATE)
		for i in range(i_start, mini(i_end, n)):
			var t := float(i - i_start) / float(SAMPLE_RATE)
			var local_prog := float(i - i_start) / float(i_end - i_start)
			var env := exp(-5.0 * local_prog)
			var s := int(clampf(sin(TAU * freq * t) * vol * env, -1.0, 1.0) * 32767.0)
			data.encode_s16(i * 2, s)
	return _make_wav(data)

func _gen_music_loop() -> AudioStreamWAV:
	var loop_dur := 4.0
	var n := int(SAMPLE_RATE * loop_dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	# Bass notes (A minor, every 1.0s)
	var bass := [[0.0, 110.0], [1.0, 82.4], [2.0, 110.0], [3.0, 130.8]]
	for entry in bass:
		var t0 := entry[0] as float
		var freq := entry[1] as float
		var i0 := int(t0 * SAMPLE_RATE)
		var i1 := mini(i0 + int(0.20 * SAMPLE_RATE), n)
		for i in range(i0, i1):
			var t := float(i - i0) / float(SAMPLE_RATE)
			var prog := float(i - i0) / float(i1 - i0)
			buf[i] += sin(TAU * freq * t) * 0.28 * exp(-4.0 * prog)
	# Melody (A minor, offset 0.5s)
	var melody := [
		[0.5,  329.6], [1.0, 392.0], [1.5, 440.0],
		[2.0,  392.0], [2.5, 349.2], [3.0, 329.6],
		[3.5,  293.7],
	]
	for entry in melody:
		var t0 := entry[0] as float
		var freq := entry[1] as float
		var i0 := int(t0 * SAMPLE_RATE)
		var i1 := mini(i0 + int(0.10 * SAMPLE_RATE), n)
		for i in range(i0, i1):
			var t := float(i - i0) / float(SAMPLE_RATE)
			var prog := float(i - i0) / float(i1 - i0)
			buf[i] += sin(TAU * freq * t) * 0.10 * exp(-6.0 * prog)
	# Convert float buf to PCM bytes
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var wav := _make_wav(data)
	wav.loop_mode  = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end   = n - 1
	return wav

func _gen_zap() -> AudioStreamWAV:
	# FM synthesis: carrier swept 560→200 Hz, modulated at 2.1× for a "magical zap"
	var duration := 0.10
	var n := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase_c := 0.0
	var phase_m := 0.0
	for i in n:
		var progress := float(i) / float(n)
		var carrier_freq := lerpf(560.0, 200.0, progress)
		var mod_freq     := carrier_freq * 2.1
		var mod_index    := lerpf(4.8, 0.4, progress)  # harmonics fade as pitch drops
		var attack := minf(float(i) / float(int(0.004 * SAMPLE_RATE)), 1.0)
		var env    := attack * exp(-9.0 * progress)
		phase_c += TAU * carrier_freq / float(SAMPLE_RATE)
		phase_m += TAU * mod_freq     / float(SAMPLE_RATE)
		var sample := sin(phase_c + mod_index * sin(phase_m)) * 0.40 * env
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	return _make_wav(data)

func _gen_punch() -> AudioStreamWAV:
	# Layered: sharp high click → low body thud → noise crackle
	var duration := 0.18
	var n := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(n * 2)
	var noise_seed := 13579
	for i in n:
		var t := float(i) / float(SAMPLE_RATE)
		var prog := float(i) / float(n)
		var click_env := exp(-70.0 * prog)
		var click := sin(TAU * 1450.0 * t) * 0.42 * click_env
		var thud_env := exp(-7.5 * prog)
		var thud := (sin(TAU * 88.0 * t) * 0.7 + sin(TAU * 160.0 * t) * 0.35) * thud_env
		noise_seed = (noise_seed * 1103515245 + 12345) & 0x7FFFFFFF
		var noise := float((noise_seed % 1024) - 512) / 512.0 * 0.30 * exp(-12.0 * prog)
		var sample := (click + thud + noise) * 0.7
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	return _make_wav(data)

func _gen_explosion() -> AudioStreamWAV:
	# Low rumble + noise crackle, sharp attack, exponential decay
	var duration := 0.45
	var n := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(n * 2)
	var noise_seed := 12345
	for i in n:
		var t := float(i) / float(SAMPLE_RATE)
		var prog := float(i) / float(n)
		var attack := minf(prog / 0.015, 1.0)
		var env := attack * exp(-4.5 * prog)
		# Layered low rumble
		var rumble := sin(TAU * 58.0 * t) * 0.55 + sin(TAU * 92.0 * t) * 0.30
		# Pseudo-random noise crackle
		noise_seed = (noise_seed * 1103515245 + 12345) & 0x7FFFFFFF
		var noise := float((noise_seed % 1024) - 512) / 512.0 * 0.4
		var sample := (rumble + noise) * 0.5 * env
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	return _make_wav(data)

func _gen_whoosh() -> AudioStreamWAV:
	# Filtered noise sweep — pitch perceived via amplitude modulation
	var duration := 0.18
	var n := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(n * 2)
	var noise_seed := 67890
	for i in n:
		var prog := float(i) / float(n)
		var attack := minf(prog / 0.04, 1.0)
		var release := 1.0 - clampf((prog - 0.5) / 0.5, 0.0, 1.0)
		var env := attack * release
		noise_seed = (noise_seed * 1103515245 + 12345) & 0x7FFFFFFF
		var noise := float((noise_seed % 1024) - 512) / 512.0
		# Modulate by a slow sweep so it perceives as pitched whoosh
		var t := float(i) / float(SAMPLE_RATE)
		var sweep_freq := lerpf(180.0, 540.0, prog)
		var carrier := sin(TAU * sweep_freq * t) * 0.3
		var sample := (noise * 0.6 + carrier * 0.4) * env * 0.4
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	return _make_wav(data)

func _gen_missile() -> AudioStreamWAV:
	# Lower, longer FM zap with sustained body — distinct from regular "shoot"
	var duration := 0.22
	var n := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase_c := 0.0
	var phase_m := 0.0
	for i in n:
		var prog := float(i) / float(n)
		var carrier_freq := lerpf(320.0, 90.0, prog)
		var mod_freq     := carrier_freq * 1.7
		var mod_index    := lerpf(3.0, 1.5, prog)
		var attack := minf(float(i) / float(int(0.005 * SAMPLE_RATE)), 1.0)
		var env := attack * exp(-3.5 * prog)
		phase_c += TAU * carrier_freq / float(SAMPLE_RATE)
		phase_m += TAU * mod_freq     / float(SAMPLE_RATE)
		var sample := sin(phase_c + mod_index * sin(phase_m)) * 0.42 * env
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	return _make_wav(data)

func _make_wav(data: PackedByteArray) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format   = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo   = false
	wav.data     = data
	return wav
