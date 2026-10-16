@tool
class_name QuickPointerPull
extends Node
## 鼠标牵引演出：采样指针方向，推动内层视觉控件并阻尼归位，固定检测层负责输入。

signal play_finished
signal play_cancelled

@export var ui: Control:
	set(value):
		if ui == value:
			return
		ui = value
		interrupt()
@export var detector: Control:
	set(value):
		if detector == value:
			return
		detector = value
		interrupt()
@export_range(0.0, 200.0, 0.5) var displacement: float = 24.0:
	set(value):
		displacement = clampf(value, 0.0, 200.0) if is_finite(value) else 0.0
@export_range(0.0, 2.0, 0.01) var outward_duration: float = 0.12:
	set(value):
		outward_duration = clampf(value, 0.0, 2.0) if is_finite(value) else 0.0
@export_range(0.0, 4.0, 0.01) var return_duration: float = 0.52:
	set(value):
		return_duration = clampf(value, 0.0, 4.0) if is_finite(value) else 0.0
@export_range(0.0, 5.0, 0.05) var spring_feel: float = 1.5:
	set(value):
		spring_feel = clampf(value, 0.0, 5.0) if is_finite(value) else 0.0

var is_playing: bool:
	get:
		return _playing
var current_offset: Vector2:
	get:
		return _last_written - _baseline if _playing else Vector2.ZERO
var _playing := false
var _target: Control
var _detector: Control
var _owned_parent: Node
var _baseline := Vector2.ZERO
var _last_written := Vector2.ZERO
var _screen_pull := Vector2.ZERO
var _generation := 0
var _elapsed := 0.0
var _outward := 0.0
var _return := 0.0
var _spring := 0.0
var _host_preview_active := false
static var _owners: Dictionary = {}

func _ready() -> void:
	set_process(false)

func _exit_tree() -> void:
	interrupt()

func get_playback_duration() -> float:
	return maxf(outward_duration, 0.0) + maxf(return_duration, 0.0)

func play() -> bool:
	if not is_inside_tree() or (Engine.is_editor_hint() and not _host_preview_active):
		return false
	_generation += 1
	var request_token := _generation
	_finish(true, false)
	if request_token != _generation:
		return false
	if not is_instance_valid(ui) or not ui.is_inside_tree() or not ui.is_visible_in_tree():
		return false
	var outer := detector
	if not is_instance_valid(outer):
		outer = ui.get_parent() as Control
	if not is_instance_valid(outer) or outer == ui or not outer.is_ancestor_of(ui):
		return false
	if not outer.is_visible_in_tree() or ui.get_parent() is Container or outer.get_viewport() != ui.get_viewport():
		return false
	var target := ui
	var previous_ref: WeakRef = _owners.get(target.get_instance_id())
	if previous_ref != null:
		var previous = previous_ref.get_ref()
		if is_instance_valid(previous):
			previous.interrupt()
	if request_token != _generation or not is_instance_valid(target) or target != ui or not target.is_inside_tree() or _owners.has(target.get_instance_id()):
		return false
	var transform := outer.get_global_transform_with_canvas()
	var center := transform * (outer.size * 0.5)
	var delta := _pointer_viewport_position() - center
	if not target.position.is_finite() or not delta.is_finite() or delta.length_squared() < 0.000001 or displacement <= 0.0:
		return false
	_target = target
	_owned_parent = target.get_parent()
	_detector = outer
	_baseline = target.position
	_last_written = _baseline
	_screen_pull = delta.normalized() * maxf(displacement, 0.0)
	_elapsed = 0.0
	_outward = maxf(outward_duration, 0.0)
	_return = maxf(return_duration, 0.0)
	_spring = clampf(spring_feel, 0.0, 5.0)
	_playing = true
	_owners[target.get_instance_id()] = weakref(self)
	_target.tree_exiting.connect(interrupt)
	_target.visibility_changed.connect(_check_visibility)
	_detector.tree_exiting.connect(interrupt)
	_detector.visibility_changed.connect(_check_visibility)
	if _outward + _return <= 0.0:
		_finish(false)
		return true
	set_process(true)
	if _outward <= 0.0:
		_apply_amount(1.0)
	return true

