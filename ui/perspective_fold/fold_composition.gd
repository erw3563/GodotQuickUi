@tool
class_name FoldComposition
extends Control
const PanelType = preload("res://addons/gdbase/ui/perspective_fold/image_fold_panel.gd")
## Children are authored panels that consume shared progress.
@export_range(0,1) var progress := 1.0:
 set(v): progress=clampf(v,0,1); _apply()
@export var stagger := true:
 set(v): stagger=v; _apply()
func _ready() -> void: _apply()
func _apply() -> void:
 var i=0
 for panel in get_children():
  if panel is PanelType:
   var start=float(i)*.105 if stagger else 0.0
   var duration=.58 if stagger else 1.0
   var t=clampf((progress-start)/duration,0,1)
   panel.fold_progress=t*t*(3.0-2.0*t)
   i+=1
