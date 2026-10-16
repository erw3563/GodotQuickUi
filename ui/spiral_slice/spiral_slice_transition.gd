@tool
class_name SpiralSliceTransition
extends Control
## Analytic time-offset cube faces evaluated at the current progress.
## Author native Controls under ContentA/Root and ContentB/Root, or assign textures.
## Source size is artwork resolution; this Control's size controls displayed extent.
## Cube corners extend at most 21% beyond each horizontal edge during rotation.
signal finished
signal cancelled
const EFFECT_SHADER := preload("res://addons/gdbase/ui/spiral_slice/spiral_slice_transition.gdshader")
@export_range(0.0, 1.0, 0.001) var progress := 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0) if is_finite(value) else 0.0
		_sync_parameters()
@export_range(1, 128, 1) var band_count := 20:
	set(value):
		band_count = clampi(value, 1, 128)
		_sync_parameters()
## Fraction of total duration between the first and last band's start.
@export_range(0.0, 0.95, 0.01) var stagger := 0.70:
	set(value):
		stagger = clampf(value, 0.0, 0.95) if is_finite(value) else 0.70
		_sync_parameters()
@export var reverse_stagger := false:
	set(value):
		reverse_stagger = value
		_sync_parameters()
@export var reverse_rotation := false:
	set(value):
		reverse_rotation = value
		_sync_parameters()
@export var swap_inputs := false:
	set(value):
		swap_inputs = value
		_sync_parameters()
@export_range(0.0, 1.0, 0.01) var shading := 0.22:
	set(value):
		shading = clampf(value, 0.0, 1.0) if is_finite(value) else 0.22
		_sync_parameters()
@export_range(0.05, 20.0, 0.01) var duration := 1.60:
	set(value): duration = clampf(value, 0.05, 20.0) if is_finite(value) else 1.60
@export var source_size := Vector2(560, 320):
	set(value):
		source_size = Vector2(clampf(value.x, 1.0, 2048.0), clampf(value.y, 1.0, 2048.0)).ceil() if value.is_finite() else Vector2(560, 320)
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
@export var external_a_premultiplied := false:
	set(value):
		external_a_premultiplied = value
		_sync_parameters()
@export var external_b_premultiplied := false:
	set(value):
		external_b_premultiplied = value
		_sync_parameters()
var _effect_material: ShaderMaterial
var _tween: Tween
var _generation := 0
var _exiting_tree := false
func _enter_tree() -> void:
	_exiting_tree = false
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_effect_material = ShaderMaterial.new()
	_effect_material.shader = EFFECT_SHADER
	$Surface.material = _effect_material
	if not resized.is_connected(_sync_parameters): resized.connect(_sync_parameters)
	if not visibility_changed.is_connected(_on_visibility): visibility_changed.connect(_on_visibility)
	_sync_layout()
func get_content_a() -> Control: return get_node("ContentA/Root")
func get_content_b() -> Control: return get_node("ContentB/Root")
func get_texture_a() -> Texture2D: return texture_a if texture_a != null else $ContentA.get_texture()
func get_texture_b() -> Texture2D: return texture_b if texture_b != null else $ContentB.get_texture()
func get_effect_material() -> ShaderMaterial: return _effect_material
func is_playing() -> bool: return _tween != null and _tween.is_running()
## Restart is deliberate. Return passes configure swap_inputs separately.
func play(from_start: bool = true) -> void:
	var expected_generation := _generation + 1
	cancel()
	# A cancellation listener may issue a newer play, seek, or cancel request.
	if not is_instance_valid(self) or _generation != expected_generation: return
	if _exiting_tree or is_queued_for_deletion() or not is_inside_tree() or Engine.is_editor_hint() or not is_visible_in_tree(): return
	if from_start: progress = 0.0
	_tween = create_tween()
	_tween.tween_property(self, "progress", 1.0, maxf(0.001, duration * (1.0 - progress)))
	_tween.finished.connect(_on_finished.bind(_generation))
func cancel() -> void:
	_generation += 1
	var active := is_playing()
	if _tween != null: _tween.kill()
	_tween = null
	if active: cancelled.emit()
func seek(value: float) -> void:
	var expected_generation := _generation + 1
	cancel()
	if not is_instance_valid(self) or _generation != expected_generation: return
	progress = value
func _on_finished(generation: int) -> void:
	if generation != _generation: return
	_tween = null
	finished.emit()
func _on_visibility() -> void:
	if not is_visible_in_tree(): cancel()
func _exit_tree() -> void:
	_exiting_tree = true
	cancel()
func _sync_layout() -> void:
	if not is_node_ready(): return
	for slot in [$ContentA, $ContentB]:
		slot.size = Vector2i(source_size)
		slot.get_node("Root").size = source_size
	_sync_parameters()
func _sync_parameters() -> void:
	if _effect_material == null: return
	_effect_material.set_shader_parameter("source_a", get_texture_a())
	_effect_material.set_shader_parameter("source_b", get_texture_b())
	_effect_material.set_shader_parameter("premultiplied_a", texture_a == null or external_a_premultiplied)
	_effect_material.set_shader_parameter("premultiplied_b", texture_b == null or external_b_premultiplied)
	_effect_material.set_shader_parameter("display_width", size.x)
	for key in ["progress", "band_count", "stagger", "reverse_stagger", "reverse_rotation", "swap_inputs", "shading"]:
		_effect_material.set_shader_parameter(key, get(key))
