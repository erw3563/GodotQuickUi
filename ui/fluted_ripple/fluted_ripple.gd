@tool
class_name FlutedRipple
extends TextureRect
## Finite traveling refractive band over any Texture2D (including ViewportTexture).
## Outside the band and at either endpoint the original texture is unchanged.
signal progress_changed(value: float)
signal playback_finished(at_end: bool)
const SHADER = preload("res://addons/gdbase/ui/fluted_ripple/fluted_ripple.gdshader")
@export_enum("Auto (ViewportTexture premultiplied)", "Straight", "Premultiplied") var source_alpha_mode: int = 0:
	set(value):
		source_alpha_mode = clampi(value, 0, 2)
		_sync_shader()
@export_group("Band")
@export_range(0.0, 1.0, 0.001) var progress: float = 0.0:
	set(value):
		if is_finite(value):
			var next := clampf(value, 0.0, 1.0)
			if next != progress:
				progress = next
				_sync_shader()
				progress_changed.emit(progress)
@export_range(-180.0, 180.0, 0.1) var band_direction_degrees: float = 180.0:
	set(value):
		if is_finite(value):
			band_direction_degrees = wrapf(value, -180.0, 180.0)
			_sync_shader()
@export_range(1.0, 8192.0, 1.0) var band_width: float = 290.0:
	set(value):
		if is_finite(value):
			band_width = clampf(value, 1.0, 8192.0)
			_sync_shader()
@export_range(0.0, 2048.0, 1.0) var edge_softness: float = 24.0:
	set(value):
		if is_finite(value):
			edge_softness = clampf(value, 0.0, 2048.0)
			_sync_shader()
@export_group("Flutes")
@export_range(0.0, 500.0, 0.1) var rib_frequency: float = 112.0:
	set(value):
		if is_finite(value):
			rib_frequency = clampf(value, 0.0, 500.0)
			_sync_shader()
@export_range(-180.0, 180.0, 0.1) var rib_angle_degrees: float = 0.0:
	set(value):
		if is_finite(value):
			rib_angle_degrees = wrapf(value, -180.0, 180.0)
			_sync_shader()
@export_range(0.0, 512.0, 0.1) var refraction_amplitude: float = 18.0:
	set(value):
		if is_finite(value):
			refraction_amplitude = clampf(value, 0.0, 512.0)
			_sync_shader()
@export_group("Transport")
@export_range(0.05, 120.0, 0.05) var duration_seconds: float = 3.3:
	set(value):
		if is_finite(value): duration_seconds = clampf(value, 0.05, 120.0)
@export var autoplay: bool = false
var playing: bool = false
var direction: float = 1.0
var _revision: int = 0
var _did_ready: bool = false
var _owned_material: ShaderMaterial
func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	focus_mode = FOCUS_NONE
	expand_mode = EXPAND_IGNORE_SIZE
	stretch_mode = STRETCH_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_owned_material = ShaderMaterial.new()
	_owned_material.shader = SHADER
	material = _owned_material
func _enter_tree() -> void:
	set_process(false)
	if not resized.is_connected(_sync_shader): resized.connect(_sync_shader)
	if not visibility_changed.is_connected(_visibility_changed): visibility_changed.connect(_visibility_changed)
	_sync_shader()
func _ready() -> void:
	if not _did_ready:
		_did_ready = true
		if autoplay and not Engine.is_editor_hint(): replay()
func _exit_tree() -> void: cancel()
func _visibility_changed() -> void:
	if not is_visible_in_tree(): cancel()
func _process(delta: float) -> void: advance(delta)
func advance(delta: float) -> void:
	if not playing or not is_inside_tree() or not is_visible_in_tree() or is_queued_for_deletion(): return
	if not is_finite(delta) or delta <= 0.0: return
	var revision := _revision
	var next := clampf(progress + minf(delta, duration_seconds) * direction / duration_seconds, 0.0, 1.0)
	progress = next
	if revision != _revision or not playing or progress != next: return
	if not is_inside_tree() or not is_visible_in_tree() or is_queued_for_deletion(): return
	if next == 0.0 or next == 1.0:
		cancel()
		playback_finished.emit(next == 1.0)
func replay() -> void:
	_revision += 1
	var revision := _revision
	_stop()
	direction = 1.0
	progress = 0.0
	if revision == _revision: _play()
func reverse() -> void:
	_revision += 1
	if progress <= 0.0: direction = 1.0
	elif progress >= 1.0: direction = -1.0
	else: direction = -direction
	_play()
func resume() -> void:
	_revision += 1
	if progress <= 0.0: direction = 1.0
	elif progress >= 1.0: direction = -1.0
	_play()
func _play() -> void:
	playing = is_inside_tree() and is_visible_in_tree() and not is_queued_for_deletion() and not Engine.is_editor_hint()
	set_process(playing)
func _stop() -> void:
	playing = false
	set_process(false)
func cancel() -> void:
	_revision += 1
	_stop()
func pause() -> void: cancel()
func seek(value: float) -> void:
	if not is_finite(value): return
	cancel()
	progress = value
func get_band_influence(local_point: Vector2) -> float:
	if not local_point.is_finite() or not size.is_finite() or size.x <= 0 or size.y <= 0: return 0.0
	if progress <= 0.0 or progress >= 1.0: return 0.0
	var travel := Vector2.from_angle(deg_to_rad(band_direction_degrees))
	var extent := travel.abs().dot(size) * 0.5
	var half_width := band_width * 0.5
	var center := lerpf(-extent-half_width, extent+half_width, progress)
	var distance_to_band := absf((local_point-size*.5).dot(travel)-center)
	var softness := minf(edge_softness, half_width)
	if softness <= 0.001: return 1.0 if distance_to_band < half_width else 0.0
	return 1.0-smoothstep(half_width-softness,half_width,distance_to_band)
func get_sample_uv(local_point: Vector2) -> Vector2:
	if size.x <= 0 or size.y <= 0 or not local_point.is_finite(): return Vector2.ZERO
	var normal := Vector2.from_angle(deg_to_rad(rib_angle_degrees))
	var wave := sin((local_point-size*.5).dot(normal)*rib_frequency*TAU/1000.0)
	return (local_point+normal*wave*refraction_amplitude*get_band_influence(local_point))/size
func _draw() -> void:
	# Native TextureRect queues redraw on source texture changes, including null.
	_sync_shader()
func _sync_shader() -> void:
	if not is_instance_valid(_owned_material): return
	_owned_material.set_shader_parameter("source_available", texture != null)
	_owned_material.set_shader_parameter("source_is_premultiplied", source_alpha_mode == 2 or (source_alpha_mode == 0 and texture is ViewportTexture))
	for key in ["progress","band_width","edge_softness","rib_frequency","refraction_amplitude"]:
		_owned_material.set_shader_parameter(key,get(key))
	_owned_material.set_shader_parameter("control_size",size.max(Vector2.ONE))
	_owned_material.set_shader_parameter("band_direction",deg_to_rad(band_direction_degrees))
	_owned_material.set_shader_parameter("rib_angle",deg_to_rad(rib_angle_degrees))
