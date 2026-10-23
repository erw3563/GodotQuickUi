@tool
class_name PixelProjectileArc2D
extends Node2D
## 地面世界坐标与归一化进度驱动原生弹体及投影，调用方持有飞行时钟。

@export_group("原生节点")
@export var body: Node2D
@export var shadow: Node2D
@export_group("抛物线")
@export_range(0.0, 256.0, 1.0) var arc_height := 32.0
@export_range(-8.0, 8.0, 0.05) var rotation_turns := 1.0
@export_range(-360.0, 360.0, 1.0, "degrees") var rotation_offset := 0.0
@export_group("地面投影")
@export_range(0.0, 1.0, 0.01) var shadow_apex_scale := 0.6
@export_range(0.0, 1.0, 0.01) var shadow_apex_opacity := 0.35

var active := false
var progress := 0.0
var _ground_world_position := Vector2.ZERO
var _body_transform := Transform2D.IDENTITY
var _shadow_transform := Transform2D.IDENTITY
var _shadow_modulate := Color.WHITE
var _layers_captured := false


func _ready() -> void:
	set_as_top_level(true)
	set_process(false)
	_capture_layers()
	reset()


func play(ground_world_position: Vector2, normalized_progress: float = 0.0) -> void:
	reset()
	if not ground_world_position.is_finite() or not is_finite(normalized_progress):
		return
	active = true
	if is_instance_valid(body):
		body.show()
	if is_instance_valid(shadow):
		shadow.show()
	set_motion(ground_world_position, normalized_progress)


func set_motion(ground_world_position: Vector2, normalized_progress: float) -> void:
	if not ground_world_position.is_finite() or not is_finite(normalized_progress):
		return
	_ground_world_position = ground_world_position
	progress = clampf(normalized_progress, 0.0, 1.0)
	global_transform = Transform2D(0.0, _ground_world_position)
	var arch := 4.0 * progress * (1.0 - progress)
	if is_instance_valid(body):
		body.transform = _body_transform
		body.position += Vector2.UP * get_height()
		body.rotation += deg_to_rad(rotation_offset) + TAU * rotation_turns * progress
	if is_instance_valid(shadow):
		shadow.transform = _shadow_transform
		shadow.scale *= lerpf(1.0, shadow_apex_scale, arch)
		shadow.modulate = _shadow_modulate
		shadow.modulate.a *= lerpf(1.0, shadow_apex_opacity, arch)


func get_height() -> float:
	return 4.0 * maxf(0.0, arc_height) * progress * (1.0 - progress)


func get_body_world_position() -> Vector2:
	if is_instance_valid(body):
		return body.global_position
	return _ground_world_position + Vector2.UP * get_height()


func stop() -> void:
	reset()


func reset() -> void:
	active = false
	progress = 0.0
	set_process(false)
	if is_instance_valid(body):
		body.transform = _body_transform
		body.hide()
	if is_instance_valid(shadow):
		shadow.transform = _shadow_transform
		shadow.modulate = _shadow_modulate
		shadow.hide()


func _capture_layers() -> void:
	if _layers_captured:
		return
	_layers_captured = true
	if is_instance_valid(body):
		_body_transform = body.transform
	if is_instance_valid(shadow):
		_shadow_transform = shadow.transform
		_shadow_modulate = shadow.modulate


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and _layers_captured and is_inside_tree() and not is_visible_in_tree():
		reset()
	elif what == NOTIFICATION_EXIT_TREE:
		reset()
