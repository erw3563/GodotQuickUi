extends ShowcasePage
## 演示页·旋转晃动面板 RotatePanel：交互（悬停进入热区/点击热区/按钮）触发一次
## 旋转晃动——依次停靠 wobble_sequence 各角后收常态角，播放中再触发从头重播。
## 「晃一次」直接播放；「序列」按钮一键换晃动形状（轻晃/往返/整圈），「方案」
## 预设换组合（默认轻摆 [-25,15]、双向大摆 [-120,120,360]），「弹性15°」开每段
## 回弹；勾选框开启悬停触发/点击触发（鼠标进入热区即晃一次，移出不打断），
## 「外部热区」把侦测区域外接到淡色矩形，「轴心」换旋转中心（静息改角即刻吸附）。

func _ready() -> void:
	var rotate_panel := %RotatePanel as RotatePanel
	%ButtonRest.pressed.connect(rotate_panel.stop_wobble)
	%ButtonPose1.pressed.connect(func():
		var light: Array[float] = [-25.0]
		rotate_panel.wobble_sequence = light)
	%ButtonPose2.pressed.connect(func():
		var round_trip: Array[float] = [-25.0, 15.0]
		rotate_panel.wobble_sequence = round_trip)
	%ButtonPose3.pressed.connect(func():
		var spin: Array[float] = [-360.0]
		rotate_panel.wobble_sequence = spin)
	%ButtonPlaySequence.pressed.connect(rotate_panel.play_wobble)
	%ButtonPresetDefault.pressed.connect(_apply_preset_default)
	%ButtonPresetBidirectional.pressed.connect(_apply_preset_bidirectional)
	%CheckElastic.toggled.connect(
		func(on: bool): rotate_panel.elastic_rotation_degrees = 15.0 if on else 0.0
	)
	%ButtonOriginCenter.pressed.connect(func(): rotate_panel.origin_ratio = Vector2(0.5, 0.5))
	%ButtonOriginTopLeft.pressed.connect(func(): rotate_panel.origin_ratio = Vector2.ZERO)
	%CheckHover.toggled.connect(func(on: bool): rotate_panel.play_on_mouse_hover = on)
	%CheckClick.toggled.connect(func(on: bool): rotate_panel.play_on_click = on)
	%CheckExternalZone.toggled.connect(_apply_external_zone)


## 方案预设：默认轻摆（[-25,15]，正负往返）。
func _apply_preset_default() -> void:
	var rotate_panel := %RotatePanel as RotatePanel
	rotate_panel.rest_rotation_degrees = 0.0
	var default_sequence: Array[float] = [-25.0, 15.0]
	rotate_panel.wobble_sequence = default_sequence


## 方案预设：双向大摆（[-120,120,360]，逆/顺时针大摆 + 整圈旋转）。
func _apply_preset_bidirectional() -> void:
	var rotate_panel := %RotatePanel as RotatePanel
	rotate_panel.rest_rotation_degrees = 0.0
	var big_sequence: Array[float] = [-120.0, 120.0, 360.0]
	rotate_panel.wobble_sequence = big_sequence


## 外部热区勾选：显示淡色矩形并接为面板热区；取消则隐藏并还原内置热区。
func _apply_external_zone(on: bool) -> void:
	var rotate_panel := %RotatePanel as RotatePanel
	var hot_zone := %HotZone as ColorRect
	hot_zone.visible = on
	rotate_panel.interaction_control = hot_zone if on else null


## 序列方案、弹性、轴心与交互开关复位并归常态。
func reset_page() -> void:
	var rotate_panel := %RotatePanel as RotatePanel
	_apply_preset_default()
	rotate_panel.elastic_rotation_degrees = 0.0
	rotate_panel.origin_ratio = Vector2(0.5, 0.5)
	rotate_panel.play_on_mouse_hover = false
	rotate_panel.play_on_click = false
	%CheckElastic.set_pressed_no_signal(false)
	%CheckHover.set_pressed_no_signal(false)
	%CheckClick.set_pressed_no_signal(false)
	%CheckExternalZone.set_pressed_no_signal(false)
	_apply_external_zone(false)
	rotate_panel.stop_wobble()
