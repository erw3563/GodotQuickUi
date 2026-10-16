@tool
class_name ThreeWeightPath
extends Control
## Scene composition: PathReveal2D nodes render authored resources.
## Geometry and every stroke width live in each PathDefinition preset.
const DURATION := 4.6
@export_range(0.0, 1.0, 0.001) var phase := 0.55:
	set(value):
		phase = clampf(value, 0.0, 1.0) if is_finite(value) else 0.0
		_sync()
func _ready() -> void:
	_sync()
func _sync() -> void:
	if not is_node_ready(): return
	# Outer paths follow the central gesture, then erase in the same order.
	for index in 3:
		var path: PathReveal2D = get_node(["Paths/Thick", "Paths/Normal", "Paths/Thin"][index])
		var delay := float(index) * 0.045
		var enter := clampf((phase - delay) / 0.40, 0.0, 1.0)
		var leave := clampf((phase - 0.72 - delay) / (0.28 - delay), 0.0, 1.0)
		path.reveal_progress = enter * (1.0 - leave)
