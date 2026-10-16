@tool
class_name ImageSliceWindow
extends Control
## Draws one image with normalized source offsets. Child drawing remains independent.
enum Axis { HORIZONTAL, VERTICAL }
@export var texture: Texture2D:
 set(value):
  texture = value
  queue_redraw()
@export var continuous := true:
 set(value):
  continuous = value
  queue_redraw()
@export var source_offset := Vector2.ZERO:
 set(value):
  source_offset = value
  queue_redraw()
@export var axis: Axis = Axis.VERTICAL:
 set(value):
  axis = value
  queue_redraw()
@export var from_end := false:
 set(value):
  from_end = value
  queue_redraw()
@export_range(0, 1) var start := 0.0:
 set(value):
  start = clampf(value, 0, 1)
  queue_redraw()
@export_range(0, 1) var end := 1.0:
 set(value):
  end = clampf(value, 0, 1)
  queue_redraw()
@export_range(0, 1) var progress := 1.0:
 set(value):
  progress = clampf(value, 0, 1)
  queue_redraw()
@export var accent := Color(1, 0.27, 0.055):
 set(value):
  accent = value
  queue_redraw()
@export_range(0,1) var accent_y := 0.61:
 set(value):
  accent_y = clampf(value,0,1)
  queue_redraw()
@export var accent_height := 4.0:
 set(value):
  accent_height = maxf(value,0)
  queue_redraw()
var _source_parent: Control
func _enter_tree() -> void:
 mouse_filter = Control.MOUSE_FILTER_IGNORE
 if not item_rect_changed.is_connected(queue_redraw): item_rect_changed.connect(queue_redraw)
 _source_parent = get_parent() as Control
 if is_instance_valid(_source_parent) and not _source_parent.resized.is_connected(queue_redraw):
  _source_parent.resized.connect(queue_redraw)
 queue_redraw()
func _exit_tree() -> void:
 if is_instance_valid(_source_parent) and _source_parent.resized.is_connected(queue_redraw):
  _source_parent.resized.disconnect(queue_redraw)
 _source_parent = null
func local_progress() -> float:
 if end <= start: return 1.0 if progress >= end else 0.0
 return clampf((progress-start)/(end-start),0,1)
func reveal_rect() -> Rect2:
 var r := Rect2(Vector2.ZERO, size.max(Vector2.ZERO))
 var p := local_progress()
 if axis == Axis.HORIZONTAL:
  r.size.x *= p
  if from_end: r.position.x = size.x-r.size.x
 else:
  r.size.y *= p
  if from_end: r.position.y = size.y-r.size.y
 return r
## UV bounds before clipping to [0,1]. Cover mapping preserves image aspect.
func source_uv() -> Rect2:
 if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0: return Rect2()
 var canvas: Vector2 = get_parent().size if continuous and get_parent() is Control else size
 if canvas.x <= 0 or canvas.y <= 0: return Rect2()
 var ts := texture.get_size()
 var scale_factor := maxf(canvas.x/ts.x, canvas.y/ts.y)
 var origin := position if continuous else Vector2.ZERO
 var crop_origin := (ts-canvas/scale_factor)*0.5
 return Rect2((crop_origin+origin/scale_factor)/ts+source_offset, size/scale_factor/ts)
## Returns destination and source pixels after both reveal and out-of-image clipping.
func draw_mapping() -> Array[Rect2]:
 var empty: Array[Rect2] = []
 if texture == null or size.x <= 0 or size.y <= 0: return empty
 var uv := source_uv()
 var reveal := reveal_rect()
 if uv.size.x <= 0 or uv.size.y <= 0 or not reveal.has_area(): return empty
 var source := Rect2((uv.position+reveal.position/size*uv.size)*texture.get_size(), reveal.size/size*uv.size*texture.get_size())
 var clipped := source.intersection(Rect2(Vector2.ZERO,texture.get_size()))
 if not clipped.has_area(): return empty
 var ratio := reveal.size/source.size
 var destination := Rect2(reveal.position+(clipped.position-source.position)*ratio,clipped.size*ratio)
 return [destination,clipped]
func _draw() -> void:
 var mapping := draw_mapping()
 if mapping.is_empty(): return
 draw_texture_rect_region(texture,mapping[0],mapping[1])
 var line := Rect2(0,size.y*accent_y,size.x,maxf(0,accent_height)).intersection(reveal_rect())
 if line.has_area(): draw_rect(line,accent)
