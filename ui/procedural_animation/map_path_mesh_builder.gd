## MapPath 网格构建器：把若干行等列采样点转为「U 轴沿路径、V 轴跨路径」的贴图网格。
## 算法参考 Pixel-Composer（MIT）Map Path 节点的多路径网格映射。
class_name MapPathMeshBuilder
extends RefCounted

const MIN_COLUMNS := 2

## 每条 Curve2D 按弧长等距采样 columns 个点，各自成一行。
## 无效路径（空或点数不足）跳过；返回行数可能少于传入路径数。
static func sample_path_rows(paths: Array[Curve2D], columns: int) -> Array[PackedVector2Array]:
	var rows: Array[PackedVector2Array] = []
	for path in paths:
		if path == null or path.point_count < 2:
			continue
		rows.append(_sample_curve_row(path, columns))
	return rows

## 行点阵转 ArrayMesh（三角形列表）。行数或列数不足、各行列数不齐时返回空网格。
## 拉伸模式 U = 列比例；平铺模式 U = 行内累计弧长 / tile_length。V = 行比例（第 0 行为贴图顶部）。
static func build_mesh(
		rows: Array[PackedVector2Array], uv_tile: bool = false, tile_length: float = 64.0
) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var row_count := rows.size()
	if row_count < 2:
		return mesh
	var columns := rows[0].size()
	if columns < MIN_COLUMNS:
		return mesh
	for row in rows:
		if row.size() != columns:
			return mesh

	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	vertices.resize(row_count * columns)
	uvs.resize(row_count * columns)

	for r in row_count:
		var row := rows[r]
		var v := float(r) / float(row_count - 1)
		var acc := 0.0
		for c in columns:
			var idx := r * columns + c
			vertices[idx] = row[c]
			if uv_tile:
				if c > 0:
					acc += row[c].distance_to(row[c - 1])
				uvs[idx] = Vector2(acc / maxf(tile_length, 0.001), v)
			else:
				uvs[idx] = Vector2(float(c) / float(columns - 1), v)

	var indices := PackedInt32Array()
	indices.resize((row_count - 1) * (columns - 1) * 6)
	var write := 0
	for r in row_count - 1:
		for c in columns - 1:
			var i0 := r * columns + c
			var i1 := (r + 1) * columns + c
			var i2 := r * columns + c + 1
			var i3 := (r + 1) * columns + c + 1
			indices[write] = i0
			indices[write + 1] = i2
			indices[write + 2] = i1
			indices[write + 3] = i2
			indices[write + 4] = i3
			indices[write + 5] = i1
			write += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

static func _sample_curve_row(path: Curve2D, columns: int) -> PackedVector2Array:
	var row := PackedVector2Array()
	if columns < MIN_COLUMNS:
		return row
	row.resize(columns)
	var total := path.get_baked_length()
	for i in columns:
		row[i] = path.sample_baked(float(i) / float(columns - 1) * total)
	return row
