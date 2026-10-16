@tool
class_name GDTargetLock
extends Control
## Transform-aware, single-playhead target lock. Add the supplied scene over an
## existing CanvasItem. The scene author retains the target’s pose and ownership.
signal acquired(target: CanvasItem)
signal released
signal target_lost
signal state_changed(state: int)

enum State { RELEASED, ACQUIRING, LOCKED, RELEASING, LOST, CANCELLED }
@export var target_path: NodePath
@export var style: GDTargetLockStyle
@export var local_bounds := Rect2(-42.0, -57.0, 84.0, 114.0)
@export var padding := Vector2(0.0, 0.0)
@export var label_text: String = "L01 / 0534"
@export var label_offset := Vector2(-150.0, -72.0)
@export var auto_acquire: bool = true
@export var auto_reacquire: bool = true
@export var animate: bool = true
@export_range(0.0, 10.0) var acquire_duration: float = 0.85
@export_range(0.0, 10.0) var release_duration: float = 0.3

var state: State = State.RELEASED
var strength: float = 0.0
var pulse_phase: float = 1.0
var requested: bool = false
var tracking: bool = false
var target_quad := PackedVector2Array()
var target_rect := Rect2()
var _target: WeakRef
var _direct_target: bool = false
var _elapsed: float = 0.0
var _duration: float = 0.0
var _from: float = 0.0
var _to: float = 0.0
var _playing: bool = false
var _loss_emitted: bool = false
var _revision: int = 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if style == null:
		style = GDTargetLockStyle.new()
	if not Engine.is_editor_hint() and auto_acquire:
		acquire()
	refresh()

func _process(delta: float) -> void:
	if not Engine.is_editor_hint() and animate:
		advance(delta)
	else:
		refresh()

func set_target(value: CanvasItem) -> void:
	_revision += 1
	var revision := _revision
	_direct_target = true
	_target = weakref(value) if is_instance_valid(value) else null
	_loss_emitted = false
	_playing = false
	strength = 0.0
	_set_state(State.LOST if requested else State.RELEASED)
	if revision == _revision:
		refresh()

func use_target_path(value: NodePath) -> void:
	_revision += 1
	var revision := _revision
	target_path = value
	_direct_target = false
	_target = null
	_playing = false
	strength = 0.0
	_set_state(State.LOST if requested else State.RELEASED)
	if revision == _revision:
		refresh()

func get_target() -> CanvasItem:
	if _direct_target:
		return _target.get_ref() as CanvasItem if _target != null else null
	return get_node_or_null(target_path) as CanvasItem if not target_path.is_empty() else null

func _set_state(value: State) -> void:
	if state != value:
		state = value
		state_changed.emit(state)

func _start(destination: float, duration: float, next_state: State) -> void:
	var revision := _revision
	_from = strength
	_to = destination
	_elapsed = 0.0
	_duration = maxf(duration, 0.0) if is_finite(duration) else 0.0
	_playing = true
	_set_state(next_state)
	if revision != _revision:
		return
	if _duration <= 0.0:
		_finish()

func acquire(value: CanvasItem = null) -> void:
	_revision += 1
	var revision := _revision
	if value != null:
		_direct_target = true
		_target = weakref(value)
		_loss_emitted = false
		strength = 0.0
	requested = true
	refresh(false)
	if revision != _revision:
		return
	if not tracking:
		_lose()
		return
	_loss_emitted = false
	pulse_phase = 0.0
	_start(1.0, acquire_duration, State.ACQUIRING)
	_redraw_layers()

func release() -> void:
	_revision += 1
	requested = false
	pulse_phase = 1.0
	_start(0.0, release_duration, State.RELEASING)
	_redraw_layers()

func cancel(reset: bool = true) -> void:
	_revision += 1
	requested = false
	_playing = false
	pulse_phase = 1.0
	if reset:
		strength = 0.0
	_set_state(State.CANCELLED)
	_redraw_layers()

func seek_acquisition(progress: float) -> void:
	if not is_finite(progress):
		return
	_revision += 1
	var revision := _revision
	requested = true
	_playing = false
	pulse_phase = clampf(progress, 0.0, 1.0)
	strength = _ease(pulse_phase)
	_set_state(State.LOCKED if pulse_phase >= 1.0 else State.ACQUIRING)
	if revision != _revision:
		return
	refresh(false)
	if not tracking:
		_lose()

