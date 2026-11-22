class_name SettingsPanel
extends PanelContainer
## Right-side editor: rocket configuration (applied on the pad / at reset) and
## live world parameters (planet, atmosphere, moon) + scenario buttons.

signal world_changed
signal rocket_changed
signal preset_requested(name: String)
signal autopilot_toggled

var cfg: SimConfig            ## live world config (shared with OrbitalSim)
var rocket: SimConfig         ## pending rocket parameters (copied on reset/pad)
var sim: OrbitalSim
var _rows: Array = []         ## [slider, getter, value_label, fmt]
var _rocket_note: Label
var _derived: Label
var _syncing := false


func setup(world_cfg: SimConfig, rocket_cfg: SimConfig, s: OrbitalSim) -> void:
	cfg = world_cfg
	rocket = rocket_cfg
	sim = s
	add_theme_stylebox_override("panel", UiKit.panel_style(0.92))
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	UiKit.pin(self, 1, 0, -14, 58, Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_END)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := UiKit.header("Rocket and world settings")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UiKit.label("Tab — hide", UiKit.FS_CAPTION, UiKit.DIM))
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(PANEL_WIDTH - 28, 470)
	v.add_child(tabs)
	tabs.add_child(_rocket_tab())
	tabs.add_child(_world_tab())
	tabs.add_child(_scenario_tab())
	refresh()
	_build_toggle()
	# Hidden at start so the launch view stays clear; the always-visible
	# "⚙ Settings" button (and Tab) opens it.
	visible = false


const PANEL_WIDTH := 344.0
var toggle_button: Button


## Discoverable, clickable entry point for the panel. It is a sibling (the panel
## itself is hidden), pinned to the top-right corner, and mirrors visibility.
func _build_toggle() -> void:
	toggle_button = Button.new()
	toggle_button.name = "SettingsToggle"
	toggle_button.toggle_mode = true
	toggle_button.focus_mode = Control.FOCUS_NONE
	toggle_button.tooltip_text = "Rocket, planet, atmosphere and moon parameters, plus scenarios (Tab)"
	toggle_button.add_theme_font_size_override("font_size", UiKit.FS_BODY)
	toggle_button.toggled.connect(func(on: bool): visible = on)
	get_parent().add_child.call_deferred(toggle_button)
	UiKit.pin(toggle_button, 1, 0, -14, 14, Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_END)
	visibility_changed.connect(_sync_toggle)
	_sync_toggle()


func _sync_toggle() -> void:
	if toggle_button == null:
		return
	toggle_button.set_pressed_no_signal(visible)
	toggle_button.text = "✕ Close settings  (Tab)" if visible else "⚙ Settings  (Tab)"


func _scroll(title: String) -> Array:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	sc.add_child(box)
	return [sc, box]


func _slider(box: VBoxContainer, title: String, lo: float, hi: float, step: float,
		getter: Callable, setter: Callable, fmt: Callable, exp_scale := false) -> void:
	var h := HBoxContainer.new()
	h.add_child(UiKit.label(title, 14, UiKit.DIM))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	var val := UiKit.label("", 14)
	h.add_child(val)
	box.add_child(h)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.exp_edit = exp_scale
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_NONE
	box.add_child(s)
	_rows.append([s, getter, val, fmt])
	s.value_changed.connect(func(x: float):
		val.text = fmt.call(x)
		if not _syncing:
			setter.call(x)
	)


