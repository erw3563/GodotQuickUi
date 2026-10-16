## 放射条带构建参数：一次构建的输入值快照，按基础几何／随机／角度偏移区域三组组织。
## 由 RadialRays 节点从导出字段装配，也可由调用方直接具名装配后交给 RadialRaysBuilder。
## 字段缺省为零值空配置（条带数为 0），构建按契约返回空数组。
class_name RadialRaysParameters
extends RefCounted

# —— 基础几何 ——

## 条带数量；小于 1 时不生成条带。
var ray_count: int = 0

## 内半径：条带起点所在的基础半径；0 时起点横线落在原点。
var inner_radius: float = 0.0

## 外半径：条带终点所在的基础半径；须大于内半径，否则不生成条带。
var outer_radius: float = 0.0

## 基础宽度：条带内端横切线的长度，起点为一条该长度的线段；0 时起点收成一个点，负值按 0 处理。
var base_width: float = 0.0

## 斜率：两侧边每单位轴向距离的横向展开量（无量纲）；0 时两侧边平行、条带等宽，
## 正值向外张开、负值向内收窄（内端最宽）。
var ray_slope: float = 0.0

## 全体中心角统一偏移（弧度）：加在每根最终中心角上，用于整盘方位调整。
var angle_offset: float = 0.0

# —— 随机 ——

## 内半径逐根随机幅度：每根条带起点半径在内半径上 ± 随机。
var inner_radius_randomness: float = 0.0

## 斜率逐根随机幅度：每根条带斜率在基础值 × (1±幅度) 系数内随机，保持斜率符号，不影响内端横线长度。
var slope_randomness: float = 0.0

## 长度逐根随机幅度：每根条带外半径在基础值 ± 幅度内随机（下限保护到该根起点，不内翻）。
var length_randomness: float = 0.0

## 角度逐根随机幅度（弧度）：每根条带中心角在基准 ± 幅度内抖动。
var angle_randomness: float = 0.0

## 固定随机种子：直接作为随机数发生器种子；同种子同参数结果完全一致。
var random_seed: int = 0

# —— 角度偏移区域 ——

## 区域起始角（弧度）；与跨度共同划定半开环段。
var region_start_angle: float = 0.0

## 区域跨度（弧度）；0 时整组区域偏移不生效，上限为一整圈。
var region_span: float = 0.0

## 区内条带的内半径固定偏移（像素，可负）；与逐根内半径随机相加。
var region_inner_radius_offset: float = 0.0

## 区内条带的斜率系数固定偏移：有效系数 = 1±随机 + 本偏移，再下限钳 0 后乘基础斜率。
var region_slope_scale_offset: float = 0.0

## 区内条带的外半径固定偏移（像素，可负）；与逐根长度随机相加。
var region_length_offset: float = 0.0

## 区内条带的中心角固定偏移（弧度，可负）；与逐根角度随机相加。
var region_angle_offset: float = 0.0
