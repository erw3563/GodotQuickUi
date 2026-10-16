@tool
class_name OrbitTrack
extends Control
## 通用环形排列节点：按直接 Control 子节点的顺序均匀排列，并支持整体自转。
## 管理子节点的位置、旋转与中心枢轴，不修改尺寸；子节点相对轨道保持直立。
## 隐藏的 Control 仍占槽位，非 Control 子节点不参与排列。
## 不依赖业务数据；调用方负责创建、挂载和释放自己的子节点。
## 可选拨盘拖动：在拨盘环带内（环心盲区与抓取半径之间）按住鼠标沿圆周拨动，
## 轨道像老式电话拨号盘一样跟随指针旋转（支持多圈），松手后可补间回正到拨动开始
## 的角度。环带内压在子控件上同样起拨，交互控件应布置在环带外。
## 可选发牌动画：play_deal_animation() 让全部子控件先隐藏并移到环心，
## 再按起播模式（错峰/齐发）依次或同时飞回各自槽位（播放前就隐藏的子控件
## 占位但不显形）。
## 单个子控件可单独入场：play_entrance_animation(control) 让该控件从环心飞到
## 当前槽位，不影响其它子控件；entrance_on_child_added 可让运行时新加入的
## 子控件自动播放入场。

## 发牌动画全部物品落位后发出（空轨道起播也立即发，等待语义一致）。
signal deal_finished
## 全批已到中心；此信号回调可以安全中断或重启。
signal transfer_gathered
## 当前汇聚与发牌操作自然完成时发出。
signal transfer_finished

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
## 自转角速度（弧度/秒）。
@export var rotation_speed := 0.5
## 首槽位角度（默认 -90° 即环的正上方）。
@export var slot_start_angle := -PI / 2.0:
	set(value):
		slot_start_angle = value if is_finite(value) else 0.0
		if is_node_ready(): reset_motion()
## 是否持续自转；暂停后子控件停在当前角度。
@export var auto_spin := true:
	set(value):
		auto_spin = value
		if is_node_ready():
			_sync_processing()

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
## 是否启用鼠标拨盘拖动：按住后轨道跟随指针绕环心旋转，松手后可选回正。
@export var rotary_drag_enabled := false:
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
## 环心盲区半径（像素）：距环心小于该值的按压不起拨——对应老式拨号盘固定的中心帽，
## 也避开环心处指针角不可靠的问题（交互控件可布置在盲区内）。
@export var rotary_hub_radius_pixels := 40.0
## 松手后是否补间转回拨动开始时的角度。
@export var snap_back_on_release := false
## 回正补间基准时长（秒）：按角距比例换算时，每 π 弧度角距耗时此值。
@export var snap_back_duration_seconds := 0.7
## 为 true 时回正恒定使用基准时长，不随角距伸缩。
@export var snap_back_fixed_duration := false
## 回正死区（度）：松手时与回正目标的角距小于该值则不再补间。
@export_range(0, 360) var snap_back_dead_zone_degrees := 15.0

@export_group("布局切换")
## transfer_controls 的整批汇聚时长；0 或 animated=false 立即采用最终排布。
@export_range(0.0, 5.0, 0.01) var transfer_duration_seconds := 0.6

@export_group("发牌动画")
## 发牌起播模式。
enum DealLaunchMode {
	## 按枚举序错峰起播：第 k 个子控件的起播时刻 = k × 错峰间隔。
	STAGGERED,
	## 齐发：全部子控件同时起飞（忽略错峰间隔），总时长 = 单飞时长。
	SIMULTANEOUS,
}

