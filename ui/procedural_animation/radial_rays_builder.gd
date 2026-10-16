## 放射条带构建器：按参数与固定种子计算一圈条带的四边形顶点。
## 纯静态无状态，不接触场景树；随机流按「角度 → 斜率 → 内半径 → 长度」逐条带顺序消费，
## 同种子同参数结果完全一致。
class_name RadialRaysBuilder
extends RefCounted

## 计算一圈放射条带的四边形顶点（本地坐标，原点为放射中心）。
## 每根条带以中心角为轴，两端各是一条垂直于轴的横切线段，顶点序：内a → 内b → 外b → 外a，
## 内a 与外a 位于轴的同一侧，内b 与外b 位于轴的另一侧。
## 内端横线长度恒为 base_width（起点为一条线段）；外端横线长度 = base_width + 2 × 轴向长度 × 有效斜率，
## 下限钳 0——负斜率把端部收窄，极端负值把外端收成一个点，条带保持简单四边形。
## 角度偏移区域：以 region_start_angle 为起点、region_span 为跨度的半开环段；跨度 0 时整组区域偏移不生效。
## 归属按基准中心角 i × TAU / ray_count 判定（不受 angle_offset 影响）；区内条带叠加四类固定有符号偏移
## （内半径、斜率系数、长度、角度），与逐根随机相加。
## 有效起点半径 = max(内半径 + 内半径随机 + 区域偏移, 0)；
## 有效终点半径 = max(外半径 + 长度随机 + 区域偏移, 有效起点半径)。
## ray_count < 1 或 outer_radius <= inner_radius 时返回空数组。
static func build_ray_polygons(parameters: RadialRaysParameters) -> Array[PackedVector2Array]:
	var polygons: Array[PackedVector2Array] = []
	if parameters.ray_count < 1 or parameters.outer_radius <= parameters.inner_radius:
		return polygons

	var rng := RandomNumberGenerator.new()
	rng.seed = parameters.random_seed

	var angle_step := TAU / float(parameters.ray_count)
	var half_base := maxf(parameters.base_width, 0.0) * 0.5
	var span := clampf(parameters.region_span, 0.0, TAU)
	var start := fposmod(parameters.region_start_angle, TAU)

	for i in parameters.ray_count:
		var base_angle := i * angle_step
		var in_region := _is_angle_in_region(base_angle, start, span)
		var region_factor := 1.0 if in_region else 0.0

		var center_angle := (
			base_angle
			+ parameters.angle_offset
			+ rng.randf_range(-parameters.angle_randomness, parameters.angle_randomness)
			+ region_factor * parameters.region_angle_offset
		)
		var slope_scale := (
			rng.randf_range(1.0 - parameters.slope_randomness, 1.0 + parameters.slope_randomness)
			+ region_factor * parameters.region_slope_scale_offset
		)
		var radius_delta := (
			rng.randf_range(
				-parameters.inner_radius_randomness, parameters.inner_radius_randomness
			)
			+ region_factor * parameters.region_inner_radius_offset
		)
		var length_delta := (
			rng.randf_range(-parameters.length_randomness, parameters.length_randomness)
			+ region_factor * parameters.region_length_offset
		)

		var axis := Vector2.from_angle(center_angle)
		var lateral := Vector2.from_angle(center_angle + PI * 0.5)
		var start_radius := maxf(parameters.inner_radius + radius_delta, 0.0)
		var end_radius := maxf(parameters.outer_radius + length_delta, start_radius)
		var ray_slope_current := parameters.ray_slope * maxf(slope_scale, 0.0)
		var half_end := maxf(half_base + (end_radius - start_radius) * ray_slope_current, 0.0)

		var start_center := axis * start_radius
		var end_center := axis * end_radius
		polygons.append(
			PackedVector2Array([
				start_center - lateral * half_base,
				start_center + lateral * half_base,
				end_center + lateral * half_end,
				end_center - lateral * half_end,
			])
		)
	return polygons

## 判断基准角是否落在以 start 为起点、span 为跨度的半开环段 [start, start+span)。
## span 为 0 时无命中；span 为 TAU 时覆盖整圈。
static func _is_angle_in_region(angle: float, start: float, span: float) -> bool:
	if span <= 0.0:
		return false
	if span >= TAU:
		return true
	var end := start + span
	if end <= TAU:
		return angle >= start and angle < end
	return angle >= start or angle < end - TAU
