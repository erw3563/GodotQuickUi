@tool
## 路径横向条带图案播撒：沿 PathDefinition 各条曲线，在法线方向 ±half_width 的走廊内按固定种子播撒 Texture2D，
## 并用 GPUParticles2D（POINTS / DIRECTED_POINTS）做淡出与沿切线漂移。
## 几何由 PathPatternScatterBuilder 计算；本节点持有参数、监听路径变更并管理生成的粒子子节点。
## 名下直接子节点由组件生成并拥有，参数变化时按配置重建。
## 生成子节点的 owner 为空；加载与实例化时按进入树重新生成。
class_name PathPatternScatter2D
extends Node2D

## 单次发射最后一颗粒子寿命结束时发出；完成通知归属当前有效轮次。
signal finished

## 随机种子下限：6 位种子的最小取值。
const SEED_MIN := 100000
## 随机种子上限：6 位种子的最大取值。
const SEED_MAX := 999999

@export_group("散布")
## 路径配置资源；每条有效曲线各自在走廊内独立播撒。
@export var definition: PathDefinition = null:
	set(value):
		_disconnect_curve_signals()
		definition = value
		_rebind_curve_signals()
		_request_rebuild()

## 横向半宽：沿路径法线方向的走廊半宽（像素）。
@export_range(0.0, 4096.0, 1.0, "or_greater", "suffix:px") var half_width: float = 32.0:
	set(value):
		half_width = maxf(value, 0.0)
		_request_rebuild()

## 沿路径弧长采样列数。
@export_range(1, 512, 1) var columns: int = 24:
	set(value):
		columns = maxi(value, 1)
		_request_rebuild()

## 每个弧长基点在横向条带内再采的点数。
@export_range(1, 64, 1) var samples_per_column: int = 1:
	set(value):
		samples_per_column = maxi(value, 1)
		_request_rebuild()

## 预设图案贴图列表；空项跳过。
@export var patterns: Array[Texture2D] = []:
	set(value):
		patterns = value
		_request_rebuild()

## 与 patterns 对齐的权重；缺省或非正则按 1；按权重把总 amount 分到各子系统。
@export var pattern_weights: Array[float] = []:
	set(value):
		pattern_weights = value
		_request_rebuild()

## 固定随机种子：同种子同参数生成结果完全一致（命名避开全局函数 seed()）。
@export_range(100000, 999999, 1) var random_seed: int = SEED_MIN:
	set(value):
		random_seed = clampi(value, SEED_MIN, SEED_MAX)
		_request_rebuild()

## 随机生成 6 位种子。
@export_tool_button("随机种子") var randomize_seed_button: Callable = randomize_seed

@export_group("粒子动画")
## 同时存活粒子总数；按权重拆到各纹理子系统。
@export_range(1, 4096, 1) var amount: int = 64:
	set(value):
		amount = maxi(value, 1)
		_request_rebuild()

## 粒子寿命（秒）。
@export_range(0.05, 600.0, 0.01, "or_greater", "suffix:s") var lifetime: float = 2.0:
	set(value):
		lifetime = maxf(value, 0.05)
		_sync_particle_runtime()

## 爆发比例：1 表示同一时刻放出全部粒子。
@export_range(0.0, 1.0, 0.01) var explosiveness: float = 0.0:
	set(value):
		explosiveness = clampf(value, 0.0, 1.0)
		_sync_particle_runtime()

## 单次发射：放完一轮后停止。
@export var one_shot: bool = false:
	set(value):
		one_shot = value
		_sync_particle_runtime()

## 是否正在发射。
@export var emitting: bool = true:
	set(value):
		emitting = value
		if not _starting:
			_playing = value
			_elapsed = 0.0
			_delay_remaining = 0.0
		_sync_particle_runtime()

## 预模拟时长（秒），用于编辑器与运行时立刻看到已铺开的粒子。
@export_range(0.0, 60.0, 0.01, "or_greater", "suffix:s") var preprocess: float = 0.0:
	set(value):
		preprocess = maxf(value, 0.0)
		_sync_particle_runtime()

## 沿路径切线的初速度（像素/秒）；为 0 时用 POINTS 发射且初速为 0。
@export_range(0.0, 2000.0, 1.0, "or_greater", "suffix:px/s") var velocity_along_path: float = 0.0:
	set(value):
		velocity_along_path = maxf(value, 0.0)
		_request_rebuild()

@export_group("运动扩展")
## 以 velocity_along_path 为中心的相对速度浮动，0 表示固定速度。
@export_range(0.0, 1.0, 0.01) var velocity_variation: float = 0.0:
	set(value):
		velocity_variation = clampf(value, 0.0, 1.0)
		_request_rebuild()

