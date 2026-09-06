extends UIShowcasePage
## 演示页·缩放组件 QuickZoom：任意 Control 挂上 QuickZoom 即可从原点
## 放大/缩回（只动 scale/pivot/modulate，布局全程不变）；「收起后隐藏」
## 开关演示 hide_on_collapse——关掉后可见性归外部所有者，可与 QuickShow
## 组合。组件经场景 NodePath 绑定 ui（".."）。

func _ready() -> void:
	var zoom := %Zoom as QuickZoom
	%ButtonExpand.pressed.connect(zoom.expand)
	%ButtonCollapse.pressed.connect(zoom.collapse)
	%ButtonOriginCenter.pressed.connect(func(): zoom.origin_ratio = Vector2(0.5, 0.5))
	%ButtonOriginTopLeft.pressed.connect(func(): zoom.origin_ratio = Vector2.ZERO)
	%HideToggle.toggled.connect(func(pressed: bool): zoom.hide_on_collapse = pressed)


## 原点回中心、收起、恢复「收起后隐藏」。
func reset_page() -> void:
	var zoom := %Zoom as QuickZoom
	zoom.origin_ratio = Vector2(0.5, 0.5)
	zoom.hide_on_collapse = true
	(%HideToggle as CheckButton).set_pressed_no_signal(true)
	zoom.collapse()
