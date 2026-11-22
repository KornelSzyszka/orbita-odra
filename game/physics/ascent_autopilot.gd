class_name AscentAutopilot
extends RefCounted
## Simple deterministic launch-to-orbit program (gravity turn + coast +
## circularisation). Used by the in-game demo (F2) and by headless checks to
## prove that the default rocket can reach a stable orbit.

enum Phase { ASCENT, COAST, CIRCULARIZE, DONE, FAILED }
const PHASE_NAMES := ["Ascent", "Coast to Ap", "Circularisation", "Orbit reached", "Aborted"]

var sim: OrbitalSim
var target_ap := 85_000.0         ## [m] cut the engine when Ap reaches this
var min_pe := 0.0                 ## [m] circularise until Pe above this
var turn_end_alt := 45_000.0      ## [m] altitude at which pitch reaches ~horizontal
var turn_rate := deg_to_rad(12.0) ## [rad/s] max attitude slew rate
var phase: int = Phase.ASCENT


func _init(s: OrbitalSim, ap_target: float = 85_000.0) -> void:
	sim = s
	target_ap = ap_target
	min_pe = s.cfg.atmo_cutoff + 8_000.0


func phase_name() -> String:
	return PHASE_NAMES[phase]


## Call once per physics tick *before* advancing the simulation.
func update(dt: float) -> void:
	if phase >= Phase.DONE:
		return
	if sim.status == OrbitalSim.Status.CRASHED:
		phase = Phase.FAILED
		return
	var up := sim.position().normalized()
	var east := Vector3(0, 0, 1).cross(up).normalized()  # prograde horizon direction
	var el := OrbitMath.elements(sim.px, sim.py, sim.pz, sim.vx, sim.vy, sim.vz, sim.cfg.mu_planet())
	var alt := sim.altitude()
	match phase:
		Phase.ASCENT:
			sim.set_throttle(1.0)
			var frac := clampf(alt / turn_end_alt, 0.0, 1.0)
			var pitch := deg_to_rad(90.0 - 85.0 * sqrt(frac))
			if alt < 800.0:
				pitch = deg_to_rad(90.0)
			sim.turn_towards(up * sin(pitch) + east * cos(pitch), turn_rate * dt)
			if alt > 1_000.0 and el.bound and el.ra - sim.cfg.planet_radius >= target_ap:
				sim.set_throttle(0.0)
				phase = Phase.COAST
			elif sim.fuel <= 0.0:
				phase = Phase.FAILED
		Phase.COAST:
			sim.set_throttle(0.0)
			sim.turn_towards(sim.velocity(), turn_rate * dt)
			var v_ap: float = el.h / el.ra if el.ra > 0.0 else 0.0
			var v_circ: float = sqrt(sim.cfg.mu_planet() / el.ra)
			var dv := maxf(v_circ - v_ap, 0.0)
			var burn_time: float = dv * sim.mass() / sim.cfg.max_thrust
			if el.time_to_ap >= 0.0 and el.time_to_ap <= burn_time * 0.5:
				phase = Phase.CIRCULARIZE
			elif el.radial_speed < 0.0 and alt < sim.cfg.atmo_cutoff:
				phase = Phase.CIRCULARIZE   # passed Ap without burning: burn anyway
		Phase.CIRCULARIZE:
			sim.turn_towards(sim.velocity(), turn_rate * dt)
			sim.set_throttle(1.0)
			if el.rp - sim.cfg.planet_radius >= min_pe:
				sim.set_throttle(0.0)
				phase = Phase.DONE
			elif sim.fuel <= 0.0:
				phase = Phase.FAILED
