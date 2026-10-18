class_name WindField2D
extends Node2D
## Independent, deterministic wind velocity in canvas-global pixels per second.
## Clients query positions and velocity vectors in their shared canvas.
## For other CanvasLayers/Viewports, explicitly convert positions AND velocity vectors.
## The field owns its ambient clock and bounded local velocity sources.

const MAX_DELTA := 0.25
const MAX_COORDINATE := 10000000.0
const MAX_SPEED := 10000.0
const SOURCE_EPSILON := 0.05

@export var enabled := true:
	set(value):
		enabled = value
		if not value:
			clear_sources()
		set_process(enabled and automatic_update)
## Set false when the owner drives advance(delta) with its own clock.
@export var automatic_update := true:
	set(value):
		automatic_update = value
		set_process(enabled and automatic_update)
@export_group("Ambient wind")
@export var ambient_direction := Vector2.RIGHT:
	set(value):
		ambient_direction = _limited_vector(value, 1.0).normalized() if value.is_finite() else Vector2.ZERO
@export_range(0.0, 1000.0, 1.0, "or_greater") var ambient_strength := 55.0:
	set(value): ambient_strength = _bounded(value, 0.0, MAX_SPEED)
@export_range(0.0, 1000.0, 1.0, "or_greater") var gust_strength := 24.0:
	set(value): gust_strength = _bounded(value, 0.0, MAX_SPEED)
## Cycles per second; zero freezes the ambient gust pattern.
@export_range(0.0, 10.0, 0.01) var gust_frequency := 0.35:
	set(value): gust_frequency = _bounded(value, 0.0, 10.0)
## Radians per canvas pixel; zero makes ambient gusts spatially uniform.
@export_range(0.0, 0.1, 0.0001) var spatial_frequency := 0.008:
	set(value): spatial_frequency = _bounded(value, 0.0, 1.0)
@export_group("Limits")
@export_range(0.0, 10000.0, 1.0) var max_wind_speed := 1200.0:
	set(value): max_wind_speed = _bounded(value, 0.0, MAX_SPEED)
@export_range(1, 128, 1) var max_sources := 32:
	set(value):
		max_sources = clampi(value, 1, 128)
		while _sources.size() > max_sources:
			_sources.erase(_sources.keys()[0])
## Unrefreshed sources are removed even with a very slow exponential decay.
@export_range(0.01, 30.0, 0.01) var source_lifetime := 2.0:
	set(value): source_lifetime = _bounded(value, 0.01, 30.0)

class LocalSource:
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var radius := 180.0
	var decay_rate := 8.0
	var age := 0.0
	static func create(center: Vector2, wind: Vector2) -> LocalSource:
		var source := LocalSource.new()
		source.position = center
		source.velocity = wind
		return source
	func with_falloff(reach: float, decay: float) -> LocalSource:
		radius = reach
		decay_rate = decay
		return self

var _sources: Dictionary = {}
var _phase := 0.0
var _secondary_phase := 1.4

func _ready() -> void:
	set_process(enabled and automatic_update)

func _exit_tree() -> void:
	clear_sources()

func _process(delta: float) -> void:
	advance(delta)

## Positive finite simulation steps advance by up to 250 ms.
func advance(delta: float) -> void:
	if not enabled or not is_finite(delta) or delta <= 0.0:
		return
	var dt := minf(delta, MAX_DELTA)
	_phase = fposmod(_phase + TAU * gust_frequency * dt, TAU)
	_secondary_phase = fposmod(_secondary_phase + TAU * gust_frequency * 0.73 * dt, TAU)
	for id in _sources.keys():
		var source: LocalSource = _sources[id]
		source.age += dt
		source.velocity *= exp(-source.decay_rate * dt)
		if source.age >= source_lifetime or source.velocity.length_squared() < SOURCE_EPSILON * SOURCE_EPSILON:
			_sources.erase(id)

## Upsert a local velocity source. A positive id is typically a Node instance id.
## Caller owns its id; updating refreshes age. At capacity, new ids are rejected,
## while existing ids can still update. Zero velocity/radius removes that id.
## Local influence applies its velocity with smoothstep radial falloff.
func set_source(id: int, input: LocalSource) -> bool:
	var canvas_position := input.position
	var wind_velocity := input.velocity
	var radius := input.radius
	var decay_rate := input.decay_rate
	if not enabled or not _valid_position(canvas_position) or not wind_velocity.is_finite() or not is_finite(radius) or not is_finite(decay_rate):
		return false
	var velocity := _limited_vector(wind_velocity, MAX_SPEED)
	if radius <= 0.0 or velocity.length_squared() < SOURCE_EPSILON * SOURCE_EPSILON:
		remove_source(id)
		return true
	if not _sources.has(id) and _sources.size() >= max_sources:
		return false
	var source: LocalSource = _sources[id] if _sources.has(id) else LocalSource.new()
	source.position = canvas_position
	source.velocity = velocity
	source.radius = clampf(radius, 0.001, 100000.0)
	source.decay_rate = clampf(decay_rate, 0.01, 60.0)
	source.age = 0.0
	_sources[id] = source
	return true

func remove_source(id: int) -> void:
	_sources.erase(id)

func clear_sources() -> void:
	_sources.clear()

func get_source_count() -> int:
	return _sources.size()

## Pure query over the current ambient phase and local-source snapshot.
func sample_wind(canvas_position: Vector2) -> Vector2:
	if not enabled or not _valid_position(canvas_position):
		return Vector2.ZERO
	var coordinate := (canvas_position.x + canvas_position.y * 0.37) * spatial_frequency
	var gust := sin(_phase + coordinate) * 0.65 + sin(_secondary_phase + coordinate * 0.67) * 0.35
	var cross_gust := sin(_secondary_phase + coordinate * 0.43) * gust_strength * 0.18
	var wind := ambient_direction * (ambient_strength + gust_strength * gust)
	wind += ambient_direction.orthogonal() * cross_gust
	# Read source entries directly during this query.
	for id in _sources:
		var source: LocalSource = _sources[id]
		var distance := canvas_position.distance_to(source.position)
		if distance >= source.radius:
			continue
		var t := 1.0 - distance / source.radius
		var falloff := t * t * (3.0 - 2.0 * t)
		wind += source.velocity * falloff
	return _limited_vector(wind, max_wind_speed)

static func _bounded(value: float, minimum: float, maximum: float) -> float:
	return clampf(value, minimum, maximum) if is_finite(value) else minimum

static func _valid_position(value: Vector2) -> bool:
	return value.is_finite() and absf(value.x) <= MAX_COORDINATE and absf(value.y) <= MAX_COORDINATE

## Scale before taking length to keep finite input magnitudes bounded.
static func _limited_vector(value: Vector2, maximum: float) -> Vector2:
	if not value.is_finite() or maximum <= 0.0:
		return Vector2.ZERO
	var largest := maxf(absf(value.x), absf(value.y))
	if largest > maximum:
		value *= maximum / largest
	return value.limit_length(maximum)
