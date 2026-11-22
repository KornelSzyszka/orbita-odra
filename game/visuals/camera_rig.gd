class_name CameraRig
extends Node3D
## Two cameras: a chase camera orbiting the rocket (render origin) and a
## strategic map camera orbiting a focus body. Right/left mouse drag rotates,
## wheel zooms. Input arrives via handle_input() from _unhandled_input so UI
## panels keep priority over the mouse.

enum Mode { CHASE, MAP }
enum Focus { PLANET, ROCKET, MOON }
const FOCUS_NAMES := ["Odra", "Rocket", "Ślęża"]

var mode: int = Mode.CHASE
var focus: int = Focus.PLANET
var chase_cam: Camera3D
var map_cam: Camera3D

var chase_yaw := deg_to_rad(205.0)
var chase_pitch := deg_to_rad(8.0)
var chase_dist := 70.0
var map_yaw := 0.0
var map_pitch := deg_to_rad(40.0)
var map_dist := 2_400_000.0
var _dragging := false


func _ready() -> void:
	chase_cam = Camera3D.new()
	chase_cam.name = "ChaseCamera"
	chase_cam.fov = 62.0
	_update_chase_clip()
	add_child(chase_cam)
	map_cam = Camera3D.new()
	map_cam.name = "MapCamera"
	map_cam.fov = 55.0
	add_child(map_cam)
	set_mode(Mode.CHASE)


## Godot's frustum maths breaks down for far/near ratios around 1e7, so the
## clip range scales with the zoom (near ~4% of the chase distance).
const MAX_CLIP_RATIO := 2.0e6


func _update_chase_clip() -> void:
	chase_cam.near = clampf(chase_dist * 0.04, 0.5, 200.0)
	chase_cam.far = chase_cam.near * MAX_CLIP_RATIO


func set_chase_distance(distance: float) -> void:
	chase_dist = clampf(distance, 25.0, 5000.0)
	_update_chase_clip()


func set_mode(m: int) -> void:
	mode = m
	chase_cam.current = mode == Mode.CHASE
	map_cam.current = mode == Mode.MAP


func toggle_mode() -> void:
	set_mode(Mode.MAP if mode == Mode.CHASE else Mode.CHASE)


func cycle_focus() -> void:
	focus = (focus + 1) % 3


func mode_name() -> String:
	return "Chase camera" if mode == Mode.CHASE else "Map — focus: %s" % FOCUS_NAMES[focus]


func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			return true
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var f := 0.88 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.88
			if mode == Mode.CHASE:
				set_chase_distance(chase_dist * f)
			else:
				map_dist = clampf(map_dist * f, 2_000.0, 6.0e7)
			return true
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		if mode == Mode.CHASE:
			chase_yaw -= mm.relative.x * 0.006
			chase_pitch = clampf(chase_pitch + mm.relative.y * 0.006, deg_to_rad(-85), deg_to_rad(85))
		else:
			map_yaw -= mm.relative.x * 0.006
			map_pitch = clampf(map_pitch + mm.relative.y * 0.006, deg_to_rad(-89), deg_to_rad(89))
		return true
	return false


## planet_center / moon_center: render-space positions (rocket = origin).
## up: local vertical at the rocket. rocket_axis: nose direction.
func update_cameras(planet_center: Vector3, moon_center: Vector3, up: Vector3,
		rocket_axis: Vector3, min_focus_dist: float) -> void:
	# --- chase: frame built on the local vertical and the orbit-plane "east"
	var u := up.normalized()
	var east := Vector3(0, 0, 1).cross(u)
	if east.length_squared() < 1e-6:
		east = Vector3(1, 0, 0)
	east = east.normalized()
	var north := u.cross(east).normalized()
	var off := (east * cos(chase_yaw) + north * sin(chase_yaw)) * cos(chase_pitch) + u * sin(chase_pitch)
	var target := rocket_axis.normalized() * 9.0
	chase_cam.position = target + off * chase_dist
	chase_cam.look_at(target, u if absf(off.dot(u)) < 0.98 else north)

	# --- map: orbit a focus, Z-up so the orbital plane (XY) is seen from above
	var f := planet_center
	match focus:
		Focus.ROCKET: f = Vector3.ZERO
		Focus.MOON: f = moon_center
	var d := maxf(map_dist, min_focus_dist if focus != Focus.ROCKET else 2_000.0)
	var dir := Vector3(cos(map_yaw) * cos(map_pitch), sin(map_yaw) * cos(map_pitch), sin(map_pitch))
	map_cam.position = f + dir * d
	map_cam.far = d * 60.0 + 2.0e7
	map_cam.near = maxf(d * 0.0005, map_cam.far / MAX_CLIP_RATIO)
	var map_up := Vector3(0, 0, 1) if absf(dir.z) < 0.99 else Vector3(0, 1, 0)
	map_cam.look_at(f, map_up)
