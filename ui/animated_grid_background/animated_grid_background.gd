@tool
class_name AnimatedGridBackground
extends Control
## A bounded, passive Control drawing three alternative grid topologies.
## Transport, geometry, placement and appearance remain independent controls.

signal progress_changed(value: float)
signal playback_finished(at_end: bool)

enum Geometry { POLAR, ORTHOGONAL, DIAGONAL }
const MAX_FAMILY_COUNT: int = 128
const MAX_RING_SEGMENTS: int = 256
const MAX_PATHS: int = MAX_FAMILY_COUNT * 2
const MAX_VERTICES: int = MAX_FAMILY_COUNT * (MAX_RING_SEGMENTS + 1) + MAX_FAMILY_COUNT * 2

@export_group("Geometry")
@export var geometry: Geometry = Geometry.POLAR:
	set(value):
		geometry = clampi(value, 0, 2) as Geometry
		_invalidate_geometry()
@export_range(2.0, 512.0, 0.5) var spacing: float = 34.0:
	set(value):
		if is_finite(value):
			spacing = clampf(value, 2.0, 512.0)
			_invalidate_geometry()
@export_range(0, 128, 1) var ring_count: int = 24:
	set(value):
		ring_count = clampi(value, 0, MAX_FAMILY_COUNT)
		_invalidate_geometry()
@export_range(0, 128, 1) var ray_count: int = 32:
	set(value):
		ray_count = clampi(value, 0, MAX_FAMILY_COUNT)
		_invalidate_geometry()
@export_range(0, 128, 1) var column_count: int = 45:
	set(value):
		column_count = clampi(value, 0, MAX_FAMILY_COUNT)
		_invalidate_geometry()
@export_range(0, 128, 1) var row_count: int = 45:
	set(value):
		row_count = clampi(value, 0, MAX_FAMILY_COUNT)
		_invalidate_geometry()
@export_range(16, 256, 1) var ring_segments: int = 160:
	set(value):
		ring_segments = clampi(value, 16, MAX_RING_SEGMENTS)
		_invalidate_geometry()

@export_group("Placement")
@export var center_ratio: Vector2 = Vector2(0.58, 0.54):
	set(value):
		if value.is_finite():
			center_ratio = value.clamp(Vector2(-2.0, -2.0), Vector2(3.0, 3.0))
			queue_redraw()
@export var pan_offset: Vector2 = Vector2.ZERO:
	set(value):
		if value.is_finite():
			pan_offset = value.clamp(Vector2(-32768.0, -32768.0), Vector2(32768.0, 32768.0))
			queue_redraw()
@export_range(-3.141593, 3.141593, 0.001, "radians_as_degrees") var grid_rotation: float = 0.0:
	set(value):
		if is_finite(value):
			grid_rotation = wrapf(value, -PI, PI)
			queue_redraw()

@export_group("Drawing")
@export_range(0.0, 1.0, 0.001) var reveal_progress: float = 1.0:
	set(value):
		if is_finite(value):
			var next := clampf(value, 0.0, 1.0)
			if reveal_progress != next:
				reveal_progress = next
				queue_redraw()
				progress_changed.emit(reveal_progress)
@export_range(0.0, 0.95, 0.01) var stagger: float = 0.26:
	set(value):
		if is_finite(value):
			stagger = clampf(value, 0.0, 0.95)
			queue_redraw()
@export_range(0.05, 120.0, 0.05) var duration_seconds: float = 2.75:
	set(value):
		if is_finite(value):
			duration_seconds = clampf(value, 0.05, 120.0)
@export var autoplay: bool = false

@export_group("Stroke")
@export var stroke_color: Color = Color(0.19, 0.48, 0.47, 0.54):
	set(value):
		if _finite_color(value):
			stroke_color = value
			queue_redraw()
@export var major_stroke_color: Color = Color(0.12, 0.40, 0.40, 0.86):
	set(value):
		if _finite_color(value):
			major_stroke_color = value
			queue_redraw()
@export_range(0.5, 12.0, 0.1) var stroke_width: float = 1.1:
	set(value):
		if is_finite(value):
			stroke_width = clampf(value, 0.5, 12.0)
			queue_redraw()
@export_range(0.5, 12.0, 0.1) var major_stroke_width: float = 1.5:
	set(value):
		if is_finite(value):
			major_stroke_width = clampf(value, 0.5, 12.0)
			queue_redraw()
@export_range(0, 32, 1) var major_every: int = 4:
	set(value):
		major_every = clampi(value, 0, 32)
		queue_redraw()
