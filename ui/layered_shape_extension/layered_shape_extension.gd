@tool
class_name LayeredShapeExtension
extends Control
## Render arbitrary children of Source/Content once, then extrude their alpha.
## This Control's size is the source canvas. Keep authored content inside it.
## Padding is automatic and stable while progress animates; parent clipping still applies.
const MAX_LAYERS := 4
const MAX_DISTANCE := 24.0
const MAX_SOURCE_SIZE := 2048.0
const EFFECT_SHADER := preload("res://addons/gdbase/ui/layered_shape_extension/layered_shape_extension.gdshader")

@export_range(0.0, 1.0, 0.001) var progress: float = 1.0:
	set(value):
		progress = clampf(value, 0.0, 1.0) if is_finite(value) else 0.0
		_sync_parameters()
@export var layer_colors := PackedColorArray([Color("9d42ff"), Color("00ff65")]):
	set(value):
		layer_colors = value.slice(0, MAX_LAYERS)
		_sync_layout()
@export var direction := Vector2(1.0, 0.5):
	set(value):
		direction = value if value.is_finite() else Vector2.ZERO
		_sync_parameters()
@export_range(0.0, 24.0, 0.1) var layer_distance: float = 7.0:
	set(value):
		layer_distance = clampf(value, 0.0, MAX_DISTANCE) if is_finite(value) else 0.0
		_sync_layout()
@export var preserve_source_color: bool = true:
	set(value):
		preserve_source_color = value
		_sync_parameters()
@export var source_color := Color.WHITE:
	set(value):
		source_color = value
		_sync_parameters()

var _effect_material: ShaderMaterial
var _padding := 2

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not resized.is_connected(_sync_layout):
		resized.connect(_sync_layout)
	_effect_material = ShaderMaterial.new()
	_effect_material.shader = EFFECT_SHADER
	$Surface.material = _effect_material
	$Surface.texture = $Source.get_texture()
	_effect_material.set_shader_parameter("source_texture", $Source.get_texture())
	_sync_layout()

## The editable input slot accepts Labels, TextureRects, Controls and CanvasItems.
func get_content() -> Control:
	return get_node_or_null("Source/Content") as Control

func get_padding() -> int:
	return _padding

func get_source_texture() -> ViewportTexture:
	return $Source.get_texture()

func get_effect_material() -> ShaderMaterial:
	return _effect_material

func _sync_layout() -> void:
	if not is_node_ready():
		return
	_padding = ceili(layer_distance * layer_colors.size()) + 2
	var source_size := Vector2i(clampi(ceili(size.x), 1, int(MAX_SOURCE_SIZE)), clampi(ceili(size.y), 1, int(MAX_SOURCE_SIZE)))
	$Source.size = source_size + Vector2i.ONE * _padding * 2
	$Source/Content.position = Vector2.ONE * _padding
	$Source/Content.size = Vector2(source_size)
	$Surface.position = -Vector2.ONE * _padding
	$Surface.size = Vector2($Source.size)
	_sync_parameters()
	update_configuration_warnings()

func _sync_parameters() -> void:
	if _effect_material == null:
		return
	var colors := PackedColorArray(layer_colors)
	colors.resize(MAX_LAYERS)
	_effect_material.set_shader_parameter("layer_colors", colors)
	_effect_material.set_shader_parameter("layer_count", layer_colors.size())
	_effect_material.set_shader_parameter("layer_step", direction.normalized() * layer_distance * progress)
	_effect_material.set_shader_parameter("preserve_source_color", preserve_source_color)
	_effect_material.set_shader_parameter("front_tint", source_color)

func _get_configuration_warnings() -> PackedStringArray:
	if size.x > MAX_SOURCE_SIZE or size.y > MAX_SOURCE_SIZE:
		return ["Source canvas is bounded to 2048 pixels per axis. Resize the component or scale the whole component for larger presentation."]
	return []
