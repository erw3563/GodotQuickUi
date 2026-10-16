class_name PixelProjectileHead2D
extends Node2D
## Pixel head presentation consumes positions and projected velocities in one canvas's
## world space. Drawing cancels parent scale/rotation; Camera2D transforms the result.

@export var core_color := Color("fff4d1")
@export var edge_color := Color("e8ae62")
@export_range(1.0, 12.0, 0.5) var width := 3.0
@export_range(1.0, 16.0, 0.5) var base_length := 4.0
@export_range(1.0, 24.0, 0.5) var max_length := 9.0
@export_range(0.0, 0.1, 0.001) var velocity_stretch := 0.018

var active := false
var velocity := Vector2.ZERO
var _direction := Vector2.RIGHT

func _ready() -> void:
	set_notify_transform(true)
	set_process(false)

func play(world_position: Vector2, world_velocity: Vector2) -> void:
	if not world_position.is_finite() or not world_velocity.is_finite():
		reset()
		return
	active = true
	set_motion(world_position, world_velocity)

func set_motion(world_position: Vector2, world_velocity: Vector2) -> void:
	if not world_position.is_finite() or not world_velocity.is_finite():
		return
	global_position = world_position
	velocity = world_velocity
	if velocity.length_squared() > 0.000001:
		_direction = velocity.normalized()
	queue_redraw()

func stop() -> void:
	reset()

func reset() -> void:
	active = false
	velocity = Vector2.ZERO
	_direction = Vector2.RIGHT
	queue_redraw()

func get_visual_length() -> float:
	return clampf(maxf(1.0, base_length) + velocity.length() * maxf(0.0, velocity_stretch), maxf(1.0, base_length), maxf(maxf(1.0, base_length), max_length))

func get_world_outline() -> PackedVector2Array:
	var length_px := get_visual_length()
	var half_width := maxf(0.5, width * 0.5)
	var normal := _direction.orthogonal()
	return PackedVector2Array([
		global_position + _direction * length_px * 0.5,
		global_position + _direction * (length_px * 0.5 - 1.0) + normal * half_width,
		global_position - _direction * length_px * 0.5 + normal * half_width * 0.55,
		global_position - _direction * length_px * 0.5 - normal * half_width * 0.55,
		global_position + _direction * (length_px * 0.5 - 1.0) - normal * half_width])

func _draw() -> void:
	if not active or absf(global_transform.determinant()) < 0.000001:
		return
	var inverse := global_transform.affine_inverse()
	var points := get_world_outline()
	for i in points.size():
		points[i] = inverse * points[i]
	draw_colored_polygon(points, edge_color)
	var normal := _direction.orthogonal()
	var core_length := maxf(1.0, get_visual_length() - 3.0)
	var center := global_position + _direction * 0.5
	var core := PackedVector2Array([center + _direction * core_length * 0.5 + normal * 0.5, center - _direction * core_length * 0.5 + normal * 0.5, center - _direction * core_length * 0.5 - normal * 0.5, center + _direction * core_length * 0.5 - normal * 0.5])
	for i in core.size():
		core[i] = inverse * core[i]
	draw_colored_polygon(core, core_color)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		queue_redraw()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree() and not is_visible_in_tree():
		reset()
	elif what == NOTIFICATION_EXIT_TREE:
		reset()
