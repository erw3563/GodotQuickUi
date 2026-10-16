@tool
class_name PathMorph
extends Node
## Arc-length morph driver. Inputs are read-only; output identity belongs to this node.
## Shapes correspond by list index. Missing paths collapse and fade their width to zero.
## Mixed open/closed pairs preserve the authored seam; closed pairs align once per rebuild.
signal updated
signal finished

@export var source: PathDefinition:
	set(value):
		source = value
		rebuild()
@export var destination: PathDefinition:
	set(value):
		destination = value
		rebuild()
@export_range(8, 256, 1) var samples := 96:
	set(value):
		samples = clampi(value, 8, 256)
		rebuild()
@export_range(0.0, 1.0, 0.001) var progress := 0.0:
	set(value):
		var bounded := clampf(value if is_finite(value) else 0.0, 0.0, 1.0)
		if progress == bounded:
			return
		progress = bounded
		_publish()
@export var paused := false:
	set(value):
		paused = value
		set_process(playing and not paused)

var _output: PathDefinition = PathDefinition.new()
var output: PathDefinition:
	get:
		return _output
var playing := false
var _a: Array[PackedVector2Array] = []
var _b: Array[PackedVector2Array] = []
var _width_a: Array[PackedFloat32Array] = []
var _width_b: Array[PackedFloat32Array] = []
var _watched: Array[Resource] = []
var _elapsed := 0.0
var _duration := 1.0
var _start := 0.0
var _goal := 1.0
var _publishing := false
var _pending := false
var _generation := 0

func _enter_tree() -> void:
	rebuild()
	set_process(playing)

func _exit_tree() -> void:
	cancel()
	_unbind()

func _unbind() -> void:
	for resource in _watched:
		if resource.changed.is_connected(rebuild):
			resource.changed.disconnect(rebuild)
	_watched.clear()

func _watch(resource: Resource) -> void:
	if resource != null and resource != output and not _watched.has(resource):
		_watched.append(resource)
		resource.changed.connect(rebuild)

func rebuild() -> void:
	if output == null:
		return
	_unbind()
	_a.clear()
	_b.clear()
	_width_a.clear()
	_width_b.clear()
	# Feedback assignments publish an empty output through the same ownership boundary.
	if source == output or destination == output:
		_publish()
		return
	# Definition notifications forward nested geometry and width edits once.
	_watch(source)
	_watch(destination)
	var curves_a: Array[Curve2D] = []
	var curves_b: Array[Curve2D] = []
	if source != null: curves_a = source.get_curves()
	if destination != null: curves_b = destination.get_curves()
	var count_a := curves_a.size()
	var count_b := curves_b.size()
	for index in mini(maxi(count_a, count_b), 16):
		var ca: Curve2D = curves_a[index] if index < count_a else null
		var cb: Curve2D = curves_b[index] if index < count_b else null
		var a := _sample(ca)
		var b := _sample(cb)
		if a.is_empty() and b.is_empty():
			continue
		# Sample actual pixel widths by source index, including pairs after empty entries.
		var width_a := _sample_widths(source, index, not a.is_empty())
		var width_b := _sample_widths(destination, index, not b.is_empty())
		if a.is_empty():
			a = _collapsed(b)
		if b.is_empty():
			b = _collapsed(a)
		# Periodic profiles permit automatic closed correspondence alignment.
		# Discontinuous width profiles retain their authored seam and endpoint values.
		if _closed(ca) and _closed(cb) and width_a[0] == width_a[-1] and width_b[0] == width_b[-1]:
			var alignment := _closed_alignment(a, b)
			var aligned_points := PackedVector2Array()
			var aligned_widths := PackedFloat32Array()
			for i in samples + 1:
				var aligned_index := posmod(alignment.x + alignment.y * i, samples)
				aligned_points.append(b[aligned_index])
				aligned_widths.append(width_b[aligned_index])
			b = aligned_points
			width_b = aligned_widths
		_a.append(a)
		_b.append(b)
		_width_a.append(width_a)
		_width_b.append(width_b)
	_publish()

func _sample(curve: Curve2D) -> PackedVector2Array:
	var result := PackedVector2Array()
	if curve == null or curve.point_count == 0:
		return result
	if curve.point_count > 4096:
		return result
	var polygon_length := 0.0
	for i in curve.point_count:
		if not curve.get_point_position(i).is_finite() or not curve.get_point_in(i).is_finite() or not curve.get_point_out(i).is_finite():
			return result
		for value in [curve.get_point_position(i), curve.get_point_in(i), curve.get_point_out(i)]:
			if value.length_squared() > 1.0e12:
				return result
		if i > 0:
			var previous := curve.get_point_position(i - 1)
			var first := previous + curve.get_point_out(i - 1)
			var last := curve.get_point_position(i) + curve.get_point_in(i)
			polygon_length += previous.distance_to(first) + first.distance_to(last) + last.distance_to(curve.get_point_position(i))
	# Private bake settings leave editor resources untouched.
	var copy := curve.duplicate() as Curve2D
	copy.bake_interval = maxf(1.0, polygon_length / 4096.0)
	var length := copy.get_baked_length()
	if not is_finite(length):
		return result
	for i in samples + 1:
		result.append(copy.sample_baked(length * float(i) / samples) if length > 0.00001 else copy.get_point_position(0))
	return result

