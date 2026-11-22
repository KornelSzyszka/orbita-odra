class_name OrbitMath
extends RefCounted
## Osculating two-body orbital elements computed from a state vector.
## Inputs are float64 scalars relative to the attracting body's centre.


## Returns a Dictionary:
##  energy, a, e, rp, ra (INF if unbound), period (INF if unbound),
##  pe_dir / ap_dir (Vector3 unit, Vector3.ZERO for ~circular orbits),
##  time_to_pe, time_to_ap (seconds, -1 if undefined), bound (bool),
##  radial_speed, horizontal_speed, h (specific angular momentum magnitude).
static func elements(rx: float, ry: float, rz: float,
		vx: float, vy: float, vz: float, mu: float) -> Dictionary:
	var out := {
		"energy": 0.0, "a": INF, "e": 0.0, "rp": 0.0, "ra": INF,
		"period": INF, "pe_dir": Vector3.ZERO, "ap_dir": Vector3.ZERO,
		"time_to_pe": -1.0, "time_to_ap": -1.0, "bound": false,
		"radial_speed": 0.0, "horizontal_speed": 0.0, "h": 0.0,
	}
	var r := sqrt(rx * rx + ry * ry + rz * rz)
	if r <= 0.0 or mu <= 0.0:
		return out
	var v2 := vx * vx + vy * vy + vz * vz
	var rdotv := rx * vx + ry * vy + rz * vz
	var vr := rdotv / r
	out.radial_speed = vr
	out.horizontal_speed = sqrt(maxf(v2 - vr * vr, 0.0))
	var energy := 0.5 * v2 - mu / r
	out.energy = energy
	# angular momentum h = r x v
	var hx := ry * vz - rz * vy
	var hy := rz * vx - rx * vz
	var hz := rx * vy - ry * vx
	var h2 := hx * hx + hy * hy + hz * hz
	var h := sqrt(h2)
	out.h = h
	# eccentricity vector e = (v x h)/mu - r/|r|
	var ex := (vy * hz - vz * hy) / mu - rx / r
	var ey := (vz * hx - vx * hz) / mu - ry / r
	var ez := (vx * hy - vy * hx) / mu - rz / r
	var e := sqrt(ex * ex + ey * ey + ez * ez)
	out.e = e
	out.rp = h2 / mu / (1.0 + e)
	if e > 1e-5:
		var pe_dir := Vector3(ex / e, ey / e, ez / e)
		out.pe_dir = pe_dir
		out.ap_dir = -pe_dir
	# Radial motion below escape speed is a degenerate ellipse (e = 1).
	if energy < 0.0:
		var a := -mu / (2.0 * energy)
		out.a = a
		out.ra = a * (1.0 + e)
		out.bound = true
		var period := TAU * sqrt(a * a * a / mu)
		out.period = period
		if e > 1e-5:
			# r = a(1 - e cos E). Using radius remains valid as angular momentum approaches zero.
			var ecc_anom := acos(clampf((1.0 - r / a) / e, -1.0, 1.0))
			if vr < 0.0:
				ecc_anom = TAU - ecc_anom
			var mean_anom := fposmod(ecc_anom - e * sin(ecc_anom), TAU)
			var t_since_pe := mean_anom / TAU * period
			out.time_to_pe = fposmod(period - t_since_pe, period)
			out.time_to_ap = fposmod(0.5 * period - t_since_pe, period)
	else:
		out.a = -mu / (2.0 * energy) if absf(energy) > 1e-12 else -INF
		if e > 1.0 + 1e-6 and rdotv < 0.0:
			var cos_nu2 := clampf((ex * rx + ey * ry + ez * rz) / (e * r), -1.0, 1.0)
			var nu2 := acos(cos_nu2)  # approaching: nu in (-pi, 0) -> use |nu|
			var f_anom := 2.0 * atanh(sqrt((e - 1.0) / (e + 1.0)) * tan(nu2 * 0.5))
			var m_h := e * sinh(f_anom) - f_anom
			var n := sqrt(mu / pow(-out.a, 3.0))
			out.time_to_pe = m_h / n
	return out
