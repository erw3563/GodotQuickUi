extends ShowcasePage
## 演示页·旋转面板 RotatePanel：触发直接连播完整序列 常态→目标1→目标2→目标3→常态，
## 一次播完收在常态角（播放中再触发从头重播）；目标角符号自定即可同时拥有
## 顺时针/逆时针旋转。按钮直达各姿态或连播序列，「方案」预设一键换角度配置
## （默认小摆 -25/25/180、双向大摆 -120/120/360），「弹性15°」开回弹
## （每段到目标角后多转 15° 再收回）；勾选框开启悬停连播/点击切换
## （鼠标进入热区即连播一次，移出不打断），「外部热区」把侦测区域外接到淡色矩形，
## 「轴心」换旋转中心（静息改角即刻吸附）。

func _ready() -> void:
	var rotate_panel := %RotatePanel as RotatePanel
	%ButtonRest.pressed.connect(rotate_panel.rotate_to_rest)
	%ButtonPose1.pressed.connect(func(): rotate_panel.rotate_to_pose(1))
	%ButtonPose2.pressed.connect(func(): rotate_panel.rotate_to_pose(2))
	%ButtonPose3.pressed.connect(func(): rotate_panel.rotate_to_pose(3))
	%ButtonPlaySequence.pressed.connect(rotate_panel.play_sequence)
	%ButtonPresetDefault.pressed.connect(_apply_preset_default)
	%ButtonPresetBidirectional.pressed.connect(_apply_preset_bidirectional)
	%CheckElastic.toggled.connect(
		func(on: bool): rotate_panel.elastic_rotation_degrees = 15.0 if on else 0.0
	)
	%ButtonOriginCenter.pressed.connect(func(): rotate_panel.origin_ratio = Vector2(0.5, 0.5))
	%ButtonOriginTopLeft.pressed.connect(func(): rotate_panel.origin_ratio = Vector2.ZERO)
	%CheckHover.toggled.connect(func(on: bool): rotate_panel.play_on_mouse_hover = on)
	%CheckClick.toggled.connect(func(on: bool): rotate_panel.toggle_on_click = on)
	%CheckExternalZone.toggled.connect(_apply_external_zone)


## 方案预设：默认小摆（-25/25/180，正负对称 + 半圈）。
func _apply_preset_default() -> void:
	var rotate_panel := %RotatePanel as RotatePanel
	rotate_panel.rest_rotation_degrees = 0.0
	rotate_panel.target_rotation_1 = -25.0
	rotate_panel.target_rotation_2 = 25.0
	rotate_panel.target_rotation_3 = 180.0


## 方案预设：双向大摆（-120/120/360，逆/顺时针大摆 + 整圈旋转）。
func _apply_preset_bidirectional() -> void:
	var rotate_panel := %RotatePanel as RotatePanel
	rotate_panel.rest_rotation_degrees = 0.0
	rotate_panel.target_rotation_1 = -120.0
	rotate_panel.target_rotation_2 = 120.0
	rotate_panel.target_rotation_3 = 360.0


## 外部热区勾选：显示淡色矩形并接为面板热区；取消则隐藏并还原内置热区。
func _apply_external_zone(on: bool) -> void:
	var rotate_panel := %RotatePanel as RotatePanel
	var hot_zone := %HotZone as ColorRect
	hot_zone.visible = on
	rotate_panel.interaction_control = hot_zone if on else null


## 角度方案、弹性、轴心与交互开关复位并回常态。
func reset_page() -> void:
	var rotate_panel := %RotatePanel as RotatePanel
	_apply_preset_default()
	rotate_panel.elastic_rotation_degrees = 0.0
	rotate_panel.origin_ratio = Vector2(0.5, 0.5)
	rotate_panel.play_on_mouse_hover = false
	rotate_panel.toggle_on_click = false
	%CheckElastic.set_pressed_no_signal(false)
	%CheckHover.set_pressed_no_signal(false)
	%CheckClick.set_pressed_no_signal(false)
	%CheckExternalZone.set_pressed_no_signal(false)
	_apply_external_zone(false)
	rotate_panel.rotate_to_rest()
