extends ShowcasePage
## 演示页·鼠标跟随定位：点「打开菜单」在鼠标位置弹出小菜单——QuickMousePlace
## 负责定位（自动避免超出屏幕、可强制顶点对齐鼠标），定位后联动 QuickShow
## 显形；按 Q 收起——收起用的 InputMap 动作 demo_quick_show_hide 由本页
## _ready 注册（hide_action 赋值不校验动作存在，注册先于输入处理即可）。

func _ready() -> void:
	_ensure_global_actions()
	%OpenButton.pressed.connect((%Placer as QuickMousePlace).place_at_mouse)


## 注册 Q 键收起动作（QuickShow.hide_action 引用）。
func _ensure_global_actions() -> void:
	if not InputMap.has_action("demo_quick_show_hide"):
		InputMap.add_action("demo_quick_show_hide")
		var key := InputEventKey.new()
		key.keycode = KEY_Q
		InputMap.action_add_event("demo_quick_show_hide", key)


## 收起菜单。
func reset_page() -> void:
	(%Menu as Control).hide()
