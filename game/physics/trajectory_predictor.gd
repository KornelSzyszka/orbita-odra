class_name TrajectoryPredictor
extends RefCounted
## Engine-off ("ballistic") forward prediction of the rocket path.
##
## Uses the same force model as OrbitalSim (planet + moon gravity incl. the
## indirect term, drag with the same atmosphere; mass constant, no thrust)
## integrated with KDK leapfrog using an adaptive step (a fraction of the local
## dynamical time, capped near surfaces and inside the atmosphere). Variable
## steps break exact symplecticity, which is acceptable for a display path.

enum Kind {
	LANDED, CRASHED, ORBIT_STABLE, ORBIT_DECAYING, IMPACT_PLANET, IMPACT_MOON,
	ESCAPE, MOON_ENCOUNTER, MOON_ORBIT,
}

const LABELS := {
	Kind.LANDED: "On the surface",
	Kind.CRASHED: "Rocket destroyed",
	Kind.ORBIT_STABLE: "Stable orbit (Pe above atmosphere)",
	Kind.ORBIT_DECAYING: "Orbit grazes the atmosphere — decaying",
	Kind.IMPACT_PLANET: "Collision course — impact on Odra",
	Kind.IMPACT_MOON: "Collision course — impact on Ślęża",
	Kind.ESCAPE: "Escape trajectory",
	Kind.MOON_ENCOUNTER: "Flyby through Ślęża's sphere of influence",
	Kind.MOON_ORBIT: "Orbit around Ślęża",
}

const FLAG_VACUUM := 0
const FLAG_ATMO := 1
const FLAG_MOON := 2

var eta := 0.01            ## step = eta * local dynamical time
var max_steps := 4000
var max_time := 400_000.0  ## [s] prediction horizon cap


static func label_for(kind: int) -> String:
	return LABELS.get(kind, "?")


