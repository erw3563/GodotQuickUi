@tool
class_name QuickZoom
extends Node
## 缩放演出件：把宿主 [Control] 从当前缩放播放到 [member target_scale]，原点钉在
## [member origin_ratio]（缩放全程该点屏幕位置不变）。统一播放契约 play＋
## play_finished；[member is_zooming] 为播放查询。
## visible、global_position、size——透明度与可见性归 QuickShow，位置归 QuickPopIn /
## QuickPopOut，真实布局全程不变；因此与 QuickConstraints（含 continuous）和位置类
## 演出件互不冲突，可叠加挂在同一控件上。
## 起点即宿主的 authored 当前缩放：装载期收起 / 隐藏由作者把控件初始态写进场景
## （如 visible=false、scale=(0,0)），本件不携带初始态。
## 编辑器内提供 Inspector「动画预览」单次演出（快照与恢复由共享 AnimationPreview
## 承载，播放经统一 play 方法）；运行时调用保持无副作用。

signal play_finished
## 目标重新绑定或退出树时通知宿主结束当前时间线。
signal play_cancelled

## 要驱动的宿主控件；为空则尝试使用本组件的父节点（若为 Control）。
@export var ui: Control:
	set(value):
		if ui == value:
			return
		var had_playback := _zoom_target_id != 0
		_kill_zoom_tween()
		ui = value
		if had_playback:
			play_cancelled.emit()

@export_group("播放效果")
## 缩放原点在宿主内的比例坐标（0~1；默认正中心向四周铺开，四角可设 0/1）。
@export var origin_ratio: Vector2 = Vector2(0.5, 0.5):
	set(value):
		origin_ratio = value
		if _play_context():
			_sync_pivot_offset()

## 目标缩放（按分量，x=宽 y=高）：play 从当前缩放到达该值。
## 任一分量负值会被钳到 0（负 scale 会镜像渲染）。
@export var target_scale: Vector2 = Vector2.ONE:
	set(value):
		target_scale = Vector2(maxf(value.x, 0.0), maxf(value.y, 0.0))

## 缩放动画时长（秒）。
@export_range(0.0, 2.0, 0.01) var animation_duration: float = 0.25

## 动画过渡类型（默认 BACK 配 EASE_OUT，带回弹弹出感）。
@export var animation_transition: Tween.TransitionType = Tween.TRANS_BACK

@export var keep_mouse_input: bool = false

## 动画缓动类型。
@export var animation_ease: Tween.EaseType = Tween.EASE_OUT

@export_group("动画预览")
## 仅编辑器生效的单次演出预览（快照与恢复由共享 AnimationPreview 承载，播放经
## 统一 play 方法）；运行时调用保持无副作用。
@export_tool_button("播放一次", "Play") var preview_play_action: Callable = preview_play
@export_tool_button("停止并恢复", "Stop") var preview_stop_action: Callable = preview_stop

## 是否正在播放缩放动画
var is_zooming: bool:
	get:
		return _zoom_tween != null and _zoom_tween.is_valid() and _zoom_tween.is_running()

var _zoom_tween: Tween
var _zoom_target: Control
var _zoom_target_id: int = 0
var _zoom_end_scale := Vector2.ONE
var _run_generation: int = 0
var _input_overridden := false
var _authored_mouse_filter: Control.MouseFilter = Control.MOUSE_FILTER_STOP
## 宿主级整树预览会话标记（编辑器内由 QuickUiAnimHost 开关）：开启时等效本组件预览——
## 解锁编辑器隔离与完成信号发射。
var _host_preview_active := false
static var _active_target_zooms: Dictionary = {}


func _ready() -> void:
	_resolve_ui()


func _exit_tree() -> void:
	preview_stop()
	_kill_zoom_tween()


