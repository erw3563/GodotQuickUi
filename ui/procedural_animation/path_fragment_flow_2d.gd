@tool
class_name PathFragmentFlow2D
extends Node2D
## Persistent seeded shards addressed by arc length on Curve2D paths.
## Drift, spatial noise, orientation and signed flow are independently composable.
## Curves are read-only; closing a path uses an owned working copy.
## Generated polygons are drawn alongside the authored child nodes.

@export_group("Path and distribution")
@export var definition: PathDefinition:
	set(value):
		_disconnect_resources()
		definition = value
		_connect_resources()
		_request_rebuild()
@export_range(0, 256, 1) var fragment_count: int = 28:
	set(value):
		fragment_count = clampi(value, 0, 256)
		_request_rebuild()
@export_range(100000, 999999, 1) var random_seed: int = 318527:
	set(value):
		random_seed = clampi(value, 100000, 999999)
		_request_rebuild()
## Zero gives uniform arc-length slots; one gives fully seeded spacing.
@export_range(0.0, 1.0, 0.01) var spacing_jitter: float = 1.0:
	set(value):
		spacing_jitter = clampf(_finite(value), 0.0, 1.0)
		_request_rebuild()
## Matching endpoints identify a closed path. An open path receives a closing
## segment in a private working copy when close_paths is enabled.
@export var close_paths: bool = false:
	set(value):
		close_paths = value
		notify_property_list_changed()
		_request_rebuild()
@export_range(0.0, 1000.0, 1.0) var half_width: float = 80.0:
	set(value):
		half_width = clampf(_finite(value), -100000.0, 100000.0)
		queue_redraw()
@export_group("Along-path taper")
## Directional taper is for open paths. Closed paths always use constant end_scale
## and corridor width to keep the seam continuous.
@export var taper_enabled: bool = true:
	set(value):
		taper_enabled = value
		notify_property_list_changed()
		queue_redraw()
@export_range(0.0, 1.0, 0.01) var start_width_ratio: float = 0.08:
	set(value):
		start_width_ratio = clampf(_finite(value), -100000.0, 100000.0)
		queue_redraw()
@export_range(0.1, 4.0, 0.01) var taper_power: float = 1.0:
	set(value):
		taper_power = clampf(_finite(value), -100000.0, 100000.0)
		queue_redraw()

@export_group("Fragment geometry")
@export_enum("Splinters", "Facets", "Mixed", "Circle", "Rectangle", "Texture") var shape_style: int = 2:
	set(value):
		shape_style = clampi(value, 0, 5)
		notify_property_list_changed()
		queue_redraw()
@export var fragment_texture: Texture2D:
	set(value):
		if fragment_texture != null and fragment_texture.changed.is_connected(_texture_changed):
			fragment_texture.changed.disconnect(_texture_changed)
		fragment_texture = value
		if is_inside_tree() and fragment_texture != null:
			fragment_texture.changed.connect(_texture_changed)
		_texture_changed()
@export var texture_keep_aspect: bool = true:
	set(value):
		texture_keep_aspect = value
		notify_property_list_changed()
		queue_redraw()
@export_range(8, 64, 1) var circle_segments: int = 24:
	set(value):
		circle_segments = clampi(value, 8, 64)
		queue_redraw()
@export_range(1.0, 500.0, 1.0) var length_min: float = 25.0:
	set(value):
		length_min = clampf(_finite(value), -100000.0, 100000.0)
		queue_redraw()
@export_range(1.0, 500.0, 1.0) var length_max: float = 145.0:
	set(value):
		length_max = clampf(_finite(value), -100000.0, 100000.0)
		queue_redraw()
@export_range(1.0, 200.0, 1.0) var width_min: float = 7.0:
	set(value):
		width_min = clampf(_finite(value), -100000.0, 100000.0)
		queue_redraw()
@export_range(1.0, 200.0, 1.0) var width_max: float = 32.0:
	set(value):
		width_max = clampf(_finite(value), -100000.0, 100000.0)
		queue_redraw()
@export_range(0.0, 3.0, 0.01) var start_scale: float = 0.3:
	set(value):
		start_scale = clampf(_finite(value), -100000.0, 100000.0)
		queue_redraw()
