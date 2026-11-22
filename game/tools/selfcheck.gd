extends SceneTree
## Headless developer self-check of the physics core.
## Usage: godot --headless --path . --script res://game/tools/selfcheck.gd
## Prints one JSON object per check and a summary; exit code 0 = all passed.

var _results: Array = []


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	_check_determinism()
	_check_orbit_preset()
	_check_autopilot_launch()
	_check_suborbital_impact()
	_check_landing_outcomes()
	_check_transfer_and_escape()
	_check_live_world_change()
	var failed := 0
	for r in _results:
		print(JSON.stringify(r))
		if not r.pass:
			failed += 1
	print(JSON.stringify({"summary": true, "checks": _results.size(), "failed": failed,
			"wall_ms": Time.get_ticks_msec() - t0}))
	quit(1 if failed > 0 else 0)


func _add(name: String, ok: bool, data: Dictionary) -> void:
	data["check"] = name
	data["pass"] = ok
	_results.append(data)


func _check_determinism() -> void:
	var a := OrbitalSim.new()
	var b := OrbitalSim.new()
	for s in [a, b]:
		var ap := AscentAutopilot.new(s)
		for i in 60 * 120:
			ap.update(OrbitalSim.DT)
			s.step(OrbitalSim.DT)
	var same: bool = a.snapshot() == b.snapshot()
	_add("determinism_120s_autopilot", same, {"a": a.snapshot(), "b": b.snapshot()})


func _check_orbit_preset() -> void:
	var s := OrbitalSim.new()
	s.set_circular_orbit()
	var pred := TrajectoryPredictor.new().predict(s)
	var el := s.orbit_elements()
	var period: float = el.period
	var min_alt := INF
	var max_alt := -INF
	var e0 := _energy(s)
	var steps := int(3.0 * period / OrbitalSim.DT)
	for i in steps:
		s.step(OrbitalSim.DT)
		if i % 60 == 0:
			var h := s.altitude()
			min_alt = minf(min_alt, h)
			max_alt = maxf(max_alt, h)
	var drift := absf((_energy(s) - e0) / e0)
	var ok: bool = pred.kind == TrajectoryPredictor.Kind.ORBIT_STABLE \
			and min_alt > s.cfg.atmo_cutoff and s.status == OrbitalSim.Status.FLYING \
			and absf(max_alt - min_alt) < 5_000.0
	_add("orbit_preset_3_periods", ok, {
		"kind": pred.label, "period_s": period, "min_alt_km": min_alt / 1000.0,
		"max_alt_km": max_alt / 1000.0, "rel_energy_change": drift,
		"pred_points": pred.points.size(), "ap_visible": pred.ap_visible, "pe_visible": pred.pe_visible,
	})


func _check_autopilot_launch() -> void:
	var s := OrbitalSim.new()
	var ap := AscentAutopilot.new(s)
	var t_limit := 1500.0
	while s.t < t_limit and ap.phase < AscentAutopilot.Phase.DONE:
		ap.update(OrbitalSim.DT)
		s.step(OrbitalSim.DT)
	var el := s.orbit_elements()
	var pred := TrajectoryPredictor.new().predict(s)
	# coast one more orbit to prove it holds
	var min_alt := INF
	if ap.phase == AscentAutopilot.Phase.DONE:
		var n := int(el.period / OrbitalSim.DT)
		for i in n:
			s.step(OrbitalSim.DT)
			if i % 60 == 0:
				min_alt = minf(min_alt, s.altitude())
	var ok: bool = ap.phase == AscentAutopilot.Phase.DONE \
			and pred.kind == TrajectoryPredictor.Kind.ORBIT_STABLE and min_alt > s.cfg.atmo_cutoff
	_add("autopilot_launch_to_orbit", ok, {
		"phase": ap.phase_name(), "kind": pred.label,
		"ap_km": (el.ra - s.cfg.planet_radius) / 1000.0, "pe_km": (el.rp - s.cfg.planet_radius) / 1000.0,
		"fuel_left_kg": s.fuel, "min_alt_next_orbit_km": min_alt / 1000.0,
	})


