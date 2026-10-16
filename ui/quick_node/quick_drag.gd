@tool
class_name QuickDrag
extends QuickUiAbility
## 拖动能力：支持宿主管理与独立装配，维护鼠标及触摸捕获并提交位置提议。
signal drag_down(vec: Vector2)
signal drag_started
signal drag_finished(cancelled: bool)
enum DragMode { FREE, HORIZONTAL_ONLY, VERTICAL_ONLY }
@export var dragged_ui: Control
@export var clickable_ui: Control
@export var placer: Node
@export var drag_mode: DragMode = DragMode.FREE
@export var auto_to_process_click := true
@export var use_axis_range_limit := false
@export var horizontal_range_min_offset := 0.0
@export var horizontal_range_max_offset := 0.0
@export var vertical_range_min_offset := 0.0
@export var vertical_range_max_offset := 0.0
@export_group("reset")
@export var is_reset_horizontal_max := true
@export var is_reset_horizontal_min := true
@export var is_reset_vertical_max := true
@export var is_reset_vertical_min := true
var horizontal_range_min := 0.0
var horizontal_range_max := 0.0
var vertical_range_min := 0.0
var vertical_range_max := 0.0
var is_draging := false
var _grab_pos_offset := Vector2.ZERO
var _grab_start_pos := Vector2.ZERO
var _grab_start_layout := Vector2.ZERO
var _proposal := Vector2.INF
var _pointer := -2 # -2 none; -1 mouse; >=0 touch index
var _click: Control
var _drag_target: Control
var _drag_parent: Node

func _init() -> void:
	proposal_priority = 100

func _ready() -> void:
	set_process_input(false)
	if not Engine.is_editor_hint() and not get_parent() is QuickUiAbilityHost:
		_refresh_click()

func _exit_tree() -> void:
	cancel_drag()
	_disconnect_click()
	super._exit_tree()

func _on_enabled_changed() -> void:
	if not enabled:
		cancel_drag()
		_disconnect_click()

func host_attach(host: Node, target: Control) -> void:
	super.host_attach(host, target)
	_refresh_click()

func host_detach() -> void:
	cancel_drag()
	_disconnect_click()
	super.host_detach()

func _target_ui() -> Control:
	if is_instance_valid(ability_host):
		return ability_target
	if get_parent() is QuickUiAbilityHost:
		return null # 托管目标由已挂载的宿主提供。
	if is_instance_valid(dragged_ui):
		return dragged_ui
	return get_parent() as Control

func _can_interact() -> bool:
	if not enabled or not is_inside_tree() or not can_process() or Engine.is_editor_hint():
		return false
	var target := _target_ui()
	if not is_instance_valid(target) or not target.is_inside_tree() or not target.is_visible_in_tree() or target.get_parent() is Container:
		return false
	if is_instance_valid(ability_host) and not ability_host._invalid_reason().is_empty():
		return false
	return true

func _refresh_click() -> void:
	var wanted: Control = null
	if _can_interact() and auto_to_process_click:
		wanted = clickable_ui if is_instance_valid(clickable_ui) else _target_ui()
	if wanted == _click:
		return
	cancel_drag()
	_disconnect_click()
	_click = wanted
	if is_instance_valid(_click):
		_click.gui_input.connect(_on_clickable_gui_input)

func _disconnect_click() -> void:
	if is_instance_valid(_click) and _click.gui_input.is_connected(_on_clickable_gui_input):
		_click.gui_input.disconnect(_on_clickable_gui_input)
	_click = null

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or get_parent() is QuickUiAbilityHost:
		return
	_refresh_click()
	_validate_capture()

func host_step(_delta: float) -> void:
	_refresh_click()
	_validate_capture()

func _validate_capture() -> void:
	if is_draging and (not _can_interact() or not is_instance_valid(_drag_target) or _drag_target != _target_ui() or _drag_target.get_parent() != _drag_parent):
		cancel_drag()

func _on_clickable_gui_input(event: InputEvent) -> void:
	if not _can_interact() or is_draging:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		begin_drag(_target_ui().get_canvas_transform().affine_inverse() * _click.get_global_transform_with_canvas() * event.position)
	elif event is InputEventScreenTouch and event.pressed:
		begin_drag(_target_ui().get_canvas_transform().affine_inverse() * _click.get_global_transform_with_canvas() * event.position, event.index)
	if is_draging and is_instance_valid(_click):
		_click.accept_event()