@export_range(0.0, 3.0, 0.01) var end_scale: float = 1.0:
	set(value):
		end_scale = clampf(_finite(value), -100000.0, 100000.0)
		queue_redraw()
@export_range(0.0, 180.0, 0.1) var angle_spread: float = 24.0:
	set(value):
		angle_spread = clampf(_finite(value), -100000.0, 100000.0)
		queue_redraw()
@export var color: Color = Color("f7f8ee"):
	set(value):
		color = value
		queue_redraw()

@export_group("Bounded drift and turning")
@export var drift_enabled: bool = true:
	set(value):
		drift_enabled = value
		notify_property_list_changed()
		queue_redraw()
## Zero uses independent seeded phases; one gives neighboring slots a coherent wave.
@export_range(0.0, 1.0, 0.01) var drift_coherence: float = 0.0:
	set(value):
		drift_coherence = clampf(_finite(value), 0.0, 1.0)
		queue_redraw()
@export_range(0.0, 100.0, 0.1) var drift_distance: float = 9.0:
	set(value):
		drift_distance = clampf(_finite(value), -100000.0, 100000.0)
		queue_redraw()
@export_range(0.0, 100.0, 0.1) var lateral_drift: float = 5.0:
	set(value):
		lateral_drift = clampf(_finite(value), -100000.0, 100000.0)
		queue_redraw()
@export_range(0.0, 4.0, 0.01) var drift_frequency: float = 0.13:
	set(value):
		drift_frequency = clampf(_finite(value), -100000.0, 100000.0)
		queue_redraw()
@export_range(0.0, 90.0, 0.1) var turn_amount: float = 8.0:
	set(value):
		turn_amount = clampf(_finite(value), -100000.0, 100000.0)
		queue_redraw()
@export_range(0.0, 0.95, 0.01) var foreshorten_amount: float = 0.35:
	set(value):
		foreshorten_amount = clampf(_finite(value), -100000.0, 100000.0)
		queue_redraw()

@export_group("Path-normal detail")
## Smooth spatial variation, separate from time-driven drift. Integer cycles make
## noise and its derivative continuous at a closed seam.
@export_range(0.0, 100.0, 0.1) var normal_noise: float = 0.0:
	set(value):
		normal_noise = clampf(_finite(value), 0.0, 100.0)
		notify_property_list_changed()
		queue_redraw()
@export_range(1, 32, 1) var noise_cycles: int = 3:
	set(value):
		noise_cycles = clampi(value, 1, 32)
		queue_redraw()

@export_group("Continuous curve flow")
@export var flow_enabled: bool = true:
	set(value):
		flow_enabled = value
		notify_property_list_changed()
		queue_redraw()
## Orient fragments along their actual signed flow and drift velocity.
@export var orient_to_motion: bool = false:
	set(value):
		orient_to_motion = value
		queue_redraw()
## Zero preserves stable slots. Nonzero advances in pixels/sec. Open ends fade; closed seams stay visible.
@export_range(-1000.0, 1000.0, 0.1) var flow_speed: float = 0.0:
	set(value):
		flow_speed = clampf(_finite(value), -100000.0, 100000.0)
		queue_redraw()
@export_range(0.001, 0.25, 0.001) var flow_edge_fade: float = 0.06:
	set(value):
		flow_edge_fade = clampf(_finite(value), -100000.0, 100000.0)
		queue_redraw()

@export_group("Playback")
## Explicit time makes scrubbing and replay deterministic. An external clock
## can drive this property through a scene-authored Control bridge.
@export var time: float = 0.0:
	set(value):
		time = clampf(_finite(value), -1.0e12, 1.0e12)
		queue_redraw()
## External clocks set this to their direction as well when orient_to_motion is on.
@export_range(-4.0, 4.0, 0.01) var playback_speed: float = 1.0:
	set(value):
		playback_speed = clampf(_finite(value), -4.0, 4.0)
		queue_redraw()
@export var autoplay: bool = true
@export var preview_animation: bool = false
@export_tool_button("Reset animation") var reset_button: Callable = reset_animation

var _slots: Array[Dictionary] = []
var _curves: Array[Curve2D] = []
var _bound_definition: PathDefinition
var _bound_curves: Array[Curve2D] = []
var _rebuild_queued := false

