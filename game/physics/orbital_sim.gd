class_name OrbitalSim
extends RefCounted
## Deterministic rocket flight + orbital dynamics core (no scene dependencies).
##
## Frame: inertial, centred on planet "Odra" (planet does not move/rotate).
## The moon follows a prescribed circular orbit in the XY plane; the indirect
## term (acceleration of the planet towards the moon) is applied to the rocket
## so the planet-centred frame stays consistent.
## Rocket: 3-DOF point mass with variable mass and a kinematic orientation
## (Basis, local +Y = nose / thrust axis). Integrator: fixed-step
## Kick-Drift-Kick leapfrog. State scalars are float64 (GDScript float).

signal event_happened(kind: String, message: String)

enum Status { LANDED, FLYING, CRASHED }
enum Body { PLANET, MOON }

const DT := 1.0 / 60.0                 ## fixed physics sub-step [s]
const SAFE_LANDING_SPEED := 6.0        ## [m/s] soft landing threshold
const HARD_LANDING_SPEED := 20.0       ## [m/s] above this the rocket is destroyed
const MAX_TILT_DEG := 30.0             ## landing tilt above this tips the rocket over
const ORBIT_PRESET_ALT := 100_000.0    ## [m]
var transfer_lead := -0.30          ## [rad] arrival phase offset vs. moon; tuned for a ~340 km flyby (0 = impact)

var cfg: SimConfig

# --- state (float64) ---
var t := 0.0
var px := 0.0
var py := 0.0
var pz := 0.0
var vx := 0.0
var vy := 0.0
var vz := 0.0
var fuel := 0.0
var throttle := 0.0                    ## commanded 0..1
var orientation := Basis.IDENTITY      ## local +Y = thrust direction
var status: int = Status.LANDED
var landed_body: int = Body.PLANET
var launched := false                  ## false while waiting on the pad before first liftoff
var engine_damaged := false
var moon_angle := 0.0                  ## [rad] current moon phase angle

# landed offset relative to the body centre (keeps rocket glued to a moving moon)
var _lox := 0.0
var _loy := 0.0
var _loz := 0.0
var _in_atmo := false
var _fuel_warned := false

# --- last-step diagnostics (for telemetry) ---
var last_thrust := 0.0                 ## [N] actual thrust produced
var last_density := 0.0                ## [kg/m^3]
var last_drag := 0.0                   ## [N] drag magnitude
var last_dynamic_pressure := 0.0       ## [Pa]
var last_proper_accel := 0.0           ## [m/s^2] |thrust + drag| / m (what an accelerometer reads)
var last_total_accel := 0.0            ## [m/s^2] |total coordinate acceleration|
var last_gravity := 0.0                ## [m/s^2] |gravity| (planet + moon, incl. indirect term)
var last_impact_speed := 0.0

# scratch outputs of _accel (avoids allocating vectors in the hot loop)
var _ax := 0.0
var _ay := 0.0
var _az := 0.0


func _init(config: SimConfig = null) -> void:
	cfg = config if config != null else SimConfig.new()
	reset_to_pad()


# ------------------------------------------------------------------ presets

## Rocket on the launch pad at the planet's +Y pole, engine off, full tank.
func reset_to_pad() -> void:
	t = 0.0
	moon_angle = cfg.moon_start_angle
	px = 0.0; py = cfg.planet_radius; pz = 0.0
	vx = 0.0; vy = 0.0; vz = 0.0
	fuel = cfg.fuel_capacity
	throttle = 0.0
	orientation = Basis.IDENTITY
	status = Status.LANDED
	landed_body = Body.PLANET
	_lox = px; _loy = py; _loz = pz
	launched = false
	engine_damaged = false
	_in_atmo = cfg.atmo_cutoff > 0.0
	_fuel_warned = false
	_clear_diag()
	event_happened.emit("reset", "Rocket on the launch pad")


## Circular, equatorial (moon-plane), prograde orbit above the pad.
func set_circular_orbit(altitude: float = ORBIT_PRESET_ALT) -> void:
	reset_to_pad()
	var r := cfg.planet_radius + altitude
	var v := sqrt(cfg.mu_planet() / r)
	_place_on_orbit(PI * 0.5, r, v)
	event_happened.emit("preset", "Circular orbit %.0f km" % (altitude / 1000.0))


