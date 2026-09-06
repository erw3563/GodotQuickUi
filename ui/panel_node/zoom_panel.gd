class_name ZoomPanel
extends PanelContainer
## 缩放面板：入场从起点缩放放大至目标缩放

signal expanded_changed(is_expanded: bool)

@export_group("缩放")
## 放大原点在面板内的比例坐标（0~1；默认正中心向四周铺开，四角可设 0/1）
@export var origin_ratio: Vector2 = Vector2(0.5, 0.5):
	set(value):
		origin_ratio = value
		if _is_layout_ready:
			_sync_pivot_offset()

## 初始是否展开
@export var start_expanded: bool = true

## 初始展开时是否播放入场放大动效（false 则直接就位）
@export var animate_entrance: bool = true

## 展开/收起动画时长（秒）
@export_range(0.0, 2.0, 0.01) var animation_duration: float = 0.25

## 动画过渡类型（默认 BACK 配 EASE_OUT，带回弹弹出感）
@export var animation_transition: Tween.TransitionType = Tween.TRANS_BACK

## 展开动画缓动类型（收起固定用 EASE_IN 吸回原点）
@export var animation_ease: Tween.EaseType = Tween.EASE_OUT

## 缩放同时淡入淡出
@export var fade_during_zoom: bool = true

## 展开动画结束时的目标缩放（默认 1=原始大小，各轴独立；真实布局尺寸不变）
@export var expanded_scale: Vector2 = Vector2.ONE:
	set(value):
		expanded_scale = Vector2(maxf(value.x, 0.0), maxf(value.y, 0.0))
		if _is_layout_ready and is_expanded:
			_apply_zoom(is_zooming)

## 收起终态/展开起点的目标缩放（默认 0=缩没并隐藏；非 0 时收起后保留可见种子，不隐藏不淡出）
@export var collapsed_scale: Vector2 = Vector2.ZERO:
	set(value):
		collapsed_scale = Vector2(maxf(value.x, 0.0), maxf(value.y, 0.0))
		if _is_layout_ready and not is_expanded:
			_apply_zoom(is_zooming)

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

## 鼠标悬停时展开，离开时收起（热区=布局矩形与展开缩放后矩形的并集；收起不可见时热区仍生效）
@export var expand_on_mouse_hover: bool = false:
	set(value):
		expand_on_mouse_hover = value
		_update_hover_process()

## 点击切换：收起时点热区内（含子控件）展开；展开时点热区空白或栏外空白区域收起
@export var toggle_on_click: bool = false:
	set(value):
		toggle_on_click = value
		_update_input_process()

## 可选：外部热区控件（设置后检测区域完全以该控件全局矩形为准，禁用面板原位置检测；
## 可摆在面板外任意位置；其自身或祖先隐藏时热区不生效；）
@export var interaction_control: Control

## 当前是否展开
var is_expanded: bool = true:
	set(value):
		if is_expanded == value:
			return
		is_expanded = value
		expanded_changed.emit(is_expanded)
		if _is_layout_ready:
			_apply_zoom(true)

## 是否正在播放展开/收起动画
var is_zooming: bool:
	get:
		return _zoom_tween != null and _zoom_tween.is_running()

var _zoom_tween: Tween
var _is_layout_ready: bool = false
## 场景中配置的鼠标过滤；动画期间临时改为 IGNORE，结束后恢复
var _authored_mouse_filter: Control.MouseFilter = Control.MOUSE_FILTER_STOP
## 鼠标是否仍在窗口客户区内
var _is_pointer_in_window: bool = true


func _ready() -> void:
	_authored_mouse_filter = mouse_filter
	# 布局采样前先隐藏归零，避免入场动画开始前闪现完整面板。
	visible = false
	scale = Vector2.ZERO
	is_expanded = start_expanded
	_connect_toggle_button()
	_connect_window_mouse_tracking()
	_update_input_process()
	_update_hover_process()
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)
	call_deferred("_initialize_zoom_state")


func _exit_tree() -> void:
	_disconnect_toggle_button()
	_disconnect_window_mouse_tracking()
	_kill_zoom_tween()


