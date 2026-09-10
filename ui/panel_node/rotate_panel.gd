@tool
class_name RotatePanel
extends PanelContainer
## 旋转面板：触发（按键/按钮/点击/热区）直接连播完整序列
## 常态→目标1→目标2→目标3→常态，一段接一段播完收在常态角，不是一次只走一步；
## 播放中再次触发从头重播。目标角符号自定，一套配置即可同时拥有顺时针与
## 逆时针的旋转动画。rotate_to_rest()/rotate_to_pose(n) 可中断序列直达姿态。
## 弹性角度：每段到达目标角后沿行进方向继续多转弹性角度，再回弹收在目标角。
## 所有权契约：只驱动自身的 rotation / pivot_offset，不改 scale / modulate.a /
## size / position，真实布局全程不变；与 ZoomPanel（驱动缩放）互不冲突，
## 嵌套包裹即得「放大 + 旋转」的合成演出——外层旋转、内层缩放，
## 各自只动自己的属性。旋转绕 origin_ratio 钉扎的轴心进行，全程该点屏幕位置不动。
## mouse_filter 仅在旋转动画期间临时改为 IGNORE 放行鼠标穿透、结束后恢复；
## visible 仅在首帧布局采样期间临时隐藏防闪现，初始化后恢复并不再触碰。
## 鼠标交互对齐 ZoomPanel：悬停连播（play_on_mouse_hover，进入热区连播一次序列，
## 移出不打断、播完收常态，再次进入重播）、点击切换（toggle_on_click，
## 本体空白与热区点击连播序列）、外部热区（interaction_control）；
## 差异在于目标姿态下面板仍可见可点——本体空白点击经 _gui_input 触发，
## 子控件（按钮等）照常自处理不被抢。

signal pose_changed(pose_index: int)
signal rotate_finished(pose_index: int)

@export_group("动画预览")
@export_tool_button("播放一次", "Play") var preview_play_action: Callable = preview_play
@export_tool_button("停止并恢复", "Stop") var preview_stop_action: Callable = preview_stop

@export_group("旋转")
## 旋转轴心在面板内的比例坐标（0~1；默认正中心，四角可设 0/1）
@export var origin_ratio: Vector2 = Vector2(0.5, 0.5):
	set(value):
		origin_ratio = value
		if _is_layout_ready:
			_sync_pivot_offset()

## 常态角度（度）：静息归宿——序列起点与终点、入场动画终点、悬停目标；
## 静息在常态时改角即刻吸附
@export_range(-1080.0, 1080.0, 0.1, "degrees") var rest_rotation_degrees: float = 0.0:
	set(value):
		rest_rotation_degrees = value
		if _is_layout_ready and pose_index == 0 and not is_rotating:
			rotation_degrees = value

## 目标角度1（度）：序列第一停靠姿态；负角逆时针、正角顺时针
@export_range(-1080.0, 1080.0, 0.1, "degrees") var target_rotation_1: float = -25.0:
	set(value):
		target_rotation_1 = value
		if _is_layout_ready and pose_index == 1 and not is_rotating:
			rotation_degrees = value

## 目标角度2（度）：序列第二停靠姿态
@export_range(-1080.0, 1080.0, 0.1, "degrees") var target_rotation_2: float = 25.0:
	set(value):
		target_rotation_2 = value
		if _is_layout_ready and pose_index == 2 and not is_rotating:
			rotation_degrees = value

## 目标角度3（度）：序列第三停靠姿态；设 360 即整圈旋转
@export_range(-1080.0, 1080.0, 0.1, "degrees") var target_rotation_3: float = 180.0:
	set(value):
		target_rotation_3 = value
		if _is_layout_ready and pose_index == 3 and not is_rotating:
			rotation_degrees = value

## 弹性角度（度）：每段到达目标角后沿行进方向继续多转的角度，再回弹收在目标角；
## 0 = 不回弹（每段单程动画）；已停在目标角时仍会朝正向原地回弹一次
@export_range(0.0, 360.0, 0.1, "degrees") var elastic_rotation_degrees: float = 0.0

## 初始是否停在常态角（false 则直接停在目标角度1）
@export var start_at_rest: bool = true

## 入场起始角（度）：入场动画从该角转往常态角
@export_range(-1080.0, 1080.0, 0.1, "degrees") var entrance_start_degrees: float = -25.0

## 初始停在常态时是否播旋转入场动效（false 则直接就位）
@export var animate_entrance: bool = true

## 单段旋转动画时长（秒）；弹性回弹时该段按 70%/30% 分给去程与回程
@export_range(0.0, 2.0, 0.01) var animation_duration: float = 0.25

