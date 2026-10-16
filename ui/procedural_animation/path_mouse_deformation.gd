class_name PathMouseDeformation
extends Node
## Rest-relative mouse attraction for PathReveal2D. Owns a private curve copy.
## Target-local offsets update privately owned curves while the reveal clock advances independently.
## External edits of the leased copy promote the WHOLE visible shape to a new
## rest baseline. Prefer editing the original source or disabling before authoring.
## Use call_deferred for update/reset requests made by changed callbacks.
const OWNER_META := &"_path_mouse_deformation_owner"
const SETTLE_EPSILON := 0.001

@export var target: PathReveal2D:
	set(value):
		if target == value and _explicit_target == (value != null):
			return
		_release()
		target = value
		_explicit_target = value != null
@export var enabled := true:
	set(value):
		if enabled == value:
			return
		enabled = value
		if not enabled:
			_release()
		set_process(enabled and is_inside_tree())
@export_range(0.0, 2000.0, 1.0, "or_greater") var radius := 170.0:
	set(value): radius = maxf(value, 0.0) if is_finite(value) else 0.0
@export_range(0.0, 4.0, 0.01, "or_greater") var strength := 0.7:
	set(value): strength = clampf(value, 0.0, 100.0) if is_finite(value) else 0.0
@export_range(0.0, 1000.0, 1.0, "or_greater") var max_offset := 64.0:
	set(value): max_offset = maxf(value, 0.0) if is_finite(value) else 0.0
## Exponential response rate per second. Zero applies the requested offset instantly.
@export_range(0.0, 60.0, 0.1, "or_greater") var smoothing := 14.0:
	set(value): smoothing = maxf(value, 0.0) if is_finite(value) else 0.0
@export var pin_start := true
@export var pin_end := true

var _active_target: PathReveal2D
var _source: PathDefinition
var _private: PathDefinition
var _source_curves: Array[Curve2D] = []
var _private_curves: Array[Curve2D] = []
var _rests: Array[PackedVector2Array] = []
var _source_paths: Array[Curve2D] = []
var _private_paths: Array[Curve2D] = []
var _generation := 0
var _source_dirty := false
var _source_widths_dirty := false
var _owned_width_notifications := 0
var _owned_definition_notifications := 0
var _private_dirty := false
var _writing := false
var _emitting_curve: Curve2D
var _expected_signature := PackedVector2Array()
var _explicit_target := false
var _pointer := Vector2.ZERO
var _has_pointer := false
var _pointer_inside := true

func _enter_tree() -> void:
	set_process(enabled)
	set_process_input(true)
	_pointer_inside = true
	var pointer_window := get_viewport() as Window
	if pointer_window != null:
		pointer_window.mouse_exited.connect(_on_pointer_exited)
		pointer_window.mouse_entered.connect(_on_pointer_entered)

func _exit_tree() -> void:
	var pointer_window := get_viewport() as Window
	if pointer_window != null:
		pointer_window.mouse_exited.disconnect(_on_pointer_exited)
		pointer_window.mouse_entered.disconnect(_on_pointer_entered)
	_release()
	_has_pointer = false

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_pointer = event.position
		_has_pointer = true
		_pointer_inside = get_viewport().get_visible_rect().has_point(_pointer)

func _on_pointer_exited() -> void:
	_pointer_inside = false

func _on_pointer_entered() -> void:
	_pointer_inside = true
	_has_pointer = false

func _process(delta: float) -> void:
	var point := _pointer if _has_pointer else get_viewport().get_mouse_position()
	update_from_viewport(point, delta, _pointer_inside and get_viewport().get_visible_rect().has_point(point))

func is_owning_target() -> bool:
	return is_instance_valid(_active_target) and _private != null and _active_target.definition == _private and _active_target.get_meta(OWNER_META, 0) == get_instance_id()

func _resolve_target() -> PathReveal2D:
	if is_instance_valid(target):
		return target
	return null if _explicit_target else get_parent() as PathReveal2D

func _on_source_changed() -> void:
	_source_dirty = true

func _on_source_widths_changed() -> void:
	_source_widths_dirty = true

func _on_private_changed() -> void:
	if _owned_definition_notifications > 0:
		_owned_definition_notifications -= 1
		return
	# The definition forwards our curve notification while emit_changed is on
	# the stack. Width notifications are watched separately so external width
	# edits in a synchronous callback still count as intentional authoring.
	if _writing and _emitting_curve != null and _curve_signature(_emitting_curve) == _expected_signature:
		return
	_private_dirty = true

func _on_private_widths_changed() -> void:
	if _owned_width_notifications > 0:
		_owned_width_notifications -= 1
		return
	_private_dirty = true

