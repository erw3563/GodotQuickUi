class_name FloatingPanel
extends PanelContainer
## 可拖拽浮动面板基类：标题栏拖动、X 按钮隐藏、点击面板外空白隐藏。

signal panel_shown
signal panel_hidden

@export var panel_title: String = "":
	set(value):
		panel_title = value
		_apply_panel_title()
@export var title_label: Label
@export var close_button: Button
@export var drag_handle: Control
## 是否允许拖拽标题栏移动面板。
@export var draggable: bool = true
## 点击面板外空白区域时是否自动隐藏。
@export var hide_on_outside_click: bool = true
## 点击其它可交互控件（按钮等）时是否忽略外部点击隐藏。
@export var ignore_interactive_controls_on_outside_click: bool = true
## 可选缩放宿主（ZoomPanel）：设置后显隐缩放动画交给宿主承载，
## 拖拽与视口夹紧也改作用于宿主；面板自身保持 visible，随宿主整体显隐。
var zoom_host: ZoomPanel = null:
	set(value):
		zoom_host = value
		if zoom_host != null:
			# 托管模式下自身必须保持可见：隐藏子项会被容器跳过最小尺寸
			# 计算与排布，宿主将量不到内容尺寸、定位错乱。
			show()

var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	_resolve_panel_nodes()
	_connect_panel_signals()
	_apply_panel_title()
	_update_outside_click_input()


## 显示面板（有缩放宿主时由宿主播放入场动画）。
func show_panel() -> void:
	show()
	if zoom_host != null:
		zoom_host.expand()
	_update_outside_click_input()
	panel_shown.emit()


## 隐藏面板，子类可覆写 _on_panel_hidden 做额外清理。
## 有缩放宿主时自身保持 visible，由宿主收起动画结束后整体隐藏。
func hide_panel() -> void:
	if zoom_host != null:
		zoom_host.collapse()
	else:
		hide()
	_is_dragging = false
	_update_outside_click_input()
	_on_panel_hidden()
	panel_hidden.emit()


## 位置操作目标：面板在宿主容器内无法自定位，设宿主后统一移动宿主。
func _position_target() -> Control:
	if zoom_host != null:
		return zoom_host
	return self


## 子类在面板隐藏时可覆写此方法。
func _on_panel_hidden() -> void:
	pass


## 解析标题、关闭按钮与拖拽区域节点。
func _resolve_panel_nodes() -> void:
	if title_label == null:
		title_label = get_node_or_null("VBoxContainer/TitleBar/TitleLabel") as Label
	if close_button == null:
		close_button = get_node_or_null("VBoxContainer/TitleBar/CloseButton") as Button
	if drag_handle == null:
		drag_handle = get_node_or_null("VBoxContainer/TitleBar") as Control


## 连接关闭按钮与拖拽区域输入。
func _connect_panel_signals() -> void:
	if close_button and not close_button.pressed.is_connected(_on_close_button_pressed):
		close_button.pressed.connect(_on_close_button_pressed)
	if drag_handle and not drag_handle.gui_input.is_connected(_on_drag_handle_gui_input):
		drag_handle.gui_input.connect(_on_drag_handle_gui_input)
		drag_handle.mouse_filter = Control.MOUSE_FILTER_STOP


## 同步标题文本。
func _apply_panel_title() -> void:
	if title_label:
		title_label.text = panel_title


## 根据可见性与配置开关外部点击监听。
func _update_outside_click_input() -> void:
	if not is_inside_tree():
		return
	set_process_input(hide_on_outside_click and is_visible_in_tree())


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_update_outside_click_input()


func _input(event: InputEvent) -> void:
	if not hide_on_outside_click or not is_visible_in_tree():
		return
	if not (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		return
	if _should_hide_from_outside_click():
		hide_panel()
		get_viewport().set_input_as_handled()


## 关闭按钮：隐藏面板。
func _on_close_button_pressed() -> void:
	hide_panel()


## 标题栏左键拖拽整个面板（有宿主时拖动宿主）。
func _on_drag_handle_gui_input(event: InputEvent) -> void:
	if not draggable:
		return
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_is_dragging = true
			_drag_offset = _position_target().global_position - get_global_mouse_position()
		else:
			_is_dragging = false
		accept_event()
	elif event is InputEventMouseMotion and _is_dragging:
		_position_target().global_position = get_global_mouse_position() + _drag_offset
		_clamp_to_viewport()
		accept_event()


## 是否为面板外空白点击（避免误触其它按钮或背包控件）。
func _should_hide_from_outside_click() -> bool:
	if _is_mouse_inside_panel():
		return false
	var hovered_control := get_viewport().gui_get_hovered_control()
	if hovered_control == null:
		return true
	if hovered_control == self or is_ancestor_of(hovered_control):
		return false
	if ignore_interactive_controls_on_outside_click:
		if hovered_control is BaseButton:
			return false
		if hovered_control.mouse_filter == Control.MOUSE_FILTER_STOP:
			return false
	return true


## 鼠标是否在本面板可见范围内。
func _is_mouse_inside_panel() -> bool:
	if not is_inside_tree() or not is_visible_in_tree():
		return false
	return get_global_rect().has_point(get_global_mouse_position())


## 将面板（或其缩放宿主）限制在当前视口范围内。
func _clamp_to_viewport() -> void:
	var viewport_rect := get_viewport_rect()
	var target := _position_target()
	var panel_size := target.size
	if panel_size.x <= 0.0 or panel_size.y <= 0.0:
		panel_size = target.get_combined_minimum_size()
	var max_position_x := maxf(
		viewport_rect.position.x,
		viewport_rect.end.x - panel_size.x
	)
	var max_position_y := maxf(
		viewport_rect.position.y,
		viewport_rect.end.y - panel_size.y
	)
	target.global_position = Vector2(
		clampf(target.global_position.x, viewport_rect.position.x, max_position_x),
		clampf(target.global_position.y, viewport_rect.position.y, max_position_y)
	)
