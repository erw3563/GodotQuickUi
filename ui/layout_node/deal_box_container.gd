@tool
@abstract
class_name DealBoxContainer
extends BoxContainer
## 盒形容器发牌动画抽象基类：子控件布局完全由引擎 BoxContainer 负责（size flags、
## separation 等引擎语义不变），本类只在引擎排好的槽位上叠加方向偏移插值动画。
## 请使用具体薄壳 DealVBoxContainer（竖直）或 DealHBoxContainer（水平）。
## 可选发牌动画：play_deal_animation() 让全部直接 Control 子控件先隐藏并移到
## 「槽位 + 方向偏移」起点，再按起播模式（错峰/齐发）依次或同时飞回各自槽位
## （播放前就隐藏的子控件计入起播序列与总时长，但不显形；引擎盒布局对隐藏
## 子控件不分配空间，基准取其最后一次被引擎排到的位置）。
## 槽位基准在 Container.sort_children 信号后捕获；播放期间容器尺寸变化或子控件增删引发
## 引擎重排时，基准随之重算，飞行追着新目标收敛。
## 单个子控件可单独入场：play_entrance_animation(control) 让该控件从起点飞到
## 当前槽位，不影响其它子控件；entrance_on_child_added 可让运行时新加入的
## 子控件自动播放入场。
## 空闲态不触碰子控件位置；本类不创建业务子节点。

## 发牌动画全部物品落位后发出（空容器起播也立即发，等待语义一致）。
signal deal_finished

@export_group("发牌动画")
## 发牌起播模式。
enum DealLaunchMode {
	## 按枚举序错峰起播：第 k 个子控件的起播时刻 = k × 错峰间隔。
	STAGGERED,
	## 齐发：全部子控件同时起飞（忽略错峰间隔），总时长 = 单飞时长。
	SIMULTANEOUS,
}

## 发牌起点方向：飞行过程中子控件位于槽位的该侧、距槽位 deal_offset_pixels。
enum DealDirection {
	FROM_TOP,
	FROM_BOTTOM,
	FROM_LEFT,
	FROM_RIGHT,
}

## 子控件生成时自动播放一轮发牌：进入树时已有子控件、或运行时首次有子控件
## 加入即在**帧末**起播（同一帧内批量加入的子控件全部计入起播数量、总时长
## 与可见性快照）；每个容器生命周期只触发一次（后续增删不重播），编辑器内
## 不触发。
@export var deal_auto_play: bool = true
## 运行时新子控件加入容器时，是否自动播放该子控件的入场动画（从起点飞到
## 当前槽位，复用发牌的单飞时长与过渡，不影响其它子控件）。默认关；编辑器
## 不触发；整批发牌尚未起播（含帧末延迟窗口）时由整批发牌统一接管，不单独
## 入场。
@export var entrance_on_child_added := false
## 单个子控件从起点飞到槽位的时长（秒）。
@export_range(0.05, 3.0, 0.01) var deal_duration_seconds := 0.35
## 相邻子控件起播间隔（秒）；仅错峰起播模式生效，0 等效齐发。
@export_range(0.0, 2.0, 0.01) var deal_stagger_seconds := 0.12
## 起播模式：错峰（默认）或齐发。
@export var deal_launch_mode: DealLaunchMode = DealLaunchMode.STAGGERED
## 飞行过渡类型（默认 BACK 配 EASE_OUT，落位带一点过冲回弹）。
@export var deal_transition: Tween.TransitionType = Tween.TRANS_BACK
## 飞行缓动类型。
@export var deal_ease: Tween.EaseType = Tween.EASE_OUT
## 发牌起点方向。
@export var deal_direction: DealDirection = DealDirection.FROM_TOP
## 起点到槽位的偏移距离（像素）。
@export_range(0.0, 2000.0, 1.0) var deal_offset_pixels := 80.0
## 编辑器检查器单次预览：播放一轮发牌动画，动画自恢复、播完即正常布局；
## 运行时入口无副作用，游戏内请用 play_deal_animation()。
@export_tool_button("播放一次", "Play") var preview_play_action: Callable = preview_play
@export_tool_button("停止并恢复", "Stop") var preview_stop_action: Callable = preview_stop