## 动画过渡类型（默认 BACK 配 EASE_OUT：越过目标过冲再恰好收敛）
@export var animation_transition: Tween.TransitionType = Tween.TRANS_BACK

## 转往常态的缓动类型（转往目标固定用 EASE_IN 加速离开）
@export var animation_ease: Tween.EaseType = Tween.EASE_OUT

@export_group("交互")
## 用于连播序列的 InputMap 动作名（留空则不响应按键）
@export var toggle_input_action: StringName = &"":
	set(value):
		toggle_input_action = value
		_update_input_process()

## 可选：绑定按钮连播序列
@export var toggle_button: BaseButton:
	set(value):
		_disconnect_toggle_button()
		toggle_button = value
		_connect_toggle_button()

## 鼠标进入热区时连播一次序列（边沿触发：在热区内停留不重复起播）；
## 移出不打断，播完收在常态角，再次进入重播
## （热区=布局矩形与各姿态角旋转包围盒的并集）
@export var play_on_mouse_hover: bool = false:
	set(value):
		play_on_mouse_hover = value
		_update_hover_process()

## 点击切换：常态下点热区内连播序列（面板本体空白走 _gui_input，交互子控件不被抢）；
## 目标姿态下点热区空白或栏外空白区域回到上次目标姿态（常态的「收起」对应物）
@export var toggle_on_click: bool = false:
	set(value):
		toggle_on_click = value
		_update_input_process()

## 可选：外部热区控件（设置后检测区域完全以该控件全局矩形为准，禁用面板原位置检测；
## 可摆在面板外任意位置；其自身或祖先隐藏时热区不生效；）
@export var interaction_control: Control

## 当前停靠姿态：0=常态，1~3=目标角度n；序列播放中为当前段的目标姿态
var pose_index: int = 0:
	set(value):
		var clamped := clampi(value, 0, 3)
		if pose_index == clamped:
			return
		pose_index = clamped
		if clamped >= 1:
			_last_target_pose = clamped
		if not Engine.is_editor_hint():
			pose_changed.emit(clamped)
		if _is_layout_ready:
			_apply_rotation(true)

## 是否正在播放旋转动画（序列段与段之间同帧衔接，不会漏出空闲帧）
var is_rotating: bool:
	get:
		return _rotation_tween != null and _rotation_tween.is_running()

var _rotation_tween: Tween
var _is_layout_ready: bool = false
## 连播序列待停靠姿态队列（play_sequence 填充，每段结束续播）
var _sequence_queue: Array[int] = []
## 悬停离开/栏外点击要回去的上次目标姿态
var _last_target_pose: int = 1
## 上一帧鼠标是否在热区内（悬停连播的边沿触发状态）
var _is_mouse_inside: bool = false
## 场景中配置的鼠标过滤；动画期间临时改为 IGNORE，结束后恢复
var _authored_mouse_filter: Control.MouseFilter = Control.MOUSE_FILTER_STOP
## 鼠标是否仍在窗口客户区内
var _is_pointer_in_window: bool = true


func _ready() -> void:
	if Engine.is_editor_hint():
		_update_input_process()
		return
	_authored_mouse_filter = mouse_filter
	# 布局采样前先隐藏并落起始角，避免入场动画开始前闪现常态或绕错轴心渲染。
	if not (start_at_rest and not animate_entrance):
		visible = false
		rotation_degrees = entrance_start_degrees if start_at_rest else _pose_angle(1)
	pose_index = 0 if start_at_rest else 1
	_connect_toggle_button()
	_connect_window_mouse_tracking()
	_update_input_process()
	_update_hover_process()
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)
	call_deferred("_initialize_rotation_state")


func _exit_tree() -> void:
	preview_stop()
	_disconnect_toggle_button()
	_disconnect_window_mouse_tracking()
	_kill_rotation_tween()
	_sequence_queue.clear()


#region 公开接口

## 直接连播完整序列：常态→目标1→目标2→目标3→常态；
## 不在常态时先转回常态再从头播；播放中再次触发从头重播。
func play_sequence() -> void:
	_sequence_queue = [1, 2, 3, 0]
	if pose_index != 0:
		_sequence_queue.push_front(0)
	pose_index = _sequence_queue.pop_front()


## 打断序列转回常态角
func rotate_to_rest() -> void:
	_sequence_queue.clear()
	pose_index = 0


## 打断序列转到指定姿态（0=常态，1~3=目标角度n；越界钳回 0~3）
func rotate_to_pose(next_pose: int) -> void:
	_sequence_queue.clear()
	pose_index = next_pose

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
		play_sequence()
	_is_mouse_inside = inside


