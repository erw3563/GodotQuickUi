@tool
class_name QuickSnap
extends QuickUiAbility
## 网格吸附阶段：依据网格间距和原点计算落笔提议。
@export var grid_size := Vector2(32, 32)
@export var grid_origin := Vector2.ZERO

func apply_place(_target: Control, proposed: Vector2) -> Vector2:
	if not enabled:
		return proposed
	var result := proposed
	if is_finite(grid_size.x) and absf(grid_size.x) > 0.000001:
		result.x = grid_origin.x + snappedf(proposed.x - grid_origin.x, absf(grid_size.x))
	if is_finite(grid_size.y) and absf(grid_size.y) > 0.000001:
		result.y = grid_origin.y + snappedf(proposed.y - grid_origin.y, absf(grid_size.y))
	return result
