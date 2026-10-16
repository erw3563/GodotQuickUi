@tool
class_name QuickUiAbility
extends Node
## 持续能力契约：宿主提供目标与生命周期，能力提交位置提议并处理有序落笔阶段。
@export var enabled := true:
	set(value):
		enabled = value
		_on_enabled_changed()
		if not value and is_instance_valid(ability_host):
			ability_host.refresh_abilities()
@export var placement_order := 100
@export var proposal_priority := 10
var ability_host: Node
var ability_target: Control

func _on_enabled_changed() -> void:
	pass

func host_attach(host: Node, target: Control) -> void:
	ability_host = host
	ability_target = target

func host_detach() -> void:
	ability_host = null
	ability_target = null

func host_step(_delta: float) -> void:
	pass

func propose_position(_delta: float) -> Vector2:
	return Vector2.INF

func apply_place(_target: Control, proposed: Vector2) -> Vector2:
	return proposed

func host_drag_finished(_cancelled: bool) -> void:
	pass

func host_layout_rebased() -> void:
	pass

func reset_ability() -> void:
	pass

func _exit_tree() -> void:
	if is_instance_valid(ability_host):
		host_detach()