## 子控件生成时自动播放一轮发牌：进入树时已有子控件、或运行时首次有子控件加入
## 即在**帧末**起播（同一帧内批量加入的子控件全部计入起播数量、总时长与可见性
## 快照）；每个轨道生命周期只触发一次（后续增删不重播），编辑器内不触发。
@export var deal_auto_play: bool = true
## 运行时新子控件加入轨道时，是否自动播放该子控件的入场动画（从环心飞到当前
## 槽位，复用发牌的单飞时长与过渡，不影响其它子控件）。默认关；编辑器不触发；
## 整轨自动发牌尚未起播（含帧末延迟窗口）时由整轨发牌统一接管，不单独入场。
@export var entrance_on_child_added := false
## 单个子控件从环心飞到槽位的时长（秒）。
@export_range(0.05, 3.0, 0.01) var deal_duration_seconds := 0.35
## 相邻子控件起播间隔（秒）；仅错峰起播模式生效，0 等效齐发。
@export_range(0.0, 2.0, 0.01) var deal_stagger_seconds := 0.12
## 起播模式：错峰（默认）或齐发。
@export var deal_launch_mode: DealLaunchMode = DealLaunchMode.STAGGERED
## 飞行过渡类型（默认 BACK 配 EASE_OUT，落位带一点过冲回弹）。
@export var deal_transition: Tween.TransitionType = Tween.TRANS_BACK
## 飞行缓动类型。
@export var deal_ease: Tween.EaseType = Tween.EASE_OUT
## 编辑器检查器单次预览（同四面板先例）：播放一轮发牌动画，动画自恢复、
## 播完即正常排列；运行时入口无副作用，游戏内请用 play_deal_animation()。
@export_tool_button("播放一次", "Play") var preview_play_action: Callable = preview_play
@export_tool_button("停止并恢复", "Stop") var preview_stop_action: Callable = preview_stop

## 可选运行时起拨裁决，由组装方注入；未设置时保持通用拨盘语义。
## 参数为视口坐标的按键事件，轨道不认识库存或其它业务对象。
var rotary_drag_filter: Callable

var _transfer_records: Array[Dictionary] = []
var _transfer_gathering := false
var _transfer_pending_deal := false
var _transfer_reparenting := false
var _transfer_clock := 0.0
var _transfer_generation := 0
var _watched_controls: Array[Control] = []
var _motion := OrbitMotion.new()
var _rotary_dragging := false
var _rotary_pointer_angle := 0.0
var _rotary_rest_phase := 0.0
var _snap_back_tween: Tween
var _deal_playing := false
var _deal_clock := 0.0
var _deal_total := 0.0
var _deal_spawn_played := false
## 帧末延迟起播的自动发牌是否已排队（防同帧批量加入时重复排队）。
var _spawn_deal_deferred := false
## 起播时的可见性快照（控件实例 → 是否可见）：播放前就被隐藏的子控件全程保持
## 隐藏但仍参与槽位重算（隐藏占位语义）；播放中加入的子控件不在快照里，按可见处理。
var _deal_visibility_snapshot := {}
## 进行中的单控件入场飞行，元素为 [Control, 已飞行秒]；整轨发牌重播与强制收尾时清空。
var _entrance_flights: Array = []
## 已见过的子控件实例 id 集合：识别"运行时新加入"的子控件（进入树时已有的不算新加入）。
var _seen_child_instance_ids := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset_ratio = Vector2.ZERO
	pivot_offset = size * 0.5
	if !resized.is_connected(_on_resized):
		resized.connect(_on_resized)
	_remember_current_children()
	_sync_processing()
	_try_auto_play_spawn_deal()


