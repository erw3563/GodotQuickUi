class_name ShapeOutline
extends RefCounted
## 形状轮廓几何：按目标矩形生成闭合折线顶点，供绘制与命中共用。
## 职责为坐标计算，节点、状态与画布命令归调用方；顶点按闭合顺序排列，绘制方在末尾补回首点。

## 形状枚举。
enum Kind {
	RECT, ## 方形：corner_radius 大于 0 时为圆角方形
	CIRCLE, ## 圆形：矩形不等边时得到椭圆
	DIAMOND, ## 菱形：四顶点落在矩形各边中点
	TRIANGLE, ## 三角形：正立，底边在下
	POLYGON, ## 正多边形：边数由 polygon_sides 决定
	STAR, ## 星形：角数与内径比可配
}

## 平滑段数下限与上限（圆形、圆角与自动推导共用）。
const MIN_SEGMENTS := 12
const MAX_SEGMENTS := 128
## 正多边形边数下限与上限。
const MIN_POLYGON_SIDES := 3
const MAX_POLYGON_SIDES := 64
## 星形角数下限与上限。
const MIN_STAR_POINTS := 3
const MAX_STAR_POINTS := 32
## 星形内径比下限与上限。
const MIN_STAR_INNER_RATIO := 0.05
const MAX_STAR_INNER_RATIO := 0.95


## 在 rect 内生成闭合轮廓顶点（局部坐标，按闭合顺序，绘制方在末尾补回首点）。
## rect 尺寸为零或负时返回空数组，调用方据此跳过绘制。
## corner_radius 作用于 RECT，polygon_sides 作用于 POLYGON，star_points 与
## star_inner_ratio 作用于 STAR；segments 为 0 时按矩形自动推导平滑段数。
static func build_points(
	kind: Kind,
	rect: Rect2,
	corner_radius := 0.0,
	polygon_sides := 6,
	star_points := 5,
	star_inner_ratio := 0.45,
	segments := 0
) -> PackedVector2Array:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return PackedVector2Array()
	var center := rect.get_center()
	var radius := rect.size * 0.5
	var steps := segments if segments > 0 else segments_for(rect)
	match kind:
		Kind.RECT:
			return _build_rect(rect, corner_radius, steps)
		Kind.CIRCLE:
			return _build_ellipse(center, radius, steps)
		Kind.DIAMOND:
			return PackedVector2Array([
				center + Vector2(0.0, -radius.y),
				center + Vector2(radius.x, 0.0),
				center + Vector2(0.0, radius.y),
				center + Vector2(-radius.x, 0.0),
			])
		Kind.TRIANGLE:
			return PackedVector2Array([
				center + Vector2(-radius.x, radius.y),
				center + Vector2(radius.x, radius.y),
				center + Vector2(0.0, -radius.y),
			])
		Kind.POLYGON:
			return _build_polygon(center, radius, clampi(polygon_sides, MIN_POLYGON_SIDES, MAX_POLYGON_SIDES))
		Kind.STAR:
			return _build_star(
				center,
				radius,
				clampi(star_points, MIN_STAR_POINTS, MAX_STAR_POINTS),
				clampf(star_inner_ratio, MIN_STAR_INNER_RATIO, MAX_STAR_INNER_RATIO)
			)
	return PackedVector2Array()


## 按矩形尺寸推导平滑段数：以椭圆周长近似值除以 4，夹取到
## [constant MIN_SEGMENTS, constant MAX_SEGMENTS]。
static func segments_for(rect: Rect2) -> int:
	var radius := rect.size * 0.5
	return clampi(int(ceil(PI * (radius.x + radius.y) / 4.0)), MIN_SEGMENTS, MAX_SEGMENTS)


## 方形与圆角方形：四角各采样一段圆弧，半径夹取到短边的一半。
static func _build_rect(rect: Rect2, corner_radius: float, steps: int) -> PackedVector2Array:
	var radius := clampf(corner_radius, 0.0, minf(rect.size.x, rect.size.y) * 0.5)
	if radius <= 0.0:
		return PackedVector2Array([
			rect.position,
			rect.position + Vector2(rect.size.x, 0.0),
			rect.end,
			rect.position + Vector2(0.0, rect.size.y),
		])
	var corner_steps := clampi(int(ceil(float(steps) / 4.0)), 2, 32)
	var centers := [
		rect.position + Vector2(radius, radius),
		Vector2(rect.end.x - radius, rect.position.y + radius),
		rect.end - Vector2(radius, radius),
		Vector2(rect.position.x + radius, rect.end.y - radius),
	]
	var start_angles := [PI, -PI * 0.5, 0.0, PI * 0.5]
	var points := PackedVector2Array()
	for index in centers.size():
		var corner_center: Vector2 = centers[index]
		var start_angle: float = start_angles[index]
		for step in corner_steps + 1:
			var angle := start_angle + PI * 0.5 * float(step) / float(corner_steps)
			points.append(corner_center + Vector2(cos(angle), sin(angle)) * radius)
	return points


## 圆形与椭圆：按矩形半径缩放单位圆顶点，顶点自右侧起点沿屏幕向下排列。
static func _build_ellipse(center: Vector2, radius: Vector2, steps: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for step in steps:
		var angle := TAU * float(step) / float(steps)
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	return points


## 正多边形：首顶点位于矩形上边中点。
static func _build_polygon(center: Vector2, radius: Vector2, sides: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for step in sides:
		var angle := -PI * 0.5 + TAU * float(step) / float(sides)
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	return points


## 星形：外顶点与内顶点交替，首顶点位于矩形上边中点，内顶点按同半径乘以内径比。
static func _build_star(center: Vector2, radius: Vector2, points_count: int, inner_ratio: float) -> PackedVector2Array:
	var total := points_count * 2
	var points := PackedVector2Array()
	for step in total:
		var factor := 1.0 if step % 2 == 0 else inner_ratio
		var angle := -PI * 0.5 + TAU * float(step) / float(total)
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y) * factor)
	return points
