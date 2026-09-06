class_name QuickZoom
extends Node
## 缩放组件：把宿主 [Control] 从原点放大展开、缩回原点收起（演出移植自 [class ZoomPanel]）。
## 所有权契约：只驱动宿主的 scale / pivot_offset / modulate.a / visible / mouse_filter，
## 不改 global_position / size，真实布局全程不变；因此与 [class QuickConstraints]（含 continuous）
## 和 [class QuickPopOut]（驱动位置）互不冲突，可叠加挂在同一控件上。

signal expanded_changed(is_expanded: bool)
signal zoom_finished(is_expanded: bool)

## 要驱动的宿主控件；为空则尝试使用本组件的父节点（若为 Control）。
@export var ui: Control

@export_group("缩放")
## 放大原点在宿主内的比例坐标（0~1；默认正中心向四周铺开，四角可设 0/1）
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

## 收起结束后是否隐藏宿主；关闭则只缩回原点，可见性交外部所有者（可与 QuickShow 等组合）
@export var hide_on_collapse: bool = true

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
## 宿主场景中配置的鼠标过滤；动画期间临时改为 IGNORE，结束后恢复
var _authored_mouse_filter: Control.MouseFilter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	_resolve_ui()
	if ui == null:
		return
	_authored_mouse_filter = ui.mouse_filter
	# 布局采样前先隐藏归零，避免入场动画开始前闪现完整面板。
	ui.visible = false
	ui.scale = Vector2.ZERO
	is_expanded = start_expanded
	_connect_toggle_button()
	_update_input_process()
	if not ui.resized.is_connected(_sync_pivot_offset):
		ui.resized.connect(_sync_pivot_offset)
	_initialize_zoom_state()


func _exit_tree() -> void:
	_disconnect_toggle_button()
	_kill_zoom_tween()
	if ui != null and ui.resized.is_connected(_sync_pivot_offset):
		ui.resized.disconnect(_sync_pivot_offset)


#region 公开接口

## 切换展开/收起
func toggle() -> void:
	is_expanded = not is_expanded


## 从原点放大展开
func expand() -> void:
	is_expanded = true


## 缩回原点（默认随附隐藏宿主）
func collapse() -> void:
	is_expanded = false

## 统一播放入口（与 QuickPopOut / QuickRotate 同名，宿主经此成组驱动演出）：
## 播放入场动画（原点放大展开）；已展开则无动作（状态机守卫）。
func play_entrance() -> void:
	expand()

## 统一播放入口：播放退场动画（缩回原点收起）；已收起则无动作。
func play_exit() -> void:
	collapse()

#endregion


#region 交互输入

func _unhandled_input(event: InputEvent) -> void:
	if toggle_input_action == &"":
		return
	if event.is_action_pressed(toggle_input_action):
		toggle()
		get_viewport().set_input_as_handled()


func _update_input_process() -> void:
	if not is_inside_tree():
		set_process_unhandled_input(false)
		return
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

## 等布局定型拿到最终尺寸后，再按初始状态就位或播入场动效。
func _initialize_zoom_state() -> void:
	if not is_inside_tree():
		return
	await QuickUI.layout_settled(self)
	if not is_inside_tree():
		return
	_is_layout_ready = true
	_apply_zoom(is_expanded and animate_entrance)


## 按当前展开状态就位或播放缩放动画。
func _apply_zoom(animate: bool) -> void:
	if ui == null or not ui.is_inside_tree():
		return
	_sync_pivot_offset()
	if is_expanded:
		ui.visible = true
		if animate and animation_duration > 0.0:
			_animate_zoom(Vector2.ONE, true)
			return
		_kill_zoom_tween()
		ui.scale = Vector2.ONE
		ui.modulate.a = 1.0
		ui.mouse_filter = _authored_mouse_filter
		zoom_finished.emit(true)
		return
	if animate and animation_duration > 0.0:
		_animate_zoom(Vector2.ZERO, false)
		return
	_set_collapsed_instantly()


## 播放缩放动画：展开放大淡入，收起吸回原点淡出。
func _animate_zoom(target_scale: Vector2, expanding: bool) -> void:
	_kill_zoom_tween()
	# 动画期间不吞点击，结束后恢复。
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zoom_tween = ui.create_tween()
	_zoom_tween.set_trans(animation_transition)
	_zoom_tween.set_ease(animation_ease if expanding else Tween.EASE_IN)
	_zoom_tween.set_parallel(true)
	_zoom_tween.tween_method(
		_set_zoom_scale_clamped, ui.scale, target_scale, animation_duration
	)
	if fade_during_zoom:
		var target_alpha := 1.0 if expanding else 0.0
		_zoom_tween.tween_method(
			_set_zoom_alpha_clamped, ui.modulate.a, target_alpha,
			animation_duration * (0.85 if expanding else 1.0)
		)
	_zoom_tween.chain().tween_callback(_on_zoom_animation_finished)


## BACK 曲线插值末端可能为负，负 scale 会镜像渲染，钳到 0。
func _set_zoom_scale_clamped(value: Vector2) -> void:
	if ui == null:
		return
	ui.scale = Vector2(maxf(value.x, 0.0), maxf(value.y, 0.0))


func _set_zoom_alpha_clamped(value: float) -> void:
	if ui == null:
		return
	ui.modulate.a = clampf(value, 0.0, 1.0)


## 无动画直接进入收起终态。
func _set_collapsed_instantly() -> void:
	ui.scale = Vector2.ZERO
	if fade_during_zoom:
		ui.modulate.a = 0.0
	if hide_on_collapse:
		ui.visible = false
	ui.mouse_filter = _authored_mouse_filter
	zoom_finished.emit(false)


## 动画结束落终态：展开对齐满幅，收起按配置隐藏。
func _on_zoom_animation_finished() -> void:
	_zoom_tween = null
	ui.mouse_filter = _authored_mouse_filter
	if is_expanded:
		ui.scale = Vector2.ONE
		ui.modulate.a = 1.0
		zoom_finished.emit(true)
		return
	if fade_during_zoom:
		ui.modulate.a = 0.0
	ui.scale = Vector2.ZERO
	if hide_on_collapse:
		ui.visible = false
	zoom_finished.emit(false)


## 把 pivot 钉到原点比例处；缩放全程该点屏幕位置保持不变。
func _sync_pivot_offset() -> void:
	if ui == null:
		return
	var basis_size := ui.size
	if basis_size.x <= 0.0 or basis_size.y <= 0.0:
		basis_size = ui.custom_minimum_size
	ui.pivot_offset = Vector2(
		clampf(origin_ratio.x, 0.0, 1.0) * basis_size.x,
		clampf(origin_ratio.y, 0.0, 1.0) * basis_size.y
	)


func _kill_zoom_tween() -> void:
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = null


## 若未指定 ui，则当父节点为 Control 时将其作为驱动目标。
func _resolve_ui() -> void:
	if ui != null:
		return
	var p := get_parent()
	if p is Control:
		ui = p as Control

#endregion
