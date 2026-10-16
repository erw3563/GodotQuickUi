class_name PathDeform2D
extends Node2D
## Single owner of source snapshot, work geometry and private PathDefinition output.
## Direct child PathModifier nodes execute in native scene-tree order each tick.
## Work offsets start at zero; modifiers compose private geometry snapshots.
const MAX_PATHS := 64
const MAX_CONTROLS := 512
const MAX_CONTROLS_PER_PATH := 64
const MAX_COORDINATE := 1000000.0
const MAX_DELTA := 0.1

class PathState:
	var curve: Curve2D
	var rest := PackedVector2Array()
	var incoming := PackedVector2Array()
	var outgoing := PackedVector2Array()
	var offsets := PackedVector2Array()
	var weights := PackedFloat32Array()
	var sample_position := Vector2.ZERO
	var progress := PackedFloat32Array()
	var normals := PackedVector2Array()
	var dirty := false

@export var definition: PathDefinition:
	set(value):
		if value == _output_definition:
			return
		_disconnect_sources()
		definition = value
		_bind_sources()
		_source_dirty = true
		if not _updating:
			rebuild_from_source()
@export var enabled := true:
	set(value):
		if enabled == value:
			return
		enabled = value
		if not enabled:
			_reset_pending = true
			reset_shape()
@export var automatic_update := true:
	set(value):
		automatic_update = value
		_accumulator = 0.0
		_elapsed_since_update = 0.0
		set_process(automatic_update)
@export_range(15, 120, 1) var update_hz := 30.0:
	set(value): update_hz = clampf(value, 15.0, 120.0) if is_finite(value) else 30.0
## Stable resource identity, separate from the shared source. Treat as read-only.
var output_definition: PathDefinition:
	get: return _output_definition
var sleeping := true
var truncated_source := false
var _output_definition := PathDefinition.new()
var _states: Array[PathState] = []
var _source_paths: Array[Curve2D] = []
var _connected_definition: PathDefinition
var _source_dirty := false
var _source_widths_dirty := false
var _updating := false
var _publishing := false
var _reset_pending := false
var _rebuilding := false
var _source_publish_pending := false
var _accumulator := 0.0
var _elapsed_since_update := 0.0
var _modifiers: Array[PathModifier] = []
var _metrics := {"update_count":0,"sample_count":0,"changed_controls":0,"publish_count":0,"sleep_skips":0,"sample_usec":0,"simulation_usec":0,"publish_usec":0,"source_rebuilds":0}
func _enter_tree() -> void:
	_accumulator = 0.0
	_elapsed_since_update = 0.0
	set_process(automatic_update)
	_bind_sources()
	_source_dirty = true

func _exit_tree() -> void:
	_disconnect_sources()
	_accumulator = 0.0
	_elapsed_since_update = 0.0

func _process(delta: float) -> void:
	if not automatic_update:
		return
	if not is_finite(delta) or delta <= 0.0:
		return
	_accumulator = minf(_accumulator + delta, MAX_DELTA)
	_elapsed_since_update = minf(_elapsed_since_update + delta, MAX_DELTA)
	var interval := 1.0 / update_hz
	if _accumulator + 0.000001 < interval:
		return
	# Preserve the schedule phase, but integrate actual time since the last tick.
	# Each frame integrates a single bounded update.
	_accumulator = maxf(_accumulator - floor((_accumulator + 0.000001) / interval) * interval, 0.0)
	var elapsed := _elapsed_since_update
	_elapsed_since_update = 0.0
	advance(elapsed)

func _refresh_modifiers() -> void:
	var ordered: Array[PathModifier] = []
	for child in get_children():
		if child is PathModifier and not child.is_queued_for_deletion(): ordered.append(child)
	if ordered != _modifiers:
		for modifier in ordered: modifier.reset_state()
		_modifiers = ordered

