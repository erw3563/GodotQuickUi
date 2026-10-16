class_name PixelImpactBurst2D
extends Node2D
## The authored Particles child owns native fragment size, motion, color and lifetime.
## This wrapper triggers and clocks the native burst and its immediate flash.
signal finished

@export var flash_color := Color("fff4d1")
@export_range(0.0, 24.0, 0.5) var flash_radius := 4.0
@export_range(0.01, 0.2, 0.005) var flash_duration := 0.045
@export var auto_free := false

const MAX_PARTICLES := 128
const MAX_LIFETIME := 4.0
var active := false
var _age := 0.0
var _direction := Vector2.RIGHT
var _generation := 0
var _particles_done := true
var _resetting := false
var _stepping := false
var _paused := false
@onready var particles: CPUParticles2D = $Particles

func _ready() -> void:
	# advance() owns native processing requests through the disabled child process mode.
	particles.process_mode = Node.PROCESS_MODE_DISABLED
	particles.finished.connect(_on_particles_finished)
	particles.emitting = false
	set_as_top_level(true)
	set_process(false)

func play(world_position: Vector2, incoming_direction: Vector2, seed_value: int = -1) -> void:
	reset()
	if not is_inside_tree() or not is_visible_in_tree() or not world_position.is_finite() or not incoming_direction.is_finite():
		return
	_direction = incoming_direction.normalized() if incoming_direction.length_squared() > 0.000001 else Vector2.RIGHT
	# Preserve native direction as an authoring parameter relative to incoming.
	# top_level and unit global basis prevent parent scale from resizing fragments.
	global_transform = Transform2D(_direction.angle(), world_position)
	particles.one_shot = true
	particles.local_coords = false
	particles.amount = clampi(particles.amount, 1, MAX_PARTICLES)
	particles.lifetime = clampf(particles.lifetime, 0.02, MAX_LIFETIME)
	particles.preprocess = clampf(particles.preprocess, 0.0, particles.lifetime)
	if seed_value >= 0:
		particles.use_fixed_seed = true
		particles.seed = seed_value
	particles.show()
	active = true
	_particles_done = false
	# Zero-speed restart isolates initialization from wall-clock frame time.
	var authored_speed := particles.speed_scale
	particles.speed_scale = 0.0
	particles.restart(particles.use_fixed_seed)
	# Explicit advance owns first emission, including native DRAW initialization.
	particles.emitting = false
	particles.speed_scale = authored_speed
	set_process(true)
	queue_redraw()

func reset() -> void:
	_generation += 1
	active = false
	_age = 0.0
	_particles_done = true
	_paused = false
	set_process(false)
	var emitter := get_node_or_null("Particles") as CPUParticles2D
	if is_instance_valid(emitter):
		_resetting = true
		var authored_speed := emitter.speed_scale
		var authored_preprocess := emitter.preprocess
		emitter.speed_scale = 0.0
		emitter.preprocess = 0.0
		# Zero-time native restart clears particle storage before stopping emission.
		emitter.restart(true)
		emitter.emitting = false
		emitter.speed_scale = authored_speed
		emitter.preprocess = authored_preprocess
		emitter.hide()
		_resetting = false
	queue_redraw()

func set_paused(value: bool) -> void:
	_paused = value
	set_process(active and not value)

func advance(delta: float) -> void:
	if not active or _paused or not is_finite(delta) or delta <= 0.0:
		return
	var step := minf(delta, MAX_LIFETIME * 3.0)
	_age += step
	if not _particles_done:
		var authored_speed := particles.speed_scale
		_stepping = true
		# Zero-speed requests isolate each explicit native step from frame processing.
		# Inspector Speed Scale supplies the authored multiplier for the requested step.
		particles.speed_scale = 0.0
		particles.request_particles_process(minf(step * maxf(0.0, authored_speed), particles.lifetime * 2.0 + 0.1))
		if not is_instance_valid(self):
			return
		particles.speed_scale = authored_speed
		if _particles_done:
			particles.emitting = false
		_stepping = false
	_complete_if_done()
	if is_instance_valid(self):
		queue_redraw()

func _process(delta: float) -> void:
	advance(delta)

func _on_particles_finished() -> void:
	if _resetting or not active:
		return
	_particles_done = true
	particles.emitting = false
	if not _stepping:
		_complete_if_done()

func _complete_if_done() -> void:
	if not active or not _particles_done or _age < clampf(flash_duration, 0.01, 0.2):
		return
	active = false
	set_process(false)
	particles.emitting = false
	particles.hide()
	var generation := _generation
	finished.emit()
	if not is_instance_valid(self):
		return
	if auto_free and generation == _generation and not active and is_inside_tree():
		queue_free()

func get_active_count() -> int:
	# Report a conservative capacity upper bound until native completion.
	return particles.amount if active and not _particles_done else 0

func _draw() -> void:
	if not active:
		return
	var progress := clampf(_age / clampf(flash_duration, 0.01, 0.2), 0.0, 1.0)
	var radius := clampf(flash_radius, 0.0, 24.0) * (1.0 - progress)
	if radius < 0.15:
		return
	# Local +X is incoming direction. Flash is flattened against that axis.
	draw_colored_polygon(PackedVector2Array([Vector2(0,radius),Vector2(radius*0.45,0),Vector2(0,-radius),Vector2(-radius*0.45,0)]),flash_color)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree() and not is_visible_in_tree():
		reset()
	elif what == NOTIFICATION_EXIT_TREE:
		reset()
