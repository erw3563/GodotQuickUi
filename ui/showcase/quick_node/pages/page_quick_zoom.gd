extends ShowcasePage
## 演示页·缩放演出件 QuickZoom：只管缩放——入场宿主持展开端点、离场宿主持收起
## 端点，play 从 authored 当前缩放到达目标（只动 scale/pivot，布局与可见性全程
## 不变，透明度与显隐归 QuickShow 组合表达）；「双向 / 高 / 宽 / 强调」预设切换
## 两端 target_scale（按分量 x=宽 y=高，单轴端点即纯高/纯宽缩放），切预设时把控
## 件直接吸附到收起端作为新起点；原点按钮切换两端 origin_ratio 钉扎位置。
## 顶部悬停强调宿主为非 0/1 端点演示（1.0 静息 ↔ 1.25 悬停脉冲），悬停检测由本页
## 轮询触发两个宿主（触发归调用方，演出件不自带输入处理）。

var _emphasis_inside := false


func _ready() -> void:
	%ButtonOriginCenter.pressed.connect(
		func(): _apply_origin(Vector2(0.5, 0.5)))
	%ButtonOriginTopLeft.pressed.connect(
		func(): _apply_origin(Vector2.ZERO))
	%ButtonPresetBoth.pressed.connect(
		func(): _apply_endpoints(Vector2.ZERO, Vector2.ONE))
	%ButtonPresetHeight.pressed.connect(
		func(): _apply_endpoints(Vector2(1, 0), Vector2.ONE))
	%ButtonPresetWidth.pressed.connect(
		func(): _apply_endpoints(Vector2(0, 1), Vector2.ONE))
	%ButtonPresetEmphasis.pressed.connect(
		func(): _apply_endpoints(Vector2.ONE, Vector2(1.25, 1.25)))


func _process(_delta: float) -> void:
	var card := %EmphasisCard as Control
	if not card.is_visible_in_tree():
		return
	var inside := card.get_global_rect().grow(60.0).has_point(card.get_global_mouse_position())
	if inside and not _emphasis_inside:
		(card.get_node("EnterHost") as QuickUiAnimHost).play()
	elif not inside and _emphasis_inside:
		(card.get_node("ExitHost") as QuickUiAnimHost).play()
	_emphasis_inside = inside


func _apply_origin(ratio: Vector2) -> void:
	(%ZoomEnter as QuickZoom).origin_ratio = ratio
	(%ZoomExit as QuickZoom).origin_ratio = ratio


func _apply_endpoints(exit_end: Vector2, enter_end: Vector2) -> void:
	(%ZoomExit as QuickZoom).target_scale = exit_end
	(%ZoomEnter as QuickZoom).target_scale = enter_end
	# 新端点就位：把控件直接吸附到收起端作为下一次播放的起点。
	(%HostCard as Control).scale = exit_end


## 原点回中心、端点回默认（双向 0↔1）并把两卡吸附回收起端；强调宿主指针离开自动
## 回静息，无需复位。
func reset_page() -> void:
	_apply_origin(Vector2(0.5, 0.5))
	_apply_endpoints(Vector2.ZERO, Vector2.ONE)
	_emphasis_inside = false
