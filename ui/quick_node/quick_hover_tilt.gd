@tool
class_name QuickHoverTilt
extends QuickUiAbility
## 悬停倾斜能力：管理目标内部视觉包装层的位移与旋转，并按所有权恢复姿态。
@export var visual: Control
@export var hover_control: Control
@export_range(0.0, 45.0, 0.1) var max_rotation_degrees := 7.0
@export var max_offset := Vector2(6, 4)
@export_range(0.0, 60.0, 0.1) var response := 12.0
var ownership_status := "unbound"
var _owned := false
var _blocked := false
var _owned_visual: Control
var _owned_parent: Node
var _rest_position := Vector2.ZERO
var _rest_rotation := 0.0
var _last_position := Vector2.ZERO
var _last_rotation := 0.0
const TILT_GROUP := &"quick_ui_hover_tilts"

func _enter_tree() -> void:
	add_to_group(TILT_GROUP)

func _exit_tree() -> void:
	_release(true)
	super._exit_tree()

func host_detach() -> void:
	_release(true)
	super.host_detach()

func _on_enabled_changed() -> void:
	if not enabled:
		_release(true)

func _unchanged() -> bool:
	return is_instance_valid(_owned_visual) and _owned_visual.get_parent() == _owned_parent and _owned_visual.position.is_equal_approx(_last_position) and is_equal_approx(_owned_visual.rotation, _last_rotation)

func _release(restore: bool) -> void:
	if _owned:
		if restore and _unchanged():
			_owned_visual.position = _rest_position
			_owned_visual.rotation = _rest_rotation
		elif not _unchanged():
			_blocked = true
			ownership_status = "released: external write or reparent"
	_owned = false
	_owned_visual = null
	_owned_parent = null

func reset_ownership() -> void:
	_release(true)
	_blocked = false
	ownership_status = "unbound"

func reset_ability() -> void:
	reset_ownership()

func _ensure_ownership() -> bool:
	if _owned and (visual != _owned_visual or not _unchanged()):
		_release(true)
	if _blocked:
		return false
	if not is_instance_valid(visual) or not visual.is_inside_tree() or not is_instance_valid(ability_target) or visual == ability_target or not ability_target.is_ancestor_of(visual) or visual.get_parent() is Container:
		_release(true)
		ownership_status = "use a descendant Control wrapper"
		return false
	for peer in get_tree().get_nodes_in_group(TILT_GROUP):
		if peer != self and peer.enabled and is_instance_valid(peer.ability_host) and peer.visual == visual:
			_release(true)
			ownership_status = "duplicate hover writers"
			return false
	if not _owned:
		_owned = true
		_owned_visual = visual
		_owned_parent = visual.get_parent()
		_rest_position = visual.position
		_rest_rotation = visual.rotation
		_last_position = visual.position
		_last_rotation = visual.rotation
	ownership_status = "owned"
	return true

func host_step(delta: float) -> void:
	if not enabled or not _ensure_ownership():
		return
	var area := hover_control if is_instance_valid(hover_control) else ability_target
	var hovered := false
	var normalized := Vector2.ZERO
	if is_instance_valid(area) and area.is_visible_in_tree() and area.get_viewport() == get_viewport():
		var top := get_viewport().gui_get_hovered_control()
		hovered = is_instance_valid(top) and (top == area or area.is_ancestor_of(top))
		if hovered and area.size.x > 0 and area.size.y > 0:
			normalized = area.get_local_mouse_position() / area.size * 2.0 - Vector2.ONE
			normalized = normalized.clamp(-Vector2.ONE, Vector2.ONE)
	_update_pose(normalized, hovered, delta)

func _update_pose(normalized: Vector2, hovered: bool, delta: float) -> void:
	if not _owned:
		return
	var weight := 1.0 if response <= 0.0 else 1.0 - exp(-response * maxf(delta, 0.0))
	var desired_position := _rest_position + normalized * max_offset if hovered else _rest_position
	var desired_rotation := _rest_rotation + deg_to_rad(max_rotation_degrees) * normalized.x if hovered else _rest_rotation
	_last_position = _last_position.lerp(desired_position, weight)
	_last_rotation = lerpf(_last_rotation, desired_rotation, weight)
	if _last_position.distance_to(desired_position) < 0.0001: _last_position = desired_position
	if absf(_last_rotation - desired_rotation) < 0.00001: _last_rotation = desired_rotation
	_owned_visual.position = _last_position
	_owned_visual.rotation = _last_rotation
