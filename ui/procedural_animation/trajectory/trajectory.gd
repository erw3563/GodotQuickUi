extends ConstrainedPoints
class_name Trajectory

@export var disappear_speed:float = 12

func _process(delta: float) -> void:
	if target:
		line_points[0] = target.global_position
	else:
		line_points[0] = get_global_mouse_position()
	apply_constraints()
	disappear_trajectory(delta)
	update_line2d()

func disappear_trajectory(delta):
	for i in range(line_points.size()-1):
		var line_vec:Vector2 = line_points[i+1] - line_points[i]
		var distance:float = line_vec.length()
		var dir:Vector2 = line_vec.normalized()
		if distance < min_radius:
			line_points[i+1] = line_points[i] + dir * min_radius
		else:
			var new_distance:float = max(distance - disappear_speed * delta * distance,0)
			if new_distance < 0.1:
				new_distance = 0
			line_points[i+1] = line_points[i] + dir * new_distance
