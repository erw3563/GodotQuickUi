class_name QuickRotate
extends Node
## 旋转组件：把宿主 [Control] 从倾斜角旋转回正入场、转回倾斜退场；可与 [class QuickZoom]
## 组合「放大 + 旋转回正」的合成出场演出——两者互不认识，各自只动自己的属性，
## 场景把 QuickZoom 的 expanded_changed 连到 [method set_upright] 即同步起播。
## 所有权契约：只驱动宿主的 rotation，不改 scale / pivot_offset / modulate.a / visible /
## mouse_filter / global_position / size，真实布局全程不变；因此与 [class QuickZoom]
## （驱动缩放）、[class QuickConstraints]（含 continuous）和 [class QuickPopOut]（驱动位置）
## 互不冲突，可叠加挂在同一控件上。旋转绕宿主当前 pivot_offset
## （配合 QuickZoom 时即其 origin_ratio 钉扎的原点）。

signal upright_changed(is_upright: bool)
signal rotate_finished(is_upright: bool)

## 要驱动的宿主控件；为空则尝试使用本组件的父节点（若为 Control）。
@export var ui: Control

@export_group("旋转")
## 入场起始倾斜角，兼退场终点角（度）；符号决定旋转方向，0 则无旋转演出。
@export_range(-1080.0, 1080.0, 0.1, "degrees") var start_rotation_degrees: float = -25.0:
	set(value):
		start_rotation_degrees = value
		# 静息在倾斜态时改角，即刻换到新倾斜角（下次入场方向随之改变）。
		if _is_layout_ready and not is_upright and not is_rotating and ui != null:
			ui.rotation_degrees = value

## 初始是否转正
@export var start_upright: bool = true

## 初始转正时是否播旋转入场动效（false 则直接就位）
@export var animate_entrance: bool = true

## 转正/转倾斜动画时长（秒）
@export_range(0.0, 2.0, 0.01) var animation_duration: float = 0.25

## 动画过渡类型（默认 BACK 配 EASE_OUT：越过 0 过冲再恰好回正）
@export var animation_transition: Tween.TransitionType = Tween.TRANS_BACK

## 转正动画缓动类型（转倾斜固定用 EASE_IN 转回倾斜）
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

## 当前是否转正
var is_upright: bool = true:
	set(value):
		if is_upright == value:
			return
		is_upright = value
		upright_changed.emit(is_upright)
		if _is_layout_ready:
			_apply_rotation(true)

## 是否正在播放旋转动画
var is_rotating: bool:
	get:
		return _rotation_tween != null and _rotation_tween.is_running()

var _rotation_tween: Tween
var _is_layout_ready: bool = false


func _ready() -> void:
	_resolve_ui()
	if ui == null:
		return
	# 布局就绪前先落到倾斜角，避免入场动画开始前闪现转正态（可见性归外部所有者）。
	if not (start_upright and not animate_entrance):
		ui.rotation_degrees = start_rotation_degrees
	is_upright = start_upright
	_connect_toggle_button()
	_update_input_process()
	_initialize_rotation_state()


func _exit_tree() -> void:
	_disconnect_toggle_button()
	_kill_rotation_tween()


#region 公开接口

## 切换转正/倾斜
func toggle() -> void:
	is_upright = not is_upright


## 从倾斜角旋转回正（入场）
func straighten() -> void:
	is_upright = true


## 从转正旋转回倾斜角（退场）
func tilt() -> void:
	is_upright = false

## 统一播放入口（与 QuickPopOut / QuickZoom 同名，宿主经此成组驱动演出）：
## 播放入场动画（倾斜角旋转回正）；已转正则无动作（状态机守卫）。
func play_entrance() -> void:
	straighten()

## 统一播放入口：播放退场动画（转回倾斜角）；已倾斜则无动作。
func play_exit() -> void:
	tilt()


## 状态转接入口：签名与 [class QuickZoom] 的 expanded_changed(is_expanded) 对齐，
## 场景里把该信号直接连到这里即得同步演出。
func set_upright(value: bool) -> void:
	is_upright = value

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


#region 旋转与动画

## 等布局定型后，再按初始状态就位或播入场动效。
func _initialize_rotation_state() -> void:
	if not is_inside_tree():
		return
	await QuickUI.layout_settled(self)
	if not is_inside_tree():
		return
	_is_layout_ready = true
	_apply_rotation(is_upright and animate_entrance)


## 按当前转正状态就位或播放旋转动画。
func _apply_rotation(animate: bool) -> void:
	if ui == null or not ui.is_inside_tree():
		return
	if is_upright:
		if animate and animation_duration > 0.0:
			_animate_rotation(0.0, true)
			return
		_kill_rotation_tween()
		ui.rotation_degrees = 0.0
		rotate_finished.emit(true)
		return
	if animate and animation_duration > 0.0:
		_animate_rotation(start_rotation_degrees, false)
		return
	_kill_rotation_tween()
	ui.rotation_degrees = start_rotation_degrees
	rotate_finished.emit(false)


## 播放旋转动画：转正越过 0 过冲后恰好落 0，倾斜加速转回起始角。
func _animate_rotation(target_degrees: float, straightening: bool) -> void:
	_kill_rotation_tween()
	_rotation_tween = ui.create_tween()
	_rotation_tween.set_trans(animation_transition)
	_rotation_tween.set_ease(animation_ease if straightening else Tween.EASE_IN)
	_rotation_tween.set_parallel(true)
	_rotation_tween.tween_method(
		_set_rotation_degrees, ui.rotation_degrees, target_degrees, animation_duration
	)
	_rotation_tween.chain().tween_callback(_on_rotation_animation_finished)


func _set_rotation_degrees(value: float) -> void:
	if ui == null:
		return
	ui.rotation_degrees = value


## 动画结束落终态：转正精确归 0，倾斜精确落起始角。
func _on_rotation_animation_finished() -> void:
	_rotation_tween = null
	if ui != null:
		ui.rotation_degrees = 0.0 if is_upright else start_rotation_degrees
	rotate_finished.emit(is_upright)


func _kill_rotation_tween() -> void:
	if _rotation_tween != null and _rotation_tween.is_valid():
		_rotation_tween.kill()
	_rotation_tween = null


## 若未指定 ui，则当父节点为 Control 时将其作为驱动目标。
func _resolve_ui() -> void:
	if ui != null:
		return
	var p := get_parent()
	if p is Control:
		ui = p as Control

#endregion
