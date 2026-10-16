@tool
class_name RadialSectorSweep
extends Control
## Reusable polar-sector mask. Transparent, passive, aspect-correct, finite work.
signal angle_changed(value: float)
signal playback_finished
const SHADER = preload("res://addons/gdbase/ui/radial_sector_sweep/radial_sector_sweep.gdshader")
@export_group("Geometry")
@export_range(0, 32, 1) var sector_count: int = 2:
	set(value):
		sector_count = clampi(value, 0, 32)
		queue_redraw()
@export_range(0.0, 360.0, 0.1) var aperture_degrees: float = 40.0:
	set(value):
		if is_finite(value):
			aperture_degrees = clampf(value, 0.0, 360.0)
			queue_redraw()
@export var center_ratio: Vector2 = Vector2(0.5, 0.5):
	set(value):
		if value.is_finite():
			center_ratio = value.clamp(Vector2(-2, -2), Vector2(3, 3))
			queue_redraw()
@export_range(0.0, 8192.0, 1.0) var inner_radius: float = 0.0:
	set(value):
		if is_finite(value):
			inner_radius = clampf(value, 0.0, 8192.0)
			queue_redraw()
@export_range(0.0, 8192.0, 1.0) var outer_radius: float = 780.0:
	set(value):
		if is_finite(value):
			outer_radius = clampf(value, 0.0, 8192.0)
			queue_redraw()
@export_group("Motion")
@export_range(-360.0, 360.0, 0.1) var start_angle_degrees: float = -60.0:
	set(value):
		if is_finite(value):
			start_angle_degrees = wrapf(value, -180.0, 180.0)
			queue_redraw()
@export_range(-720.0, 720.0, 0.1) var angular_speed_degrees: float = 64.0:
	set(value):
		if is_finite(value): angular_speed_degrees = clampf(value, -720.0, 720.0)
@export_range(0.0, 360.0, 0.1) var phase_degrees: float = 0.0:
	set(value):
		if is_finite(value):
			var next := wrapf(value, 0.0, 360.0)
			if next != phase_degrees:
				phase_degrees = next
				queue_redraw()
				angle_changed.emit(phase_degrees)
@export var autoplay: bool = false
@export_group("Colors")
@export var sector_color: Color = Color(0.025, 0.69, 0.72, 1.0):
	set(value):
		if _finite_color(value):
			sector_color = value
			queue_redraw()
@export var alternate_color: Color = Color(0.93, 0.55, 0.22, 1.0):
	set(value):
		if _finite_color(value):
			alternate_color = value
			queue_redraw()
@export var alternate_colors: bool = false:
	set(value):
		alternate_colors = value
		queue_redraw()
var playing: bool = false
var direction: float = 1.0
var _revision: int = 0
var _did_ready: bool = false
var _owned_material: ShaderMaterial

func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	focus_mode = FOCUS_NONE
	clip_contents = true
	_owned_material = ShaderMaterial.new()
	_owned_material.shader = SHADER
	material = _owned_material

func _enter_tree() -> void:
	set_process(false)
	if not resized.is_connected(queue_redraw): resized.connect(queue_redraw)
	if not visibility_changed.is_connected(_visibility_changed): visibility_changed.connect(_visibility_changed)
	queue_redraw()

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
	# Reduce time before multiplication to stay finite even at extreme finite delta.
	var speed := angular_speed_degrees * direction
	if speed != 0.0:
		phase_degrees += fmod(delta, 360.0 / absf(speed)) * speed
func replay() -> void:
	_revision += 1
	var revision := _revision
	cancel_processing()
	direction = 1.0
	phase_degrees = 0.0
	if revision == _revision: _play()
func reverse() -> void:
	_revision += 1
	direction = -direction
	_play()
func resume() -> void:
	_revision += 1
	_play()
func _play() -> void:
	playing = is_inside_tree() and is_visible_in_tree() and not is_queued_for_deletion() and not Engine.is_editor_hint()
	set_process(playing)
func cancel_processing() -> void:
	playing = false
	set_process(false)
func cancel() -> void:
	_revision += 1
	cancel_processing()
func pause() -> void: cancel()
func seek(degrees: float) -> void:
	if not is_finite(degrees): return
	cancel()
	phase_degrees = degrees
func get_angle_degrees() -> float: return wrapf(start_angle_degrees + phase_degrees, 0.0, 360.0)
func contains_local(point: Vector2) -> bool:
	if not point.is_finite() or sector_count <= 0 or aperture_degrees <= 0.0 or outer_radius <= inner_radius: return false
	if size.x <= 0.0 or size.y <= 0.0 or not Rect2(Vector2.ZERO, size).has_point(point): return false
	var p := point - size * center_ratio
	if p.length() < inner_radius or p.length() > outer_radius: return false
	var spacing := TAU / sector_count
	var angle := wrapf(p.angle() - deg_to_rad(get_angle_degrees()) + spacing * 0.5, 0.0, spacing) - spacing * 0.5
	return absf(angle) <= deg_to_rad(aperture_degrees) * 0.5
func _finite_color(value: Color) -> bool:
	return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)
func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0 or not size.is_finite(): return
	for key in ["sector_count", "inner_radius", "outer_radius", "center_ratio", "sector_color", "alternate_color", "alternate_colors"]:
		_owned_material.set_shader_parameter(key, get(key))
	_owned_material.set_shader_parameter("control_size", size)
	_owned_material.set_shader_parameter("angle", deg_to_rad(get_angle_degrees()))
	_owned_material.set_shader_parameter("aperture", deg_to_rad(aperture_degrees))
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
