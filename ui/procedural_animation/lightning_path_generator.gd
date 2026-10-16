@tool
class_name LightningPathGenerator
extends Resource
## Deterministic geometry authoring, independent of nodes, playback and rendering.
## generate() returns an editable PathDefinition with a trunk followed by branches.
## Each call creates its own Curve2D resources and preserves input and output snapshots.

const MAX_DETAIL := 8
const MAX_BRANCHES := 32
const MAX_DEPTH := 3
const COORDINATE_LIMIT := 1000000.0

@export var seed_value: int = 42
@export var start_point := Vector2(0, 0)
@export var end_point := Vector2(600, 0)
@export_range(1, 8, 1) var detail: int = 5
## Initial perpendicular displacement as a fraction of each bolt's length.
@export_range(0.0, 1.0, 0.01) var jaggedness: float = 0.12
## Displacement multiplier at each subdivision. Lower means smoother large shapes.
@export_range(0.0, 1.0, 0.01) var roughness: float = 0.55
@export_range(0, 32, 1) var branch_count: int = 8
@export_range(0.0, 1.0, 0.01) var branch_probability: float = 0.65
@export_range(0, 3, 1) var branch_depth: int = 2
## Branch length relative to remaining parent chord, with a short minimum reach.
@export_range(0.02, 0.8, 0.01) var branch_length: float = 0.32
@export_range(5.0, 85.0, 1.0, "degrees") var branch_angle: float = 45.0

func generate() -> PathDefinition:
	return generate_with_metadata().definition

## Metadata describes parent relationships for authoring and diagnostics.
## Parents always precede children; attachment_indices index the parent's vertices.
func generate_with_metadata() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var definition := PathDefinition.new()
	var curves: Array[Curve2D] = []
	var parents := PackedInt32Array([-1])
	var attachments := PackedInt32Array([-1])
	var depths := PackedInt32Array([0])
	var a := _safe_point(start_point)
	var b := _safe_point(end_point)
	var subdivisions := clampi(detail, 1, MAX_DETAIL)
	var displacement := _finite_clamp(jaggedness, 0.0, 1.0, 0.12)
	var decay := _finite_clamp(roughness, 0.0, 1.0, 0.55)
	curves.append(_bolt(a, b, subdivisions, displacement, decay, rng))
	var limit := clampi(branch_count, 0, MAX_BRANCHES)
	var depth_limit := clampi(branch_depth, 0, MAX_DEPTH)
	var chance := _finite_clamp(branch_probability, 0.0, 1.0, 0.65)
	var length_ratio := _finite_clamp(branch_length, 0.02, 0.8, 0.32)
	var angle := deg_to_rad(_finite_clamp(branch_angle, 5.0, 85.0, 45.0))
	var parent_index := 0
	while parent_index < curves.size() and curves.size() <= limit:
		var parent := curves[parent_index]
		var depth := depths[parent_index]
		var chord := parent.get_point_position(parent.point_count - 1) - parent.get_point_position(0)
		var chord_length := chord.length()
		if depth < depth_limit and chord_length > 0.001 and chance > 0.0:
			# Five distributed attachment candidates, rotated deterministically for variety.
			# The fixed candidate budget bounds work independently of point count.
			var first := rng.randi_range(0, 4)
			for candidate in 5:
				if curves.size() > limit: break
				var slot := (first + candidate) % 5
				var fraction := (float(slot) + rng.randf_range(0.4, 0.8)) / 6.0
				var index := clampi(roundi(fraction * (parent.point_count - 1)), 1, parent.point_count - 2)
				if rng.randf() >= chance: continue
				var origin := parent.get_point_position(index)
				var side := -1.0 if rng.randf() < 0.5 else 1.0
				var direction := chord.normalized().rotated(side * angle * rng.randf_range(0.7, 1.2))
				var reach := chord_length * maxf(0.15, 1.0 - fraction) * length_ratio * rng.randf_range(0.75, 1.25)
				var tip := _safe_point(origin + direction * reach)
				if origin.distance_squared_to(tip) <= 0.000001: continue
				curves.append(_bolt(origin, tip, maxi(1, subdivisions - depth - 1), displacement, decay, rng))
				parents.append(parent_index)
				attachments.append(index)
				depths.append(depth + 1)
		parent_index += 1
	definition.set_curves(curves)
	return {"definition": definition, "parents": parents, "attachment_indices": attachments, "depths": depths}

func _bolt(a: Vector2, b: Vector2, subdivisions: int, displacement: float, decay: float, rng: RandomNumberGenerator) -> Curve2D:
	var curve := Curve2D.new()
	# Bake spacing bounds sample density across large authoring coordinates.
	curve.bake_interval = maxf(1.0, a.distance_to(b) / 512.0)
	if a.distance_squared_to(b) <= 0.000001:
		curve.add_point(a)
		curve.add_point(b)
		return curve
	var normal := (b - a).normalized().orthogonal()
	var points := PackedVector2Array([a, b])
	var amplitude := a.distance_to(b) * displacement
	for _level in subdivisions:
		var refined := PackedVector2Array()
		for i in points.size() - 1:
			refined.append(points[i])
			refined.append(_safe_point((points[i] + points[i + 1]) * 0.5 + normal * rng.randf_range(-amplitude, amplitude)))
		refined.append(b)
		points = refined
		amplitude *= decay
	for point in points:
		curve.add_point(point)
	return curve

static func _finite_clamp(value: float, lower: float, upper: float, fallback: float) -> float:
	return clampf(value, lower, upper) if is_finite(value) else fallback

static func _safe_point(point: Vector2) -> Vector2:
	return Vector2(_finite_clamp(point.x, -COORDINATE_LIMIT, COORDINATE_LIMIT, 0.0), _finite_clamp(point.y, -COORDINATE_LIMIT, COORDINATE_LIMIT, 0.0))