#region 公开接口

## 切换展开/收起
func toggle() -> void:
	is_expanded = not is_expanded


## 从原点放大展开
func expand() -> void:
	is_expanded = true


## 缩回原点并隐藏
func collapse() -> void:
	is_expanded = false

#endregion


#region 交互输入

func _process(_delta: float) -> void:
	if not expand_on_mouse_hover:
		return
	if _is_mouse_inside_panel():
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
		if _should_collapse_from_zone_click():
			collapse()
			get_viewport().set_input_as_handled()
		return
	if _is_mouse_inside_panel():
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
	if interaction_control != null:
		# 外部热区模式下原位置检测禁用：面板本体不再是点击切换面（子控件照常自处理）
		return
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		collapse()
		accept_event()


## 是否为「栏外空白」点击（外部切换按钮等交互控件除外）
func _should_collapse_from_outside_click() -> bool:
	if _is_mouse_inside_panel():
		return false
	var hovered_control := get_viewport().gui_get_hovered_control()
	if hovered_control == null:
		return true
	# 点在本面板内（含子控件）时不收起
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


## 展开态点击热区本体是否收起：命中外部热区控件（含子孙）或 IGNORE 热区下的空白
## 视为点击热区（面板自身的空白仍走 _gui_input）；热区上的其它交互控件不抢。
func _should_collapse_from_zone_click() -> bool:
	if interaction_control == null:
		return false
	if not _is_mouse_inside_panel():
		return false
	var hovered_control := get_viewport().gui_get_hovered_control()
	if hovered_control == null:
		return true
	return hovered_control == interaction_control \
			or interaction_control.is_ancestor_of(hovered_control)


## 鼠标是否在面板热区内（含全部子控件）
func _is_mouse_inside_panel() -> bool:
	if not _is_hover_zone_active():
		return false
	# 系统标题栏属于非客户区：离开客户区后不能凭旧坐标维持悬停
	if not _is_pointer_in_window:
		return false
	return _get_interaction_rect().has_point(get_global_mouse_position())


## 热区是否参与交互：外部热区跟随热区控件自身可见性；内置热区在祖先链整块隐藏
## （如翻页互斥）时不触发，收起终态自身 visible=false 只影响渲染，不影响热区。
func _is_hover_zone_active() -> bool:
	if not is_inside_tree():
		return false
	if interaction_control != null:
		return interaction_control.is_visible_in_tree()
	if is_visible_in_tree():
		return true
	if visible:
		return false
	var parent_control := get_parent_control()
	return parent_control == null or parent_control.is_visible_in_tree()


## 悬停/点击热区：指定 interaction_control 时直接用其全局矩形（外部热区）；
## 否则取布局矩形与展开/收起目标缩放矩形（绕 pivot）的并集。
## 与当前展开状态无关，默认终点 1、起点 0 时即布局矩形；并集保证收起/展开热区互相覆盖，
## 不因缩放差异来回抖动。
func _get_interaction_rect() -> Rect2:
	if interaction_control != null:
		return interaction_control.get_global_rect()
	# get_global_position() 含当前缩放绕 pivot 的原点位移，先还原未缩放布局原点
	var layout_origin := get_global_position() - pivot_offset * (Vector2.ONE - scale)
	var layout_rect := Rect2(layout_origin, size)
	if expanded_scale == Vector2.ONE and collapsed_scale == Vector2.ZERO:
		return layout_rect
	var expanded_origin := layout_origin + pivot_offset * (Vector2.ONE - expanded_scale)
	var result := layout_rect.merge(Rect2(expanded_origin, size * expanded_scale))
	if collapsed_scale == Vector2.ZERO:
		return result
	var collapsed_origin := layout_origin + pivot_offset * (Vector2.ONE - collapsed_scale)
	return result.merge(Rect2(collapsed_origin, size * collapsed_scale))


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


#region 缩放与动画

## 等一帧布局定型拿到最终尺寸后，再按初始状态就位或播入场动效。
func _initialize_zoom_state() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_is_layout_ready = true
	_apply_zoom(is_expanded and animate_entrance)


