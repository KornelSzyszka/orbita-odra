class_name TrajectoryView
extends Node3D
## Draws the predicted engine-off path (ImmediateMesh line strip), Ap/Pe/impact
## markers and the moon's orbit. Must be a child of WorldView.planet_frame:
## all coordinates are relative to the planet centre.

const COL_VACUUM := Color(0.25, 0.85, 1.0)
const COL_ATMO := Color(1.0, 0.62, 0.2)
const COL_MOON := Color(0.8, 0.5, 1.0)
const COL_IMPACT := Color(1.0, 0.25, 0.2)
const SUBDIV_LEN := 4_000.0   ## [m] chords longer than this get spline points
const MAX_SUBDIV := 12

var line_mesh: ImmediateMesh
var line_instance: MeshInstance3D
var orbit_mesh: ImmediateMesh
var orbit_instance: MeshInstance3D
var ap_label: Label3D
var pe_label: Label3D
var impact_label: Label3D
var encounter_label: Label3D
var moon_label: Label3D
var _orbit_r := -1.0


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.disable_fog = true
	line_mesh = ImmediateMesh.new()
	line_instance = MeshInstance3D.new()
	line_instance.mesh = line_mesh
	line_instance.material_override = mat
	line_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	line_instance.extra_cull_margin = 1e7
	add_child(line_instance)
	orbit_mesh = ImmediateMesh.new()
	orbit_instance = MeshInstance3D.new()
	orbit_instance.mesh = orbit_mesh
	orbit_instance.material_override = mat
	orbit_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	orbit_instance.extra_cull_margin = 1e7
	add_child(orbit_instance)
	ap_label = _make_label(Color(0.4, 1.0, 0.6))
	pe_label = _make_label(Color(1.0, 0.9, 0.35))
	impact_label = _make_label(COL_IMPACT)
	impact_label.offset = Vector2(0, 62)   # stacked above Ap / the rocket marker near launch
	encounter_label = _make_label(COL_MOON)
	moon_label = _make_label(Color(0.8, 0.8, 0.85))
	moon_label.text = "ŚLĘŻA"


func _make_label(c: Color) -> Label3D:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.font_size = 24
	l.outline_size = 8
	l.modulate = c
	l.offset = Vector2(0, 30)
	l.visible = false
	add_child(l)
	return l


## Rebuild the line from a TrajectoryPredictor result.
func show_prediction(res: Dictionary, planet_radius: float, map_mode: bool) -> void:
	line_mesh.clear_surfaces()
	var pts: PackedVector3Array = res.points
	var flags: PackedByteArray = res.flags
	if pts.size() >= 2:
		line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		var n := pts.size()
		for i in n:
			var c := COL_VACUUM
			match flags[i]:
				TrajectoryPredictor.FLAG_ATMO: c = COL_ATMO
				TrajectoryPredictor.FLAG_MOON: c = COL_MOON
			if res.impact and i >= n - 2:
				c = COL_IMPACT
			# fade slightly along the path so direction of travel is readable
			c.a = lerpf(1.0, 0.45, float(i) / n)
			line_mesh.surface_set_color(c)
			line_mesh.surface_add_vertex(pts[i])
			# long chords look kinked up close (chase view): add Catmull-Rom points
			if i < n - 1:
				var p1: Vector3 = pts[i]
				var p2: Vector3 = pts[i + 1]
				var seg := p1.distance_to(p2)
				var sub := clampi(int(seg / SUBDIV_LEN), 0, MAX_SUBDIV)
				if sub > 0:
					var p0: Vector3 = pts[i - 1] if i > 0 else p1 - (p2 - p1)
					var p3: Vector3 = pts[i + 2] if i + 2 < n else p2 + (p2 - p1)
					for k in range(1, sub + 1):
						var t := float(k) / (sub + 1)
						line_mesh.surface_set_color(c)
						line_mesh.surface_add_vertex(_catmull(p0, p1, p2, p3, t))
		line_mesh.surface_end()

	var el: Dictionary = res.elements
	ap_label.visible = res.ap_visible
	if res.ap_visible:
		ap_label.position = res.ap_pos
		ap_label.text = "◆ Ap %s" % _alt_text(el.ra - el.body_radius)
	pe_label.visible = res.pe_visible
	if res.pe_visible:
		pe_label.position = res.pe_pos
		pe_label.text = "◆ Pe %s" % _alt_text(el.rp - el.body_radius)
	impact_label.visible = res.impact
	if res.impact:
		impact_label.position = res.impact_pos
		impact_label.text = "✖ Engine off — impact in %s" % _time_text(res.time_to_impact)
	encounter_label.visible = res.moon_encounter and not res.impact and map_mode
	if encounter_label.visible:
		encounter_label.position = res.closest_moon_pos
		encounter_label.text = "● min. %s above Ślęża" % _alt_text(res.closest_moon_alt)


func update_moon(moon_pos: Vector3, distance: float, map_mode: bool) -> void:
	moon_label.visible = map_mode
	moon_label.position = moon_pos
	orbit_instance.visible = map_mode
	if not is_equal_approx(distance, _orbit_r):
		_orbit_r = distance
		orbit_mesh.clear_surfaces()
		orbit_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		var seg := 256
		for i in seg + 1:
			var a := TAU * i / seg
			orbit_mesh.surface_set_color(Color(0.6, 0.6, 0.7, 0.35))
			orbit_mesh.surface_add_vertex(Vector3(cos(a) * distance, sin(a) * distance, 0.0))
		orbit_mesh.surface_end()


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
			+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


static func _alt_text(m: float) -> String:
	if absf(m) >= 10_000.0:
		return "%.1f km" % (m / 1000.0)
	return "%.0f m" % m


static func _time_text(s: float) -> String:
	if s < 0.0:
		return "—"
	var si := int(s)
	if si >= 3600:
		return "%d:%02d:%02d" % [si / 3600, (si / 60) % 60, si % 60]
	return "%d:%02d" % [si / 60, si % 60]
