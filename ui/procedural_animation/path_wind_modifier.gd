class_name PathWindModifier
extends PathModifier
## Adds a canvas-wind spring displacement to incoming work geometry.
## Samples the field at a fixed authored root-to-tip position.
const SETTLE_EPSILON := 0.001
class SpringState:
	var offsets := PackedVector2Array()
	var velocities := PackedVector2Array()
	var target := Vector2.ZERO
@export var field: WindField2D
## Canvas wind px/sec is converted through the coordinator's inverse transform, then
## multiplied by this response (seconds) and a root-to-tip compliance profile.
@export_range(0.0, 2.0, 0.01) var wind_response := 0.12:
	set(value): wind_response = clampf(value, 0.0, 10.0) if is_finite(value) else 0.0
@export_range(0.0, 128.0, 0.1) var max_offset := 12.0:
	set(value):
		max_offset = clampf(value, 0.0, 4096.0) if is_finite(value) else 0.0
@export_range(0.1, 12.0, 0.05) var spring_frequency := 2.1:
	set(value): spring_frequency = clampf(value, 0.1, 12.0) if is_finite(value) else 2.1
@export_range(0.05, 0.95, 0.01) var damping_ratio := 0.60:
	set(value): damping_ratio = clampf(value, 0.05, 0.95) if is_finite(value) else 0.60
@export_range(0.0, 0.4, 0.01) var variation := 0.12:
	set(value):
		variation = clampf(value, 0.0, 0.4) if is_finite(value) else 0.0
## Per-instance seed produces small reproducible response differences.
@export var response_seed := 1:
	set(value):
		response_seed = value
var _springs: Array[SpringState] = []
func reset_state() -> void:
	active = false
	_springs.clear()
func apply(paths: Array, coordinator: Node2D, delta: float) -> void:
	if _springs.size() != paths.size():
		_springs.clear()
		for path: PathDeform2D.PathState in paths:
			var spring := SpringState.new()
			spring.offsets.resize(path.rest.size()); spring.offsets.fill(Vector2.ZERO)
			spring.velocities.resize(path.rest.size()); spring.velocities.fill(Vector2.ZERO)
			_springs.append(spring)
	active = false
	var sample_start := Time.get_ticks_usec()
	var transform := coordinator.global_transform
	var valid_transform := transform.x.is_finite() and transform.y.is_finite() and transform.origin.is_finite() and absf(transform.determinant()) > 0.000001
	var valid_field := is_instance_valid(field) and not field.is_queued_for_deletion()
	if valid_field and coordinator.is_inside_tree() and field.is_inside_tree():
		valid_field = coordinator.get_viewport() == field.get_viewport() and coordinator.get_canvas() == field.get_canvas()
	var inverse := transform.affine_inverse() if valid_transform else Transform2D.IDENTITY
	for p in paths.size():
		var path: PathDeform2D.PathState = paths[p]
		var spring := _springs[p]
		spring.target = Vector2.ZERO
		if path.rest.size() < 2 or not valid_transform or not valid_field: continue
		var wind := field.sample_wind(transform * path.sample_position)
		coordinator._metrics.sample_count += 1
		if wind.is_finite():
			var phase := float(posmod(response_seed, 100003)) * 0.61803398875 + float(p) * 2.39996322973
			var local_wind: Vector2 = coordinator._safe_vector(inverse.basis_xform(wind))
			if local_wind.is_finite(): spring.target = (local_wind * wind_response * (1.0 + sin(phase) * variation)).limit_length(max_offset)
	coordinator._metrics.sample_usec += Time.get_ticks_usec() - sample_start
	var threshold := SETTLE_EPSILON * SETTLE_EPSILON
	for p in paths.size():
		var path: PathDeform2D.PathState = paths[p]
		var state := _springs[p]
		var phase := float(posmod(response_seed, 100003)) * 0.61803398875 + float(p) * 2.39996322973
		var omega := TAU * spring_frequency * (1.0 + cos(phase + 0.7) * variation * 0.5)
		var decay := damping_ratio * omega
		var frequency := omega * sqrt(1.0 - damping_ratio * damping_ratio)
		var envelope := exp(-decay * delta)
		var cosine := cos(frequency * delta)
		var sine_over_frequency := sin(frequency * delta) / frequency
		for i in range(1, path.rest.size()):
			var target: Vector2 = state.target * path.weights[i]
			var offset := state.offsets[i]
			var velocity := state.velocities[i]
			var displacement := offset - target
			var next_offset: Vector2
			var next_velocity: Vector2
			if displacement.length_squared() <= threshold and velocity.length_squared() <= threshold:
				next_offset = target
				next_velocity = Vector2.ZERO
			else:
				next_offset = target + envelope * (displacement * cosine + (velocity + decay * displacement) * sine_over_frequency)
				next_velocity = envelope * (velocity * cosine - (decay * velocity + omega * omega * displacement) * sine_over_frequency)
				active = true
			next_offset = next_offset.limit_length(max_offset * path.weights[i])
			next_velocity = next_velocity.limit_length(max_offset * omega * 4.0)
			if not next_offset.is_finite() or not next_velocity.is_finite():
				next_offset = Vector2.ZERO; next_velocity = Vector2.ZERO
			state.offsets[i] = next_offset
			state.velocities[i] = next_velocity
			path.offsets[i] += next_offset