## Hohmann-like transfer: rocket at periapsis (100 km) on an ellipse whose
## apoapsis reaches the moon's orbit, timed (transfer_lead) for a close flyby.
func set_moon_transfer() -> void:
	reset_to_pad()
	var mu := cfg.mu_planet()
	var r1 := cfg.planet_radius + ORBIT_PRESET_ALT
	var r2 := cfg.moon_distance
	var a := 0.5 * (r1 + r2)
	var v_p := sqrt(mu * (2.0 / r1 - 1.0 / a))
	var t_half := PI * sqrt(a * a * a / mu)
	var arrival_moon_angle := moon_angle + cfg.moon_angular_rate() * t_half
	var phi := arrival_moon_angle + transfer_lead - PI
	_place_on_orbit(phi, r1, v_p)
	event_happened.emit("preset", "Transfer trajectory to Ślęża")


func _place_on_orbit(phi: float, r: float, v: float) -> void:
	px = r * cos(phi); py = r * sin(phi); pz = 0.0
	vx = -v * sin(phi); vy = v * cos(phi); vz = 0.0
	# point the nose prograde: rotate +Y onto the velocity direction (about +Z)
	orientation = Basis(Vector3(0, 0, 1), phi)
	status = Status.FLYING
	launched = true
	_in_atmo = false


# ------------------------------------------------------------------ control

func set_throttle(value: float) -> void:
	throttle = clampf(value, 0.0, 1.0)


## Rotate about the rocket's local axes. pitch: about local Z (W = nose
## towards local -X, i.e. "east" on the pad); yaw: about local X.
func rotate_pitch_yaw(pitch_rad: float, yaw_rad: float) -> void:
	if status == Status.CRASHED:
		return
	if pitch_rad != 0.0:
		orientation = orientation * Basis(Vector3(0, 0, 1), pitch_rad)
	if yaw_rad != 0.0:
		orientation = orientation * Basis(Vector3(1, 0, 0), yaw_rad)
	orientation = orientation.orthonormalized()


## Turn the nose towards a world direction by at most max_angle (shortest arc).
func turn_towards(dir: Vector3, max_angle: float) -> void:
	if dir.length_squared() < 1e-12 or status == Status.CRASHED:
		return
	var cur := orientation.y.normalized()
	var target := dir.normalized()
	var angle := cur.angle_to(target)
	if angle < 1e-6:
		return
	var axis := cur.cross(target)
	if axis.length_squared() < 1e-12:
		axis = orientation.x
	orientation = (Basis(axis.normalized(), minf(angle, max_angle)) * orientation).orthonormalized()


func apply_rocket_config_if_on_pad() -> bool:
	if is_on_pad():
		fuel = cfg.fuel_capacity
		return true
	return false


func is_on_pad() -> bool:
	return status == Status.LANDED and not launched


# ------------------------------------------------------------------ queries

func mass() -> float:
	return cfg.dry_mass + fuel


func position() -> Vector3:
	return Vector3(px, py, pz)


func velocity() -> Vector3:
	return Vector3(vx, vy, vz)


func radius() -> float:
	return sqrt(px * px + py * py + pz * pz)


func altitude() -> float:
	return radius() - cfg.planet_radius


func speed() -> float:
	return sqrt(vx * vx + vy * vy + vz * vz)


func fuel_fraction() -> float:
	return fuel / cfg.fuel_capacity if cfg.fuel_capacity > 0.0 else 0.0


func moon_pos_at_angle(angle: float) -> Vector3:
	return Vector3(cfg.moon_distance * cos(angle), cfg.moon_distance * sin(angle), 0.0)


func moon_position() -> Vector3:
	return moon_pos_at_angle(moon_angle)


func moon_velocity() -> Vector3:
	var w := cfg.moon_angular_rate()
	return Vector3(-cfg.moon_distance * w * sin(moon_angle), cfg.moon_distance * w * cos(moon_angle), 0.0)


func moon_altitude() -> float:
	var m := moon_position()
	return sqrt(pow(px - m.x, 2) + pow(py - m.y, 2) + pow(pz - m.z, 2)) - cfg.moon_radius


