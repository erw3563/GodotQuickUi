@tool
@abstract
class_name PixelProjectileTrail2D
extends ProjectileVisualEffect2D
## 世界空间尾迹的采样、距离裁剪与残留时钟；派生表现消费轨迹与出生时刻绘制。

signal finished
@export var trail_color := Color("ce894f")
@export_range(0.5, 8.0, 0.5) var width := 2.0
@export_range(0.5, 8.0, 0.5) var sample_spacing := 2.0
@export_range(2.0, 96.0, 1.0) var max_length := 24.0
@export_range(0.02, 1.0, 0.01) var lifetime := 0.14
@export_range(2, 128, 1) var max_points := 64
@export_range(8.0, 512.0, 1.0) var teleport_threshold := 96.0
@export var auto_free := false

var emitting := false
var _points := PackedVector2Array()
var _births := PackedFloat64Array()
var _clock := 0.0
var _previous := Vector2.ZERO
var _sample_clock := 0.0
var _residual := 0.0
var _pending_finish := false
var _generation := 0

func _ready() -> void:
	set_notify_transform(true)
	set_process(emitting or not _points.is_empty())

func begin(world_position: Vector2) -> void:
	reset()
	if not world_position.is_finite():
		return
	emitting = true
	_pending_finish = true
	_previous = world_position
	_sample_clock = _clock
	_points.append(world_position)
	_births.append(_clock)
	set_process(true)
	queue_redraw()

func sample(world_position: Vector2, delta: float = 0.0, teleport: bool = false) -> void:
	if not emitting or not world_position.is_finite():
		return
	var travel := _previous.distance_to(world_position)
	if teleport or travel > maxf(1.0, teleport_threshold):
		begin(world_position)
		return
	if travel <= 0.000001:
		_sample_clock = _clock
		_previous = world_position
		return
	var spacing := clampf(sample_spacing, 0.5, 8.0)
	var elapsed := maxf(0.0, _clock - _sample_clock)
	if is_finite(delta) and delta > 0.0:
		elapsed = minf(delta, maxf(0.0, _clock))
	var first_distance := spacing - fmod(_residual, spacing)
	var count := maxi(0, int(floor((travel - first_distance) / spacing)) + 1)
	# Arithmetic trimming bounds the samples generated for each movement segment.
	var cap := clampi(max_points, 2, 128)
	var first_index := maxi(0, count - cap)
	for i in range(first_index, count):
		var fraction := clampf((first_distance + i * spacing) / travel, 0.0, 1.0)
		_points.append(_previous.lerp(world_position, fraction))
		_births.append(_clock - elapsed * (1.0 - fraction))
	_residual = fmod(_residual + travel, spacing)
	_previous = world_position
	_sample_clock = _clock
	_trim()
	queue_redraw()

func stop_emitting() -> void:
	emitting = false
	# Preserve the exact final endpoint, including sub-spacing travel.
	if not _points.is_empty() and _points[-1].distance_squared_to(_previous) > 0.000001:
		_points.append(_previous)
		_births.append(_clock)
	_trim()
	_complete_if_empty()
	if is_instance_valid(self):
		queue_redraw()

func reset() -> void:
	_generation += 1
	emitting = false
	_pending_finish = false
	_points.clear()
	_births.clear()
	_clock = 0.0
	_sample_clock = 0.0
	_residual = 0.0
	_previous = Vector2.ZERO
	set_process(false)
	queue_redraw()

func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	# Bounded time steps expire all points safely after a long pause.
	_clock += minf(delta, 10.0)
	_trim()
	_complete_if_empty()
	if is_instance_valid(self):
		queue_redraw()

func _process(delta: float) -> void:
	advance(delta)

func _trim() -> void:
	var duration := clampf(lifetime, 0.02, 1.0)
	while not _births.is_empty() and _clock - _births[0] >= duration:
		_points.remove_at(0)
		_births.remove_at(0)
	var cap := clampi(max_points, 2, 128)
	while _points.size() > cap:
		_points.remove_at(0)
		_births.remove_at(0)
	# Distance includes the moving unsampled endpoint, and follows the polyline.
	var length_left := clampf(max_length, 2.0, 96.0)
	var last := _previous if emitting else (_points[-1] if not _points.is_empty() else _previous)
	for i in range(_points.size() - 1, -1, -1):
		var distance := last.distance_to(_points[i])
		if distance > length_left:
			_points[i] = last.lerp(_points[i], length_left / distance)
			_births[i] = lerpf(_births[mini(i + 1, _births.size() - 1)], _births[i], length_left / distance)
			if i > 0:
				_points = _points.slice(i)
				_births = _births.slice(i)
			break
		length_left -= distance
		last = _points[i]

func _complete_if_empty() -> void:
	if emitting or not _points.is_empty():
		return
	set_process(false)
	if not _pending_finish:
		return
	_pending_finish = false
	var generation := _generation
	finished.emit()
	if not is_instance_valid(self):
		return
	if auto_free and _generation == generation and not emitting and is_inside_tree():
		queue_free()

func get_points() -> PackedVector2Array:
	return _points.duplicate()

func get_point_ages() -> PackedFloat32Array:
	var ages := PackedFloat32Array()
	for birth in _births:
		ages.append(maxf(0.0, _clock - birth))
	return ages

func get_active_count() -> int:
	return _points.size()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		queue_redraw()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree() and not is_visible_in_tree():
		reset()
	elif what == NOTIFICATION_EXIT_TREE:
		reset()

func start_effect(world_position: Vector2, _direction: Vector2, _seed: int = 0) -> void:
	auto_free = false
	begin(world_position)
	set_process(false)

func follow_effect(world_position: Vector2, _velocity: Vector2, delta: float) -> void:
	sample(world_position, delta)
	set_process(false)

func advance_effect(delta: float) -> void:
	advance(delta)
	set_process(false)

func stop_effect() -> void:
	stop_emitting()
	set_process(false)

func effect_finished() -> bool:
	return not emitting and get_active_count() == 0
