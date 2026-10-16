@tool
class_name LayeredTitle
extends Control
## Authored scene preset with editable AnimationPlayer choreography.
signal finished(shown: bool)
@export var title := "NORTH / SIGNAL":
 set(v):
  title = v
  _sync()
@export var subtitle := "北境观测站 / FIELD RESEARCH":
 set(v):
  subtitle = v
  _sync()
@export var kicker := "TRANSMISSION  /  004":
 set(v):
  kicker = v
  _sync()
@export var detail := "SECTOR 08    •    06:24 UTC":
 set(v):
  detail = v
  _sync()
@export var icon_text := "✦":
 set(v):
  icon_text = v
  _sync()
@export var show_icon := true:
 set(v):
  show_icon = v
  _sync()
@export var plate_color := Color("f0f0e8"):
 set(v):
  plate_color = v
  _sync()
@export var ink_color := Color("101923"):
 set(v):
  ink_color = v
  _sync()
@export var accent_color := Color("caff5b"):
 set(v):
  accent_color = v
  _sync()
@export_range(18, 80, 1) var title_font_size := 42:
 set(v):
  title_font_size = v
  _sync()
## Optional project font, including a full CJK font for portable bilingual output.
@export var font: Font:
 set(v):
  font = v
  _sync()
@export var autoplay := false
var _leaving := false
func _ready() -> void:
 _sync()
 if not Engine.is_editor_hint():
  $Timeline.animation_finished.connect(_completed)
  reset()
  if autoplay: play()
func _sync() -> void:
 if not is_node_ready(): return
 $Title/Content.text = title
 $Subtitle/Content.text = subtitle
 $Kicker/Content.text = kicker
 $Detail/Content.text = detail
 $Icon/Content/Text.text = icon_text
 $Icon.visible = show_icon
 $Plate.fill_color = plate_color
 $Accent.fill_color = accent_color
 $Plate.accent_color = accent_color
 for label in [$Title/Content, $Subtitle/Content, $Kicker/Content, $Detail/Content]:
  label.add_theme_color_override("font_color", ink_color)
  if font: label.add_theme_font_override("font", font)
  else: label.remove_theme_font_override("font")
 $Title/Content.add_theme_font_size_override("font_size", title_font_size)
 $Icon/Content.color = ink_color
 $Icon/Content/Text.add_theme_color_override("font_color", plate_color)
## Restarts the authored timeline deterministically from its beginning.
func play() -> void:
 reset()
 _leaving = false
 $Timeline.play("reveal")
func reset() -> void:
 $Timeline.stop()
 $Timeline.play("reveal")
 $Timeline.seek(0.0, true)
 $Timeline.pause()
func show_instant() -> void:
 $Timeline.stop()
 $Timeline.play("reveal")
 $Timeline.seek(1.2, true)
 $Timeline.pause()
## Reverse from current position, including a partially entered state.
func conceal() -> void:
 var t: float = $Timeline.current_animation_position
 _leaving = true
 $Timeline.play_backwards("reveal")
 $Timeline.seek(t, true)
 if t <= 0.0:
  reset()
  finished.emit(false)
func _completed(_name: StringName) -> void:
 finished.emit(not _leaving)
