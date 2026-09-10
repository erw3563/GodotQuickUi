extends ShowcasePage
## 演示页·环形排列 OrbitTrack：直接 Control 子节点按场景树顺序均匀排上环形轨道，
## 子控件自身保持直立，自转状态属于轨道实例。本页演示自转开关、半径调节、
## 增删卡片与隐藏占位（隐藏的 Control 仍占槽位；非 Control 子节点不参与排列）、
## 发牌动画与起播模式（错峰/齐发）。
## 卡片由本页脚本从隐藏模板复制挂载——OrbitTrack 只负责排列，不创建业务子节点。

const INITIAL_CARD_COUNT := 5
const INITIAL_RADIUS := 150.0
const CARD_HUES: PackedFloat32Array = [0.58, 0.08, 0.33, 0.13, 0.72]


var _orbit: OrbitTrack
var _spin_toggle: CheckButton
var _radius_slider: HSlider
var _radius_value: Label
var _hide_button: Button
var _simultaneous_toggle: CheckButton
var _card_template: Panel


func _ready() -> void:
	_orbit = %Orbit as OrbitTrack
	_spin_toggle = %SpinToggle as CheckButton
	_radius_slider = %RadiusSlider as HSlider
	_radius_value = %RadiusValue as Label
	_hide_button = %HideCardButton as Button
	_simultaneous_toggle = %SimultaneousToggle as CheckButton
	_card_template = %CardTemplate as Panel
	_spin_toggle.toggled.connect(_on_spin_toggled)
	_radius_slider.value_changed.connect(_on_radius_changed)
	(%AddCardButton as Button).pressed.connect(_on_add_card)
	(%RemoveCardButton as Button).pressed.connect(_on_remove_card)
	_hide_button.pressed.connect(_on_toggle_first_card_visible)
	_simultaneous_toggle.toggled.connect(_on_simultaneous_toggled)
	(%DealButton as Button).pressed.connect(_on_deal_pressed)
	_rebuild_initial_cards()


## 重置回五张初始卡片：自转开启、半径恢复 150、首卡恢复显示、错峰起播模式，
## 随后播放发牌动画。
func reset_page() -> void:
	_rebuild_initial_cards()
	_spin_toggle.set_pressed_no_signal(true)
	_orbit.set_orbit_spinning(true)
	_radius_slider.set_value_no_signal(INITIAL_RADIUS)
	_apply_radius(INITIAL_RADIUS)
	_simultaneous_toggle.set_pressed_no_signal(false)
	_orbit.deal_launch_mode = OrbitTrack.DealLaunchMode.STAGGERED
	_orbit.play_deal_animation()


func _on_simultaneous_toggled(simultaneous: bool) -> void:
	_orbit.deal_launch_mode = OrbitTrack.DealLaunchMode.SIMULTANEOUS if simultaneous \
		else OrbitTrack.DealLaunchMode.STAGGERED


func _on_deal_pressed() -> void:
	_orbit.play_deal_animation()


func _rebuild_initial_cards() -> void:
	for control in _orbit.get_orbit_controls():
		_orbit.remove_child(control)
		control.queue_free()
	for index in INITIAL_CARD_COUNT:
		var card := _spawn_card(index)
		card.modulate = Color.from_hsv(CARD_HUES[index], 0.55, 1.0)
		# 初始五张卡宽窄交替，直观展示不同尺寸控件的中心都落在轨道槽位上。
		card.size = Vector2(112.0 + 24.0 * (index % 3), 60.0)
	_update_hide_button_text(true)


func _spawn_card(slot_index: int) -> Panel:
	var card := _card_template.duplicate() as Panel
	(card.get_node("Caption") as Label).text = "卡片 %d" % (slot_index + 1)
	card.visible = true
	_orbit.add_child(card)
	return card


func _on_spin_toggled(spinning: bool) -> void:
	_orbit.set_orbit_spinning(spinning)


func _on_radius_changed(value: float) -> void:
	_apply_radius(value)


## 半径不是自动触发重排的属性，改完显式调用 relayout_slots 收敛一次。
func _apply_radius(value: float) -> void:
	_orbit.orbit_radius = value
	_orbit.relayout_slots()
	_radius_value.text = "%d px" % int(value)


func _on_add_card() -> void:
	var slot_index := _orbit.get_orbit_control_count()
	var card := _spawn_card(slot_index)
	card.modulate = Color.from_hsv(CARD_HUES[slot_index % CARD_HUES.size()], 0.55, 1.0)


func _on_remove_card() -> void:
	var controls := _orbit.get_orbit_controls()
	if controls.is_empty():
		return
	var last := controls[controls.size() - 1]
	_orbit.remove_child(last)
	last.queue_free()


func _on_toggle_first_card_visible() -> void:
	var controls := _orbit.get_orbit_controls()
	if controls.is_empty():
		return
	var first := controls[0]
	first.visible = not first.visible
	_update_hide_button_text(first.visible)


func _update_hide_button_text(first_visible: bool) -> void:
	_hide_button.text = "隐藏首卡（仍占槽位）" if first_visible else "恢复首卡显示"