## 相对路径切线的发射张角，默认 45 度。
@export_range(0.0, 180.0, 0.1, "suffix:°") var spread_degrees: float = 45.0:
	set(value):
		spread_degrees = clampf(value, 0.0, 180.0)
		_request_rebuild()

## 粒子持续自转的角速度下限与上限。
@export_range(-1440.0, 1440.0, 1.0, "or_less", "or_greater", "suffix:°/s") var angular_velocity_min: float = 0.0:
	set(value):
		angular_velocity_min = value
		_request_rebuild()
@export_range(-1440.0, 1440.0, 1.0, "or_less", "or_greater", "suffix:°/s") var angular_velocity_max: float = 0.0:
	set(value):
		angular_velocity_max = value
		_request_rebuild()

## 线性减速（像素/秒²），速度下界为 0；阻尼为 0 时匀速运动。
@export_range(0.0, 4000.0, 1.0, "or_greater") var damping_min: float = 0.0:
	set(value):
		damping_min = maxf(value, 0.0)
		_request_rebuild()
@export_range(0.0, 4000.0, 1.0, "or_greater") var damping_max: float = 0.0:
	set(value):
		damping_max = maxf(value, 0.0)
		_request_rebuild()

@export_group("寿命扩展")
## 横轴为归一化寿命，纵轴乘出生缩放；空资源表示恒定出生缩放。
@export var scale_over_life: CurveTexture:
	set(value):
		scale_over_life = value
		_rebind_animation_resources()
		_request_rebuild()
## RGBA 寿命渐变；显式资源优先于 fade_out 的线性淡出。
@export var color_over_life: GradientTexture1D:
	set(value):
		color_over_life = value
		_rebind_animation_resources()
		_request_rebuild()
## 可选独立透明度乘数曲线，叠乘颜色渐变的 alpha。
@export var opacity_over_life: CurveTexture:
	set(value):
		opacity_over_life = value
		_rebind_animation_resources()
		_request_rebuild()

@export_group("粒子外观")
## 粒子出生缩放下限。
@export_range(0.01, 64.0, 0.01, "or_greater") var scale_min: float = 1.0:
	set(value):
		scale_min = maxf(value, 0.01)
		_request_rebuild()

## 粒子出生缩放上限。
@export_range(0.01, 64.0, 0.01, "or_greater") var scale_max: float = 1.0:
	set(value):
		scale_max = maxf(value, 0.01)
		_request_rebuild()

## 粒子出生朝向下限（度）。
@export_range(-720.0, 720.0, 0.1, "or_less", "or_greater", "suffix:°") var angle_degrees_min: float = 0.0:
	set(value):
		angle_degrees_min = value
		_request_rebuild()

## 粒子出生朝向上限（度）。
@export_range(-720.0, 720.0, 0.1, "or_less", "or_greater", "suffix:°") var angle_degrees_max: float = 0.0:
	set(value):
		angle_degrees_max = value
		_request_rebuild()

## 是否启用寿命内 alpha 从 1 到 0 的淡出。
@export var fade_out: bool = true:
	set(value):
		fade_out = value
		_request_rebuild()

var _animation_resources: Array[Resource] = []
var _emission_bounds := Rect2()
var _playing := false
var _delay_remaining := 0.0
var _elapsed := 0.0
var _starting := false

var _particle_nodes: Array[GPUParticles2D] = []
var _definition_connected := false
var _rebuild_queued := false
var _emission_point_texture: Texture2D = null
var _emission_normal_texture: Texture2D = null
var _emission_point_count: int = 0
var _fade_ramp: GradientTexture1D = null

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_ENTER_TREE:
			_rebind_curve_signals()
			_rebind_animation_resources()
			_request_rebuild()
		NOTIFICATION_EXIT_TREE:
			stop()
			_disconnect_curve_signals()
			_disconnect_animation_resources()

## 当前生成的粒子子系统快照副本。
func get_particle_systems() -> Array[GPUParticles2D]:
	return _particle_nodes.duplicate()

## 最近一次烘焙的发射点数量。
func get_emission_point_count() -> int:
	return _emission_point_count

## 随机生成 6 位种子并重建；Inspector 按钮与运行时共用。
func randomize_seed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	random_seed = rng.randi_range(SEED_MIN, SEED_MAX)

## 按当前固定种子重播，延迟结束后开始发射。
func restart(delay: float = 0.0) -> void:
	stop()
	_delay_remaining = maxf(delay, 0.0)
	_playing = true
	_elapsed = 0.0
	if _rebuild_queued:
		_rebuild()
	if _delay_remaining <= 0.0:
		_start_emission()

## 停止并取消待发射；默认清空存活粒子。false 保留尾迹自然消失。
func stop(clear_particles: bool = true) -> void:
	_playing = false
	_delay_remaining = 0.0
	emitting = false
	if clear_particles:
		for particles in _particle_nodes:
			particles.restart(true)
			particles.emitting = false