## 统一播放契约：从当前缩放到达 [member target_scale]；已处目标且不在播放则无操作。
## 返回是否实际起播或正在播（false = 已处终态或目标缺失，宿主据此把该步视为无操作
## 跳过）；播放中再次 play 杀旧建新、从当前缩放重播。
func play() -> bool:
	if not _play_context() or not is_inside_tree():
		return false
	_resolve_ui()
	if not is_instance_valid(ui) or not ui.is_inside_tree():
		return false
	var target := ui
	var request_token := _run_generation + 1
	_kill_zoom_tween()
	if _run_generation != request_token or not is_instance_valid(target) or ui != target or not target.is_inside_tree():
		return false
	var target_id := target.get_instance_id()
	var owner_ref: WeakRef = _active_target_zooms.get(target_id)
	var previous = owner_ref.get_ref() if owner_ref != null else null
	if is_instance_valid(previous) and previous != self:
		previous.interrupt()
	if _run_generation != request_token or not is_inside_tree() or not is_instance_valid(target) or ui != target or not target.is_inside_tree():
		return false
	var successor_ref: WeakRef = _active_target_zooms.get(target_id)
	if successor_ref != null and is_instance_valid(successor_ref.get_ref()):
		return false
	if target.scale.is_equal_approx(target_scale):
		return false
	_zoom_target = target
	_zoom_target_id = target_id
	_zoom_end_scale = target_scale
	_authored_mouse_filter = target.mouse_filter
	_active_target_zooms[target_id] = weakref(self)
	target.tree_exiting.connect(_on_target_tree_exiting)
	_sync_pivot_offset()
	var token := _run_generation
	if animation_duration <= 0.0:
		target.scale = _zoom_end_scale
		_release_zoom_session(false)
		if is_instance_valid(self) and not is_queued_for_deletion() and _run_generation == token + 1:
			_emit_finished()
		return true
	_zoom_tween = target.create_tween()
	_zoom_tween.set_trans(animation_transition)
	_zoom_tween.set_ease(animation_ease)
	_zoom_tween.tween_method(_set_scale_clamped.bind(token), target.scale, _zoom_end_scale, animation_duration)
	_zoom_tween.chain().tween_callback(_on_zoom_finished.bind(token))
	if not keep_mouse_input:
		_input_overridden = true
		target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return true


func interrupt() -> void:
	_kill_zoom_tween()


## BACK 曲线插值末端可能为负，负 scale 会镜像渲染，钳到 0。
func _set_scale_clamped(value: Vector2, token: int) -> void:
	if token != _run_generation or not is_instance_valid(_zoom_target):
		return
	_zoom_target.scale = Vector2(maxf(value.x, 0.0), maxf(value.y, 0.0))


func _on_zoom_finished(token: int) -> void:
	if token != _run_generation or not is_instance_valid(_zoom_target):
		return
	_zoom_target.scale = _zoom_end_scale
	_release_zoom_session(false)
	if is_instance_valid(self) and not is_queued_for_deletion() and _run_generation == token + 1:
		_emit_finished()


func _on_target_tree_exiting() -> void:
	var had_playback := _zoom_target_id != 0
	_kill_zoom_tween()
	if had_playback:
		play_cancelled.emit()


## 把 pivot 钉到原点比例处；缩放全程该点屏幕位置保持不变。
func _sync_pivot_offset() -> void:
	if not is_instance_valid(ui):
		return
	var basis_size := ui.size
	if basis_size.x <= 0.0 or basis_size.y <= 0.0:
		basis_size = ui.custom_minimum_size
	ui.pivot_offset = Vector2(
		clampf(origin_ratio.x, 0.0, 1.0) * basis_size.x,
		clampf(origin_ratio.y, 0.0, 1.0) * basis_size.y
	)


func _kill_zoom_tween() -> void:
	_release_zoom_session(true)


