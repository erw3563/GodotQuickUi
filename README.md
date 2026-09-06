# GodotQuickUi

一套功能性 UI 节点集。全部脚本零外部依赖，可随意取用，带一个可交互的十页演示沙盒。

## 功能一览

| 类名 | 目录 | 说明 |
|---|---|---|
| `QuickDrag` | `ui/quick_node/` | 让 Control 可被鼠标拖拽：自由 / 仅水平 / 仅竖直三种模式，可限制在相对拖拽起点的轴向区间内 |
| `QuickPopOut` | `ui/quick_node/` | 从屏幕外八个方向之一飞入 / 收起，可附带淡入淡出、反向离场 |
| `QuickZoom` | `ui/quick_node/` | 从可配置原点（`origin_ratio`）放大展开、缩回原点收起的出场演出 |
| `QuickRotate` | `ui/quick_node/` | 从倾斜角旋转回正入场、转回倾斜退场，可与 QuickZoom 联动出「放大 + 回正」组合演出 |
| `QuickShow` | `ui/quick_node/` | 显隐管理：可绑按键快速收起，配了 QuickPopOut 后显隐自动改走飞入 / 收起动画 |
| `QuickMousePlace` | `ui/quick_node/` | 把 Control 定位到鼠标处：视口钳制、越界贴角翻转、可选轴居中，定位后可联动显形 |
| `QuickConstraints` | `ui/quick_node/` | 按标记控件边界与视口偏移把 Control 钳回合法驻留区域，支持每帧持续钳制 |
| `QuickHost` | `ui/quick_node/` | 组件宿主：检查器里按预设一键生成上述组件并全自动接线，兼任位置落笔仲裁（见下文） |
| `SideBarPanel` | `ui/panel_node/` | 贴边抽屉侧边栏：四边可选、悬停 / 点击 / 按键展开收起、收起后保留指定露出长度 |
| `PocketDrawerPanel` | `ui/panel_node/` | 屏内抽屉：展开显示完整内容，收起缩成钉在四角之一的标题方块，不依赖贴屏边 |
| `ZoomPanel` | `ui/panel_node/` | 缩放面板：从种子缩放放大入场，展开 / 收起目标缩放均可配，支持悬停、点击与外部热区控件交互 |
| `ConstrainedPoints` | `ui/procedural_animation/` | 约束链线段：点列带长度上下限与折角约束，头端跟随目标或鼠标，自然甩动 |
| `Trajectory` | `ui/procedural_animation/` | 在约束链基础上加拖尾渐消（`disappear_speed`），适合做鼠标轨迹、挥剑残影 |
| `FixedBaseConstrainedLine2d` | `ui/procedural_animation/` | 定基约束线：尾端钉在自身位置、头端跟随目标，叠加正弦波动（振幅 / 频率 / 波速） |

## 快捷系组件（quick_node）

### 推荐用法：QuickHost 装配

在目标 Control 下挂一个 `QuickHost` 节点（或把它的 `ui` 指向目标），然后在检查器里：

1. 选一枚生成预设：`DRAGGABLE`（可拖拽卡片）、`POP_OUT`（弹入弹出）、`SHOW_MENU`（鼠标处弹出菜单）、`ZOOM_UPRIGHT_ENTRANCE`（放大回正入场）；
2. 点 「生成快捷节点」 按钮——组件子节点即按开关生成、目标引用与组合接线全部自动完成，并随场景一起保存；
3. 各组件的行为参数（弹出方向、拖拽模式、原点比例……）直接在生成的子节点上调；跨演出组件的高频入场参数（`animate_entrance` / `animation_duration` / `animation_transition` / `animation_ease`）由宿主统一下发，您可在生成后随意修改。

运行时用 `host.play_entrance()` / `host.play_exit()` 成组播放旗下所有演出组件；纯代码装配（如动态浮窗）调用 `ensure_quick_nodes()` 即可。

### 散装用法

单独挂任意组件到 Control 下，行为参数在组件自身上配置。

## 面板节点（panel_node）

三个面板都是 `PanelContainer` 子类，放进场景、配好导出参数即用，共同提供：`expanded_changed` 信号、`toggle_input_action` 按键切换、`toggle_button` 绑定按钮、`expand_on_mouse_hover` 悬停展开与 `toggle_on_click` 点击切换，以及统一的动画时长 / 过渡 / 缓动参数。

- SideBarPanel — 贴左 / 上 / 右 / 下边，`collapsed_visible_length` 控制收起后残留长度，`stretch_along_edge` 控制沿边拉满；
- PocketDrawerPanel — 收起缩成 `collapsed_size` 见方的方块钉在 `pivot_corner` 角，可带 `collapsed_title` 短标题，展开时向对角铺开；
- ZoomPanel — 从 `collapsed_scale` 种子放大到 `expanded_scale`，原点由 `origin_ratio` 钉扎；可选 `interaction_control` 把悬停 / 点击检测区完全交给面板外的任意控件（外部热区）。

## 程序化动画（procedural_animation）

基于「长度约束 + 折角约束」迭代求解的点列线段，头端跟随 `target`（留空则跟随鼠标）：

- ConstrainedPoints — 基础约束链；同目录 `procedural_animation_line.tscn` 演示像素化线段与描边 shader（`outline.gdshader`）的用法；
- Trajectory — 约束链 + 距离衰减渐消的拖尾；
- FixedBaseConstrainedLine2d — 尾端钉死、头端跟随，叠加沿线正弦波动。

## 示例沙盒

运行 `ui/examples/ui_showcase/ui_showcase_sandbox.tscn`：左侧抽屉导航互斥切换 **10 个演示页**，覆盖全部快捷系组件与三个面板；**R** 重置当前页，**Esc** 退出。想看某个组件的标准装配，直接打开对应 `pages/page_*.tscn` 单页场景即可。

## 许可

[MIT](LICENSE)
