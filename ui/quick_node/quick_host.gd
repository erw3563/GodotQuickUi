@tool
class_name QuickHost
extends Node
## 快捷系组件宿主：统一管理 QuickDrag / QuickConstraints / QuickShow / QuickMousePlace /
## QuickPopOut / QuickZoom / QuickRotate 七类子节点的生成、恢复与组合接线，免去手工
## NodePath 接线；同时兼任位置落笔中介——写位置组件（QuickDrag / QuickMousePlace）只提议、
## 永不直写，
## 统一经 [method place] 按落笔意图裁决（[enum QuickUI.PlaceIntent] 固定优先级表：
## 交互打断演出、演出挡住定位），再过 stage 链加工后唯一落笔——stage 即子节点中
## 实现 apply_place 契约者，按场景树顺序依次加工（QuickConstraints 天然是首个）；
## QuickPopOut 的演出动画走租约通道（acquire / release_performance_lease），
## 屏外端点以 PRESENTATION 意图直写，交互落笔可打断演出（performance_lease_broken）。
## 对齐 InventoryHost 装配模式：编辑器里用导出按钮生成子节点并随场景烘焙保存，
## 运行时按固定节点名恢复引用；纯代码装配（如动态浮窗）走 ensure_quick_nodes()。
## 宿主只负责「结构与接线 + 位置裁决」：生成哪些组件（生成即组合，接线全自动——
## 一个宿主即一套完整行为，部分组合 / 特殊接线走散装 QuickNode）；各组件的行为参数
## （弹出方向、拖拽模式、原点比例、离场时长等）直接在生成的子节点上调，宿主不镜像——
## 唯一例外是「演出参数」组：跨演出组件的高频入场参数由宿主统一下发（见该组注释）；
## 宿主另提供 play_entrance / play_exit 成组播放旗下演出组件（鸭子发现同名契约者）；
## 散装 QuickNode 单独配置（无宿主中介）的用法不受影响——写位置组件 placer 为空时
## 直写，语义等价于空管道。

## 目标控件（六类组件共同驱动的宿主 UI）；为空时兜底解析父节点（须为 Control，
## 与 QuickPopOut / QuickZoom 的 ui 解析同款）。运行时更改会重新下发给全部子节点。
@export var ui: Control:
	set(value):
		ui = value
		if is_node_ready():
			_apply_target_to_children()

## 编辑器里生成 / 移除快捷子节点（生成结果随场景烘焙保存）。
@export_tool_button("生成快捷节点") var create_action = _create_quick_nodes
@export_tool_button("移除快捷节点") var remove_action = _remove_quick_nodes

## 生成预设：设为非 CUSTOM 时按矩阵自动写好六个生成开关；套用后手动改任一开关
## 会把预设回落 CUSTOM，检查器如实反映当前组合。场景装载期（未就绪）不套用、
## 以场景保存的开关为准——与 inventory_data 的就绪守卫同款。
enum Preset {
	CUSTOM,                ## 自定义：保持当前开关不动
	DRAGGABLE,             ## 可拖拽卡片：仅 QuickDrag
	POP_OUT,               ## 弹入弹出：仅 QuickPopOut
	SHOW_MENU,             ## 鼠标处弹出菜单：QuickShow + QuickMousePlace（定位）
	ZOOM_UPRIGHT_ENTRANCE, ## 放大回正：QuickZoom + QuickRotate 联动出场
}

## 生成预设：检查器里选一枚即自动配置下方开关。
@export var preset: Preset = Preset.CUSTOM:
	set(value):
		preset = value
		if is_node_ready() and preset != Preset.CUSTOM:
			_apply_preset()

## 是否生成拖拽组件（dragged_ui / clickable_ui 均指向目标控件）。
@export var create_drag: bool = false:
	set(value):
		create_drag = value
		_revert_preset_if_tweaked()

## 是否生成位置仲裁组件（目标控件驻留位置经其钳制）。
@export var create_constraints: bool = false:
	set(value):
		create_constraints = value
		_revert_preset_if_tweaked()

