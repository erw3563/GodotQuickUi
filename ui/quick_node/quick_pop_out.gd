class_name QuickPopOut
extends Node
## 将 [Control] 从屏幕外 tween 到目标位置；支持多方向与弹出/收起。
## 所有权契约：本组件驱动 global_position / modulate / visible 的「演出路径」——
## 屏外起止端点经中介（[member placer]）以 PRESENTATION 意图直写（不经 stage
## 加工，钳回屏内会毁掉动画）；动画进行期持有宿主的演出租约：定位类落笔被挡、
## 交互落笔（拖拽）会打断演出（杀 tween 并恢复可交互状态）。
## placer 为空时全部直写（散装用法，行为与无中介时一致）。

signal pop_in_finished
signal pop_out_finished

## 要驱动的 UI 根节点；为空则尝试使用本组件的父节点（若为 Control）。
@export var ui: Control
## 进入方向：从屏幕哪一侧外移入。
@export var enter_direction: EnterDirection = EnterDirection.FROM_BOTTOM
## 入场动画时长（秒）；命名对齐 QuickZoom / QuickRotate 与面板系的 animation_duration。
@export_range(0.05, 3.0, 0.01) var animation_duration: float = 0.45
## 离场动画时长（秒）；组件特有粒度，不随宿主演出参数统一下发。
@export_range(0.05, 3.0, 0.01) var animation_duration_out: float = 0.38
## 动画过渡类型（入场与离场共用）。
@export var animation_transition: Tween.TransitionType = Tween.TRANS_CUBIC
## 入场缓动类型；离场固定 EASE_IN（与 QuickZoom / QuickRotate 同形）。
@export var animation_ease: Tween.EaseType = Tween.EASE_OUT
## 在视口尺寸基础上额外偏移（像素），确保完全在屏外。
@export var extra_margin: float = 64.0
## 弹入弹出全程淡入淡出（命名对齐 QuickZoom 的 fade_during_zoom）。
@export var fade_during_pop: bool = true
## 离开时是否在动画末尾隐藏节点。
@export var hide_on_pop_out: bool = true
## 初始是否播入场动画（false 保持收起隐藏）；命名对齐 QuickZoom / QuickRotate 的 animate_entrance。
@export var animate_entrance: bool = false
## 是否反方向离开
@export var is_reverse_exit:bool = false
## 位置落笔中介（鸭子契约：实现演出租约与 PRESENTATION 落笔的节点，QuickHost 即是）；
## 留空则本组件直写（散装）。
@export var placer: Node
## 当前是否处于屏外收起态；初始即收起（_ready 就隐藏宿主），首次 pop() 即入场。
var is_out := true

enum EnterDirection {
	FROM_TOP,
	FROM_BOTTOM,
	FROM_LEFT,
	FROM_RIGHT,
	FROM_TOP_LEFT,
	FROM_TOP_RIGHT,
	FROM_BOTTOM_LEFT,
	FROM_BOTTOM_RIGHT,
}

var _rest_global: Vector2
var _captured: bool = false
var _tween: Tween


## 解析目标 Control、记录初始收起态，并按需延迟播放进入动画。
func _ready() -> void:
	_resolve_ui()
	capture_rest_position()
	ui.visible = false
	if animate_entrance:
		pop_out()
		call_deferred("_deferred_play_pop_in")
## 等两帧布局稳定后再捕获位置并播放进入动画（供 animate_entrance 使用）；
## 等待期间节点被移除 / 释放时安全返回（宿主移除子节点可能赶在本调用执行前）。
func _deferred_play_pop_in() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	await tree.process_frame
	if not is_instance_valid(self) or not is_inside_tree():
		return
	await tree.process_frame
	if not is_instance_valid(self) or not is_inside_tree():
		return
	pop_in()
## 节点退出树时终止未完成的 Tween、归还演出租约，避免悬空引用与漏租约。
func _exit_tree() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
		_tween = null
	_release_lease()
## 若未指定 ui，则当父节点为 Control 时将其作为驱动目标。
func _resolve_ui() -> void:
	if ui != null:
		return
	var p := get_parent()
	if p is Control:
		ui = p as Control
## 记录当前布局下的目标位置（世界坐标）；进入前请先调用或依赖首次 [method pop_in] 内捕获。
func capture_rest_position() -> void:
	_resolve_ui()
	if ui == null:
		return
	_rest_global = ui.global_position
	_captured = true
## 在弹出与收起之间切换（由 is_out 决定本次调用 pop_in 或 pop_out）。
func pop():
	if is_out:
		pop_in()
	else:
		pop_out()

## 统一播放入口（与 QuickZoom / QuickRotate 同名，宿主经此成组驱动演出）：
## 播放入场动画；已处于入场态则无动作。
func play_entrance() -> void:
	if is_out:
		pop_in()

## 统一播放入口：播放退场动画；已处于收起态则无动作。
func play_exit() -> void:
	if not is_out:
		pop_out()
## 从屏外飞入到当前布局位置。
func pop_in() -> void:
	_resolve_ui()
	if ui == null:
		return
	if not _captured:
		capture_rest_position()
	_acquire_lease()
	var start_global := _rest_global + _compute_screen_offset(enter_direction)
	ui.visible = true
	_place_performance(start_global)
	if fade_during_pop:
		ui.modulate.a = 0.0
	_run_tween_in()
	is_out = false