func _enter_tree() -> void:
	if fragment_texture != null and not fragment_texture.changed.is_connected(_texture_changed):
		fragment_texture.changed.connect(_texture_changed)
	_connect_resources()
	rebuild()

func _exit_tree() -> void:
	_disconnect_resources()
	if fragment_texture != null and fragment_texture.changed.is_connected(_texture_changed):
		fragment_texture.changed.disconnect(_texture_changed)

func _process(delta: float) -> void:
	if autoplay and (not Engine.is_editor_hint() or preview_animation):
		advance_animation(delta * playback_speed)
	elif Engine.is_editor_hint():
		# Inspector geometry edits should preview even while the clock is paused.
		queue_redraw()

func reset_animation() -> void:
	time = 0.0

func advance_animation(delta: float) -> void:
	if is_finite(delta):
		time += delta

func _request_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	rebuild.call_deferred()

func rebuild() -> void:
	_rebuild_queued = false
	_slots.clear()
	_curves.clear()
	if definition == null:
		queue_redraw()
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	for curve_index in definition.get_curves().size():
		var curve := definition.get_curves()[curve_index]
		if curve == null or curve.point_count < 2 or not _curve_is_finite(curve):
			continue
		if not is_finite(curve.get_baked_length()) or curve.get_baked_length() <= 0.001:
			continue
		var closed := _is_closed(curve)
		if close_paths and not closed:
			curve = curve.duplicate(true) as Curve2D
			curve.add_point(curve.get_point_position(0), curve.get_point_in(0))
			closed = true
		_curves.append(curve)
		for i in fragment_count:
			_slots.append({
				"curve": curve, "closed": closed, "path_index": curve_index, "slot_index": i,
				"u": (float(i) + lerpf(0.5, rng.randf_range(0.12, 0.88), spacing_jitter)) / maxf(fragment_count, 1),
				"side": rng.randf_range(-1.0, 1.0),
				"length": rng.randf(), "width": rng.randf(),
				"angle": rng.randf_range(-1.0, 1.0),
				"phase": rng.randf_range(0.0, TAU),
				"frequency": rng.randf_range(0.7, 1.3),
				"shape": rng.randi_range(0, 2),
				"cut": rng.randf_range(0.12, 0.4),
			})
	notify_property_list_changed()
	queue_redraw()
	if is_inside_tree():
		update_configuration_warnings()

## Returns value snapshots owned by the caller.
func get_fragment_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot in _slots:
		var curve: Curve2D = slot["curve"]
		var total := curve.get_baked_length()
		if not is_finite(total) or total <= 0.001 or not _curve_is_finite(curve):
			continue
		var pose := _sample_pose(slot, time)
		var u: float = pose.distance / total
		var phase: float = pose.phase
		var scale_factor := maxf(lerpf(start_scale, end_scale, u) if taper_enabled and not slot.closed else end_scale, 0.0)
		var length := lerpf(maxf(minf(length_min, length_max), 0.0), maxf(maxf(length_min, length_max), 0.0), slot["length"]) * scale_factor
		var width := lerpf(maxf(minf(width_min, width_max), 0.0), maxf(maxf(width_min, width_max), 0.0), slot["width"]) * scale_factor
		if shape_style == 3:
			width = length
		elif shape_style == 5 and texture_keep_aspect and fragment_texture != null and fragment_texture.get_width() > 0:
			width = length * float(fragment_texture.get_height()) / fragment_texture.get_width()
		if drift_enabled:
			width *= 1.0 - clampf(foreshorten_amount, 0.0, 0.95) * (0.5 + 0.5 * sin(phase * 0.81))
		var facing: Vector2 = pose.tangent
		var velocity := Vector2.ZERO
		if orient_to_motion:
			# Open respawn points use the flow velocity across their wrap.
			var before := _sample_pose(slot, time - 0.001)
			var after := _sample_pose(slot, time + 0.001)
			if slot.closed or absf(after.distance - before.distance) < total * 0.5:
				velocity = (after.center - before.center) / 0.002
			else:
				velocity = facing * (flow_speed if flow_enabled else 0.0)
			velocity *= signf(playback_speed) if not is_zero_approx(playback_speed) else 1.0
			if velocity.length_squared() > 0.000001:
				facing = velocity.normalized()
		var turning := sin(phase * 0.91) * turn_amount if drift_enabled else 0.0
		var angle := facing.angle() + deg_to_rad(slot["angle"] * angle_spread + turning)
		var polygon: PackedVector2Array
		if shape_style == 3:
			polygon = _circle_polygon(circle_segments)
		elif shape_style >= 4:
			polygon = _rectangle_polygon()
		else:
			var shape: int = slot["shape"] if shape_style == 2 else (0 if shape_style == 0 else 2)
			polygon = _local_polygon(shape, slot["cut"])
		for i in polygon.size():
			polygon[i] = pose.center + Vector2(polygon[i].x * length, polygon[i].y * width).rotated(angle)
		var alpha := 1.0
		if flow_enabled and not is_zero_approx(flow_speed) and not slot.closed:
			var edge := clampf(flow_edge_fade, 0.001, 0.25)
			alpha = smoothstep(0.0, edge, u) * smoothstep(0.0, edge, 1.0 - u)
		result.append({"path_index": slot["path_index"], "slot_index": slot["slot_index"], "base_distance": slot["u"] * total, "distance": pose.distance, "center": pose.center, "tangent": pose.tangent, "facing": facing, "velocity": velocity, "angle": angle, "closed": slot.closed, "lateral": pose.lateral, "vertices": polygon, "alpha": alpha})
	return result

