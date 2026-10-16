@tool
class_name QuickFollow
extends QuickUiAbility
## 持续跟随能力：在目标画布坐标中计算平滑提议，拖动结束后重建跟随偏移。
enum FollowSource { MOUSE, CONTROL }
@export var follow_source: FollowSource = FollowSource.MOUSE
@export var follow_target: Control
@export var offset := Vector2.ZERO:
	set(value):
		if is_node_ready(): _runtime_offset += value - offset
		offset = value
@export_range(0.0, 60.0, 0.1) var smoothing := 8.0
@export var rebase_after_drag := true
var _continuous := Vector2.INF
var _runtime_offset := Vector2.ZERO

func host_attach(host: Node, target: Control) -> void:
	super.host_attach(host, target)
	reset_ability()

func host_layout_rebased() -> void:
	host_drag_finished(true)

func reset_ability() -> void:
	_runtime_offset = offset
	if is_instance_valid(ability_target):
		_continuous = QuickUI.layout_to_global(ability_target, ability_target.position)

func _source_position() -> Vector2:
	if not is_instance_valid(ability_target) or not ability_target.is_inside_tree():
		return Vector2.INF
	if follow_source == FollowSource.MOUSE:
		return ability_target.get_global_mouse_position()
	if not is_instance_valid(follow_target) or not follow_target.is_inside_tree() or follow_target.get_viewport() != ability_target.get_viewport():
		return Vector2.INF
	var screen := follow_target.get_global_transform_with_canvas() * (follow_target.size * 0.5)
	return ability_target.get_canvas_transform().affine_inverse() * screen

func propose_position(delta: float) -> Vector2:
	if not enabled or not is_instance_valid(ability_host) or ability_host.is_dragging():
		return Vector2.INF
	var source := _source_position()
	if not source.is_finite():
		return Vector2.INF
	if not _continuous.is_finite():
		_continuous = QuickUI.layout_to_global(ability_target, ability_target.position)
	var destination := source + _runtime_offset
	var weight := 1.0 if smoothing <= 0.0 else 1.0 - exp(-smoothing * maxf(delta, 0.0))
	_continuous = _continuous.lerp(destination, weight)
	return _continuous

func host_drag_finished(_cancelled: bool) -> void:
	if not is_instance_valid(ability_target):
		return
	_continuous = QuickUI.layout_to_global(ability_target, ability_target.position)
	var source := _source_position()
	if rebase_after_drag and source.is_finite():
		_runtime_offset = _continuous - source

func get_continuous_position() -> Vector2:
	return _continuous