func predict(sim: OrbitalSim) -> Dictionary:
	var cfg := sim.cfg
	var res := {
		"kind": Kind.LANDED, "label": "", "points": PackedVector3Array(),
		"flags": PackedByteArray(), "impact": false, "impact_pos": Vector3.ZERO,
		"impact_body": OrbitalSim.Body.PLANET, "time_to_impact": -1.0,
		"moon_encounter": false, "closest_moon_alt": INF,
		"closest_moon_pos": Vector3.ZERO, "moon_at_closest": Vector3.ZERO,
		"time_to_closest_moon": -1.0, "duration": 0.0,
		"elements": sim.orbit_elements(),
		"ap_visible": false, "pe_visible": false,
		"ap_pos": Vector3.ZERO, "pe_pos": Vector3.ZERO,
	}
	if sim.status == OrbitalSim.Status.CRASHED:
		res.kind = Kind.CRASHED
		res.label = label_for(res.kind)
		return res
	if sim.status == OrbitalSim.Status.LANDED:
		res.kind = Kind.LANDED
		res.label = label_for(res.kind)
		return res

	var mu_p := cfg.mu_planet()
	var mu_m := cfg.mu_moon()
	var rp := cfg.planet_radius
	var rm := cfg.moon_radius
	var soi := cfg.moon_soi()
	var w := cfg.moon_angular_rate()
	var x := sim.px
	var y := sim.py
	var z := sim.pz
	var ux := sim.vx
	var uy := sim.vy
	var uz := sim.vz
	var m := sim.mass()
	var theta := sim.moon_angle
	var dist := cfg.moon_distance
	var t := 0.0
	var swept := 0.0          # angle swept around the planet
	var swept_moon := 0.0     # angle swept around the moon while inside its SOI
	var pts: PackedVector3Array = res.points
	var flags: PackedByteArray = res.flags
	pts.append(Vector3(x, y, z))
	flags.append(_flag(x, y, z, theta, dist, rp, cfg.atmo_cutoff, soi, cfg.atmo_rho0))
	var bound_planet: bool = res.elements.body == OrbitalSim.Body.PLANET and res.elements.bound
	var period_hint: float = res.elements.period if bound_planet else INF
	var horizon := minf(max_time, period_hint * 1.02) if bound_planet else max_time
	var escape_r := maxf(2.5 * dist, 20.0 * rp)
	var acc := [0.0, 0.0, 0.0]
	var started_in_soi := sim.in_moon_soi()

	for i in max_steps:
		var r := sqrt(x * x + y * y + z * z)
		var mx := dist * cos(theta)
		var my := dist * sin(theta)
		var dxm := x - mx
		var dym := y - my
		var dm := sqrt(dxm * dxm + dym * dym + z * z)
		var sp := sqrt(ux * ux + uy * uy + uz * uz)
		var dyn := sqrt(r * r * r / mu_p)
		if mu_m > 0.0:
			dyn = minf(dyn, sqrt(dm * dm * dm / mu_m))
		var dt := eta * dyn
		var clearance := minf(r - rp, dm - rm)
		var max_disp := clampf(clearance * 0.25, 100.0, 50_000.0)
		if sp > 0.0:
			dt = minf(dt, max_disp / sp)
		if r - rp < cfg.atmo_cutoff and cfg.atmo_rho0 > 0.0:
			dt = minf(dt, 1.0)
		dt = maxf(dt, 0.02)

		# KDK
		_accel(acc, x, y, z, ux, uy, uz, mx, my, m, cfg)
		var hx: float = ux + acc[0] * dt * 0.5
		var hy: float = uy + acc[1] * dt * 0.5
		var hz: float = uz + acc[2] * dt * 0.5
		var nx := x + hx * dt
		var ny := y + hy * dt
		var nz := z + hz * dt
		theta += w * dt
		t += dt
		var mx2 := dist * cos(theta)
		var my2 := dist * sin(theta)
		_accel(acc, nx, ny, nz, hx, hy, hz, mx2, my2, m, cfg)
		ux = hx + acc[0] * dt * 0.5
		uy = hy + acc[1] * dt * 0.5
		uz = hz + acc[2] * dt * 0.5

		# swept angle around planet
		var nr := sqrt(nx * nx + ny * ny + nz * nz)
		var cosang := clampf((x * nx + y * ny + z * nz) / (r * nr), -1.0, 1.0)
		swept += acos(cosang)

		# planet impact (interpolate on radius)
		if nr <= rp:
			var f := clampf((r - rp) / maxf(r - nr, 1e-9), 0.0, 1.0)
			var ip := Vector3(x + (nx - x) * f, y + (ny - y) * f, z + (nz - z) * f)
			ip = ip.normalized() * rp
			pts.append(ip)
			flags.append(FLAG_ATMO if cfg.atmo_rho0 > 0.0 and cfg.atmo_cutoff > 0.0 else FLAG_VACUUM)
			res.impact = true
			res.impact_pos = ip
			res.impact_body = OrbitalSim.Body.PLANET
			res.time_to_impact = t - dt * (1.0 - f)
			break

		# moon proximity
		var ndx := nx - mx2
		var ndy := ny - my2
		var ndm := sqrt(ndx * ndx + ndy * ndy + nz * nz)
		if ndm - rm < res.closest_moon_alt:
			res.closest_moon_alt = ndm - rm
			res.closest_moon_pos = Vector3(nx, ny, nz)
			res.moon_at_closest = Vector3(mx2, my2, 0.0)
			res.time_to_closest_moon = t
		if ndm <= soi:
			res.moon_encounter = true
			var c2 := clampf((dxm * ndx + dym * ndy + z * nz) / (dm * ndm), -1.0, 1.0)
			swept_moon += acos(c2)
		if ndm <= rm:
			var fm := clampf((dm - rm) / maxf(dm - ndm, 1e-9), 0.0, 1.0)
			var mc := Vector3(mx2, my2, 0.0)
			var ipm := Vector3(x + (nx - x) * fm, y + (ny - y) * fm, z + (nz - z) * fm)
			ipm = mc + (ipm - mc).normalized() * rm
			pts.append(ipm)
			flags.append(FLAG_MOON)
			res.impact = true
			res.impact_pos = ipm
			res.impact_body = OrbitalSim.Body.MOON
			res.time_to_impact = t
			break

		x = nx; y = ny; z = nz
		pts.append(Vector3(x, y, z))
		flags.append(_flag(x, y, z, theta, dist, rp, cfg.atmo_cutoff, soi, cfg.atmo_rho0))

		if started_in_soi and swept_moon >= TAU:
			break
		if not res.moon_encounter and swept >= TAU and bound_planet:
			break
		if t >= horizon:
			break
		if nr > escape_r:
			break

	res.duration = t
	res.kind = _classify(sim, res, started_in_soi)
	res.label = label_for(res.kind)
	_place_markers(sim, res)
	return res


