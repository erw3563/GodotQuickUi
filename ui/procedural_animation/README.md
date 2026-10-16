# MapPath 内部 Add 试用

## UV 流动

`MapPathAddMesh2D` 的“UV 流动”组提供：

- `uv_offset`：起始采样偏移，U 沿路径，V 跨宽度。
- `uv_flow_speed`：每秒采样偏移的贴图周期数，默认 `(0.25, 0)`；正 U 使图案向路径起点移动，负 U 向终点移动。拉伸模式的周期对应整条路径，平铺模式对应 `tile_length`。
- `uv_flow_enabled`：自动播放开关，关闭后保持相位。默认关闭，避免已有场景自动改变。
- `preview_uv_flow`：显式开启编辑器预览，需要同时开启自动播放；运行时不受此预览开关限制。
- `uv_repeat_u/v`：独立循环开关，默认仅 U 循环，非循环轴钳制贴图边缘。无缝流动需要首尾可衔接的贴图。
- Inspector “重置流动”按钮／`reset_uv_flow()`：清除累积相位，回到 `uv_offset`；不改变播放开关。
- `advance_uv_flow(delta)`：外部时间轴手动推进，使用时关闭自动播放。自动播放遵循节点 process_mode 和游戏暂停／时间缩放，不依赖 Shader TIME。

Shader 只挂在独立画布内的路径网格上；最终输出仍为普通混合。相位与 ShaderMaterial 每个节点独立，不写回 PathDefinition、不重建网格，兼容低分辨率像素输出。本轮仅接入 Add 节点，普通 MapPath 节点未增加流动控制。

`MapPathAddMesh2D` 继承 `MapPathMesh2D`，复用 definition、subdivision、texture、uv_tile 和 tile_length。修改曲线后会自动更新。

- 每个实例拥有独立透明 SubViewport，按本地网格包围盒向外取整并留 1 像素边距，支持负坐标。
- 内部 MeshInstance2D 使用 Add；输出 Sprite2D 使用普通混合。背景不参与内部累加，节点 modulate/self_modulate 在最终合成阶段生效。内部节点不保存进场景。
- 原始 LDR 输出遵循 Pixel Composer `bm_add`：RGB = sum(src.rgb * src.a)，Alpha = sum(src.a * src.a)，各通道钳制到 [0,1]。输出是原始累加 RGBA，不做额外反预乘；普通显示会按输出 Alpha 合成，半透明单层不保证与直接绘制原贴图一致。
- 本轮验证的是上述输出公式与 Godot 普通合成；没有对 Pixel Composer 完整预览链做截图逐像素比对。
- `pixel_size` 控制每个输出像素覆盖的本地尺寸（1–32，默认 1）；先降低内部画布分辨率，再最近邻放大，轮廓与颜色同时像素化，几何尺寸保持不变。像素格对齐本地原点，路径包围盒变化不会改变采样格的相位，可在 Inspector 调整。
- 试用版无 HDR/灯光；缩放旋转作用于最终图像。实际渲染画布单边上限 4096，超限隐藏输出并警告。输出可见时更新画布；空贴图或无有效网格时停更并隐藏。
- 不要再给最终显示挂 `shaders/add.gdshader`。该 Shader 是直接对当前目标做 Add，适用于另外的加光需求。