func _sample_pose(slot: Dictionary, clock: float) -> Dictionary:
	var curve: Curve2D = slot.curve
	var total := curve.get_baked_length()
	var coherent_phase: float = slot.u * TAU + float(random_seed % 997) * 0.01
	var phase: float = lerpf(slot.phase, coherent_phase, drift_coherence) + clock * TAU * maxf(drift_frequency, 0.0) * lerpf(slot.frequency, 1.0, drift_coherence)
	var travel := clock * flow_speed if flow_enabled else 0.0
	var longitudinal := sin(phase) * maxf(drift_distance, 0.0) if drift_enabled else 0.0
	var raw_distance: float = slot.u * total + travel + longitudinal
	var wraps: bool = slot.closed or (flow_enabled and not is_zero_approx(flow_speed))
	var distance := fposmod(raw_distance, total) if wraps else clampf(raw_distance, 0.0, total)
	var u := distance / total
	var frame := curve.sample_baked_with_rotation(distance, true)
	var tangent := frame.x.normalized()
	if slot.closed:
		# Central cyclic differences provide a continuous normal at the seam.
		var epsilon := minf(0.5, total * 0.001)
		tangent = (curve.sample_baked(fposmod(distance + epsilon, total), true) - curve.sample_baked(fposmod(distance - epsilon, total), true)).normalized()
	if tangent.is_zero_approx() or not tangent.is_finite():
		tangent = Vector2.RIGHT
	var normal := Vector2(-tangent.y, tangent.x)
	var envelope := lerpf(clampf(start_width_ratio, 0.0, 1.0), 1.0, pow(u, maxf(taper_power, 0.1))) if taper_enabled and not slot.closed else 1.0
	var lateral_motion := sin(phase * 0.73 + 1.2) * maxf(lateral_drift, 0.0) if drift_enabled else 0.0
	var noise_phase := u * TAU * noise_cycles + float(random_seed % 997) * 0.01
	var noise := normal_noise * (sin(noise_phase) + 0.35 * sin(noise_phase * 2.0 + 1.7)) / 1.35
	var lateral: float = (slot.side * maxf(half_width, 0.0) + lateral_motion + noise) * envelope
	return {"distance": distance, "center": frame.origin + normal * lateral, "tangent": tangent, "lateral": lateral, "phase": phase}

static func _finite(value: float) -> float:
	return value if is_finite(value) else 0.0

static func _is_closed(curve: Curve2D) -> bool:
	return curve != null and curve.point_count > 2 and curve.get_point_position(0).is_equal_approx(curve.get_point_position(curve.point_count - 1))

static func _curve_is_finite(curve: Curve2D) -> bool:
	for i in curve.point_count:
		if not curve.get_point_position(i).is_finite() or not curve.get_point_in(i).is_finite() or not curve.get_point_out(i).is_finite():
			return false
	return true

