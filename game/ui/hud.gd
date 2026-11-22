class_name Hud
extends Control
## Telemetry, status bar, contextual guidance, toasts, controls help,
## quick-action bar, intro and outcome overlays. Purely presentational: emits
## signals and reads the simulation, never changes physics state.
##
## Layout contract (logical 1280x720 base viewport, see project.godot):
##   top-left      telemetry: primary readouts (h, v, Ap, Pe), fuel/throttle,
##                 forecast, collapsible details (TelemetryDetailsToggle)
##   top-centre    status line + toasts
##   bottom-centre "Next step" guidance (GuidanceText) above the action bar
##   top-right     settings entry (owned by SettingsPanel)
##   centre        intro / outcome / F1 help overlays

signal warp_requested(index: int)
signal pause_toggled
signal camera_toggled
signal preset_requested(name: String)
signal autopilot_toggled
signal showcase_requested
signal showcase_exited
signal showcase_pause_toggled

const WARPS := [1, 5, 10, 50]
const TELEMETRY_WIDTH := 316.0
const STATUS_WIDTH := 540.0   ## fits between telemetry and the settings button at 1280 px

var _vals := {}
var _fuel_bar: ProgressBar
var _thr_bar: ProgressBar
var _fuel_text: Label
var _thr_text: Label
var _traj_label: Label
var _status_label: Label
var _status_chip: PanelContainer
var _warp_buttons: Array[Button] = []
var _pause_button: Button
var _cam_button: Button
var _toasts: VBoxContainer
var _help: PanelContainer
var _intro: PanelContainer
var _outcome: PanelContainer
var _outcome_title: Label
var _outcome_text: Label
var _pause_overlay: Label
var _details: GridContainer
var _details_toggle: Button
var _guide_panel: PanelContainer
var _guide_style: StyleBoxFlat
var _guide_text: Label
var _action_bar: Control
var _showcase_panel: PanelContainer
var _showcase_title: Label
var _showcase_text: Label
var _showcase_pause: Button
var _showcase_active := false
var _sandbox_panels: Array[bool] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_telemetry()
	_build_status_bar()
	_build_action_bar()
	_build_guidance()
	_build_help()
	_build_intro()
	_build_outcome()
	_build_showcase()


# ------------------------------------------------------------------ build

func _value_label(key: String, size := UiKit.FS_VALUE) -> Label:
	var val := UiKit.label("—", size)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_vals[key] = val
	return val


## One of the four large primary readouts: caption, big value, small sub-line.
func _primary_cell(key: String, caption: String, sub_key: String) -> Control:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", -2)
	v.add_child(UiKit.label(caption, UiKit.FS_CAPTION, UiKit.DIM))
	var val := UiKit.label("—", UiKit.FS_PRIMARY)
	val.clip_text = true
	_vals[key] = val
	v.add_child(val)
	var sub := UiKit.label("", UiKit.FS_CAPTION, UiKit.DIM)
	sub.clip_text = true
	_vals[sub_key] = sub
	v.add_child(sub)
	return v


func _bar_row(v: VBoxContainer, caption: String, hint: String, color: Color) -> Array:
	var h := HBoxContainer.new()
	h.add_child(UiKit.label(caption, UiKit.FS_CAPTION, UiKit.DIM))
	var hint_l := UiKit.label(hint, UiKit.FS_CAPTION - 1, Color(UiKit.DIM, 0.8))
	hint_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(hint_l)
	var pct := UiKit.label("—", UiKit.FS_CAPTION + 1)
	h.add_child(pct)
	v.add_child(h)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 10)
	bar.max_value = 100.0
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	v.add_child(bar)
	return [bar, pct]


