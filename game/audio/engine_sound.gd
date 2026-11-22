class_name EngineSound
extends AudioStreamPlayer
## Procedurally generated rocket engine rumble + aerodynamic wind.
## Volume follows throttle; both engine and wind fade with air density
## (sound needs a medium) — in vacuum only a faint structure-borne hum remains.

const MIX_RATE := 22050.0
const VACUUM_FLOOR := 0.06

var _playback: AudioStreamGeneratorPlayback
var _engine_gain := 0.0
var _wind_gain := 0.0
var _target_engine := 0.0
var _target_wind := 0.0
var _lp1 := 0.0
var _lp2 := 0.0
var _brown := 0.0
var _wind_lp := 0.0
var _cutoff := 0.2
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return   # no audio device: skip the generator (avoids a playback leak warning)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.25
	stream = gen
	volume_db = -4.0
	_rng.seed = 1234
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback


## throttle_frac: actual thrust / max; air: density / sea-level density;
## q: dynamic pressure [Pa].
func set_state(throttle_frac: float, air: float, q: float, muted: bool) -> void:
	var medium := clampf(air, 0.0, 1.0)
	var transmit := lerpf(VACUUM_FLOOR, 1.0, pow(medium, 0.3) if medium > 0.0 else 0.0)
	_target_engine = 0.0 if muted else clampf(throttle_frac, 0.0, 1.0) * transmit
	_target_wind = 0.0 if muted else clampf(q / 25_000.0, 0.0, 1.0) * 0.6
	_cutoff = lerpf(0.05, 0.25, medium)  # thinner air -> more muffled


func _process(_delta: float) -> void:
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	for i in frames:
		_engine_gain += (_target_engine - _engine_gain) * 0.0004
		_wind_gain += (_target_wind - _wind_gain) * 0.0004
		var white := _rng.randf() * 2.0 - 1.0
		_brown = clampf(_brown + white * 0.02, -1.0, 1.0) * 0.998
		_lp1 += (white - _lp1) * _cutoff
		_lp2 += (_lp1 - _lp2) * _cutoff
		var crackle := 0.0
		if _rng.randf() < 0.002 * _engine_gain:
			crackle = (_rng.randf() * 2.0 - 1.0) * 0.6
		var engine := (_lp2 * 1.6 + _brown * 1.2 + crackle) * _engine_gain
		_wind_lp += (white - _wind_lp) * 0.08
		var wind := _wind_lp * _wind_gain
		var s := clampf(engine + wind, -1.0, 1.0)
		_playback.push_frame(Vector2(s, s))
