class_name PathModifier
extends Node
## Direct children of PathDeform2D run in scene-tree order. Runtime state is local.
## apply receives private rest snapshots and the current composed offsets.
@export var enabled := true:
	set(value):
		if enabled != value:
			enabled = value
			reset_state()
var active := false
func apply(_paths: Array, _coordinator: Node2D, _delta: float) -> void: pass
func reset_state() -> void: active = false
func _exit_tree() -> void: reset_state()