## Positive finite ticks advance clocks; suspension steps use a bounded delta.
func advance(delta: float) -> int:
	if _updating or _publishing or _rebuilding: return 0
	if _reset_pending: reset_shape()
	_updating = true
	_refresh_modifiers()
	if _source_dirty or (definition != null and definition.get_curves() != _source_paths): rebuild_from_source()
	if _source_widths_dirty: _copy_source_widths()
	if not enabled or not is_finite(delta) or delta <= 0.0:
		if _source_publish_pending: _publish()
		_updating = false
		return 0
	_metrics.update_count += 1
	var start := Time.get_ticks_usec()
	var previous_sample_usec: int = _metrics.sample_usec
	# Every tick composes offsets from the authored geometry snapshot.
	for state in _states: state.offsets.fill(Vector2.ZERO)
	sleeping = true
	for modifier in _modifiers:
		if not is_instance_valid(modifier) or modifier.get_parent() != self: continue
		if modifier.enabled:
			modifier.apply(_states, self, minf(delta, MAX_DELTA))
			sleeping = sleeping and not modifier.active
	_metrics.simulation_usec += maxi(Time.get_ticks_usec() - start - (_metrics.sample_usec - previous_sample_usec), 0)
	var changed := 0
	for state in _states:
		state.dirty = false
		if not state.offsets.is_empty(): state.offsets[0] = Vector2.ZERO
		for i in range(1, state.rest.size()):
			if not state.offsets[i].is_finite(): state.offsets[i] = Vector2.ZERO
			if state.curve.get_point_position(i) != state.rest[i] + state.offsets[i]:
				state.dirty = true
				changed += 1
	if changed > 0 or _source_publish_pending:
		start = Time.get_ticks_usec()
		_publish()
		_metrics.publish_usec += Time.get_ticks_usec() - start
		_metrics.changed_controls += changed
	else: _metrics.sleep_skips += 1
	_updating = false
	if _reset_pending: reset_shape()
	return changed

func reset_shape() -> void:
	if _updating or _publishing or _rebuilding: return
	_reset_pending = false
	if _source_dirty: rebuild_from_source()
	if _source_widths_dirty: _copy_source_widths()
	_refresh_modifiers()
	for modifier in _modifiers: modifier.reset_state()
	for state in _states:
		state.dirty = false
		for offset in state.offsets: state.dirty = state.dirty or offset != Vector2.ZERO
		state.offsets.fill(Vector2.ZERO)
	sleeping = true
	if not _states.is_empty() or _source_publish_pending: _publish()

func get_metrics() -> Dictionary:
	var result := _metrics.duplicate()
	result["sleeping"] = sleeping
	result["path_count"] = _states.size()
	result["truncated_source"] = truncated_source
	return result
func reset_metrics() -> void:
	for key in _metrics: _metrics[key] = 0
func _disconnect_sources() -> void:
	if _connected_definition != null:
		if _connected_definition.geometry_changed.is_connected(_on_source_changed):
			_connected_definition.geometry_changed.disconnect(_on_source_changed)
		if _connected_definition.widths_changed.is_connected(_on_source_widths_changed):
			_connected_definition.widths_changed.disconnect(_on_source_widths_changed)
	_connected_definition = null

func _bind_sources() -> void:
	_disconnect_sources()
	if definition == null:
		return
	_connected_definition = definition
	definition.geometry_changed.connect(_on_source_changed)
	definition.widths_changed.connect(_on_source_widths_changed)

func _on_source_changed() -> void:
	_source_dirty = true

func _on_source_widths_changed() -> void:
	_source_widths_dirty = true

func _copy_source_widths() -> void:
	# Width edits preserve curve identity, offsets and modifier phase.
	# Keep the batch open for this tick's combined publication.
	_source_widths_dirty = false
	if not _source_publish_pending:
		_output_definition.begin_update()
	_output_definition.copy_widths_from(definition)
	_source_publish_pending = true