func _classify(sim: OrbitalSim, res: Dictionary, started_in_soi: bool) -> int:
	if res.impact:
		return Kind.IMPACT_MOON if res.impact_body == OrbitalSim.Body.MOON else Kind.IMPACT_PLANET
	var el: Dictionary = res.elements
	if started_in_soi and el.body == OrbitalSim.Body.MOON and el.bound:
		return Kind.MOON_ORBIT
	if res.moon_encounter:
		return Kind.MOON_ENCOUNTER
	if not el.bound:
		return Kind.ESCAPE
	if el.rp < sim.cfg.planet_radius + sim.cfg.atmo_cutoff and sim.cfg.atmo_rho0 > 0.0:
		return Kind.ORBIT_DECAYING
	return Kind.ORBIT_STABLE


## Ap/Pe markers from osculating elements, shown only if the predicted path
## actually passes near them (e.g. no Pe marker below the surface).
func _place_markers(sim: OrbitalSim, res: Dictionary) -> void:
	var el: Dictionary = res.elements
	var c: Vector3 = el.center
	var pts: PackedVector3Array = res.points
	if el.pe_dir != Vector3.ZERO and el.rp > el.body_radius:
		res.pe_pos = c + el.pe_dir * el.rp
		res.pe_visible = _near_path(pts, res.pe_pos, el.rp * 0.03)
	if el.bound and el.ap_dir != Vector3.ZERO:
		res.ap_pos = c + el.ap_dir * el.ra
		res.ap_visible = _near_path(pts, res.ap_pos, el.ra * 0.03)


static func _near_path(pts: PackedVector3Array, p: Vector3, tol: float) -> bool:
	var tol2 := tol * tol
	for q in pts:
		if q.distance_squared_to(p) <= tol2:
			return true
	return false


static func _flag(x: float, y: float, z: float, theta: float, dist: float,
		rp: float, cutoff: float, soi: float, rho0: float) -> int:
	var dx := x - dist * cos(theta)
	var dy := y - dist * sin(theta)
	if dx * dx + dy * dy + z * z <= soi * soi:
		return FLAG_MOON
	if rho0 > 0.0 and sqrt(x * x + y * y + z * z) - rp < cutoff:
		return FLAG_ATMO
	return FLAG_VACUUM


static func _accel(out: Array, x: float, y: float, z: float, ux: float, uy: float, uz: float,
		mx: float, my: float, m: float, cfg: SimConfig) -> void:
	var r2 := x * x + y * y + z * z
	var r := sqrt(r2)
	var k := -cfg.mu_planet() / (r2 * r)
	var ax := k * x
	var ay := k * y
	var az := k * z
	var mu_m := cfg.mu_moon()
	if mu_m > 0.0:
		var dx := mx - x
		var dy := my - y
		var dz := -z
		var d2 := dx * dx + dy * dy + dz * dz
		var d := sqrt(d2)
		var km := mu_m / (d2 * d)
		var md2 := mx * mx + my * my
		var md := sqrt(md2)
		var ki := mu_m / (md2 * md)
		ax += km * dx - ki * mx
		ay += km * dy - ki * my
		az += km * dz
	var rho := cfg.density_at(r - cfg.planet_radius)
	if rho > 0.0:
		var sp := sqrt(ux * ux + uy * uy + uz * uz)
		if sp > 0.0:
			var dk := 0.5 * rho * sp * cfg.cd * cfg.area / m
			ax -= dk * ux
			ay -= dk * uy
			az -= dk * uz
	out[0] = ax
	out[1] = ay
	out[2] = az
