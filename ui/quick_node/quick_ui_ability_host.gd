@tool
class_name QuickUiAbilityHost
extends Node
## 持续能力宿主：管理目标控件的能力挂载、位置提议仲裁与有序落笔阶段。
var _explicit_target := false
@export var ui: Control:
	set(value):
		ui = value
		_explicit_target = is_instance_valid(value)
@export var enabled := true:
	set(value):
		enabled = value
		if is_node_ready() and not Engine.is_editor_hint():
			refresh_abilities()
@export_group("Add persistent ability")
@export_tool_button("Drag") var add_drag = _add_drag
@export_tool_button("Bounds") var add_bounds = _add_bounds
@export_tool_button("Snap") var add_snap = _add_snap
@export_tool_button("Follow") var add_follow = _add_follow
@export_tool_button("Hover tilt") var add_hover_tilt = _add_hover_tilt

signal position_committed(position: Vector2)
signal status_changed(reason: String)
var status := "inactive"
var _target: Control
var _target_parent: Node
var _active: Array[QuickUiAbility] = []
var _refreshing := false
var _placing := false
var _last_layout := Vector2.INF
const HOST_GROUP := &"quick_ui_ability_hosts"

func _enter_tree() -> void:
	add_to_group(HOST_GROUP)

func _ready() -> void:
	if not Engine.is_editor_hint():
		refresh_abilities()

func _exit_tree() -> void:
	_detach_all()

func get_target() -> Control:
	if is_instance_valid(ui):
		return ui
	if _explicit_target:
		return null
	if get_parent() is Control:
		return get_parent() as Control
	return null

func _invalid_reason() -> String:
	if not enabled or not is_inside_tree() or not can_process():
		return "host disabled"
	var target := get_target()
	if not is_instance_valid(target) or not target.is_inside_tree():
		return "missing target"
	if not target.is_visible_in_tree():
		return "target hidden"
	if target.get_parent() is Container:
		return "Container owns layout; add a Control shell"
	if target.is_set_as_top_level():
		return "top-level target unsupported; use a Control shell"
	var parent := target.get_parent()
	if parent is CanvasItem and absf(parent.get_global_transform().determinant()) < 0.000001:
		return "singular parent transform"
	for peer in get_tree().get_nodes_in_group(HOST_GROUP):
		if peer != self and peer.enabled and peer.can_process() and peer.get_target() == target:
			return "duplicate target hosts"
	return ""

func _set_status(value: String) -> void:
	if value != status:
		status = value
		status_changed.emit(value)

func refresh_abilities() -> void:
	if _refreshing or Engine.is_editor_hint():
		return
	_refreshing = true
	var reason := _invalid_reason()
	var target := get_target()
	if not reason.is_empty():
		_detach_all()
		_set_status(reason)
		_refreshing = false
		return
	if target != _target or target.get_parent() != _target_parent:
		_detach_all()
		reason = _invalid_reason()
		target = get_target()
		if not reason.is_empty():
			_set_status(reason)
			_refreshing = false
			return
		_target = target
		_target_parent = target.get_parent()
		_last_layout = target.position
	var wanted: Array[QuickUiAbility] = []
	for child in get_children():
		if child is QuickUiAbility and child.enabled and child.can_process() and not child.is_queued_for_deletion():
			wanted.append(child)
	for ability in _active.duplicate():
		if not is_instance_valid(ability) or not wanted.has(ability):
			if is_instance_valid(ability) and ability.ability_host == self:
				ability.host_detach()
	for ability in wanted:
		if not _active.has(ability) or ability.ability_host != self:
			_active.append(ability)
			ability.host_attach(self, target)
	_active = wanted
	var drag_count := 0
	for ability in _active:
		if ability is QuickDrag: drag_count += 1
	if drag_count > 1:
		cancel_input()
	_set_status("ready")
	_refreshing = false

func _detach_all() -> void:
	var previous := _active.duplicate()
	_active.clear()
	for ability in previous:
		if is_instance_valid(ability) and ability.ability_host == self:
			ability.host_detach()
	_target = null
	_target_parent = null
	_last_layout = Vector2.INF

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		_detach_all()
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel_input()

func cancel_input() -> void:
	for ability in _active.duplicate():
		if is_instance_valid(ability) and ability.has_method("cancel_drag"):
			ability.cancel_drag()

func is_dragging() -> bool:
	for ability in _active:
		if is_instance_valid(ability) and ability is QuickDrag and ability.is_draging:
			return true
	return false

