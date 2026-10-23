@tool
class_name QuickUiOutsideClickTrigger
extends Node
## 将面板外的左键点击转换为信号，关闭状态与演出由场景接线拥有。
signal clicked

@export_node_path("Control") var panel_path := NodePath("..")
## 可接收空白点击的背景控件；其上的按钮和独立面板仍保持原生交互。
@export_node_path("Control") var background_path: NodePath
## 此控件可见时暂停检测，供上层面板独占外部关闭输入。
@export_node_path("Control") var blocked_by_path: NodePath
@export var enabled := true
@export var consume_event := true
@export_range(0.0, 32.0, 1.0) var drag_threshold := 7.0
## 最近一次有效点击的 Viewport 坐标，供领域接线进一步判断命中。
var click_position := Vector2.ZERO
var _pressed_outside := false
var _press_position := Vector2.ZERO

func _ready() -> void:
	set_process_input(not Engine.is_editor_hint())

func _input(event: InputEvent) -> void:
	if not enabled or not _available():
		_pressed_outside = false
		return
	if event is InputEventMouseMotion and _pressed_outside:
		if event.position.distance_to(_press_position) > drag_threshold:
			_pressed_outside = false
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_press_position = event.position
		_pressed_outside = _is_blank(event.position)
		return
	var dismiss: bool = _pressed_outside and event.position.distance_to(_press_position) <= drag_threshold and _is_blank(event.position)
	_pressed_outside = false
	if dismiss:
		click_position = event.position
		clicked.emit()
		if consume_event:
			get_viewport().set_input_as_handled()

func _available() -> bool:
	var panel := get_node_or_null(panel_path) as Control
	if panel == null or not panel.is_visible_in_tree():
		return false
	var blocker := get_node_or_null(blocked_by_path) as Control if not blocked_by_path.is_empty() else null
	return blocker == null or not blocker.is_visible_in_tree()

func _is_blank(point: Vector2) -> bool:
	var panel := get_node_or_null(panel_path) as Control
	if panel == null or Rect2(Vector2.ZERO, panel.size).has_point(panel.get_global_transform_with_canvas().affine_inverse() * point):
		return false
	var background := get_node_or_null(background_path) as Control if not background_path.is_empty() else null
	var hovered := get_viewport().gui_get_hovered_control()
	while hovered != null:
		if hovered is BaseButton:
			return false
		if hovered == background:
			return true
		if hovered.mouse_filter == Control.MOUSE_FILTER_STOP:
			return false
		hovered = hovered.get_parent_control()
	return true

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_EXIT_TREE:
		_pressed_outside = false