func _rocket_tab() -> Control:
	var pair := _scroll("Rocket")
	var box: VBoxContainer = pair[1]
	_rocket_note = UiKit.label("", 13, UiKit.WARN)
	_rocket_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rocket_note.custom_minimum_size = Vector2(PANEL_WIDTH - 60, 0)
	box.add_child(_rocket_note)
	_slider(box, "Dry mass", 500, 10_000, 50,
		func(): return rocket.dry_mass, func(x): rocket.dry_mass = x; _rocket_edit(),
		func(x): return "%.0f kg" % x)
	_slider(box, "Fuel (mass)", 0, 30_000, 100,
		func(): return rocket.fuel_capacity, func(x): rocket.fuel_capacity = x; _rocket_edit(),
		func(x): return "%.0f kg" % x)
	_slider(box, "Max engine thrust", 10, 600, 5,
		func(): return rocket.max_thrust / 1000.0, func(x): rocket.max_thrust = x * 1000.0; _rocket_edit(),
		func(x): return "%.0f kN" % x)
	_slider(box, "Specific impulse Isp", 150, 450, 5,
		func(): return rocket.isp, func(x): rocket.isp = x; _rocket_edit(),
		func(x): return "%.0f s" % x)
	_slider(box, "Drag coefficient Cd", 0.05, 1.5, 0.01,
		func(): return rocket.cd, func(x): rocket.cd = x; _rocket_edit(),
		func(x): return "%.2f" % x)
	_slider(box, "Cross-section area S", 0.5, 15, 0.1,
		func(): return rocket.area, func(x): rocket.area = x; _rocket_edit(),
		func(x): return "%.1f m²" % x)
	_derived = UiKit.label("", 13, UiKit.ACCENT)
	_derived.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_derived.custom_minimum_size = Vector2(PANEL_WIDTH - 60, 0)
	box.add_child(_derived)
	var b := Button.new()
	b.text = "Restore default rocket"
	b.pressed.connect(func():
		var d := SimConfig.new()
		for k in ["dry_mass", "fuel_capacity", "max_thrust", "isp", "cd", "area"]:
			rocket.set(k, d.get(k))
		refresh()
		_rocket_edit())
	box.add_child(b)
	return pair[0]


func _world_tab() -> Control:
	var pair := _scroll("World")
	var box: VBoxContainer = pair[1]
	box.add_child(UiKit.header("Planet Odra"))
	_slider(box, "Planet mass", 0.3, 12.0, 0.01,
		func(): return cfg.planet_mass / 1e22, func(x): cfg.planet_mass = x * 1e22; _world_edit(),
		func(x): return "%.2f·10²² kg" % x)
	_slider(box, "Planet radius", 200, 1200, 5,
		func(): return cfg.planet_radius / 1000.0, func(x): cfg.planet_radius = x * 1000.0; _world_edit(),
		func(x): return "%.0f km" % x)
	box.add_child(UiKit.header("Atmosphere"))
	_slider(box, "Surface density ρ₀", 0.0, 5.0, 0.05,
		func(): return cfg.atmo_rho0, func(x): cfg.atmo_rho0 = x; _world_edit(),
		func(x): return "%.2f kg/m³" % x)
	_slider(box, "Scale height H", 2, 25, 0.5,
		func(): return cfg.atmo_scale_height / 1000.0, func(x): cfg.atmo_scale_height = x * 1000.0; _world_edit(),
		func(x): return "%.1f km" % x)
	_slider(box, "Atmosphere upper limit", 10, 150, 1,
		func(): return cfg.atmo_cutoff / 1000.0, func(x): cfg.atmo_cutoff = x * 1000.0; _world_edit(),
		func(x): return "%.0f km" % x)
	box.add_child(UiKit.header("Moon Ślęża"))
	_slider(box, "Moon mass", 0.0, 30.0, 0.1,
		func(): return cfg.moon_mass / 1e20, func(x): cfg.moon_mass = x * 1e20; _world_edit(),
		func(x): return "%.1f·10²⁰ kg" % x)
	_slider(box, "Distance from planet", 1500, 15000, 50,
		func(): return cfg.moon_distance / 1000.0, func(x): cfg.moon_distance = x * 1000.0; _world_edit(),
		func(x): return "%.0f km" % x)
	_slider(box, "Position (phase angle)", 0, 360, 1,
		func(): return rad_to_deg(sim.moon_angle),
		func(x):
			sim.moon_angle = deg_to_rad(x)
			cfg.moon_start_angle = sim.moon_angle
			_world_edit(),
		func(x): return "%.0f°" % x)
	var mv := CheckBox.new()
	mv.text = "Moon moves along its orbit"
	mv.button_pressed = cfg.moon_moving
	mv.focus_mode = Control.FOCUS_NONE
	mv.toggled.connect(func(on: bool): cfg.moon_moving = on; _world_edit())
	box.add_child(mv)
	var b := Button.new()
	b.text = "Restore default world"
	b.pressed.connect(func():
		var d := SimConfig.new()
		for k in ["planet_mass", "planet_radius", "atmo_rho0", "atmo_scale_height", "atmo_cutoff",
				"moon_mass", "moon_radius", "moon_distance", "moon_moving"]:
			cfg.set(k, d.get(k))
		sim.moon_angle = d.moon_start_angle
		cfg.moon_start_angle = d.moon_start_angle
		mv.button_pressed = true
		refresh()
		_world_edit())
	box.add_child(b)
	return pair[0]


