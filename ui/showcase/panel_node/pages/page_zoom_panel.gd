extends ShowcasePage
## 演示页·缩放面板 ZoomPanel：点「展开/收起」体验起点与终点缩放驱动的放大/缩回；
## 按钮把原点切到左上角或正中心、目标缩放切换展开终态大小，勾选框开启侧边栏式
## 悬停/点击切换，「外部热区」把侦测区域外接到淡色矩形，「收起留种子」收起后
## 保留 0.3x 可见种子不隐藏（配悬停展开即停靠栏效果）。

func _ready() -> void:
	var zoom_panel := %ZoomPanel as ZoomPanel
	%ButtonExpand.pressed.connect(zoom_panel.expand)
	%ButtonCollapse.pressed.connect(zoom_panel.collapse)
	%ButtonOriginCenter.pressed.connect(func(): zoom_panel.origin_ratio = Vector2(0.5, 0.5))
	%ButtonOriginTopLeft.pressed.connect(func(): zoom_panel.origin_ratio = Vector2.ZERO)
	%ButtonScaleSmall.pressed.connect(func(): zoom_panel.expanded_scale = Vector2(0.6, 0.6))
	%ButtonScaleNormal.pressed.connect(func(): zoom_panel.expanded_scale = Vector2.ONE)
	%ButtonScaleLarge.pressed.connect(func(): zoom_panel.expanded_scale = Vector2(1.4, 1.4))
	%CheckHover.toggled.connect(func(on: bool): zoom_panel.expand_on_mouse_hover = on)
	%CheckClick.toggled.connect(func(on: bool): zoom_panel.toggle_on_click = on)
	%CheckExternalZone.toggled.connect(_apply_external_zone)
	%CheckSeed.toggled.connect(
		func(on: bool): zoom_panel.collapsed_scale = Vector2(0.3, 0.3) if on else Vector2.ZERO
	)


## 外部热区勾选：显示淡色矩形并接为面板热区；取消则隐藏并还原内置热区。
func _apply_external_zone(on: bool) -> void:
	var zoom_panel := %ZoomPanel as ZoomPanel
	var hot_zone := %HotZone as ColorRect
	hot_zone.visible = on
	zoom_panel.interaction_control = hot_zone if on else null


## 原点回中心、起点/目标缩放与交互开关复位并收起。
func reset_page() -> void:
	var zoom_panel := %ZoomPanel as ZoomPanel
	zoom_panel.origin_ratio = Vector2(0.5, 0.5)
	zoom_panel.expanded_scale = Vector2.ONE
	zoom_panel.collapsed_scale = Vector2.ZERO
	zoom_panel.expand_on_mouse_hover = false
	zoom_panel.toggle_on_click = false
	%CheckHover.set_pressed_no_signal(false)
	%CheckClick.set_pressed_no_signal(false)
	%CheckExternalZone.set_pressed_no_signal(false)
	%CheckSeed.set_pressed_no_signal(false)
	_apply_external_zone(false)
	zoom_panel.collapse()