func _pointer_viewport_position() -> Vector2:
	return ui.get_viewport().get_mouse_position()

func _process(delta: float) -> void:
	if not is_playing:
		return
	if not is_instance_valid(_target) or not is_instance_valid(_detector) or not _target.is_inside_tree() or not _detector.is_inside_tree() or not _target.is_visible_in_tree() or not _detector.is_visible_in_tree() or not _detector.is_ancestor_of(_target) or _target.get_parent() != _owned_parent or _target.get_parent() is Container:
		interrupt()
		return
	_elapsed += maxf(delta, 0.0) if is_finite(delta) else 0.0
	if _elapsed >= _outward + _return:
		_finish(false)
		return
	var amount: float
	if _outward > 0.0 and _elapsed < _outward:
		var t := _elapsed / _outward
		amount = t * t * (3.0 - 2.0 * t)
	else:
		var t := clampf((_elapsed - _outward) / maxf(_return, 0.000001), 0.0, 1.0)
		amount = pow(1.0 - t, 3.0) * cos(TAU * _spring * t)
	_apply_amount(amount)

func _apply_amount(amount: float) -> void:
	if not is_instance_valid(_target):
		return
	if not _target.position.is_equal_approx(_last_written):
		_baseline = _target.position
	var parent_transform := _target.get_canvas_transform()
	var parent_item := _target.get_parent() as CanvasItem
	if not _target.is_set_as_top_level() and parent_item != null:
		parent_transform = parent_item.get_global_transform_with_canvas()
	if not parent_transform.is_finite() or absf(parent_transform.determinant()) < 0.000001:
		interrupt()
		return
	var inverse := parent_transform.affine_inverse()
	var local_offset := inverse.basis_xform(_screen_pull * clampf(amount, -1.0, 1.0))
	_last_written = _baseline + local_offset
	_target.position = _last_written

func _check_visibility() -> void:
	if is_playing and (not is_instance_valid(_target) or not _target.is_visible_in_tree() or not is_instance_valid(_detector) or not _detector.is_visible_in_tree()):
		interrupt()

func interrupt() -> void:
	_generation += 1
	_finish(true)

func _finish(cancelled: bool, notify: bool = true) -> void:
	if not is_playing:
		return
	_playing = false
	set_process(false)
	var generation := _generation
	var target := _target
	var outer := _detector
	var owned_parent := _owned_parent
	_owned_parent = null
	_target = null
	_detector = null
	if is_instance_valid(target):
		var owner_ref: WeakRef = _owners.get(target.get_instance_id())
		if owner_ref != null and owner_ref.get_ref() == self:
			_owners.erase(target.get_instance_id())
		if target.tree_exiting.is_connected(interrupt):
			target.tree_exiting.disconnect(interrupt)
		if target.visibility_changed.is_connected(_check_visibility):
			target.visibility_changed.disconnect(_check_visibility)
	if is_instance_valid(outer):
		if outer.tree_exiting.is_connected(interrupt):
			outer.tree_exiting.disconnect(interrupt)
		if outer.visibility_changed.is_connected(_check_visibility):
			outer.visibility_changed.disconnect(_check_visibility)
	if is_instance_valid(target) and target.get_parent() == owned_parent and target.position.is_equal_approx(_last_written):
		target.position = _baseline
	if not notify or generation != _generation:
		return
	if cancelled:
		play_cancelled.emit()
	else:
		play_finished.emit()

func _begin_host_preview_session() -> void:
	_host_preview_active = true

func _end_host_preview_session() -> void:
	interrupt()
	_host_preview_active = false
