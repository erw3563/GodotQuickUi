@tool
class_name RadialMotifLayer2D
extends Node2D

## 可在场景树独立选中的径向路径部件。布局使用设计像素，运动由父级节点变换承担。
## 路径及宽度资源保持共享输入；派生轮廓和绘制缓存归当前节点所有。
@export_group("Path")
@export var paths: PathDefinition:
	set(value):
		if paths == value:
			return
		if paths != null and paths.changed.is_connected(_request_rebuild):
			paths.changed.disconnect(_request_rebuild)
		paths = value
		if paths != null:
			paths.changed.connect(_request_rebuild)
		_request_rebuild()
@export_group("Arrangement")
@export_range(1, 256, 1) var repeat_count := 8:
	set(value):
		repeat_count = clampi(value, 1, 256)
		_request_rebuild()
@export_range(0.0, 4096.0, 0.1, "or_greater") var radius := 100.0:
	set(value):
		radius = maxf(value, 0.0) if is_finite(value) else 0.0
		_request_rebuild()
@export_range(-360.0, 360.0, 0.1, "suffix:°") var phase_degrees := 0.0:
	set(value):
		phase_degrees = value if is_finite(value) else 0.0
		_request_rebuild()
@export var unit_size := Vector2.ONE:
	set(value):
		unit_size = value if value.is_finite() else Vector2.ONE
		_request_rebuild()
@export_range(-360.0, 360.0, 0.1, "suffix:°") var unit_rotation_degrees := 0.0:
	set(value):
		unit_rotation_degrees = value if is_finite(value) else 0.0
		_request_rebuild()
@export_enum("None", "Alternate", "Mirrored pair") var mirror_mode := 0:
	set(value):
		mirror_mode = clampi(value, 0, 2)
		_request_rebuild()
@export var close_paths := true:
	set(value):
		close_paths = value
		_request_rebuild()
@export_group("Appearance")
@export var fill_color := Color(0.12, 0.02, 0.08, 1.0):
	set(value):
		fill_color = value
		_request_rebuild()
@export var stroke_color := Color(0.55, 0.12, 0.3, 1.0):
	set(value):
		stroke_color = value
		_request_rebuild()

var _geometry: Array[Dictionary] = []
var _dirty := false

func _enter_tree() -> void:
	if paths != null and not paths.changed.is_connected(_request_rebuild):
		paths.changed.connect(_request_rebuild)
	_request_rebuild()

func _exit_tree() -> void:
	if paths != null and paths.changed.is_connected(_request_rebuild):
		paths.changed.disconnect(_request_rebuild)
	_geometry.clear()
	_dirty = false

func _request_rebuild() -> void:
	if not is_inside_tree() or _dirty:
		return
	_dirty = true
	_rebuild.call_deferred()

## 查询当前重复单元在部件局部设计坐标中的变换。
func get_unit_transform(repeat_index: int, mirrored := false) -> Transform2D:
	var angle := deg_to_rad(phase_degrees) + TAU * float(repeat_index) / repeat_count
	var facing := angle + deg_to_rad(unit_rotation_degrees)
	var tangent_sign := -1.0 if mirrored or (mirror_mode == 1 and posmod(repeat_index, 2) == 1) else 1.0
	return Transform2D(Vector2.from_angle(facing) * unit_size.x,
		Vector2.from_angle(facing + PI * 0.5) * unit_size.y * tangent_sign,
		Vector2.from_angle(angle) * radius)

func _rebuild() -> void:
	_dirty = false
	_geometry.clear()
	if not is_inside_tree() or paths == null:
		queue_redraw()
		return
	var contours: Array[Dictionary] = []
	for shape in paths.shapes:
		if shape == null or shape.curve == null or shape.curve.point_count < 2:
			continue
		var points := shape.curve.tessellate(6, 3.0)
		if close_paths and points.size() > 2 and not points[0].is_equal_approx(points[-1]):
			points.append(points[0])
		if points.size() < 2:
			continue
		var distances := PackedFloat32Array([0.0])
		for i in range(1, points.size()):
			distances.append(distances[-1] + points[i].distance_to(points[i - 1]))
		if distances[-1] <= 0.00001:
			continue
		var widths := PackedFloat32Array()
		for distance in distances:
			widths.append(shape.sample_width(distance / distances[-1]))
		contours.append({"points":points, "widths":widths, "variable":shape.width_profile != null})
	for repeat_index in repeat_count:
		var copies := 2 if mirror_mode == 2 else 1
		for copy_index in copies:
			var unit_transform := get_unit_transform(repeat_index, copy_index == 1)
			for contour in contours:
				_geometry.append({"points":unit_transform * contour.points, "widths":contour.widths, "variable":contour.variable})
	queue_redraw()

func _draw() -> void:
	for entry in _geometry:
		var points: PackedVector2Array = entry.points
		var widths: PackedFloat32Array = entry.widths
		if close_paths and fill_color.a > 0.0 and points.size() > 3:
			draw_colored_polygon(points, fill_color)
		if stroke_color.a <= 0.0:
			continue
		if not entry.variable:
			if widths[0] > 0.0:
				draw_polyline(points, stroke_color, widths[0], true)
			continue
		for i in range(1, points.size()):
			var width := (widths[i - 1] + widths[i]) * 0.5
			if width > 0.0:
				draw_line(points[i - 1], points[i], stroke_color, width, true)
				draw_circle(points[i - 1], widths[i - 1] * 0.5, stroke_color, true, -1.0, true)
