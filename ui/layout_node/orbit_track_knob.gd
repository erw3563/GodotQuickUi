@tool
class_name OrbitTrackKnob
extends Control
## 旋钮环形轨道：把直接 Control 子节点均匀排列在环形轨道上，并让轨道停在离散档位上。
## 档位数量由子控件数量决定：第 i 个档位对应第 i 个子控件，档位角把该子控件转到
## 基准槽位（slot_start_angle 指向的槽位，默认环顶）。
## 轨道静止在档位上；按住鼠标在拨盘环带内（环心盲区与抓取半径之间）沿圆周拖动时
## 跟随指针转动，每转进一个档位就发出 detent_changed（该档位对应的子控件），
## 松手后补间归到当前圈内最近的档位。
## 子控件相对轨道保持直立，隐藏的 Control 仍占档位，非 Control 子节点不参与排列。
## 节点不自转，输入全部来自拨盘拖动；调用方负责创建、挂载和释放自己的子节点。

## 轨道转进新档位时发出，参数为该档位对应的直接 Control 子控件。
## 拖动跨档、set_detent_control()、子控件增删引起的档位变化都会发出；
## 停在原档位不重复发出，轨道清空子控件时以 null 播报。
signal detent_changed(detent_control: Control)

## 椭圆 X / Y 半径（像素）。相等时为圆形；零分量可表达线形或点形轨道。
@export var orbit_radii := Vector2(160.0, 160.0):
	set(value):
		orbit_radii = Vector2(maxf(value.x, 0.0) if is_finite(value.x) else 0.0,
			maxf(value.y, 0.0) if is_finite(value.y) else 0.0)
		if is_node_ready():
			reset_motion()
## 沿轨道移动的相位。Control.rotation 控制椭圆固定朝向。
@export var orbit_phase := 0.0:
	set(value):
		orbit_phase = value if is_finite(value) else 0.0
		if is_node_ready():
			relayout_slots()
## 基准槽位角（默认 -90° 即环的正上方）：档位角把该档位对应的子控件转到该角。
@export var slot_start_angle := -PI / 2.0:
	set(value):
		slot_start_angle = value if is_finite(value) else 0.0
		if is_node_ready(): reset_motion()

@export_group("运动倾斜")
## 按速度水平分量倾斜；与弹簧独立组合，默认关。
@export var motion_lean_enabled := false:
	set(value):
		motion_lean_enabled = value
		if is_node_ready(): reset_motion()
@export_range(0.0, 90.0, 0.1) var lean_max_degrees := 15.0
## 每 px/s 水平速度对应的倾角（度）；负值反向。
@export var lean_velocity_scale := 0.035

@export_group("惯性弹簧")
## 加速度驱动的有限惯性偏移与旋转，默认关；理想椭圆与相位独立持有。
@export var spring_enabled := false:
	set(value):
		spring_enabled = value
		if is_node_ready(): reset_motion()
@export_range(0.1, 20.0, 0.1) var spring_frequency_hz := 2.2
@export_range(0.02, 3.0, 0.01) var spring_damping_ratio := 0.32
@export_range(0.0, 3.0, 0.01) var spring_inertia := 1.0
@export_range(0.0, 1000.0, 1.0) var spring_max_offset_pixels := 48.0
@export_range(0.0, 90.0, 0.1) var spring_max_rotation_degrees := 12.0

@export_group("拨盘拖动")
## 是否启用鼠标拨盘拖动；关闭时中断进行中的拨动与归位补间。
@export var rotary_drag_enabled := true:
	set(value):
		rotary_drag_enabled = value
		if is_node_ready():
			if not rotary_drag_enabled:
				_cancel_rotary_interaction()
			_sync_processing()
## 触发拨盘拖动的鼠标按键。
@export var rotary_mouse_button: MouseButton = MOUSE_BUTTON_LEFT
## 指针距环心小于该半径（像素）时按下才开始拨动（含压在子控件上）；拨动开始后不再受半径限制。
@export var rotary_grab_radius_pixels := 240.0
## 环心盲区半径（像素）：距环心小于该值的按压不起拨。
@export var rotary_hub_radius_pixels := 40.0

