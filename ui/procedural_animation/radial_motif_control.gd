@tool
class_name RadialMotifControl
extends Control

## 径向纹样的布局与输入宿主。Design Space 子节点承接中心和等比缩放。
## 场景树中的运动组和路径部件保存制作配置；每个实例拥有自己的运动时钟。
signal motion_advanced(effective_delta: float)
signal motion_reset

@export var design_space: Node2D:
	set(value):
		design_space = value
		_update_layout()
		if is_inside_tree():
			update_configuration_warnings()
@export var center_ratio := Vector2(0.5, 0.5):
	set(value):
		center_ratio = value if value.is_finite() else Vector2(0.5, 0.5)
		_update_layout()
## 控件短边对应的设计直径。
@export_range(1.0, 8192.0, 1.0, "or_greater") var reference_diameter := 640.0:
	set(value):
		reference_diameter = maxf(value, 1.0) if is_finite(value) else 640.0
		_update_layout()
@export var fit_to_control := true:
	set(value):
		fit_to_control = value
		_update_layout()
@export_range(0.01, 16.0, 0.01, "or_greater") var motif_scale := 1.0:
	set(value):
		motif_scale = maxf(value, 0.01) if is_finite(value) else 1.0
		_update_layout()

@export_group("Motion")
## 运行时推进运动组；编辑器保持作者设置的静态姿态。
@export var animation_enabled := false:
	set(value):
		animation_enabled = value
		if not value:
			_proximity = 0.0
			motion_reset.emit()
		set_process(value and not Engine.is_editor_hint())
		set_process_input(value and not Engine.is_editor_hint())
@export var mouse_feedback_enabled := true
## 鼠标响应半径使用设计像素，随纹样适配缩放。
@export_range(1.0, 2048.0, 1.0, "or_greater") var proximity_radius := 300.0:
	set(value):
		proximity_radius = maxf(value, 1.0) if is_finite(value) else 300.0
## 圆心处的额外转速比例；1 表示最多增加一倍。
@export_range(0.0, 4.0, 0.05) var proximity_speed_boost := 0.75:
	set(value):
		proximity_speed_boost = clampf(value, 0.0, 4.0) if is_finite(value) else 0.75
@export_range(0.05, 5.0, 0.05, "suffix:s") var response_time := 0.8:
	set(value):
		response_time = clampf(value, 0.05, 5.0) if is_finite(value) else 0.8

var _proximity := 0.0
var _mouse_in_window := true
var _mouse_position := Vector2.ZERO
var _has_mouse_position := false
var _motion_window: Window

func _enter_tree() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(animation_enabled and not Engine.is_editor_hint())
	set_process_input(animation_enabled and not Engine.is_editor_hint())
	if not Engine.is_editor_hint():
		_motion_window = get_window()
		_motion_window.mouse_entered.connect(_on_window_mouse_entered)
		_motion_window.mouse_exited.connect(_on_window_mouse_exited)
	_update_layout.call_deferred()

func _ready() -> void:
	_update_layout()

func _exit_tree() -> void:
	if is_instance_valid(_motion_window):
		_motion_window.mouse_entered.disconnect(_on_window_mouse_entered)
		_motion_window.mouse_exited.disconnect(_on_window_mouse_exited)
	_motion_window = null
	_proximity = 0.0
	_has_mouse_position = false
	_mouse_in_window = true
	motion_reset.emit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_layout()

func _update_layout() -> void:
	if not is_inside_tree() or not is_instance_valid(design_space) or design_space.get_parent() != self:
		return
	design_space.position = size * center_ratio
	design_space.scale = Vector2.ONE * get_design_scale()

func get_design_scale() -> float:
	var fit := minf(size.x, size.y) / reference_diameter if fit_to_control else 1.0
	return maxf(fit, 0.0) * motif_scale

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_position = event.position
		_has_mouse_position = true
		_mouse_in_window = true

func _on_window_mouse_entered() -> void:
	_mouse_in_window = true
	_has_mouse_position = false

func _on_window_mouse_exited() -> void:
	_mouse_in_window = false
	_has_mouse_position = false

func _process(delta: float) -> void:
	if not animation_enabled or Engine.is_editor_hint() or not is_visible_in_tree():
		return
	var target := 0.0
	if mouse_feedback_enabled and _mouse_in_window and is_instance_valid(_motion_window) and _motion_window.has_focus():
		var pointer := get_local_mouse_position()
		if _has_mouse_position:
			pointer = get_global_transform_with_canvas().affine_inverse() * _mouse_position
		target = clampf(1.0 - pointer.distance_to(size * center_ratio) / maxf(proximity_radius * get_design_scale(), 0.001), 0.0, 1.0)
		target = target * target * (3.0 - 2.0 * target)
	_proximity = lerpf(_proximity, target, 1.0 - exp(-delta / response_time))
	motion_advanced.emit(delta * (1.0 + _proximity * proximity_speed_boost))

func _get_configuration_warnings() -> PackedStringArray:
	if not is_instance_valid(design_space) or design_space.get_parent() != self:
		return PackedStringArray(["Assign a direct child Node2D as Design Space for the ornament's center and scale."])
	return PackedStringArray()
