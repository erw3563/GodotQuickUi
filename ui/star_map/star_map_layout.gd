@tool
class_name StarMapLayout
extends Resource
## Bounded world-space spring and repulsion layout with exact drag pins.
## configure() copies inputs; step() sanitizes public arrays and advances dynamics.
## Coordinates are bounded to +/-1e6, speed to 1200, nodes to 128 and links to 512.
## Each frame integrates at most 1/15 s with substeps up to 1/60 s.
## constraint_error() exposes residuals for dense, contradictory and pinned graphs.
## Assign pinned[index] while dragging and erase it on release.

const MAX_NODES := 128
const MAX_LINKS := 512
const COORDINATE_LIMIT := 1000000.0
const MAX_SPEED := 1200.0
const MAX_DELTA := 1.0 / 15.0
const MAX_SUBSTEP := 1.0 / 60.0
const DISTANCE_EPSILON := 0.0001
const CONSTRAINT_TOLERANCE := 0.025

@export_range(0.0, 2000.0, 1.0) var min_spacing: float = 100.0
@export_range(0.0, 4000.0, 1.0) var max_link_distance: float = 230.0
@export_range(0.0, 4000.0, 1.0) var rest_length: float = 165.0
## Exponential damping rate in inverse seconds.
@export_range(0.0, 60.0, 0.1) var damping: float = 8.0
@export_range(0.0, 100.0, 0.1) var spring_strength: float = 24.0
@export_range(0.0, 100.0, 0.1) var repulsion_strength: float = 18.0
@export_range(1, 64, 1) var constraint_iterations: int = 64
@export var sleep_enabled: bool = true

var positions: Array[Vector2] = []
var velocities: Array[Vector2] = []
var links: Array[Vector2i] = []
var pinned: Dictionary = {}
## True after 0.5 s below motion thresholds; direct data/settings edits wake it.
var settled: bool = false
var _quiet_time := 0.0
var _last_signature := 0
var _forces: Array[Vector2] = []
var _pin_mask := PackedByteArray()

func configure(initial_positions: Array[Vector2], edges: Array[Vector2i]) -> void:
	positions = initial_positions.duplicate()
	links = edges.duplicate()
	velocities = []
	pinned = {}
	settled = false
	_quiet_time = 0.0
	_sanitize_state()
	_last_signature = _state_signature()

func step(delta: float) -> void:
	_sanitize_state()
	_apply_pins()
	var signature := _state_signature()
	if signature != _last_signature:
		settled = false
		_quiet_time = 0.0
	_last_signature = signature
	if settled and sleep_enabled:
		return
	if positions.is_empty() or not is_finite(delta) or delta <= 0.0:
		return
	var previous_positions: Array[Vector2] = positions.duplicate()
	var elapsed := minf(delta, MAX_DELTA)
	var substeps := clampi(ceili(elapsed / MAX_SUBSTEP), 1, 4)
	var h := elapsed / float(substeps)
	var spacing := _setting(min_spacing, 0.0, 2000.0, 100.0)
	var maximum := _setting(max_link_distance, 0.0, 4000.0, 230.0)
	var rest := _setting(rest_length, 0.0, 4000.0, 165.0)
	if maximum >= spacing:
		rest = clampf(rest, spacing, maximum)
	var spring := _setting(spring_strength, 0.0, 100.0, 24.0)
	var repulsion := _setting(repulsion_strength, 0.0, 100.0, 18.0)
	var drag := _setting(damping, 0.0, 60.0, 8.0)
	for _substep in substeps:
		_accumulate_forces(rest, spacing, spring, repulsion)
		var attenuation := exp(-drag * h)
		for index in positions.size():
			if _pin_mask[index]:
				continue
			velocities[index] = (velocities[index] + _forces[index] * h).limit_length(MAX_SPEED) * attenuation
			positions[index] = _safe_point(positions[index] + velocities[index] * h)
		_project_constraints(spacing, maximum)
		for index in positions.size():
			velocities[index] = velocities[index].limit_length(MAX_SPEED)
		_apply_pins()
	var quiet := true
	for index in positions.size():
		if velocities[index].length_squared() > 0.09 or positions[index].distance_squared_to(previous_positions[index]) > 0.000625:
			quiet = false
			break
	_quiet_time = _quiet_time + elapsed if quiet else 0.0
	settled = sleep_enabled and _quiet_time >= 0.5
	if settled:
		velocities.fill(Vector2.ZERO)
	_last_signature = _state_signature()