var _deal_playing := false
var _deal_clock := 0.0
var _deal_total := 0.0
var _deal_spawn_played := false
## 帧末延迟起播的自动发牌是否已排队（防同帧批量加入时重复排队）。
var _spawn_deal_deferred := false
## 起播时的可见性快照（控件实例 → 是否可见）：播放前就被隐藏的子控件全程
## 保持隐藏但仍计入起播序列（总时长与错峰序号照算）；播放中加入的子控件
## 不在快照里，按可见处理。
var _deal_visibility_snapshot := {}
## 槽位基准（控件实例 → 引擎排序写下的位置）：sort_children 信号后更新；
## 发牌与入场飞行都插值收敛到基准。
var _slot_positions := {}
## 进行中的单控件入场飞行，元素为 [Control, 已飞行秒]；整批发牌重播与强制
## 收尾时清空。
var _entrance_flights: Array = []
## 已见过的子控件实例 id 集合：识别"运行时新加入"的子控件（进入树时已有的
## 不算新加入）。
var _seen_child_instance_ids := {}


func _ready() -> void:
	if !sort_children.is_connected(_on_sorted):
		sort_children.connect(_on_sorted)
	_remember_current_children()
	_sync_processing()
	_try_auto_play_spawn_deal()


func _process(delta: float) -> void:
	if _deal_playing:
		_deal_clock += delta
		if _deal_clock >= _deal_total:
			_finish_deal()
	_advance_entrance_flights(delta)
	if _deal_playing or not _entrance_flights.is_empty():
		_apply_current_offsets()


func _notification(what: int) -> void:
	# 子控件增删时识别新加入者并按配置起播入场或整批发牌；布局由引擎自理。
	if what == NOTIFICATION_CHILD_ORDER_CHANGED:
		_sync_child_added_entrances()
		_try_auto_play_spawn_deal()
	# 保存场景前终结进行中的发牌与入场，不把动画中间状态（隐藏/驻留起点）写入场景。
	elif what == NOTIFICATION_EDITOR_PRE_SAVE:
		_force_finish_deal()
		_force_finish_entrances()


func _exit_tree() -> void:
	# 退出树时立即终结进行中的发牌与入场，子控件不留隐藏或半飞行状态。
	_force_finish_deal()
	_force_finish_entrances()
	_spawn_deal_deferred = false


## 播放发牌动画：全部子控件先隐藏并移到「槽位 + 方向偏移」起点，再按起播
## 模式（错峰/齐发）飞回各自槽位。播放中重播从头再来，且沿用首次起播时的
## 可见性快照——不把动画自身隐藏的卡片误判为本来就隐藏。
func play_deal_animation() -> void:
	var controls := get_deal_controls()
	if controls.is_empty():
		deal_finished.emit()
		return
	if not _deal_playing:
		# 只有此刻位置可信（无动画在跑）：入场飞行中的控件沿用起播时记录的
		# 基准（其当前位置被飞行偏移污染），其余按当前引擎位置冻结基准。
		_capture_slot_positions(true)
		_deal_visibility_snapshot.clear()
		for control in controls:
			_deal_visibility_snapshot[control] = control.visible
	# 整批发牌接管全部子控件：进行中的单控件入场一并终止。
	_entrance_flights.clear()
	_deal_playing = true
	_deal_clock = 0.0
	_deal_total = deal_duration_seconds
	if deal_launch_mode == DealLaunchMode.STAGGERED:
		_deal_total += deal_stagger_seconds * float(controls.size() - 1)
	_apply_current_offsets()
	_sync_processing()


## 发牌动画是否正在播放。
func is_deal_playing() -> bool:
	return _deal_playing


## 播放单个子控件的入场动画：该控件从起点飞到当前槽位，复用发牌的单飞时长
## 与过渡（槽位基准随引擎重排经 sort_children 更新，飞行追着活动目标收敛）；不影响
## 其它子控件的位置与可见性。目标不是本容器的直接 Control 子节点时告警忽略；
## 目标本身隐藏时不做任何事（不显形）。正在进行整批发牌时对其中某控件调用，
## 该控件改走入场飞行；整批发牌重播会接管并终止所有入场飞行。
func play_entrance_animation(control: Control) -> void:
	if control == null or control.get_parent() != self:
		push_warning("DealBoxContainer 入场动画：目标不是本容器的直接子控件，已忽略。")
		return
	if not control.visible:
		return
	if is_entrance_playing(control):
		return
	if not _slot_positions.has(control) and not _deal_playing:
		# 发牌中改走入场者沿用整批起播时冻结的基准，不把飞行位当槽位。
		_slot_positions[control] = control.position
	_entrance_flights.append([control, 0.0])
	_write_entrance_position(control, 0.0)
	_sync_processing()


## 指定子控件是否正在播放入场动画。
func is_entrance_playing(control: Control) -> bool:
	return _entrance_elapsed_for(control) >= 0.0


## 编辑器单次预览：在编辑器内播放一轮发牌动画（播放中再点从头重播）；
## 运行时调用无副作用，游戏内请用 play_deal_animation()。
func preview_play() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if get_deal_control_count() == 0:
		push_warning("DealBoxContainer 预览：容器上没有子控件，无事可播。")
		return
	play_deal_animation()


