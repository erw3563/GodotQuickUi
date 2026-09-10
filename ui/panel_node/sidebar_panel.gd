@tool
class_name SideBarPanel
extends PanelContainer
## 轻量抽屉侧边栏：负责贴边排布与展开/收起。

signal expanded_changed(is_expanded: bool)

enum Side {
	LEFT,
	TOP,
	RIGHT,
	BOTTOM,
}

@export_group("动画预览")
@export_tool_button("播放一次", "Play") var preview_play_action: Callable = preview_play
@export_tool_button("停止并恢复", "Stop") var preview_stop_action: Callable = preview_stop
@export_group("")

@export var side: SideBarPanel.Side:
	set(value):
		if side == value:
			return
		side = value
		_base_drawer_length = 0.0
		_apply_side_layout()
		_capture_base_drawer_length()
		_apply_drawer_offset(false)

@export_group("抽屉")
## 收起后仍留在屏幕内的长度（像素）
@export var collapsed_visible_length: float = 40.0:
	set(value):
		collapsed_visible_length = maxf(value, 0.0)
		_apply_drawer_offset(false)

## 沿贴边方向是否拉满（如底栏是否占满屏幕宽度）
@export var stretch_along_edge: bool = false:
	set(value):
		if stretch_along_edge == value:
			return
		stretch_along_edge = value
		_apply_side_layout()
		_apply_drawer_offset(false)

## 初始是否展开
@export var start_expanded: bool = true

## 展开/收起动画时长（秒）
@export_range(0.0, 2.0, 0.01) var animation_duration: float = 0.2

## 动画过渡类型
@export var animation_transition: Tween.TransitionType = Tween.TRANS_CUBIC

## 动画缓动类型
@export var animation_ease: Tween.EaseType = Tween.EASE_OUT

@export_group("交互")
## 用于切换的 InputMap 动作名（留空则不响应按键）
@export var toggle_input_action: StringName = &"":
	set(value):
		toggle_input_action = value
		_update_input_process()

## 可选：绑定按钮进行切换
@export var toggle_button: BaseButton:
	set(value):
		_disconnect_toggle_button()
		toggle_button = value
		_connect_toggle_button()

## 鼠标悬停时展开，离开时收起
@export var expand_on_mouse_hover: bool = false:
	set(value):
		expand_on_mouse_hover = value
		_update_hover_process()

## 点击切换：收起时点侧边栏（含子控件）展开；展开时点栏内空白或栏外空白区域收起
@export var toggle_on_click: bool = false:
	set(value):
		toggle_on_click = value
		_update_input_process()

## 当前是否展开
var is_expanded: bool = true:
	set(value):
		if is_expanded == value:
			return
		is_expanded = value
		if not Engine.is_editor_hint():
			expanded_changed.emit(is_expanded)
		_apply_drawer_offset(true)

var _drawer_tween: Tween
var _is_ready: bool = false
## 防止设置 offset 触发 resized 时重入
var _is_applying_drawer_offset: bool = false
## 展开时的稳定抽屉长度，避免半更新 size 造成长度失控
var _base_drawer_length: float = 0.0
## 鼠标是否仍在窗口客户区内
var _is_pointer_in_window: bool = true


func _ready() -> void:
	if Engine.is_editor_hint():
		_update_input_process()
		return
	_is_ready = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	is_expanded = start_expanded
	_apply_side_layout()
	_connect_toggle_button()
	_connect_window_mouse_tracking()
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)
	_update_hover_process()
	_update_input_process()
	# 等布局稳定后再采样长度并对齐偏移
	call_deferred("_initialize_drawer_state")


func _exit_tree() -> void:
	preview_stop()
	_disconnect_toggle_button()
	_disconnect_window_mouse_tracking()
	_kill_drawer_tween()


#region 公开接口

## 切换展开/收起
func toggle() -> void:
	is_expanded = not is_expanded


## 展开侧边栏
func expand() -> void:
	is_expanded = true


## 收起侧边栏
func collapse() -> void:
	is_expanded = false


