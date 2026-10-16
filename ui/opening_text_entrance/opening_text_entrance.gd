@tool
class_name OpeningTextEntrance
extends Control
## Self-contained GOOD/LUCK poster preset. Phase drives the forward
## entrance, settle, pulse and exit.
const DURATION := 4.6
const EFFECT := preload("res://addons/gdbase/ui/opening_text_entrance/opening_text_entrance.gdshader")
@export_range(0.0, 1.0, 0.001) var phase := 0.35:
	set(value):
		phase = clampf(value, 0.0, 1.0) if is_finite(value) else 0.0
		_sync()
@export var front_color := Color("ededeb"):
	set(value):
		front_color = value
		_sync()
@export var middle_color := Color("9933fa"):
	set(value):
		middle_color = value
		_sync()
@export var back_color := Color("14ff59"):
	set(value):
		back_color = value
		_sync()
@export_range(0.0, 1.0) var rotation_amount := 1.0:
	set(value):
		rotation_amount = clampf(value,0.0,1.0) if is_finite(value) else 1.0
		_sync()
var _material: ShaderMaterial
func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = EFFECT
	$LetterField.material = _material
	resized.connect(_sync)
	_sync()
func _sync() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("canvas_size", Vector2(450,600))
	_material.set_shader_parameter("seconds", phase * DURATION)
	_material.set_shader_parameter("front_color", front_color)
	_material.set_shader_parameter("middle_color", middle_color)
	_material.set_shader_parameter("back_color", back_color)
	_material.set_shader_parameter("motion_scale", rotation_amount)
func get_effect_material() -> ShaderMaterial:
	return _material