## 是否生成显隐组件（含按键收起）。
@export var create_show: bool = false:
	set(value):
		create_show = value
		_revert_preset_if_tweaked()

## 是否生成鼠标处定位组件（定位后联动显隐组件显形）。
@export var create_place: bool = false:
	set(value):
		create_place = value
		_revert_preset_if_tweaked()

## 是否生成屏外飞入 / 收起动画组件。
@export var create_pop_out: bool = false:
	set(value):
		create_pop_out = value
		_revert_preset_if_tweaked()

## 是否生成原点缩放组件。
@export var create_zoom: bool = false:
	set(value):
		create_zoom = value
		_revert_preset_if_tweaked()

## 是否生成倾斜回正旋转组件。
@export var create_rotate: bool = false:
	set(value):
		create_rotate = value
		_revert_preset_if_tweaked()

@export_group("演出参数")
## 跨演出组件（QuickPopOut / QuickZoom / QuickRotate）统一的高频入场参数，是「宿主不
## 镜像行为参数」原则的显式例外（仅限跨组件高频项）：生成子节点时作为初始值下发，
## 运行时更改会重新下发给已存在的演出组件；场景装载期不下发（就绪守卫同 ui / preset），
## 烘焙子节点的细调值以场景为准。注意默认 animate_entrance = true——经宿主生成的
## QuickPopOut 会随就绪自动入场（散装默认 false 不变）。
@export var animate_entrance: bool = true:
	set(value):
		animate_entrance = value
		_apply_performance_params_if_ready()

@export_range(0.0, 2.0, 0.01) var animation_duration: float = 0.25:
	set(value):
		animation_duration = value
		_apply_performance_params_if_ready()

@export var animation_transition: Tween.TransitionType = Tween.TRANS_BACK:
	set(value):
		animation_transition = value
		_apply_performance_params_if_ready()

@export var animation_ease: Tween.EaseType = Tween.EASE_OUT:
	set(value):
		animation_ease = value
		_apply_performance_params_if_ready()

var _applying_preset := false

## 演出租约被交互落笔打断时发出（参数为持约者，即正在演出的组件）。
signal performance_lease_broken(holder: Node)

## 当前演出租约持约者（空 = 无演出进行，定位类落笔不受挡）。
var _performance_lease_holder: Node = null

var drag: QuickDrag
var constraints: QuickConstraints
var show: QuickShow
var mouse_place: QuickMousePlace
var pop_out: QuickPopOut
var zoom: QuickZoom
var rotate: QuickRotate


func _ready() -> void:
	_cache_quick_nodes()
	_apply_links()


## 若按导出开关尚缺子节点则补建（已存在的不动，保留 inspector 细调结果），
## 并统一应用组合接线；纯代码装配宿主时调用（烘焙场景子节点已在，无需调用）。
func ensure_quick_nodes() -> void:
	_cache_quick_nodes()
	_spawn_missing_quick_nodes()
	_apply_links()


## 强制重建全部快捷节点（保留宿主配置；子节点参数回到组件默认值）。
func rebuild_quick_nodes() -> void:
	_create_quick_nodes()


## 获取拖拽组件（必要时从子节点恢复引用）。
func get_drag() -> QuickDrag:
	_cache_quick_nodes()
	return drag


## 获取位置仲裁组件（必要时从子节点恢复引用）。
func get_constraints() -> QuickConstraints:
	_cache_quick_nodes()
	return constraints


## 获取显隐组件（必要时从子节点恢复引用）。
func get_show() -> QuickShow:
	_cache_quick_nodes()
	return show


## 获取鼠标处定位组件（必要时从子节点恢复引用）。
func get_place() -> QuickMousePlace:
	_cache_quick_nodes()
	return mouse_place


## 获取飞入 / 收起动画组件（必要时从子节点恢复引用）。
func get_pop_out() -> QuickPopOut:
	_cache_quick_nodes()
	return pop_out


## 获取缩放组件（必要时从子节点恢复引用）。
func get_zoom() -> QuickZoom:
	_cache_quick_nodes()
	return zoom