## 立即结束编辑器预览并恢复全部子控件到正常布局与可见性；空闲或运行时调用
## 无副作用。
func preview_stop() -> void:
	if not Engine.is_editor_hint():
		return
	_force_finish_deal()
	_force_finish_entrances()


## 引擎排序完成后：重捕全部槽位基准（此刻子控件位置必为引擎写下的真实槽位，
## 无论是否在动画中，飞行目标随之更新到新布局）；动画进行中随即按当前进度
## 重写偏移，避免重排后一帧正常位闪烁。
func _on_sorted() -> void:
	_capture_slot_positions(false)
	if _deal_playing or not _entrance_flights.is_empty():
		_apply_current_offsets()


## 重捕槽位基准。skip_flying 为 true 时跳过入场飞行中的控件（其当前位置被
## 飞行偏移污染，沿用其起播入场时记录的基准）；信号回调传 false。
## 已移除或已释放控件的旧基准一并清理。
func _capture_slot_positions(skip_flying: bool) -> void:
	for control in get_deal_controls():
		if skip_flying and _entrance_elapsed_for(control) >= 0.0:
			continue
		_slot_positions[control] = control.position
	for key in _slot_positions.keys():
		var remembered := key as Control
		if not is_instance_valid(remembered) or remembered.get_parent() != self:
			_slot_positions.erase(key)


## 按当前时钟与飞行表写全部动画位置：发牌中的按枚举序进度写入；入场飞行中
## 的按各自已飞行秒写入。空闲子控件不触碰。
func _apply_current_offsets() -> void:
	if _deal_playing:
		var controls := get_deal_controls()
		for slot_index in controls.size():
			_write_deal_position(controls[slot_index], slot_index)
	for flight in _entrance_flights:
		var control := flight[0] as Control
		if is_instance_valid(control) and control.get_parent() == self:
			_write_entrance_position(control, flight[1])


## 发牌中单个子控件的位置与可见性：未轮到的隐藏驻留起点；轮到的恢复显示
## （按起播时的快照——起播前就被使用者隐藏的保持隐藏）并按进度插值飞行。
func _write_deal_position(control: Control, slot_index: int) -> void:
	var progress := _deal_progress_for(slot_index)
	var slot: Vector2 = _slot_positions.get(control, control.position)
	if progress <= 0.0:
		control.visible = false
		control.position = slot + _deal_offset_vector()
		return
	control.visible = _deal_visibility_snapshot.get(control, true)
	if progress >= 1.0:
		control.position = slot
		return
	var eased: float = Tween.interpolate_value(0.0, 1.0, progress, true,
		deal_transition, deal_ease)
	control.position = slot + _deal_offset_vector() * (1.0 - eased)


## 发牌子控件的飞行进度：起播时刻按模式取枚举序 × 错峰间隔（齐发恒为 0），
## 除以单飞时长。
func _deal_progress_for(slot_index: int) -> float:
	var launch_offset := 0.0
	if deal_launch_mode == DealLaunchMode.STAGGERED:
		launch_offset = deal_stagger_seconds * float(slot_index)
	return (_deal_clock - launch_offset) / deal_duration_seconds


## 入场飞行中单个子控件的位置：从起点按进度插值飞向当前基准；入场不改变
## 可见性（隐藏控件不发起入场）。
func _write_entrance_position(control: Control, elapsed: float) -> void:
	var slot: Vector2 = _slot_positions.get(control, control.position)
	var progress := elapsed / deal_duration_seconds
	if progress >= 1.0:
		control.position = slot
		return
	var eased: float = Tween.interpolate_value(0.0, 1.0, progress, true,
		deal_transition, deal_ease)
	control.position = slot + _deal_offset_vector() * (1.0 - eased)


## 当前方向的起点偏移向量。
func _deal_offset_vector() -> Vector2:
	match deal_direction:
		DealDirection.FROM_TOP:
			return Vector2(0.0, -deal_offset_pixels)
		DealDirection.FROM_BOTTOM:
			return Vector2(0.0, deal_offset_pixels)
		DealDirection.FROM_LEFT:
			return Vector2(-deal_offset_pixels, 0.0)
		DealDirection.FROM_RIGHT:
			return Vector2(deal_offset_pixels, 0.0)
	return Vector2.ZERO


## 指定子控件的已飞行秒数；不在入场飞行中返回 -1。
func _entrance_elapsed_for(control: Control) -> float:
	for flight in _entrance_flights:
		var flying := flight[0] as Control
		if is_instance_valid(flying) and flying == control:
			return flight[1]
	return -1.0