func _scenario_tab() -> Control:
	var pair := _scroll("Scenarios")
	var box: VBoxContainer = pair[1]
	box.add_theme_constant_override("separation", 8)
	for item in [
		["pad", "↺ Launch from pad (R)", "Full tank, engine off. Requires a manual launch."],
		["orbit", "◯ 100 km circular orbit (O)", "Ready, stable orbit — start experimenting with manoeuvres right away."],
		["transfer", "☾ Transfer to Ślęża (K)", "Elliptical orbit with Ap near the moon — flyby about 340 km above Ślęża (use 50×)."],
	]:
		var b := Button.new()
		b.text = item[1]
		var key: String = item[0]
		b.pressed.connect(func(): preset_requested.emit(key))
		box.add_child(b)
		var d := UiKit.label(item[2], 13, UiKit.DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(PANEL_WIDTH - 60, 0)
		box.add_child(d)
	var ap := Button.new()
	ap.text = "✈ Launch autopilot (F2)"
	ap.pressed.connect(func(): autopilot_toggled.emit())
	box.add_child(ap)
	var d2 := UiKit.label("Resets to the pad and flies a gravity turn, cut-off at Ap 85 km and circularisation. Any control key takes over.", 13, UiKit.DIM)
	d2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d2.custom_minimum_size = Vector2(PANEL_WIDTH - 60, 0)
	box.add_child(d2)
	return pair[0]


func _rocket_edit() -> void:
	_update_derived()
	rocket_changed.emit()


func _world_edit() -> void:
	world_changed.emit()


func _update_derived() -> void:
	if _derived == null:
		return
	var m0 := rocket.dry_mass + rocket.fuel_capacity
	var ve := rocket.isp * SimConfig.G0
	var dv := ve * log(m0 / rocket.dry_mass) if rocket.dry_mass > 0.0 else 0.0
	var twr := rocket.max_thrust / (m0 * cfg.surface_gravity()) if m0 > 0.0 else 0.0
	var burn := rocket.fuel_capacity / (rocket.max_thrust / ve) if rocket.max_thrust > 0.0 else 0.0
	var v_orb := sqrt(cfg.mu_planet() / (cfg.planet_radius + 100_000.0))
	_derived.text = "Launch mass %.0f kg • Δv %.0f m/s • TWR %.2f • burn time %.0f s\n(100 km orbit needs about %.0f m/s + ~700 m/s losses)" % [m0, dv, twr, burn, v_orb]
	_derived.add_theme_color_override("font_color", UiKit.BAD if twr < 1.0 else UiKit.ACCENT)


## Re-read slider values from the model and update the lock note.
func refresh() -> void:
	_syncing = true
	for r in _rows:
		var s: HSlider = r[0]
		s.value = r[1].call()
		r[2].text = r[3].call(s.value)
	_syncing = false
	_update_derived()
	update_lock_note()


func update_lock_note() -> void:
	if _rocket_note == null or sim == null:
		return
	if sim.is_on_pad():
		_rocket_note.text = "Rocket on the pad — changes apply immediately."
		_rocket_note.add_theme_color_override("font_color", UiKit.GOOD)
	else:
		_rocket_note.text = "In flight — rocket changes apply after a reset (R) or scenario choice."
		_rocket_note.add_theme_color_override("font_color", UiKit.WARN)
