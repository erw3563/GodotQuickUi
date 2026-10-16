## 路径图案播撒构建器：沿 Curve2D 弧长采样，在法线横向条带内按固定种子偏移，得到发射点与切线方向；
## 并为静态贴图节点提供按权重抽图、缩放与朝向烘焙。
## 静态几何函数；同种子同参数结果完全一致。
class_name PathPatternScatterBuilder
extends RefCounted

## 沿路径列表烘焙发射点与单位切线方向。
## 每条有效曲线（至少 2 个点）按弧长等距取 columns 个基点；零长度曲线采用首点与右向切线。
## 每个基点再采 samples_per_column 个横向点，
## 横向偏移落在 [-half_width, half_width]。无效曲线跳过。columns 或 samples_per_column 小于 1 时返回空。
static func bake_emission(
	paths: Array[Curve2D],
	columns: int,
	samples_per_column: int,
	half_width: float,
	random_seed: int
) -> Dictionary:
	var positions := PackedVector2Array()
	var directions := PackedVector2Array()
	if columns < 1 or samples_per_column < 1:
		return {"positions": positions, "directions": directions}

	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var band := maxf(half_width, 0.0)

	for path in paths:
		if path == null or path.point_count < 2:
			continue
		var total_length := path.get_baked_length()
		for column_index in columns:
			var arc_offset := 0.0
			if columns > 1:
				arc_offset = float(column_index) / float(columns - 1) * total_length
			else:
				arc_offset = total_length * 0.5
			var sample_transform := Transform2D(0.0, path.get_point_position(0))
			if total_length > 0.000001:
				sample_transform = path.sample_baked_with_rotation(arc_offset)
			var tangent := sample_transform.x
			if tangent.length_squared() < 0.000001:
				tangent = Vector2.RIGHT
			else:
				tangent = tangent.normalized()
			var normal := Vector2(-tangent.y, tangent.x)
			for _sample_index in samples_per_column:
				var lateral := rng.randf_range(-band, band)
				positions.append(sample_transform.origin + normal * lateral)
				directions.append(tangent)

	return {"positions": positions, "directions": directions}

## 把位置与方向写入 1×N 的 RGBAF ImageTexture，供 ParticleProcessMaterial 的 POINTS / DIRECTED_POINTS 使用。
## 点数为 0 时返回空纹理字典（point_texture / normal_texture 均为 null）。
static func build_emission_textures(
	positions: PackedVector2Array,
	directions: PackedVector2Array
) -> Dictionary:
	var point_count := positions.size()
	if point_count < 1 or directions.size() != point_count:
		return {"point_texture": null, "normal_texture": null, "point_count": 0}

	var point_image := Image.create(point_count, 1, false, Image.FORMAT_RGBAF)
	var normal_image := Image.create(point_count, 1, false, Image.FORMAT_RGBAF)
	for index in point_count:
		var position := positions[index]
		var direction := directions[index]
		point_image.set_pixel(index, 0, Color(position.x, position.y, 0.0, 1.0))
		normal_image.set_pixel(index, 0, Color(direction.x, direction.y, 0.0, 1.0))

	return {
		"point_texture": ImageTexture.create_from_image(point_image),
		"normal_texture": ImageTexture.create_from_image(normal_image),
		"point_count": point_count,
	}

## 按权重把总粒子数拆到各图案槽；权重非正或缺失时按 1 处理。返回与有效图案数等长的整数数组，和为 total_amount。
static func split_amounts_by_weight(total_amount: int, weights: Array[float], pattern_count: int) -> PackedInt32Array:
	var amounts := PackedInt32Array()
	amounts.resize(pattern_count)
	if pattern_count < 1:
		return amounts
	var safe_total := maxi(total_amount, 0)
	if safe_total == 0:
		return amounts

	var normalized: Array[float] = []
	normalized.resize(pattern_count)
	var weight_sum := 0.0
	for index in pattern_count:
		var weight := 1.0
		if index < weights.size() and weights[index] > 0.0:
			weight = weights[index]
		normalized[index] = weight
		weight_sum += weight
	if weight_sum <= 0.0:
		return amounts

	var assigned := 0
	for index in pattern_count:
		if index == pattern_count - 1:
			amounts[index] = safe_total - assigned
		else:
			var share := int(floor(float(safe_total) * normalized[index] / weight_sum))
			amounts[index] = share
			assigned += share
	return amounts