## 就位/动画结束后恢复的鼠标过滤：点击切换需要 STOP 才能收到 _gui_input
func _get_restored_mouse_filter() -> Control.MouseFilter:
	if toggle_on_click:
		return Control.MOUSE_FILTER_STOP
	return _authored_mouse_filter


## 收起终态是否隐藏：缩没（0 倍率）才隐藏；非 0 收起缩放保留可见种子
func _is_collapse_hidden() -> bool:
	return collapsed_scale == Vector2.ZERO


## 按当前展开状态就位或播放缩放动画。
func _apply_zoom(animate: bool) -> void:
	if not is_inside_tree():
		return
	_sync_pivot_offset()
	if is_expanded:
		visible = true
		if animate and animation_duration > 0.0:
			_animate_zoom(expanded_scale, true)
			return
		_kill_zoom_tween()
		scale = expanded_scale
		modulate.a = 1.0
		mouse_filter = _get_restored_mouse_filter()
		return
	if animate and animation_duration > 0.0:
		_animate_zoom(collapsed_scale, false)
		return
	_kill_zoom_tween()
	_set_collapsed_instantly()


## 播放缩放动画：展开放大淡入，收起吸回原点淡出。
func _animate_zoom(target_scale: Vector2, expanding: bool) -> void:
	_kill_zoom_tween()
	# 动画期间不吞点击，结束后恢复。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zoom_tween = create_tween()
	_zoom_tween.set_trans(animation_transition)
	_zoom_tween.set_ease(animation_ease if expanding else Tween.EASE_IN)
	_zoom_tween.set_parallel(true)
	_zoom_tween.tween_method(
		_set_zoom_scale_clamped, scale, target_scale, animation_duration
	)
	if fade_during_zoom and (expanding or _is_collapse_hidden()):
		var target_alpha := 1.0 if expanding else 0.0
		_zoom_tween.tween_method(
			_set_zoom_alpha_clamped, modulate.a, target_alpha,
			animation_duration * (0.85 if expanding else 1.0)
		)
	_zoom_tween.chain().tween_callback(_on_zoom_animation_finished)


## BACK 曲线插值末端可能为负，负 scale 会镜像渲染，钳到 0。
func _set_zoom_scale_clamped(value: Vector2) -> void:
	scale = Vector2(maxf(value.x, 0.0), maxf(value.y, 0.0))


func _set_zoom_alpha_clamped(value: float) -> void:
	modulate.a = clampf(value, 0.0, 1.0)


## 无动画直接进入收起终态：缩没隐藏，或落到非 0 收起缩放的可见种子。
func _set_collapsed_instantly() -> void:
	scale = collapsed_scale
	if _is_collapse_hidden():
		if fade_during_zoom:
			modulate.a = 0.0
		visible = false
	else:
		visible = true
	mouse_filter = _get_restored_mouse_filter()


## 动画结束落终态：展开对齐目标缩放，收起缩没隐藏或落到种子。
func _on_zoom_animation_finished() -> void:
	_zoom_tween = null
	mouse_filter = _get_restored_mouse_filter()
	if is_expanded:
		scale = expanded_scale
		modulate.a = 1.0
		return
	if fade_during_zoom and _is_collapse_hidden():
		modulate.a = 0.0
	scale = collapsed_scale
	if _is_collapse_hidden():
		visible = false


## 把 pivot 钉到原点比例处；缩放全程该点屏幕位置保持不变。
func _sync_pivot_offset() -> void:
	var basis_size := size
	if basis_size.x <= 0.0 or basis_size.y <= 0.0:
		basis_size = custom_minimum_size
	pivot_offset = Vector2(
		clampf(origin_ratio.x, 0.0, 1.0) * basis_size.x,
		clampf(origin_ratio.y, 0.0, 1.0) * basis_size.y
	)


## 布局变化后重钉 pivot，避免下次缩放原点漂移。
func _on_resized() -> void:
	_sync_pivot_offset()


func _kill_zoom_tween() -> void:
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = null

#endregion
