extends Node3D
## Composition root: owns the simulation, routes input, drives the fixed-step
## loop (time warp = more fixed sub-steps per tick) and feeds the views.
##
## Command-line (after `--`): --preset=pad|orbit|transfer  --warp=1|5|10|50
##   --autopilot  --no-intro  --quit-after=<sim seconds>  (prints RESULT json)
##   --showcase  (starts the automatic presentation)
##   --map  --screenshot=<png path> [--shot-frame=N]  (saves a frame, then quits)

const WARPS := [1, 5, 10, 50]
const ROT_RATE := deg_to_rad(22.0)     ## [rad/s real time] manual pitch/yaw rate
const HOLD_RATE := deg_to_rad(30.0)    ## [rad/s] attitude-hold slew rate
const THROTTLE_RATE := 0.6             ## [1/s] Shift/Ctrl throttle change
const PREDICT_EVERY := 6               ## physics ticks between predictions

enum Hold { NONE, PROGRADE, RETROGRADE }
enum Showcase { OFF, READY, FLIGHT, COMPLETE, FAILED }

const SHOWCASE_READY_SECONDS := 2.5
const SHOWCASE_LAUNCH_SECONDS := 4.0
const SHOWCASE_LIMIT := 600.0

var cfg := SimConfig.new()
var rocket_cfg := SimConfig.new()       ## pending rocket parameters from the UI
var sim: OrbitalSim
var predictor := TrajectoryPredictor.new()
var prediction: Dictionary = {}
var autopilot: AscentAutopilot = null
var warp_index := 0
var paused := false
var hold: int = Hold.NONE

var world: WorldView
var rocket_view: RocketView
var trajectory: TrajectoryView
var cams: CameraRig
var sound: EngineSound
var hud: Hud
var settings: SettingsPanel

# previous physics state for render interpolation
var _prev := PackedFloat64Array([0, 0, 0, 0])
var _cur := PackedFloat64Array([0, 0, 0, 0])
var _tick := 0
var _predict_dirty := true
var _quit_after := -1.0
var _last_acc := Vector3.ZERO
var _shot_path := ""
var _shot_frame := 120
var _frame := 0
var _showcase := Showcase.OFF
var _showcase_countdown := 0.0
var _sandbox: Dictionary = {}


func _ready() -> void:
	sim = OrbitalSim.new(cfg)
	sim.event_happened.connect(_on_sim_event)

	world = WorldView.new()
	add_child(world)
	trajectory = TrajectoryView.new()
	world.planet_frame.add_child(trajectory)
	rocket_view = RocketView.new()
	add_child(rocket_view)
	cams = CameraRig.new()
	add_child(cams)
	sound = EngineSound.new()
	add_child(sound)

	var layer := CanvasLayer.new()
	add_child(layer)
	var ui_root := Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.theme = UiKit.make_theme()
	layer.add_child(ui_root)
	hud = Hud.new()
	ui_root.add_child(hud)
	settings = SettingsPanel.new()
	ui_root.add_child(settings)
	settings.setup(cfg, rocket_cfg, sim)

	hud.warp_requested.connect(_set_warp)
	hud.pause_toggled.connect(_toggle_pause)
	hud.camera_toggled.connect(cams.toggle_mode)
	hud.preset_requested.connect(_apply_preset)
	hud.showcase_requested.connect(_start_showcase)
	hud.showcase_exited.connect(_exit_showcase)
	hud.showcase_pause_toggled.connect(_toggle_showcase_pause)
	settings.preset_requested.connect(_apply_preset)
	settings.autopilot_toggled.connect(_start_autopilot)
	settings.world_changed.connect(func(): _predict_dirty = true)
	settings.rocket_changed.connect(_on_rocket_edit)

	_parse_args()
	_sync_prev()


