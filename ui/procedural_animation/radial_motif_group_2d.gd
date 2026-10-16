@tool
class_name RadialMotifGroup2D
extends Node2D

## 同组部件继承同一原生旋转变换，花瓣、描边和叶脉保持对齐。
## 运行角度属于当前实例；运动关闭或退出场景时恢复作者设置的角度。
@export var motion_source: RadialMotifControl:
	set(value):
		_disconnect_source()
		motion_source = value
		_bind_source()
		_reset_motion()
@export_range(-30.0, 30.0, 0.1, "or_less", "or_greater", "suffix:°/s") var rotation_speed_degrees := 0.0:
	set(value):
		rotation_speed_degrees = value if is_finite(value) else 0.0

var _authored_rotation := 0.0
var _pose_captured := false
var _motion_angle := 0.0

func _enter_tree() -> void:
	_authored_rotation = rotation
	_pose_captured = true
	_motion_angle = 0.0
	_bind_source()

func _ready() -> void:
	_bind_source()

func _exit_tree() -> void:
	_disconnect_source()
	_reset_motion()
	_pose_captured = false

func _bind_source() -> void:
	if not is_inside_tree() or not is_instance_valid(motion_source):
		return
	if not motion_source.motion_advanced.is_connected(_advance_motion):
		motion_source.motion_advanced.connect(_advance_motion)
	if not motion_source.motion_reset.is_connected(_reset_motion):
		motion_source.motion_reset.connect(_reset_motion)

func _disconnect_source() -> void:
	if not is_instance_valid(motion_source):
		return
	if motion_source.motion_advanced.is_connected(_advance_motion):
		motion_source.motion_advanced.disconnect(_advance_motion)
	if motion_source.motion_reset.is_connected(_reset_motion):
		motion_source.motion_reset.disconnect(_reset_motion)

func _advance_motion(effective_delta: float) -> void:
	if Engine.is_editor_hint() or not is_visible_in_tree() or is_zero_approx(rotation_speed_degrees):
		return
	_motion_angle = wrapf(_motion_angle + deg_to_rad(rotation_speed_degrees) * effective_delta, -PI, PI)
	rotation = _authored_rotation + _motion_angle

func _reset_motion() -> void:
	_motion_angle = 0.0
	if _pose_captured and not Engine.is_editor_hint():
		rotation = _authored_rotation