func in_moon_soi() -> bool:
	return moon_altitude() + cfg.moon_radius < cfg.moon_soi()


## Thrust-to-weight ratio against the local reference body's Newtonian gravity.
func twr() -> float:
	var lunar := _uses_lunar_surface_frame()
	var distance := moon_altitude() + cfg.moon_radius if lunar else radius()
	var mu := cfg.mu_moon() if lunar else cfg.mu_planet()
	var g := mu / maxf(distance * distance, 1.0)
	var m := mass()
	if g <= 0.0 or m <= 0.0 or engine_damaged or fuel <= 0.0:
		return 0.0
	return cfg.max_thrust * throttle / (m * g)


## Angle of the nose above the local horizon of the reference body [deg].
func pitch_above_horizon() -> float:
	var center := moon_position() if _uses_lunar_surface_frame() else Vector3.ZERO
	var up := Vector3(px - center.x, py - center.y, pz - center.z).normalized()
	return rad_to_deg(asin(clampf(orientation.y.normalized().dot(up), -1.0, 1.0)))


func _uses_lunar_surface_frame() -> bool:
	return (status != Status.FLYING and landed_body == Body.MOON) or in_moon_soi()


## Orbital elements relative to the dominant body (moon inside its SOI).
func orbit_elements() -> Dictionary:
	if in_moon_soi():
		var m := moon_position()
		var mv := moon_velocity()
		var el := OrbitMath.elements(px - m.x, py - m.y, pz - m.z,
				vx - mv.x, vy - mv.y, vz - mv.z, cfg.mu_moon())
		el["body"] = Body.MOON
		el["body_radius"] = cfg.moon_radius
		el["center"] = m
		return el
	var e := OrbitMath.elements(px, py, pz, vx, vy, vz, cfg.mu_planet())
	e["body"] = Body.PLANET
	e["body_radius"] = cfg.planet_radius
	e["center"] = Vector3.ZERO
	return e


# ------------------------------------------------------------------ integration

## Advance by `seconds` of simulation time in fixed DT sub-steps.
func advance(seconds: float) -> void:
	var n := int(round(seconds / DT))
	for i in n:
		step(DT)


## One Kick-Drift-Kick leapfrog step of length dt.
func step(dt: float) -> void:
	if status == Status.CRASHED:
		t += dt
		_advance_moon(dt)
		if landed_body == Body.MOON:
			var center := moon_position()
			var surface_velocity := moon_velocity()
			px = center.x + _lox; py = center.y + _loy; pz = center.z + _loz
			vx = surface_velocity.x; vy = surface_velocity.y; vz = surface_velocity.z
		return

	var m0 := mass()
	var thrust := _available_thrust(dt)
	var tdx := orientation.y.x
	var tdy := orientation.y.y
	var tdz := orientation.y.z
	var tlen := sqrt(tdx * tdx + tdy * tdy + tdz * tdz)
	tdx /= tlen; tdy /= tlen; tdz /= tlen

	if status == Status.LANDED:
		_step_landed(dt, thrust, tdx, tdy, tdz, m0)
		if status == Status.LANDED:
			return

	# --- kick (half) ---
	var mpos := moon_pos_at_angle(moon_angle)
	_accel(px, py, pz, vx, vy, vz, mpos, m0, thrust, tdx, tdy, tdz)
	var hvx := vx + _ax * dt * 0.5
	var hvy := vy + _ay * dt * 0.5
	var hvz := vz + _az * dt * 0.5
	# --- drift ---
	px += hvx * dt
	py += hvy * dt
	pz += hvz * dt
	_burn_fuel(thrust, dt)
	t += dt
	_advance_moon(dt)
	# --- kick (half) ---
	var m1 := mass()
	mpos = moon_pos_at_angle(moon_angle)
	_accel(px, py, pz, hvx, hvy, hvz, mpos, m1, thrust, tdx, tdy, tdz)
	vx = hvx + _ax * dt * 0.5
	vy = hvy + _ay * dt * 0.5
	vz = hvz + _az * dt * 0.5
	last_total_accel = sqrt(_ax * _ax + _ay * _ay + _az * _az)
	last_thrust = thrust

	_check_events()
	_check_collisions()


