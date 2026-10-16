class_name PathWaveModifier
extends PathModifier
## One reusable oscillation: sin(TAU * (spatial_cycles * arc_fraction - phase)).
## Positive frequency travels root to tip. Wavelength = path_length/spatial_cycles;
## propagation speed = frequency_hz * wavelength.
@export_range(0.0, 128.0, 0.1) var amplitude := 3.0:
	set(value): amplitude = clampf(value, 0.0, 4096.0) if is_finite(value) else 0.0
@export_range(0.0, 8.0, 0.01) var frequency_hz := 0.45:
	set(value): frequency_hz = clampf(value, 0.0, 20.0) if is_finite(value) else 0.0
@export_range(0.0, 4.0, 0.01) var spatial_cycles := 0.25:
	set(value): spatial_cycles = clampf(value, 0.0, 16.0) if is_finite(value) else 0.0
@export_range(1.0, 4.0, 0.05) var envelope_power := 1.5:
	set(value): envelope_power = clampf(value, 1.0, 8.0) if is_finite(value) else 1.5
@export var phase_seed := 1
var phase_cycles := 0.0
func reset_state() -> void:
	active = false
	phase_cycles = 0.0
func apply(paths: Array, _coordinator: Node2D, delta: float) -> void:
	phase_cycles = fposmod(phase_cycles + delta * frequency_hz, 1.0)
	active = false
	for p in paths.size():
		var path: PathDeform2D.PathState = paths[p]
		active = active or (amplitude > 0.0 and frequency_hz > 0.0 and path.rest.size() > 1)
		var seed_phase := fposmod(float(posmod(phase_seed, 100003)) * 0.61803398875 + float(p) * 0.38196601125, 1.0)
		for i in range(1, path.rest.size()):
			var u: float = path.progress[i]
			var displacement := amplitude * pow(u, envelope_power) * sin(TAU * (spatial_cycles * u - phase_cycles + seed_phase))
			path.offsets[i] += path.normals[i] * displacement
