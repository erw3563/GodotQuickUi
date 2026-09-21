@tool
class_name RotatePanel
extends PanelContainer
## 旋转晃动面板：交互（悬停进入热区/点击热区/按钮/按键）触发一次旋转晃动演出，
## 依次停靠 wobble_sequence 各角度后收常态角；播放中再次触发从头重播。
## 演出引擎为共享 RotationWobble（ui/core/），本面板独占一个实例；
## 交互判定复用 UIInteraction / PointerWindowTracker（与 ZoomPanel 同口径）。
## 所有权契约：只驱动自身的 rotation / pivot_offset / mouse_filter（动画期间临时
## IGNORE 放行穿透，结束恢复），不改 scale / modulate.a / size / position，
## 真实布局全程不变；旋转绕 origin_ratio 钉扎的轴心进行，全程该点屏幕位置不动。
## 悬停连播为边沿触发（进入热区晃一次，停留不重播、移出不打断、再入重播）；
## 点击触发点热区内（面板本体空白走 _gui_input，交互子控件照常自处理不被抢）。

signal wobble_finished

@export_group("动画预览")
@export_tool_button("播放一次", "Play") var preview_play_action: Callable = preview_play
@export_tool_button("停止并恢复", "Stop") var preview_stop_action: Callable = preview_stop

@export_group("晃动")
## 旋转轴心在面板内的比例坐标（0~1；默认正中心，四角可设 0/1）
@export var origin_ratio: Vector2 = Vector2(0.5, 0.5):
	set(value):
		origin_ratio = value
		if _is_layout_ready:
			_sync_pivot_offset()

## 常态角（度）：静息归宿——每轮晃动的终点；静息时改角即刻吸附
@export_range(-1080.0, 1080.0, 0.1, "degrees") var rest_rotation_degrees: float = 0.0:
	set(value):
		rest_rotation_degrees = value
		if _is_layout_ready and not is_wobbling():
			rotation_degrees = value

## 晃动停靠角序列（度）：一轮演出依次停靠的角度，播完自动收常态角；
## 正负号自定，一套配置可同时拥有顺时针与逆时针的旋转晃动；设 360 即整圈旋转
@export var wobble_sequence: Array[float] = [-25.0, 15.0]:
	set(value):
		wobble_sequence = value
		_wobble.sequence = value

## 弹性角度（度）：每段到达目标角后沿行进方向继续多转的角度，再回弹收在目标角；
## 0 = 不回弹（每段单程动画）；已停在目标角时仍会朝正向原地回弹一次
@export_range(0.0, 360.0, 0.1, "degrees") var elastic_rotation_degrees: float = 0.0:
	set(value):
		elastic_rotation_degrees = value
		_wobble.elastic_degrees = value

## 初始是否播一轮晃动入场（false 则静息在常态角）
@export var animate_entrance: bool = true

## 单段晃动动画时长（秒）；弹性回弹时该段按 70%/30% 分给去程与回程
@export_range(0.0, 2.0, 0.01) var animation_duration: float = 0.25:
	set(value):
		animation_duration = value
		_wobble.segment_duration = value

## 动画过渡类型（默认 BACK 配 EASE_OUT：越过目标过冲再恰好收敛）
@export var animation_transition: Tween.TransitionType = Tween.TRANS_BACK:
	set(value):
		animation_transition = value
		_wobble.transition = value

## 收常态段的缓动类型（去程段固定用 EASE_IN 加速离开）
@export var animation_ease: Tween.EaseType = Tween.EASE_OUT:
	set(value):
		animation_ease = value
		_wobble.ease_type = value

@export_group("交互")
## 用于触发晃动的 InputMap 动作名（留空则不响应按键）
@export var toggle_input_action: StringName = &"":
	set(value):
		toggle_input_action = value
		_update_input_process()

## 可选：绑定按钮触发晃动
@export var toggle_button: BaseButton:
	set(value):
		_disconnect_toggle_button()
		toggle_button = value
		_connect_toggle_button()

## 鼠标进入热区时晃一次（边沿触发：在热区内停留不重复起播）；
## 移出不打断，播完收常态角，再次进入重播（热区=布局矩形与常态/各停靠角包围盒的并集）
@export var play_on_mouse_hover: bool = false:
	set(value):
		play_on_mouse_hover = value
		_update_hover_process()