func _parse_args() -> void:
	var showcase_requested := false
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		var key := kv[0]
		var val := kv[1] if kv.size() > 1 else ""
		match key:
			"preset": _apply_preset(val)
			"warp":
				var w := WARPS.find(int(val))
				if w >= 0:
					_set_warp(w)
			"autopilot": _start_autopilot()
			"showcase": showcase_requested = true
			"no-intro": hud.hide_intro()
			"quit-after": _quit_after = float(val)
			"map": cams.set_mode(CameraRig.Mode.MAP)
			"screenshot": _shot_path = val; hud.hide_intro()
			"shot-frame": _shot_frame = int(val)
	if _quit_after > 0.0:
		hud.hide_intro()
	if showcase_requested:
		_start_showcase()


# ------------------------------------------------------------------ actions

func _apply_preset(name: String) -> void:
	_copy_rocket_config()
	autopilot = null
	hold = Hold.NONE
	match name:
		"orbit": sim.set_circular_orbit()
		"transfer": sim.set_moon_transfer()
		_: sim.reset_to_pad()
	hud.hide_outcome()
	hud.hide_intro()
	_sync_prev()
	_predict_dirty = true
	settings.update_lock_note()


func _start_autopilot() -> void:
	_apply_preset("pad")
	autopilot = AscentAutopilot.new(sim)
	hud.toast("Launch autopilot engaged — any control key takes over", UiKit.ACCENT)


func _copy_rocket_config() -> void:
	for k in ["dry_mass", "fuel_capacity", "max_thrust", "isp", "cd", "area"]:
		cfg.set(k, rocket_cfg.get(k))


func _on_rocket_edit() -> void:
	if sim.is_on_pad():
		_copy_rocket_config()
		sim.apply_rocket_config_if_on_pad()
	_predict_dirty = true
	settings.update_lock_note()


func _set_warp(i: int) -> void:
	warp_index = clampi(i, 0, WARPS.size() - 1)


func _toggle_pause() -> void:
	paused = not paused


func _start_showcase() -> void:
	if _showcase == Showcase.OFF:
		_sandbox = {
			"sim": sim, "autopilot": autopilot, "warp": warp_index, "paused": paused,
			"hold": hold, "acceleration": _last_acc, "settings_visible": settings.visible,
			"camera_mode": cams.mode, "focus": cams.focus,
			"chase": Vector3(cams.chase_yaw, cams.chase_pitch, cams.chase_dist),
			"map": Vector3(cams.map_yaw, cams.map_pitch, cams.map_dist),
		}
		hud.set_showcase(true)
		settings.hide()
		settings.toggle_button.hide()
	# A separate simulation leaves the sandbox and its pending rocket settings intact.
	cfg = SimConfig.new()
	sim = OrbitalSim.new(cfg)
	sim.event_happened.connect(_on_sim_event)
	autopilot = null
	hold = Hold.NONE
	paused = false
	_last_acc = Vector3.ZERO
	_showcase = Showcase.READY
	_showcase_countdown = SHOWCASE_READY_SECONDS
	warp_index = 0
	cams.set_mode(CameraRig.Mode.CHASE)
	cams.focus = CameraRig.Focus.PLANET
	cams.chase_yaw = deg_to_rad(205.0)
	cams.chase_pitch = deg_to_rad(8.0)
	cams.set_chase_distance(70.0)
	cams.map_yaw = 0.0
	cams.map_pitch = deg_to_rad(40.0)
	cams.map_dist = 1_850_000.0
	_sync_prev()
	_predict_dirty = true


func _exit_showcase() -> void:
	if _showcase == Showcase.OFF:
		return
	sim = _sandbox.sim
	cfg = sim.cfg
	autopilot = _sandbox.autopilot
	warp_index = _sandbox.warp
	paused = _sandbox.paused
	hold = _sandbox.hold
	_last_acc = _sandbox.acceleration
	cams.set_mode(_sandbox.camera_mode)
	cams.focus = _sandbox.focus
	var chase: Vector3 = _sandbox.chase
	var map_pose: Vector3 = _sandbox.map
	cams.chase_yaw = chase.x
	cams.chase_pitch = chase.y
	cams.set_chase_distance(chase.z)
	cams.map_yaw = map_pose.x
	cams.map_pitch = map_pose.y
	cams.map_dist = map_pose.z
	settings.visible = _sandbox.settings_visible
	settings.toggle_button.show()
	hud.set_showcase(false)
	_showcase = Showcase.OFF
	_sandbox.clear()
	_sync_prev()
	_predict_dirty = true