func _on_private_curve_changed(curve: Curve2D) -> void:
	if _writing and curve == _emitting_curve and _curve_signature(curve) == _expected_signature:
		return
	_private_dirty = true

func _disconnect_resources() -> void:
	if _source != null:
		if _source.geometry_changed.is_connected(_on_source_changed):
			_source.geometry_changed.disconnect(_on_source_changed)
		if _source.widths_changed.is_connected(_on_source_widths_changed):
			_source.widths_changed.disconnect(_on_source_widths_changed)
	if _private != null and _private.changed.is_connected(_on_private_changed):
		_private.changed.disconnect(_on_private_changed)
	if _private != null and _private.widths_changed.is_connected(_on_private_widths_changed):
		_private.widths_changed.disconnect(_on_private_widths_changed)
	for curve in _private_curves:
		if curve.changed.is_connected(_on_private_curve_changed.bind(curve)):
			curve.changed.disconnect(_on_private_curve_changed.bind(curve))
	_source_curves.clear()
	_private_curves.clear()
	_rests.clear()

func _on_target_exiting() -> void:
	_release()

func _release() -> void:
	_generation += 1
	if _private != null and _private.get_curves() != _private_paths:
		_private_dirty = true
	# An externally assigned definition retains ownership during release.
	if is_owning_target():
		_active_target.definition = _private if _private_dirty else _source
	if is_instance_valid(_active_target) and _active_target.get_meta(OWNER_META, 0) == get_instance_id():
		_active_target.remove_meta(OWNER_META)
	if is_instance_valid(_active_target) and _active_target.tree_exiting.is_connected(_on_target_exiting):
		_active_target.tree_exiting.disconnect(_on_target_exiting)
	_disconnect_resources()
	_source_paths.clear()
	_private_paths.clear()
	_active_target = null
	_source = null
	_private = null
	_source_dirty = false
	_source_widths_dirty = false
	_owned_width_notifications = 0
	_owned_definition_notifications = 0
	_private_dirty = false

func _acquire(candidate: PathReveal2D, reuse_private: PathDefinition = null) -> bool:
	if candidate == null or not candidate.is_inside_tree() or candidate.is_queued_for_deletion() or candidate.get_viewport() != get_viewport() or candidate.definition == null:
		return false
	var owner_id: int = candidate.get_meta(OWNER_META, 0)
	if owner_id != 0 and owner_id != get_instance_id() and is_instance_id_valid(owner_id):
		return false
	_active_target = candidate
	_source = candidate.definition
	_private = reuse_private if reuse_private != null else PathDefinition.new()
	var copies: Dictionary = {}
	var paths: Array[Curve2D] = []
	for original in _source.get_curves():
		if original == null:
			paths.append(null)
			continue
		if not copies.has(original):
			var copy := original.duplicate(true) as Curve2D
			copies[original] = copy
			_source_curves.append(original)
			_private_curves.append(copy)
			var rest := PackedVector2Array()
			for i in original.point_count:
				rest.append(original.get_point_position(i))
			_rests.append(rest)
		paths.append(copies[original])
	_private.begin_update()
	_private.set_curves(paths)
	_private.copy_widths_from(_source)
	_private.end_update()
	_source_paths.assign(_source.get_curves())
	_private_paths.assign(paths)
	_source.geometry_changed.connect(_on_source_changed)
	_source.widths_changed.connect(_on_source_widths_changed)
	_private.changed.connect(_on_private_changed)
	_private.widths_changed.connect(_on_private_widths_changed)
	for curve in _private_curves:
		curve.changed.connect(_on_private_curve_changed.bind(curve))
	candidate.tree_exiting.connect(_on_target_exiting)
	candidate.set_meta(OWNER_META, get_instance_id())
	candidate.definition = _private
	_source_dirty = false
	_source_widths_dirty = false
	_owned_width_notifications = 0
	_owned_definition_notifications = 0
	_private_dirty = false
	return true

func _ensure_ownership() -> bool:
	if not enabled or not is_inside_tree():
		return false
	var candidate := _resolve_target()
	if candidate != _active_target or not is_owning_target():
		_release()
		return _acquire(candidate)
	if _private.get_curves() != _private_paths:
		_private_dirty = true
	if _source.get_curves() != _source_paths:
		_source_dirty = true
	if _private_dirty:
		# Intentional external edits of the leased copy become a new authoring
		# baseline. Release preserves it; reacquire makes a fresh private copy.
		_release()
		return _acquire(candidate)
	if _source_dirty:
		# Rebuild geometry and metadata into the same leased output identity.
		# Deformation ticks retain the private width profiles.
		var retained_private := _private
		_release()
		return _acquire(candidate, retained_private)
	if _source_widths_dirty:
		return _copy_source_widths()
	return true