func _collapsed(points: PackedVector2Array) -> PackedVector2Array:
	var center := Vector2.ZERO
	for point in points:
		center += point
	center /= points.size()
	var result := PackedVector2Array()
	result.resize(samples + 1)
	result.fill(center)
	return result

func _closed(curve: Curve2D) -> bool:
	return curve != null and curve.point_count >= 2 and curve.get_point_position(0).distance_squared_to(curve.get_point_position(curve.point_count - 1)) < 0.0001

func _closed_alignment(a: PackedVector2Array, b: PackedVector2Array) -> Vector2i:
	var best := INF
	var shift := 0
	var direction := 1
	for sign_value in [1, -1]:
		for offset in samples:
			var cost := 0.0
			for i in range(0, samples, maxi(1, floori(float(samples) / 24.0))):
				cost += a[i].distance_squared_to(b[posmod(offset + sign_value * i, samples)])
			if cost < best:
				best = cost
				shift = offset
				direction = sign_value
	return Vector2i(shift, direction)

func _sample_widths(definition: PathDefinition, index: int, has_path: bool) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(samples + 1)
	if not has_path or definition == null:
		result.fill(0.0)
		return result
	for i in samples + 1:
		result[i] = definition.sample_width(index, float(i) / samples)
	return result

func _publish() -> void:
	if output == null:
		return
	if _publishing:
		_pending = true
		return
	_publishing = true
	var curves: Array[Curve2D] = []
	var widths := PackedFloat32Array()
	var profiles: Array[Curve] = []
	for index in _a.size():
		var curve := Curve2D.new()
		curve.bake_interval = 2.0
		var actual_widths := PackedFloat32Array()
		var distances := PackedFloat32Array()
		var max_width := 0.0
		var distance := 0.0
		var previous := Vector2.ZERO
		for i in _a[index].size():
			var point := _a[index][i].lerp(_b[index][i], progress)
			curve.add_point(point)
			if i > 0:
				distance += previous.distance_to(point)
			previous = point
			distances.append(distance)
			var actual_width := lerpf(_width_a[index][i], _width_b[index][i], progress)
			actual_widths.append(actual_width)
			max_width = maxf(max_width, actual_width)
		curves.append(curve)
		widths.append(max_width)
		profiles.append(_make_width_profile(actual_widths, distances, distance, max_width))
	# Publish matching geometry and owned width profiles atomically. Retained
	# profiles and curves keep their immutable snapshot values.
	output.begin_update()
	output.set_curves(curves)
	for index in widths.size():
		output.set_path_width(index, widths[index], profiles[index])
	output.end_update()
	updated.emit()
	_publishing = false
	if _pending:
		_pending = false
		call_deferred("_publish")

func _make_width_profile(actual_widths: PackedFloat32Array, distances: PackedFloat32Array, total_length: float, max_width: float) -> Curve:
	if max_width <= 0.0:
		return null
	var uniform := true
	for actual_width in actual_widths:
		if actual_width != max_width:
			uniform = false
			break
	if uniform:
		return null
	var profile := Curve.new()
	# Geometry interpolation changes spacing. Width knots follow the same
	# correspondence points using the output's normalized polyline arc length.
	for i in actual_widths.size():
		var u := distances[i] / total_length if total_length > 0.00001 else float(i) / maxf(actual_widths.size() - 1, 1)
		var value := actual_widths[i] / max_width
		if profile.point_count > 0 and is_equal_approx(profile.get_point_position(profile.point_count - 1).x, u):
			profile.set_point_value(profile.point_count - 1, value)
		else:
			profile.add_point(Vector2(u, value), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return profile

func seek(value: float) -> void:
	cancel()
	progress = value

func play_to(value: float, seconds: float = 1.5) -> void:
	_generation += 1
	_start = progress
	_goal = clampf(value if is_finite(value) else 0.0, 0.0, 1.0)
	_duration = maxf(seconds if is_finite(seconds) else 0.0, 0.0)
	_elapsed = 0.0
	paused = false
	playing = _duration > 0.0 and not is_equal_approx(_start, _goal)
	set_process(playing)
	if not playing:
		var generation := _generation
		progress = _goal
		if generation == _generation:
			finished.emit()

func cancel() -> void:
	_generation += 1
	playing = false
	set_process(false)

func _process(delta: float) -> void:
	if not playing or paused:
		return
	_elapsed = minf(_elapsed + maxf(delta, 0.0), _duration)
	var t := _elapsed / _duration
	var done := t >= 1.0
	if done:
		cancel()
	var generation := _generation
	# Quintic ease gives zero endpoint velocity and acceleration.
	progress = lerpf(_start, _goal, t * t * t * (t * (t * 6.0 - 15.0) + 10.0))
	if done and not playing and generation == _generation:
		finished.emit()