func can_begin_drag(drag: Node) -> bool:
	refresh_abilities()
	if not _active.has(drag):
		return false
	var count := 0
	for ability in _active:
		if ability is QuickDrag:
			count += 1
	if count > 1:
		_set_status("duplicate drag abilities")
	return count == 1

func drag_finished(cancelled: bool) -> void:
	for ability in _active.duplicate():
		if is_instance_valid(ability):
			ability.host_drag_finished(cancelled)

func reset_abilities() -> void:
	cancel_input()
	refresh_abilities()
	for ability in _active:
		ability.reset_ability()
	if is_instance_valid(_target):
		_last_layout = _target.position

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	refresh_abilities()
	if not is_instance_valid(_target):
		return
	if _last_layout.is_finite() and not _target.position.is_equal_approx(_last_layout):
		cancel_input()
		for ability in _active.duplicate():
			if is_instance_valid(ability) and ability.ability_host == self:
				ability.host_layout_rebased()
	for ability in _active.duplicate():
		if is_instance_valid(ability) and ability.ability_host == self:
			ability.host_step(delta)
	if not is_instance_valid(_target) or not _invalid_reason().is_empty():
		return
	var proposed := QuickUI.layout_to_global(_target, _target.position)
	var follow_count := 0
	for ability in _active:
		if ability is QuickFollow: follow_count += 1
	if follow_count > 1 and not is_dragging():
		_set_status("duplicate position proposals")
		return
	var priority := -2147483648
	var writers := 0
	for ability in _active.duplicate():
		if not is_instance_valid(ability) or ability.ability_host != self:
			continue
		var candidate: Vector2 = ability.propose_position(delta)
		if not is_instance_valid(_target) or not _invalid_reason().is_empty():
			return
		if not candidate.is_finite():
			continue
		if ability.proposal_priority > priority:
			priority = ability.proposal_priority
			proposed = candidate
			writers = 1
		elif ability.proposal_priority == priority:
			writers += 1
	if writers > 1:
		_set_status("duplicate position proposals")
		return
	place(_target, proposed)

func place(control: Control, proposed: Vector2, intent: QuickUI.PlaceIntent = QuickUI.PlaceIntent.PLACEMENT) -> Vector2:
	if _placing or Engine.is_editor_hint() or not proposed.is_finite():
		return proposed
	refresh_abilities()
	if not is_instance_valid(_target) or control != _target:
		return proposed
	if intent == QuickUI.PlaceIntent.INTERACTIVE and not is_dragging():
		return QuickUI.layout_to_global(control, control.position)
	_placing = true
	var result := proposed
	var stages := _active.duplicate()
	stages.sort_custom(func(a: QuickUiAbility, b: QuickUiAbility):
		if a.placement_order == b.placement_order:
			return a.get_index() < b.get_index()
		return a.placement_order < b.placement_order)
	for ability in stages:
		if is_instance_valid(ability) and ability.ability_host == self:
			result = ability.apply_place(control, result)
			if not is_instance_valid(control) or control != _target or control != get_target() or not _invalid_reason().is_empty():
				_placing = false
				return proposed
			if not result.is_finite():
				_placing = false
				_set_status("invalid placement stage")
				return QuickUI.layout_to_global(control, control.position)
	if is_instance_valid(control) and control == get_target() and control.get_parent() == _target_parent and _invalid_reason().is_empty() and (intent != QuickUI.PlaceIntent.INTERACTIVE or is_dragging()):
		control.position = QuickUI.global_to_layout(control, result)
		_last_layout = control.position
		position_committed.emit(result)
	_placing = false
	return result

func _add(script: Script, label: String) -> Node:
	var node: Node = script.new()
	node.name = label
	add_child(node, true)
	node.owner = owner if owner != null else self
	return node
func _add_drag() -> void: _add(load("res://addons/gdbase/ui/quick_node/quick_drag.gd"), "Drag")
func _add_bounds() -> void: _add(load("res://addons/gdbase/ui/quick_node/quick_constraints.gd"), "Bounds")
func _add_snap() -> void: _add(load("res://addons/gdbase/ui/quick_node/quick_snap.gd"), "Snap")
func _add_follow() -> void: _add(load("res://addons/gdbase/ui/quick_node/quick_follow.gd"), "Follow")
func _add_hover_tilt() -> void: _add(load("res://addons/gdbase/ui/quick_node/quick_hover_tilt.gd"), "HoverTilt")