func _copy_source_widths() -> bool:
	# Copy metadata while retaining the private geometry, rest baseline and
	# current deformation. The copy API publishes one notification pair.
	var generation := _generation
	_source_widths_dirty = false
	_writing = true
	_owned_width_notifications = 1
	_owned_definition_notifications = 1
	_private.copy_widths_from(_source)
	# Consume the expected pair of signals. Any nested external edit
	# produces an extra notification and remains intentional private authoring.
	_owned_width_notifications = 0
	_owned_definition_notifications = 0
	_writing = false
	if generation != _generation or not is_owning_target():
		return false
	return not _private_dirty and not _source_dirty and not _source_widths_dirty and _private.get_curves() == _private_paths and _source.get_curves() == _source_paths

func update_from_viewport(viewport_mouse: Vector2, delta: float, pointer_inside := true) -> int:
	if _writing or not _ensure_ownership():
		return 0
	var transform := _active_target.get_global_transform_with_canvas()
	if not transform.is_finite() or absf(transform.determinant()) < 0.000001:
		return update_at(Vector2.ZERO, delta, false)
	return update_at(transform.affine_inverse() * viewport_mouse, delta, pointer_inside)

func _curve_signature(curve: Curve2D) -> PackedVector2Array:
	var signature := PackedVector2Array([Vector2(curve.bake_interval, 0)])
	for i in curve.point_count:
		signature.append(curve.get_point_position(i))
		signature.append(curve.get_point_in(i))
		signature.append(curve.get_point_out(i))
	return signature

func _emit_owned_change(curve: Curve2D) -> bool:
	# Signals may synchronously disable/rebind us or edit the just-written curve.
	var generation := _generation
	var expected := _curve_signature(curve)
	_emitting_curve = curve
	_expected_signature = expected
	curve.emit_changed()
	_emitting_curve = null
	if generation != _generation or not is_owning_target():
		_writing = false
		return false
	if _curve_signature(curve) != expected:
		_private_dirty = true
	if _private_dirty or _source_dirty or _source_widths_dirty or _private.get_curves() != _private_paths or _source.get_curves() != _source_paths:
		_writing = false
		return false
	return true

func update_at(local_mouse: Vector2, delta: float, pointer_inside := true) -> int:
	if _writing or not _ensure_ownership():
		return 0
	var mouse_valid := pointer_inside and local_mouse.is_finite() and radius > 0.0 and strength > 0.0 and max_offset > 0.0
	var safe_delta := maxf(delta, 0.0) if is_finite(delta) else 0.0
	var blend := 1.0 if smoothing == 0.0 else 1.0 - exp(-smoothing * safe_delta)
	var changed := 0
	_writing = true
	for c in _private_curves.size():
		var curve := _private_curves[c]
		var rest := _rests[c]
		var curve_changed := false
		curve.set_block_signals(true)
		for i in rest.size():
			var offset := Vector2.ZERO
			var pinned := (pin_start and i == 0) or (pin_end and i == rest.size() - 1)
			if mouse_valid and not pinned:
				var difference := local_mouse - rest[i]
				var distance := difference.length()
				if distance < radius:
					var falloff := 1.0 - distance / radius
					falloff = falloff * falloff * (3.0 - 2.0 * falloff)
					offset = (difference * (strength * falloff)).limit_length(max_offset)
			var desired := rest[i] + offset
			var current := curve.get_point_position(i)
			var next := desired if pinned else current.lerp(desired, blend)
			# Immediate projection honors a newly lowered displacement bound.
			if (next - rest[i]).length() > max_offset + 0.00001:
				next = rest[i] + (next - rest[i]).limit_length(max_offset)
			if (blend > 0.0 or pinned) and next.distance_squared_to(desired) <= SETTLE_EPSILON * SETTLE_EPSILON:
				next = desired
			if next != current:
				curve.set_point_position(i, next)
				changed += 1
				curve_changed = true
		curve.set_block_signals(false)
		if curve_changed and not _emit_owned_change(curve):
			return changed
	_writing = false
	return changed

func reset_shape() -> void:
	if _writing or not _ensure_ownership():
		return
	_writing = true
	for c in _private_curves.size():
		var curve := _private_curves[c]
		var changed := false
		curve.set_block_signals(true)
		for i in _rests[c].size():
			if curve.get_point_position(i) != _rests[c][i]:
				curve.set_point_position(i, _rests[c][i])
				changed = true
		curve.set_block_signals(false)
		if changed and not _emit_owned_change(curve):
			return
	_writing = false