## 点击热区内触发晃动（面板本体空白走 _gui_input，交互子控件不被抢；
## 热区上的空白与外部热区控件同样触发；热区上的其它交互控件不抢）
@export var play_on_click: bool = false:
	set(value):
		play_on_click = value
		_update_input_process()

## 可选：外部热区控件（设置后检测区域完全以该控件全局矩形为准，禁用面板原位置检测；
## 可摆在面板外任意位置；其自身或祖先隐藏时热区不生效）
@export var interaction_control: Control

## 是否正在播放晃动演出
func is_wobbling() -> bool:
	return _wobble.is_playing

var _wobble := RotationWobble.new()
var _is_layout_ready: bool = false
## 悬停触发的边沿状态：上一帧鼠标是否在热区内
var _is_mouse_inside: bool = false
## 窗口客户区指针在场跟踪（共享原语）
var _pointer_tracker := PointerWindowTracker.new()
## 场景中配置的鼠标过滤；动画期间临时改为 IGNORE，结束后恢复
var _authored_mouse_filter: Control.MouseFilter = Control.MOUSE_FILTER_STOP
var _preview := AnimationPreview.new()


func _ready() -> void:
	_wobble.setup(self, self)
	_sync_wobble_config()
	if Engine.is_editor_hint():
		_update_input_process()
		return
	_authored_mouse_filter = mouse_filter
	rotation_degrees = rest_rotation_degrees
	_connect_toggle_button()
	_pointer_tracker.attach(self)
	_update_input_process()
	_update_hover_process()
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)
	_wobble.finished.connect(_on_wobble_finished)
	call_deferred("_initialize_rotation_state")


func _exit_tree() -> void:
	preview_stop()
	_disconnect_toggle_button()
	_pointer_tracker.detach(self)
	_wobble.abort()


#region 公开接口

## 播放一轮晃动（依次停靠 wobble_sequence 后收常态角）；播放中调用从头重播。
## 空序列无演出（不动 mouse_filter，避免置 IGNORE 后无人恢复）。
func play_wobble() -> void:
	if Engine.is_editor_hint() and not is_previewing():
		return
	if wobble_sequence.is_empty():
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sync_wobble_config()
	_wobble.play()


## 停止晃动并立即吸附常态角。
func stop_wobble() -> void:
	_wobble.stop()
	rotation_degrees = rest_rotation_degrees
	mouse_filter = _get_restored_mouse_filter()

#endregion


#region 演出收尾

## 一轮晃动完整结束：恢复鼠标过滤并发信号。
func _on_wobble_finished() -> void:
	mouse_filter = _get_restored_mouse_filter()
	if not Engine.is_editor_hint():
		wobble_finished.emit()


func _sync_wobble_config() -> void:
	_wobble.rest_degrees = rest_rotation_degrees
	_wobble.sequence = wobble_sequence
	_wobble.elastic_degrees = elastic_rotation_degrees
	_wobble.segment_duration = animation_duration
	_wobble.transition = animation_transition
	_wobble.ease_type = animation_ease

#endregion


#region 交互输入

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	# 首帧轴心尚未按布局同步，旋转热区会绕 (0, 0) 计算并误命中栏外鼠标。
	if not play_on_mouse_hover or not _is_layout_ready:
		return
	var inside := _is_mouse_inside_panel()
	if inside and not _is_mouse_inside:
		play_wobble()
	_is_mouse_inside = inside


