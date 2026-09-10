extends ShowcasePage
## 演示页·快捷拖拽 QuickDrag：上方卡片自由拖动；下方细长卡只能水平拖
## 且最多右移 240px（HORIZONTAL_ONLY + 区间限制）。按压点即抓取基准，
## 拖动中保持抓取偏移不跳动。两个拖拽组件与绑定（dragged_ui / clickable_ui）
## 直接序列化在本场景里——组件作卡片子节点、以 ".." 回指宿主卡片。

var _free_card_origin: Vector2
var _knob_origin: Vector2


func _ready() -> void:
	_free_card_origin = (%FreeCard as Control).position
	_knob_origin = (%SliderKnob as Control).position


## 两张可拖卡归位。
func reset_page() -> void:
	(%FreeCard as Control).position = _free_card_origin
	(%SliderKnob as Control).position = _knob_origin
