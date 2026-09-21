extends Node2D
class_name ConstrainedPoints
## 如果您想要使用像素化的线段，可以参照与脚本同文件夹下的procedural_animation_line场景

@export var line2d:Line2D
@export var target: Node2D
@export var line_points:Array[Vector2] = []
@export_group("约束")
@export var max_radius:float = 16
@export var min_radius:float = 8
@export_range(0,180) var max_bend_angle_deg:float = 90
@export_range(0,180) var min_bend_angle_deg:float = 90
@export_group("线段样式")
@export var line_curve:Curve:
	set(curve):
		line_curve = curve
		if line2d:
			line2d.width_curve = curve
@export var line_width:float = 10:
	set(value):
		line_width = value
		if line2d:
			line2d.width = value
@export var line_color:Color = Color.WHITE:
	set(color):
		line_color = color
		if line2d:
			line2d.default_color = color

func _ready() -> void:
	line2d.default_color = line_color
	line2d.width = line_width
	line2d.width_curve = line_curve

func _process(_delta: float) -> void:
	if target:
		line_points[0] = target.global_position
	else:
		line_points[0] = get_global_mouse_position()
	apply_constraints()
	update_line2d()

func apply_constraints():
	for i in 4:
		_apply_length_constraints()
		_apply_angle_constraints()

func _apply_length_constraints():
	for i in range(line_points.size()-1):
		var line_vec:Vector2 = line_points[i+1] - line_points[i]
		var distance:float = line_vec.length()
		var dir:Vector2 = line_vec.normalized()
		if distance > max_radius:
			line_points[i+1] = line_points[i] + dir * max_radius
		if distance < min_radius:
			line_points[i+1] = line_points[i] + dir * min_radius

func _apply_angle_constraints():
	for i in range(1, line_points.size()-1):
		var vec_to_prev = line_points[i-1] - line_points[i]
		var vec_to_next = line_points[i+1] - line_points[i]
		if vec_to_next == Vector2.ZERO or vec_to_prev == Vector2.ZERO:
			continue
		var dir_to_prev = vec_to_prev.normalized()
		var dir_to_next = vec_to_next.normalized()

		var current_bend_angle_rad = dir_to_prev.angle_to(dir_to_next)
		var current_bend_angle_deg = rad_to_deg(current_bend_angle_rad)
		if current_bend_angle_deg >0:
			if current_bend_angle_deg > max_bend_angle_deg:
				line_points[i+1] = line_points[i] + dir_to_prev.rotated(deg_to_rad(max_bend_angle_deg)) * vec_to_next.length()
			elif current_bend_angle_deg < min_bend_angle_deg:
				line_points[i+1] = line_points[i] + dir_to_prev.rotated(deg_to_rad(min_bend_angle_deg)) * vec_to_next.length()
		elif current_bend_angle_deg <0:
			if current_bend_angle_deg < -max_bend_angle_deg:
				line_points[i+1] = line_points[i] + dir_to_prev.rotated(deg_to_rad(-max_bend_angle_deg)) * vec_to_next.length()
			if current_bend_angle_deg > - min_bend_angle_deg:
				line_points[i+1] = line_points[i] + dir_to_prev.rotated(deg_to_rad(-min_bend_angle_deg)) * vec_to_next.length()

func update_line2d():
	line2d.clear_points()
	for pos in line_points:
		line2d.add_point(line2d.to_local(pos))
