@tool
class_name PathAnchorSet
extends Resource
## 路径挂点集合，按曲线索引与 PathDefinition 对应。
## parents[i] 为第 i 条曲线的父曲线索引，-1 表示该曲线没有挂点；父曲线索引小于 i。
## fractions[i] 为挂点在父曲线上的归一化弧长（0 为父曲线起点，1 为终点）。
## LightningPathGenerator.generate_with_metadata() 返回与闪电定义配套的实例；
## PathMorph 在 GROW_FROM_ANCHOR 模式下读取它，让缺失一侧的曲线从挂点沿弧长生长。

@export var parents := PackedInt32Array():
	set(value):
		parents = value
		emit_changed()
@export var fractions := PackedFloat32Array():
	set(value):
		fractions = value
		emit_changed()

## 返回第 index 条曲线的父曲线索引；无挂点或数据不完整时返回 -1。
func get_parent_index(index: int) -> int:
	if index < 0 or index >= parents.size() or index >= fractions.size():
		return -1
	var parent := parents[index]
	return parent if parent >= 0 and parent < index and is_finite(fractions[index]) else -1

## 返回第 index 条曲线挂点的归一化弧长，范围 0–1；无挂点时返回 0。
func get_fraction(index: int) -> float:
	return clampf(fractions[index], 0.0, 1.0) if get_parent_index(index) >= 0 else 0.0
