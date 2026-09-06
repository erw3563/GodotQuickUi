class_name PocketDrawerPanel
extends PanelContainer
## 屏幕内抽屉：展开显示完整内容，收起缩成预设大小的正方体。不贴屏幕边。

signal expanded_changed(is_expanded: bool)

## 收起后方块所在角；展开时向对角铺开。不使用 Control.Corner，避免与父类枚举同名且顺序不同。
enum PivotCorner {
	TOP_LEFT,
	TOP_RIGHT,
	BOTTOM_LEFT,
	BOTTOM_RIGHT,
}

@export_group("抽屉")
## 收起方块钉在哪一角（右上、右下等）
@export var pivot_corner: PivotCorner = PivotCorner.TOP_LEFT:
	set(value):
		pivot_corner = value
		_apply_grow_flags()
		_apply_size_flags_for_state()
		if _is_layout_ready:
			_pinned_corner_position = _get_corner_position(
				_authored_position,
				_content_size
			)
			_apply_drawer_size(false)

## 收起后的正方形边长（像素）
@export var collapsed_size: float = 48.0:
	set(value):
		collapsed_size = maxf(value, 8.0)
		if _is_layout_ready and not is_expanded:
			update_minimum_size()
			_apply_drawer_size(false)

## 收起方块上显示的短标题
@export var collapsed_title: String = "":
	set(value):
		collapsed_title = value
		queue_redraw()

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

## 点击切换：收起时点方块展开；展开时点栏内空白或栏外空白收起，点物品不收起
@export var toggle_on_click: bool = true:
	set(value):
		toggle_on_click = value
		_update_input_process()

## 鼠标进入时展开，离开时收起（与 SideBarPanel 相同）
@export var expand_on_mouse_hover: bool = false:
	set(value):
		expand_on_mouse_hover = value
		_update_hover_process()

## 当前是否展开
var is_expanded: bool = true:
	set(value):
		if is_expanded == value:
			return
		is_expanded = value
		expanded_changed.emit(is_expanded)
		if _is_layout_ready:
			_apply_drawer_size(true)

var _drawer_tween: Tween
var _is_ready: bool = false
var _is_applying_size: bool = false
var _content_size: Vector2 = Vector2.ZERO
var _authored_position: Vector2 = Vector2.ZERO
var _pinned_corner_position: Vector2 = Vector2.ZERO
var _is_layout_ready: bool = false
## 场景中配置的尺寸标志；收起时会临时改为不拉伸
var _authored_size_flags_horizontal: int = 0
var _authored_size_flags_vertical: int = 0
var _is_collapse_correction_queued: bool = false


func _ready() -> void:
	_is_ready = true
	_capture_authored_position()
	_authored_size_flags_horizontal = size_flags_horizontal
	_authored_size_flags_vertical = size_flags_vertical
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_apply_grow_flags()
	is_expanded = start_expanded
	_apply_size_flags_for_state()
	_connect_toggle_button()
	_update_input_process()
	_update_hover_process()
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)
	call_deferred("_initialize_drawer_state")


## 收起时锁定为正方形；展开时按可见子控件测量（不可对 PanelContainer 虚函数使用 super）。
func _get_minimum_size() -> Vector2:
	if _is_layout_ready and not is_expanded:
		return Vector2(collapsed_size, collapsed_size)
	var measured := Vector2.ZERO
	for child in get_children():
		var child_control := child as Control
		if child_control == null or not child_control.visible:
			continue
		var child_min: Vector2 = child_control.get_combined_minimum_size()
		measured.x = maxf(measured.x, child_min.x)
		measured.y = maxf(measured.y, child_min.y)
	var stylebox := get_theme_stylebox("panel")
	if stylebox:
		measured.x += stylebox.content_margin_left + stylebox.content_margin_right
		measured.y += stylebox.content_margin_top + stylebox.content_margin_bottom
	return measured


func _exit_tree() -> void:
	_disconnect_toggle_button()
	_kill_drawer_tween()


#region 公开接口

## 切换展开/收起
func toggle() -> void:
	is_expanded = not is_expanded


