class_name StarMapLinks
extends Node2D
## Connection rendering is independent of the layout solver.
func _draw() -> void:
	var view := get_parent().get_parent() as StarMapView
	if view == null or view.layout == null: return
	var palette := view.get_palette()
	for edge in view.layout.links:
		var a: Vector2 = view.layout.positions[edge.x]
		var b: Vector2 = view.layout.positions[edge.y]
		var highlight := edge.x == view.selected or edge.y == view.selected
		var color := palette.link_highlight_color if highlight else palette.link_color
		if not highlight and palette.link_locked_color.a > 0.0 and (view.is_star_locked(edge.x) or view.is_star_locked(edge.y)):
			color = palette.link_locked_color
		var direction := (b - a).normalized()
		draw_line(a + direction * 14, b - direction * 14, color, (palette.link_highlight_width if highlight else palette.link_width) / view.zoom_level, true)
