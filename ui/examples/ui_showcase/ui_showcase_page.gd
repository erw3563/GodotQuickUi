class_name UIShowcasePage
extends Control
## UI 演示台页面基类：每个演示页是一个独立子场景（pages/page_*.tscn），
## 场景根挂一个继承本类的脚本，各自负责本页的运行时接线（工具栏按钮信号、
## InputMap 动作注册）与初始状态快照；根场景 ui_showcase_sandbox.tscn
## 只做页面管理（可见性互斥切换），经 reset_page() 驱动 R 重置。

## R 重置当前页（恢复初始状态：卡片归位、方向/贴边/原点/展开态回默认）：
## 默认无操作，需要恢复的页面覆写本方法。
func reset_page() -> void:
	pass
