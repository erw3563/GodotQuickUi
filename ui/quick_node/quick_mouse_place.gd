class_name QuickMousePlace
extends Node
## 鼠标处定位：placement 提议者，位置落笔以 PLACEMENT 意图经中介（[member placer]）
## 裁决加工，演出租约期间被忽略；留空则直写（散装，语义等价于空管道）。
## 只定位置、不碰显隐——联动 [member show] 非空时定位完成后交由其显形。

@export var control: Control
## 强制 control 控件全部显示在屏幕内
@export var is_show_in_viewport: bool = true
## 强制处于鼠标位置的是 control 控件的四个顶点之一。如果不开启 is_show_in_viewport 则会一直显示为左上角处于鼠标位置。
@export var is_point_in_mouse_pos: bool = true
## 控件在x轴上是否居中,居中优先级低于强制全部显示与强制处于顶点
@export var is_control_x_center: bool = false
## 控件在y轴上是否居中,居中优先级低于强制全部显示与强制处于顶点
@export var is_control_y_center: bool = false
## 控件与鼠标位置的偏移
@export var offset: Vector2
## 定位前把控件收缩回内容最小尺寸（经 Control.reset_size，不绕过布局系统；
## 隐藏状态下 size 即最小大小，先收缩才能算准定位与钳制）
@export var shrink_to_content: bool = true
## 位置落笔中介（鸭子契约：实现 place(control, proposed, intent) 的节点，QuickHost 即是）；
## 定位落笔以 PLACEMENT 意图经其裁决加工，演出租约期间被忽略。留空则直写（散装）。
@export var placer: Node
## 可选联动显隐组件：定位完成后调用其 show()（显隐节奏——含 popout 动画——归其所有）
@export var show: QuickShow

## 定位到鼠标处：先按最小尺寸算定位（隐藏状态下 size 即最小大小），
## 落笔经仲裁者钳制，最后交联动组件显形。
func place_at_mouse() -> void:
	if control == null:
		return
	if shrink_to_content:
		control.reset_size()
	var new_pos := control.get_global_mouse_position()
	if not is_point_in_mouse_pos:
		if is_control_x_center:
			new_pos.x -= control.size.x / 2
		if is_control_y_center:
			new_pos.y -= control.size.y / 2
	if is_show_in_viewport:
		if is_point_in_mouse_pos:
			# 顶点策略：越界的一侧整体翻到鼠标另一侧
			var viewport_rect := control.get_viewport_rect()
			if new_pos.x + control.size.x > viewport_rect.end.x:
				new_pos.x -= control.size.x
			if new_pos.y + control.size.y > viewport_rect.end.y:
				new_pos.y -= control.size.y
		else:
			new_pos = _clamp_rect_inside_viewport(new_pos)
	_place_proposed(new_pos + offset)
	if show != null:
		show.show()

## 定位落笔：经中介以定位意图加工（无中介时直写，语义等价于空管道）。
func _place_proposed(proposed: Vector2) -> void:
	if placer != null and placer.has_method("place"):
		placer.place(control, proposed, QuickUI.PlaceIntent.PLACEMENT)
	else:
		control.global_position = proposed

## 把整块控件（含尺寸）钳进视口。
func _clamp_rect_inside_viewport(pos: Vector2) -> Vector2:
	var viewport_rect := control.get_viewport_rect()
	var result := pos
	result.x = clampf(result.x, viewport_rect.position.x, viewport_rect.end.x)
	result.y = clampf(result.y, viewport_rect.position.y, viewport_rect.end.y)
	result.x = clampf(result.x + control.size.x, viewport_rect.position.x, viewport_rect.end.x) - control.size.x
	result.y = clampf(result.y + control.size.y, viewport_rect.position.y, viewport_rect.end.y) - control.size.y
	return result
