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
	if not expand_on_mouse_hover:
		return
	if _is_mouse_inside_side_bar():
		expand()
	else:
		collapse()


func _input(event: InputEvent) -> void:
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
	if toggle_input_action == &"":
		return
	if event.is_action_pressed(toggle_input_action):
		toggle()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
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
	set_process(expand_on_mouse_hover and is_inside_tree())


## 按需启用点击/按键输入处理
func _update_input_process() -> void:
	if not is_inside_tree():
		set_process_input(false)
		set_process_unhandled_input(false)
		return
	set_process_input(toggle_on_click)
	set_process_unhandled_input(toggle_input_action != &"")


func _on_toggle_button_pressed() -> void:
	toggle()


func _connect_toggle_button() -> void:
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