func _toggle_showcase_pause() -> void:
	if _showcase == Showcase.READY or _showcase == Showcase.FLIGHT:
		paused = not paused


func _advance_showcase(delta: float) -> void:
	if paused:
		return
	if _showcase == Showcase.READY:
		_showcase_countdown -= delta
		if _showcase_countdown <= 0.0:
			_showcase = Showcase.FLIGHT
			autopilot = AscentAutopilot.new(sim)
	if _showcase == Showcase.FLIGHT:
		match autopilot.phase:
			AscentAutopilot.Phase.ASCENT:
				_set_warp(0 if sim.t < SHOWCASE_LAUNCH_SECONDS else 2)
			AscentAutopilot.Phase.COAST:
				cams.set_mode(CameraRig.Mode.MAP)
				_set_warp(2)
			AscentAutopilot.Phase.CIRCULARIZE:
				_set_warp(1)


func _finish_showcase(autopilot_succeeded: bool) -> void:
	var stable: bool = autopilot_succeeded and predictor.predict(sim).kind == TrajectoryPredictor.Kind.ORBIT_STABLE
	_showcase = Showcase.COMPLETE if stable else Showcase.FAILED
	autopilot = null
	sim.set_throttle(0.0)
	warp_index = 0
	paused = true
	_predict_dirty = true
	if stable:
		cams.set_mode(CameraRig.Mode.MAP)


func _update_showcase_card() -> void:
	match _showcase:
		Showcase.READY:
			hud.update_showcase("Launch from the pad", "The rocket lifts off automatically in %d s." % ceili(_showcase_countdown), paused, false)
		Showcase.FLIGHT:
			match autopilot.phase:
				AscentAutopilot.Phase.ASCENT:
					hud.update_showcase("Ascent", "The rocket climbs and pitches over to build speed along the surface.", paused, false)
				AscentAutopilot.Phase.COAST:
					hud.update_showcase("Trajectory forecast", "The engine is off. The line on the map shows the predicted coast to apoapsis.", paused, false)
				AscentAutopilot.Phase.CIRCULARIZE:
					hud.update_showcase("Circularisation", "The engine adds speed along the path until the lowest point of the orbit is above the atmosphere.", paused, false)
		Showcase.COMPLETE:
			var el := sim.orbit_elements()
			hud.update_showcase("Stable orbit", "Pe %s  ·  Ap %s  ·  Fuel %.0f kg" % [
				UiKit.fmt_alt(el.rp - el.body_radius), UiKit.fmt_alt(el.ra - el.body_radius), sim.fuel,
			], false, true)
		Showcase.FAILED:
			hud.update_showcase("Flight aborted", "The rocket did not reach a stable orbit. Replay the showcase or return to the game.", false, true)


func _on_sim_event(kind: String, message: String) -> void:
	_predict_dirty = true
	if _showcase != Showcase.OFF:
		return
	if hud == null:
		return
	match kind:
		"crash":
			warp_index = 0
			hud.toast(message, UiKit.BAD, 6.0)
			hud.show_outcome("Crash", message + "\nR — reset to the pad,  O — 100 km orbit", false)
		"hard_landing":
			warp_index = 0
			hud.toast(message, UiKit.WARN, 6.0)
			hud.show_outcome("Hard landing", message + "\nR — reset,  O — orbit", false)
		"landed":
			warp_index = 0
			hud.toast(message, UiKit.GOOD, 6.0)
			if sim.landed_body == OrbitalSim.Body.MOON:
				hud.show_outcome("Landed on Ślęża!", message, true)
		"liftoff", "fuel_out":
			hud.toast(message, UiKit.WARN if kind == "fuel_out" else UiKit.GOOD)
			settings.update_lock_note()
		"atmo_exit", "atmo_enter", "preset":
			hud.toast(message, UiKit.ACCENT)
		_:
			pass