## 按权重为每个贴图点抽图案下标；权重非正或缺失时按 1。返回长度 point_count 的下标数组。
## 独立 RNG（seed = random_seed），与 bake_emission 的抽数序列分离。
static func pick_weighted_pattern_indices(
	point_count: int,
	weights: Array[float],
	random_seed: int
) -> PackedInt32Array:
	var indices := PackedInt32Array()
	var safe_count := maxi(point_count, 0)
	indices.resize(safe_count)
	var pattern_count := weights.size()
	if safe_count < 1 or pattern_count < 1:
		return indices

	var normalized: Array[float] = []
	normalized.resize(pattern_count)
	var weight_sum := 0.0
	for index in pattern_count:
		var weight := 1.0
		if weights[index] > 0.0:
			weight = weights[index]
		normalized[index] = weight
		weight_sum += weight
	if weight_sum <= 0.0:
		return indices

	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	for point_index in safe_count:
		indices[point_index] = _pick_weighted_index(rng, normalized, weight_sum)
	return indices

## 为每个贴图点抽图案下标、统一缩放与朝向（弧度）。
## 每点依次抽图案、缩放、角度；独立 RNG（seed = random_seed），与 bake_emission 分离。
static func bake_stamp_instances(
	point_count: int,
	weights: Array[float],
	scale_min: float,
	scale_max: float,
	angle_degrees_min: float,
	angle_degrees_max: float,
	random_seed: int
) -> Dictionary:
	var safe_count := maxi(point_count, 0)
	var pattern_indices := PackedInt32Array()
	var scales := PackedFloat32Array()
	var angles_radians := PackedFloat32Array()
	pattern_indices.resize(safe_count)
	scales.resize(safe_count)
	angles_radians.resize(safe_count)

	var pattern_count := weights.size()
	if safe_count < 1 or pattern_count < 1:
		return {
			"pattern_indices": pattern_indices,
			"scales": scales,
			"angles_radians": angles_radians,
		}

	var normalized: Array[float] = []
	normalized.resize(pattern_count)
	var weight_sum := 0.0
	for index in pattern_count:
		var weight := 1.0
		if weights[index] > 0.0:
			weight = weights[index]
		normalized[index] = weight
		weight_sum += weight
	if weight_sum <= 0.0:
		return {
			"pattern_indices": pattern_indices,
			"scales": scales,
			"angles_radians": angles_radians,
		}

	var low_scale := minf(scale_min, scale_max)
	var high_scale := maxf(scale_min, scale_max)
	var low_angle := minf(angle_degrees_min, angle_degrees_max)
	var high_angle := maxf(angle_degrees_min, angle_degrees_max)
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	for point_index in safe_count:
		pattern_indices[point_index] = _pick_weighted_index(rng, normalized, weight_sum)
		scales[point_index] = rng.randf_range(low_scale, high_scale)
		angles_radians[point_index] = deg_to_rad(rng.randf_range(low_angle, high_angle))
	return {
		"pattern_indices": pattern_indices,
		"scales": scales,
		"angles_radians": angles_radians,
	}

static func _pick_weighted_index(
	rng: RandomNumberGenerator,
	normalized: Array[float],
	weight_sum: float
) -> int:
	var roll := rng.randf() * weight_sum
	var cumulative := 0.0
	for index in normalized.size():
		cumulative += normalized[index]
		if roll <= cumulative:
			return index
	return normalized.size() - 1
