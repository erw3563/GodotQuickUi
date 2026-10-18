@tool
class_name PathMorph
extends Node
## Arc-length morph driver. Inputs are read-only; output identity belongs to this node.
## Shapes correspond by list index. Missing paths collapse and fade their width to zero.
## Mixed open/closed pairs preserve the authored seam; closed pairs align once per rebuild.
## missing_curve_mode selects how a path present on one side only appears: it collapses to
## its centroid, or it grows along its arc length from an anchor on its parent path.
signal updated
signal finished

enum MissingCurveMode { COLLAPSE_TO_CENTROID, GROW_FROM_ANCHOR }

## Schedule offset of a first-level anchored path per unit of anchor arc-length fraction.
const ANCHOR_STAGGER := 0.55
## Schedule gap between a parent passing an anchor and the child starting to grow.
const ANCHOR_CHILD_GAP := 0.03
## Growth amount over which an anchored path's width rises from zero to its authored width.
const ANCHOR_WIDTH_RAMP := 0.1

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

@export_group("Missing Curves")
@export var missing_curve_mode := MissingCurveMode.COLLAPSE_TO_CENTROID:
	set(value):
		missing_curve_mode = value
		rebuild()
## Anchors of source paths, indexed like source curves. Used by GROW_FROM_ANCHOR for paths
## missing from destination; they retract toward their anchors as progress rises.
@export var source_anchors: PathAnchorSet:
	set(value):
		source_anchors = value
		rebuild()
## Anchors of destination paths, indexed like destination curves. Used by GROW_FROM_ANCHOR for
## paths missing from source; they grow from their anchors as progress rises.
@export var destination_anchors: PathAnchorSet:
	set(value):
		destination_anchors = value
		rebuild()
## Progress range shared by all anchored growth. Anchored paths on the parent start in anchor
## order; nested paths start once their parent has grown past the anchor.
@export var anchor_growth_window := Vector2(0.15, 0.97):
	set(value):
		anchor_growth_window = Vector2(clampf(minf(value.x, value.y), 0.0, 1.0), clampf(maxf(value.x, value.y), 0.0, 1.0))
		rebuild()
## Growth length of one anchored path, relative to a schedule where the parent spans 1.
@export_range(0.05, 1.0, 0.01) var anchor_growth_duration := 0.45:
	set(value):
		anchor_growth_duration = clampf(value, 0.05, 1.0)
		rebuild()
## Rotates each anchored path by the change of its parent's tangent at the anchor.
@export var anchor_follow_rotation := false:
	set(value):
		anchor_follow_rotation = value
		_publish()
@export_group("")

var _output: PathDefinition = PathDefinition.new()
var output: PathDefinition:
	get:
		return _output
var playing := false
var _a: Array[PackedVector2Array] = []
var _b: Array[PackedVector2Array] = []
var _width_a: Array[PackedFloat32Array] = []
var _width_b: Array[PackedFloat32Array] = []
# Anchored growth per morph entry: curve index, present side (1 destination only, -1 source
# only, 0 both), parent entry (-1 for lerp), anchor sample position and progress window.
var _curve_indices := PackedInt32Array()
var _present_sides := PackedInt32Array()
var _anchor_parents := PackedInt32Array()
var _anchor_samples := PackedFloat32Array()
var _anchor_windows := PackedVector2Array()
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
	_curve_indices.clear()
	_present_sides.clear()
	_anchor_parents.clear()
	_anchor_samples.clear()
	_anchor_windows.clear()
	# Feedback assignments publish an empty output through the same ownership boundary.
	if source == output or destination == output:
		_publish()
		return
	# Definition notifications forward nested geometry and width edits once.
	_watch(source)
	_watch(destination)
	_watch(source_anchors)
	_watch(destination_anchors)
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
		_curve_indices.append(index)
		_present_sides.append(1 if a.is_empty() else (-1 if b.is_empty() else 0))
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
	if missing_curve_mode == MissingCurveMode.GROW_FROM_ANCHOR:
		_resolve_anchor_growth()
	_publish()

## Resolves parent entries, anchor sample positions and growth windows. Parents precede
## children; unresolved paths keep the centroid collapse.
func _resolve_anchor_growth() -> void:
	var count := _a.size()
	var entries := {}
	for entry in count:
		entries[_curve_indices[entry]] = entry
	_anchor_parents.resize(count)
	_anchor_parents.fill(-1)
	_anchor_samples.resize(count)
	_anchor_samples.fill(0.0)
	_anchor_windows.resize(count)
	_anchor_windows.fill(Vector2.ZERO)
	var starts := PackedFloat32Array()
	starts.resize(count)
	var schedule_end := 0.0
	for entry in count:
		var side := _present_sides[entry]
		var anchors := destination_anchors if side > 0 else source_anchors
		if side == 0 or anchors == null:
			continue
		var parent_curve := anchors.get_parent_index(_curve_indices[entry])
		if parent_curve < 0 or not entries.has(parent_curve):
			continue
		var parent: int = entries[parent_curve]
		if parent >= entry or _present_sides[parent] == -side:
			continue
		var fraction := anchors.get_fraction(_curve_indices[entry])
		_anchor_parents[entry] = parent
		_anchor_samples[entry] = fraction * samples
		if _anchor_parents[parent] < 0:
			starts[entry] = fraction * ANCHOR_STAGGER
		else:
			starts[entry] = starts[parent] + anchor_growth_duration * fraction + ANCHOR_CHILD_GAP
		schedule_end = maxf(schedule_end, starts[entry] + anchor_growth_duration)
	var span := anchor_growth_window.y - anchor_growth_window.x
	for entry in count:
		if _anchor_parents[entry] >= 0:
			var first := anchor_growth_window.x + starts[entry] / schedule_end * span
			var last := anchor_growth_window.x + (starts[entry] + anchor_growth_duration) / schedule_end * span
			_anchor_windows[entry] = Vector2(first, maxf(last, first + 0.0001))

