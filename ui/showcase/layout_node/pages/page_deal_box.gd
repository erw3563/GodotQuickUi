extends ShowcasePage
## 演示页·V/H 发牌盒容器：DealVBoxContainer 竖直下落与 DealHBoxContainer 水平滑入，
## 偏移距离、齐发模式与发牌重播；卡片增删针对竖直容器。卡片由本页脚本从隐藏
## 模板复制挂载——容器只负责排列，不创建业务子节点。

const INITIAL_CARD_COUNT := 4
const CARD_HUES: PackedFloat32Array = [0.58, 0.08, 0.33, 0.13]


var _v_box: DealBoxContainer
var _h_box: DealBoxContainer
var _offset_slider: HSlider
var _offset_value: Label
var _simultaneous_toggle: CheckButton
var _card_template: Panel


func _ready() -> void:
	_v_box = %DealVBox as DealBoxContainer
	_h_box = %DealHBox as DealBoxContainer
	_offset_slider = %OffsetSlider as HSlider
	_offset_value = %OffsetValue as Label
	_simultaneous_toggle = %SimultaneousToggle as CheckButton
	_card_template = %CardTemplate as Panel
	_offset_slider.value_changed.connect(_on_offset_changed)
	(%DealButton as Button).pressed.connect(_on_deal_pressed)
	(%AddCardButton as Button).pressed.connect(_on_add_card)
	(%RemoveCardButton as Button).pressed.connect(_on_remove_card)
	_simultaneous_toggle.toggled.connect(_on_simultaneous_toggled)
	_rebuild_initial_cards()


## 重置回初始卡片与参数（偏移 80、错峰起播），随后两容器各重播发牌。
func reset_page() -> void:
	_rebuild_initial_cards()
	_offset_slider.set_value_no_signal(80.0)
	_apply_offset(80.0)
	_simultaneous_toggle.set_pressed_no_signal(false)
	_apply_simultaneous(false)
	_play_all()


func _on_offset_changed(value: float) -> void:
	_apply_offset(value)


func _apply_offset(value: float) -> void:
	_v_box.deal_offset_pixels = value
	_h_box.deal_offset_pixels = value
	_offset_value.text = "%d px" % int(value)


func _on_simultaneous_toggled(simultaneous: bool) -> void:
	_apply_simultaneous(simultaneous)


func _apply_simultaneous(simultaneous: bool) -> void:
	var mode: DealBoxContainer.DealLaunchMode = \
			DealBoxContainer.DealLaunchMode.SIMULTANEOUS if simultaneous \
			else DealBoxContainer.DealLaunchMode.STAGGERED
	_v_box.deal_launch_mode = mode
	_h_box.deal_launch_mode = mode


func _on_deal_pressed() -> void:
	_play_all()


func _play_all() -> void:
	_v_box.play_deal_animation()
	_h_box.play_deal_animation()


func _rebuild_initial_cards() -> void:
	for control in _v_box.get_deal_controls():
		_v_box.remove_child(control)
		control.queue_free()
	for control in _h_box.get_deal_controls():
		_h_box.remove_child(control)
		control.queue_free()
	for index in INITIAL_CARD_COUNT:
		var card := _spawn_card(_v_box, index)
		card.self_modulate = Color.from_hsv(CARD_HUES[index % CARD_HUES.size()], 0.55, 1.0)
	for index in INITIAL_CARD_COUNT:
		var card := _spawn_card(_h_box, index)
		card.self_modulate = Color.from_hsv(CARD_HUES[index % CARD_HUES.size()], 0.55, 1.0)


func _spawn_card(box: DealBoxContainer, slot_index: int) -> Panel:
	var card := _card_template.duplicate() as Panel
	(card.get_node("Caption") as Label).text = "卡片 %d" % (slot_index + 1)
	card.visible = true
	box.add_child(card)
	return card


func _on_add_card() -> void:
	var slot_index := _v_box.get_deal_control_count()
	var card := _spawn_card(_v_box, slot_index)
	card.self_modulate = Color.from_hsv(CARD_HUES[slot_index % CARD_HUES.size()], 0.55, 1.0)


func _on_remove_card() -> void:
	var controls := _v_box.get_deal_controls()
	if controls.is_empty():
		return
	var last := controls[controls.size() - 1]
	_v_box.remove_child(last)
	last.queue_free()