# ------------------------------------------------------------------ input

## Tab is also GUI focus navigation; intercept plain Tab before the GUI so the
## settings shortcut works even after a HUD button took focus (Shift+Tab stays GUI).
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F3:
		_start_showcase()
		get_viewport().set_input_as_handled()
	elif _showcase != Showcase.OFF:
		match key.keycode:
			KEY_ESCAPE: _exit_showcase()
			KEY_P: _toggle_showcase_pause()
			_: return
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_TAB and not key.shift_pressed:
		settings.visible = not settings.visible
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _showcase != Showcase.OFF:
		return
	if cams.handle_input(event):
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = (event as InputEventKey).keycode
	if hud.intro_visible() and (k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE):
		hud.hide_intro()
		return
	match k:
		KEY_P, KEY_ESCAPE: _toggle_pause()
		KEY_R: _apply_preset("pad")
		KEY_O: _apply_preset("orbit")
		KEY_K: _apply_preset("transfer")
		KEY_F2: _start_autopilot()
		KEY_C, KEY_M: cams.toggle_mode()
		KEY_F: cams.cycle_focus()
		KEY_F1: hud.toggle_help()
		KEY_1, KEY_2, KEY_3, KEY_4: _set_warp(k - KEY_1)
		KEY_COMMA, KEY_BRACKETLEFT: _set_warp(warp_index - 1)
		KEY_PERIOD, KEY_BRACKETRIGHT: _set_warp(warp_index + 1)
		KEY_Z: _manual(); sim.set_throttle(1.0)
		KEY_X: _manual(); sim.set_throttle(0.0)
		KEY_T: _manual(); hold = Hold.NONE if hold == Hold.PROGRADE else Hold.PROGRADE
		KEY_G: _manual(); hold = Hold.NONE if hold == Hold.RETROGRADE else Hold.RETROGRADE
	get_viewport().set_input_as_handled()


func _manual() -> void:
	if autopilot != null:
		autopilot = null
		hud.toast("Autopilot off — manual control", UiKit.WARN)


func _continuous_controls(delta: float) -> void:
	var pitch := 0.0
	var yaw := 0.0
	if Input.is_key_pressed(KEY_W): pitch += 1.0
	if Input.is_key_pressed(KEY_S): pitch -= 1.0
	if Input.is_key_pressed(KEY_A): yaw += 1.0
	if Input.is_key_pressed(KEY_D): yaw -= 1.0
	if pitch != 0.0 or yaw != 0.0:
		_manual()
		hold = Hold.NONE
		sim.rotate_pitch_yaw(pitch * ROT_RATE * delta, yaw * ROT_RATE * delta)
	var dthr := 0.0
	if Input.is_key_pressed(KEY_SHIFT): dthr += 1.0
	if Input.is_key_pressed(KEY_CTRL): dthr -= 1.0
	if dthr != 0.0:
		_manual()
		sim.set_throttle(sim.throttle + dthr * THROTTLE_RATE * delta)


func _apply_hold(dt: float) -> void:
	if hold == Hold.NONE or sim.status != OrbitalSim.Status.FLYING:
		return
	var v := sim.velocity()
	if sim.in_moon_soi():
		v -= sim.moon_velocity()
	if v.length() < 1.0:
		return
	sim.turn_towards(v if hold == Hold.PROGRADE else -v, HOLD_RATE * dt)


# ------------------------------------------------------------------ loop