## Returns per-entry [points, widths] for anchored paths at the current progress, and an
## empty array for paths that use the regular interpolation.
func _anchored_frame() -> Array:
	var result := []
	var shapes: Array[PackedVector2Array] = []
	for entry in _a.size():
		var parent := _anchor_parents[entry]
		if parent < 0:
			var current := PackedVector2Array()
			for i in _a[entry].size():
				current.append(_a[entry][i].lerp(_b[entry][i], progress))
			shapes.append(current)
			result.append([])
			continue
		var grows_forward := _present_sides[entry] > 0
		var authored := _b[entry] if grows_forward else _a[entry]
		var authored_widths := _width_b[entry] if grows_forward else _width_a[entry]
		var parent_authored := _b[parent] if grows_forward else _a[parent]
		var anchor := _anchor_samples[entry]
		var anchor_now := _sample_polyline(shapes[parent], anchor)
		var anchor_authored := _sample_polyline(parent_authored, anchor)
		var turn := 0.0
		if anchor_follow_rotation:
			var tangent_now := _polyline_tangent(shapes[parent], anchor)
			var tangent_authored := _polyline_tangent(parent_authored, anchor)
			if tangent_now != Vector2.ZERO and tangent_authored != Vector2.ZERO:
				turn = tangent_authored.angle_to(tangent_now)
		var shaped := PackedVector2Array()
		for point in authored:
			shaped.append(anchor_now + (point - anchor_authored).rotated(turn))
		shapes.append(shaped)
		var window := _anchor_windows[entry]
		var growth := smoothstep(window.x, window.y, progress if grows_forward else 1.0 - progress)
		var fade := smoothstep(0.0, ANCHOR_WIDTH_RAMP, growth)
		var widths := PackedFloat32Array()
		for i in samples + 1:
			var cursor := growth * i
			var left := mini(int(cursor), samples - 1)
			widths.append(lerpf(authored_widths[left], authored_widths[left + 1], cursor - left) * fade)
		result.append([_clip_polyline(shaped, growth), widths])
	return result

## Point at a fractional sample position of a samples + 1 point polyline.
func _sample_polyline(points: PackedVector2Array, cursor: float) -> Vector2:
	var left := clampi(int(cursor), 0, points.size() - 2)
	return points[left].lerp(points[left + 1], clampf(cursor - left, 0.0, 1.0))

## Unit tangent at a fractional sample position; zero for degenerate spans.
func _polyline_tangent(points: PackedVector2Array, cursor: float) -> Vector2:
	var left := clampi(int(cursor), 0, points.size() - 2)
	var tangent := points[left + 1] - points[left]
	return tangent.normalized() if tangent.length_squared() > 0.000001 else Vector2.ZERO

## The first amount of a polyline's arc length, as samples + 1 evenly spaced points
## starting at its first point.
func _clip_polyline(points: PackedVector2Array, amount: float) -> PackedVector2Array:
	var cumulative := PackedFloat32Array([0.0])
	for i in range(1, points.size()):
		cumulative.append(cumulative[i - 1] + points[i - 1].distance_to(points[i]))
	var target := cumulative[-1] * amount
	var result := PackedVector2Array()
	var segment := 0
	for i in samples + 1:
		var distance := target * float(i) / samples
		while segment < points.size() - 2 and cumulative[segment + 1] < distance:
			segment += 1
		var length := cumulative[segment + 1] - cumulative[segment]
		var t := (distance - cumulative[segment]) / length if length > 0.00001 else 0.0
		result.append(points[segment].lerp(points[segment + 1], clampf(t, 0.0, 1.0)))
	return result

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
	var anchored: Array = _anchored_frame() if missing_curve_mode == MissingCurveMode.GROW_FROM_ANCHOR and _anchor_parents.size() == _a.size() else []
	for index in _a.size():
		var grown: Array = anchored[index] if index < anchored.size() else []
		var curve := Curve2D.new()
		curve.bake_interval = 2.0
		var actual_widths := PackedFloat32Array()
		var distances := PackedFloat32Array()
		var max_width := 0.0
		var distance := 0.0
		var previous := Vector2.ZERO
		for i in _a[index].size():
			var point: Vector2 = grown[0][i] if not grown.is_empty() else _a[index][i].lerp(_b[index][i], progress)
			curve.add_point(point)
			if i > 0:
				distance += previous.distance_to(point)
			previous = point
			distances.append(distance)
			var actual_width: float = grown[1][i] if not grown.is_empty() else lerpf(_width_a[index][i], _width_b[index][i], progress)
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
