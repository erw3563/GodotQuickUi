@tool
class_name LiquidCellFusion
extends Control
## Bounded, pairwise polynomial soft-union of at most eight fixed circles.
## Centers are normalized to size; radii use the shorter side, so circles stay
## round on non-square controls. Callers drive the input parameters.

const MAX_CELLS := 8
const FIELD_SHADER = preload("res://addons/gdbase/ui/liquid_cell_fusion/liquid_cell_fusion.gdshader")

@export_group("Cells")
@export var cell_centers := PackedVector2Array([Vector2(0.37, 0.5), Vector2(0.625, 0.5)]):
	set(value):
		cell_centers = value.duplicate()
		queue_redraw()
@export var cell_radii := PackedFloat32Array([0.28, 0.105]):
	set(value):
		cell_radii = value.duplicate()
		queue_redraw()
@export_group("Connection")
@export_range(0.0, 1.0, 0.001) var join_strength := 0.0:
	set(value):
		if is_finite(value):
			join_strength = clampf(value, 0.0, 1.0)
			queue_redraw()
@export_range(0.0, 1024.0, 0.5, "or_greater") var connection_range := 260.0:
	set(value):
		if is_finite(value):
			connection_range = clampf(value, 0.0, 4096.0)
			queue_redraw()
@export_range(0.0, 256.0, 0.25) var neck_radius := 0.0:
	set(value):
		if is_finite(value):
			neck_radius = clampf(value, 0.0, 256.0)
			queue_redraw()
@export_range(0.0, 256.0, 0.25) var surface_softness := 0.0:
	set(value):
		if is_finite(value):
			surface_softness = clampf(value, 0.0, 256.0)
			queue_redraw()
@export_group("Paint")
@export var fill_color := Color("12c8d0"):
	set(value):
		if _finite_color(value):
			fill_color = value
			queue_redraw()
@export var outline_color := Color("fff0ce"):
	set(value):
		if _finite_color(value):
			outline_color = value
			queue_redraw()
@export_range(0.0, 32.0, 0.25) var outline_width := 0.0:
	set(value):
		if is_finite(value):
			outline_width = clampf(value, 0.0, 32.0)
			queue_redraw()
@export_range(0.0, 1.0, 0.01) var opacity := 1.0:
	set(value):
		if is_finite(value):
			opacity = clampf(value, 0.0, 1.0)
			queue_redraw()

var _own_material: ShaderMaterial

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _enter_tree() -> void:
	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)
	_ensure_material()
	queue_redraw()

func _ensure_material() -> void:
	if _own_material == null:
		_own_material = ShaderMaterial.new()
		_own_material.shader = FIELD_SHADER
		_own_material.resource_local_to_scene = true
	material = _own_material

static func _finite_color(value: Color) -> bool:
	return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)

func field_snapshot() -> Dictionary:
	## Public, detached data for geometry consumers and deterministic testing.
	var centers := PackedVector2Array()
	var radii := PackedFloat32Array()
	if not size.is_finite() or size.x <= 0.0 or size.y <= 0.0:
		return {"centers": centers, "radii": radii}
	var unit := minf(size.x, size.y)
	for index in mini(MAX_CELLS, mini(cell_centers.size(), cell_radii.size())):
		var center := cell_centers[index]
		var radius: float = cell_radii[index]
		if not center.is_finite() or not is_finite(radius) or radius <= 0.0:
			continue
		# Filter extreme coordinates to keep GPU inputs finite.
		if absf(center.x) > 10000.0 or absf(center.y) > 10000.0:
			continue
		centers.append(center * size)
		radii.append(minf(radius, 4.0) * unit)
	return {"centers": centers, "radii": radii}

func pair_smoothing(center_a: Vector2, radius_a: float, center_b: Vector2, radius_b: float) -> float:
	var gap := maxf(0.0, center_a.distance_to(center_b) - radius_a - radius_b)
	if gap > connection_range:
		return 0.0
	# At strength=1 and neck=softness=0 the two surfaces first touch.
	# Increased neck/softness thickens the join while preserving cell centers.
	return join_strength * (2.0 * gap + 4.0 * neck_radius) + surface_softness

static func soft_union(a: float, b: float, smoothing: float) -> float:
	if smoothing <= 0.00001:
		return minf(a, b)
	var h := maxf(smoothing - absf(a - b), 0.0) / smoothing
	return minf(a, b) - h * h * smoothing * 0.25

func sample_distance(point: Vector2) -> float:
	## Visual field value; it may be negative outside local bounds.
	if not point.is_finite():
		return INF
	var data := field_snapshot()
	var distances := PackedFloat32Array()
	var result := INF
	for index in data.centers.size():
		var distance: float = point.distance_to(data.centers[index]) - data.radii[index]
		distances.append(distance)
		result = minf(result, distance)
	for a in data.centers.size():
		for b in range(a + 1, data.centers.size()):
			var k := pair_smoothing(data.centers[a], data.radii[a], data.centers[b], data.radii[b])
			result = minf(result, soft_union(distances[a], distances[b], k))
	return result

func geometry_bounds() -> Rect2:
	var data := field_snapshot()
	if data.centers.is_empty() or opacity <= 0.0:
		return Rect2()
	var bounds := Rect2()
	var padding := outline_width * 0.5 + 2.0
	for a in data.centers.size():
		var radius: float = data.radii[a]
		for b in range(a + 1, data.centers.size()):
			var k := pair_smoothing(data.centers[a], radius, data.centers[b], data.radii[b])
			padding = maxf(padding, k * 0.25 + outline_width * 0.5 + 2.0)
	# Polynomial soft-union subtracts at most k/4 from min(circle distances).
	# Thus this padded union bound is conservative and the quad stays clipped.
	for a in data.centers.size():
		var radius: float = data.radii[a] + padding
		var clipped := Rect2(data.centers[a] - Vector2.ONE * radius, Vector2.ONE * radius * 2.0).intersection(Rect2(Vector2.ZERO, size))
		if clipped.has_area():
			bounds = bounds.merge(clipped) if bounds.has_area() else clipped
	return bounds

func _draw() -> void:
	var bounds := geometry_bounds()
	if not bounds.has_area():
		return
	_ensure_material()
	var data := field_snapshot()
	var centers: PackedVector2Array = data.centers
	var radii: PackedFloat32Array = data.radii
	var count := centers.size()
	centers.resize(MAX_CELLS)
	radii.resize(MAX_CELLS)
	_own_material.set_shader_parameter("cell_count", count)
	_own_material.set_shader_parameter("centers", centers)
	_own_material.set_shader_parameter("radii", radii)
	_own_material.set_shader_parameter("join_strength", join_strength)
	_own_material.set_shader_parameter("connection_range", connection_range)
	_own_material.set_shader_parameter("neck_radius", neck_radius)
	_own_material.set_shader_parameter("surface_softness", surface_softness)
	_own_material.set_shader_parameter("fill_color", fill_color)
	_own_material.set_shader_parameter("outline_color", outline_color)
	_own_material.set_shader_parameter("outline_width", outline_width)
	_own_material.set_shader_parameter("opacity", opacity)
	draw_rect(bounds, Color.WHITE)
