extends Control
## 通用 UI 手动演示台（场景组装版）：根场景只负责页面管理——左侧 SideBarPanel
## 抽屉内的导航按钮互斥切换十个演示页（贴左缘、悬停展开、移开收起），R 重置
## 当前页（各页覆写 reset_page() 恢复初始状态），Esc 退出。
## 十个演示页各自是独立子场景（pages/page_*.tscn），页面脚本继承
## UIShowcasePage，负责本页的运行时接线（工具栏信号、InputMap 动作注册）
## 与初始状态快照；页面常驻场景树、切页只切可见性，想学习某个组件的
## 标准装配，打开对应单页场景即可。
## 覆盖快捷系（QuickDrag / QuickPopOut / QuickShow / QuickConstraints /
## QuickZoom / QuickRotate / QuickHost）与面板系（PocketDrawerPanel / SideBarPanel / ZoomPanel）。
## 运行：project_run(mode="custom", scene="res://addons/gdbase/ui/examples/ui_showcase/ui_showcase_sandbox.tscn")

@onready var _pages: Array[UIShowcasePage] = [
	%PageQuickDrag, %PageQuickPopOut, %PageQuickShow, %PageQuickConstraints,
	%PagePocketDrawer, %PageSideBar, %PageZoomPanel, %PageQuickZoom,
	%PageQuickRotate, %PageQuickHost,
]
@onready var _nav_buttons: Array[Button] = [
	%NavQuickDrag, %NavQuickPopOut, %NavQuickShow, %NavQuickConstraints,
	%NavPocketDrawer, %NavSideBar, %NavZoomPanel, %NavQuickZoom,
	%NavQuickRotate, %NavQuickHost,
]

var _current_page := -1


func _ready() -> void:
	_show_page(0)


## R 重置当前演示页（恢复初始状态），Esc 退出。
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				get_viewport().set_input_as_handled()
				if _current_page >= 0:
					_pages[_current_page].reset_page()
			KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				get_tree().quit()


#region 页面切换

func _on_nav_quick_drag_pressed() -> void:
	_show_page(0)


func _on_nav_quick_pop_out_pressed() -> void:
	_show_page(1)


func _on_nav_quick_show_pressed() -> void:
	_show_page(2)


func _on_nav_quick_constraints_pressed() -> void:
	_show_page(3)


func _on_nav_pocket_drawer_pressed() -> void:
	_show_page(4)


func _on_nav_side_bar_pressed() -> void:
	_show_page(5)


func _on_nav_zoom_panel_pressed() -> void:
	_show_page(6)


func _on_nav_quick_zoom_pressed() -> void:
	_show_page(7)


func _on_nav_quick_rotate_pressed() -> void:
	_show_page(8)


func _on_nav_quick_host_pressed() -> void:
	_show_page(9)


## 互斥显示十个页面（页面常驻，切页只切可见性）。
func _show_page(index: int) -> void:
	_current_page = index
	for page_index in _pages.size():
		_pages[page_index].visible = page_index == index
	for button_index in _nav_buttons.size():
		var button := _nav_buttons[button_index]
		button.set_pressed_no_signal(button_index == index)

#endregion
