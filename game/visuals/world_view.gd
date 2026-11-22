class_name WorldView
extends Node3D
## Visual representation of the planet system (floating origin).
##
## The rocket is always rendered at the scene origin. `planet_frame` is placed
## at (planet centre - rocket position), computed in float64 before casting, so
## nearby geometry keeps full float32 precision. The launch site (pad + detailed
## ground patch) is positioned separately relative to the origin for the same
## reason. Everything is procedural (meshes + shaders), no external assets.

## Direction towards the sun (world). Chosen so the default chase camera sees the
## pad front-lit from the side and the default map view shows a day/night terminator.
const SUN_DIR := Vector3(0.38, 0.78, -0.50)
const CLOUD_ALT := 5_000.0                    # [m] cloud shell height above the surface
const MAP_CAMERA_DIST := 60_000.0             # [m] camera this far from the rocket = map view
const PATCH_HALF := 30_000.0                  # [m] half size of the launch-site patch
const PATCH_RES := 72

var planet_frame: Node3D
var planet_mesh: MeshInstance3D
var atmo_mesh: MeshInstance3D
var moon_node: Node3D
var moon_mesh: MeshInstance3D
var pad_frame: Node3D
var patch_mesh: MeshInstance3D
var sun: DirectionalLight3D
var environment: Environment
var sky_material: ShaderMaterial
var atmo_material: ShaderMaterial
var cloud_mesh: MeshInstance3D
var cloud_material: ShaderMaterial
var bounce: DirectionalLight3D

var _planet_material: ShaderMaterial
var _patch_material: ShaderMaterial
var _patch_radius := -1.0


func _ready() -> void:
	planet_frame = Node3D.new()
	planet_frame.name = "PlanetFrame"
	add_child(planet_frame)

	_planet_material = ShaderMaterial.new()
	_planet_material.shader = preload("res://game/visuals/shaders/planet.gdshader")
	_planet_material.set_shader_parameter("sun_dir", SUN_DIR.normalized())
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 192
	sphere.rings = 96
	planet_mesh = MeshInstance3D.new()
	planet_mesh.name = "Planet"
	planet_mesh.mesh = sphere
	planet_mesh.material_override = _planet_material
	planet_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	planet_frame.add_child(planet_mesh)

	atmo_material = ShaderMaterial.new()
	atmo_material.shader = preload("res://game/visuals/shaders/atmosphere.gdshader")
	atmo_material.set_shader_parameter("sun_dir", SUN_DIR.normalized())
	var shell := SphereMesh.new()
	shell.radius = 1.0
	shell.height = 2.0
	shell.radial_segments = 128
	shell.rings = 64
	atmo_mesh = MeshInstance3D.new()
	atmo_mesh.name = "Atmosphere"
	atmo_mesh.mesh = shell
	atmo_mesh.material_override = atmo_material
	atmo_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	planet_frame.add_child(atmo_mesh)

	cloud_material = ShaderMaterial.new()
	cloud_material.shader = preload("res://game/visuals/shaders/clouds.gdshader")
	cloud_material.set_shader_parameter("sun_dir", SUN_DIR.normalized())
	cloud_material.render_priority = -1   # before the additive atmosphere
	var cshell := SphereMesh.new()
	cshell.radius = 1.0
	cshell.height = 2.0
	cshell.radial_segments = 192
	cshell.rings = 96
	cloud_mesh = MeshInstance3D.new()
	cloud_mesh.name = "Clouds"
	cloud_mesh.mesh = cshell
	cloud_mesh.material_override = cloud_material
	cloud_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	planet_frame.add_child(cloud_mesh)

	moon_node = Node3D.new()
	moon_node.name = "Moon"
	planet_frame.add_child(moon_node)
	var moon_sphere := SphereMesh.new()
	moon_sphere.radius = 1.0
	moon_sphere.height = 2.0
	moon_sphere.radial_segments = 128
	moon_sphere.rings = 64
	moon_mesh = MeshInstance3D.new()
	moon_mesh.mesh = moon_sphere
	var moon_mat := ShaderMaterial.new()
	moon_mat.shader = preload("res://game/visuals/shaders/moon.gdshader")
	moon_mesh.material_override = moon_mat
	moon_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	moon_node.add_child(moon_mesh)

	pad_frame = Node3D.new()
	pad_frame.name = "LaunchSite"
	add_child(pad_frame)
	_patch_material = ShaderMaterial.new()
	_patch_material.shader = _planet_material.shader
	_patch_material.set_shader_parameter("sun_dir", SUN_DIR.normalized())
	patch_mesh = MeshInstance3D.new()
	patch_mesh.material_override = _patch_material
	patch_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pad_frame.add_child(patch_mesh)
	_build_pad_structures()

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.5
	sun.light_color = Color(1.0, 0.96, 0.90)
	sun.shadow_enabled = false
	add_child(sun)
	sun.basis = Basis.looking_at(-SUN_DIR.normalized(), Vector3(0, 0, 1))
	# light reflected by the planet below the rocket (no specular), aimed each frame
	bounce = DirectionalLight3D.new()
	bounce.name = "PlanetBounce"
	bounce.light_specular = 0.0
	bounce.light_energy = 0.3
	bounce.shadow_enabled = false
	bounce.light_cull_mask = RocketView.BOUNCE_LAYER   # lights the rocket only, never the planet
	add_child(bounce)

	sky_material = ShaderMaterial.new()
	sky_material.shader = preload("res://game/visuals/shaders/sky.gdshader")
	sky_material.set_shader_parameter("sun_dir", SUN_DIR.normalized())
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.16, 0.18, 0.24)
	environment.ambient_light_energy = 0.5
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.05
	environment.tonemap_white = 6.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.7
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 1.1
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.12
	environment.adjustment_contrast = 1.06
	# aerial perspective near the ground; density follows the local air (update_view)
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_light_color = Color(0.58, 0.70, 0.86)
	environment.fog_density = 0.0
	environment.fog_sky_affect = 0.0
	environment.fog_sun_scatter = 0.25
	var we := WorldEnvironment.new()
	we.environment = environment
	add_child(we)