func seek_release(progress: float) -> void:
	if not is_finite(progress):
		return
	_revision += 1
	var revision := _revision
	requested = false
	_playing = false
	pulse_phase = 1.0
	strength = 1.0 - _ease(clampf(progress, 0.0, 1.0))
	_set_state(State.RELEASED if progress >= 1.0 else State.RELEASING)
	if revision == _revision:
		refresh(false)

func advance(delta: float) -> void:
	if not is_finite(delta) or delta < 0.0:
		return
	refresh()
	if _playing:
		_elapsed = minf(_elapsed + delta, _duration)
		var fraction := 1.0 if _duration <= 0.0 else _elapsed / _duration
		strength = lerpf(_from, _to, _ease(fraction))
		if state == State.ACQUIRING:
			pulse_phase = fraction
		if fraction >= 1.0:
			_finish()
	_redraw_layers()

func _finish() -> void:
	var revision := _revision
	var destination := _to
	var completed_target := get_target()
	strength = destination
	_playing = false
	pulse_phase = 1.0
	_set_state(State.LOCKED if destination >= 1.0 else State.RELEASED)
	if revision != _revision:
		return
	if destination >= 1.0:
		refresh(false)
		if revision == _revision and tracking and get_target() == completed_target:
			acquired.emit(completed_target)
	else:
		released.emit()

func _lose() -> void:
	_revision += 1
	var revision := _revision
	tracking = false
	strength = 0.0
	pulse_phase = 1.0
	_playing = false
	_set_state(State.LOST)
	if revision != _revision:
		return
	if not _loss_emitted:
		_loss_emitted = true
		target_lost.emit()
	_redraw_layers()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree() and not is_visible_in_tree() and not Engine.is_editor_hint():
		cancel()

func _exit_tree() -> void:
	# Teardown invalidates writers and clears owned runtime state.
	_revision += 1
	_playing = false
	requested = false
	strength = 0.0
	pulse_phase = 1.0
	tracking = false
	state = State.CANCELLED

func refresh(allow_reacquire: bool = true) -> void:
	var target := get_target()
	var valid := is_instance_valid(target) and is_inside_tree() and target.is_inside_tree()
	if valid:
		valid = target.is_visible_in_tree() and target.get_viewport() == get_viewport() and is_visible_in_tree()
	var transform := get_global_transform_with_canvas()
	if not valid or absf(transform.determinant()) < 0.000001:
		tracking = false
		target_quad.clear()
		if requested:
			_lose()
		_redraw_layers()
		return
	var bounds := _bounds_for(target)
	if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		tracking = false
		target_quad.clear()
		if requested:
			_lose()
		_redraw_layers()
		return
	var relative := transform.affine_inverse() * target.get_global_transform_with_canvas()
	if not is_finite(relative.determinant()) or absf(relative.determinant()) < 0.000001:
		tracking = false
		target_quad.clear()
		if requested:
			_lose()
		_redraw_layers()
		return
	var quad := PackedVector2Array([
		relative * bounds.position, relative * Vector2(bounds.end.x, bounds.position.y),
		relative * bounds.end, relative * Vector2(bounds.position.x, bounds.end.y)])
	for point in quad:
		if not point.is_finite():
			_lose()
			return
	target_quad = quad
	target_rect = Rect2(quad[0], Vector2.ZERO)
	for point in quad:
		target_rect = target_rect.expand(point)
	target_rect = target_rect.grow_individual(maxf(padding.x, 0.0), maxf(padding.y, 0.0), maxf(padding.x, 0.0), maxf(padding.y, 0.0))
	tracking = true
	if allow_reacquire and requested and auto_reacquire and state == State.LOST:
		_loss_emitted = false
		pulse_phase = 0.0
		_start(1.0, acquire_duration, State.ACQUIRING)
	_redraw_layers()

func _bounds_for(target: CanvasItem) -> Rect2:
	if target is Control:
		return Rect2(Vector2.ZERO, target.size)
	if target.has_method("get_target_lock_rect"):
		var supplied: Variant = target.call("get_target_lock_rect")
		if supplied is Rect2:
			return supplied
	if target is Sprite2D:
		return target.get_rect()
	if target is Polygon2D and not target.polygon.is_empty():
		var bounds := Rect2(target.polygon[0] + target.offset, Vector2.ZERO)
		for point: Vector2 in target.polygon:
			bounds = bounds.expand(point + target.offset)
		return bounds
	return local_bounds

func _redraw_layers() -> void:
	for child in get_children():
		if child is CanvasItem:
			child.queue_redraw()

static func _ease(value: float) -> float:
	return value * value * (3.0 - 2.0 * value)
