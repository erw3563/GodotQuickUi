@tool
class_name DrawShapeControl
extends Control
## 形状绘制控件：在检查器里选择形状并配置参数，节点在 _draw 内绘制填充与描边。
## 轮廓顶点来自 ShapeOutline；参数夹取、画布命令与最小尺寸归本节点。
## 独特参数（圆角、边数、星形角数与内径比）按当前形状在检查器中显示。
## 局部坐标命中经 contains_point 提供：precise_hit_test 开启时鼠标命中按形状轮廓
## 判定，关闭时沿用 Control 的矩形命中；鼠标事件本身仍由 mouse_filter 过滤。
## 编辑器内即时预览；节点持有形状参数与绘制职责，配合检查器完成配置与预览。

@export_group("形状")
## 形状选择。
@export var shape: ShapeOutline.Kind = ShapeOutline.Kind.RECT:
	set(value):
		if shape == value:
			return
		shape = value
		notify_property_list_changed()
		queue_redraw()
## 方形圆角半径，夹取到短边的一半（形状为方形时生效）。
@export var corner_radius: float = 0.0:
	set(value):
		if corner_radius == value:
			return
		corner_radius = value
		queue_redraw()
## 正多边形边数（形状为正多边形时生效）。
@export var polygon_sides: int = 6:
	set(value):
		if polygon_sides == value:
			return
		polygon_sides = value
		queue_redraw()
## 星形角数（形状为星形时生效）。
@export var star_points: int = 5:
	set(value):
		if star_points == value:
			return
		star_points = value
		queue_redraw()
## 星形内顶点与外顶点的半径比（形状为星形时生效）。
@export var star_inner_ratio: float = 0.45:
	set(value):
		if star_inner_ratio == value:
			return
		star_inner_ratio = value
		queue_redraw()

@export_group("外观")
## 填充颜色，透明度为 0 时跳过填充。
@export var fill_color: Color = Color.WHITE:
	set(value):
		if fill_color == value:
			return
		fill_color = value
		queue_redraw()
## 描边颜色，透明度为 0 时跳过描边。
@export var outline_color: Color = Color(0.0, 0.0, 0.0, 0.0):
	set(value):
		if outline_color == value:
			return
		outline_color = value
		queue_redraw()
## 描边线宽：大于 0 时描边，轮廓按线宽一半内缩，描边落在控件范围内。
@export var outline_width: float = 0.0:
	set(value):
		if outline_width == value:
			return
		outline_width = value
		queue_redraw()
## 描边抗锯齿。
@export var anti_aliasing: bool = true:
	set(value):
		if anti_aliasing == value:
			return
		anti_aliasing = value
		queue_redraw()

@export_group("布局与命中")
## 最小尺寸：_get_minimum_size 的返回值。
@export var min_shape_size: Vector2 = Vector2(16.0, 16.0):
	set(value):
		if min_shape_size == value:
			return
		min_shape_size = value
		update_minimum_size()
		queue_redraw()
## 鼠标命中方式：开启后按形状轮廓判定，关闭时按控件矩形判定。
@export var precise_hit_test: bool = false


func _init() -> void:
	resized.connect(queue_redraw)


## 按当前形状隐藏无关导出：值仍参与序列化，检查器只显示当前形状所需参数。
func _validate_property(property: Dictionary) -> void:
	match property.name:
		"corner_radius":
			if shape != ShapeOutline.Kind.RECT:
				property.usage = PROPERTY_USAGE_NO_EDITOR
		"polygon_sides":
			if shape != ShapeOutline.Kind.POLYGON:
				property.usage = PROPERTY_USAGE_NO_EDITOR
		"star_points", "star_inner_ratio":
			if shape != ShapeOutline.Kind.STAR:
				property.usage = PROPERTY_USAGE_NO_EDITOR


func _get_minimum_size() -> Vector2:
	return min_shape_size


func _draw() -> void:
	var points := get_outline_points()
	if points.size() < 3:
		return
	if fill_color.a > 0.0:
		draw_colored_polygon(points, fill_color)
	if outline_width > 0.0 and outline_color.a > 0.0:
		var closed := points.duplicate()
		closed.append(points[0])
		draw_polyline(closed, outline_color, outline_width, anti_aliasing)


func _has_point(point: Vector2) -> bool:
	if not precise_hit_test:
		return Rect2(Vector2.ZERO, size).has_point(point)
	return contains_point(point)


## 当前尺寸下的形状轮廓（局部坐标，闭合顺序）；尺寸退化时返回空数组。
## 调用方按需查询轮廓用于拾取、对齐或自绘扩展。
func get_outline_points() -> PackedVector2Array:
	var settings := ShapeOutline.Settings.new()
	settings.corner_radius = corner_radius
	settings.polygon_sides = polygon_sides
	settings.star_points = star_points
	settings.star_inner_ratio = star_inner_ratio
	return ShapeOutline.build_points(shape, _content_rect(), settings)


## 按当前形状轮廓判断局部坐标点是否命中；凸凹形状共用同一入口。
func contains_point(point: Vector2) -> bool:
	var points := get_outline_points()
	if points.size() < 3:
		return false
	return Geometry2D.is_point_in_polygon(point, points)


## 形状占用的绘制矩形：按描边线宽一半内缩，描边落在控件范围内。
func _content_rect() -> Rect2:
	return Rect2(Vector2.ZERO, size).grow(-outline_width * 0.5)
