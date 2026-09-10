extends ShowcasePage
## 演示页·拨盘拖动 OrbitTrack：在抓取半径内按住鼠标沿圆周拨动，轨道像老式
## 电话拨号盘一样跟随指针旋转（支持多圈），松手后补间回正到拨动开始的角度。
## 演示回正开关与自转共存：拨动与回正期间自转暂停，回正完成后恢复。
## 卡片由本页脚本从隐藏模板复制挂载——OrbitTrack 只负责排列，不创建业务子节点。

const CARD_COUNT := 4
const CARD_HUES: PackedFloat32Array = [0.58, 0.08, 0.33, 0.13]


var _orbit: OrbitTrack
var _snap_toggle: CheckButton
var _spin_toggle: CheckButton
var _card_template: Panel


func _ready() -> void:
	_orbit = %Orbit as OrbitTrack
	_snap_toggle = %SnapBackToggle as CheckButton
	_spin_toggle = %SpinToggle as CheckButton
	_card_template = %CardTemplate as Panel
	_apply_dial_defaults()
	_snap_toggle.toggled.connect(_on_snap_toggled)
	_spin_toggle.toggled.connect(_on_spin_toggled)
	(%DealButton as Button).pressed.connect(_on_deal_pressed)
	_rebuild_cards()


## 重置回四张初始卡片：回正开启、自转关闭、轨道角度归零，随后播放发牌动画。
func reset_page() -> void:
	_rebuild_cards()
	_apply_dial_defaults()
	_snap_toggle.set_pressed_no_signal(true)
	_spin_toggle.set_pressed_no_signal(false)
	_orbit.rotation = 0.0
	_orbit.relayout_slots()
	_orbit.play_deal_animation()


func _on_deal_pressed() -> void:
	_orbit.play_deal_animation()


## 拨盘是本页的存在意义，运行时统一从脚本落配置，场景只存通用布局属性。
func _apply_dial_defaults() -> void:
	_orbit.rotary_drag_enabled = true
	_orbit.snap_back_on_release = true
	_orbit.set_orbit_spinning(false)


func _rebuild_cards() -> void:
	for control in _orbit.get_orbit_controls():
		_orbit.remove_child(control)
		control.queue_free()
	for index in CARD_COUNT:
		var card := _card_template.duplicate() as Panel
		(card.get_node("Caption") as Label).text = "拨号 %d" % (index + 1)
		card.modulate = Color.from_hsv(CARD_HUES[index], 0.55, 1.0)
		card.visible = true
		_orbit.add_child(card)


func _on_snap_toggled(snap_back: bool) -> void:
	_orbit.snap_back_on_release = snap_back


func _on_spin_toggled(spinning: bool) -> void:
	_orbit.set_orbit_spinning(spinning)
