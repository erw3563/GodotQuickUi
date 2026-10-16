@tool
extends Control
## A pixel-stepped inward vortex with a solid central cover for a square drop target.
## The centered covered square measures 53 percent of the control width and height.

@export_range(0.0, 1.0) var openness: float = 1.0:
 set(value):
  openness = clampf(value, 0.0, 1.0)
  _update_material()
@export_range(0.0, 4.0) var swirl_speed: float = 0.85:
 set(value):
  swirl_speed = value
  _update_material()
@export_range(24.0, 128.0, 1.0) var pixel_count: float = 64.0:
 set(value):
  pixel_count = value
  _update_material()
@export var core_color: Color = Color("09070e"):
 set(value):
  core_color = value
  _update_material()
@export var shadow_color: Color = Color("292038"):
 set(value):
  shadow_color = value
  _update_material()
@export var spiral_color: Color = Color("644d82"):
 set(value):
  spiral_color = value
  _update_material()
@export var rim_color: Color = Color("a88cb5"):
 set(value):
  rim_color = value
  _update_material()
@export_range(0.0, 2.0) var open_duration: float = 0.48
@export_range(0.0, 2.0) var close_duration: float = 0.32

var _transition: Tween
var _ink: ShaderMaterial

func _ready() -> void:
 _ink = $Surface.material.duplicate() as ShaderMaterial
 $Surface.material = _ink
 _update_material()

func open() -> void:
 _animate_to(1.0, open_duration)

func close() -> void:
 _animate_to(0.0, close_duration)

func _animate_to(target: float, duration: float) -> void:
 if is_instance_valid(_transition):
  _transition.kill()
 if duration <= 0.0:
  openness = target
  return
 _transition = create_tween()
 _transition.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
 _transition.tween_property(self, "openness", target, duration * absf(target - openness))

func _exit_tree() -> void:
 if is_instance_valid(_transition):
  _transition.kill()

func _update_material() -> void:
 if not is_instance_valid(_ink):
  return
 _ink.set_shader_parameter("openness", openness)
 _ink.set_shader_parameter("swirl_speed", swirl_speed)
 _ink.set_shader_parameter("pixel_count", pixel_count)
 _ink.set_shader_parameter("core_color", core_color)
 _ink.set_shader_parameter("shadow_color", shadow_color)
 _ink.set_shader_parameter("spiral_color", spiral_color)
 _ink.set_shader_parameter("rim_color", rim_color)
