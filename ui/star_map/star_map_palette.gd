@tool
class_name StarMapPalette
extends Resource
## 星图绘制样式：连线、节点标签、状态描边、交互反馈、区域标题与字体。
## 默认值与抽取前的硬编码表现一致；未指定时视图使用一份默认实例。
## 透明色（alpha = 0）的描边 / 光晕项表示不绘制。

@export_group("字体")
## 指定字体；为空时按 use_theme_font 决定。
@export var font: Font
## 为 true 时使用星图视图所在主题的默认字体；为 false 且 font 为空时用 ThemeDB.fallback_font。
@export var use_theme_font := false
@export_range(6, 48, 1) var label_font_size := 13
@export_range(6, 48, 1) var current_font_size := 8
@export_range(6, 48, 1) var region_title_font_size := 15
@export_range(6, 48, 1) var region_subtitle_font_size := 9

@export_group("标签")
@export var label_color := Color("b9b8a5")
## 选中或悬停时的标签色，同时用作下划线颜色。
@export var label_active_color := Color("eee2c6")
## 当前节点书签与文字颜色。
@export var current_color := Color("dcc185")
@export var current_text := "HERE"

@export_group("连线")
@export var link_color := Color(0.68, 0.70, 0.57, 0.28)
@export var link_highlight_color := Color(0.82, 0.76, 0.57, 0.8)
## 任一端为锁定状态的连线颜色；alpha = 0 时沿用 link_color。
@export var link_locked_color := Color(0, 0, 0, 0)
@export var link_width := 1.0
@export var link_highlight_width := 1.4
## 选中节点到小面板的引线颜色。
@export var leader_line_color := Color(0.78, 0.74, 0.57, 0.4)

@export_group("交互反馈")
## 选中 / 悬停时是否画下划线。
@export var underline := true
## 悬停与选中时节点外观的放大倍数（1 = 不放大）。
@export_range(0.5, 2.0, 0.01) var hover_scale := 1.0
@export_range(0.5, 2.0, 0.01) var selected_scale := 1.0
## 放大过渡速度（每秒趋近系数）；0 表示立即到位。
@export_range(0.0, 60.0, 0.1) var emphasis_speed := 14.0
## 悬停 / 选中的柔光颜色；alpha = 0 时不绘制。
@export var halo_color := Color(0, 0, 0, 0)
## 柔光半径，相对节点外观的半对角线。
@export_range(0.5, 4.0, 0.01) var halo_radius := 1.6
## 选中描边颜色；alpha = 0 时不绘制。
@export var selected_ring_color := Color(0, 0, 0, 0)
@export var selected_ring_width := 2.0

@export_group("节点状态")
## 各状态的外观调制（作用于节点外观与标签）。
@export var available_modulate := Color.WHITE
@export var completed_modulate := Color.WHITE
@export var locked_modulate := Color.WHITE
## 各状态的标签色；alpha = 0 时沿用 label_color。
@export var available_label_color := Color(0, 0, 0, 0)
@export var completed_label_color := Color(0, 0, 0, 0)
@export var locked_label_color := Color(0, 0, 0, 0)
## 可进入节点的状态描边；alpha = 0 时不绘制。
@export var available_ring_color := Color(0, 0, 0, 0)
@export var state_ring_width := 1.0
## 已完成节点的角标颜色；alpha = 0 时不绘制。
@export var completed_badge_color := Color(0, 0, 0, 0)
## 已完成角标内的勾线颜色。
@export var completed_badge_ink := Color(0, 0, 0, 1)
## 锁定节点的锁形角标颜色；alpha = 0 时不绘制。
@export var locked_badge_color := Color(0, 0, 0, 0)
## 当前节点的状态描边；alpha = 0 时不绘制。
@export var current_ring_color := Color(0, 0, 0, 0)

@export_group("区域")
## 为 true 时区域标题使用 region_title_color，否则沿用区域自身的 tint。
@export var override_region_title_color := false
@export var region_title_color := Color(1, 1, 1, 0.7)

@export_group("内置外观")
## 内置剪影的暗部颜色。
@export var glyph_dark_color := Color("292b25")


static var _default: StarMapPalette


## 未配置时共享的默认样式（即抽取前的硬编码表现）。
static func get_default() -> StarMapPalette:
	if _default == null:
		_default = StarMapPalette.new()
	return _default


## 按配置解析绘制字体；context 为可取主题字体的控件（可为空）。
func resolve_font(context: Control) -> Font:
	if font != null:
		return font
	if use_theme_font and context != null:
		return context.get_theme_default_font()
	return ThemeDB.fallback_font
