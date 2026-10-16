@tool
class_name LevelNodeVisual
extends Node2D
## Custom visual scene contract: draw in a normalized [-0.5, 0.5] square.
## The parent clips/scales the visual and supplies presentation snapshots.
var presentation: Dictionary = {}
func set_presentation(state: Dictionary) -> void:
	presentation = state.duplicate(true)
	queue_redraw()