func _std(color: Color, metallic := 0.0, roughness := 0.8, emission := Color.BLACK) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if emission != Color.BLACK:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = 3.0
	return m


func _box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, mat: Material, pos: Vector3, segs := 24) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = segs
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## Launch complex in pad-local axes (+Y up, "east" = -X; the default chase
## camera looks from +X/-Z). Structures stay out of the camera's line of sight:
## the lattice tower stands behind the rocket to one side, tanks and masts
## behind, the hangar far down the access road.
func _build_pad_structures() -> void:
	var concrete := _std(Color(0.58, 0.58, 0.56), 0.0, 0.95)
	var dark_concrete := _std(Color(0.20, 0.20, 0.21), 0.0, 0.95)
	var steel := _std(Color(0.86, 0.33, 0.14), 0.35, 0.55)
	var white := _std(Color(0.88, 0.89, 0.90), 0.2, 0.45)
	var grey := _std(Color(0.42, 0.44, 0.47), 0.6, 0.5)
	var red_lamp := _std(Color(0.3, 0.02, 0.02), 0.0, 0.5, Color(1.0, 0.12, 0.08))
	var hangar_mat := _std(Color(0.78, 0.80, 0.82), 0.3, 0.6)
	var stripe := _std(Color(0.10, 0.22, 0.48), 0.2, 0.6)

	# pad: stepped octagonal plinth + flame-trench deflector
	_cyl(pad_frame, 13.0, 15.0, 3.0, concrete, Vector3(0, -1.5, 0), 8)
	_cyl(pad_frame, 20.0, 22.0, 1.4, concrete, Vector3(0, -2.4, 0), 8)
	var cam_dir := Vector3(0.906, 0.0, -0.423)          # default chase camera (horizontal)
	var side := Vector3(0.423, 0.0, 0.906)               # perpendicular to it
	var behind := -cam_dir
	var trench := _box(pad_frame, Vector3(5.0, 0.2, 26.0), dark_concrete, behind * 14.0 + Vector3(0, -0.05, 0))
	trench.rotation = Vector3(0, atan2(behind.x, behind.z), 0)
	for k in 4:   # hold-down clamps around the nozzle
		var a := k * PI * 0.5 + PI * 0.25
		_box(pad_frame, Vector3(0.5, 1.2, 0.5), grey, Vector3(cos(a) * 1.9, 0.6, sin(a) * 1.9))

	# lattice service tower
	var tower := Node3D.new()
	tower.name = "ServiceTower"
	tower.position = behind * 8.5 - side * 6.0
	tower.rotation = Vector3(0, atan2(cam_dir.x, cam_dir.z), 0)
	pad_frame.add_child(tower)
	var w := 3.2
	var hgt := 30.0
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			_box(tower, Vector3(0.28, hgt, 0.28), steel, Vector3(cx * w * 0.5, hgt * 0.5, cz * w * 0.5))
	var level := 0.0
	var diag := sqrt(w * w + 9.0)
	var ang := atan2(3.0, w)
	while level <= hgt:
		_box(tower, Vector3(w, 0.18, 0.18), steel, Vector3(0, level, -w * 0.5))
		_box(tower, Vector3(w, 0.18, 0.18), steel, Vector3(0, level, w * 0.5))
		_box(tower, Vector3(0.18, 0.18, w), steel, Vector3(-w * 0.5, level, 0))
		_box(tower, Vector3(0.18, 0.18, w), steel, Vector3(w * 0.5, level, 0))
		if level + 3.0 <= hgt:
			_box(tower, Vector3(diag, 0.12, 0.12), steel, Vector3(0, level + 1.5, w * 0.5), Vector3(0, 0, ang))
			_box(tower, Vector3(diag, 0.12, 0.12), steel, Vector3(0, level + 1.5, -w * 0.5), Vector3(0, 0, -ang))
			_box(tower, Vector3(0.12, 0.12, diag), steel, Vector3(w * 0.5, level + 1.5, 0), Vector3(ang, 0, 0))
			_box(tower, Vector3(0.12, 0.12, diag), steel, Vector3(-w * 0.5, level + 1.5, 0), Vector3(-ang, 0, 0))
		level += 3.0
	_box(tower, Vector3(w + 1.0, 0.4, w + 1.0), grey, Vector3(0, hgt + 0.2, 0))
	_box(tower, Vector3(0.3, 0.3, 0.3), red_lamp, Vector3(0, hgt + 0.6, 0))
	# swing arms reaching to the rocket
	var to_rocket := -tower.position
	to_rocket.y = 0.0
	var reach := to_rocket.length() - 1.3
	var arms := Node3D.new()
	arms.position = tower.position
	arms.rotation = Vector3(0, atan2(to_rocket.x, to_rocket.z), 0)
	pad_frame.add_child(arms)
	for y in [7.0, 14.5, 21.0]:
		_box(arms, Vector3(0.9, 0.5, reach - 1.6), grey, Vector3(0, y, 1.6 + (reach - 1.6) * 0.5))
		_box(arms, Vector3(1.3, 1.1, 0.4), white, Vector3(0, y, reach - 0.2))

	# lightning masts with red beacons
	for mp in [behind * 34.0 + side * 22.0, behind * 30.0 - side * 30.0, behind * 60.0 - side * 4.0]:
		_cyl(pad_frame, 0.18, 0.35, 44.0, grey, mp + Vector3(0, 22.0, 0), 8)
		_box(pad_frame, Vector3(0.5, 0.5, 0.5), red_lamp, mp + Vector3(0, 44.3, 0))

	# propellant tanks (spheres on short legs) and a water tower
	for tp in [behind * 48.0 + side * 6.0, behind * 48.0 + side * 16.0]:
		var sph := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 4.0
		sm.height = 8.0
		sph.mesh = sm
		sph.material_override = white
		sph.position = tp + Vector3(0, 6.0, 0)
		pad_frame.add_child(sph)
		_cyl(pad_frame, 2.0, 2.6, 2.2, grey, tp + Vector3(0, 1.1, 0), 12)
	var wt := behind * 40.0 - side * 22.0
	_cyl(pad_frame, 3.2, 3.2, 6.0, white, wt + Vector3(0, 20.0, 0), 20)
	_cyl(pad_frame, 0.0, 3.2, 1.6, white, wt + Vector3(0, 23.8, 0), 20)
	for k in 4:
		var a := k * PI * 0.5
		_cyl(pad_frame, 0.2, 0.25, 17.0, grey, wt + Vector3(cos(a) * 2.6, 8.5, sin(a) * 2.6), 6)

	# assembly hangar at the end of the access road (matches the planet.gdshader yard)
	var hangar := _box(pad_frame, Vector3(70.0, 34.0, 52.0), hangar_mat, Vector3(-420.0, 17.0, -640.0))
	hangar.name = "Hangar"
	_box(pad_frame, Vector3(70.4, 4.0, 52.4), stripe, Vector3(-420.0, 28.0, -640.0))
	_box(pad_frame, Vector3(24.0, 28.0, 0.6), dark_concrete, Vector3(-420.0, 14.0, -613.7))

	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 30, 0) + behind * 6.0
	lamp.light_energy = 0.5
	lamp.light_color = Color(1.0, 0.92, 0.8)
	lamp.omni_range = 120.0
	pad_frame.add_child(lamp)


