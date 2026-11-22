class_name RocketView
extends Node3D
## Procedural rocket model with engine flame, exhaust smoke and explosion.
## Origin = nozzle exit (the simulated point), local +Y = nose.
##
## Smoke uses world-space particles. Because the scene uses a floating origin
## centred on the rocket, still air moves past at -v_rocket and appears to
## accelerate at -a_rocket; both are fed to the particle material each frame.

const BODY_RADIUS := 1.0
const LENGTH := 20.0
const BOUNCE_LAYER := 1 << 1   ## render layer 2: receives WorldView's planet-bounce light

var model: Node3D
var flame: GPUParticles3D
var flame_core: MeshInstance3D
var smoke: GPUParticles3D
var explosion: GPUParticles3D
var engine_light: OmniLight3D
var map_marker: Label3D

var _smoke_mat: ParticleProcessMaterial
var _flame_mat: ParticleProcessMaterial
var _core_mat: StandardMaterial3D
var _exploded := false


func _ready() -> void:
	model = Node3D.new()
	model.name = "Model"
	add_child(model)
	_build_model()
	_build_flame()
	_build_smoke()
	_build_explosion()
	engine_light = OmniLight3D.new()
	engine_light.light_color = Color(1.0, 0.6, 0.25)
	engine_light.omni_range = 60.0
	engine_light.position = Vector3(0, -3, 0)
	add_child(engine_light)
	map_marker = Label3D.new()
	map_marker.text = "▲ ROCKET"
	map_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	map_marker.no_depth_test = true
	map_marker.fixed_size = true
	map_marker.pixel_size = 0.0012
	map_marker.font_size = 26
	map_marker.outline_size = 8
	map_marker.modulate = Color(1.0, 0.95, 0.4)
	map_marker.offset = Vector2(0, -24)
	map_marker.visible = false
	add_child(map_marker)