func begin_drag(press_global := Vector2.INF, pointer_index := -1) -> void:
	if is_draging or not _can_interact():
		return
	if is_instance_valid(ability_host) and not ability_host.can_begin_drag(self):
		return
	_drag_target = _target_ui()
	_drag_parent = _drag_target.get_parent()
	var point := press_global
	if point == Vector2.INF:
		point = _drag_target.get_global_mouse_position()
	if not point.is_finite():
		return
	_grab_start_layout = _drag_target.position
	_grab_start_pos = QuickUI.layout_to_global(_drag_target, _drag_target.position)
	_grab_pos_offset = _grab_start_pos - point
	_proposal = _grab_start_pos
	_pointer = pointer_index
	_reset_range()
	is_draging = true
	set_process_input(true)
	drag_started.emit()

func _reset_range() -> void:
	var target := _target_ui()
	if not is_instance_valid(target):
		return
	if is_reset_horizontal_min: horizontal_range_min = target.position.x + horizontal_range_min_offset
	if is_reset_horizontal_max: horizontal_range_max = target.position.x + horizontal_range_max_offset
	if is_reset_vertical_min: vertical_range_min = target.position.y + vertical_range_min_offset
	if is_reset_vertical_max: vertical_range_max = target.position.y + vertical_range_max_offset

func _input(event: InputEvent) -> void:
	_validate_capture()
	if not is_draging:
		return
	var owned_event: bool = (_pointer == -1 and ((event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT) or event is InputEventMouseMotion)) or (_pointer >= 0 and ((event is InputEventScreenTouch or event is InputEventScreenDrag) and event.index == _pointer))
	if owned_event: get_viewport().set_input_as_handled()
	if _pointer == -1:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_end_drag()
		elif event is InputEventMouseMotion:
			if not event.button_mask & MOUSE_BUTTON_MASK_LEFT:
				cancel_drag()
			else:
				_move_pointer(event.position)
	elif event is InputEventScreenTouch and event.index == _pointer and not event.pressed:
		_end_drag(event.canceled)
	elif event is InputEventScreenDrag and event.index == _pointer:
		_move_pointer(event.position)

func _move_pointer(viewport_position: Vector2) -> void:
	var canvas_position := _drag_target.get_canvas_transform().affine_inverse() * viewport_position
	_proposal = _apply_drag_constraints(canvas_position + _grab_pos_offset)
	_place_proposed(_proposal)

func propose_position(_delta: float) -> Vector2:
	return _proposal if is_draging else Vector2.INF

func _apply_drag_constraints(global_position: Vector2) -> Vector2:
	var target := _target_ui()
	if not is_instance_valid(target): return global_position
	var result := QuickUI.global_to_layout(target, global_position)
	if drag_mode == DragMode.HORIZONTAL_ONLY: result.y = _grab_start_layout.y
	if drag_mode == DragMode.VERTICAL_ONLY: result.x = _grab_start_layout.x
	if use_axis_range_limit:
		if drag_mode != DragMode.VERTICAL_ONLY:
			result.x = clampf(result.x, minf(horizontal_range_min, horizontal_range_max), maxf(horizontal_range_min, horizontal_range_max))
		if drag_mode != DragMode.HORIZONTAL_ONLY:
			result.y = clampf(result.y, minf(vertical_range_min, vertical_range_max), maxf(vertical_range_min, vertical_range_max))
	return QuickUI.layout_to_global(target, result)

func _place_proposed(proposed: Vector2) -> void:
	var target := _target_ui()
	if not is_instance_valid(target) or not _can_interact(): return
	if is_instance_valid(ability_host):
		ability_host.place(target, proposed, QuickUI.PlaceIntent.INTERACTIVE)
	elif is_instance_valid(placer) and placer.has_method("place"):
		placer.place(target, proposed, QuickUI.PlaceIntent.INTERACTIVE)
	else:
		target.position = QuickUI.global_to_layout(target, proposed)

func cancel_drag() -> void:
	_end_drag(true)

func _end_drag(cancelled := false) -> void:
	if not is_draging: return
	is_draging = false
	_pointer = -2
	_proposal = Vector2.INF
	set_process_input(false)
	var delta := Vector2.ZERO
	if is_instance_valid(_drag_target):
		delta = QuickUI.layout_to_global(_drag_target, _drag_target.position) - _grab_start_pos
	if is_instance_valid(ability_host): ability_host.drag_finished(cancelled)
	_drag_target = null
	_drag_parent = null
	drag_finished.emit(cancelled)
	if not cancelled: drag_down.emit(delta)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel_drag()
