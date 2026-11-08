@tool
class_name DecoratedNinePatchPanel
extends Control
## 带装饰的九宫格面板。边框场景以九宫格切片和装饰控件的锚点排布外观。

## 全矩形锚定的边框场景。边框的最小尺寸为固定切片和装饰预留空间。
@export var frame: Control:
	set(value):
		if frame == value:
			return
		if is_instance_valid(frame):
			frame.minimum_size_changed.disconnect(update_minimum_size)
		frame = value
		if is_instance_valid(frame):
			frame.minimum_size_changed.connect(update_minimum_size)
		update_minimum_size()

## 当前布局宽度。尺寸演出沿水平增长方向调整边缘。
@export_custom(PROPERTY_HINT_RANGE, "0,4096,1,or_greater,suffix:px", PROPERTY_USAGE_EDITOR)
var layout_width: float:
	get:
		return size.x
	set(value):
		_resize_frame(Vector2(value, size.y))

## 当前布局高度。尺寸演出沿垂直增长方向调整边缘。
@export_custom(PROPERTY_HINT_RANGE, "0,4096,1,or_greater,suffix:px", PROPERTY_USAGE_EDITOR)
var layout_height: float:
	get:
		return size.y
	set(value):
		_resize_frame(Vector2(size.x, value))


## 返回装饰边框在面板局部坐标中的布局矩形。
func get_frame_rect() -> Rect2:
	return frame.get_rect() if is_instance_valid(frame) else Rect2(Vector2.ZERO, size)


func _get_minimum_size() -> Vector2:
	if not is_instance_valid(frame):
		return Vector2.ZERO
	var frame_margins := Vector2(
		frame.offset_left - frame.offset_right,
		frame.offset_top - frame.offset_bottom
	)
	return frame.get_combined_minimum_size() + frame_margins


func _resize_frame(requested_size: Vector2) -> void:
	var target_size := requested_size.max(get_combined_minimum_size())
	var growth_origin := Vector2(
		_growth_origin(grow_horizontal),
		_growth_origin(grow_vertical)
	)
	var pinned_position := position + (size - target_size) * growth_origin
	size = target_size
	position = pinned_position


func _growth_origin(direction: GrowDirection) -> float:
	match direction:
		GROW_DIRECTION_BEGIN:
			return 1.0
		GROW_DIRECTION_BOTH:
			return 0.5
	return 0.0