func _step_landed(dt: float, thrust: float, tdx: float, tdy: float, tdz: float, m0: float) -> void:
	# glue to surface, then test whether net force pushes away from the body
	var c := Vector3.ZERO
	var cv := Vector3.ZERO
	var body_r := cfg.planet_radius
	if landed_body == Body.MOON:
		c = moon_position()
		cv = moon_velocity()
		body_r = cfg.moon_radius
	var ol := sqrt(_lox * _lox + _loy * _loy + _loz * _loz)
	var nx := _lox / ol
	var ny := _loy / ol
	var nz := _loz / ol
	px = c.x + nx * body_r; py = c.y + ny * body_r; pz = c.z + nz * body_r
	vx = cv.x; vy = cv.y; vz = cv.z
	_accel(px, py, pz, vx, vy, vz, moon_position(), m0, thrust, tdx, tdy, tdz)
	var bax := 0.0
	var bay := 0.0
	if landed_body == Body.MOON:
		var w := cfg.moon_angular_rate()
		bax = -w * w * c.x
		bay = -w * w * c.y
	var radial := (_ax - bax) * nx + (_ay - bay) * ny + _az * nz
	last_thrust = thrust
	last_total_accel = 0.0
	if radial > 0.0 and thrust > 0.0:
		status = Status.FLYING
		if not launched:
			launched = true
			event_happened.emit("liftoff", "Liftoff! The rocket has cleared the pad")
		else:
			event_happened.emit("liftoff", "Liftoff from the surface")
		return
	# still on the ground: time passes, fuel burns (engine may be below TWR 1)
	_burn_fuel(thrust, dt)
	t += dt
	_advance_moon(dt)
	if landed_body == Body.MOON:
		var c2 := moon_position()
		var cv2 := moon_velocity()
		px = c2.x + nx * body_r; py = c2.y + ny * body_r; pz = c2.z + nz * body_r
		vx = cv2.x; vy = cv2.y; vz = cv2.z
	else:
		px = nx * body_r; py = ny * body_r; pz = nz * body_r


func _available_thrust(dt: float) -> float:
	if engine_damaged or fuel <= 0.0 or throttle <= 0.0:
		return 0.0
	var thrust := cfg.max_thrust * throttle
	var ve := cfg.exhaust_velocity()
	var burn := thrust / ve * dt
	if burn > fuel:
		thrust *= fuel / burn   # last partial step
	return thrust


func _burn_fuel(thrust: float, dt: float) -> void:
	if thrust <= 0.0:
		return
	fuel = maxf(fuel - thrust / cfg.exhaust_velocity() * dt, 0.0)
	if fuel <= 0.0 and not _fuel_warned:
		_fuel_warned = true
		event_happened.emit("fuel_out", "Out of fuel — engine off")


func _advance_moon(dt: float) -> void:
	moon_angle = fposmod(moon_angle + cfg.moon_angular_rate() * dt, TAU)


## Total acceleration at a given state -> (_ax, _ay, _az). Also updates diagnostics.
func _accel(x: float, y: float, z: float, ux: float, uy: float, uz: float,
		mpos: Vector3, m: float, thrust: float, tdx: float, tdy: float, tdz: float) -> void:
	var r2 := x * x + y * y + z * z
	var r := sqrt(r2)
	var mu_p := cfg.mu_planet()
	var k := -mu_p / (r2 * r)
	var ax := k * x
	var ay := k * y
	var az := k * z
	# moon: direct term + indirect term (planet accelerates towards the moon)
	var mu_m := cfg.mu_moon()
	if mu_m > 0.0:
		var dx := mpos.x - x
		var dy := mpos.y - y
		var dz := mpos.z - z
		var d2 := dx * dx + dy * dy + dz * dz
		var d := sqrt(d2)
		var km := mu_m / (d2 * d)
		var md2 := mpos.x * mpos.x + mpos.y * mpos.y + mpos.z * mpos.z
		var md := sqrt(md2)
		var ki := mu_m / (md2 * md)
		ax += km * dx - ki * mpos.x
		ay += km * dy - ki * mpos.y
		az += km * dz - ki * mpos.z
	last_gravity = sqrt(ax * ax + ay * ay + az * az)
	# thrust
	var fx := thrust * tdx
	var fy := thrust * tdy
	var fz := thrust * tdz
	# drag (air at rest in the planet frame — planet does not rotate)
	var rho := cfg.density_at(r - cfg.planet_radius)
	var sp := sqrt(ux * ux + uy * uy + uz * uz)
	var drag := 0.0
	if rho > 0.0 and sp > 0.0:
		var q := 0.5 * rho * sp * sp
		drag = q * cfg.cd * cfg.area
		fx -= drag * ux / sp
		fy -= drag * uy / sp
		fz -= drag * uz / sp
		last_dynamic_pressure = q
	else:
		last_dynamic_pressure = 0.0
	last_density = rho
	last_drag = drag
	last_proper_accel = sqrt(fx * fx + fy * fy + fz * fz) / m
	_ax = ax + fx / m
	_ay = ay + fy / m
	_az = az + fz / m


