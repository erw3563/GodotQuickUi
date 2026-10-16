class_name PathRibbon2D
extends Node2D
## Independent, cached ribbon renderer. Output producers emit definition.changed once.
## Curve notifications mark dirty; flush() coalesces pending changes into one build.
const MAX_RENDER_SAMPLES := 4096
class RenderPath:
	var curve: Curve2D
	var control_count := 0
	var source_curve: Curve2D
## Native scene-tree binding to the producer's stable output resource.
@export var producer: PathDeform2D:
	set(value):
		producer = value
		definition = producer.output_definition if is_instance_valid(producer) else null
@export var definition: PathDefinition:
	set(value):
		if definition == value: return
		_disconnect_definition()
		definition = value
		_bind_definition()
		_topology_dirty = true
		_ribbon_style_dirty = true
		_render_dirty = true
@export var draw_enabled := true:
	set(value):
		draw_enabled = value
		_render_dirty = true
		queue_redraw()
@export var color := Color(0.78, 0.87, 1.0, 0.92):
	set(value):
		color = value if is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a) else Color.WHITE
		_render_dirty = true
@export_range(1, 16, 1) var samples_per_segment := 4:
	set(value):
		samples_per_segment = clampi(value, 1, 16)
		_render_dirty = true
		_topology_dirty = true

var max_offset := 0.0
var _states: Array[RenderPath] = []
var _render_dirty := true
var _topology_dirty := true
var _ribbon_style_dirty := true
var _bounds_dirty := true
var _render_counts := PackedInt32Array()
var _render_points := PackedVector2Array()
var _render_segments := PackedInt32Array()
var _render_parameters := PackedFloat32Array()
var _render_radii := PackedFloat32Array()
var _render_distances := PackedFloat32Array()
const WIDTH_SAMPLES := 256
var _width_samples: Array[PackedFloat32Array] = []
var _width_max_radius := 0.0
var _render_vertices := PackedVector2Array()
var _render_colors := PackedColorArray()
var _render_indices := PackedInt32Array()
var _mesh_color := Color.TRANSPARENT
var _mesh := ArrayMesh.new()
var _metrics := {"width_cache_builds":0,"render_builds":0,"render_cache_usec":0,"draw_submit_usec":0,"draw_count":0,"render_vertices":0}

func _disconnect_definition() -> void:
	if definition != null:
		if definition.changed.is_connected(_mark_dirty): definition.changed.disconnect(_mark_dirty)
		if definition.widths_changed.is_connected(_mark_widths_dirty): definition.widths_changed.disconnect(_mark_widths_dirty)
func _bind_definition() -> void:
	if definition == null: return
	if not definition.changed.is_connected(_mark_dirty): definition.changed.connect(_mark_dirty)
	if not definition.widths_changed.is_connected(_mark_widths_dirty): definition.widths_changed.connect(_mark_widths_dirty)
func _mark_widths_dirty() -> void:
	_ribbon_style_dirty = true
	_render_dirty = true
func _enter_tree() -> void:
	_bind_definition()
	# Width resources may have been edited while this renderer was detached.
	_ribbon_style_dirty = true
	_render_dirty = true
func _exit_tree() -> void: _disconnect_definition()
func _mark_dirty() -> void: _render_dirty = true
func _process(_delta: float) -> void: flush()
func flush() -> void:
	if not _render_dirty: return
	var paths: Array[Curve2D] = definition.get_curves() if definition != null else []
	var topology_changed := paths.size() != _states.size()
	if not topology_changed:
		for i in paths.size():
			if paths[i] != _states[i].source_curve or (paths[i] != null and paths[i].point_count != _states[i].control_count): topology_changed = true
	if topology_changed:
		_states.clear()
		_disconnect_definition()
		_bind_definition()
		for curve in paths:
			var state := RenderPath.new()
			state.curve = curve if curve != null else Curve2D.new()
			state.control_count = state.curve.point_count
			state.source_curve = curve
			_states.append(state)
		_topology_dirty = true
	_bounds_dirty = true
	_rebuild_render_cache()
func get_build_mesh() -> ArrayMesh: return _mesh
func get_metrics() -> Dictionary: return _metrics.duplicate()
func reset_metrics() -> void:
	for key in _metrics: _metrics[key] = 0
func _draw() -> void:
	if not draw_enabled or _mesh.get_surface_count() == 0:
		return
	var start := Time.get_ticks_usec()
	draw_mesh(_mesh, null)
	_metrics.draw_submit_usec += Time.get_ticks_usec() - start
	_metrics.draw_count += 1

