extends ShowcasePage
## 拖动演示：两张卡片分别以持续能力宿主管理自由拖动与水平限幅拖动。
## 场景树声明宿主、拖动件与输入目标，重置时取消捕获并恢复卡片布局。

var _free_card_origin: Vector2
var _knob_origin: Vector2


func _ready() -> void:
	_free_card_origin = (%FreeCard as Control).position
	_knob_origin = (%SliderKnob as Control).position


## 两张可拖卡归位。
func reset_page() -> void:
	(%FreeCard.get_node("AbilityHost") as QuickUiAbilityHost).cancel_input()
	(%SliderKnob.get_node("AbilityHost") as QuickUiAbilityHost).cancel_input()
	(%FreeCard as Control).position = _free_card_origin
	(%SliderKnob as Control).position = _knob_origin
	(%FreeCard.get_node("AbilityHost") as QuickUiAbilityHost).reset_abilities()
	(%SliderKnob.get_node("AbilityHost") as QuickUiAbilityHost).reset_abilities()
