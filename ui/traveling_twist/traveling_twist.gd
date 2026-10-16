@tool
class_name TravelingTwist
extends Control
## Two transparent native content slots, or two equal-extent external textures.
## Content roots use source_size pixels; resizing this Control scales the result.
## Progress always moves forward. Configure swap_inputs and reverse_direction
## for a separate return pass with its own playback direction.
const EFFECT_SHADER := preload("res://addons/gdbase/ui/traveling_twist/traveling_twist.gdshader")
@export_range(0.0, 1.0, 0.001) var progress := 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0) if is_finite(value) else 0.0
		_sync_parameters()
@export var reverse_direction := false:
	set(value):
		reverse_direction = value
		_sync_parameters()
@export var swap_inputs := false:
	set(value):
		swap_inputs = value
		_sync_parameters()
@export_range(0.05, 0.95, 0.01) var fold_span := 0.70:
	set(value):
		fold_span = clampf(value, 0.05, 0.95) if is_finite(value) else 0.70
		_sync_parameters()
@export_range(-0.2, 0.2, 0.001) var bend := 0.025:
	set(value):
		bend = clampf(value, -0.2, 0.2) if is_finite(value) else 0.025
		_sync_parameters()
@export var source_size := Vector2(760, 360):
	set(value):
		source_size = Vector2(clampf(value.x, 1.0, 2048.0), clampf(value.y, 1.0, 2048.0)) if value.is_finite() else Vector2(760, 360)
		_sync_layout()
@export_group("Optional external textures")
@export var texture_a: Texture2D:
	set(value):
		texture_a = value
		_sync_parameters()
@export var texture_b: Texture2D:
	set(value):
		texture_b = value
		_sync_parameters()
## ImageTexture/PNG usually uses straight alpha. ViewportTexture uses premultiplied.
@export var external_a_premultiplied := false:
	set(value):
		external_a_premultiplied = value
		_sync_parameters()
@export var external_b_premultiplied := false:
	set(value):
		external_b_premultiplied = value
		_sync_parameters()
var _effect_material: ShaderMaterial
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_effect_material = ShaderMaterial.new()
	_effect_material.shader = EFFECT_SHADER
	$Surface.material = _effect_material
	_sync_layout()
func get_content_a() -> Control: return get_node("ContentA/Root")
func get_content_b() -> Control: return get_node("ContentB/Root")
func get_effect_material() -> ShaderMaterial: return _effect_material
func get_texture_a() -> Texture2D: return texture_a if texture_a != null else $ContentA.get_texture()
func get_texture_b() -> Texture2D: return texture_b if texture_b != null else $ContentB.get_texture()
func _sync_layout() -> void:
	if not is_node_ready(): return
	for slot in [$ContentA, $ContentB]:
		slot.size = Vector2i(source_size.ceil())
		slot.get_node("Root").size = source_size
	_sync_parameters()
func _sync_parameters() -> void:
	if _effect_material == null: return
	_effect_material.set_shader_parameter("source_a", get_texture_a())
	_effect_material.set_shader_parameter("source_b", get_texture_b())
	_effect_material.set_shader_parameter("premultiplied_a", texture_a == null or external_a_premultiplied)
	_effect_material.set_shader_parameter("premultiplied_b", texture_b == null or external_b_premultiplied)
	for key in ["progress", "reverse_direction", "swap_inputs", "fold_span", "bend"]:
		_effect_material.set_shader_parameter(key, get(key))
