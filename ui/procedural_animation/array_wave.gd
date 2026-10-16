@tool
class_name ArrayWave
extends Node
## Drives inner Visual transforms while the outer layout owns Slots.
## Compose additional animation below Visual or on another wrapper.

enum PhaseMode { INDEX, DISTANCE }
enum SourceMode { FIXED, MOUSE, CONTROL }

@export var enabled := true:
	set(value):
		enabled = value
		if not value: release_all()
@export var preview_in_editor := false:
	set(value):
		preview_in_editor = value
		if not value and Engine.is_editor_hint(): release_all()
@export var slots_root: Control:
	set(value):
		if slots_root != value:
			release_all()
			slots_root = value
@export var visual_path: NodePath = ^"Visual":
	set(value):
		if visual_path != value:
			release_all()
			visual_path = value
@export var include_hidden := false
@export_group("Phase")
@export var phase_mode := PhaseMode.INDEX
@export_range(-6.283185, 6.283185, 0.01) var phase_step := 0.35
@export_range(1.0, 2000.0, 1.0) var wavelength := 160.0
@export_range(-10.0, 10.0, 0.01) var frequency := 0.7
@export_range(-6.283185, 6.283185, 0.01) var phase_offset := 0.0
@export_group("Source / independent falloff")
@export var source_mode := SourceMode.FIXED
@export var source_position := Vector2.ZERO
@export var source_control: Control
## Zero disables attenuation; phase and falloff are independently composable.
@export_range(0.0, 4000.0, 1.0) var falloff_radius := 0.0
@export_range(0.01, 10.0, 0.01) var falloff_power := 1.0
@export_group("Translation")
@export var translate_enabled := true
@export var translation := Vector2(0.0, 12.0)
@export_range(-6.283185, 6.283185, 0.01) var translation_phase := 0.0
@export_group("Rotation")
@export var rotate_enabled := true
@export_range(-180.0, 180.0, 0.1) var rotation_degrees := 8.0
@export_range(-6.283185, 6.283185, 0.01) var rotation_phase := 0.0
@export_group("Scale / multiplicative")
@export var scale_enabled := true
@export var scale_amount := Vector2(0.08, 0.08)
@export_range(-6.283185, 6.283185, 0.01) var scale_phase := 0.0

const CLAIM := &"_array_wave_transform_owner"
var time_seconds := 0.0
var ownership_status := "idle"
var _entries: Dictionary = {}
var _blocked: Dictionary = {}
var _pointer_seen := false
var _pointer_position := Vector2.ZERO

class Entry:
	var slot: Control
	var visual: Control
	var parent: Node
	var position: Vector2
	var rotation: float
	var scale: Vector2
	var last_position: Vector2
	var last_rotation: float
	var last_scale: Vector2
	var exit_callback: Callable
	var center: Vector2

func _enter_tree() -> void:
	_pointer_seen = false

func _input(event: InputEvent) -> void:
	# Use viewport input coordinates: supports native, embedded and replay input.
	if event is InputEventMouse and event.position.is_finite():
		_pointer_position = event.position
		_pointer_seen = true

func _process(delta: float) -> void:
	if not Engine.is_editor_hint() or preview_in_editor:
		advance(delta)

func _exit_tree() -> void:
	release_all()

func advance(delta: float) -> void:
	if not is_finite(delta) or delta < 0.0: return
	if enabled:
		time_seconds += delta
		sample_at(time_seconds)

func tracked_count() -> int:
	return _entries.size()

func blocked_count() -> int:
	return _blocked.size()

func reset_ownership() -> void:
	release_all()
	_blocked.clear()
	ownership_status = "idle"

func release_all() -> void:
	for id in _entries.keys():
		_release(id, false)

func _owns_claim(visual: Control) -> bool:
	if not visual.has_meta(CLAIM): return false
	var claim = visual.get_meta(CLAIM)
	return claim is WeakRef and claim.get_ref() == self

func _available(visual: Control) -> bool:
	if not visual.has_meta(CLAIM): return true
	var claim = visual.get_meta(CLAIM)
	return claim is WeakRef and (claim.get_ref() == null or claim.get_ref() == self)

func _unchanged(entry: Entry) -> bool:
	return is_instance_valid(entry.visual) and entry.visual.get_parent() == entry.parent and entry.visual.position.is_equal_approx(entry.last_position) and is_equal_approx(entry.visual.rotation, entry.last_rotation) and entry.visual.scale.is_equal_approx(entry.last_scale)

func _release(id: int, block: bool) -> void:
	if not _entries.has(id): return
	var entry: Entry = _entries[id]
	block = block or not _unchanged(entry)
	_entries.erase(id)
	if is_instance_valid(entry.visual):
		# Restore owned fields while their parent and most recent writes match.
		# Preserve external edits and coordinates belonging to another parent.
		if entry.visual.get_parent() == entry.parent and _owns_claim(entry.visual):
			if entry.visual.position.is_equal_approx(entry.last_position): entry.visual.position = entry.position
			if is_equal_approx(entry.visual.rotation, entry.last_rotation): entry.visual.rotation = entry.rotation
			if entry.visual.scale.is_equal_approx(entry.last_scale): entry.visual.scale = entry.scale
		if _owns_claim(entry.visual): entry.visual.remove_meta(CLAIM)
		if entry.visual.tree_exiting.is_connected(entry.exit_callback):
			entry.visual.tree_exiting.disconnect(entry.exit_callback)
		if block: _blocked[id] = weakref(entry.visual)

func _visual_exiting(id: int) -> void:
	_release(id, true)