func rebuild_from_source() -> void:
	if _publishing or _rebuilding:
		_source_dirty = true
		return
	_rebuilding = true
	_bind_sources()
	_states.clear()
	_source_paths.clear()
	_source_dirty = false
	_source_widths_dirty = false
	truncated_source = false
	var paths: Array[Curve2D] = []
	var total_controls := 0
	if definition != null:
		_source_paths.assign(definition.get_curves())
		truncated_source = _source_paths.size() > MAX_PATHS
		for path_index in mini(_source_paths.size(), MAX_PATHS):
			var original := _source_paths[path_index]
			if original == null:
				paths.append(null)
				continue
			var count := mini(original.point_count, mini(MAX_CONTROLS_PER_PATH, MAX_CONTROLS - total_controls))
			truncated_source = truncated_source or count != original.point_count
			total_controls += count
			var state := PathState.new()
			state.curve = Curve2D.new()
			state.curve.bake_interval = clampf(original.bake_interval, 0.1, 256.0) if is_finite(original.bake_interval) else 5.0
			state.curve.set_block_signals(true)
			for i in count:
				var point := _safe_vector(original.get_point_position(i))
				var incoming := _safe_vector(original.get_point_in(i))
				var outgoing := _safe_vector(original.get_point_out(i))
				state.rest.append(point)
				state.incoming.append(incoming)
				state.outgoing.append(outgoing)
				state.curve.add_point(point, incoming, outgoing)
			state.curve.set_block_signals(false)
			state.offsets.resize(count)
			state.offsets.fill(Vector2.ZERO)
			state.weights.resize(count)
			state.progress.resize(count)
			state.normals.resize(count)
			var total_length := 0.0
			for i in range(1, count):
				# Bezier arc-length approximation per segment, independent of control spacing.
				var previous := state.rest[i - 1]
				for sample in range(1, 17):
					var point := state.curve.sample(i - 1, float(sample) / 16.0)
					total_length += previous.distance_to(point)
					previous = point
				state.weights[i] = total_length
			for i in count:
				var progress := state.weights[i] / total_length if total_length > 0.0001 else float(i) / maxf(count - 1, 1)
				state.progress[i] = progress
				state.weights[i] = progress * progress
				var tangent := state.rest[mini(i + 1, count - 1)] - state.rest[maxi(i - 1, 0)]
				state.normals[i] = tangent.normalized().orthogonal() if tangent.length_squared() > 0.000001 else Vector2.RIGHT
			if count > 0:
				state.sample_position = state.rest[0].lerp(state.rest[count - 1], 0.72)
			paths.append(state.curve)
			_states.append(state)
	for modifier in _modifiers: modifier.reset_state()
	sleeping = true
	# Clone profiles during source rebuilds and explicit width edits. Keep
	# this batch open inside advance() so edits and deformation publish once.
	if not _source_publish_pending:
		_output_definition.begin_update()
	_output_definition.set_curves(paths)
	var source_indices := PackedInt32Array()
	for path_index in paths.size(): source_indices.append(path_index)
	_output_definition.copy_widths_from(definition, source_indices)
	_source_publish_pending = _updating
	if not _updating:
		_output_definition.end_update()
	_metrics.source_rebuilds += 1
	_rebuilding = false
	if _reset_pending and not _updating:
		reset_shape()

func _safe_vector(value: Vector2) -> Vector2:
	if not value.is_finite():
		return Vector2.ZERO
	return value.clamp(Vector2(-MAX_COORDINATE, -MAX_COORDINATE), Vector2(MAX_COORDINATE, MAX_COORDINATE))

func _publish() -> void:
	_publishing = true
	var published := _source_publish_pending
	if not _source_publish_pending:
		_output_definition.begin_update()
	_source_publish_pending = false
	for state in _states:
		if not state.dirty:
			continue
		published = true
		state.dirty = false
		state.curve.set_block_signals(true)
		for i in range(1, state.rest.size()):
			state.curve.set_point_position(i, state.rest[i] + state.offsets[i])
			# Keep authored Bezier handle lengths and shape. Rotate the handles with
			# the local deformed tangent; leave the pinned root's tangent untouched.
			var angle := 0.0
			if i > 0 and state.offsets[i] != Vector2.ZERO:
				var previous := i - 1
				var following := mini(i + 1, state.rest.size() - 1)
				var rest_tangent := state.rest[following] - state.rest[previous]
				var new_tangent := rest_tangent + state.offsets[following] - state.offsets[previous]
				if rest_tangent.length_squared() > 0.000001 and new_tangent.length_squared() > 0.000001:
					angle = rest_tangent.angle_to(new_tangent)
			state.curve.set_point_in(i, state.incoming[i].rotated(angle) if angle != 0.0 else state.incoming[i])
			state.curve.set_point_out(i, state.outgoing[i].rotated(angle) if angle != 0.0 else state.outgoing[i])
		state.curve.set_block_signals(false)
		state.curve.emit_changed()
	# PathDefinition forwards curve geometry changes. A single batch keeps
	# geometry notifications coalesced while preserving width metadata.
	_output_definition.end_update()
	if published:
		_metrics.publish_count += 1
	_publishing = false
