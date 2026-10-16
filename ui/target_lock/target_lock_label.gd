@tool
extends Control
## Independent target-anchored leader and text layer.
@export var controller_path: NodePath = NodePath("..")
func _draw() -> void:
	var lock := get_node_or_null(controller_path) as GDTargetLock
	if lock == null or lock.style == null or not lock.tracking or lock.strength <= 0.05:
		return
	var style := lock.style
	var color := style.line_color
	color.a *= lock.strength
	var anchor := Vector2(lock.target_rect.end.x, lock.target_rect.position.y)
	var elbow := anchor + lock.label_offset
	var tail := elbow + Vector2(58.0, 0.0)
	var end := anchor.lerp(elbow, lock.strength)
	draw_line(anchor, end, color, maxf(style.line_width, 0.1), true)
	if lock.strength > 0.95:
		draw_line(elbow, tail, color, maxf(style.line_width, 0.1), true)
		var font := style.label_font if style.label_font != null else ThemeDB.fallback_font
		draw_string(font, elbow + Vector2(0.0, -8.0), lock.label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, style.label_size, color)