## 沿抽屉方向的内容长度（即最大拉出长度）
func get_drawer_length() -> float:
	return maxf(_base_drawer_length, _get_minimum_drawer_length())

#endregion


#region 交互输入

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not expand_on_mouse_hover:
		return
	if _is_mouse_inside_side_bar():
		expand()
	else:
		collapse()


func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if not toggle_on_click:
		return
	if not (event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if is_expanded:
		if _should_collapse_from_outside_click():
			collapse()
			get_viewport().set_input_as_handled()
		return
	if _is_mouse_inside_side_bar():
		expand()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if toggle_input_action == &"":
		return
	if event.is_action_pressed(toggle_input_action):
		toggle()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if not toggle_on_click or not is_expanded:
		return
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		collapse()
		accept_event()


## 是否为「栏外空白」点击（外部切换按钮等交互控件除外）
func _should_collapse_from_outside_click() -> bool:
	if _is_mouse_inside_side_bar():
		return false
	var hovered_control := get_viewport().gui_get_hovered_control()
	if hovered_control == null:
		return true
	# 点在本侧边栏内（含子控件）时不收起
	if hovered_control == self or is_ancestor_of(hovered_control):
		return false
	# 外部切换按钮交给按钮自己处理，避免先收起再被 toggle 拉开
	if toggle_button != null and (
			hovered_control == toggle_button \
			or toggle_button.is_ancestor_of(hovered_control)):
		return false
	# 其它外部按钮视为非空白，不抢点击
	if hovered_control is BaseButton:
		return false
	return true


## 鼠标是否在本侧边栏的视口可见范围内（含全部子控件）
func _is_mouse_inside_side_bar() -> bool:
	if not is_inside_tree() or not is_visible_in_tree():
		return false
	# 系统标题栏属于非客户区：离开客户区后不能把抽屉滑出屏幕的部分当成悬停
	if not _is_pointer_in_window:
		return false
	var mouse_pos := get_global_mouse_position()
	var viewport_rect := _get_viewport_content_rect()
	if not viewport_rect.has_point(mouse_pos):
		return false
	var visible_bar_rect := get_global_rect().intersection(viewport_rect)
	if visible_bar_rect.size.x <= 0.0 or visible_bar_rect.size.y <= 0.0:
		return false
	return visible_bar_rect.has_point(mouse_pos)


## 视口客户区矩形（与 Control 全局坐标同一空间，不含系统标题栏）
func _get_viewport_content_rect() -> Rect2:
	var viewport := get_viewport()
	if viewport == null:
		return Rect2()
	return viewport.get_visible_rect()


func _connect_window_mouse_tracking() -> void:
	if Engine.is_editor_hint():
		return
	if not is_inside_tree():
		return
	var window := get_window()
	if window == null:
		return
	if not window.mouse_entered.is_connected(_on_window_mouse_entered):
		window.mouse_entered.connect(_on_window_mouse_entered)
	if not window.mouse_exited.is_connected(_on_window_mouse_exited):
		window.mouse_exited.connect(_on_window_mouse_exited)
	_is_pointer_in_window = true


func _disconnect_window_mouse_tracking() -> void:
	if not is_inside_tree():
		return
	var window := get_window()
	if window == null:
		return
	if window.mouse_entered.is_connected(_on_window_mouse_entered):
		window.mouse_entered.disconnect(_on_window_mouse_entered)
	if window.mouse_exited.is_connected(_on_window_mouse_exited):
		window.mouse_exited.disconnect(_on_window_mouse_exited)


func _on_window_mouse_entered() -> void:
	_is_pointer_in_window = true


func _on_window_mouse_exited() -> void:
	_is_pointer_in_window = false


## 仅在开启悬停展开时启用每帧检测
func _update_hover_process() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		return
	set_process(expand_on_mouse_hover and is_inside_tree())


## 按需启用点击/按键输入处理
func _update_input_process() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		return
	if not is_inside_tree():
		set_process_input(false)
		set_process_unhandled_input(false)
		return
	set_process_input(toggle_on_click)
	set_process_unhandled_input(toggle_input_action != &"")


func _on_toggle_button_pressed() -> void:
	toggle()


func _connect_toggle_button() -> void:
	if Engine.is_editor_hint():
		return
	if toggle_button == null:
		return
	if not toggle_button.pressed.is_connected(_on_toggle_button_pressed):
		toggle_button.pressed.connect(_on_toggle_button_pressed)


func _disconnect_toggle_button() -> void:
	if toggle_button == null:
		return
	if toggle_button.pressed.is_connected(_on_toggle_button_pressed):
		toggle_button.pressed.disconnect(_on_toggle_button_pressed)

#endregion


#region 抽屉布局与动画

func _initialize_drawer_state() -> void:
	_capture_base_drawer_length()
	_apply_drawer_offset(false)


func _get_minimum_drawer_length() -> float:
	var minimum_size := get_combined_minimum_size()
	match side:
		Side.LEFT, Side.RIGHT:
			return maxf(minimum_size.x, custom_minimum_size.x)
		Side.TOP, Side.BOTTOM:
			return maxf(minimum_size.y, custom_minimum_size.y)
	return 0.0


## 在稳定布局下采样抽屉长度；不在重入期间调用 size，避免半更新尺寸
func _capture_base_drawer_length() -> void:
	if Engine.is_editor_hint() and not is_previewing():
		return
	if not is_inside_tree() or _is_applying_drawer_offset:
		return
	var minimum_length := _get_minimum_drawer_length()
	var current_length := 0.0
	match side:
		Side.LEFT, Side.RIGHT:
			current_length = size.x
		Side.TOP, Side.BOTTOM:
			current_length = size.y
	_base_drawer_length = maxf(minimum_length, current_length)


func _on_resized() -> void:
	if Engine.is_editor_hint() and not is_previewing():
		return
	if _is_applying_drawer_offset:
		return
	if _drawer_tween != null and _drawer_tween.is_running():
		return
	# 仅在展开且布局稳定时刷新基准长度
	if is_expanded:
		_capture_base_drawer_length()
	_apply_drawer_offset(false)


## 按所在边设置抽屉轴锚点；另一轴保留场景中的相对位置
func _apply_side_layout() -> void:
	if Engine.is_editor_hint() and not is_previewing():
		return
	if not _is_ready and not is_inside_tree():
		return
	match side:
		Side.LEFT:
			anchor_left = 0.0
			anchor_right = 0.0
			grow_horizontal = Control.GROW_DIRECTION_END
			if stretch_along_edge:
				anchor_top = 0.0
				anchor_bottom = 1.0
				offset_top = 0.0
				offset_bottom = 0.0
				grow_vertical = Control.GROW_DIRECTION_BOTH
		Side.RIGHT:
			anchor_left = 1.0
			anchor_right = 1.0
			grow_horizontal = Control.GROW_DIRECTION_BEGIN
			if stretch_along_edge:
				anchor_top = 0.0
				anchor_bottom = 1.0
				offset_top = 0.0
				offset_bottom = 0.0
				grow_vertical = Control.GROW_DIRECTION_BOTH
		Side.TOP:
			anchor_top = 0.0
			anchor_bottom = 0.0
			grow_vertical = Control.GROW_DIRECTION_END
			if stretch_along_edge:
				anchor_left = 0.0
				anchor_right = 1.0
				offset_left = 0.0
				offset_right = 0.0
				grow_horizontal = Control.GROW_DIRECTION_BOTH
		Side.BOTTOM:
			anchor_top = 1.0
			anchor_bottom = 1.0
			grow_vertical = Control.GROW_DIRECTION_BEGIN
			if stretch_along_edge:
				anchor_left = 0.0
				anchor_right = 1.0
				offset_left = 0.0
				offset_right = 0.0
				grow_horizontal = Control.GROW_DIRECTION_BOTH


## 根据展开状态计算偏移：展开时外边缘贴边；收起时滑出，仅保留可见长度
func _apply_drawer_offset(animate: bool) -> void:
	if Engine.is_editor_hint() and not is_previewing():
		return
	if not is_inside_tree() or _is_applying_drawer_offset:
		return
	var drawer_length := get_drawer_length()
	if drawer_length <= 0.0:
		return
	var peek_length := minf(collapsed_visible_length, drawer_length)
	# 收起时需要滑出屏幕的距离；展开时为 0，保证外边缘不露在屏幕内侧
	var slide_distance := 0.0 if is_expanded else (drawer_length - peek_length)
	var target_offsets := _build_target_offsets(drawer_length, slide_distance)
	if animate and animation_duration > 0.0 and _is_ready:
		_animate_offsets(target_offsets)
	else:
		_kill_drawer_tween()
		_set_offsets(target_offsets)


## 只改抽屉轴偏移，另一轴沿用当前（场景）相对位置
func _build_target_offsets(drawer_length: float, slide_distance: float) -> Dictionary:
	var result := {
		"left": offset_left,
		"right": offset_right,
		"top": offset_top,
		"bottom": offset_bottom,
	}
	match side:
		Side.LEFT:
			result["left"] = -slide_distance
			result["right"] = drawer_length - slide_distance
		Side.RIGHT:
			result["left"] = -drawer_length + slide_distance
			result["right"] = slide_distance
		Side.TOP:
			result["top"] = -slide_distance
			result["bottom"] = drawer_length - slide_distance
		Side.BOTTOM:
			result["top"] = -drawer_length + slide_distance
			result["bottom"] = slide_distance
	return result


func _set_offsets(offsets: Dictionary) -> void:
	_is_applying_drawer_offset = true
	if not is_equal_approx(offset_left, offsets["left"]):
		offset_left = offsets["left"]
	if not is_equal_approx(offset_right, offsets["right"]):
		offset_right = offsets["right"]
	if not is_equal_approx(offset_top, offsets["top"]):
		offset_top = offsets["top"]
	if not is_equal_approx(offset_bottom, offsets["bottom"]):
		offset_bottom = offsets["bottom"]
	_is_applying_drawer_offset = false


func _animate_offsets(target_offsets: Dictionary) -> void:
	_kill_drawer_tween()
	_drawer_tween = create_tween()
	_drawer_tween.set_parallel(true)
	_drawer_tween.set_trans(animation_transition)
	_drawer_tween.set_ease(animation_ease)
	_drawer_tween.tween_property(self, "offset_left", target_offsets["left"], animation_duration)
	_drawer_tween.tween_property(self, "offset_right", target_offsets["right"], animation_duration)
	_drawer_tween.tween_property(self, "offset_top", target_offsets["top"], animation_duration)
	_drawer_tween.tween_property(self, "offset_bottom", target_offsets["bottom"], animation_duration)


func _kill_drawer_tween() -> void:
	if _drawer_tween != null and _drawer_tween.is_valid():
		_drawer_tween.kill()
	_drawer_tween = null

#endregion


#region 编辑器单次预览

const _PREVIEW_GEOMETRY: Array[StringName] = [
	&"layout_mode", &"grow_horizontal", &"grow_vertical",
	&"anchor_left", &"anchor_top", &"anchor_right", &"anchor_bottom",
	&"offset_left", &"offset_top", &"offset_right", &"offset_bottom",
]
const _PREVIEW_PRESENTATION: Array[StringName] = [
	&"custom_minimum_size", &"size_flags_horizontal", &"size_flags_vertical",
	&"clip_contents", &"mouse_filter", &"visible", &"modulate",
	&"pivot_offset", &"scale", &"rotation",
]
var _preview_active: bool = false
var _preview_generation: int = 0
var _preview_snapshots: Array[Dictionary] = []


func _preview_begin(properties: Array[StringName], capture_children: bool = false) -> bool:
	if not Engine.is_editor_hint() or not self.is_inside_tree():
		return false
	var parent := self.get_parent_control()
	if parent != null and not parent.is_visible_in_tree():
		push_warning("动画预览：请先显示面板的父控件。")
		return false
	if self.size.x <= 0.0 or self.size.y <= 0.0:
		push_warning("动画预览：面板尚无有效尺寸。")
		return false
	_preview_generation += 1
	_preview_snapshots.clear()
	_preview_capture(self, properties)
	if capture_children:
		_preview_capture_children(self)
	_preview_active = true
	return true


func _preview_capture(node: Object, properties: Array[StringName]) -> void:
	var values: Dictionary = {}
	for property in properties:
		var value: Variant = node.get(property)
		values[property] = value.duplicate() if value is Array or value is Dictionary else value
	_preview_snapshots.append({"node": weakref(node), "values": values})


func _preview_capture_children(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			_preview_capture(child, _PREVIEW_PRESENTATION + _PREVIEW_GEOMETRY)
		_preview_capture_children(child)


func _preview_restore() -> void:
	_preview_active = false
	_preview_generation += 1
	var snapshots := _preview_snapshots
	_preview_snapshots = []
	# 内部状态由调用方列在几何前；子控件先恢复可见性/最小尺寸，再恢复矩形。
	for snapshot in snapshots:
		var node: Object = snapshot.node.get_ref()
		if not is_instance_valid(node):
			continue
		for property in snapshot.values:
			if property not in _PREVIEW_GEOMETRY:
				node.set(property, snapshot.values[property])
		if node is Control:
			node.update_minimum_size()
	for snapshot in snapshots:
		var node: Object = snapshot.node.get_ref()
		if not is_instance_valid(node):
			continue
		for property in _PREVIEW_GEOMETRY:
			if snapshot.values.has(property):
				node.set(property, snapshot.values[property])


func _preview_is_current(token: int) -> bool:
	return _preview_active and token == _preview_generation


## Tween 被 kill 不发 finished；逐帧检查代次避免悬挂协程。超时返回 false，由面板恢复。
func _preview_wait_tween(tween: Tween, token: int, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(maxf(timeout, 0.1) * 1000.0)
	while _preview_is_current(token) and is_instance_valid(self) and self.is_inside_tree():
		if tween == null or not tween.is_valid() or not tween.is_running():
			return true
		if Time.get_ticks_msec() >= deadline:
			push_warning("动画预览等待超时，已停止并恢复。")
			return false
		await self.get_tree().process_frame
	return false


func _preview_wait_seconds(seconds: float, token: int) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while _preview_is_current(token) and is_instance_valid(self) and self.is_inside_tree():
		if Time.get_ticks_msec() >= deadline:
			return true
		await self.get_tree().process_frame
	return false


## 仅在编辑器播放；再次点击从原编辑状态重新开始。
func preview_play() -> void:
	if not Engine.is_editor_hint():
		return
	preview_stop()
	var properties: Array[StringName] = [&"_is_ready", &"_base_drawer_length", &"is_expanded"]
	properties.append_array(_PREVIEW_PRESENTATION)
	properties.append_array(_PREVIEW_GEOMETRY)
	if not _preview_begin(properties, true):
		return
	_preview_run(_preview_generation)


func is_previewing() -> bool:
	return _preview_active


## 保存前和退出树同步恢复；不依赖 Inspector 选择或插件生命周期。
func preview_stop() -> void:
	if not is_previewing():
		return
	_preview_active = false
	_kill_drawer_tween()
	_preview_restore()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		preview_stop()


func _preview_run(token: int) -> void:
	# 等当前布局帧完成；停止或重播后旧轮不能再初始化。
	await get_tree().process_frame
	if not _preview_is_current(token) or not is_inside_tree():
		return
	visible = true
	_is_ready = true
	_capture_base_drawer_length()
	_apply_side_layout()
	is_expanded = false
	_apply_drawer_offset(false)
	expand()
	if await _preview_wait_tween(_drawer_tween, token, animation_duration + 2.0):
		if await _preview_wait_seconds(0.2, token):
			collapse()
			await _preview_wait_tween(_drawer_tween, token, animation_duration + 2.0)
	if _preview_is_current(token):
		preview_stop()

#endregion