@export var antialiased: bool = true:
	set(value):
		antialiased = value
		queue_redraw()
@export_group("Background")
@export var background_enabled: bool = false:
	set(value):
		background_enabled = value
		queue_redraw()
@export var background_color: Color = Color(0.855, 0.921, 0.861, 1.0):
	set(value):
		if _finite_color(value):
			background_color = value
			queue_redraw()

var playing: bool = false
var direction: float = 1.0
var build_revision: int = 0
var _paths: Array[PackedVector2Array] = []
var _path_ordinals: PackedInt32Array = []
var _transport_revision: int = 0
var _did_ready: bool = false
var _geometry_dirty: bool = true
var _built_size := Vector2(-1.0, -1.0)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	clip_contents = true

func _enter_tree() -> void:
	# Re-entry preserves the current cancelled state.
	set_process(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not resized.is_connected(_invalidate_geometry):
		resized.connect(_invalidate_geometry)
	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)
	_invalidate_geometry()

func _ready() -> void:
	if not _did_ready:
		_did_ready = true
		if autoplay and not Engine.is_editor_hint():
			replay()

func _exit_tree() -> void:
	cancel()

func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		cancel()

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	## Deterministic transport follows this node’s lifecycle.
	if not playing or not is_inside_tree() or not is_visible_in_tree():
		return
	if not is_finite(delta) or delta <= 0.0:
		return
	var revision := _transport_revision
	var next := clampf(reveal_progress + delta * direction / duration_seconds, 0.0, 1.0)
	reveal_progress = next
	# progress_changed is public and synchronous: a listener can take ownership.
	if revision != _transport_revision or not playing or reveal_progress != next:
		return
	if not is_inside_tree() or not is_visible_in_tree() or is_queued_for_deletion():
		return
	if next == 0.0 or next == 1.0:
		cancel()
		playback_finished.emit(next == 1.0)

func replay() -> void:
	_transport_revision += 1
	var revision := _transport_revision
	_stop_processing()
	direction = 1.0
	reveal_progress = 0.0
	if revision == _transport_revision:
		_play()

func reverse() -> void:
	_transport_revision += 1
	# Endpoint commands head inward. Mid-run reversal preserves the playhead.
	if reveal_progress <= 0.0:
		direction = 1.0
	elif reveal_progress >= 1.0:
		direction = -1.0
	else:
		direction = -direction
	_play()

func resume() -> void:
	_transport_revision += 1
	if reveal_progress <= 0.0:
		direction = 1.0
	elif reveal_progress >= 1.0:
		direction = -1.0
	_play()

func _play() -> void:
	playing = is_inside_tree() and is_visible_in_tree() and not is_queued_for_deletion() and not Engine.is_editor_hint()
	set_process(playing)

func cancel() -> void:
	_transport_revision += 1
	_stop_processing()

func _stop_processing() -> void:
	playing = false
	set_process(false)

func pause() -> void:
	cancel()

func seek(value: float) -> void:
	if not is_finite(value):
		return
	cancel()
	reveal_progress = value

func _finite_color(value: Color) -> bool:
	return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)

func _invalidate_geometry() -> void:
	_geometry_dirty = true
	queue_redraw()

func _safe_size() -> Vector2:
	if not size.is_finite():
		return Vector2.ZERO
	return size.clamp(Vector2.ZERO, Vector2(65536.0, 65536.0))

func _ensure_geometry() -> void:
	var bounds := _safe_size()
	if not _geometry_dirty and bounds == _built_size:
		return
	_geometry_dirty = false
	_built_size = bounds
	_paths.clear()
	_path_ordinals.clear()
	build_revision += 1
	if bounds.x <= 0.0 or bounds.y <= 0.0:
		return
	match geometry:
		Geometry.POLAR:
			_build_polar(bounds)
		Geometry.ORTHOGONAL:
			_build_lattice(bounds, 0.0)
		Geometry.DIAGONAL:
			_build_lattice(bounds, PI * 0.25)

func _add_path(points: PackedVector2Array, ordinal: int) -> void:
	_paths.append(points)
	_path_ordinals.append(ordinal)

func _build_polar(bounds: Vector2) -> void:
	for i in ring_count:
		var radius := spacing * (i + 1)
		var points := PackedVector2Array()
		points.resize(ring_segments + 1)
		for j in ring_segments + 1:
			points[j] = Vector2.from_angle(-PI * 0.5 + TAU * float(j) / ring_segments) * radius
		_add_path(points, i + 1)
	# Rays remain useful when the rings are independently disabled.
	var radius := maxf(bounds.length() * 1.5, ring_count * spacing)
	for i in ray_count:
		var endpoint := Vector2.from_angle(-PI * 0.5 + TAU * float(i) / maxi(1, ray_count)) * radius
		_add_path(PackedVector2Array([Vector2.ZERO, endpoint]), i)

