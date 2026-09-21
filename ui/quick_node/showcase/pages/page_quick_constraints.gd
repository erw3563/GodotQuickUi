extends ShowcasePage
## 演示页·边界约束 QuickConstraints（散装装配）：自由拖动卡片——拖拽落笔经
## QuickUiAnimHost 中介以 INTERACTIVE 意图裁决、过 QuickConstraints stage 钳制后唯一
## 落笔，始终被夹在四角浅色标记框内。钳制目标用两个零尺寸隐形标记：min 取其
## 原点，max 需额外扣除卡片自身宽高（220/120 + 6px 边距）；QuickDrag 与
## QuickConstraints 均为散装组件手工烘焙在本场景里——drag 的 placer 手工指宿主、
## constraints 挂宿主名下作 stage（树序首位，钳制为第一道）。

var _card_origin: Vector2


func _ready() -> void:
	_card_origin = (%Card as Control).position


## 卡片归位。
func reset_page() -> void:
	(%Card as Control).position = _card_origin
