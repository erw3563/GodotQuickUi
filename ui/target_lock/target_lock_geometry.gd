@tool
extends Control
## Independent lock geometry, with visibility controlled separately from tracking.
@export var controller_path: NodePath = NodePath("..")
func _draw() -> void:
	var lock := get_node_or_null(controller_path) as GDTargetLock
	if lock == null or lock.style == null or not lock.tracking or lock.strength <= 0.0:
		return
	var style := lock.style
	var color := style.line_color
	color.a *= lock.strength
	var rect := lock.target_rect.grow((1.0 - lock.strength) * style.acquisition_spread)
	var width := maxf(style.line_width, 0.1)
	if style.draw_box:
		var faint := color
		faint.a *= style.box_opacity
		draw_rect(rect, faint, false, width, true)
	if style.draw_target_quad and lock.target_quad.size() == 4:
		var quad := lock.target_quad.duplicate()
		quad.append(quad[0])
		draw_polyline(quad, color, width, true)
		# An inscribed diamond makes rotation visible independently of the fitted box.
		var diamond := PackedVector2Array()
		for i in 4:
			diamond.append((quad[i] + quad[i + 1]) * 0.5)
		diamond.append(diamond[0])
		draw_polyline(diamond, color, width, true)
	if style.draw_corners:
		var length := minf(style.corner_length, minf(rect.size.x, rect.size.y) * 0.45)
		for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
			var xsign := 1.0 if corner.x < rect.get_center().x else -1.0
			var ysign := 1.0 if corner.y < rect.get_center().y else -1.0
			draw_line(corner, corner + Vector2(length * xsign, 0), color, width, true)
			draw_line(corner, corner + Vector2(0, length * ysign), color, width, true)
	if style.draw_crosshair:
		var center := rect.get_center()
		draw_line(center - Vector2(7, 0), center + Vector2(7, 0), color, width, true)
		draw_line(center - Vector2(0, 7), center + Vector2(0, 7), color, width, true)