@export_group("档位归位")
## 松手归位补间时长（秒）；取 0 时立即落位。
@export_range(0.0, 3.0, 0.01) var detent_snap_duration_seconds := 0.18
## 归位补间过渡类型。
@export var detent_snap_transition: Tween.TransitionType = Tween.TRANS_CUBIC
## 归位补间缓动类型。
@export var detent_snap_ease: Tween.EaseType = Tween.EASE_OUT

## 可选运行时起拨裁决，由组装方注入；未设置时保持通用拨盘语义。
## 参数为视口坐标的按键事件，轨道不认识业务对象。
var rotary_drag_filter: Callable

var _watched_controls: Array[Control] = []
var _motion := OrbitMotion.new()
var _rotary_dragging := false
var _rotary_pointer_angle := 0.0
var _snap_tween: Tween
## 最近播报过的档位子控件。
var _detent_control: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset_ratio = Vector2.ZERO
	pivot_offset = size * 0.5
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)
	# 编辑器内保留作者摆放的轨道角度，运行时把轨道对到最近的档位。
	if not Engine.is_editor_hint():
		orbit_phase = get_nearest_detent_angle()
	relayout_slots()
	_sync_processing()
	# 子控件的就绪早于本节点，就绪时的当前档位作为播报基准。
	_detent_control = get_current_detent_control()


func _process(delta: float) -> void:
	_advance_motion(delta)
	relayout_slots()


func _notification(what: int) -> void:
	if what == NOTIFICATION_CHILD_ORDER_CHANGED:
		_ensure_control_resize_listeners()
		_refresh_detents()


func _exit_tree() -> void:
	_rotary_dragging = false
	_motion.reset()
	_kill_snap_tween()


## 拨盘输入统一走 _input（GUI 处理之前，不可被消费拦截）：抓取半径内的按压即刻起拨，
## 组合交互由 rotary_drag_filter 裁决；跟手与松手同样在 GUI 之前。
## 全程使用事件自身坐标（派发时已换算到本画布空间），不读视口鼠标位。
func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	var button_event := event as InputEventMouseButton
	if button_event != null and button_event.button_index == rotary_mouse_button:
		if button_event.pressed:
			_try_begin_rotary_drag(button_event)
		elif _rotary_dragging:
			_end_rotary_drag()
		return
	if not _rotary_dragging:
		return
	var motion_event := event as InputEventMouseMotion
	if motion_event != null:
		_track_rotary_pointer(_canvas_position(motion_event.position))


## 按压起拨判定：启用、可见、未在拨动且指针落在拨盘环带内（盲区 < 距环心 ≤ 抓取半径）。
func _try_begin_rotary_drag(button_event: InputEventMouseButton) -> void:
	if Engine.is_editor_hint():
		return
	if not rotary_drag_enabled or not is_visible_in_tree() or _rotary_dragging:
		return
	if rotary_drag_filter.is_valid() and not rotary_drag_filter.call(button_event):
		return
	var to_center := _canvas_position(button_event.position) - get_track_center_global()
	var center_distance := to_center.length()
	if center_distance > rotary_grab_radius_pixels or center_distance < rotary_hub_radius_pixels:
		return
	_begin_rotary_drag(to_center.angle())


## 当前是否处于拨盘拖动中（按住跟手阶段，不含归位补间）。
func is_rotary_dragging() -> bool:
	return _rotary_dragging


## 单档位角距（弧度）：整圈按子控件数量均分；轨道上没有子控件时为整圈。
func get_detent_step() -> float:
	var detent_count := get_orbit_control_count()
	if detent_count == 0:
		return TAU
	return TAU / float(detent_count)


## 当前档位对应的子控件；轨道上没有子控件时为 null。
func get_current_detent_control() -> Control:
	var orbit_controls := get_orbit_controls()
	if orbit_controls.is_empty():
		return null
	return orbit_controls[_current_detent_index(orbit_controls.size())]


## 与当前 orbit_phase 最近的档位角（绝对角，保留圈数）：多圈拖动只退到最近的档位。
func get_nearest_detent_angle() -> float:
	if get_orbit_control_count() == 0:
		return orbit_phase
	return roundf(orbit_phase / get_detent_step()) * get_detent_step()


## 归位补间是否进行中。
func is_detent_snapping() -> bool:
	return _snap_tween != null and is_instance_valid(_snap_tween)


