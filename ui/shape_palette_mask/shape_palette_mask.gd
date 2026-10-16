@tool
class_name ShapePaletteMask
extends Control
## Alpha-preserving local palette replacement for arbitrary texture or viewport
## content. This node owns its material; callers own input textures and viewports.
## Texture and viewport inputs are stretched to the Control's local rectangle.

enum SourceAlpha { AUTO, STRAIGHT, PREMULTIPLIED }

const EFFECT_SHADER = preload("res://addons/gdbase/ui/shape_palette_mask/shape_palette_mask.gdshader")

@export_group("Authored Inputs")
@export var source_texture: Texture2D:
	set(value):
		source_texture = value
		refresh_inputs()
@export_node_path("SubViewport") var source_viewport_path: NodePath:
	set(value):
		source_viewport_path = value
		refresh_inputs()
@export var mask_texture: Texture2D:
	set(value):
		mask_texture = value
		refresh_inputs()
@export_node_path("SubViewport") var mask_viewport_path: NodePath:
	set(value):
		mask_viewport_path = value
		refresh_inputs()

## AUTO recognizes ViewportTexture inputs. Other texture producers may override.
@export var source_alpha: SourceAlpha = SourceAlpha.AUTO:
	set(value):
		source_alpha = clampi(value, SourceAlpha.AUTO, SourceAlpha.PREMULTIPLIED) as SourceAlpha
		_sync_parameters()

@export_group("Palette")
@export var effect_enabled: bool = true:
	set(value):
		effect_enabled = value
		_sync_parameters()
@export var replacement_color: Color = Color("ff092b"):
	set(value):
		if is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a):
			replacement_color = value
			_sync_parameters()
@export_range(0.0, 1.0, 0.001) var strength: float = 1.0:
	set(value):
		if is_finite(value):
			strength = clampf(value, 0.0, 1.0)
			_sync_parameters()

@export_group("Mask Mapping")
## Center in output UV coordinates. Values outside 0..1 intentionally allow exit.
@export var mask_position: Vector2 = Vector2(0.5, 0.5):
	set(value):
		if value.is_finite():
			mask_position = value
			_sync_parameters()
## Extent relative to the output size; rotation is performed in local pixels.
@export var mask_size: Vector2 = Vector2.ONE:
	set(value):
		if value.is_finite():
			mask_size = Vector2(maxf(value.x, 0.0001), maxf(value.y, 0.0001))
			_sync_parameters()
@export_range(-3.14159265, 3.14159265, 0.001, "radians_as_degrees") var mask_rotation: float = 0.0:
	set(value):
		if is_finite(value):
			mask_rotation = fposmod(value + PI, TAU) - PI
			_sync_parameters()

var _owned_material: ShaderMaterial
var _resolved_source: Texture2D
var _resolved_mask: Texture2D

func _enter_tree() -> void:
	_ensure_material()
	refresh_inputs()
	_sync_parameters()
	set_process(true)

func _ready() -> void:
	refresh_inputs()

func _exit_tree() -> void:
	# Release viewport-derived references while preserving caller-owned resources.
	_resolved_source = null
	_resolved_mask = null
	if is_instance_valid(_owned_material):
		_owned_material.set_shader_parameter("source_image", null)
		_owned_material.set_shader_parameter("mask_image", null)
		_owned_material.set_shader_parameter("has_source", false)
		_owned_material.set_shader_parameter("has_mask", false)

func _process(_delta: float) -> void:
	# Supports late-added, removed, replaced or renamed authored viewports in both
	# the editor and runtime, preserving their authored update modes.
	if not source_viewport_path.is_empty() or not mask_viewport_path.is_empty():
		refresh_inputs()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_sync_parameters()

func _ensure_material() -> void:
	if not is_instance_valid(_owned_material):
		_owned_material = ShaderMaterial.new()
		_owned_material.resource_local_to_scene = true
		_owned_material.shader = EFFECT_SHADER
	if material != _owned_material:
		material = _owned_material
	if use_parent_material:
		use_parent_material = false

func _resolve_input(path: NodePath, fallback: Texture2D) -> Texture2D:
	if is_inside_tree() and not path.is_empty():
		var viewport := get_node_or_null(path) as SubViewport
		if is_instance_valid(viewport) and viewport.is_inside_tree():
			return viewport.get_texture()
	return fallback

func refresh_inputs() -> void:
	## Re-resolve inputs after scene changes. Missing viewport falls back to its
	## corresponding texture; absent source is transparent, absent mask is a pass.
	if not is_inside_tree():
		return
	_ensure_material()
	var next_source := _resolve_input(source_viewport_path, source_texture)
	var next_mask := _resolve_input(mask_viewport_path, mask_texture)
	if next_source != _resolved_source or next_mask != _resolved_mask:
		_resolved_source = next_source
		_resolved_mask = next_mask
		_owned_material.set_shader_parameter("source_image", _resolved_source)
		_owned_material.set_shader_parameter("mask_image", _resolved_mask)
		_owned_material.set_shader_parameter("has_source", _resolved_source != null)
		_owned_material.set_shader_parameter("has_mask", _resolved_mask != null)
		_sync_parameters()

func _sync_parameters() -> void:
	if not is_instance_valid(_owned_material):
		return
	var premultiplied := source_alpha == SourceAlpha.PREMULTIPLIED or (source_alpha == SourceAlpha.AUTO and _resolved_source is ViewportTexture)
	_owned_material.set_shader_parameter("source_premultiplied", premultiplied)
	_owned_material.set_shader_parameter("effect_enabled", effect_enabled)
	_owned_material.set_shader_parameter("replacement_color", replacement_color)
	_owned_material.set_shader_parameter("strength", strength)
	_owned_material.set_shader_parameter("output_size", Vector2(maxf(size.x, 0.0001), maxf(size.y, 0.0001)))
	_owned_material.set_shader_parameter("mask_position", mask_position)
	_owned_material.set_shader_parameter("mask_size", mask_size)
	_owned_material.set_shader_parameter("mask_rotation", mask_rotation)
	queue_redraw()

func _draw() -> void:
	if size.x > 0.0 and size.y > 0.0 and _resolved_source != null:
		draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)

func get_resolved_source() -> Texture2D:
	return _resolved_source

func get_resolved_mask() -> Texture2D:
	return _resolved_mask
