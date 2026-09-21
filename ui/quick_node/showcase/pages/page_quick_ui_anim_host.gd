extends ShowcasePage
## 演示页·动画宿主 QuickUiAnimHost：入场与离场各一个宿主，树序即编排（显形 →
## 放大 → 晃动 → 鼠标处定位；离场缩回后隐藏）。卡片 authored 初始态＝隐藏＋缩 0，
## 复位即回该初始态；行为参数都在演出子节点上直接调，全部以 node_paths 烘焙在
## 本场景里。

var _card: Control
var _rest_position: Vector2


func _ready() -> void:
	_card = %BakedCard as Control
	# 卡片是页面的手工摆放子节点，布局 position 即场景内 authored 值，就绪即可快照。
	_rest_position = _card.position


## 卡片回 authored 初始态（隐藏＋缩 0）。
func reset_page() -> void:
	_card.rotation_degrees = 0.0
	_card.scale = Vector2.ZERO
	_card.position = _rest_position
	_card.modulate.a = 1.0
	_card.visible = false