func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if not toggle_on_click:
		return
	if not (event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if pose_index == 0:
		# 常态下：点栏外空白回到上次目标姿态；点外部热区控件本体连播序列
		if _should_leave_rest_from_outside_click():
			rotate_to_pose(_last_target_pose)
			get_viewport().set_input_as_handled()
			return
		if _should_play_from_zone_click():
			play_sequence()
			get_viewport().set_input_as_handled()
		return
	# 目标姿态下点热区连播序列；但点在面板本体或其子控件上时不抢——
	# 本体空白交给 _gui_input 触发，按钮等交互子控件自处理（倾斜态面板仍可见可点）；
	# 热区上的其它外部按钮同样不抢（与栏外空白判定的排除一致）。
	if not _is_mouse_inside_panel():
		return
	var hovered_control := get_viewport().gui_get_hovered_control()
	if hovered_control != null and (
			hovered_control == self or is_ancestor_of(hovered_control)):
		return
	if hovered_control is BaseButton:
		return
	play_sequence()
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if toggle_input_action == &"":
		return
	if event.is_action_pressed(toggle_input_action):
		play_sequence()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if not toggle_on_click:
		return
	if interaction_control != null:
		# 外部热区模式下原位置检测禁用：面板本体不再是点击触发面（子控件照常自处理）
		return
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		play_sequence()
		accept_event()


## 是否为「栏外空白」点击（外部切换按钮等交互控件除外）
func _should_leave_rest_from_outside_click() -> bool:
	if _is_mouse_inside_panel():
		return false
	var hovered_control := get_viewport().gui_get_hovered_control()
	if hovered_control == null:
		return true
	# 点在本面板内（含子控件）时不离开常态
	if hovered_control == self or is_ancestor_of(hovered_control):
		return false
	# 外部切换按钮交给按钮自己处理，避免先离场再被按钮重新拉起
	if toggle_button != null and (
			hovered_control == toggle_button \
			or toggle_button.is_ancestor_of(hovered_control)):
		return false
	# 其它外部按钮视为非空白，不抢点击
	if hovered_control is BaseButton:
		return false
	return true


## 常态下点击热区本体是否连播：命中外部热区控件（含子孙）或 IGNORE 热区下的空白
## 视为点击热区（面板自身的空白仍走 _gui_input）；热区上的其它交互控件不抢。
func _should_play_from_zone_click() -> bool:
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


## 热区是否参与交互：外部热区跟随热区控件自身可见性；面板各姿态均可见，
## 跟随自身在场景树中的可见性即可（区别于 ZoomPanel 收起自隐藏的祖先兜底判定）。
func _is_hover_zone_active() -> bool:
	if not is_inside_tree():
		return false
	if interaction_control != null:
		return interaction_control.is_visible_in_tree()
	return is_visible_in_tree()


## 悬停/点击热区：指定 interaction_control 时直接用其全局矩形（外部热区）；
## 否则取布局矩形与常态/三目标各姿态角（绕轴心旋转后）包围盒的并集。
## 与当前动画进度无关，各姿态热区互相覆盖，不因姿态差异来回抖动。
func _get_interaction_rect() -> Rect2:
	if interaction_control != null:
		return interaction_control.get_global_rect()
	var corners: Array[Vector2] = []
	_append_pose_corners(corners, rest_rotation_degrees)
	_append_pose_corners(corners, target_rotation_1)
	_append_pose_corners(corners, target_rotation_2)
	_append_pose_corners(corners, target_rotation_3)
	var result := Rect2(corners[0], Vector2.ZERO)
	for corner in corners:
		result = result.expand(corner)
	return result


## 把面板四角变换到指定姿态角（在当前全局变换上绕轴心补转角度差），
## 收集角点供热区取包围盒；对当前姿态角即精确还原布局矩形。
func _append_pose_corners(corners: Array[Vector2], pose_degrees: float) -> void:
	var xf := get_global_transform()
	var delta := deg_to_rad(pose_degrees) - rotation
	var pivot_global := xf * pivot_offset
	for corner in [Vector2.ZERO, Vector2(size.x, 0.0), Vector2(0.0, size.y), size]:
		corners.append(pivot_global + (xf * corner - pivot_global).rotated(delta))


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


## 仅在开启悬停连播时启用每帧检测
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
	set_process_input(toggle_on_click)
	set_process_unhandled_input(toggle_input_action != &"")


func _on_toggle_button_pressed() -> void:
	play_sequence()


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


#region 旋转与动画

## 姿态角查找：0=常态，1~3=目标角度n
func _pose_angle(index: int) -> float:
	match index:
		1:
			return target_rotation_1
		2:
			return target_rotation_2
		3:
			return target_rotation_3
		_:
			return rest_rotation_degrees


## 等一帧布局定型拿到最终尺寸后，再按初始状态就位或播入场动效。
func _initialize_rotation_state() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_is_layout_ready = true
	_apply_rotation(start_at_rest and animate_entrance)


## 就位/动画结束后恢复的鼠标过滤：点击切换需要 STOP 才能收到 _gui_input
func _get_restored_mouse_filter() -> Control.MouseFilter:
	if toggle_on_click:
		return Control.MOUSE_FILTER_STOP
	return _authored_mouse_filter


## 按当前姿态就位或播放旋转动画；面板各姿态均可见，就位即恢复显示。
func _apply_rotation(animate: bool) -> void:
	if Engine.is_editor_hint() and not is_previewing():
		return
	if not is_inside_tree():
		return
	_sync_pivot_offset()
	visible = true
	var target := _pose_angle(pose_index)
	var needs_animation := absf(rotation_degrees - target) > 0.05 \
			or elastic_rotation_degrees > 0.0
	if animate and animation_duration > 0.0 and needs_animation:
		_animate_rotation(target)
		return
	_kill_rotation_tween()
	_settle_rotation()


## 播放单段旋转动画：单程直达目标；配置弹性角度时先转到目标外的过冲角
## （沿行进方向多转弹性角度，占时长 70%），再以 CUBIC/EASE_OUT 回弹收在目标角（30%）。
func _animate_rotation(target_degrees: float) -> void:
	_kill_rotation_tween()
	# 动画期间不吞点击，结束后恢复。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var start_degrees := rotation_degrees
	_rotation_tween = create_tween()
	_rotation_tween.set_trans(animation_transition)
	_rotation_tween.set_ease(animation_ease if pose_index == 0 else Tween.EASE_IN)
	if elastic_rotation_degrees <= 0.0:
		_rotation_tween.set_parallel(true)
		_rotation_tween.tween_method(
			_set_rotation_degrees, start_degrees, target_degrees, animation_duration
		)
		_rotation_tween.chain().tween_callback(_on_rotation_animation_finished)
		return
	var delta := target_degrees - start_degrees
	# 角度差在浮点误差内视为原地回弹，按约定朝正向弹出（signf(0 附近的负 epsilon) 会随机反向）
	var direction := 1.0 if absf(delta) < 0.05 else signf(delta)
	var overshoot_degrees := target_degrees + direction * elastic_rotation_degrees
	_rotation_tween.tween_method(
		_set_rotation_degrees, start_degrees, overshoot_degrees, animation_duration * 0.7
	)
	_rotation_tween.tween_method(
		_set_rotation_degrees, overshoot_degrees, target_degrees, animation_duration * 0.3
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_rotation_tween.chain().tween_callback(_on_rotation_animation_finished)


func _set_rotation_degrees(value: float) -> void:
	rotation_degrees = value


## 动画结束回调：段结束就位并续播。
func _on_rotation_animation_finished() -> void:
	_rotation_tween = null
	_settle_rotation()


## 单段就位收尾：角度精确落位、恢复鼠标过滤、发 rotate_finished；
## 序列队列非空时同帧续播下一段（段与段之间无空闲帧）。
func _settle_rotation() -> void:
	rotation_degrees = _pose_angle(pose_index)
	mouse_filter = _get_restored_mouse_filter()
	if not Engine.is_editor_hint():
		rotate_finished.emit(pose_index)
	if _sequence_queue.is_empty():
		return
	pose_index = _sequence_queue.pop_front()


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


func _kill_rotation_tween() -> void:
	if _rotation_tween != null and _rotation_tween.is_valid():
		_rotation_tween.kill()
	_rotation_tween = null

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
	var properties: Array[StringName] = [
		&"_is_layout_ready", &"_authored_mouse_filter", &"_last_target_pose",
		&"_sequence_queue", &"pose_index",
	]
	properties.append_array(_PREVIEW_PRESENTATION)
	properties.append_array(_PREVIEW_GEOMETRY)
	if not _preview_begin(properties, false):
		return
	_preview_run(_preview_generation)


func is_previewing() -> bool:
	return _preview_active


## 保存前和退出树同步恢复；不依赖 Inspector 选择或插件生命周期。
func preview_stop() -> void:
	if not is_previewing():
		return
	_preview_active = false
	_kill_rotation_tween()
	_sequence_queue.clear()
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
	_authored_mouse_filter = mouse_filter
	_sequence_queue.clear()
	pose_index = 0
	rotation_degrees = rest_rotation_degrees
	_is_layout_ready = true
	_sync_pivot_offset()
	play_sequence()
	while _preview_is_current(token) and is_rotating:
		if not await _preview_wait_tween(_rotation_tween, token, animation_duration + 2.0):
			break
	if _preview_is_current(token):
		preview_stop()

#endregion