参考：[Map Path](https://github.com/Ttanasart-pt/Pixel-Composer/blob/main/scripts/node_path_map/node_path_map.gml)、[混合宏](https://github.com/Ttanasart-pt/Pixel-Composer/blob/main/scripts/_draw_defines/_draw_defines.gml)。实现未复制其网格或 Shader 源码。

# 放射条带生成器（RadialRays）

`RadialRays`（`@tool` Control）按参数在名下生成一圈从中心向外发散的条带（每根一个 `Polygon2D` 子节点），用于开场/主菜单类背景装饰。几何计算在 `RadialRaysBuilder`（纯静态）；节点持有参数并调度重建。

- 控件形态：放射中心为矩形中心（`size / 2`；无布局时 `size` 为 0，中心即节点原点），尺寸变化只移动条带不重建；默认 `mouse_filter = IGNORE` 不拦截下层 UI 点击；可按普通 Control 锚点布局（满屏铺开即从屏幕中心放射）。
- 几何口径：每根条带以中心角为轴，两端各是一条垂直于轴的横切线段，顶点序内a → 内b → 外b → 外a。内端横线长度恒为 `base_width`——起点为一条该长度的线段，`base_width = 0` 时收成一个点；外端横线长度 = `base_width` + 2 × 轴向长度 × `ray_slope`，下限 0（负斜率把外端收窄，极端负值收成一个点，条带保持简单四边形）。
- 参数面：`ray_count`/`inner_radius`/`outer_radius`/`base_width`/`ray_slope`/`angle_offset` 基础几何（`ray_slope` 为两侧边每单位轴向距离的横向展开量，无量纲：0 时两侧边平行、整根等宽，正值向外张开、负值向内收窄即内端最宽，与条带数量无关；`angle_offset` 为全体中心角统一偏移，用于整盘方位调整，不改节点 `rotation`）；`inner_radius_randomness`/`slope_randomness`/`length_randomness`/`angle_randomness` 随机组（内半径随机幅度 0 时全体起点落在内半径、>0 逐根 ± 抖动；`slope_randomness` 按 1±幅度 逐根缩放斜率的绝对值、保持符号、不改变 `base_width`）；`region_start_angle`/`region_span`/`region_inner_radius_offset`/`region_slope_scale_offset`/`region_length_offset`/`region_angle_offset` 角度偏移组（起始角 + 跨度划定半开环段，跨度 0 时整组不生效；归属按基准中心角判定，可跨 0 缝合；区内四类固定有符号偏移与逐根随机相加）；`color`；`random_seed` 固定种子（同参数同结果，命名避开全局函数 `seed()`）。
- 种子口径：`random_seed` 为 6 位整数，取值范围 `100000`–`999999`（类常量 `SEED_MIN`/`SEED_MAX`），越界输入按上下限取值；Inspector「随机种子」按钮／`randomize_seed()` 随机生成一个 6 位种子并即时重建，编辑器与运行时共用同一入口。
- 每根有效起点半径 = max(内半径 + 内半径随机 + 区域偏移, 0)；有效终点半径 = max(外半径 + 长度随机 + 区域偏移, 有效起点半径)——把起点顶到外半径外或负长度压到起点时退化为零长度而非内翻。`inner_radius = 0` 时起点横线落在原点。
- 契约：名下直接子节点均为生成产物，参数变化即全部移除重建，不得挂业务节点；生成子节点不设 owner，不序列化进 `.tscn`，加载/实例化时按进入树重新生成。整盘动画（旋转/缩放/淡入）直接驱动本节点 transform。
- 参数 setter 走同帧合并 + 延迟重建（同 MapPathMesh2D 管线）；`color` 只同步子节点不重建；配置警告：外半径 ≤ 内半径、端部宽度达到外半径处相邻条带间距、起点宽度达到内半径处相邻条带间距（两条重叠警告都只在对应半径处生效；内半径 0 时跳过起点检查）。
- 预留扩展（未实施）：逐根条带展开 Tween、两盘反向缓旋编排、中心圆盘遮罩、Shader 版本。

## RadialRaysOutwardWave（向外波动）

`RadialRaysOutwardWave` 继承 `RadialRays`，用循环 Tween 推进 `wave_phase`（0→TAU），按条带序号错相把各 `Polygon2D` 缩放到 `1 + wave_amplitude × sin(相位 + 错相)`，形成沿环行进的规律外扩脉冲。

- 参数：`wave_autoplay`（默认开）、`wave_duration`、`wave_amplitude`、`wave_crest_count`（环上波峰数）。
- 入口：`play_wave()` / `stop_wave()`（停止时缩放归 1）/ `is_wave_playing()`；重建后自动恢复缩放，自动播放开启时重启 Tween。
- 脚本：`addons/gdbase/ui/procedural_animation/radial_rays_outward_wave.gd`。

自动化：`res://test/automated/procedural_animation/test_radial_rays.tscn` 覆盖构建器几何（基础宽度/斜率/等宽与点起点口径）/随机值域/种子确定性/内半径随机与角度区域偏移语义与节点级重建、落盘纪律（owner==null）、配置警告、向外波动。手动调参沙盒：`res://test/manual/gdbase/procedural_animation/radial_rays_preview.tscn`（宽深蓝 + 细亮蓝双盘叠放，细盘带内半径随机示例）。

# 路径横向条带图案播撒（PathPatternScatter2D）

`PathPatternScatter2D`（`@tool` Node2D）消费 `PathDefinition`，在每条有效 `Curve2D` 的法线方向 ±`half_width` 走廊内按固定种子播撒预设 `Texture2D`，并用 `GPUParticles2D`（`POINTS` / `DIRECTED_POINTS`）做淡出与沿切线漂移。几何在 `PathPatternScatterBuilder`（纯静态）；节点持有参数、监听路径变更并管理生成的粒子子节点。

- 多条曲线各自独立在自身走廊内播撒；单条有效曲线即可工作（与 MapPath「多条组成贴图带宽」语义分离）。
- 散布参数：`definition`、`half_width`、`columns`、`samples_per_column`、`patterns`、`pattern_weights`、`random_seed`（6 位，口径同 RadialRays）+「随机种子」按钮。
- 粒子参数：`amount`（按权重拆到各纹理子系统）、`lifetime`、`explosiveness`、`one_shot`、`emitting`、`preprocess`、`velocity_along_path`（>0 时用 DIRECTED_POINTS 沿切线初速）、`scale_min`/`scale_max`、`angle_degrees_min`/`max`、`fade_out`（默认寿命内不透明→透明）。
- 多纹理：每个有效图案一个 `GPUParticles2D`，共享同一套发射点/法线纹理；单系统 draw pass 不能做加权抽图。
- 契约：名下直接子节点均为生成产物，不设 owner，不进 `.tscn`；不得挂业务节点。路径/种子/半宽变化重建发射纹理并 `restart()`。
- 配置警告：无 definition、无有效曲线、无图案、权重和为 0。

手动沙盒：`res://test/manual/gdbase/procedural_animation/path_pattern_scatter_preview.tscn`。

# 路径横向条带图案静态贴图（PathPatternStamp2D）

`PathPatternStamp2D`（`@tool` Node2D）与 Scatter 共用走廊烘焙语义：消费 `PathDefinition`，在每条有效 `Curve2D` 的法线 ±`half_width` 走廊内按固定种子播撒预设 `Texture2D`。每个烘焙点生成一张 `Sprite2D`（按权重抽图案，并随机缩放与朝向）；不含粒子寿命、发射或漂移。

- 散布参数与 Scatter 对齐：`definition`、`half_width`、`columns`、`samples_per_column`、`patterns`、`pattern_weights`、`random_seed` +「随机种子」按钮。
- 外观：`scale_min`/`scale_max`、`angle_degrees_min`/`max`。
- 贴图数量 = 烘焙点数（`columns × samples_per_column × 有效曲线`）；每个点独立按权重抽图案。
- 几何复用 `PathPatternScatterBuilder.bake_emission`；实例外观由 `bake_stamp_instances` / `pick_weighted_pattern_indices` 计算。
- 契约：名下直接子节点均为生成的 `Sprite2D`，不设 owner，不进 `.tscn`；不得挂业务节点。
- 配置警告：无 definition、无有效曲线、无图案、权重和为 0。

手动沙盒：`res://test/manual/gdbase/procedural_animation/path_pattern_stamp_preview.tscn`。
