extends ShowcasePage
## 演示页·快捷宿主 QuickHost：页脚本不关心宿主当前配置了哪些组件——按实际
## 生成的组件自适应（有弹出组件则布局稳定后飞入就位），在编辑器里切换生成
## 预设 / 重新生成后页面照常运行。宿主只管「结构与接线」，行为参数都在生成
## 的子节点上直接调；纯代码装配路径（ensure_quick_nodes）见 test_quick_host。

var _host: QuickHost
var _card: Control
var _rest_position: Vector2


func _ready() -> void:
	_host = %BakedHost as QuickHost
	_card = _host.get_parent() as Control
	# 卡片是页面的手工摆放子节点，布局 position 即场景内 authored 值，就绪即可快照。
	_rest_position = _card.position
	_setup_pop.call_deferred()


## 布局稳定后重采弹出休息位并从屏外飞入就位（宿主配置了弹出组件时才有意义）。
func _setup_pop() -> void:
	await get_tree().create_timer(0.4).timeout
	if not is_inside_tree() or not is_instance_valid(_host):
		return
	var pop := _host.get_pop_out()
	if pop == null:
		return
	# 弹出动画写 global_position 会经当前旋转 / 缩放变换补偿，飞入前先确保卡片
	# 处于未旋转未缩放的正身；实例装载期组件自采的休息位可能早于舞台布局，
	# 此刻按当前布局位重采一次。
	_card.rotation_degrees = 0.0
	_card.scale = Vector2.ONE
	pop.capture_rest_position()
	pop.pop_in()


## 卡片回初始态：位置与变换先复位，宿主已有的演出组件一并归位（动画回初始态）。
func reset_page() -> void:
	_card.rotation_degrees = 0.0
	_card.scale = Vector2.ONE
	_card.position = _rest_position
	_card.modulate.a = 1.0
	_card.visible = true
	var zoom := _host.get_zoom()
	if zoom != null:
		zoom.is_expanded = true
	var rotate := _host.get_rotate()
	if rotate != null:
		rotate.is_upright = true
	var pop := _host.get_pop_out()
	if pop != null:
		pop.is_out = false
