class_name StarMapLinks
extends Node2D
## Connection rendering is independent of the layout solver.
func _draw() -> void:
	var view := get_parent().get_parent() as StarMapView
	if view == null or view.layout == null: return
	for edge in view.layout.links:
		var a: Vector2 = view.layout.positions[edge.x]
		var b: Vector2 = view.layout.positions[edge.y]
		var highlight := edge.x == view.selected or edge.y == view.selected
		var color := Color(0.82, 0.76, 0.57, 0.8) if highlight else Color(0.68, 0.70, 0.57, 0.28)
		var direction := (b - a).normalized()
		draw_line(a + direction * 14, b - direction * 14, color, (1.4 if highlight else 1.0) / view.zoom_level, true)