## Detailed, correctly curved ground around the launch site. Vertices are
## stored relative to the pad (small numbers) and the shader gets the offset.
func _rebuild_patch(radius: float) -> void:
	_patch_radius = radius
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pad := Vector3(0, radius, 0)
	var n := PATCH_RES
	for j in n + 1:
		for i in n + 1:
			var u := (float(i) / n * 2.0 - 1.0)
			var v := (float(j) / n * 2.0 - 1.0)
			# denser near the centre
			var x := signf(u) * u * u * PATCH_HALF
			var z := signf(v) * v * v * PATCH_HALF
			var dir := Vector3(x, radius, z).normalized()
			st.set_normal(dir)
			st.add_vertex(dir * (radius + 0.15) - pad)
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			var b := a + 1
			var c := a + (n + 1)
			var d := c + 1
			st.add_index(a); st.add_index(c); st.add_index(b)
			st.add_index(b); st.add_index(c); st.add_index(d)
	patch_mesh.mesh = st.commit()
	_patch_material.set_shader_parameter("local_offset", pad)


## origin: rocket render position (float64 components) relative to planet centre.
func update_view(sim: OrbitalSim, ox: float, oy: float, oz: float, moon_angle: float) -> void:
	var cfg := sim.cfg
	planet_frame.position = Vector3(-ox, -oy, -oz)
	var r := cfg.planet_radius
	planet_mesh.scale = Vector3.ONE * r
	var has_atmo := cfg.atmo_rho0 > 0.0 and cfg.atmo_cutoff > 0.0
	atmo_mesh.visible = has_atmo
	if has_atmo:
		atmo_mesh.scale = Vector3.ONE * (r + cfg.atmo_cutoff)
		atmo_material.set_shader_parameter("intensity", clampf(cfg.atmo_rho0 / 1.2, 0.15, 2.5))
	atmo_material.set_shader_parameter("inner_ratio", r / (r + maxf(cfg.atmo_cutoff, 1.0)))
	atmo_material.set_shader_parameter("scale_ratio",
			clampf(cfg.atmo_scale_height / maxf(cfg.atmo_cutoff, 1.0), 0.04, 0.6))
	cloud_mesh.visible = has_atmo
	cloud_mesh.scale = Vector3.ONE * (r + CLOUD_ALT)
	cloud_material.set_shader_parameter("opacity", clampf(0.55 + 0.25 * cfg.atmo_rho0, 0.0, 0.9))
	_planet_material.set_shader_parameter("planet_radius", r)
	_patch_material.set_shader_parameter("planet_radius", r)
	var m := sim.moon_pos_at_angle(moon_angle)
	moon_node.position = m
	moon_mesh.scale = Vector3.ONE * cfg.moon_radius
	moon_node.visible = cfg.moon_radius > 0.0

	if not is_equal_approx(_patch_radius, r):
		_rebuild_patch(r)
	# pad at (0, R, 0) relative to planet -> render position in float64
	pad_frame.position = Vector3(-ox, r - oy, -oz)
	var near_pad := (ox * ox + (oy - r) * (oy - r) + oz * oz) < pow(PATCH_HALF * 4.0, 2.0)
	pad_frame.visible = near_pad

	# sky tint by local air density, with "up" = local vertical
	var up := Vector3(ox, oy, oz).normalized()
	var alt := sqrt(ox * ox + oy * oy + oz * oz) - r
	var air := 0.0
	if has_atmo:
		air = clampf(cfg.density_at(alt) / 1.2, 0.0, 1.0)
		air = pow(air, 0.35) if air > 0.0 else 0.0
	# map camera (far from the rocket): no local sky tint or haze
	var cam := get_viewport().get_camera_3d()
	var far_view := cam != null and cam.global_position.length() > MAP_CAMERA_DIST
	var sun_n := SUN_DIR.normalized()
	var day := clampf(up.dot(sun_n) * 1.6 + 0.35, 0.0, 1.0)
	var local_air := 0.0 if far_view else air
	sky_material.set_shader_parameter("air", local_air)
	sky_material.set_shader_parameter("up_dir", up)
	var raw_air := cfg.density_at(alt) / 1.2 if has_atmo else 0.0
	environment.fog_density = 0.0 if far_view else clampf(raw_air, 0.0, 3.0) * 0.00007
	environment.fog_light_color = Color(0.58, 0.70, 0.86) * (0.25 + 0.75 * day)
	var amb_space := Color(0.10, 0.11, 0.15)
	var amb_day := Color(0.46, 0.56, 0.70)
	environment.ambient_light_color = amb_space.lerp(amb_day, local_air * day)
	environment.ambient_light_energy = 0.55 + 0.35 * local_air
	# planet bounce light: from below, greenish near the ground, bluish from orbit
	var near_ground := clampf(1.0 - alt / 40_000.0, 0.0, 1.0)
	var lit_below := clampf(up.dot(sun_n) * 1.4 + 0.25, 0.0, 1.0)
	bounce.light_color = Color(0.55, 0.70, 1.0).lerp(Color(0.62, 0.62, 0.50), near_ground)
	bounce.light_energy = (0.18 + 0.17 * near_ground) * lit_below
	var side_ref := Vector3(0, 0, 1) if absf(up.z) < 0.9 else Vector3(1, 0, 0)
	bounce.basis = Basis.looking_at(up, side_ref)
