@tool
class_name DealHBoxContainer
extends DealBoxContainer
## 水平发牌盒容器：布局（size flags、separation 等）为引擎水平盒语义，
## 子控件默认从左侧依次滑入落位（deal_direction 可改为其余三向，如右侧滑入）。
## 发牌参数与行为契约见 DealBoxContainer。
## 可直接挂到既有 HBoxContainer 节点，也可动态 new()：VBoxContainer/HBoxContainer
## 是引擎固定方向子类（不可再设 vertical），方向已正确时跳过赋值。

func _init() -> void:
	if vertical:
		vertical = false
	deal_direction = DealDirection.FROM_LEFT