static func _rectangle_polygon() -> PackedVector2Array:
	return PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])

static func _circle_polygon(segments: int) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for i in segments:
		polygon.append(Vector2.from_angle(TAU * i / segments) * 0.5)
	return polygon

static func _local_polygon(shape: int, cut: float) -> PackedVector2Array:
	match shape:
		0:
			return PackedVector2Array([Vector2(-0.6, 0.16), Vector2(0.55, -0.5), Vector2(0.2, 0.12), Vector2(-0.2, 0.5)])
		1:
			return PackedVector2Array([Vector2(-0.55, 0.4), Vector2(0.55, -0.5), Vector2(0.1, 0.5)])
		_:
			return PackedVector2Array([Vector2(-0.55, 0.1), Vector2(-0.2, -0.5), Vector2(0.5 - cut, -0.38), Vector2(0.55, -0.1), Vector2(0.22, 0.5), Vector2(-0.4, 0.34)])

func _draw() -> void:
	for fragment in get_fragment_snapshot():
		var tint := color
		tint.a *= fragment["alpha"]
		if tint.a > 0.0 and Geometry2D.triangulate_polygon(fragment["vertices"]).size() > 0:
			if shape_style == 5:
				if fragment_texture != null:
					draw_polygon(fragment.vertices, PackedColorArray([tint]), PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]), fragment_texture)
			else:
				draw_colored_polygon(fragment["vertices"], tint)

func _connect_resources() -> void:
	_disconnect_resources()
	if not is_inside_tree():
		return
	_bound_definition = definition
	if _bound_definition == null:
		return
	_bound_definition.geometry_changed.connect(_resource_changed)

func _disconnect_resources() -> void:
	if is_instance_valid(_bound_definition) and _bound_definition.geometry_changed.is_connected(_resource_changed):
		_bound_definition.geometry_changed.disconnect(_resource_changed)
	for curve in _bound_curves:
		if is_instance_valid(curve) and curve.changed.is_connected(_request_rebuild):
			curve.changed.disconnect(_request_rebuild)
	_bound_curves.clear()
	_bound_definition = null

func _resource_changed() -> void:
	_connect_resources()
	_request_rebuild()

func _texture_changed() -> void:
	queue_redraw()
	if is_inside_tree():
		update_configuration_warnings()

func _all_paths_closed() -> bool:
	if close_paths:
		return true
	if definition == null or definition.get_curves().is_empty():
		return false
	for curve in definition.get_curves():
		if not _is_closed(curve):
			return false
	return true

## Inspector visibility follows the selected primitive and independent toggles.
## Serialized values remain available when a control is hidden.
func _validate_property(property: Dictionary) -> void:
	var property_name: String = property.name
	var hidden := false
	if property_name in ["fragment_texture", "texture_keep_aspect"]:
		hidden = shape_style != 5
	elif property_name == "circle_segments":
		hidden = shape_style != 3
	elif property_name in ["width_min", "width_max"]:
		hidden = shape_style == 3 or (shape_style == 5 and texture_keep_aspect)
	elif property_name in ["start_width_ratio", "taper_power", "start_scale"]:
		hidden = not taper_enabled or _all_paths_closed()
	elif property_name in ["drift_coherence", "drift_distance", "lateral_drift", "drift_frequency", "turn_amount", "foreshorten_amount"]:
		hidden = not drift_enabled
	elif property_name == "flow_speed":
		hidden = not flow_enabled
	elif property_name == "flow_edge_fade":
		hidden = not flow_enabled or _all_paths_closed()
	elif property_name == "noise_cycles":
		hidden = is_zero_approx(normal_noise)
	if hidden:
		property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR

func _get_configuration_warnings() -> PackedStringArray:
	if shape_style == 5 and fragment_texture == null:
		return PackedStringArray(["Assign a fragment texture. Texture fragments remain invisible without one."])
	if definition == null:
		return PackedStringArray(["Assign a PathDefinition containing at least one nonzero Curve2D."])
	if _slots.is_empty() and fragment_count > 0:
		return PackedStringArray(["No valid nonzero curves. Add at least two distinct curve points."])
	return PackedStringArray()
