extends ShowcasePage
## 边界演示：持续能力宿主接收拖动提议，经标记边界约束后提交卡片位置。
## 场景树声明宿主、拖动件和约束阶段，重置时恢复目标与能力状态。

var _card_origin: Vector2


func _ready() -> void:
	_card_origin = (%Card as Control).position


## 卡片归位。
func reset_page() -> void:
	(%Card.get_node("QuickUiAbilityHost") as QuickUiAbilityHost).cancel_input()
	(%Card as Control).position = _card_origin
	(%Card.get_node("QuickUiAbilityHost") as QuickUiAbilityHost).reset_abilities()