func _capture(slot: Control, visual: Control) -> Entry:
	var entry := Entry.new()
	entry.slot = slot
	entry.visual = visual
	entry.parent = visual.get_parent()
	entry.position = visual.position
	entry.rotation = visual.rotation
	entry.scale = visual.scale
	entry.last_position = entry.position
	entry.last_rotation = entry.rotation
	entry.last_scale = entry.scale
	entry.exit_callback = _visual_exiting.bind(visual.get_instance_id())
	visual.tree_exiting.connect(entry.exit_callback)
	visual.set_meta(CLAIM, weakref(self))
	_entries[visual.get_instance_id()] = entry
	return entry

func _parameters_valid() -> bool:
	return is_finite(frequency) and is_finite(phase_step) and is_finite(phase_offset) and is_finite(wavelength) and wavelength > 0.0 and is_finite(falloff_radius) and is_finite(falloff_power) and falloff_power > 0.0 and translation.is_finite() and scale_amount.is_finite() and is_finite(rotation_degrees) and is_finite(translation_phase) and is_finite(rotation_phase) and is_finite(scale_phase)

func sample_at(seconds: float) -> void:
	if not enabled or not is_inside_tree() or (Engine.is_editor_hint() and not preview_in_editor):
		release_all()
		return
	if not is_instance_valid(slots_root) or not slots_root.is_inside_tree() or slots_root.get_viewport() != get_viewport() or not _parameters_valid() or not is_finite(seconds):
		release_all()
		ownership_status = "invalid root or parameters"
		return
	var root_transform := slots_root.get_global_transform_with_canvas()
	if not root_transform.is_finite() or absf(root_transform.determinant()) < 0.000001:
		release_all()
		ownership_status = "non-invertible root"
		return
	var inverse := root_transform.affine_inverse()
	var origin := source_position
	if source_mode == SourceMode.MOUSE:
		origin = inverse * (_pointer_position if _pointer_seen else get_viewport().get_mouse_position())
	elif source_mode == SourceMode.CONTROL:
		if not is_instance_valid(source_control) or not source_control.is_inside_tree() or source_control.get_viewport() != get_viewport():
			release_all()
			ownership_status = "invalid source"
			return
		origin = inverse * (source_control.get_global_transform_with_canvas() * (source_control.size * 0.5))
	if not origin.is_finite():
		release_all()
		ownership_status = "invalid source"
		return
	time_seconds = seconds
	# A compact participant list avoids phase holes from helper Nodes, empty slots,
	# hidden visuals or controls whose transforms belong to another driver.
	var participants: Array[Entry] = []
	var present: Dictionary = {}
	for child in slots_root.get_children():
		if not child is Control or child.is_queued_for_deletion(): continue
		var slot := child as Control
		var visual := slot.get_node_or_null(visual_path) as Control
		if not is_instance_valid(visual) or visual == slot or visual.is_queued_for_deletion() or not visual.is_inside_tree(): continue
		# The dedicated wrapper must sit directly under its layout-owned slot. A
		# Container as that parent would write the same transform and is rejected.
		if visual.get_parent() != slot or slot is Container: continue
		var id := visual.get_instance_id()
		var center := inverse * (slot.get_global_transform_with_canvas() * (slot.size * 0.5))
		if not center.is_finite(): continue
		if not include_hidden and not visual.is_visible_in_tree(): continue
		if not visual.position.is_finite() or not visual.scale.is_finite() or not is_finite(visual.rotation): continue
		if _entries.has(id):
			var existing: Entry = _entries[id]
			if existing.slot != slot or not _unchanged(existing) or not _owns_claim(visual):
				_release(id, true)
		if _blocked.has(id) or not _available(visual): continue
		var entry: Entry = _entries[id] if _entries.has(id) else _capture(slot, visual)
		entry.center = center
		participants.append(entry)
		present[id] = true
	for id in _entries.keys():
		if not present.has(id): _release(id, false)
	for id in _blocked.keys():
		if _blocked[id].get_ref() == null: _blocked.erase(id)
	for index in participants.size():
		var entry := participants[index]
		var distance := entry.center.distance_to(origin)
		var coordinate := float(index) * phase_step if phase_mode == PhaseMode.INDEX else distance / wavelength * TAU
		var phase := seconds * frequency * TAU - coordinate + phase_offset
		var weight := pow(clampf(1.0 - distance / falloff_radius, 0.0, 1.0), falloff_power) if falloff_radius > 0.0 else 1.0
		entry.last_position = entry.position + translation * sin(phase + translation_phase) * weight if translate_enabled else entry.position
		entry.last_rotation = entry.rotation + deg_to_rad(rotation_degrees) * sin(phase + rotation_phase) * weight if rotate_enabled else entry.rotation
		var multiplier := Vector2.ONE + scale_amount * sin(phase + scale_phase) * weight if scale_enabled else Vector2.ONE
		# Preserve authored mirrored scales with a positive wave multiplier.
		entry.last_scale = entry.scale * multiplier.max(Vector2(0.01, 0.01))
		if not entry.last_position.is_finite() or not is_finite(entry.last_rotation) or not entry.last_scale.is_finite():
			# Keep the last owned pose available to conditional restoration.
			entry.last_position = entry.visual.position
			entry.last_rotation = entry.visual.rotation
			entry.last_scale = entry.visual.scale
			_release(entry.visual.get_instance_id(), true)
			continue
		entry.visual.position = entry.last_position
		entry.visual.rotation = entry.last_rotation
		entry.visual.scale = entry.last_scale
	ownership_status = "%d owned / %d released" % [_entries.size(), _blocked.size()]
