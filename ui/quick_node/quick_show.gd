class_name QuickShow
extends Node
## 显隐管理：显隐语义归本组件，配置了 [member popout] 时改由其入场 / 收起动画执行。
## show() 以控件当前位置为休息位飞入——定位归外部所有者（如 QuickMousePlace），
## 本组件只读位置服务动画，永不写位置。

@export var control: Control
## 开始时隐藏
@export var is_hide_in_ready: bool = true
## 触发隐藏的动作名称，为空时不响应按键
@export var hide_action: String:
	set(value):
		hide_action = value
		_update_input_process()
## 可选动画宿主：设置后显隐改由 pop_in / pop_out 执行
@export var popout: QuickPopOut

func _ready() -> void:
	if is_hide_in_ready:
		hide()
	_update_input_process()

func _unhandled_input(event: InputEvent) -> void:
	if hide_action != "" and event.is_action_pressed(hide_action):
		get_viewport().set_input_as_handled()
		hide()

## 按 hide_action 是否配置动态开关按键监听。
func _update_input_process() -> void:
	set_process_unhandled_input(not hide_action.is_empty())

## 在显隐与收起之间切换。
func change_visible() -> void:
	if control == null:
		return
	if control.visible:
		hide()
	else:
		show()

## 纯显形（不重定位）：挂动画宿主时以当前位置为休息位飞入。
func show() -> void:
	if control == null:
		return
	if popout != null:
		# 休息位跟随控件当前位置，入场动画从屏外飞向外部所有者摆好的落点。
		popout.capture_rest_position()
	_set_visible(true)

## 纯收起：只动 visible，不搬运控件位置。
func hide() -> void:
	_set_visible(false)

func _set_visible(shown: bool) -> void:
	if control == null:
		return
	if popout != null:
		if shown:
			popout.pop_in()
		else:
			popout.pop_out()
	elif shown:
		control.show()
	else:
		control.hide()
