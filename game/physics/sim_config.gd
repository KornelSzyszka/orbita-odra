class_name SimConfig
extends RefCounted
## All tunable parameters of the simulation, in SI units (m, kg, s, N).
##
## World parameters can be changed live; rocket parameters are applied by
## OrbitalSim only on reset/preset or while the rocket waits on the launch pad.

const G := 6.674e-11            ## gravitational constant [m^3 kg^-1 s^-2]
const G0 := 9.80665             ## standard gravity used only for Isp -> v_e

# --- Planet "Odra" (fictional, downscaled ~1:13 relative to Earth) ---
var planet_mass := 3.107e22         ## [kg]  -> surface g ~= 9.0 m/s^2
var planet_radius := 480_000.0      ## [m]
var atmo_rho0 := 1.2                ## sea-level air density [kg/m^3]
var atmo_scale_height := 6_500.0    ## [m]  rho(h) = rho0 * exp(-h / H)
var atmo_cutoff := 60_000.0         ## [m]  rho = 0 above this altitude

# --- Moon "Ślęża" (prescribed circular orbit in the XY plane) ---
var moon_mass := 2.357e20           ## [kg]  -> surface g ~= 1.3 m/s^2
var moon_radius := 110_000.0        ## [m]
var moon_distance := 5_000_000.0    ## [m]  centre-to-centre
var moon_moving := true             ## false = moon frozen at its current angle
var moon_start_angle := deg_to_rad(60.0)  ## [rad] placement restored on reset

# --- Rocket ---
var dry_mass := 3_000.0             ## [kg]
var fuel_capacity := 9_000.0        ## [kg]
var max_thrust := 170_000.0         ## [N]
var isp := 300.0                    ## [s]
var cd := 0.35                      ## drag coefficient (constant, no Mach term)
var area := 3.1                     ## reference cross-section [m^2]


func mu_planet() -> float:
	return G * planet_mass


func mu_moon() -> float:
	return G * moon_mass


func exhaust_velocity() -> float:
	return isp * G0


## Angular rate of the prescribed circular moon orbit (two-body, M + m).
func moon_angular_rate() -> float:
	if not moon_moving or moon_distance <= 0.0:
		return 0.0
	return sqrt(G * (planet_mass + moon_mass) / pow(moon_distance, 3.0))


func surface_gravity() -> float:
	return mu_planet() / (planet_radius * planet_radius)


## Exponential atmosphere with a hard cutoff. Returns density [kg/m^3].
func density_at(altitude: float) -> float:
	if altitude >= atmo_cutoff or atmo_rho0 <= 0.0:
		return 0.0
	return atmo_rho0 * exp(-maxf(altitude, 0.0) / atmo_scale_height)


## Moon sphere of influence (Laplace), used for classification/telemetry only.
func moon_soi() -> float:
	if planet_mass <= 0.0:
		return 0.0
	return moon_distance * pow(moon_mass / planet_mass, 0.4)


func copy() -> SimConfig:
	var c := SimConfig.new()
	for p in get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			c.set(p.name, get(p.name))
	return c