func _build_telemetry() -> void:
	var p := UiKit.panel(0.86)
	p.name = "Telemetry"
	p.custom_minimum_size = Vector2(TELEMETRY_WIDTH, 0)
	add_child(p)
	UiKit.pin(p, 0, 0, 14, 14, Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_END)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	p.add_child(v)

	# header: title, mission clock, state chip
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	head.add_child(UiKit.header("Telemetry"))
	var clock := _value_label("time", UiKit.FS_CAPTION + 1)
	clock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(clock)
	_status_chip = PanelContainer.new()
	_status_chip.add_theme_stylebox_override("panel", UiKit.chip_style(UiKit.ACCENT))
	head.add_child(_status_chip)
	var st := UiKit.label("—", UiKit.FS_CAPTION)
	_vals["status"] = st
	_status_chip.add_child(st)

	# primary readouts
	var prim := GridContainer.new()
	prim.columns = 2
	prim.add_theme_constant_override("h_separation", 14)
	prim.add_theme_constant_override("v_separation", 4)
	v.add_child(prim)
	prim.add_child(_primary_cell("alt", "Altitude h", "alt_sub"))
	prim.add_child(_primary_cell("speed", "Speed v", "speed_sub"))
	prim.add_child(_primary_cell("ap", "Apoapsis Ap", "ap_sub"))
	prim.add_child(_primary_cell("pe", "Periapsis Pe", "pe_sub"))

	v.add_child(UiKit.divider())
	var fb := _bar_row(v, "Fuel", "", UiKit.ACCENT)
	_fuel_bar = fb[0]
	_fuel_text = fb[1]
	var tb := _bar_row(v, "Thrust", "  Shift/Ctrl · Z 100% · X 0%", UiKit.WARN)
	_thr_bar = tb[0]
	_thr_text = tb[1]

	v.add_child(UiKit.divider())
	v.add_child(UiKit.header("Trajectory forecast (engine off)"))
	_traj_label = UiKit.label("—", UiKit.FS_BODY + 1, UiKit.GOOD)
	_traj_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_traj_label.custom_minimum_size = Vector2(TELEMETRY_WIDTH - 28, 0)
	v.add_child(_traj_label)

	v.add_child(UiKit.divider())
	_details_toggle = Button.new()
	_details_toggle.name = "TelemetryDetailsToggle"
	_details_toggle.flat = true
	_details_toggle.focus_mode = Control.FOCUS_NONE
	_details_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_details_toggle.add_theme_font_size_override("font_size", UiKit.FS_CAPTION)
	_details_toggle.add_theme_color_override("font_color", UiKit.ACCENT)
	_details_toggle.tooltip_text = "Show / hide detailed flight parameters"
	_details_toggle.pressed.connect(_toggle_details)
	v.add_child(_details_toggle)
	_details = GridContainer.new()
	_details.name = "TelemetryDetails"
	_details.columns = 2
	_details.add_theme_constant_override("h_separation", 10)
	_details.add_theme_constant_override("v_separation", 0)
	v.add_child(_details)
	for row in [
		["vvert", "Vertical / horizontal"], ["acc", "Acceleration a"],
		["grav", "Local gravity"], ["mass", "Mass"], ["dv", "Remaining Δv"],
		["thrust", "Thrust / TWR"], ["pitch", "Pitch above horizon"],
		["air", "Density ρ / q"], ["ecc", "Eccentricity / period"],
		["moon", "Distance to Ślęża"],
	]:
		var n := UiKit.label(row[1], UiKit.FS_CAPTION, UiKit.DIM)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_details.add_child(n)
		_details.add_child(_value_label(row[0], UiKit.FS_CAPTION + 1))
	_set_details(true)


func _set_details(on: bool) -> void:
	_details.visible = on
	_details_toggle.text = ("▾ Flight details" if on else "▸ Flight details (show)")


func _toggle_details() -> void:
	_set_details(not _details.visible)


func _build_status_bar() -> void:
	var top := VBoxContainer.new()
	top.name = "StatusArea"
	top.custom_minimum_size = Vector2(STATUS_WIDTH, 0)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 6)
	add_child(top)
	UiKit.pin(top, 0.5, 0, 0, 14, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_END)
	var p := UiKit.panel(0.8)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps: StyleBoxFlat = p.get_theme_stylebox("panel")
	ps.content_margin_top = 6
	ps.content_margin_bottom = 6
	top.add_child(p)
	_status_label = UiKit.label("", UiKit.FS_BODY)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # long states wrap, never widen
	p.add_child(_status_label)
	_toasts = VBoxContainer.new()
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_toasts)
	_pause_overlay = UiKit.label("PAUSED", 44, UiKit.WARN)
	_pause_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_overlay.add_theme_constant_override("outline_size", 12)
	_pause_overlay.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_pause_overlay.visible = false
	add_child(_pause_overlay)
	UiKit.pin(_pause_overlay, 0.5, 0.5, 0, -140, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)


