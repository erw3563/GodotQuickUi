@tool
class_name OrbitMotion
extends RefCounted
## 每轨道独立的运动状态；_process 调用 step 积分，重排读取当前结果。
## 相对目标的受迫阻尼振子：offset'' + 2ζω offset' + ω² offset = -inertia * acceleration。
var _states: Dictionary = {}

func reset() -> void:
	_states.clear()

func forget(control: Control) -> void:
	_states.erase(control)

func get_offset(control: Control) -> Vector2:
	return _states.get(control, {}).get("offset", Vector2.ZERO)

func get_rotation(control: Control) -> float:
	var state: Dictionary = _states.get(control, {})
	return state.get("lean", 0.0) + state.get("angle", 0.0)

func step(host: Control, controls: Array[Control], delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	# 窗口或调试器恢复产生大步长时重新建立导数历史。
	if delta > 0.25:
		reset()
	for old in _states.keys():
		if not is_instance_valid(old) or not controls.has(old):
			_states.erase(old)
	var dt := minf(delta, 0.1)
	var spring: bool = host.get("spring_enabled")
	var lean: bool = host.get("motion_lean_enabled")
	var frequency := _number(host.get("spring_frequency_hz"), 0.1, 20.0, 2.2)
	var damping := _number(host.get("spring_damping_ratio"), 0.02, 3.0, 0.32)
	var inertia := _number(host.get("spring_inertia"), 0.0, 3.0, 1.0)
	var max_offset := _number(host.get("spring_max_offset_pixels"), 0.0, 1000.0, 48.0)
	var max_angle := deg_to_rad(_number(host.get("spring_max_rotation_degrees"), 0.0, 90.0, 12.0))
	var omega := TAU * frequency
	var lean_max := deg_to_rad(_number(host.get("lean_max_degrees"), 0.0, 90.0, 15.0))
	var lean_scale := deg_to_rad(_number(host.get("lean_velocity_scale"), -1.0, 1.0, 0.035))
	for index in controls.size():
		var control := controls[index]
		var target: Vector2 = host.call("get_slot_center", index, controls.size())
		if not _states.has(control):
			_states[control] = {"target": target, "velocity": Vector2.ZERO, "offset": Vector2.ZERO,
				"offset_velocity": Vector2.ZERO, "angle": 0.0, "angular_velocity": 0.0, "lean": 0.0}
			continue
		var state: Dictionary = _states[control]
		var velocity: Vector2 = ((target - Vector2(state.target)) / delta).limit_length(50000.0)
		var acceleration: Vector2 = ((velocity - Vector2(state.velocity)) / delta).limit_length(100000.0)
		state.target = target
		state.velocity = velocity
		var screen_velocity := velocity.rotated(host.rotation)
		var desired_lean := clampf(-screen_velocity.x * lean_scale, -lean_max, lean_max) if lean else 0.0
		state.lean = lerpf(float(state.lean), desired_lean, 1.0 - exp(-12.0 * dt)) if lean else 0.0
		if not spring:
			state.offset = Vector2.ZERO
			state.offset_velocity = Vector2.ZERO
			state.angle = 0.0
			state.angular_velocity = 0.0
			continue
		# 小步长半隐式积分；步数随频率增加，20Hz极端参数也稳定。
		var steps := maxi(1, ceili(dt / minf(1.0 / 120.0, 0.18 / omega)))
		var h := dt / float(steps)
		for _step in steps:
			var offset: Vector2 = state.offset
			var offset_velocity: Vector2 = state.offset_velocity
			offset_velocity += (-omega * omega * offset - 2.0 * damping * omega * offset_velocity - inertia * acceleration) * h
			offset += offset_velocity * h
			if offset.length() > max_offset:
				offset = offset.limit_length(max_offset)
				# 边界消除继续向外的速度并保留回弹。
				if not offset.is_zero_approx():
					var normal := offset.normalized()
					offset_velocity -= normal * maxf(offset_velocity.dot(normal), 0.0)
			state.offset = offset
			state.offset_velocity = offset_velocity.limit_length(10000.0)
			var angle: float = state.angle
			var angular_velocity: float = state.angular_velocity
			var angular_force := acceleration.rotated(host.rotation).x * inertia * 0.0015
			angular_velocity += (-omega * omega * angle - 2.0 * damping * omega * angular_velocity + angular_force) * h
			angle += angular_velocity * h
			if absf(angle) > max_angle:
				angle = clampf(angle, -max_angle, max_angle)
				if signf(angular_velocity) == signf(angle): angular_velocity = 0.0
			state.angle = angle
			state.angular_velocity = clampf(angular_velocity, -50.0, 50.0)

func _number(value: float, low: float, high: float, fallback: float) -> float:
	return clampf(value, low, high) if is_finite(value) else fallback