func _build_lattice(bounds: Vector2, angle: float) -> void:
	# A fixed margin supports live pan with the current cached paths.
	# The authored geometry has finite bounds.
	var extent := bounds.length() * 4.0 + 65536.0
	var cross_extent := extent
	for i in column_count:
		var x := (float(i) - float(column_count - 1) * 0.5) * spacing
		_add_path(PackedVector2Array([Vector2(x, -cross_extent).rotated(angle), Vector2(x, cross_extent).rotated(angle)]), i)
	for i in row_count:
		var y := (float(i) - float(row_count - 1) * 0.5) * spacing
		_add_path(PackedVector2Array([Vector2(-extent, y).rotated(angle), Vector2(extent, y).rotated(angle)]), i)

func get_path_count() -> int:
	_ensure_geometry()
	return _paths.size()

func get_vertex_count() -> int:
	_ensure_geometry()
	var count := 0
	for points in _paths:
		count += points.size()
	return count

func get_path_progress(index: int) -> float:
	_ensure_geometry()
	if index < 0 or index >= _paths.size():
		return 0.0
	if reveal_progress <= 0.0:
		return 0.0
	if reveal_progress >= 1.0:
		return 1.0
	var start := stagger * float(index) / maxi(1, _paths.size() - 1)
	return clampf((reveal_progress - start) / (1.0 - stagger), 0.0, 1.0)

func get_path_points(index: int) -> PackedVector2Array:
	_ensure_geometry()
	if index < 0 or index >= _paths.size():
		return PackedVector2Array()
	return _paths[index].duplicate()

func get_visible_path_points(index: int) -> PackedVector2Array:
	_ensure_geometry()
	if index < 0 or index >= _paths.size():
		return PackedVector2Array()
	var source := _paths[index]
	if geometry != Geometry.POLAR:
		source = _clip_lattice_path(source)
	return _partial_path(source, get_path_progress(index))

func _clip_lattice_path(source: PackedVector2Array) -> PackedVector2Array:
	# Clip before revealing so visible paths own the drawing time.
	# Transform edits therefore preserve geometry and the normalized playhead.
	var bounds := _safe_size()
	var origin := bounds * center_ratio + pan_offset
	var a := source[0].rotated(grid_rotation) + origin
	var b := source[1].rotated(grid_rotation) + origin
	var vector := b - a
	var enter := 0.0
	var leave := 1.0
	for axis in 2:
		if absf(vector[axis]) < 0.00001:
			if a[axis] < 0.0 or a[axis] > bounds[axis]:
				return PackedVector2Array()
			continue
		var first := -a[axis] / vector[axis]
		var last := (bounds[axis] - a[axis]) / vector[axis]
		if first > last:
			var swap := first
			first = last
			last = swap
		enter = maxf(enter, first)
		leave = minf(leave, last)
		if enter >= leave:
			return PackedVector2Array()
	return PackedVector2Array([(a.lerp(b, enter) - origin).rotated(-grid_rotation), (a.lerp(b, leave) - origin).rotated(-grid_rotation)])

func _partial_path(source: PackedVector2Array, progress: float) -> PackedVector2Array:
	if progress <= 0.0 or source.size() < 2:
		return PackedVector2Array()
	if progress >= 1.0:
		return source
	var segments := source.size() - 1
	var position := progress * segments
	var complete := mini(floori(position), segments - 1)
	var points := source.slice(0, complete + 1)
	points.append(source[complete].lerp(source[complete + 1], position - complete))
	return points

func _draw() -> void:
	_ensure_geometry()
	var bounds := _safe_size()
	if bounds.x <= 0.0 or bounds.y <= 0.0:
		return
	if background_enabled:
		draw_rect(Rect2(Vector2.ZERO, bounds), background_color)
	var origin := bounds * center_ratio + pan_offset
	draw_set_transform(origin, grid_rotation)
	for i in _paths.size():
		var points := get_visible_path_points(i)
		if points.size() < 2:
			continue
		var major := major_every > 0 and _path_ordinals[i] % major_every == 0
		draw_polyline(points, major_stroke_color if major else stroke_color, major_stroke_width if major else stroke_width, antialiased)
	draw_set_transform(Vector2.ZERO)