## 获取旋转组件（必要时从子节点恢复引用）。
func get_rotate() -> QuickRotate:
	_cache_quick_nodes()
	return rotate


# ---------- 成组演出播放 ----------

## 播放宿主旗下全部演出组件的入场动画：按鸭子发现遍历子节点，实现了
## play_entrance 契约者（QuickPopOut / QuickZoom / QuickRotate，含自建演出节点）
## 同节奏起播（节奏由「演出参数」统一）；拖拽 / 约束 / 定位等持续或被动组件
## 无此方法，天然不参与。已在入场终态的组件按各自状态机无动作。
func play_entrance() -> void:
	for child in get_children():
		if child.has_method("play_entrance"):
			child.play_entrance()

## 播放宿主旗下全部演出组件的退场动画（发现规则同 [method play_entrance]）。
func play_exit() -> void:
	for child in get_children():
		if child.has_method("play_exit"):
			child.play_exit()


# ---------- 演出参数下发 ----------

## setter 侧入口：就绪后延迟到帧末统一下发——脚本热重载的属性恢复期，后声明的
## 成员可能尚未初始化（立即读取会以 Nil 赋给占位子节点报错）；延迟也把同帧
## 多次改动合并成一次下发。生成路径不经此（_spawn 直接赋值，成员彼时已就绪）。
func _apply_performance_params_if_ready() -> void:
	if not is_node_ready():
		return
	_apply_performance_params.call_deferred()


## 把演出参数下发给已存在的演出组件（pop_out / zoom / rotate，含烘焙档恢复的子节点）。
func _apply_performance_params() -> void:
	_cache_quick_nodes()
	if pop_out != null:
		_assign_performance_params(pop_out)
	if zoom != null:
		_assign_performance_params(zoom)
	if rotate != null:
		_assign_performance_params(rotate)


## 四个演出参数在三类组件上同名同型，生成与下发共用一个赋值入口。
func _assign_performance_params(node) -> void:
	node.animate_entrance = animate_entrance
	node.animation_duration = animation_duration
	node.animation_transition = animation_transition
	node.animation_ease = animation_ease


# ---------- 位置落笔中介 ----------

## 位置落笔入口：写位置组件的唯一合法通道。按意图裁决（固定优先级表
## INTERACTIVE > PRESENTATION > PLACEMENT），经 stage 链加工后唯一写
## control.global_position；control 与宿主目标不一致时绕过管道直写并警告。
## 返回最终落笔位置（被租约忽略的定位请求返回控件当前位置）。
func place(control: Control, proposed: Vector2, intent: QuickUI.PlaceIntent = QuickUI.PlaceIntent.PLACEMENT) -> Vector2:
	if control == null:
		return proposed
	if control != _resolve_ui():
		push_warning("QuickHost.place：落笔控件与宿主目标不一致，绕过管道直写。")
		control.global_position = proposed
		return proposed
	match intent:
		QuickUI.PlaceIntent.INTERACTIVE:
			_break_performance_lease()
			return _place_through_stages(control, proposed)
		QuickUI.PlaceIntent.PRESENTATION:
			# 演出端点不加工：钳回屏内会毁掉入场 / 收起动画。
			control.global_position = proposed
			return proposed
		QuickUI.PlaceIntent.PLACEMENT, _:
			if _performance_lease_holder != null:
				push_warning("QuickHost.place：演出租约期间忽略定位落笔。")
				return control.global_position
			return _place_through_stages(control, proposed)


## 申请演出租约：租约期间定位类落笔（PLACEMENT）被忽略，持约者动画可直写；
## 已有其他持约者时拒绝并警告，同一持约者重复申请幂等。
func acquire_performance_lease(holder: Node) -> bool:
	if holder == null:
		return false
	if _performance_lease_holder != null and _performance_lease_holder != holder:
		push_warning("QuickHost：演出租约已被占用，拒绝新的演出申请。")
		return false
	_performance_lease_holder = holder
	return true


