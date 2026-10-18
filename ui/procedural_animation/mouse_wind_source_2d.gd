class_name MouseWindSource2D
extends Node
## Mouse-to-wind adapter that emits motion velocity.
## WindField2D owns decay; displacement refreshes the local source.
## The first point after enable, reentry or retarget establishes a baseline.

@export var wind_field: WindField2D:
	set(value):
		if wind_field != value:
			reset()
			wind_field = value
@export var enabled := true:
	set(value):
		enabled = value
		if not value:
			reset()
		set_process(enabled and automatic_update)
@export var automatic_update := true:
	set(value):
		automatic_update = value
		reset()
		set_process(enabled and automatic_update)
@export_range(0.0, 2000.0, 1.0, "or_greater") var radius := 180.0:
	set(value): radius = WindField2D._bounded(value, 0.0, 100000.0)
@export_range(0.0, 5.0, 0.01) var strength := 0.65:
	set(value): strength = WindField2D._bounded(value, 0.0, 5.0)
@export_range(0.0, 10000.0, 1.0) var max_speed := 1600.0:
	set(value): max_speed = WindField2D._bounded(value, 0.0, WindField2D.MAX_SPEED)
@export_range(0.01, 60.0, 0.01) var decay_rate := 8.0:
	set(value): decay_rate = WindField2D._bounded(value, 0.01, 60.0)

var _active_field: WindField2D
var _previous_position := Vector2.ZERO
var _has_previous := false
var _previous_was_viewport := false
var _pointer_inside := true
var _viewport_pointer := Vector2.ZERO
var _has_viewport_pointer := false
var _pointer_surface: Node
var _pointer_window: Window

func _enter_tree() -> void:
	reset()
	set_process(enabled and automatic_update)
	# Use Window signals or the owning SubViewportContainer signals.
	var viewport := get_viewport()
	_pointer_surface = viewport if viewport.has_signal("mouse_exited") else viewport.get_parent() as SubViewportContainer
	_connect_pointer_surface(_pointer_surface)
	_pointer_window = get_window()
	if _pointer_window != _pointer_surface:
		_connect_pointer_surface(_pointer_window)

func _exit_tree() -> void:
	_disconnect_pointer_surface(_pointer_surface)
	if _pointer_window != _pointer_surface:
		_disconnect_pointer_surface(_pointer_window)
	_pointer_surface = null
	_pointer_window = null
	reset()

func _connect_pointer_surface(surface: Node) -> void:
	if not is_instance_valid(surface):
		return
	if surface.has_signal("mouse_exited"):
		surface.connect("mouse_exited", _on_mouse_exited)
	if surface.has_signal("mouse_entered"):
		surface.connect("mouse_entered", _on_mouse_entered)

func _disconnect_pointer_surface(surface: Node) -> void:
	if not is_instance_valid(surface):
		return
	if surface.has_signal("mouse_exited") and surface.is_connected("mouse_exited", _on_mouse_exited):
		surface.disconnect("mouse_exited", _on_mouse_exited)
	if surface.has_signal("mouse_entered") and surface.is_connected("mouse_entered", _on_mouse_entered):
		surface.disconnect("mouse_entered", _on_mouse_entered)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		reset()

func _on_mouse_exited() -> void:
	_pointer_inside = false
	reset()

func _on_mouse_entered() -> void:
	_pointer_inside = true
	reset()

## Use native forwarded event positions: SubViewportContainer applies its shrink
## transform before dispatch, preserving pushed-input coordinates.
func _input(event: InputEvent) -> void:
	if enabled and event is InputEventMouseMotion:
		_viewport_pointer = event.position
		_has_viewport_pointer = true

func _process(delta: float) -> void:
	if not _has_viewport_pointer:
		return
	update_from_viewport(_viewport_pointer, delta, _pointer_inside and get_viewport().get_visible_rect().has_point(_viewport_pointer))

## Clear the sample and the source owned by this adapter.
func reset() -> void:
	_has_viewport_pointer = false
	_reset_source()

func _reset_source() -> void:
	if is_instance_valid(_active_field):
		_active_field.remove_source(get_instance_id())
	_active_field = null
	_has_previous = false

func _resolve_field() -> WindField2D:
	return wind_field if is_instance_valid(wind_field) else get_parent() as WindField2D

func _prepare(position: Vector2, delta: float, active: bool, viewport_space: bool) -> WindField2D:
	var field := _resolve_field()
	if not enabled or not active or not is_instance_valid(field) or not field.enabled or not WindField2D._valid_position(position) or not is_finite(delta) or delta <= 0.0:
		reset()
		return null
	if _active_field != field or _previous_was_viewport != viewport_space:
		_reset_source()
	_active_field = field
	_previous_was_viewport = viewport_space
	return field

## Deterministic/manual entry for external cursor replay, in the field's canvas.
## The field owner advances its clock separately through advance(delta).
func update_from_canvas(canvas_position: Vector2, delta: float, active: bool = true) -> bool:
	var field := _prepare(canvas_position, delta, active, false)
	if field == null:
		return false
	var displacement := canvas_position - _previous_position if _has_previous else Vector2.ZERO
	_previous_position = canvas_position
	_has_previous = true
	return _emit_motion(field, canvas_position, displacement, delta)

## Converts viewport position/vector through the field's canvas transform.
## Viewport displacement supplies velocity independently of camera motion.
## Field and adapter must belong to the same viewport; cross-viewport input needs
## an explicit caller-owned conversion and update_from_canvas instead.
func update_from_viewport(viewport_position: Vector2, delta: float, active: bool = true) -> bool:
	var field := _prepare(viewport_position, delta, active, true)
	if field == null:
		return false
	if not is_inside_tree() or not field.is_inside_tree() or get_viewport() != field.get_viewport():
		reset()
		return false
	var transform := field.get_canvas_transform()
	if not transform.x.is_finite() or not transform.y.is_finite() or not transform.origin.is_finite() or not is_finite(transform.determinant()) or absf(transform.determinant()) < 0.000001:
		reset()
		return false
	var inverse := transform.affine_inverse()
	var canvas_position := inverse * viewport_position
	var viewport_displacement := viewport_position - _previous_position if _has_previous else Vector2.ZERO
	var canvas_displacement := inverse.basis_xform(viewport_displacement)
	_previous_position = viewport_position
	_has_previous = true
	return _emit_motion(field, canvas_position, canvas_displacement, delta)

func _emit_motion(field: WindField2D, canvas_position: Vector2, displacement: Vector2, delta: float) -> bool:
	if not displacement.is_finite() or displacement.length_squared() <= 0.000001:
		return false
	# Bound the integration window and sub-millisecond event velocity.
	var dt := clampf(delta, 0.001, WindField2D.MAX_DELTA)
	var velocity := WindField2D._limited_vector(displacement / dt, max_speed) * strength
	return field.set_source(get_instance_id(), WindField2D.LocalSource.create(canvas_position, velocity).with_falloff(radius, decay_rate))