func is_playing() -> bool:
	return _playing

## one_shot 的最大排空时间；连续发射由调用方显式停止。
func get_burst_duration() -> float:
	return lifetime * (2.0 - explosiveness)

func _start_emission() -> void:
	_starting = true
	emitting = true
	_starting = false
	for particles in _particle_nodes:
		particles.restart(true)
		particles.emitting = true
	if _particle_nodes.is_empty():
		_finish_burst()

func _finish_burst() -> void:
	_playing = false
	emitting = false
	finished.emit()

func _process(delta: float) -> void:
	if not _playing or Engine.is_editor_hint():
		return
	if _delay_remaining > 0.0:
		_delay_remaining -= delta
		if _delay_remaining <= 0.0:
			_start_emission()
		return
	_elapsed += delta
	# 完成边界采用最后出生时刻、完整寿命与一个粒子模拟步长的总和。
	if one_shot and _elapsed >= get_burst_duration() + 1.0 / 30.0:
		_finish_burst()

func _request_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()

func _rebuild() -> void:
	if not _rebuild_queued:
		return
	_rebuild_queued = false
	_clear_particle_nodes()
	_rebind_animation_resources()

	var curve_list: Array[Curve2D] = []
	if definition != null:
		curve_list = definition.get_curves()
	var baked := PathPatternScatterBuilder.bake_emission(
		curve_list,
		columns,
		samples_per_column,
		half_width,
		random_seed
	)
	var positions: PackedVector2Array = baked["positions"]
	_emission_bounds = Rect2()
	if not positions.is_empty():
		_emission_bounds = Rect2(positions[0], Vector2.ZERO)
		for point in positions:
			_emission_bounds = _emission_bounds.expand(point)
	var textures := PathPatternScatterBuilder.build_emission_textures(
		baked["positions"],
		baked["directions"]
	)
	_emission_point_texture = textures["point_texture"]
	_emission_normal_texture = textures["normal_texture"]
	_emission_point_count = int(textures["point_count"])

	var valid_patterns := _collect_valid_patterns()
	if _emission_point_count < 1 or valid_patterns.is_empty():
		update_configuration_warnings()
		return

	var amounts := PathPatternScatterBuilder.split_amounts_by_weight(
		amount,
		_collect_weights(valid_patterns.size()),
		valid_patterns.size()
	)
	_ensure_fade_ramp()
	for index in valid_patterns.size():
		var particle_amount := amounts[index]
		if particle_amount < 1:
			continue
		var particles := _create_particle_system(valid_patterns[index], particle_amount)
		add_child(particles)
		_particle_nodes.append(particles)
		particles.restart(true)
		particles.emitting = emitting and _delay_remaining <= 0.0
	if emitting and not Engine.is_editor_hint():
		_playing = true
		_elapsed = 0.0
	update_configuration_warnings()

func _collect_valid_patterns() -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	for pattern in patterns:
		if pattern != null:
			result.append(pattern)
	return result

func _collect_weights(pattern_count: int) -> Array[float]:
	var weights: Array[float] = []
	var valid_index := 0
	for pattern_index in patterns.size():
		if patterns[pattern_index] == null:
			continue
		var weight := 1.0
		if pattern_index < pattern_weights.size() and pattern_weights[pattern_index] > 0.0:
			weight = pattern_weights[pattern_index]
		weights.append(weight)
		valid_index += 1
		if valid_index >= pattern_count:
			break
	while weights.size() < pattern_count:
		weights.append(1.0)
	return weights

func _create_particle_system(texture: Texture2D, particle_amount: int) -> GPUParticles2D:
	var particles := GPUParticles2D.new()
	particles.texture = texture
	particles.amount = particle_amount
	particles.lifetime = lifetime
	particles.explosiveness = explosiveness
	particles.one_shot = one_shot
	particles.emitting = emitting
	particles.preprocess = preprocess
	particles.local_coords = true
	particles.use_fixed_seed = true
	particles.seed = random_seed
	particles.process_material = _build_process_material()
	particles.visibility_rect = _calculate_visibility_rect(texture)
	return particles