## 收起到屏外（方向与 [member enter_direction] 相反一侧离开，观感更自然）。
func pop_out() -> void:
	_resolve_ui()
	if ui == null:
		return
	if not _captured:
		capture_rest_position()
	_acquire_lease()
	var end_global:Vector2
	if is_reverse_exit:
		end_global = _rest_global + _compute_screen_offset(_opposite_direction(enter_direction))
	else:
		end_global = _rest_global + _compute_screen_offset(enter_direction)
	_run_tween_out(end_global)
	is_out = true
## 创建并播放进入动画：位移到休息位置，可选淡入；结束时发出 pop_in_finished。
func _run_tween_in() -> void:
	_kill_tween()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_trans(animation_transition)
	_tween.set_ease(animation_ease)
	_tween.tween_property(ui, "global_position", _rest_global, animation_duration)
	if fade_during_pop:
		_tween.tween_property(ui, "modulate:a", 1.0, animation_duration * 0.85)
	_tween.finished.connect(func():
		_release_lease(_rest_global)
		pop_in_finished.emit(), CONNECT_ONE_SHOT)
## 创建并播放离开动画：位移到 end_global，可选淡出；结束时可隐藏并发出 pop_out_finished。
func _run_tween_out(end_global: Vector2) -> void:
	_kill_tween()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_trans(animation_transition)
	_tween.set_ease(Tween.EASE_IN)
	_tween.tween_property(ui, "global_position", end_global, animation_duration_out)
	if fade_during_pop:
		_tween.tween_property(ui, "modulate:a", 0.0, animation_duration_out)
	_tween.finished.connect(
		func():
			_release_lease()
			if hide_on_pop_out:
				ui.visible = false
			pop_out_finished.emit(),
		CONNECT_ONE_SHOT
	)
## 申请演出租约并订阅打断信号（同一持约者幂等；散装无中介时静默跳过）。
func _acquire_lease() -> void:
	if placer == null or not placer.has_method("acquire_performance_lease"):
		return
	if not placer.acquire_performance_lease(self):
		return
	if placer.has_signal("performance_lease_broken") \
			and not placer.performance_lease_broken.is_connected(_on_performance_lease_broken):
		placer.performance_lease_broken.connect(_on_performance_lease_broken)
## 归还演出租约；final_rest 非 Vector2.INF 时经管道登记最终休息位，收起传 INF 只归还。
func _release_lease(final_rest := Vector2.INF) -> void:
	if placer == null or not placer.has_method("release_performance_lease"):
		return
	placer.release_performance_lease(self, final_rest)
## 演出端点落笔：以 PRESENTATION 意图经中介直写（散装无中介时同样直写）。
func _place_performance(pos: Vector2) -> void:
	if placer != null and placer.has_method("place"):
		placer.place(ui, pos, QuickUI.PlaceIntent.PRESENTATION)
	else:
		ui.global_position = pos
## 演出租约被交互落笔打断：杀 tween，把控件恢复为可交互状态（可见、不透明）。
func _on_performance_lease_broken(holder: Node) -> void:
	if holder != self or ui == null:
		return
	_kill_tween()
	ui.modulate.a = 1.0
	ui.visible = true
## 停止并清空当前 Tween，便于启动新动画。
func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
## 当前视口可见区域尺寸；无视口时返回默认 1920×1080。
func _viewport_size() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2(1920, 1080)
	return vp.get_visible_rect().size
## 按进入方向计算相对休息位置的屏外偏移（含 extra_margin）。
func _compute_screen_offset(dir: EnterDirection) -> Vector2:
	var vs := _viewport_size()
	var m := extra_margin
	match dir:
		EnterDirection.FROM_TOP:
			return Vector2(0.0, -vs.y - m)
		EnterDirection.FROM_BOTTOM:
			return Vector2(0.0, vs.y + m)
		EnterDirection.FROM_LEFT:
			return Vector2(-vs.x - m, 0.0)
		EnterDirection.FROM_RIGHT:
			return Vector2(vs.x + m, 0.0)
		EnterDirection.FROM_TOP_LEFT:
			return Vector2(-vs.x - m, -vs.y - m)
		EnterDirection.FROM_TOP_RIGHT:
			return Vector2(vs.x + m, -vs.y - m)
		EnterDirection.FROM_BOTTOM_LEFT:
			return Vector2(-vs.x - m, vs.y + m)
		EnterDirection.FROM_BOTTOM_RIGHT:
			return Vector2(vs.x + m, vs.y + m)
	return Vector2.ZERO
## 返回与进入方向相对的离开方向（用于 pop_out 从对侧飞出）。
func _opposite_direction(dir: EnterDirection) -> EnterDirection:
	match dir:
		EnterDirection.FROM_TOP:
			return EnterDirection.FROM_BOTTOM
		EnterDirection.FROM_BOTTOM:
			return EnterDirection.FROM_TOP
		EnterDirection.FROM_LEFT:
			return EnterDirection.FROM_RIGHT
		EnterDirection.FROM_RIGHT:
			return EnterDirection.FROM_LEFT
		EnterDirection.FROM_TOP_LEFT:
			return EnterDirection.FROM_BOTTOM_RIGHT
		EnterDirection.FROM_TOP_RIGHT:
			return EnterDirection.FROM_BOTTOM_LEFT
		EnterDirection.FROM_BOTTOM_LEFT:
			return EnterDirection.FROM_TOP_RIGHT
		EnterDirection.FROM_BOTTOM_RIGHT:
			return EnterDirection.FROM_TOP_LEFT
	return EnterDirection.FROM_TOP
