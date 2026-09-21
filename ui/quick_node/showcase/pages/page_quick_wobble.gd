extends ShowcasePage
## QuickWobble 演示页：QuickZoom（缩放）× QuickWobble（晃动反馈）叠加在同一宿主上。
## 入场宿主的同播组把「放大展开」与「晃动一次」同帧齐播；离场宿主把缩放播放回
## 收起端。两者互不认识——组合完全由宿主树序（同播组）表达，页面脚本只接工具栏。

func _ready() -> void:
	%ButtonDirection.pressed.connect(_on_direction_pressed)


func _on_direction_pressed() -> void:
	var rotate := %Rotate as QuickWobble
	var flipped: Array[float] = []
	for angle in rotate.wobble_sequence:
		flipped.append(-angle)
	rotate.wobble_sequence = flipped


func reset_page() -> void:
	var rotate := %Rotate as QuickWobble
	var default_sequence: Array[float] = [-25.0]
	rotate.wobble_sequence = default_sequence
	(%HostCard as Control).scale = Vector2.ZERO
