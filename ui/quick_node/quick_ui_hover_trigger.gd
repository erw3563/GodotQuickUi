@tool
class_name QuickUiHoverTrigger
extends Node
## 显式 Control 区域的悬停传感器，通过 entered / exited 连接零参数动作。
## 固定区域可包含参与缩放的按钮；检测使用区域局部矩形和原生 GUI 遮挡。

signal entered
signal exited

## 显式检测区域，与传感器处于同一 Viewport。
@export var region: Control:
	set(value):
		if region == value:
			return
		region = value
		reset_hover()
		_update_processing()
## 关闭时同步清除悬停状态，由 exited 信号驱动连接的恢复动作。
@export var enabled := true:
	set(value):
		enabled = value
		if not enabled:
			reset_hover()
		_update_processing()
## 区域局部空间的左、上、右、下扩展量；负数收缩检测矩形。
## 按钮点击范围由原生按钮几何定义，固定区域尺寸可覆盖放大后的按钮。
@export var margins := Vector4.ZERO
## 通过原生 GUI 命中关系判断区域与鼠标输入覆盖层的前后关系。
@export var respect_occlusion := true

var is_hovered: bool = false
var _pointer := Vector2.ZERO
var _pointer_in_window := true
var _leaving_tree := false
var _refreshing := false
var _exit_window: Window

func _enter_tree() -> void:
	_leaving_tree = false
	_pointer_in_window = true
	var viewport := get_viewport()
	_pointer = viewport.get_mouse_position()
	_exit_window = viewport as Window
	if not Engine.is_editor_hint() and is_instance_valid(_exit_window):
		if not _exit_window.mouse_exited.is_connected(_on_viewport_mouse_exited):
			_exit_window.mouse_exited.connect(_on_viewport_mouse_exited)
	_update_processing()

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_pointer = event.position
		_pointer_in_window = true

func _on_viewport_mouse_exited() -> void:
	_pointer_in_window = false
	reset_hover()

func _exit_tree() -> void:
	_leaving_tree = true
	set_process(false)
	if is_instance_valid(_exit_window) and _exit_window.mouse_exited.is_connected(_on_viewport_mouse_exited):
		_exit_window.mouse_exited.disconnect(_on_viewport_mouse_exited)
	_exit_window = null
	reset_hover()

func _update_processing() -> void:
	set_process(not Engine.is_editor_hint() and enabled and is_inside_tree() and not _leaving_tree)

## 同步清空悬停状态，后续帧根据区域与指针状态重新检测。
func reset_hover() -> void:
	# 清空过程持有重入守卫，退出回调完成后由后续帧重新检测。
	var was_refreshing := _refreshing
	_refreshing = true
	_set_hovered(false)
	_refreshing = was_refreshing

func _set_hovered(value: bool) -> void:
	if value == is_hovered:
		return
	is_hovered = value
	if value:
		entered.emit()
	else:
		exited.emit()

func _process(_delta: float) -> void:
	refresh()

## 立即重算布局、显隐、输入或区域变化后的状态；常规使用由逐帧处理驱动。
func refresh() -> void:
	if Engine.is_editor_hint() or _refreshing:
		return
	_refreshing = true
	# 显示窗口以原生指针位置为权威；headless 视口消费注入的输入事件。
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		_pointer = get_viewport().get_mouse_position()
	_set_hovered(_contains_pointer())
	_refreshing = false

func _contains_pointer() -> bool:
	var target := region
	if not is_instance_valid(target) or not _geometry_contains_pointer(target):
		return false
	if not respect_occlusion:
		return true
	var viewport := target.get_viewport()
	# 显示窗口先刷新原生 GUI 指针命中状态。
	if DisplayServer.get_name() != "headless":
		viewport.update_mouse_cursor_state()
	# 原生命中通知可同步修改区域、启用状态与树归属，刷新后重新验证几何条件。
	if not is_instance_valid(target) or not _geometry_contains_pointer(target):
		return false
	if not respect_occlusion:
		return true
	var hovered := viewport.gui_get_hovered_control()
	if not is_instance_valid(hovered):
		return false
	return hovered == target or target.is_ancestor_of(hovered) or hovered.is_ancestor_of(target)

func _geometry_contains_pointer(target: Control) -> bool:
	if not enabled or _leaving_tree or not is_inside_tree() or not is_instance_valid(target) or target != region:
		return false
	if target.is_queued_for_deletion() or not target.is_inside_tree() or not target.is_visible_in_tree():
		return false
	var viewport := target.get_viewport()
	if viewport != get_viewport():
		return false
	if not _pointer_in_window:
		return false
	var point := _pointer
	if not viewport.get_visible_rect().has_point(point):
		return false
	var transform := target.get_global_transform_with_canvas()
	if absf(transform.determinant()) < 0.000001:
		return false
	var local := transform.affine_inverse() * point
	var bounds := Rect2(Vector2(-margins.x, -margins.y), target.size + Vector2(margins.x + margins.z, margins.y + margins.w))
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or not bounds.has_point(local):
		return false
	# 祖先 Control 的裁剪矩形共同限制指针命中范围。
	var ancestor := target.get_parent()
	while ancestor != null:
		if ancestor is Control and ancestor.clip_contents:
			var clip_transform: Transform2D = ancestor.get_global_transform_with_canvas()
			if absf(clip_transform.determinant()) < 0.000001 or not Rect2(Vector2.ZERO, ancestor.size).has_point(clip_transform.affine_inverse() * point):
				return false
		ancestor = ancestor.get_parent()
	return true
