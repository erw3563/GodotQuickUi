extends ShowcasePage
## 演示页·OrbitTrack：直接 Control 子节点按场景树顺序均匀排上环形轨道，子控件
## 自身保持直立。本页同时演示自转开关、半径调节、增删卡片、隐藏占位、发牌动画
## 与起播模式，以及拨盘拖动（环带内按住跟手旋转、松手可选回正；拨动与回正期间
## 自转暂停）。卡片由本页脚本从隐藏模板复制挂载——OrbitTrack 只负责排列，不创建
## 业务子节点。

const INITIAL_CARD_COUNT := 5
const INITIAL_RADIUS := 150.0
const CARD_HUES: PackedFloat32Array = [0.58, 0.08, 0.33, 0.13, 0.72]


var _orbit: OrbitTrack
var _spin_toggle: CheckButton
var _snap_toggle: CheckButton
var _radius_slider: HSlider
var _radius_value: Label
var _hide_button: Button
var _simultaneous_toggle: CheckButton
var _card_template: Panel


func _ready() -> void:
	_orbit = %Orbit as OrbitTrack
	_spin_toggle = %SpinToggle as CheckButton
	_snap_toggle = %SnapBackToggle as CheckButton
	_radius_slider = %RadiusSlider as HSlider
	_radius_value = %RadiusValue as Label
	_hide_button = %HideCardButton as Button
	_simultaneous_toggle = %SimultaneousToggle as CheckButton
	_card_template = %CardTemplate as Panel
	_apply_interaction_defaults()
	_spin_toggle.toggled.connect(_on_spin_toggled)
	_snap_toggle.toggled.connect(_on_snap_toggled)
	_radius_slider.value_changed.connect(_on_radius_changed)
	(%AddCardButton as Button).pressed.connect(_on_add_card)
	(%RemoveCardButton as Button).pressed.connect(_on_remove_card)
	_hide_button.pressed.connect(_on_toggle_first_card_visible)
	_simultaneous_toggle.toggled.connect(_on_simultaneous_toggled)
	(%DealButton as Button).pressed.connect(_on_deal_pressed)
	_rebuild_initial_cards()


## 重置回五张初始卡片：自转开启、回正开启、半径恢复 150、轨道相位归零、首卡恢复显示、
## 错峰起播模式，随后播放发牌动画。
func reset_page() -> void:
	_rebuild_initial_cards()
	_apply_interaction_defaults()
	_spin_toggle.set_pressed_no_signal(true)
	_snap_toggle.set_pressed_no_signal(true)
	_radius_slider.set_value_no_signal(INITIAL_RADIUS)
	_apply_radius(INITIAL_RADIUS)
	_simultaneous_toggle.set_pressed_no_signal(false)
	_orbit.deal_launch_mode = OrbitTrack.DealLaunchMode.STAGGERED
	_orbit.orbit_phase = 0.0
	_orbit.relayout_slots()
	_orbit.play_deal_animation()


## 拨盘与回正确认为本页演示能力，运行时统一从脚本落配置。
func _apply_interaction_defaults() -> void:
	_orbit.rotary_drag_enabled = true
	_orbit.snap_back_on_release = true
	_orbit.set_orbit_spinning(true)


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


func _on_snap_toggled(snap_back: bool) -> void:
	_orbit.snap_back_on_release = snap_back


func _on_radius_changed(value: float) -> void:
	_apply_radius(value)


## 以相等的 X/Y 半径保持圆形轨道，并刷新槽位与数值标签。
func _apply_radius(value: float) -> void:
	_orbit.orbit_radii = Vector2.ONE * value
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