## Reports current world-unit residuals and direct fixed-pair conflicts.
## Chain conflicts contribute to the observed spacing and link-distance residuals.
func constraint_error() -> Dictionary:
	var finite := positions.size() <= MAX_NODES and velocities.size() == positions.size()
	var minimum_error := 0.0
	var maximum_error := 0.0
	var pin_error := 0.0
	var pin_conflicts := 0
	var max_speed := 0.0
	var spacing := _setting(min_spacing, 0.0, 2000.0, 100.0)
	var maximum := _setting(max_link_distance, 0.0, 4000.0, 230.0)
	var count := mini(positions.size(), MAX_NODES)
	for index in count:
		finite = finite and positions[index].is_finite()
		if index < velocities.size():
			finite = finite and velocities[index].is_finite()
			max_speed = maxf(max_speed, _safe_point(velocities[index]).length())
		if _valid_pin(index):
			pin_error = maxf(pin_error, _safe_point(positions[index]).distance_to(_safe_point(pinned[index])))
		for other in range(index + 1, count):
			var distance := _safe_point(positions[index]).distance_to(_safe_point(positions[other]))
			var violation := maxf(0.0, spacing - distance)
			minimum_error = maxf(minimum_error, violation)
			if violation > CONSTRAINT_TOLERANCE and _valid_pin(index) and _valid_pin(other):
				pin_conflicts += 1
	var valid_link_count := 0
	for edge in links:
		if edge.x < 0 or edge.y < 0 or edge.x >= count or edge.y >= count or edge.x == edge.y:
			continue
		valid_link_count += 1
		var distance := _safe_point(positions[edge.x]).distance_to(_safe_point(positions[edge.y]))
		var violation := maxf(0.0, distance - maximum)
		maximum_error = maxf(maximum_error, violation)
		if violation > CONSTRAINT_TOLERANCE and _valid_pin(edge.x) and _valid_pin(edge.y):
			pin_conflicts += 1
	var settings_conflict := valid_link_count > 0 and spacing > maximum
	return {
		"min_spacing_error": minimum_error,
		"max_link_error": maximum_error,
		"pin_error": pin_error,
		"pinned_conflicts": pin_conflicts,
		"settings_conflict": settings_conflict,
		"finite": finite,
		"max_speed": max_speed,
		"converged": finite and not settings_conflict and maxf(maxf(minimum_error, maximum_error), pin_error) <= CONSTRAINT_TOLERANCE,
	}

func _accumulate_forces(rest: float, spacing: float, spring: float, repulsion: float) -> void:
	_forces.fill(Vector2.ZERO)
	for edge in links:
		var offset := positions[edge.y] - positions[edge.x]
		var distance := offset.length()
		var direction := _pair_direction(edge.x, edge.y, offset, distance)
		# A bounded force even for inputs at opposite coordinate limits.
		var force := direction * clampf((distance - rest) * spring, -10000.0, 10000.0)
		_forces[edge.x] += force
		_forces[edge.y] -= force
	var reach := spacing * 1.5
	if reach <= 0.0 or repulsion <= 0.0:
		return
	var reach_squared := reach * reach
	for index in positions.size():
		for other in range(index + 1, positions.size()):
			var offset := positions[other] - positions[index]
			if offset.length_squared() >= reach_squared:
				continue
			var distance := offset.length()
			var force := _pair_direction(index, other, offset, distance) * (reach - distance) * repulsion
			_forces[index] -= force
			_forces[other] += force

func _project_constraints(spacing: float, maximum: float) -> void:
	var spacing_squared := spacing * spacing
	var maximum_squared := maximum * maximum
	for _iteration in clampi(constraint_iterations, 1, 64):
		var largest_correction := 0.0
		# Project long links, then all-pairs spacing, with fixed pin weights.
		for edge in links:
			var offset := positions[edge.y] - positions[edge.x]
			if offset.length_squared() <= maximum_squared:
				continue
			largest_correction = maxf(largest_correction, _project_pair(edge.x, edge.y, maximum, false))
		for index in positions.size():
			for other in range(index + 1, positions.size()):
				var offset := positions[other] - positions[index]
				if offset.length_squared() >= spacing_squared:
					continue
				largest_correction = maxf(largest_correction, _project_pair(index, other, spacing, true))
		if largest_correction <= CONSTRAINT_TOLERANCE * 0.25:
			break