func _bar_button(h: HBoxContainer, text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(cb)
	h.add_child(b)
	return b


func _bar_sep(h: HBoxContainer) -> void:
	var s := VSeparator.new()
	var line := StyleBoxLine.new()
	line.color = Color(UiKit.ACCENT, 0.25)
	line.vertical = true
	s.add_theme_stylebox_override("separator", line)
	s.add_theme_constant_override("separation", 8)
	h.add_child(s)


func _build_action_bar() -> void:
	var p := UiKit.panel(0.86)
	_action_bar = p
	p.name = "ActionBar"
	var ps: StyleBoxFlat = p.get_theme_stylebox("panel")
	ps.content_margin_top = 6
	ps.content_margin_bottom = 6
	ps.content_margin_left = 10
	ps.content_margin_right = 10
	add_child(p)
	UiKit.pin(p, 0.5, 1, 0, -12, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	p.add_child(h)
	h.add_child(UiKit.label("Time", UiKit.FS_CAPTION, UiKit.DIM))
	for i in WARPS.size():
		var b := _bar_button(h, "%d×" % WARPS[i], "Time warp (key %d)" % (i + 1),
				func(): warp_requested.emit(i))
		b.toggle_mode = true
		_warp_buttons.append(b)
	_bar_sep(h)
	_pause_button = _bar_button(h, "⏸ Pause (P)", "Pause / resume the simulation (P or Esc)",
			func(): pause_toggled.emit())
	_cam_button = _bar_button(h, "🎥 Camera (C)", "Toggle: chase camera / orbital map (C or M)",
			func(): camera_toggled.emit())
	_bar_sep(h)
	_bar_button(h, "↺ Reset (R)", "Return to the launch pad with a full tank",
			func(): preset_requested.emit("pad"))
	_bar_button(h, "◯ Orbit (O)", "Instantly: stable 100 km circular orbit",
			func(): preset_requested.emit("orbit"))
	_bar_button(h, "Showcase (F3)", "Run the automatic launch-to-orbit showcase",
			func(): showcase_requested.emit())


func _build_guidance() -> void:
	_guide_panel = PanelContainer.new()
	_guide_panel.name = "Guidance"
	_guide_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_guide_style = UiKit.panel_style(0.82)
	_guide_style.border_width_left = 4
	_guide_style.content_margin_top = 6
	_guide_style.content_margin_bottom = 7
	_guide_panel.add_theme_stylebox_override("panel", _guide_style)
	add_child(_guide_panel)
	UiKit.pin(_guide_panel, 0.5, 1, 0, -66, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	_guide_panel.add_child(h)
	var cap := UiKit.header("Next step")
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(cap)
	_guide_text = UiKit.label("—", UiKit.FS_BODY + 2)
	_guide_text.name = "GuidanceText"
	_guide_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_guide_text.custom_minimum_size = Vector2(420, 0)
	h.add_child(_guide_text)


func _build_help() -> void:
	_help = UiKit.panel(0.95)
	_help.name = "Help"
	_help.visible = false   # shown on demand (F1); the intro already lists the basics
	add_child(_help)
	UiKit.pin(_help, 0.5, 0.5, 0, 0, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_help.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UiKit.label("Controls", 20, UiKit.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := Button.new()
	close.text = "✕ Close (F1)"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(toggle_help)
	head.add_child(close)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 3)
	v.add_child(g)
	for row in [
		["W / S", "pitch"], ["A / D", "yaw"],
		["Shift / Ctrl", "throttle up / down"], ["Z / X", "full thrust / cut-off"],
		["T / G", "hold prograde / retrograde (WASD cancels)"],
		["1–4  or  , / .", "time 1× 5× 10× 50×"], ["P / Esc", "pause"],
		["C / M", "chase camera / orbital map"], ["F", "map focus: Odra / rocket / Ślęża"],
		["Mouse", "drag — rotate camera, wheel — zoom"],
		["R / O / K", "reset to pad / 100 km orbit / transfer to Ślęża"],
		["F2 / F3", "launch autopilot / automatic showcase"], ["Tab", "rocket and world settings panel"],
		["F1", "this list"],
	]:
		g.add_child(UiKit.label(row[0], UiKit.FS_BODY, UiKit.WARN))
		g.add_child(UiKit.label(row[1], UiKit.FS_BODY))


func _build_intro() -> void:
	_intro = UiKit.panel(0.95)
	_intro.name = "Intro"
	_intro.custom_minimum_size = Vector2(700, 0)
	add_child(_intro)
	UiKit.pin(_intro, 0.5, 0.5, 0, 0, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_intro.add_child(v)
	v.add_child(UiKit.label("Orbita Odra", UiKit.FS_TITLE + 4, UiKit.ACCENT))
	v.add_child(UiKit.label("Fly the rocket from the launch pad into a stable orbit around the planet Odra.", UiKit.FS_BODY + 2))
	v.add_child(UiKit.divider())
	v.add_child(UiKit.header("How to reach orbit (about 5 min)"))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 5)
	v.add_child(g)
	for row in [
		["1", "Z — full thrust. The rocket lifts off vertically."],
		["2", "From about 1 km, hold W to pitch east:\n~60° above the horizon at 10 km, ~30° at 25 km, ~10° at 40 km."],
		["3", "When Ap reaches ~85 km — X (cut-off)."],
		["4", "Coast (you can use 10×). Just before Ap: T (prograde) and Z."],
		["5", "Cut the engine when Pe rises above 60 km — the forecast shows \"Stable orbit\"."],
	]:
		var n := UiKit.label(row[0], UiKit.FS_BODY + 2, UiKit.WARN)
		n.custom_minimum_size = Vector2(18, 0)
		g.add_child(n)
		g.add_child(UiKit.label(row[1], UiKit.FS_BODY))
	v.add_child(UiKit.label("The \"Next step\" panel at the bottom of the screen suggests the next action during flight.", UiKit.FS_CAPTION + 1, UiKit.GOOD))
	v.add_child(UiKit.divider())
	v.add_child(UiKit.label(
		"Shortcuts: O — ready 100 km orbit · K — transfer to Ślęża · F2 — launch autopilot\n" +
		"Tab or ⚙ — settings · R — reset · P/Esc — pause · C — camera/map · 1–4 — time · F1 — all keys",
		UiKit.FS_CAPTION + 1, UiKit.DIM))
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(actions)
	_bar_button(actions, "Start (Enter)", "Switch to manual control", hide_intro)
	_bar_button(actions, "Automatic showcase (F3)", "Watch the launch and orbit insertion",
			func(): showcase_requested.emit())


func _build_showcase() -> void:
	_showcase_panel = UiKit.panel(0.94)
	_showcase_panel.name = "ShowcasePanel"
	_showcase_panel.custom_minimum_size.x = 670.0
	_showcase_panel.hide()
	add_child(_showcase_panel)
	UiKit.pin(_showcase_panel, 0.5, 1, 0, -18, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	_showcase_panel.add_child(column)
	_showcase_title = UiKit.label("", 28, UiKit.ACCENT)
	_showcase_title.name = "ShowcaseTitle"
	column.add_child(_showcase_title)
	_showcase_text = UiKit.label("", 20)
	_showcase_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_showcase_text)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(actions)
	_showcase_pause = _bar_button(actions, "Pause (P)", "Pause the narration and flight",
			func(): showcase_pause_toggled.emit())
	_bar_button(actions, "Restart (F3)", "Replay the whole showcase", func(): showcase_requested.emit())
	_bar_button(actions, "Back to game (Esc)", "Return to the previous flight", func(): showcase_exited.emit())


func set_showcase(active: bool) -> void:
	if active == _showcase_active:
		return
	_showcase_active = active
	if active:
		_sandbox_panels = [_intro.visible, _help.visible, _outcome.visible, _details.visible]
		_intro.hide()
		_help.hide()
		_outcome.hide()
		_set_details(false)
	else:
		_intro.visible = _sandbox_panels[0]
		_help.visible = _sandbox_panels[1]
		_outcome.visible = _sandbox_panels[2]
		_set_details(_sandbox_panels[3])
	_details_toggle.visible = not active
	_action_bar.visible = not active
	_toasts.visible = not active
	_showcase_panel.visible = active


func update_showcase(title: String, description: String, stopped: bool, done: bool) -> void:
	_showcase_title.text = title
	_showcase_text.text = description
	_showcase_pause.text = "Resume (P)" if stopped else "Pause (P)"
	_showcase_pause.visible = not done


func _build_outcome() -> void:
	_outcome = UiKit.panel(0.94)
	_outcome.name = "Outcome"
	_outcome.custom_minimum_size = Vector2(520, 0)
	_outcome.visible = false
	add_child(_outcome)
	UiKit.pin(_outcome, 0.5, 0.5, 0, 60, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_outcome.add_child(v)
	_outcome_title = UiKit.label("", UiKit.FS_TITLE, UiKit.BAD)
	_outcome_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_outcome_title)
	_outcome_text = UiKit.label("", UiKit.FS_BODY)
	_outcome_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outcome_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_outcome_text)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	var r := Button.new()
	r.text = "↺ Reset to pad (R)"
	r.pressed.connect(func(): preset_requested.emit("pad"))
	h.add_child(r)
	var o := Button.new()
	o.text = "◯ 100 km orbit (O)"
	o.pressed.connect(func(): preset_requested.emit("orbit"))
	h.add_child(o)


# ------------------------------------------------------------------ API

func intro_visible() -> bool:
	return _intro.visible


func hide_intro() -> void:
	_intro.visible = false


func toggle_help() -> void:
	_help.visible = not _help.visible


## Current contextual hint shown in the "Next step" panel.
func guidance_text() -> String:
	return _guide_text.text


func toast(msg: String, color := UiKit.TEXT, seconds := 4.0) -> void:
	var p := UiKit.panel(0.8)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps: StyleBoxFlat = p.get_theme_stylebox("panel")
	ps.border_color = Color(color, 0.6)
	ps.content_margin_top = 5
	ps.content_margin_bottom = 5
	var l := UiKit.label(msg, UiKit.FS_BODY + 1, color)
	if msg.length() > 58:   # long messages wrap inside the status column
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(STATUS_WIDTH - 28, 0)
	p.add_child(l)
	_toasts.add_child(p)
	while _toasts.get_child_count() > 3:
		_toasts.get_child(0).queue_free()
		_toasts.remove_child(_toasts.get_child(0))
	var tw := create_tween()
	tw.tween_interval(seconds)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)


func show_outcome(title: String, text: String, good: bool) -> void:
	_outcome_title.text = title
	_outcome_title.add_theme_color_override("font_color", UiKit.GOOD if good else UiKit.BAD)
	_outcome_text.text = text
	_outcome.visible = true


func hide_outcome() -> void:
	_outcome.visible = false


func update_hud(sim: OrbitalSim, pred: Dictionary, warp_index: int, paused: bool,
		cam_text: String, hold_text: String, autopilot_text: String) -> void:
	var cfg := sim.cfg
	var el: Dictionary = sim.orbit_elements()
	var in_moon: bool = el.body == OrbitalSim.Body.MOON
	var status := ""
	var status_col := UiKit.ACCENT
	match sim.status:
		OrbitalSim.Status.LANDED:
			if sim.is_on_pad():
				status = "On the pad"
			else:
				status = "Engine damaged" if sim.engine_damaged else "On surface"
			status_col = UiKit.GOOD
		OrbitalSim.Status.FLYING:
			status = "Ślęża SOI" if in_moon else ("In atmosphere" if sim.last_density > 0.0 else "In vacuum")
			status_col = UiKit.MOON if in_moon else (UiKit.WARN if sim.last_density > 0.0 else UiKit.ACCENT)
		OrbitalSim.Status.CRASHED:
			status = "DESTROYED"
			status_col = UiKit.BAD
	_show_val("status", status, status_col)
	_status_chip.add_theme_stylebox_override("panel", _chip_for(status_col))
	_show_val("time", "T+ " + UiKit.fmt_time(sim.t), UiKit.DIM)
	var alt_txt := UiKit.fmt_alt(sim.altitude())
	var alt_sub := "above Odra"
	if in_moon:
		alt_txt = UiKit.fmt_alt(sim.moon_altitude())
		alt_sub = "above Ślęża"
	_show_val("alt", alt_txt)
	_show_val("alt_sub", alt_sub, UiKit.DIM)
	var rel_v := sim.velocity()
	if in_moon:
		rel_v -= sim.moon_velocity()
	_show_val("speed", "%.0f m/s" % rel_v.length() if rel_v.length() >= 100.0 else "%.1f m/s" % rel_v.length())
	_show_val("speed_sub", "vertical %+.0f m/s" % el.radial_speed, UiKit.DIM)
	_show_val("vvert", "%+.0f / %.0f m/s" % [el.radial_speed, el.horizontal_speed])
	_show_val("acc", "%.2f m/s² (%.2f g)" % [sim.last_proper_accel, sim.last_proper_accel / SimConfig.G0])
	_show_val("grav", "%.2f m/s²" % sim.last_gravity)
	_show_val("mass", "%.0f kg" % sim.mass())
	var dv := cfg.exhaust_velocity() * log(sim.mass() / cfg.dry_mass) if cfg.dry_mass > 0.0 else 0.0
	_show_val("dv", "%.0f m/s" % dv)
	_show_val("thrust", "%.0f kN / %.2f" % [sim.last_thrust / 1000.0, sim.twr()])
	_show_val("pitch", "%.1f°" % sim.pitch_above_horizon())
	_show_val("air", "%.4f / %.1f kPa" % [sim.last_density, sim.last_dynamic_pressure / 1000.0])
	var br: float = el.body_radius
	if sim.status == OrbitalSim.Status.FLYING:
		var pe_alt: float = el.rp - br
		if el.bound:
			_show_val("ap", UiKit.fmt_alt(el.ra - br), UiKit.GOOD)
			_show_val("ap_sub", "in " + UiKit.fmt_time(el.time_to_ap), UiKit.DIM)
		else:
			_show_val("ap", "∞", UiKit.WARN)
			_show_val("ap_sub", "escape", UiKit.WARN)
		var low: bool = pe_alt < cfg.atmo_cutoff and not in_moon
		if pe_alt < 0.0:
			_show_val("pe", "below surf.", UiKit.BAD)
			_show_val("pe_sub", UiKit.fmt_alt(pe_alt), UiKit.BAD)
		else:
			_show_val("pe", UiKit.fmt_alt(pe_alt), UiKit.BAD if low else UiKit.WARN)
			_show_val("pe_sub", ("in atmosphere · " if low else "") + "in " + UiKit.fmt_time(el.time_to_pe),
					UiKit.BAD if low else UiKit.DIM)
		_show_val("ecc", "%.4f / %s" % [el.e, UiKit.fmt_time(el.period) if el.bound else "—"])
	else:
		_show_val("ap", "—"); _show_val("pe", "—"); _show_val("ecc", "—")
		_show_val("ap_sub", ""); _show_val("pe_sub", "")
	_show_val("moon", UiKit.fmt_alt(sim.moon_altitude()) + (" (in SOI)" if in_moon else ""))
	var ff := sim.fuel_fraction()
	_fuel_bar.value = ff * 100.0
	_fuel_text.text = "%.0f%%  (%.0f kg)" % [ff * 100.0, sim.fuel]
	_fuel_text.add_theme_color_override("font_color", UiKit.BAD if ff < 0.1 else UiKit.TEXT)
	_thr_bar.value = sim.throttle * 100.0
	_thr_text.text = "%.0f%%" % (sim.throttle * 100.0)

	var kind: int = pred.get("kind", TrajectoryPredictor.Kind.LANDED)
	var tl: String = pred.get("label", "—")
	if pred.get("impact", false):
		tl += "  (in %s)" % UiKit.fmt_time(pred.time_to_impact)
	elif kind == TrajectoryPredictor.Kind.MOON_ENCOUNTER:
		tl += "\nmin. %s above Ślęża in %s" % [UiKit.fmt_alt(pred.closest_moon_alt), UiKit.fmt_time(pred.time_to_closest_moon)]
	_traj_label.text = tl
	_traj_label.add_theme_color_override("font_color", _kind_color(kind))

	var parts := ["Time %d×" % WARPS[warp_index], cam_text]
	if hold_text != "":
		parts.append(hold_text)
	if autopilot_text != "":
		parts.append("Autopilot: " + autopilot_text)
	if paused and not _showcase_active:
		parts.push_front("PAUSED")
	parts.append("SHOWCASE" if _showcase_active else "F1 — controls")
	_status_label.text = "  ·  ".join(parts)
	for i in _warp_buttons.size():
		_warp_buttons[i].set_pressed_no_signal(i == warp_index)
	_pause_button.text = "▶ Resume (P)" if paused else "⏸ Pause (P)"
	_pause_overlay.visible = paused and not _intro.visible and not _showcase_active

	var g := _guidance(sim, el, pred, kind, paused, autopilot_text, cam_text.begins_with("Map"))
	_guide_text.text = g[0]
	_guide_text.add_theme_color_override("font_color", g[1])
	_guide_style.border_color = Color(g[1], 0.75)
	_guide_panel.visible = not _intro.visible and not _outcome.visible and not _showcase_active


func _kind_color(kind: int) -> Color:
	match kind:
		TrajectoryPredictor.Kind.ORBIT_STABLE, TrajectoryPredictor.Kind.MOON_ORBIT: return UiKit.GOOD
		TrajectoryPredictor.Kind.IMPACT_PLANET, TrajectoryPredictor.Kind.IMPACT_MOON, TrajectoryPredictor.Kind.CRASHED: return UiKit.BAD
		TrajectoryPredictor.Kind.ORBIT_DECAYING, TrajectoryPredictor.Kind.ESCAPE: return UiKit.WARN
		TrajectoryPredictor.Kind.MOON_ENCOUNTER: return UiKit.MOON
	return UiKit.TEXT


var _chip_cache := {}

func _chip_for(c: Color) -> StyleBoxFlat:
	if not _chip_cache.has(c):
		_chip_cache[c] = UiKit.chip_style(c)
	return _chip_cache[c]


## Recommended pitch above the horizon for the manual ascent described in the
## intro (90° until 1 km, then ~60° at 10 km, ~30° at 25 km, ~10° at 40 km).
static func _ascent_pitch(alt: float) -> float:
	var pts := [[1000.0, 90.0], [10_000.0, 60.0], [25_000.0, 30.0], [40_000.0, 10.0], [50_000.0, 3.0]]
	if alt <= pts[0][0]:
		return 90.0
	for i in range(1, pts.size()):
		if alt <= pts[i][0]:
			var a: Array = pts[i - 1]
			var b: Array = pts[i]
			return lerpf(a[1], b[1], (alt - a[0]) / (b[0] - a[0]))
	return 3.0


## Contextual "next step" hint: [text, colour]. Mirrors the intro's flight plan.
func _guidance(sim: OrbitalSim, el: Dictionary, pred: Dictionary, kind: int, paused: bool,
		autopilot_text: String, map_mode: bool) -> Array:
	var cfg := sim.cfg
	if paused:
		return ["Paused — P or Esc resumes. World settings also work while paused (Tab).", UiKit.WARN]
	if autopilot_text != "":
		return ["Autopilot: %s. Any control key takes over." % autopilot_text, UiKit.ACCENT]
	match sim.status:
		OrbitalSim.Status.CRASHED:
			return ["Rocket destroyed. R — try again from the pad,  O — ready orbit.", UiKit.BAD]
		OrbitalSim.Status.LANDED:
			if sim.is_on_pad():
				if sim.throttle <= 0.0:
					return ["Z — full thrust to lift off  (Shift — gradually,  F2 — autopilot).", UiKit.GOOD]
				return ["Thrust too low to lift off — add Shift or Z, or change the rocket in settings (Tab).", UiKit.WARN]
			if sim.landed_body == OrbitalSim.Body.MOON:
				return ["Landed on Ślęża. R — return to the pad.", UiKit.GOOD]
			return ["Rocket on the surface. R — return to the pad,  O — orbit.", UiKit.TEXT]
	# flying
	var thrusting := sim.last_thrust > 0.0
	var br: float = el.body_radius
	var ap_alt: float = (el.ra - br) if el.bound else INF
	var pe_alt: float = el.rp - br
	var alt := sim.altitude()
	var target_ap := cfg.atmo_cutoff + 25_000.0
	var in_moon: bool = el.body == OrbitalSim.Body.MOON
	if sim.fuel <= 0.0 and kind != TrajectoryPredictor.Kind.ORBIT_STABLE:
		return ["Out of fuel — coasting. Watch the trajectory forecast; R — reset.", UiKit.WARN]
	if in_moon or kind == TrajectoryPredictor.Kind.MOON_ENCOUNTER or kind == TrajectoryPredictor.Kind.MOON_ORBIT:
		if kind == TrajectoryPredictor.Kind.IMPACT_MOON:
			return ["On course for Ślęża — G (retrograde) + Z brakes before landing (< 6 m/s).", UiKit.BAD]
		if map_mode:
			return ["Ślęża flyby — F changes map focus (Ślęża), 50× shortens the wait, C — rocket view.", UiKit.MOON]
		return ["Ślęża flyby — M shows the orbital map, 50× shortens the wait.", UiKit.MOON]
	if kind == TrajectoryPredictor.Kind.ORBIT_STABLE:
		if thrusting:
			return ["Pe above the atmosphere — X cuts the engine. The orbit will be stable.", UiKit.GOOD]
		return ["Stable orbit. T + Z at Pe raises Ap,  G + Z lowers the orbit,  K — transfer to Ślęża.", UiKit.GOOD]
	if kind == TrajectoryPredictor.Kind.ESCAPE:
		return ["Escape trajectory — G (retrograde) and Z to return to orbit.", UiKit.WARN]
	if thrusting and pe_alt < cfg.atmo_cutoff:
		if ap_alt >= target_ap:
			if alt < cfg.atmo_cutoff * 0.8 or el.radial_speed > 50.0:
				return ["Ap ≈ %s — X (cut-off), then coast to Ap." % UiKit.fmt_alt(ap_alt), UiKit.WARN]
			return ["Circularisation: hold T (prograde) and thrust until Pe > %s." % UiKit.fmt_alt(cfg.atmo_cutoff), UiKit.ACCENT]
		var want := _ascent_pitch(alt)
		var have := sim.pitch_above_horizon()
		if alt < 1000.0:
			return ["Vertical ascent. From 1 km, hold W to pitch east.", UiKit.GOOD]
		var diff := have - want
		var fix := "W — pitch over more" if diff > 0.0 else "S — raise the nose"
		var col := UiKit.GOOD if absf(diff) < 8.0 else UiKit.WARN
		if absf(diff) < 8.0:
			fix = "on track"
		return ["Pitch %.0f°, target about %.0f° at this altitude — %s. Cut-off at Ap ≈ %s." % [have, want, fix, UiKit.fmt_alt(target_ap)], col]
	if not thrusting and pe_alt < cfg.atmo_cutoff:
		if ap_alt > cfg.atmo_cutoff and el.radial_speed > 0.0:
			if el.time_to_ap > 45.0:
				return ["Coasting to Ap (in %s) — 10× speeds up time. Before Ap: T and Z." % UiKit.fmt_time(el.time_to_ap), UiKit.ACCENT]
			return ["Ap approaching (in %s) — T (prograde), then Z; cut off when Pe > %s." % [UiKit.fmt_time(el.time_to_ap), UiKit.fmt_alt(cfg.atmo_cutoff)], UiKit.WARN]
		if kind == TrajectoryPredictor.Kind.IMPACT_PLANET:
			return ["Collision course — Z with the nose up slows the descent; R — reset.", UiKit.BAD]
		return [pred.get("label", "—"), UiKit.WARN]
	return [pred.get("label", "—"), _kind_color(kind)]


func _show_val(key: String, text: String, color := UiKit.TEXT) -> void:
	var l: Label = _vals[key]
	l.text = text
	l.add_theme_color_override("font_color", color)
