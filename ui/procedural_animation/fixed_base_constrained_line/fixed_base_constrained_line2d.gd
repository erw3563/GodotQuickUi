extends Node2D
class_name FixedBaseConstrainedLine2d

@export var line2d:Line2D
@export var target: Node2D
@export var line_points:Array[Vector2] = []
@export_group("约束")
@export var max_radius:float = 16
@export var min_radius:float = 8
@export_range(0,180) var max_bend_angle_deg:float = 90
@export_range(0,180) var min_bend_angle_deg:float = 90
@export_group("波动")
@export_range(0.0, 5.0, 0.5) var wave_amplitude: float = 2.5
@export_range(0.0, 5, 0.1) var wave_frequency: float = 2.0
@export_range(0.0, 10.0, 0.1) var wave_speed: float = 3.0
var _wave_time: float = 0.0
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

func _process(delta: float) -> void:
	apply_constraints()
	apply_wave(delta)
	update_line2d()

func apply_constraints():
	for i in 4:
		_apply_length_constraints()
		_apply_angle_constraints()
	

func _apply_length_constraints():
	if target:
		line_points[0] = target.global_position
	else:
		line_points[0] = get_global_mouse_position()
	_apply_length_constraints_from_zero()
	line_points[-1] = global_position
	_apply_length_constraints_from_max()
	

func _apply_length_constraints_from_max():
	for i in range(line_points.size()-2,-1,-1):
		var line_vec:Vector2 = line_points[i] - line_points[i+1]
		var distance:float = line_vec.length()
		var dir:Vector2 = line_vec.normalized()
		if distance > max_radius:
			line_points[i] = line_points[i+1] + dir * max_radius
		if distance < min_radius:
			line_points[i] = line_points[i+1] + dir * min_radius

func _apply_length_constraints_from_zero():
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

func apply_wave(delta:float):
	if wave_amplitude <= 0.0:
		return
	_wave_time += delta * wave_speed
	var total_length:float = 0.0
	for i in range(line_points.size()):
		var vec: Vector2 = line_points[i] - line_points[i - 1]
		total_length += vec.length()
	var accumulated_length: float = 0.0
	for i in range(1, line_points.size()):
		var vec: Vector2 = line_points[i] - line_points[i - 1]
		accumulated_length += vec.length()
		var t:float = accumulated_length / total_length
		var direction: Vector2 = vec.normalized()
		var perpendicular: Vector2 = direction.orthogonal()
		var wave_phase: float = _wave_time + t * wave_frequency * TAU
		var wave_offset: float = sin(wave_phase) * wave_amplitude
		line_points[i-1] += perpendicular * wave_offset

func update_line2d():
	line2d.clear_points()
	for pos in line_points:
		line2d.add_point(line2d.to_local(pos))
