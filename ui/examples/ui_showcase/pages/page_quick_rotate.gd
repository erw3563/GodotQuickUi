extends UIShowcasePage
## QuickRotate 演示页：QuickZoom（缩放）× QuickRotate（旋转）叠加在同一宿主上的
## 合成出场演出。两者互不认识——同步完全靠场景里序列化的
## Zoom.expanded_changed → Rotate.set_upright 连接，页面脚本只接工具栏。

func _ready() -> void:
	var zoom := %Zoom as QuickZoom
	%ButtonExpand.pressed.connect(zoom.expand)
	%ButtonCollapse.pressed.connect(zoom.collapse)
	%ButtonDirection.pressed.connect(_on_direction_pressed)


func _on_direction_pressed() -> void:
	var rotate := %Rotate as QuickRotate
	rotate.start_rotation_degrees = -rotate.start_rotation_degrees


func reset_page() -> void:
	var zoom := %Zoom as QuickZoom
	var rotate := %Rotate as QuickRotate
	rotate.start_rotation_degrees = -25.0
	zoom.collapse()