## 推进入场飞行时钟：到时的控件先精确落位再移交引擎布局；已移除或已释放的
## 控件直接结束入场。
func _advance_entrance_flights(delta: float) -> void:
	if _entrance_flights.is_empty():
		return
	var surviving: Array = []
	for flight in _entrance_flights:
		var control := flight[0] as Control
		if not is_instance_valid(control) or control.get_parent() != self:
			continue
		var elapsed: float = flight[1] + delta
		if elapsed < deal_duration_seconds:
			surviving.append([control, elapsed])
			continue
		var slot: Vector2 = _slot_positions.get(control, control.position)
		control.position = slot
	_entrance_flights = surviving
	if _entrance_flights.is_empty():
		_sync_processing()


func _finish_deal() -> void:
	_deal_playing = false
	# 强制收尾（预览停止/退出树）时部分子控件可能尚未轮到起播，仍处隐藏态；
	# 统一按起播快照恢复可见性后再清空，正常播完时此循环是幂等的。
	for control in get_deal_controls():
		control.visible = _deal_visibility_snapshot.get(control, true)
		var slot: Vector2 = _slot_positions.get(control, control.position)
		control.position = slot
	_deal_visibility_snapshot.clear()
	_sync_processing()
	deal_finished.emit()


## 立即完成进行中的发牌：跳到终点，可见性按快照恢复、位置回到引擎槽位。
func _force_finish_deal() -> void:
	if not _deal_playing:
		return
	_deal_clock = _deal_total
	_finish_deal()


## 立即结束全部入场飞行：位置回到引擎槽位（保存场景/退出树前收尾用）。
func _force_finish_entrances() -> void:
	if _entrance_flights.is_empty():
		return
	var finishing := _entrance_flights.duplicate()
	_entrance_flights.clear()
	for flight in finishing:
		var control := flight[0] as Control
		if not is_instance_valid(control) or control.get_parent() != self:
			continue
		var slot: Vector2 = _slot_positions.get(control, control.position)
		control.position = slot
	_sync_processing()


## 生成时自动发牌：运行时首次出现子控件后延迟到**帧末**起播——同一帧内批量
## 加入的子控件（如装配逐个挂载）到齐后再计算起播数量、总时长与可见性快照。
## 每个容器生命周期至多一次；关闭开关、编辑器环境或空容器不触发。
func _try_auto_play_spawn_deal() -> void:
	if _deal_spawn_played or not deal_auto_play or Engine.is_editor_hint():
		return
	if not is_inside_tree() or get_deal_control_count() == 0:
		return
	if _spawn_deal_deferred:
		return
	_spawn_deal_deferred = true
	call_deferred("_deferred_spawn_deal")


## 帧末执行的自动发牌：同帧批量加入的子控件此刻已全部在容器上。
func _deferred_spawn_deal() -> void:
	_spawn_deal_deferred = false
	if _deal_spawn_played or not deal_auto_play or Engine.is_editor_hint():
		return
	if not is_inside_tree() or get_deal_control_count() == 0:
		return
	_deal_spawn_played = true
	play_deal_animation()


## 识别运行时新加入的子控件并按配置起播其入场动画；同时清理已移除子控件的
## 登记。整批发牌尚在待起播窗口（帧末延迟未执行）时跳过——首批子控件由
## 整批发牌统一接管，不逐张入场。
func _sync_child_added_entrances() -> void:
	var current_instance_ids := {}
	for control in get_deal_controls():
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
	if not entrance_on_child_added or Engine.is_editor_hint():
		return false
	if deal_auto_play and not _deal_spawn_played:
		return false
	return true


## 把当前子控件登记为已见：进入树时已存在的子控件不算"运行时新加入"，不
## 触发育场。
func _remember_current_children() -> void:
	for control in get_deal_controls():
		_seen_child_instance_ids[control.get_instance_id()] = true


## 当前直接 Control 子节点，按场景树顺序返回。排除已 queue_free 等待释放的
## 节点：临死前一帧不再计入起播序列、总时长与基准。
func get_deal_controls() -> Array[Control]:
	var controls: Array[Control] = []
	for child in get_children():
		var control := child as Control
		if control != null and is_instance_valid(control) \
				and not control.is_queued_for_deletion():
			controls.append(control)
	return controls


## 当前直接 Control 子节点数量。
func get_deal_control_count() -> int:
	return get_deal_controls().size()


## 帧循环开关：发牌或任一入场飞行进行时保持 _process 运行，其余交给引擎布局
## 与通知。编辑器空闲态不运转，仅预览与入场需要帧循环。
func _sync_processing() -> void:
	set_process(_deal_playing or not _entrance_flights.is_empty())