func _physics_process(delta: float) -> void:
	_sync_prev()
	if _showcase == Showcase.OFF:
		if not paused and (not hud.intro_visible() or _quit_after > 0.0):
			_continuous_controls(delta)
	else:
		_advance_showcase(delta)
	if not paused and _showcase != Showcase.READY:
		var v0 := sim.velocity()
		var t0 := sim.t
		for i in WARPS[warp_index]:
			if autopilot != null:
				autopilot.update(OrbitalSim.DT)
			_apply_hold(OrbitalSim.DT)
			sim.step(OrbitalSim.DT)
		var el := sim.t - t0
		if el > 0.0:
			_last_acc = (sim.velocity() - v0) / el
		if autopilot != null and autopilot.phase >= AscentAutopilot.Phase.DONE:
			if _showcase == Showcase.FLIGHT:
				_finish_showcase(autopilot.phase == AscentAutopilot.Phase.DONE)
			else:
				hud.toast("Autopilot: " + autopilot.phase_name(), UiKit.GOOD if autopilot.phase == AscentAutopilot.Phase.DONE else UiKit.BAD)
				autopilot = null
		elif _showcase == Showcase.FLIGHT and sim.t >= SHOWCASE_LIMIT:
			_finish_showcase(false)
	_cur = PackedFloat64Array([sim.px, sim.py, sim.pz, sim.moon_angle])
	if paused:
		_prev = _cur.duplicate()

	_tick += 1
	if _predict_dirty or _tick % PREDICT_EVERY == 0:
		_predict_dirty = false
		prediction = predictor.predict(sim)
		trajectory.show_prediction(prediction, cfg.planet_radius, cams.mode == CameraRig.Mode.MAP)

	var showcase_finished := _showcase == Showcase.COMPLETE or _showcase == Showcase.FAILED
	if _quit_after > 0.0 and (sim.t >= _quit_after or showcase_finished):
		var snap := sim.snapshot()
		var el2 := sim.orbit_elements()
		snap["prediction"] = prediction.get("label", "")
		snap["ap_alt"] = el2.ra - el2.body_radius if el2.bound else -1.0
		snap["pe_alt"] = el2.rp - el2.body_radius
		print("RESULT " + JSON.stringify(snap))
		get_tree().quit(1 if _showcase == Showcase.FAILED else 0)


func _sync_prev() -> void:
	_prev = PackedFloat64Array([sim.px, sim.py, sim.pz, sim.moon_angle])
	_cur = _prev.duplicate()


func _process(_delta: float) -> void:
	var f := 1.0 if paused else Engine.get_physics_interpolation_fraction()
	var ox := _prev[0] + (_cur[0] - _prev[0]) * f
	var oy := _prev[1] + (_cur[1] - _prev[1]) * f
	var oz := _prev[2] + (_cur[2] - _prev[2]) * f
	var ma := _cur[3]
	var map_mode := cams.mode == CameraRig.Mode.MAP
	world.update_view(sim, ox, oy, oz, ma)
	var moon_local := sim.moon_pos_at_angle(ma)
	trajectory.update_moon(moon_local, cfg.moon_distance, map_mode)
	trajectory.line_instance.visible = true
	rocket_view.update_view(sim, sim.velocity(), _last_acc, map_mode, paused)
	var planet_center := world.planet_frame.position
	var up := Vector3(ox, oy, oz).normalized()
	var min_focus := cfg.planet_radius * 1.15
	if cams.focus == CameraRig.Focus.MOON:
		min_focus = cfg.moon_radius * 1.3
	cams.update_cameras(planet_center, planet_center + moon_local, up, sim.orientation.y, min_focus)

	var air := clampf(sim.last_density / 1.2, 0.0, 1.0)
	var thr := sim.last_thrust / cfg.max_thrust if cfg.max_thrust > 0.0 else 0.0
	sound.set_state(thr, air, sim.last_dynamic_pressure, paused or sim.status == OrbitalSim.Status.CRASHED)

	var hold_text := ""
	match hold:
		Hold.PROGRADE: hold_text = "Hold: prograde"
		Hold.RETROGRADE: hold_text = "Hold: retrograde"
	var ap_text := autopilot.phase_name() if autopilot != null else ""
	hud.update_hud(sim, prediction, warp_index, paused, cams.mode_name(), hold_text, ap_text)
	if _showcase != Showcase.OFF:
		_update_showcase_card()
	_frame += 1
	if _shot_path != "" and _frame == _shot_frame:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(_shot_path)
		print("SCREENSHOT " + _shot_path)
		if _quit_after <= 0.0:
			get_tree().quit()