func _build_process_material() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.particle_flag_disable_z = true
	material.gravity = Vector3.ZERO
	material.emission_point_count = _emission_point_count
	material.emission_point_texture = _emission_point_texture
	var use_directed := velocity_along_path > 0.0
	if use_directed:
		material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_DIRECTED_POINTS
		material.emission_normal_texture = _emission_normal_texture
		material.initial_velocity_min = velocity_along_path * (1.0 - velocity_variation)
		material.initial_velocity_max = velocity_along_path * (1.0 + velocity_variation)
	else:
		material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
		material.initial_velocity_min = 0.0
		material.initial_velocity_max = 0.0
	material.spread = spread_degrees
	material.angular_velocity_min = minf(angular_velocity_min, angular_velocity_max)
	material.angular_velocity_max = maxf(angular_velocity_min, angular_velocity_max)
	material.damping_min = minf(damping_min, damping_max)
	material.damping_max = maxf(damping_min, damping_max)
	if scale_over_life != null:
		material.scale_curve = scale_over_life.duplicate(true)
	if opacity_over_life != null:
		material.alpha_curve = opacity_over_life.duplicate(true)
	material.scale_min = minf(scale_min, scale_max)
	material.scale_max = maxf(scale_min, scale_max)
	material.angle_min = minf(angle_degrees_min, angle_degrees_max)
	material.angle_max = maxf(angle_degrees_min, angle_degrees_max)
	if color_over_life != null:
		material.color_ramp = color_over_life.duplicate(true)
	elif fade_out and _fade_ramp != null:
		material.color_ramp = _fade_ramp.duplicate(true)
	return material

func _ensure_fade_ramp() -> void:
	if _fade_ramp != null:
		return
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	_fade_ramp = GradientTexture1D.new()
	_fade_ramp.gradient = gradient

func _calculate_visibility_rect(texture: Texture2D) -> Rect2:
	# 重力为零且阻尼非负，最大出生速度乘寿命覆盖全部运动方向。
	var travel := velocity_along_path * (1.0 + velocity_variation) * lifetime
	var curve_scale := 1.0
	if scale_over_life != null and scale_over_life.curve != null:
		var curve := scale_over_life.curve
		curve_scale = maxf(absf(curve.min_value), absf(curve.max_value))
		for index in curve.point_count:
			curve_scale = maxf(curve_scale, absf(curve.get_point_position(index).y))
		# 曲线纹理各 texel 的最大采样值覆盖切线过冲与 GPU 线性插值。
		for index in maxi(scale_over_life.width, 2):
			curve_scale = maxf(curve_scale, absf(curve.sample_baked(float(index) / float(maxi(scale_over_life.width, 2) - 1))))
	var radius := texture.get_size().length() * 0.5 * maxf(scale_min, scale_max) * curve_scale
	return _emission_bounds.grow(maxf(travel + radius + 8.0, 1.0))

func _disconnect_animation_resources() -> void:
	for resource in _animation_resources:
		if is_instance_valid(resource) and resource.changed.is_connected(_request_rebuild):
			resource.changed.disconnect(_request_rebuild)
	_animation_resources.clear()

func _rebind_animation_resources() -> void:
	_disconnect_animation_resources()
	for resource in [scale_over_life, color_over_life, opacity_over_life]:
		if resource != null and not _animation_resources.has(resource):
			resource.changed.connect(_request_rebuild)
			_animation_resources.append(resource)

func _sync_particle_runtime() -> void:
	for particles in _particle_nodes:
		if particles == null:
			continue
		particles.visibility_rect = _calculate_visibility_rect(particles.texture)
		particles.lifetime = lifetime
		particles.explosiveness = explosiveness
		particles.one_shot = one_shot
		particles.emitting = emitting
		particles.preprocess = preprocess

func _clear_particle_nodes() -> void:
	for particles in _particle_nodes:
		if particles == null:
			continue
		remove_child(particles)
		particles.queue_free()
	_particle_nodes.clear()

func _on_definition_changed() -> void:
	_rebind_curve_signals()
	_request_rebuild()

func _rebind_curve_signals() -> void:
	_disconnect_curve_signals()
	if definition == null:
		return
	definition.geometry_changed.connect(_on_definition_changed)
	_definition_connected = true

func _disconnect_curve_signals() -> void:
	if _definition_connected and definition != null \
			and definition.geometry_changed.is_connected(_on_definition_changed):
		definition.geometry_changed.disconnect(_on_definition_changed)
	_definition_connected = false

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if definition == null:
		warnings.append("需要指定 PathDefinition 路径配置资源。")
		return warnings
	var valid_curves := 0
	for path in definition.get_curves():
		if path != null and path.point_count >= 2:
			valid_curves += 1
	if valid_curves < 1:
		warnings.append("PathDefinition 需要至少 1 条有效 Curve2D（各含至少 2 个点）。")
	var has_pattern := false
	for pattern in patterns:
		if pattern != null:
			has_pattern = true
			break
	if not has_pattern:
		warnings.append("需要至少一张有效的图案 Texture2D。")
	var weight_sum := 0.0
	var valid_pattern_count := 0
	for pattern_index in patterns.size():
		if patterns[pattern_index] == null:
			continue
		valid_pattern_count += 1
		if pattern_index < pattern_weights.size():
			weight_sum += maxf(pattern_weights[pattern_index], 0.0)
		else:
			weight_sum += 1.0
	if valid_pattern_count > 0 and pattern_weights.size() > 0 and weight_sum <= 0.0:
		warnings.append("图案权重之和需要大于 0。")
	return warnings