## 归还演出租约：final_rest 非 Vector2.INF 时以 PLACEMENT 意图经管道登记最终
## 休息位（marks 移动后仍被钳回合法区）；传 Vector2.INF 表示只归还不落笔
## （收起动画结束于屏外，经管道会被钳回视口）。
func release_performance_lease(holder: Node, final_rest := Vector2.INF) -> void:
	if _performance_lease_holder != holder:
		return
	_performance_lease_holder = null
	var target := _resolve_ui()
	if final_rest != Vector2.INF and target != null:
		place(target, final_rest, QuickUI.PlaceIntent.PLACEMENT)


## 打断演出租约（交互落笔前调用）：先清空持约者再发出 performance_lease_broken，
## 演出组件听到后杀 tween 并恢复可交互状态。
func _break_performance_lease() -> void:
	if _performance_lease_holder == null:
		return
	var holder := _performance_lease_holder
	_performance_lease_holder = null
	performance_lease_broken.emit(holder)


## 提议经 stage 链加工后唯一落笔：stage 即子节点中实现 apply_place 契约者，
## 按场景树顺序依次加工（生成顺序保证 QuickConstraints 在首，钳制为第一道）。
func _place_through_stages(control: Control, proposed: Vector2) -> Vector2:
	var result := proposed
	for child in get_children():
		if child.has_method("apply_place"):
			result = child.apply_place(control, result)
	control.global_position = result
	return result


func _create_quick_nodes() -> void:
	_remove_quick_nodes()
	_spawn_missing_quick_nodes()
	_apply_links()


func _remove_quick_nodes() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	drag = null
	constraints = null
	show = null
	mouse_place = null
	pop_out = null
	zoom = null
	rotate = null


## 按预设矩阵写生成开关（套用期间不触发预设回落）。
func _apply_preset() -> void:
	_applying_preset = true
	match preset:
		Preset.DRAGGABLE:
			_set_create_toggles(true, false, false, false, false, false, false)
		Preset.POP_OUT:
			_set_create_toggles(false, false, false, false, true, false, false)
		Preset.SHOW_MENU:
			_set_create_toggles(false, false, true, true, false, false, false)
		Preset.ZOOM_UPRIGHT_ENTRANCE:
			_set_create_toggles(false, false, false, false, false, true, true)
	_applying_preset = false


func _set_create_toggles(
	want_drag: bool, want_constraints: bool, want_show: bool, want_place: bool,
	want_pop_out: bool, want_zoom: bool, want_rotate: bool
) -> void:
	create_drag = want_drag
	create_constraints = want_constraints
	create_show = want_show
	create_place = want_place
	create_pop_out = want_pop_out
	create_zoom = want_zoom
	create_rotate = want_rotate


## 手动改动生成开关时把预设回落 CUSTOM（检查器如实反映当前组合）。
func _revert_preset_if_tweaked() -> void:
	if is_node_ready() and not _applying_preset and preset != Preset.CUSTOM:
		preset = Preset.CUSTOM


## 按开关生成缺失的子节点：固定名 + 目标引用 + owner 持久化（编辑器生成后随场景保存）。
## 生成顺序保持 constraints 在首——stage 链按子节点顺序加工，钳制宜为第一道。
func _spawn_missing_quick_nodes() -> void:
	var target := _resolve_ui()
	if target == null:
		push_warning("QuickHost：目标控件缺失（ui 未导出且父节点不是 Control），跳过生成。")
		return
	if create_constraints and constraints == null:
		constraints = QuickConstraints.new()
		constraints.name = "QuickConstraints"
		constraints.ui = target
		_add_managed(constraints)
	if create_pop_out and pop_out == null:
		pop_out = QuickPopOut.new()
		pop_out.name = "QuickPopOut"
		pop_out.ui = target
		_assign_performance_params(pop_out)
		_add_managed(pop_out)
	if create_drag and drag == null:
		drag = QuickDrag.new()
		drag.name = "QuickDrag"
		drag.dragged_ui = target
		drag.clickable_ui = target
		_add_managed(drag)
	if create_show and show == null:
		show = QuickShow.new()
		show.name = "QuickShow"
		show.control = target
		_add_managed(show)
	if create_place and mouse_place == null:
		mouse_place = QuickMousePlace.new()
		mouse_place.name = "QuickMousePlace"
		mouse_place.control = target
		_add_managed(mouse_place)
	if create_zoom and zoom == null:
		zoom = QuickZoom.new()
		zoom.name = "QuickZoom"
		zoom.ui = target
		_assign_performance_params(zoom)
		_add_managed(zoom)
	if create_rotate and rotate == null:
		rotate = QuickRotate.new()
		rotate.name = "QuickRotate"
		rotate.ui = target
		_assign_performance_params(rotate)
		_add_managed(rotate)


