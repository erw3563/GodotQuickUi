@tool
class_name GDTargetLockStyle
extends Resource
## Scene-local visual configuration read by the controller.
@export var line_color := Color(0.88, 0.94, 0.88)
@export var accent_color := Color(0.78, 0.91, 0.36)
@export_range(0.1, 10.0) var line_width: float = 1.5
@export_range(0.0, 80.0) var corner_length: float = 16.0
@export_range(0.0, 160.0) var acquisition_spread: float = 48.0
@export_range(0.0, 1.0) var box_opacity: float = 0.6
@export var draw_box: bool = true
@export var draw_corners: bool = true
@export var draw_target_quad: bool = true
@export var draw_crosshair: bool = false
@export_range(1, 8) var pulse_count: int = 3
@export_range(1.0, 200.0) var pulse_expansion: float = 42.0
@export var label_font: Font
@export_range(6, 40) var label_size: int = 12