func _check_events() -> void:
	var alt := altitude()
	var inside := alt < cfg.atmo_cutoff and cfg.atmo_rho0 > 0.0
	if inside != _in_atmo:
		_in_atmo = inside
		if inside:
			event_happened.emit("atmo_enter", "Entering the atmosphere")
		else:
			event_happened.emit("atmo_exit", "Leaving the atmosphere — vacuum")


func _check_collisions() -> void:
	var r := radius()
	if r <= cfg.planet_radius:
		_touch_down(Body.PLANET, Vector3.ZERO, Vector3.ZERO, cfg.planet_radius)
		return
	var m := moon_position()
	var dx := px - m.x
	var dy := py - m.y
	var dz := pz - m.z
	if dx * dx + dy * dy + dz * dz <= cfg.moon_radius * cfg.moon_radius:
		_touch_down(Body.MOON, m, moon_velocity(), cfg.moon_radius)


func _touch_down(body: int, c: Vector3, cv: Vector3, body_r: float) -> void:
	var rel := Vector3(px - c.x, py - c.y, pz - c.z)
	var n := rel.normalized()
	var rvx := vx - cv.x
	var rvy := vy - cv.y
	var rvz := vz - cv.z
	var impact := sqrt(rvx * rvx + rvy * rvy + rvz * rvz)
	last_impact_speed = impact
	var tilt := rad_to_deg(orientation.y.normalized().angle_to(n))
	# put the rocket exactly on the surface
	_lox = n.x * body_r; _loy = n.y * body_r; _loz = n.z * body_r
	px = c.x + _lox; py = c.y + _loy; pz = c.z + _loz
	vx = cv.x; vy = cv.y; vz = cv.z
	landed_body = body
	var where := "on Odra" if body == Body.PLANET else "on Ślęża"
	if impact > HARD_LANDING_SPEED:
		status = Status.CRASHED
		throttle = 0.0
		event_happened.emit("crash", "CRASH %s — impact at %.0f m/s" % [where, impact])
	elif tilt > MAX_TILT_DEG:
		status = Status.CRASHED
		throttle = 0.0
		event_happened.emit("crash", "Rocket tipped over %s (tilt %.0f°)" % [where, tilt])
	elif impact > SAFE_LANDING_SPEED:
		status = Status.LANDED
		engine_damaged = true
		throttle = 0.0
		event_happened.emit("hard_landing", "Hard landing %s (%.1f m/s) — engine damaged" % [where, impact])
	else:
		status = Status.LANDED
		event_happened.emit("landed", "Successful landing %s (%.1f m/s)" % [where, impact])


func _clear_diag() -> void:
	last_thrust = 0.0
	last_density = cfg.density_at(altitude())
	last_drag = 0.0
	last_dynamic_pressure = 0.0
	last_proper_accel = 0.0
	last_total_accel = 0.0
	last_gravity = cfg.surface_gravity()
	last_impact_speed = 0.0


## Snapshot of the full dynamic state (used by tests / determinism checks).
func snapshot() -> Dictionary:
	return {
		"t": t, "px": px, "py": py, "pz": pz, "vx": vx, "vy": vy, "vz": vz,
		"fuel": fuel, "throttle": throttle, "status": status,
		"landed_body": landed_body, "moon_angle": moon_angle,
		"altitude": altitude(), "speed": speed(),
	}
