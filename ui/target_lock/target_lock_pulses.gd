@tool
extends Control
## Acquisition rings driven by deterministic seek/replay progress.
@export var controller_path: NodePath = NodePath("..")
func _draw() -> void:
	var lock := get_node_or_null(controller_path) as GDTargetLock
	if lock == null or lock.style == null or not lock.tracking or not lock.requested or lock.pulse_phase >= 1.0:
		return
	var style := lock.style
	var radius := maxf(lock.target_rect.size.x, lock.target_rect.size.y) * 0.55
	var count := clampi(style.pulse_count, 1, 8)
	for i in count:
		var phase := lock.pulse_phase * 1.55 - float(i) * 0.18
		if phase <= 0.0 or phase >= 1.0:
			continue
		var color := style.accent_color
		color.a *= sin(phase * PI) * (1.0 - lock.pulse_phase) * 0.7
		draw_arc(lock.target_rect.get_center(), radius + phase * style.pulse_expansion, 0.0, TAU, 80, color, maxf(style.line_width, 0.1), true)
