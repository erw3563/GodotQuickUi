extends ShowcasePage
## 演示页·鼠标跟随定位与显隐：点「打开菜单」经入场宿主播放一趟——QuickMousePlace
## 先把菜单定位到鼠标处（自动避免超出屏幕），QuickShow 随后淡入显形；按 Q 经离场
## 宿主播放目标为隐藏的 QuickShow 收起菜单——收起动作 demo_quick_show_hide 由本页
## _ready 注册，收起入口为页面按键处理（触发归调用方，演出件不自带输入处理）。

func _ready() -> void:
	_ensure_global_actions()


## 注册 Q 键收起动作（本页按键处理引用）。
func _ensure_global_actions() -> void:
	if not InputMap.has_action("demo_quick_show_hide"):
		InputMap.add_action("demo_quick_show_hide")
		var key := InputEventKey.new()
		key.keycode = KEY_Q
		InputMap.action_add_event("demo_quick_show_hide", key)


## 按键收起：经离场宿主播放目标为隐藏的显隐演出。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("demo_quick_show_hide"):
		get_viewport().set_input_as_handled()
		(%ExitHost as QuickUiAnimHost).play()


## 收起菜单（R 重置路径）。
func reset_page() -> void:
	(%ExitHost as QuickUiAnimHost).play()