func _process(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	if _transfer_gathering:
		_advance_transfer(delta)
		return
	if _deal_playing:
		_deal_clock += delta
		if _deal_clock >= _deal_total:
			_finish_deal()
	_advance_entrance_flights(delta)
	if auto_spin and not Engine.is_editor_hint() and not _rotary_dragging \
			and not _is_snapping_back():
		orbit_phase += rotation_speed * delta
	_advance_motion(delta)
	relayout_slots()


## 拨盘输入统一走 _input（GUI 处理之前，不可被消费拦截）：抓取半径内的按压即刻
## 起拨——默认压在卡片或子控件上也可抓住拨盘；组合交互由 rotary_drag_filter 裁决；
## 跟手与松手同样在 GUI 之前，指针扫过会消费鼠标事件的控件不中断、释放被消费不卡死。
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


## 当前是否处于拨盘拖动中（按住跟手阶段，不含回正补间）。
func is_rotary_dragging() -> bool:
	return _rotary_dragging


## 播放发牌动画：全部子控件先隐藏并移到环心，再按起播模式（错峰/齐发）飞回
## 各自槽位；槽位按当前全部子控件（含隐藏者）重算。播放中重播从头再来，且沿用
## 首次起播时的可见性快照——不把动画自身隐藏的卡片误判为本来就隐藏。
func play_deal_animation() -> void:
	cancel_transfer()
	_start_deal_animation()


func _start_deal_animation() -> void:
	reset_motion()
	var orbit_controls := get_orbit_controls()
	if orbit_controls.is_empty():
		deal_finished.emit()
		return
	# 整轨发牌接管全部子控件：进行中的单控件入场一并终止。
	_entrance_flights.clear()
	if not _deal_playing:
		_deal_visibility_snapshot.clear()
		for control in orbit_controls:
			_deal_visibility_snapshot[control] = control.visible
	for control in orbit_controls:
		control.visible = false
	_deal_playing = true
	_deal_clock = 0.0
	_deal_total = deal_duration_seconds
	if deal_launch_mode == DealLaunchMode.STAGGERED:
		_deal_total += deal_stagger_seconds * float(orbit_controls.size() - 1)
	relayout_slots()
	_sync_processing()


## 发牌动画是否正在播放。
func is_deal_playing() -> bool:
	return _deal_playing


## 播放单个子控件的入场动画：该控件从环心飞到当前槽位，复用发牌的单飞时长与
## 过渡（槽位随自转/拨盘每帧重算，飞行追着活动目标收敛）；不影响其它子控件的
## 位置与可见性。目标不是本轨道的直接 Control 子节点时告警忽略；目标本身隐藏
## 时不做任何事（隐藏占位语义，不显形）。正在进行整轨发牌时对其中某控件调用，
## 该控件改走入场飞行；整轨发牌重播会接管并终止所有入场飞行。
func play_entrance_animation(control: Control) -> void:
	if control == null or control.get_parent() != self:
		push_warning("OrbitTrack 入场动画：目标不是本轨道的直接子控件，已忽略。")
		return
	if not control.visible:
		return
	if is_entrance_playing(control):
		return
	_entrance_flights.append([control, 0.0])
	_sync_processing()


## 指定子控件是否正在播放入场动画。
func is_entrance_playing(control: Control) -> bool:
	return _entrance_elapsed_for(control) >= 0.0


## 编辑器单次预览：在编辑器内播放一轮发牌动画（播放中再点从头重播）；
## 运行时调用无副作用，游戏内请用 play_deal_animation()。
func preview_play() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if get_orbit_control_count() == 0:
		push_warning("OrbitTrack 预览：轨道上没有子控件，无事可播。")
		return
	play_deal_animation()


## 立即结束编辑器预览并恢复全部子控件到正常排列与可见性；空闲或运行时调用无副作用。
func preview_stop() -> void:
	if not Engine.is_editor_hint():
		return
	cancel_transfer()
	_motion.reset()
	_force_finish_deal()
	_force_finish_entrances()


## 生成时自动发牌：运行时首次出现子控件后延迟到**帧末**起播——同一帧内批量加入
## 的子控件（如库存装配逐格挂载）到齐后再计算起播数量、总时长与可见性快照。
## 每个生命周期至多一次；关闭开关、编辑器环境或空轨道不触发。
func _try_auto_play_spawn_deal() -> void:
	if _transfer_gathering or _transfer_pending_deal or _deal_spawn_played or not deal_auto_play or Engine.is_editor_hint():
		return
	if not is_inside_tree() or get_orbit_control_count() == 0:
		return
	if _spawn_deal_deferred:
		return
	_spawn_deal_deferred = true
	call_deferred("_deferred_spawn_deal")


## 帧末执行的自动发牌：同帧批量加入的子控件此刻已全部在轨道上。
func _deferred_spawn_deal() -> void:
	_spawn_deal_deferred = false
	if _transfer_gathering or _transfer_pending_deal or _deal_spawn_played or not deal_auto_play or Engine.is_editor_hint():
		return
	if not is_inside_tree() or get_orbit_control_count() == 0:
		return
	_deal_spawn_played = true
	play_deal_animation()


## 识别运行时新加入的子控件并按配置起播其入场动画；同时清理已移除子控件的登记。
## 整轨自动发牌尚在待起播窗口（帧末延迟未执行）时跳过——首批子控件由整轨发牌
## 统一接管，不逐张入场。
func _sync_child_added_entrances() -> void:
	var current_instance_ids := {}
	for control in get_orbit_controls():
		var instance_id := control.get_instance_id()
		current_instance_ids[instance_id] = true
		if _seen_child_instance_ids.has(instance_id):
			continue
		_seen_child_instance_ids[instance_id] = true
		if _should_entrance_new_child():
			play_entrance_animation(control)
	for instance_id in _seen_child_instance_ids.keys():
		if not current_instance_ids.has(instance_id):
			_seen_child_instance_ids.erase(instance_id)


func _should_entrance_new_child() -> bool:
	if _transfer_gathering or _transfer_reparenting or not entrance_on_child_added or Engine.is_editor_hint():
		return false
	if deal_auto_play and not _deal_spawn_played:
		return false
	return true


## 把当前子控件登记为已见：进入树时已存在的子控件不算"运行时新加入"，不触发育场。
func _remember_current_children() -> void:
	for control in get_orbit_controls():
		_seen_child_instance_ids[control.get_instance_id()] = true


## 立即完成进行中的发牌：跳到终点，可见性按快照恢复、位置回到正常排列。
func _force_finish_deal() -> void:
	if not _deal_playing:
		return
	_deal_clock = _deal_total
	_finish_deal()


## 环形轨道圆心（矩形中心）的全局坐标；旋转绕中心枢轴，圆心在旋转中保持不动。
func get_track_center_global() -> Vector2:
	return get_global_transform() * (size * 0.5)


func _notification(what: int) -> void:
	if _transfer_reparenting:
		return
	# 子节点增删（子控件加入 / 移除）时立即重排一次，并补挂新控件的尺寸监听，
	# 暂停自转期间也能保持均匀、响应控件尺寸变化。
	if what == NOTIFICATION_CHILD_ORDER_CHANGED:
		_release_departed_children()
		_ensure_control_resize_listeners()
		_sync_child_added_entrances()
		relayout_slots()
		_try_auto_play_spawn_deal()
	# 保存场景前终结进行中的发牌与入场，不把动画中间状态（隐藏/驻留环心）写入场景。
	elif what == NOTIFICATION_EDITOR_PRE_SAVE:
		cancel_transfer()
		_motion.reset()
		_force_finish_deal()
		_force_finish_entrances()


func _exit_tree() -> void:
	cancel_transfer()
	_rotary_dragging = false
	_motion.reset()
	# 退出树时立即终结进行中的发牌、入场与回正补间，子控件不留隐藏或半飞行状态。
	_force_finish_deal()
	_force_finish_entrances()
	_kill_snap_back_tween()
	_spawn_deal_deferred = false


## 把当前子控件的 resized 信号接到重排上：控件自身尺寸变化（非增删）时也重新收敛，
## 包括暂停自转期间。
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


## 把当前子控件按枚举序 k/n 均匀摆上环形轨道，并反向旋转抵消自转（子控件保持直立）。
## 发牌播放期间：未轮到的隐藏驻留环心，轮到的从环心插值飞向**当前**槽位
## （槽位随自转/拨盘每帧重算，飞行追着活动目标收敛）。
func relayout_slots() -> void:
	if _transfer_reparenting or _transfer_gathering:
		return
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
		if _entrance_elapsed_for(control) >= 0.0:
			_write_entrance_position(control, track_center, slot_center)
		elif _deal_playing:
			_write_deal_position(control, slot_index, track_center, slot_center)
		else:
			control.position = slot_center - control.size * 0.5 + _motion.get_offset(control)
			control.rotation += _motion.get_rotation(control)


## 发牌中单个子控件的位置与可见性：未轮到的隐藏驻留环心；轮到的恢复显示
## （按起播时的快照——起播前就被使用者隐藏的保持隐藏、只占位）并按进度插值飞行。
func _write_deal_position(control: Control, slot_index: int, track_center: Vector2,
		slot_center: Vector2) -> void:
	var progress := _deal_progress_for(slot_index)
	if progress <= 0.0:
		control.visible = false
		control.position = track_center - control.size * 0.5
		return
	control.visible = _deal_visibility_snapshot.get(control, true)
	if progress >= 1.0:
		control.position = slot_center - control.size * 0.5
		return
	# 本引擎（4.8.dev）interpolate_value 六参签名第 4 参为插值开关：false 直接返回 to，
	# true 才按 trans/ease 计算缓动权重。
	var eased: float = Tween.interpolate_value(0.0, 1.0, progress, true, deal_transition, deal_ease)
	control.position = track_center.lerp(slot_center, eased) - control.size * 0.5


## 发牌子控件的飞行进度：起播时刻按模式取枚举序 × 错峰间隔（齐发恒为 0），
## 除以单飞时长。
func _deal_progress_for(slot_index: int) -> float:
	var launch_offset := 0.0
	if deal_launch_mode == DealLaunchMode.STAGGERED:
		launch_offset = deal_stagger_seconds * float(slot_index)
	return (_deal_clock - launch_offset) / maxf(deal_duration_seconds, 0.00001)


## 入场飞行中单个子控件的位置：从环心按进度插值飞向当前槽位（槽位随自转/拨盘
## 每帧重算）；入场不改变可见性（隐藏控件不发起入场）。
func _write_entrance_position(control: Control, track_center: Vector2,
		slot_center: Vector2) -> void:
	var progress := _entrance_elapsed_for(control) / maxf(deal_duration_seconds, 0.00001)
	if progress >= 1.0:
		control.position = slot_center - control.size * 0.5
		return
	var eased: float = Tween.interpolate_value(0.0, 1.0, progress, true,
		deal_transition, deal_ease)
	control.position = track_center.lerp(slot_center, eased) - control.size * 0.5


## 指定子控件的已飞行秒数；不在入场飞行中返回 -1。
func _entrance_elapsed_for(control: Control) -> float:
	for flight in _entrance_flights:
		if is_instance_valid(flight[0]) and flight[0] == control:
			return flight[1]
	return -1.0


## 推进入场飞行时钟：到时、已移除或已释放的控件结束入场，移交常规排布。
func _advance_entrance_flights(delta: float) -> void:
	if _entrance_flights.is_empty():
		return
	var surviving: Array = []
	for flight in _entrance_flights:
		# 先对 Variant 做有效性判定：typed 赋值为 Control 时，已释放实例会直接报错。
		var raw_flight_ref = flight[0]
		if not is_instance_valid(raw_flight_ref) or raw_flight_ref.get_parent() != self:
			continue
		var control: Control = raw_flight_ref
		var elapsed: float = flight[1] + delta
		if elapsed < deal_duration_seconds:
			surviving.append([control, elapsed])
	_entrance_flights = surviving
	if _entrance_flights.is_empty():
		_sync_processing()


## 立即结束全部入场飞行：位置回到常规槽位（保存场景/退出树前收尾用）。
func _force_finish_entrances() -> void:
	if _entrance_flights.is_empty():
		return
	_entrance_flights.clear()
	relayout_slots()
	_sync_processing()


func _finish_deal() -> void:
	var transfer_done := _transfer_pending_deal
	var generation := _transfer_generation
	_transfer_pending_deal = false
	_deal_playing = false
	# 强制收尾（预览停止/退出树）时部分子控件可能尚未轮到起播，仍处隐藏态；
	# 统一按起播快照恢复可见性后再清空，正常播完时此循环是幂等的。
	for control in get_orbit_controls():
		control.visible = _deal_visibility_snapshot.get(control, true)
	_deal_visibility_snapshot.clear()
	relayout_slots()
	_sync_processing()
	deal_finished.emit()
	if transfer_done and generation == _transfer_generation:
		transfer_finished.emit()


## 理想槽位中心（轨道局部坐标），由椭圆半径、相位与槽位序号计算。
func get_slot_center(slot_index: int, slot_count: int = -1) -> Vector2:
	if slot_count < 0:
		slot_count = get_orbit_control_count()
	if slot_count <= 0:
		return size * 0.5
	var angle := orbit_phase + slot_start_angle + TAU * float(slot_index) / float(slot_count)
	return size * 0.5 + Vector2(cos(angle), sin(angle)) * orbit_radii


## 当前直接 Control 子节点，按场景树顺序返回。排除已 queue_free 等待释放的节点：
## 全量重建的旧格子临死前一帧不再占位，避免把幽灵格子计入排布、发牌起播数量与总时长。
func get_orbit_controls() -> Array[Control]:
	var orbit_controls: Array[Control] = []
	for child in get_children():
		var control := child as Control
		if control != null and is_instance_valid(control) \
				and not control.is_queued_for_deletion():
			orbit_controls.append(control)
	return orbit_controls


## 当前直接 Control 子节点数量。
func get_orbit_control_count() -> int:
	return get_orbit_controls().size()


## 运行时切换自转（暂停 / 继续）：状态只属于本节点，
## 不影响其它轨道实例。
func set_orbit_spinning(spinning: bool) -> void:
	auto_spin = spinning


func _on_resized() -> void:
	pivot_offset_ratio = Vector2.ZERO
	pivot_offset = size * 0.5
	relayout_slots()


## 视口坐标 → 本画布空间坐标。
func _canvas_position(viewport_position: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * viewport_position


func _begin_rotary_drag(pointer_angle: float) -> void:
	_kill_snap_back_tween()
	_rotary_dragging = true
	_rotary_rest_phase = orbit_phase
	_rotary_pointer_angle = pointer_angle
	_sync_processing()


func _end_rotary_drag() -> void:
	_rotary_dragging = false
	_start_snap_back_if_needed()
	_sync_processing()


## 拨动期间把指针绕环心的角增量累积到轨道旋转上：跟随指针、支持多圈。
func _track_rotary_pointer(pointer_canvas_position: Vector2) -> void:
	var pointer_angle := (pointer_canvas_position - get_track_center_global()).angle()
	orbit_phase += angle_difference(_rotary_pointer_angle, pointer_angle)
	_rotary_pointer_angle = pointer_angle


## 松手后按配置补间回拨动开始时的角度。角距取原始差值而非最短路径，
## 多圈拨动会沿原路整圈退回，模拟老式拨号盘的回卷。
func _start_snap_back_if_needed() -> void:
	if not snap_back_on_release:
		return
	var angle_distance := absf(_rotary_rest_phase - orbit_phase)
	if snap_back_duration_seconds <= 0.0:
		orbit_phase = _rotary_rest_phase
		relayout_slots()
		return
	if angle_distance < deg_to_rad(snap_back_dead_zone_degrees):
		return
	var tween_time := snap_back_duration_seconds
	if not snap_back_fixed_duration:
		tween_time = snap_back_duration_seconds * angle_distance / PI
	_snap_back_tween = create_tween()
	_snap_back_tween.finished.connect(_on_snap_back_finished)
	_snap_back_tween.tween_property(self, "orbit_phase", _rotary_rest_phase, tween_time)


func _is_snapping_back() -> bool:
	return _snap_back_tween != null and is_instance_valid(_snap_back_tween)


func _on_snap_back_finished() -> void:
	_snap_back_tween = null
	relayout_slots()
	_sync_processing()


func _kill_snap_back_tween() -> void:
	if _snap_back_tween != null and is_instance_valid(_snap_back_tween):
		_snap_back_tween.kill()
	_snap_back_tween = null


## 关闭拨盘时中断进行中的拨动与回正，不留悬挂状态。
func _cancel_rotary_interaction() -> void:
	_rotary_dragging = false
	_kill_snap_back_tween()


## 帧循环开关：自转、拨动、回正、发牌或任一入场飞行进行时保持 _process 运行，
## 其余交给通知重排。编辑器空闲态不自转不响应输入（同面板预览规范的编辑器隔离），
## 仅发牌预览与入场需要帧循环。
func _sync_processing() -> void:
	if Engine.is_editor_hint():
		set_process(_transfer_gathering or _deal_playing or not _entrance_flights.is_empty())
		return
	set_process(_transfer_gathering or spring_enabled or motion_lean_enabled or auto_spin or _rotary_dragging or _is_snapping_back() \
		or _deal_playing or not _entrance_flights.is_empty())


## 清除速度导数/弹簧/倾斜历史，立即回到理想位置。用于传送、重新绑定与手动复位。
func reset_motion() -> void:
	_motion.reset()
	if is_inside_tree():
		relayout_slots()
		_sync_processing()


func _advance_motion(delta: float) -> void:
	if _deal_playing or _transfer_gathering:
		_motion.reset()
		return
	if Engine.is_editor_hint() or not (spring_enabled or motion_lean_enabled):
		return
	_motion.step(self, get_orbit_controls(), delta)


## 采用同一 Viewport 内的 Controls。先对全批截取屏幕姿态，再逐个移出 Grid。
## 动画顺序为「全批汇聚 → 一轮发牌」；false 立即采用最终排布，跨 Viewport 批次校验失败时保持场景。
## 临时 Node2D 承载动画仿射变换，可精确保留旋转与非均匀缩放产生的剪切；操作结束时释放。
func transfer_controls(controls: Array, animated := true) -> bool:
	if not is_inside_tree() or is_queued_for_deletion():
		return false
	var incoming: Array[Control] = []
	for item in controls:
		if not is_instance_valid(item) or not item is Control:
			continue
		var control: Control = item
		if control == self or control.is_ancestor_of(self) or not control.is_inside_tree() \
				or control.is_queued_for_deletion() or control.get_viewport() != get_viewport():
			push_warning("OrbitTrack transfer: requires live Controls in the same Viewport, without ancestor cycles.")
			return false
		if not incoming.has(control): incoming.append(control)
	if incoming.is_empty():
		return true
	var canvas_transform := get_global_transform_with_canvas()
	if absf(canvas_transform.determinant()) < 0.000001:
		push_warning("OrbitTrack transfer: destination transform is singular.")
		return false
	var all_controls := get_transfer_controls()
	for control in incoming:
		if not all_controls.has(control): all_controls.append(control)
	var snapshots: Array[Dictionary] = []
	# This loop MUST finish before any reparent/cancel can trigger Container reflow.
	for control in all_controls:
		snapshots.append({"control": control, "screen": control.get_global_transform_with_canvas(),
			"size": control.size, "scale": _transfer_original_scale(control),
			"visible": _logical_visibility(control)})
	cancel_transfer()
	_cancel_deal_without_signal()
	_force_finish_entrances()
	_cancel_rotary_interaction()
	_motion.reset()
	_deal_spawn_played = true
	_spawn_deal_deferred = false
	_transfer_generation += 1
	_transfer_clock = 0.0
	_transfer_reparenting = true
	for snapshot in snapshots:
		var control: Control = snapshot.control
		var old_parent := control.get_parent()
		if old_parent is OrbitTrack:
			old_parent._release_for_transfer(control)
		if control.resized.is_connected(_on_control_resized):
			control.resized.disconnect(_on_control_resized)
		if animated and transfer_duration_seconds > 0.0:
			var carrier := Node2D.new()
			carrier.name = "_OrbitTransfer_%d" % control.get_instance_id()
			add_child(carrier)
			control.reparent(carrier, false)
			control.set_as_top_level(false)
			control.set_anchors_preset(Control.PRESET_TOP_LEFT)
			control.pivot_offset_ratio = Vector2.ZERO
			control.pivot_offset = Vector2.ZERO
			control.rotation = 0.0
			control.scale = Vector2.ONE
			control.size = snapshot.size
			control.position = Vector2.ZERO
			carrier.transform = canvas_transform.affine_inverse() * Transform2D(snapshot.screen)
			snapshot.carrier = carrier
			_transfer_records.append(snapshot)
		else:
			control.reparent(self, false)
			control.set_as_top_level(false)
			control.set_anchors_preset(Control.PRESET_TOP_LEFT)
			control.size = snapshot.size
			control.scale = snapshot.scale
		control.visible = snapshot.visible
	_transfer_reparenting = false
	_transfer_gathering = not _transfer_records.is_empty()
	_remember_current_children()
	_ensure_control_resize_listeners()
	if not _transfer_gathering:
		relayout_slots()
		transfer_finished.emit()
	_sync_processing()
	return true


## 返回归本轨道及汇聚载体持有的控件，供再次切换等调用复用。
func get_transfer_controls() -> Array[Control]:
	var result := get_orbit_controls()
	for record in _transfer_records:
		if _owns_transfer_record(record) and not result.has(record.control):
			result.append(record.control)
	return result


func is_transfer_playing() -> bool:
	return _transfer_gathering or _transfer_pending_deal


## 静默取消当前切换并采用仍归本轨道所有的控件，恢复可见性与槽位；普通发牌由其自身生命周期完成。
func cancel_transfer() -> void:
	var cancel_deal := is_transfer_playing()
	_transfer_generation += 1
	_transfer_pending_deal = false
	_transfer_gathering = false
	if not _transfer_records.is_empty():
		_adopt_transfer_records()
	if cancel_deal:
		_cancel_deal_without_signal()
	_motion.reset()
	if is_inside_tree():
		relayout_slots()
		_sync_processing()


func _advance_transfer(delta: float) -> void:
	_transfer_clock += delta
	var progress := clampf(_transfer_clock / maxf(transfer_duration_seconds, 0.00001), 0.0, 1.0)
	var eased := progress * progress * (3.0 - 2.0 * progress)
	var destination_canvas := get_global_transform_with_canvas()
	if absf(destination_canvas.determinant()) < 0.000001:
		cancel_transfer()
		return
	for record in _transfer_records:
		if not _owns_transfer_record(record): continue
		var carrier: Node2D = record.carrier
		var target := Transform2D(-rotation, Vector2(record.scale), 0.0, Vector2.ZERO)
		target.origin = size * 0.5 - target.basis_xform(Vector2(record.size) * 0.5)
		var start_local: Transform2D = destination_canvas.affine_inverse() * Transform2D(record.screen)
		carrier.transform = start_local.interpolate_with(target, eased)
	if progress < 1.0: return
	var generation := _transfer_generation
	_transfer_gathering = false
	_adopt_transfer_records()
	# Everybody is at the center before callbacks or any deal movement.
	for control in get_orbit_controls():
		control.pivot_offset_ratio = Vector2.ZERO
		control.pivot_offset = control.size * 0.5
		control.rotation = -rotation
		control.position = size * 0.5 - control.size * 0.5
	transfer_gathered.emit()
	if generation != _transfer_generation or not is_inside_tree(): return
	_transfer_pending_deal = true
	_start_deal_animation()
	if generation != _transfer_generation or not is_inside_tree(): return
	if get_orbit_control_count() == 0:
		_transfer_pending_deal = false
		transfer_finished.emit()


func _owns_transfer_record(record: Dictionary) -> bool:
	return is_instance_valid(record.get("control")) and is_instance_valid(record.get("carrier")) \
		and record.control.get_parent() == record.carrier and not record.control.is_queued_for_deletion()


func _adopt_transfer_records() -> void:
	_transfer_reparenting = true
	for record in _transfer_records:
		if _owns_transfer_record(record):
			var control: Control = record.control
			control.reparent(self, false)
			control.set_as_top_level(false)
			control.set_anchors_preset(Control.PRESET_TOP_LEFT)
			control.size = record.size
			control.scale = record.scale
			control.visible = record.visible
		if is_instance_valid(record.get("carrier")):
			record.carrier.queue_free()
	_transfer_records.clear()
	_transfer_reparenting = false
	_remember_current_children()
	_ensure_control_resize_listeners()


func _logical_visibility(control: Control) -> bool:
	if _deal_visibility_snapshot.has(control): return _deal_visibility_snapshot[control]
	for record in _transfer_records:
		if record.control == control: return record.visible
	var source := _transfer_owner_of(control)
	if source != null and source != self: return source._logical_visibility(control)
	return control.visible


func _transfer_original_scale(control: Control) -> Vector2:
	for record in _transfer_records:
		if record.control == control: return record.scale
	var source := _transfer_owner_of(control)
	if source != null and source != self: return source._transfer_original_scale(control)
	return control.scale


func _transfer_owner_of(control: Control) -> OrbitTrack:
	var parent := control.get_parent()
	if parent is OrbitTrack: return parent
	if parent is Node2D and parent.get_parent() is OrbitTrack:
		var possible: OrbitTrack = parent.get_parent()
		for record in possible._transfer_records:
			if record.control == control and possible._owns_transfer_record(record): return possible
	return null


func _cancel_deal_without_signal() -> void:
	_deal_playing = false
	for control in _deal_visibility_snapshot:
		if is_instance_valid(control) and control.get_parent() == self:
			control.visible = _deal_visibility_snapshot[control]
	_deal_visibility_snapshot.clear()
	_entrance_flights.clear()


func _release_for_transfer(control: Control) -> void:
	if _deal_visibility_snapshot.has(control):
		control.visible = _deal_visibility_snapshot[control]
		_deal_visibility_snapshot.erase(control)
	_motion.forget(control)
	if control.resized.is_connected(_on_control_resized):
		control.resized.disconnect(_on_control_resized)


func _release_departed_children() -> void:
	for control in _deal_visibility_snapshot.keys():
		if not is_instance_valid(control):
			_deal_visibility_snapshot.erase(control)
		elif control.get_parent() != self:
			_release_for_transfer(control)