## 转到指定子控件所在的档位：取当前圈内离 orbit_phase 最近的同档位角，animated 为 false
## 时立即落位。目标档位一经确定即按子控件变化播报；目标不是本轨道的直接子控件时告警忽略。
func set_detent_control(control: Control, animated := true) -> void:
	if control == null:
		push_warning("OrbitTrackKnob 设档：目标为空，已忽略。")
		return
	var orbit_controls := get_orbit_controls()
	var detent_index := orbit_controls.find(control)
	if detent_index < 0:
		push_warning("OrbitTrackKnob 设档：目标不是本轨道的直接子控件，已忽略。")
		return
	var target := _detent_angle_near_phase(detent_index, orbit_controls.size())
	_kill_snap_tween()
	if animated:
		_rotate_to_detent(target)
	else:
		_rotate_to_detent_now(target)
	_announce_detent_control(control)


## 把当前子控件按枚举序 k/n 均匀摆上环形轨道，并反向旋转抵消轨道旋转（子控件保持直立）。
func relayout_slots() -> void:
	var orbit_controls := get_orbit_controls()
	var slot_count := orbit_controls.size()
	if slot_count == 0:
		return
	var track_center := size * 0.5
	for slot_index in slot_count:
		var control := orbit_controls[slot_index]
		var angle := orbit_phase + slot_start_angle + TAU * float(slot_index) / float(slot_count)
		var slot_center := track_center + Vector2(cos(angle), sin(angle)) * orbit_radii
		# 反向旋转必须绕控件中心，否则不同尺寸控件的实际显示中心会偏离轨道槽位。
		control.pivot_offset_ratio = Vector2.ZERO
		control.pivot_offset = control.size * 0.5
		control.rotation = -rotation
		control.position = slot_center - control.size * 0.5 + _motion.get_offset(control)
		control.rotation += _motion.get_rotation(control)


## 理想槽位中心（轨道局部坐标），由椭圆半径、相位与槽位序号计算。
func get_slot_center(slot_index: int, slot_count: int = -1) -> Vector2:
	if slot_count < 0:
		slot_count = get_orbit_control_count()
	if slot_count <= 0:
		return size * 0.5
	var angle := orbit_phase + slot_start_angle + TAU * float(slot_index) / float(slot_count)
	return size * 0.5 + Vector2(cos(angle), sin(angle)) * orbit_radii


## 当前直接 Control 子节点，按场景树顺序返回。排除已 queue_free 等待释放的节点：
## 全量重建的旧档位临死前一帧不再占位，避免把幽灵子控件计入档位与排列。
func get_orbit_controls() -> Array[Control]:
	var orbit_controls: Array[Control] = []
	for child in get_children():
		var control := child as Control
		if control != null and is_instance_valid(control) \
				and not control.is_queued_for_deletion():
			orbit_controls.append(control)
	return orbit_controls


## 当前直接 Control 子节点数量，即档位数量。
func get_orbit_control_count() -> int:
	return get_orbit_controls().size()


## 环形轨道圆心（矩形中心）的全局坐标；旋转绕中心枢轴，圆心在旋转中保持不动。
func get_track_center_global() -> Vector2:
	return get_global_transform() * (size * 0.5)


## 子控件增删后重算档位：交互空闲时把轨道对到新网格上最近的档位（编辑器内保留作者摆放
## 的角度），重排槽位，并按当前档位子控件的变化播报。
func _refresh_detents() -> void:
	if not Engine.is_editor_hint() and not _rotary_dragging and not is_detent_snapping():
		orbit_phase = get_nearest_detent_angle()
	relayout_slots()
	_sync_processing()
	_announce_current_detent()


## 拖动跟手后立即重排并按新档位播报：信号回调里读到的槽位与 orbit_phase 同步。
func _track_rotary_pointer(pointer_canvas_position: Vector2) -> void:
	var pointer_angle := (pointer_canvas_position - get_track_center_global()).angle()
	orbit_phase += angle_difference(_rotary_pointer_angle, pointer_angle)
	_rotary_pointer_angle = pointer_angle
	relayout_slots()
	_announce_current_detent()


## 松手归位：转到当前圈内最近的档位角。
func _start_detent_snap_if_needed() -> void:
	# 拖动中增删子控件时落点档位此刻才确定，先按落点播报再转动。
	_announce_current_detent()
	_rotate_to_detent(get_nearest_detent_angle())


