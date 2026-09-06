extends UIShowcasePage
## 演示页·边界约束 QuickConstraints（宿主装配）：自由拖动卡片——拖拽落笔经
## QuickHost 中介以 INTERACTIVE 意图裁决、过 QuickConstraints stage 钳制后唯一
## 落笔，始终被夹在四角浅色标记框内。钳制目标用两个零尺寸隐形标记：min 取其
## 原点，max 需额外扣除卡片自身宽高（220/120 + 6px 边距）；QuickHost 生成
## QuickDrag + QuickConstraints，标记与绑定全部序列化在本场景里。

var _card_origin: Vector2


func _ready() -> void:
	_card_origin = (%Card as Control).position


## 卡片归位。
func reset_page() -> void:
	(%Card as Control).position = _card_origin