func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if not play_on_click:
		return
	if not (event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _should_play_from_zone_click():
		play_wobble()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if toggle_input_action == &"":
		return
	if event.is_action_pressed(toggle_input_action):
		play_wobble()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if not play_on_click:
		return
	if interaction_control != null:
		# 外部热区模式下原位置检测禁用：面板本体不再是点击触发面（子控件照常自处理）
		return
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		play_wobble()
		accept_event()


## 点击热区是否触发晃动：命中外部热区控件（含子孙）或热区下的空白视为点击热区；
## 面板自身本体（含子控件）不在此触发——空白走 _gui_input，交互子控件自处理不被抢。
func _should_play_from_zone_click() -> bool:
	if not _is_mouse_inside_panel():
		return false
	if interaction_control != null:
		return UIInteraction.is_click_on_zone(self, interaction_control, true)
	return get_viewport().gui_get_hovered_control() == null


## 鼠标是否在面板热区内（含全部子控件）
func _is_mouse_inside_panel() -> bool:
	if not _is_hover_zone_active():
		return false
	# 系统标题栏属于非客户区：离开客户区后不能凭旧坐标维持悬停
	if not _pointer_tracker.is_pointer_in_window:
		return false
	return _get_interaction_rect().has_point(get_global_mouse_position())


## 热区是否参与交互：外部热区跟随热区控件自身可见性；
## 面板晃动全程可见，跟随自身在场景树中的可见性即可。
func _is_hover_zone_active() -> bool:
	if not is_inside_tree():
		return false
	return UIInteraction.zone_active(interaction_control, is_visible_in_tree())


## 悬停/点击热区：指定 interaction_control 时直接用其全局矩形（外部热区）；
## 否则取布局矩形与常态/各停靠角（绕轴心旋转后）包围盒的并集——
## 与当前动画进度无关，各停靠角热区互相覆盖，不因角度差异来回抖动（算法见共享原语）。
func _get_interaction_rect() -> Rect2:
	if interaction_control != null:
		return interaction_control.get_global_rect()
	var pose_angles: Array[float] = [rest_rotation_degrees]
	pose_angles.append_array(wobble_sequence)
	return UIInteraction.pose_zone_rect(self, pose_angles)


## 仅在开启悬停触发时启用每帧检测
func _update_hover_process() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		return
	set_process(play_on_mouse_hover and is_inside_tree())


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
	set_process_input(play_on_click)
	set_process_unhandled_input(toggle_input_action != &"")


func _on_toggle_button_pressed() -> void:
	play_wobble()


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


#region 轴心与初始化

## 等一帧布局定型拿到最终尺寸后，再吸附常态角或播入场晃动。
func _initialize_rotation_state() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_is_layout_ready = true
	_sync_pivot_offset()
	if not is_previewing():
		rotation_degrees = rest_rotation_degrees
	if animate_entrance and not Engine.is_editor_hint():
		play_wobble()


## 就位/动画结束后恢复的鼠标过滤：点击触发需要 STOP 才能收到 _gui_input
func _get_restored_mouse_filter() -> Control.MouseFilter:
	if play_on_click:
		return Control.MOUSE_FILTER_STOP
	return _authored_mouse_filter


## 把 pivot 钉到轴心比例处；旋转全程该点屏幕位置保持不变。
func _sync_pivot_offset() -> void:
	if Engine.is_editor_hint() and not is_previewing():
		return
	var basis_size := size
	if basis_size.x <= 0.0 or basis_size.y <= 0.0:
		basis_size = custom_minimum_size
	pivot_offset = Vector2(
		clampf(origin_ratio.x, 0.0, 1.0) * basis_size.x,
		clampf(origin_ratio.y, 0.0, 1.0) * basis_size.y
	)


## 布局变化后重钉 pivot，避免下次旋转轴心漂移。
func _on_resized() -> void:
	if Engine.is_editor_hint() and not is_previewing():
		return
	_sync_pivot_offset()

#endregion


#region 编辑器单次预览

## 仅在编辑器播放一轮晃动；再次点击从原编辑状态重新开始。
func preview_play() -> void:
	if not Engine.is_editor_hint():
		return
	preview_stop()
	var properties: Array[StringName] = [&"_is_layout_ready", &"_authored_mouse_filter"]
	properties.append_array(AnimationPreview.PRESENTATION_PROPERTIES)
	properties.append_array(AnimationPreview.GEOMETRY_PROPERTIES)
	if not _preview.begin(self, properties, false):
		return
	_preview_run(_preview.generation)


func is_previewing() -> bool:
	return _preview.is_active()


## 保存前和退出树同步恢复；不依赖 Inspector 选择或插件生命周期。
func preview_stop() -> void:
	if not is_previewing():
		return
	_wobble.abort()
	_preview.stop()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		preview_stop()


func _preview_run(token: int) -> void:
	# 等当前布局帧完成；停止或重播后旧轮不能再初始化。
	await get_tree().process_frame
	if not _preview.is_current(token) or not is_inside_tree():
		return
	visible = true
	_authored_mouse_filter = mouse_filter
	_is_layout_ready = true
	_sync_pivot_offset()
	rotation_degrees = rest_rotation_degrees
	var segment_count := maxi(1, wobble_sequence.size() + 1)
	var total_timeout := segment_count * (animation_duration + 2.0)
	play_wobble()
	while _preview.is_current(token) and is_wobbling():
		if not await _preview.wait_tween(
				self, _wobble.get_active_tween(), token, total_timeout):
			break
	if _preview.is_current(token):
		preview_stop()

#endregion