func _project_pair(a: int, b: int, target: float, minimum: bool) -> float:
	var offset := positions[b] - positions[a]
	var distance := offset.length()
	var weight_a := 0.0 if _pin_mask[a] else 1.0
	var weight_b := 0.0 if _pin_mask[b] else 1.0
	var total := weight_a + weight_b
	if total == 0.0:
		return 0.0
	var normal := _pair_direction(a, b, offset, distance)
	var error := distance - target
	var correction := normal * (error / total)
	positions[a] = _safe_point(positions[a] + correction * weight_a)
	positions[b] = _safe_point(positions[b] - correction * weight_b)
	# Remove velocity directed farther into the active constraint.
	var separating_speed := (velocities[b] - velocities[a]).dot(normal)
	if (minimum and separating_speed < 0.0) or (not minimum and separating_speed > 0.0):
		var impulse := normal * (separating_speed / total)
		velocities[a] += impulse * weight_a
		velocities[b] -= impulse * weight_b
	return absf(error)

func _sanitize_state() -> void:
	if positions.size() > MAX_NODES:
		positions.resize(MAX_NODES)
	var old_velocity_count := velocities.size()
	velocities.resize(positions.size())
	_forces.resize(positions.size())
	_pin_mask.resize(positions.size())
	_pin_mask.fill(0)
	for index in positions.size():
		positions[index] = _safe_point(positions[index])
		velocities[index] = _safe_point(velocities[index]).limit_length(MAX_SPEED) if index < old_velocity_count else Vector2.ZERO
	var clean_links: Array[Vector2i] = []
	var seen := {}
	for edge in links:
		if edge.x < 0 or edge.y < 0 or edge.x >= positions.size() or edge.y >= positions.size() or edge.x == edge.y:
			continue
		var canonical := Vector2i(mini(edge.x, edge.y), maxi(edge.x, edge.y))
		if seen.has(canonical):
			continue
		seen[canonical] = true
		clean_links.append(canonical)
		if clean_links.size() >= MAX_LINKS:
			break
	links = clean_links
	var clean_pins := {}
	for key in pinned:
		if typeof(key) != TYPE_INT or key < 0 or key >= positions.size() or typeof(pinned[key]) != TYPE_VECTOR2:
			continue
		var point: Vector2 = pinned[key]
		if not point.is_finite():
			continue
		clean_pins[key] = _safe_point(point)
		_pin_mask[key] = 1
	pinned = clean_pins

func _apply_pins() -> void:
	for index in pinned:
		positions[index] = pinned[index]
		velocities[index] = Vector2.ZERO

func _valid_pin(index: int) -> bool:
	return pinned.has(index) and typeof(pinned[index]) == TYPE_VECTOR2 and (pinned[index] as Vector2).is_finite()

func _pair_direction(a: int, b: int, offset: Vector2, distance: float) -> Vector2:
	if distance > DISTANCE_EPSILON:
		return offset / distance
	# Deterministic pair-derived direction separates coincident points.
	var angle := fposmod(float((a + 1) * 92821 + (b + 1) * 68917) * 2.399963229728653, TAU)
	return Vector2(cos(angle), sin(angle))

func _safe_point(point: Vector2) -> Vector2:
	return Vector2(clampf(point.x, -COORDINATE_LIMIT, COORDINATE_LIMIT) if is_finite(point.x) else 0.0, clampf(point.y, -COORDINATE_LIMIT, COORDINATE_LIMIT) if is_finite(point.y) else 0.0)

func _setting(value: float, minimum: float, maximum: float, fallback: float) -> float:
	return clampf(value, minimum, maximum) if is_finite(value) else fallback

func _state_signature() -> int:
	return hash([positions, velocities, links, pinned, min_spacing, max_link_distance, rest_length, damping, spring_strength, repulsion_strength, constraint_iterations, sleep_enabled])