## 展开抽屉
func expand() -> void:
	is_expanded = true


## 收起成方块
func collapse() -> void:
	is_expanded = false

#endregion


#region 交互输入

func _process(_delta: float) -> void:
	if not expand_on_mouse_hover or not _is_layout_ready:
		return
	if _is_mouse_inside_drawer():
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
	if _is_mouse_inside_drawer():
		expand()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if toggle_input_action == &"":
		return
	if event.is_action_pressed(toggle_input_action):
		toggle()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not toggle_on_click:
		return
	if not (event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if is_expanded:
		collapse()
		accept_event()
	else:
		expand()
		accept_event()


## 是否为栏外空白点击（点其它背包/按钮不收起）
func _should_collapse_from_outside_click() -> bool:
	if _is_mouse_inside_drawer():
		return false
	var hovered_control := get_viewport().gui_get_hovered_control()
	if hovered_control == null:
		return true
	if hovered_control == self or is_ancestor_of(hovered_control):
		return false
	if toggle_button != null and (
			hovered_control == toggle_button \
			or toggle_button.is_ancestor_of(hovered_control)):
		return false
	if hovered_control is BaseButton:
		return false
	if hovered_control.mouse_filter == Control.MOUSE_FILTER_STOP:
		return false
	return true


## 鼠标是否在本抽屉可见范围内
func _is_mouse_inside_drawer() -> bool:
	if not is_inside_tree() or not is_visible_in_tree():
		return false
	return get_global_rect().has_point(get_global_mouse_position())


func _update_input_process() -> void:
	if not is_inside_tree():
		set_process_input(false)
		set_process_unhandled_input(false)
		return
	set_process_input(toggle_on_click)
	set_process_unhandled_input(toggle_input_action != &"")


## 仅在开启悬停展开时启用每帧检测
func _update_hover_process() -> void:
	set_process(expand_on_mouse_hover and is_inside_tree() and _is_layout_ready)


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


#region 尺寸与动画

func _initialize_drawer_state() -> void:
	await _measure_by_hugging_content()
	_pinned_corner_position = _get_corner_position(
		_authored_position,
		_content_size
	)
	_set_content_visible(is_expanded)
	_apply_size_flags_for_state()
	_is_layout_ready = true
	update_minimum_size()
	if is_expanded:
		_set_drawer_rect(_content_size, _authored_position)
	else:
		_set_drawer_rect(
			Vector2(collapsed_size, collapsed_size),
			_get_collapsed_position()
		)
	queue_redraw()
	_update_hover_process()
	call_deferred("_pin_authored_if_collapsed")


## 记下场景里摆放的左上角，用 offset 避免布局后 position 已偏。
func _capture_authored_position() -> void:
	_authored_position = Vector2(offset_left, offset_top)


func _pin_authored_if_collapsed() -> void:
	if is_expanded:
		return
	_set_drawer_rect(
		Vector2(collapsed_size, collapsed_size),
		_get_collapsed_position()
	)


## 按 pivot 将收起方块放到与场景中展开状态相同的固定角上。
func _get_collapsed_position() -> Vector2:
	var collapsed_drawer_size := Vector2(collapsed_size, collapsed_size)
	return _get_position_from_pinned_corner(collapsed_drawer_size)


## 显示子控件并采样最小尺寸，位置始终保持场景中的摆放。
func _measure_by_hugging_content() -> void:
	if not is_inside_tree():
		return
	var saved_modulate := modulate
	var saved_mouse_filter := mouse_filter
	modulate.a = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_content_visible(true)
	await get_tree().process_frame
	await get_tree().process_frame
	_content_size = _measure_content_size()
	_set_drawer_rect(size, _authored_position)
	modulate = saved_modulate
	mouse_filter = saved_mouse_filter


func _on_resized() -> void:
	if _is_applying_size:
		return
	if _drawer_tween != null and _drawer_tween.is_running():
		return
	if _is_layout_ready and not is_expanded:
		_queue_collapsed_size_correction()


## 等父容器完成本帧布局后，再将收起状态纠正为正方形。
func _queue_collapsed_size_correction() -> void:
	if _is_collapse_correction_queued:
		return
	_is_collapse_correction_queued = true
	call_deferred("_correct_collapsed_size")


## 消除父容器延迟布局对收起尺寸的覆盖。
func _correct_collapsed_size() -> void:
	_is_collapse_correction_queued = false
	if not is_inside_tree() or not _is_layout_ready or is_expanded:
		return
	if _drawer_tween != null and _drawer_tween.is_running():
		return
	var target_size := Vector2(collapsed_size, collapsed_size)
	if get_parent() is Container:
		# 容器负责摆放位置，此处只纠正宽高，避免破坏兄弟节点排列。
		_set_drawer_size_only(target_size)
	else:
		_set_drawer_rect(target_size, _get_collapsed_position())


## 始终从左上角增减尺寸，钉住角只通过改 offset 实现，避免 GROW_BEGIN 把节点挪走。
func _apply_grow_flags() -> void:
	grow_horizontal = Control.GROW_DIRECTION_END
	grow_vertical = Control.GROW_DIRECTION_END


## 收起时取消 FILL，避免被 VBox/HBox 拉成列宽；展开时恢复场景标志。
func _apply_size_flags_for_state() -> void:
	if not _is_ready:
		return
	if is_expanded:
		size_flags_horizontal = _authored_size_flags_horizontal
		size_flags_vertical = _authored_size_flags_vertical
		return
	size_flags_horizontal = _get_collapsed_shrink_flag_horizontal()
	size_flags_vertical = _get_collapsed_shrink_flag_vertical()


## 收起方块在父容器中的水平贴齐方向
func _get_collapsed_shrink_flag_horizontal() -> int:
	match pivot_corner:
		PivotCorner.TOP_RIGHT, PivotCorner.BOTTOM_RIGHT:
			return Control.SIZE_SHRINK_END
		_:
			return Control.SIZE_SHRINK_BEGIN


## 收起方块在父容器中的垂直贴齐方向
func _get_collapsed_shrink_flag_vertical() -> int:
	match pivot_corner:
		PivotCorner.BOTTOM_LEFT, PivotCorner.BOTTOM_RIGHT:
			return Control.SIZE_SHRINK_END
		_:
			return Control.SIZE_SHRINK_BEGIN


## 用子控件的最小尺寸；隐藏时仍可读 custom_minimum_size。
func _measure_content_size() -> Vector2:
	var measured := Vector2.ZERO
	for child in get_children():
		var child_control := child as Control
		if child_control == null:
			continue
		var child_min: Vector2 = child_control.get_combined_minimum_size()
		measured.x = maxf(measured.x, child_min.x)
		measured.y = maxf(measured.y, child_min.y)
	var stylebox := get_theme_stylebox("panel")
	if stylebox:
		measured.x += stylebox.content_margin_left + stylebox.content_margin_right
		measured.y += stylebox.content_margin_top + stylebox.content_margin_bottom
	if measured.x < collapsed_size:
		measured.x = collapsed_size
	if measured.y < collapsed_size:
		measured.y = collapsed_size
	return measured


func _apply_drawer_size(animate: bool) -> void:
	if not is_inside_tree() or _is_applying_size:
		return
	if is_expanded:
		# 展开过程中先不显示内部 UI，避免最小尺寸把动画目标撑大。
		_set_content_visible(false)
	else:
		# 收起前趁内容仍可见时记下真实大小。
		if _is_content_visible():
			_content_size = _measure_content_size()
		_set_content_visible(false)
	_apply_size_flags_for_state()
	update_minimum_size()
	queue_redraw()
	var target_size := _get_target_size()
	var target_position := _get_position_from_pinned_corner(target_size)
	if animate and animation_duration > 0.0 and _is_ready:
		_animate_to_rect(target_size, target_position)
	else:
		_kill_drawer_tween()
		_set_drawer_rect(target_size, target_position)
		if is_expanded:
			_set_content_visible(true)


## 收起时隐藏内容。展开动画结束后再显示。
func _set_content_visible(should_show: bool) -> void:
	for child in get_children():
		var child_control := child as Control
		if child_control == null:
			continue
		child_control.visible = should_show


func _is_content_visible() -> bool:
	for child in get_children():
		var child_control := child as Control
		if child_control != null and child_control.visible:
			return true
	return false


func _get_target_size() -> Vector2:
	if is_expanded:
		if _content_size.x > collapsed_size and _content_size.y > collapsed_size:
			return _content_size
		return _measure_content_size()
	return Vector2(collapsed_size, collapsed_size)


## 获取指定矩形受 pivot_corner 固定的角点。
func _get_corner_position(rect_position: Vector2, rect_size: Vector2) -> Vector2:
	var corner_position := rect_position
	match pivot_corner:
		PivotCorner.TOP_RIGHT, PivotCorner.BOTTOM_RIGHT:
			corner_position.x += rect_size.x
		_:
			pass
	match pivot_corner:
		PivotCorner.BOTTOM_LEFT, PivotCorner.BOTTOM_RIGHT:
			corner_position.y += rect_size.y
		_:
			pass
	return corner_position


## 根据初始化时记录的固定角点，计算目标矩形左上角。
func _get_position_from_pinned_corner(target_size: Vector2) -> Vector2:
	var target_position := _pinned_corner_position
	match pivot_corner:
		PivotCorner.TOP_RIGHT, PivotCorner.BOTTOM_RIGHT:
			target_position.x -= target_size.x
		_:
			pass
	match pivot_corner:
		PivotCorner.BOTTOM_LEFT, PivotCorner.BOTTOM_RIGHT:
			target_position.y -= target_size.y
		_:
			pass
	return target_position


func _animate_to_rect(target_size: Vector2, target_position: Vector2) -> void:
	_kill_drawer_tween()
	var start_size := size
	if start_size.x <= 0.0 or start_size.y <= 0.0:
		start_size = custom_minimum_size
	_drawer_tween = create_tween()
	_drawer_tween.set_trans(animation_transition)
	_drawer_tween.set_ease(animation_ease)
	_drawer_tween.set_parallel(true)
	_drawer_tween.tween_method(_set_drawer_size_only, start_size, target_size, animation_duration)
	_drawer_tween.tween_property(self, "offset_left", target_position.x, animation_duration)
	_drawer_tween.tween_property(self, "offset_top", target_position.y, animation_duration)
	_drawer_tween.chain().tween_callback(_on_drawer_animation_finished)


## 只改宽高，左上角由 offset tween 负责。
func _set_drawer_size_only(target_size: Vector2) -> void:
	_is_applying_size = true
	custom_minimum_size = target_size
	offset_right = offset_left + target_size.x
	offset_bottom = offset_top + target_size.y
	_is_applying_size = false


func _set_drawer_rect(target_size: Vector2, target_position: Vector2) -> void:
	_is_applying_size = true
	custom_minimum_size = target_size
	offset_left = target_position.x
	offset_top = target_position.y
	offset_right = target_position.x + target_size.x
	offset_bottom = target_position.y + target_size.y
	_is_applying_size = false


## 展开动画完成后再显示内部 UI，不再二次改尺寸以免偏移。
func _on_drawer_animation_finished() -> void:
	_drawer_tween = null
	if is_expanded:
		_set_content_visible(true)
	else:
		_correct_collapsed_size()
		_queue_collapsed_size_correction()
	queue_redraw()


func _kill_drawer_tween() -> void:
	if _drawer_tween != null and _drawer_tween.is_valid():
		_drawer_tween.kill()
	_drawer_tween = null


func _draw() -> void:
	if is_expanded or collapsed_title.is_empty():
		return
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	if font == null:
		return
	var text_size := font.get_string_size(collapsed_title, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_position := Vector2(
		(size.x - text_size.x) * 0.5,
		(size.y + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	)
	draw_string(
		font,
		text_position,
		collapsed_title,
		HORIZONTAL_ALIGNMENT_CENTER,
		-1,
		font_size,
		Color.WHITE
	)

#endregion