## 应用组合接线（全自动，无开关——一个宿主即一套完整行为，生成即组合）：
## 写位置 / 演出组件统一接宿主中介（placer = self，中介是唯一落笔通道）；
## place 与 show 同存则定位完成后自动显形；show 与 pop_out 同存则显隐自动
## 改走飞入 / 收起动画；zoom 与 rotate 同存则信号联动（首次接线按当前缩放
## 状态同步一次旋转，等价于 page_quick_rotate 的场景 connection）。部分组合 /
## 特殊接线需求走散装 QuickNode 手工配置。
## zoom↔rotate 信号只在运行时连接——编辑器中非 @tool 子脚本是占位实例，
## 没有可连接的信号（连接也无法随场景持久化）。
func _apply_links() -> void:
	_cache_quick_nodes()
	if drag != null:
		drag.placer = self
	if mouse_place != null:
		mouse_place.placer = self
	if pop_out != null:
		pop_out.placer = self
	if mouse_place != null and show != null:
		mouse_place.show = show
	if pop_out != null and show != null:
		show.popout = pop_out
	if zoom != null and rotate != null and not Engine.is_editor_hint():
		if not zoom.expanded_changed.is_connected(rotate.set_upright):
			zoom.expanded_changed.connect(rotate.set_upright)
			# 首次接线按当前缩放状态同步旋转（覆盖烘焙档 start_expanded = false 的初始态）。
			rotate.set_upright(zoom.is_expanded)


## 把解析出的目标控件下发给全部子节点（ui 运行时变更后调用）。
func _apply_target_to_children() -> void:
	_cache_quick_nodes()
	var target := _resolve_ui()
	if target == null:
		return
	if drag != null:
		drag.dragged_ui = target
		drag.clickable_ui = target
	if constraints != null:
		constraints.ui = target
	if show != null:
		show.control = target
	if mouse_place != null:
		mouse_place.control = target
	if pop_out != null:
		pop_out.ui = target
	if zoom != null:
		zoom.ui = target
	if rotate != null:
		rotate.ui = target


## 解析目标控件：优先显式导出，其次父节点（须为 Control）。
func _resolve_ui() -> Control:
	if ui != null:
		return ui
	var parent := get_parent()
	if parent is Control:
		return parent
	return null


## 挂到宿主名下并按场景归属持久化（编辑器生成结果随场景保存）。
func _add_managed(node: Node) -> void:
	add_child(node)
	if owner:
		node.owner = owner
	else:
		node.owner = self


## 从已有子节点恢复运行时引用（编辑器生成的节点随场景保存后，脚本变量不持久；
## 固定名约定：QuickDrag / QuickConstraints / QuickShow / QuickMousePlace /
## QuickPopOut / QuickZoom / QuickRotate）。
func _cache_quick_nodes() -> void:
	if drag == null:
		drag = get_node_or_null("QuickDrag") as QuickDrag
	if constraints == null:
		constraints = get_node_or_null("QuickConstraints") as QuickConstraints
	if show == null:
		show = get_node_or_null("QuickShow") as QuickShow
	if mouse_place == null:
		mouse_place = get_node_or_null("QuickMousePlace") as QuickMousePlace
	if pop_out == null:
		pop_out = get_node_or_null("QuickPopOut") as QuickPopOut
	if zoom == null:
		zoom = get_node_or_null("QuickZoom") as QuickZoom
	if rotate == null:
		rotate = get_node_or_null("QuickRotate") as QuickRotate