func _prepare_render_topology() -> void:
	_render_counts.clear()
	_render_segments.clear()
	_render_parameters.clear()
	_render_indices.clear()
	var total_samples := 0
	for state in _states:
		var count := 0
		if state.curve.point_count >= 2 and MAX_RENDER_SAMPLES - total_samples >= 2:
			count = mini((state.curve.point_count - 1) * samples_per_segment + 1, MAX_RENDER_SAMPLES - total_samples)
		_render_counts.append(count)
		for i in count:
			var cursor := float(i) * float(state.curve.point_count - 1) / float(count - 1)
			var segment := mini(int(cursor), state.curve.point_count - 2)
			_render_segments.append(segment)
			_render_parameters.append(cursor - float(segment))
			if i < count - 1:
				var index := (total_samples + i) * 2
				_render_indices.append_array(PackedInt32Array([index, index + 1, index + 2, index + 1, index + 3, index + 2]))
		total_samples += count
	_render_points.resize(total_samples)
	_render_vertices.resize(total_samples * 2)
	_render_colors.resize(total_samples * 2)
	_render_radii.resize(total_samples)
	_render_distances.resize(total_samples)
	_ribbon_style_dirty = true
	_topology_dirty = false

func _refresh_width_cache() -> void:
	_width_samples.clear()
	_width_max_radius = 0.0
	for index in _states.size():
		var samples := PackedFloat32Array()
		for i in WIDTH_SAMPLES + 1:
			samples.append(definition.sample_width(index, float(i) / WIDTH_SAMPLES) * 0.5)
			_width_max_radius = maxf(_width_max_radius, samples[-1])
		_width_samples.append(samples)
	_ribbon_style_dirty = false
	_metrics.width_cache_builds += 1

func _rebuild_render_cache() -> void:
	var start := Time.get_ticks_usec()
	_render_dirty = false
	if not draw_enabled:
		queue_redraw()
		_metrics.render_cache_usec += Time.get_ticks_usec() - start
		return
	var rebuild_surface := _topology_dirty or color != _mesh_color or _mesh.get_surface_count() == 0
	if _topology_dirty:
		_prepare_render_topology()
	if _ribbon_style_dirty:
		_refresh_width_cache()
	var bounds_min := Vector2(INF, INF)
	var bounds_max := Vector2(-INF, -INF)
	var cursor := 0
	for path_index in _states.size():
		var count := _render_counts[path_index]
		if count < 2:
			continue
		var curve := _states[path_index].curve
		var end := cursor + count
		for i in range(cursor, end):
			var point := curve.sample(_render_segments[i], _render_parameters[i])
			_render_points[i] = point
			_render_distances[i] = _render_distances[i - 1] + point.distance_to(_render_points[i - 1]) if i > cursor else 0.0
			bounds_min = bounds_min.min(point)
			bounds_max = bounds_max.max(point)
		# Reuse preallocated arc-distance, width and profile-sample buffers.
		var total := _render_distances[end - 1]
		var inverse_total := float(WIDTH_SAMPLES) / total if total > 0.00001 else 0.0
		var widths := _width_samples[path_index]
		for i in range(cursor, end):
			var width_cursor := clampf(_render_distances[i] * inverse_total, 0.0, WIDTH_SAMPLES)
			var left := mini(int(width_cursor), WIDTH_SAMPLES - 1)
			_render_radii[i] = lerpf(widths[left], widths[left + 1], width_cursor - left)
			var tangent := _render_points[mini(i + 1, end - 1)] - _render_points[maxi(cursor, i - 1)]
			var normal := tangent.normalized().orthogonal() if tangent.length_squared() > 0.000001 else Vector2.UP
			var side := normal * _render_radii[i]
			_render_vertices[i * 2] = _render_points[i] + side
			_render_vertices[i * 2 + 1] = _render_points[i] - side
		cursor = end
	# Rendered polyline plus half-width bounds, computed during the sampling pass.
	if bounds_min.is_finite() and bounds_max.is_finite():
		var padding := Vector2.ONE * (_width_max_radius + 1.0)
		var origin := bounds_min - padding
		var extent := bounds_max - bounds_min + padding * 2.0
		_mesh.custom_aabb = AABB(Vector3(origin.x, origin.y, -1.0), Vector3(extent.x, extent.y, 2.0))
	if _render_vertices.is_empty():
		_mesh.clear_surfaces()
	elif rebuild_surface:
		_mesh.clear_surfaces()
		_render_colors.fill(color)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _render_vertices
		arrays[Mesh.ARRAY_COLOR] = _render_colors
		arrays[Mesh.ARRAY_INDEX] = _render_indices
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	else:
		# PackedVector2 positions have a contiguous 8-byte layout. Stable topology
		# reuses the index/color buffers and surface for vertex-position updates.
		_mesh.surface_update_vertex_region(0, 0, _render_vertices.to_byte_array())
	_mesh_color = color
	_metrics.render_vertices = _render_vertices.size()
	_metrics.render_builds += 1
	_metrics.render_cache_usec += Time.get_ticks_usec() - start
	queue_redraw()