func _release_zoom_session(kill_tween: bool) -> void:
	_run_generation += 1
	var target := _zoom_target
	var target_id := _zoom_target_id
	var restore_input := _input_overridden
	var saved_filter := _authored_mouse_filter
	var tween := _zoom_tween
	_zoom_tween = null
	_zoom_target = null
	_zoom_target_id = 0
	_input_overridden = false
	var owner_ref: WeakRef = _active_target_zooms.get(target_id)
	if owner_ref != null and owner_ref.get_ref() == self:
		_active_target_zooms.erase(target_id)
	if kill_tween and tween != null and tween.is_valid():
		tween.kill()
	if is_instance_valid(target):
		if target.tree_exiting.is_connected(_on_target_tree_exiting):
			target.tree_exiting.disconnect(_on_target_tree_exiting)
		if restore_input and target.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			target.mouse_filter = saved_filter


## 若未指定 ui，则当父节点为 Control 时将其作为驱动目标。
func _resolve_ui() -> void:
	if is_instance_valid(ui):
		return
	var p := get_parent()
	if p is Control:
		ui = p as Control


## 编辑器空闲态不改动宿主表现：运行时、本组件预览或宿主预览会话内才生效。
func _play_context() -> bool:
	return not Engine.is_editor_hint() or is_previewing() or _host_preview_active


## 完成信号仅在运行时发射——编辑器空闲（含本组件单次预览）静默；宿主整树预览
## 会话期间放行（宿主预览的步骤等待依赖完成信号，见预览规范）。
func _emit_finished() -> void:
	if not Engine.is_editor_hint() or _host_preview_active:
		play_finished.emit()


## 宿主级整树预览会话开启（QuickUiAnimHost 编辑器预览调用）：解锁编辑器隔离与
## 完成信号发射（表现态由宿主的 AnimationPreview 快照恢复）。
func _begin_host_preview_session() -> void:
	_host_preview_active = true


## 宿主级整树预览会话结束：杀进行中的缩放动画（表现态由宿主快照恢复）。
func _end_host_preview_session() -> void:
	_host_preview_active = false
	_kill_zoom_tween()


#region 编辑器单次预览

var _preview := AnimationPreview.new()


## 仅在编辑器播放一次：从 authored 当前缩放到达目标后恢复编辑状态；再次点击从原
## 编辑状态重新开始。
func preview_play() -> void:
	if not Engine.is_editor_hint():
		return
	preview_stop()
	_stop_sibling_previews()
	_resolve_ui()
	if ui == null:
		push_warning("QuickZoom：目标控件缺失（ui 未导出且父节点不是 Control），无法预览。")
		return
	var properties: Array[StringName] = []
	properties.append_array(AnimationPreview.PRESENTATION_PROPERTIES)
	properties.append_array(AnimationPreview.GEOMETRY_PROPERTIES)
	if not _preview.begin(ui, properties, false):
		return
	_preview_run(_preview.generation)


func is_previewing() -> bool:
	return _preview.is_active()


## 保存前和退出树同步恢复；不依赖 Inspector 选择或插件生命周期。
func preview_stop() -> void:
	if not is_previewing():
		return
	_kill_zoom_tween()
	_preview.stop()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		preview_stop()


## 同目标互斥：起播前停掉同级其它演出组件的预览会话——两个组件并发预览同一
## 宿主会互相踩对方的快照恢复；宿主（QuickUiAnimHost）名下时先停宿主的预览会话。
func _stop_sibling_previews() -> void:
	var parent := get_parent()
	if parent == null:
		return
	if parent.has_method("preview_stop"):
		parent.call("preview_stop")
	for child in parent.get_children():
		if child != self and child.has_method("preview_stop"):
			child.call("preview_stop")


func _preview_run(token: int) -> void:
	# 等当前布局帧完成；停止或重播后旧轮不能再初始化。
	await get_tree().process_frame
	if not _preview.is_current(token) or not is_inside_tree():
		return
	play()
	await _preview.wait_tween(self, _zoom_tween, token, animation_duration + 2.0)
	if _preview.is_current(token):
		preview_stop()

#endregion