func _mat(color: Color, metallic := 0.1, roughness := 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


func _add_part(mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.layers = 1 | BOUNCE_LAYER
	model.add_child(mi)
	return mi


func _build_model() -> void:
	var white := _mat(Color(0.92, 0.93, 0.95), 0.15, 0.4)
	var dark := _mat(Color(0.08, 0.09, 0.11), 0.3, 0.5)
	var accent := _mat(Color(0.85, 0.18, 0.12), 0.2, 0.45)
	var metal := _mat(Color(0.35, 0.33, 0.32), 0.85, 0.35)
	# nozzle bell
	var bell := CylinderMesh.new()
	bell.top_radius = 0.38
	bell.bottom_radius = 0.75
	bell.height = 1.6
	_add_part(bell, metal, Vector3(0, 0.8, 0))
	# engine section
	var eng := CylinderMesh.new()
	eng.top_radius = BODY_RADIUS
	eng.bottom_radius = 0.85
	eng.height = 1.2
	_add_part(eng, dark, Vector3(0, 2.2, 0))
	# main tank
	var body := CylinderMesh.new()
	body.top_radius = BODY_RADIUS
	body.bottom_radius = BODY_RADIUS
	body.height = 12.0
	body.radial_segments = 32
	_add_part(body, white, Vector3(0, 8.8, 0))
	# stripes
	for y in [4.0, 11.5]:
		var ring := CylinderMesh.new()
		ring.top_radius = BODY_RADIUS + 0.02
		ring.bottom_radius = BODY_RADIUS + 0.02
		ring.height = 0.6
		ring.radial_segments = 32
		_add_part(ring, dark, Vector3(0, y, 0))
	# interstage + capsule
	var cap := CylinderMesh.new()
	cap.top_radius = 0.7
	cap.bottom_radius = BODY_RADIUS
	cap.height = 1.8
	cap.radial_segments = 32
	_add_part(cap, accent, Vector3(0, 15.7, 0))
	var nose := CylinderMesh.new()
	nose.top_radius = 0.0
	nose.bottom_radius = 0.7
	nose.height = 2.6
	nose.radial_segments = 32
	_add_part(nose, white, Vector3(0, 17.9, 0))
	var window := BoxMesh.new()
	window.size = Vector3(0.5, 0.35, 0.1)
	_add_part(window, _mat(Color(0.2, 0.5, 0.8), 0.6, 0.1), Vector3(0, 15.9, 0.82), Vector3(-0.3, 0, 0))
	# fins
	for k in 4:
		var a := k * PI * 0.5 + PI * 0.25
		var fin := BoxMesh.new()
		fin.size = Vector3(0.12, 3.2, 1.6)
		var mi := _add_part(fin, accent, Vector3(cos(a) * 1.5, 3.4, sin(a) * 1.5), Vector3(0, -a, 0))
		mi.rotation = Vector3(0, -a + PI * 0.5, 0)


func _soft_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex


func _billboard_material(additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_texture()
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


func _ramp(colors: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in colors.size():
		offsets.append(float(i) / (colors.size() - 1))
		cols.append(colors[i])
	g.offsets = offsets
	g.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


func _build_flame() -> void:
	flame = GPUParticles3D.new()
	flame.name = "Flame"
	flame.amount = 160
	flame.lifetime = 0.35
	flame.local_coords = true
	flame.position = Vector3(0, 0.1, 0)
	flame.visibility_aabb = AABB(Vector3(-20, -80, -20), Vector3(40, 90, 40))
	_flame_mat = ParticleProcessMaterial.new()
	_flame_mat.direction = Vector3(0, -1, 0)
	_flame_mat.spread = 5.0
	_flame_mat.initial_velocity_min = 45.0
	_flame_mat.initial_velocity_max = 70.0
	_flame_mat.gravity = Vector3.ZERO
	_flame_mat.scale_min = 1.2
	_flame_mat.scale_max = 1.8
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.6))
	sc.add_point(Vector2(0.3, 1.0))
	sc.add_point(Vector2(1, 2.2))
	var sct := CurveTexture.new()
	sct.curve = sc
	_flame_mat.scale_curve = sct
	_flame_mat.color_ramp = _ramp([Color(1, 1, 0.9, 1), Color(1, 0.75, 0.3, 0.9), Color(1, 0.35, 0.1, 0.5), Color(0.6, 0.2, 0.1, 0.0)])
	flame.process_material = _flame_mat
	var quad := QuadMesh.new()
	quad.size = Vector2(1.4, 1.4)
	quad.material = _billboard_material(true)
	flame.draw_pass_1 = quad
	flame.emitting = false
	add_child(flame)
	# solid emissive core so the flame reads clearly even at distance
	flame_core = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.55
	cone.bottom_radius = 0.05
	cone.height = 1.0
	flame_core.mesh = cone
	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_core_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_core_mat.albedo_color = Color(1.0, 0.7, 0.35, 0.8)
	flame_core.material_override = _core_mat
	flame_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flame_core)


func _build_smoke() -> void:
	smoke = GPUParticles3D.new()
	smoke.name = "Smoke"
	smoke.amount = 420
	smoke.lifetime = 7.0
	smoke.local_coords = false
	smoke.top_level = true   # identity basis: direction/gravity are in world axes
	smoke.visibility_aabb = AABB(Vector3(-4000, -4000, -4000), Vector3(8000, 8000, 8000))
	_smoke_mat = ParticleProcessMaterial.new()
	_smoke_mat.direction = Vector3(0, -1, 0)
	_smoke_mat.spread = 12.0
	_smoke_mat.initial_velocity_min = 20.0
	_smoke_mat.initial_velocity_max = 30.0
	_smoke_mat.gravity = Vector3.ZERO
	_smoke_mat.scale_min = 3.0
	_smoke_mat.scale_max = 5.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.3))
	sc.add_point(Vector2(1, 1.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	_smoke_mat.scale_curve = sct
	_smoke_mat.color_ramp = _ramp([Color(1.0, 0.8, 0.6, 0.0), Color(0.85, 0.83, 0.8, 0.55), Color(0.7, 0.7, 0.7, 0.3), Color(0.6, 0.6, 0.62, 0.0)])
	smoke.process_material = _smoke_mat
	var quad := QuadMesh.new()
	quad.size = Vector2(6.0, 6.0)
	quad.material = _billboard_material(false)
	smoke.draw_pass_1 = quad
	smoke.emitting = false
	add_child(smoke)


func _build_explosion() -> void:
	explosion = GPUParticles3D.new()
	explosion.name = "Explosion"
	explosion.amount = 260
	explosion.lifetime = 3.5
	explosion.one_shot = true
	explosion.explosiveness = 0.95
	explosion.local_coords = false
	explosion.top_level = true
	explosion.visibility_aabb = AABB(Vector3(-500, -500, -500), Vector3(1000, 1000, 1000))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 90.0
	pm.initial_velocity_min = 10.0
	pm.initial_velocity_max = 60.0
	pm.damping_min = 8.0
	pm.damping_max = 14.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 4.0
	pm.scale_max = 9.0
	pm.color_ramp = _ramp([Color(1, 0.95, 0.7, 1), Color(1, 0.5, 0.1, 0.9), Color(0.3, 0.25, 0.22, 0.6), Color(0.15, 0.15, 0.15, 0.0)])
	explosion.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(5, 5)
	quad.material = _billboard_material(false)
	explosion.draw_pass_1 = quad
	explosion.emitting = false
	add_child(explosion)


## Called every frame. `vel` / `acc` are the rocket's velocity and coordinate
## acceleration relative to the planet frame (world axes).
func update_view(sim: OrbitalSim, vel: Vector3, acc: Vector3, map_mode: bool, sim_paused: bool) -> void:
	basis = sim.orientation.orthonormalized()
	smoke.global_transform = Transform3D(Basis.IDENTITY, global_position - basis.y * 2.0)
	explosion.global_transform = Transform3D(Basis.IDENTITY, global_position + basis.y * 6.0)
	var crashed := sim.status == OrbitalSim.Status.CRASHED
	if crashed and not _exploded:
		_exploded = true
		explosion.restart()
		explosion.emitting = true
	elif not crashed and _exploded:
		_exploded = false
	model.visible = not crashed
	map_marker.visible = map_mode
	map_marker.modulate = Color(1.0, 0.35, 0.3) if crashed else Color(1.0, 0.95, 0.4)

	var thrust_frac := sim.last_thrust / sim.cfg.max_thrust if sim.cfg.max_thrust > 0.0 else 0.0
	if crashed:
		thrust_frac = 0.0
	var air := clampf(sim.last_density / 1.2, 0.0, 1.0)
	var on := thrust_frac > 0.001
	flame.emitting = on
	flame.amount_ratio = clampf(0.25 + thrust_frac, 0.0, 1.0)
	# plume expands in vacuum
	_flame_mat.spread = lerpf(28.0, 5.0, sqrt(air))
	_flame_mat.initial_velocity_min = 40.0 + 40.0 * thrust_frac
	_flame_mat.initial_velocity_max = 60.0 + 60.0 * thrust_frac
	flame_core.visible = on
	if on:
		var len := 3.0 + 9.0 * thrust_frac
		flame_core.scale = Vector3(1.0 + (1.0 - air) * 0.8, len, 1.0 + (1.0 - air) * 0.8)
		flame_core.position = Vector3(0, -len * 0.5, 0)
		_core_mat.albedo_color = Color(1.0, 0.65 + 0.2 * thrust_frac, 0.35, 0.45 + 0.4 * thrust_frac)
	engine_light.light_energy = 6.0 * thrust_frac if on else 0.0

	# smoke only in dense air
	var smoky := on and air > 0.02 and not map_mode
	smoke.emitting = smoky
	smoke.amount_ratio = clampf(thrust_frac * air * 1.2, 0.05, 1.0)
	if smoky:
		# exhaust direction in world frame, plus apparent wind of still air
		var exhaust := -basis.y * 25.0
		var start_v := exhaust - vel
		var sp := start_v.length()
		_smoke_mat.direction = start_v / maxf(sp, 0.001)
		_smoke_mat.initial_velocity_min = sp * 0.95
		_smoke_mat.initial_velocity_max = sp * 1.05
		_smoke_mat.gravity = -acc
		# near the ground the exhaust is deflected sideways into a billowing cloud
		var alt := sim.altitude()
		_smoke_mat.spread = lerpf(85.0, 12.0, clampf(alt / 150.0, 0.0, 1.0))
	smoke.speed_scale = 0.0 if sim_paused else 1.0
	flame.speed_scale = 0.0 if sim_paused else 1.0
	explosion.speed_scale = 0.0 if sim_paused else 1.0
