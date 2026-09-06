extends UIShowcasePage
## 演示页·弹入弹出 QuickPopOut：目标卡从屏幕外沿所选方向飞入到休息位、
## 反向飞出并淡出。组件经场景 NodePath 绑定 ui（".."，节点路径先于 _ready
## 解析，不会误驱动父页面）；休息位在布局稳定后（等两帧）只重采一次——
## 卡片此后不被外力移动，运行中反复弹出/收回不会漂移。

const DIRECTION_TEXTS: Array[String] = ["从底部进入", "从顶部进入", "从左侧进入", "从右侧进入"]
const DIRECTIONS: Array[QuickPopOut.EnterDirection] = [
	QuickPopOut.EnterDirection.FROM_BOTTOM,
	QuickPopOut.EnterDirection.FROM_TOP,
	QuickPopOut.EnterDirection.FROM_LEFT,
	QuickPopOut.EnterDirection.FROM_RIGHT,
]

var _rest_global: Vector2


func _ready() -> void:
	var option := %DirectionOption as OptionButton
	for item_index in DIRECTION_TEXTS.size():
		option.add_item(DIRECTION_TEXTS[item_index])
	option.select(0)
	option.item_selected.connect(_on_direction_option_selected)
	%ButtonPopOut.pressed.connect((%Popper as QuickPopOut).pop_out)
	%ButtonPopIn.pressed.connect((%Popper as QuickPopOut).pop_in)
	_recapture_rest.call_deferred()


## 等两帧布局稳定后重采休息位（与组件自身的延迟入场时序一致）。
func _recapture_rest() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree() or not is_instance_valid(%Popper):
		return
	(%Popper as QuickPopOut).capture_rest_position()
	_rest_global = (%TargetCard as Control).global_position


func _on_direction_option_selected(item_index: int) -> void:
	(%Popper as QuickPopOut).enter_direction = DIRECTIONS[item_index]


## 方向回「从底部进入」，卡片直接落回隐藏于休息位的初始状态。
func reset_page() -> void:
	(%DirectionOption as OptionButton).select(0)
	var popper := %Popper as QuickPopOut
	popper.enter_direction = QuickPopOut.EnterDirection.FROM_BOTTOM
	var card := %TargetCard as Control
	card.global_position = _rest_global
	card.modulate.a = 1.0
	card.visible = false
	popper.is_out = false