## 按当前 orbit_phase 归属的档位播报；档位子控件变化时发出信号。
func _announce_current_detent() -> void:
	_announce_detent_control(get_current_detent_control())


func _announce_detent_control(control: Control) -> void:
	if control == _detent_control:
		return
	_detent_control = control
	detent_changed.emit(control)


## orbit_phase 归属的档位序号：顺时针拖动时轨道角增大，序号沿子控件顺序递减。
func _current_detent_index(detent_count: int) -> int:
	return posmod(-roundi(orbit_phase / (TAU / float(detent_count))), detent_count)


## 档位序号在当前圈内的绝对角：与 orbit_phase 的差落在半档以内。
func _detent_angle_near_phase(detent_index: int, detent_count: int) -> float:
	var detent_angle := -float(posmod(detent_index, detent_count)) * (TAU / float(detent_count))
	return detent_angle + roundf((orbit_phase - detent_angle) / TAU) * TAU


## 转到目标档位角：已经在该角上时不启动补间；补间时长取 0 或节点未入树时立即落位。
func _rotate_to_detent(target_angle: float) -> void:
	if is_equal_approx(orbit_phase, target_angle):
		return
	if detent_snap_duration_seconds <= 0.0 or not is_inside_tree():
		_rotate_to_detent_now(target_angle)
		return
	_start_detent_tween(target_angle)


func _rotate_to_detent_now(target_angle: float) -> void:
	orbit_phase = target_angle
	relayout_slots()
	_sync_processing()


func _start_detent_tween(target_angle: float) -> void:
	_snap_tween = create_tween()
	_snap_tween.set_trans(detent_snap_transition).set_ease(detent_snap_ease)
	_snap_tween.finished.connect(_on_detent_snap_finished)
	_snap_tween.tween_property(self, "orbit_phase", target_angle, detent_snap_duration_seconds)


## 归位补间结束：复位补间状态，按最终角度重排一次（补间末帧与本节点 _process 的顺序不保证）。
func _on_detent_snap_finished() -> void:
	_snap_tween = null
	relayout_slots()
	_sync_processing()


func _kill_snap_tween() -> void:
	if _snap_tween != null and is_instance_valid(_snap_tween):
		_snap_tween.kill()
	_snap_tween = null


## 关闭拨盘时中断进行中的拨动与归位补间，不留悬挂状态。
func _cancel_rotary_interaction() -> void:
	_rotary_dragging = false
	_kill_snap_tween()


## 把当前子控件的 resized 信号接到重排上：控件自身尺寸变化（非增删）时也重新收敛。
func _ensure_control_resize_listeners() -> void:
	for previous in _watched_controls:
		if is_instance_valid(previous) and previous.get_parent() != self:
			if previous.resized.is_connected(_on_control_resized):
				previous.resized.disconnect(_on_control_resized)
	_watched_controls = get_orbit_controls()
	for control in _watched_controls:
		if not control.resized.is_connected(_on_control_resized):
			control.resized.connect(_on_control_resized)


func _on_control_resized() -> void:
	relayout_slots()


func _on_resized() -> void:
	pivot_offset_ratio = Vector2.ZERO
	pivot_offset = size * 0.5
	relayout_slots()


func _begin_rotary_drag(pointer_angle: float) -> void:
	_kill_snap_tween()
	_rotary_dragging = true
	_rotary_pointer_angle = pointer_angle
	_sync_processing()


func _end_rotary_drag() -> void:
	_rotary_dragging = false
	_start_detent_snap_if_needed()
	_sync_processing()


## 视口坐标 → 本画布空间坐标。
func _canvas_position(viewport_position: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * viewport_position


## 帧循环开关：拖动或归位补间进行时保持 _process 运行，其余交给通知与显式调用重排。
## 编辑器空闲态保持静止。
func _sync_processing() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		return
	set_process(spring_enabled or motion_lean_enabled or _rotary_dragging or is_detent_snapping())


## 清除速度导数/弹簧/倾斜历史，立即回到理想位置。用于传送、重新绑定与手动复位。
func reset_motion() -> void:
	_motion.reset()
	if is_inside_tree():
		relayout_slots()
		_sync_processing()


func _advance_motion(delta: float) -> void:
	if Engine.is_editor_hint() or not (spring_enabled or motion_lean_enabled):
		return
	_motion.step(self, get_orbit_controls(), delta)
