@tool
class_name DealVBoxContainer
extends DealBoxContainer
## 竖直发牌盒容器：布局（size flags、separation 等）为引擎竖直盒语义，
## 子控件默认从上方依次下落入位（deal_direction 可改为其余三向）。
## 发牌参数与行为契约见 DealBoxContainer。
## 可直接挂到既有 VBoxContainer 节点，也可动态 new()：VBoxContainer/HBoxContainer
## 是引擎固定方向子类（不可再设 vertical），方向已正确时跳过赋值。

func _init() -> void:
	if not vertical:
		vertical = true
	deal_direction = DealDirection.FROM_TOP