func _check_suborbital_impact() -> void:
	var s := OrbitalSim.new()
	s.set_throttle(1.0)
	s.rotate_pitch_yaw(deg_to_rad(20.0), 0.0)
	s.advance(40.0)
	s.set_throttle(0.0)
	var pred := TrajectoryPredictor.new().predict(s)
	var t_start := s.t
	var guard := 0
	while s.status == OrbitalSim.Status.FLYING and guard < 60 * 3000:
		s.step(OrbitalSim.DT)
		guard += 1
	var actual := s.t - t_start
	var landed_pos := s.position()
	var miss: float = landed_pos.distance_to(pred.impact_pos)
	var ok: bool = pred.kind == TrajectoryPredictor.Kind.IMPACT_PLANET \
			and s.status == OrbitalSim.Status.CRASHED \
			and absf(actual - pred.time_to_impact) < 0.02 * actual + 2.0 and miss < 2_000.0
	_add("suborbital_impact_prediction", ok, {
		"kind": pred.label, "pred_time_s": pred.time_to_impact, "actual_time_s": actual,
		"impact_miss_m": miss, "impact_speed": s.last_impact_speed,
	})


func _check_landing_outcomes() -> void:
	var outcomes := {}
	for v in [2.0, 12.0, 60.0]:
		var s := OrbitalSim.new()
		s.status = OrbitalSim.Status.FLYING
		s.launched = true
		s.py = s.cfg.planet_radius + 0.05
		s.vy = -v
		for i in 30:
			s.step(OrbitalSim.DT)
		outcomes[str(v)] = [s.status, s.engine_damaged]
	var ok: bool = outcomes["2.0"] == [OrbitalSim.Status.LANDED, false] \
			and outcomes["12.0"] == [OrbitalSim.Status.LANDED, true] \
			and outcomes["60.0"][0] == OrbitalSim.Status.CRASHED
	_add("landing_outcomes_soft_hard_crash", ok, {"outcomes": outcomes})


func _check_transfer_and_escape() -> void:
	var s := OrbitalSim.new()
	s.set_moon_transfer()
	var pred := TrajectoryPredictor.new().predict(s)
	var e := OrbitalSim.new()
	e.set_circular_orbit()
	e.vx *= 1.5; e.vy *= 1.5
	var pe := TrajectoryPredictor.new().predict(e)
	var ok: bool = pred.kind == TrajectoryPredictor.Kind.MOON_ENCOUNTER \
			and pe.kind == TrajectoryPredictor.Kind.ESCAPE
	_add("transfer_encounter_and_escape", ok, {
		"transfer_kind": pred.label, "closest_moon_alt_km": pred.closest_moon_alt / 1000.0,
		"time_to_closest_h": pred.time_to_closest_moon / 3600.0, "escape_kind": pe.label,
	})


func _check_live_world_change() -> void:
	var s := OrbitalSim.new()
	s.set_circular_orbit()
	var before: int = TrajectoryPredictor.new().predict(s).kind
	s.cfg.planet_mass *= 0.3   # weaker gravity -> same speed now escapes
	var after: int = TrajectoryPredictor.new().predict(s).kind
	var p := OrbitalSim.new()
	p.cfg.planet_radius = 520_000.0
	p.step(OrbitalSim.DT)
	var ok: bool = before == TrajectoryPredictor.Kind.ORBIT_STABLE \
			and after == TrajectoryPredictor.Kind.ESCAPE and absf(p.radius() - 520_000.0) < 0.01
	_add("live_world_change", ok, {
		"before": TrajectoryPredictor.label_for(before), "after": TrajectoryPredictor.label_for(after),
		"pad_radius_after_resize": p.radius(),
	})


func _energy(s: OrbitalSim) -> float:
	return 0.5 * s.speed() * s.speed() - s.cfg.mu_planet() / s.radius()
