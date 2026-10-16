@tool
class_name LayoutStateTrack
extends Resource
## Authored endpoints in the transition root's reference_size coordinate system.
## Treat shared tracks as immutable; duplicate(true) before editing at runtime.
@export var target: NodePath
@export var compact_rect := Rect2(0, 0, 100, 100)
@export var expanded_rect := Rect2(0, 0, 100, 100)
@export_range(0.0, 1.0) var compact_alpha := 1.0
@export_range(0.0, 1.0) var expanded_alpha := 1.0
## Local timeline window; stagger is authored, reversible and scrubbable.
@export_range(0.0, 1.0) var start := 0.0
@export_range(0.0, 1.0) var end := 1.0
