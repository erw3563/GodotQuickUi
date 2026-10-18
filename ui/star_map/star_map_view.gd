class_name StarMapView
extends Control
## Presents scene-authored nodes, map navigation and independent detail content slots.
signal star_selected(star: StarMapStar)
signal detail_requested(star: StarMapStar, content_slot: Control)
signal drag_finished(star: StarMapStar)

@export var layout_settings: StarMapLayout
@export var edges: Array[Vector2i] = []
@export var current_star_index := 0
@export_range(0.35, 2.0) var minimum_zoom := 0.55
@export_range(0.35, 3.0) var maximum_zoom := 1.45
@export var focus_speed := 7.0
@export var drag_threshold := 7.0
@export var region_follow_speed := 5.0
## 绘制样式（连线、标签、状态、字体等）；为空时使用默认样式。
@export var palette: StarMapPalette
## 小面板与选中节点之间的水平间距（像素）。
@export var small_panel_gap := 30.0
@export_group("面板演出")
## 可选的小面板 / 详情面板显隐演出宿主（QuickUiAnimHost）。未设置时直接 show / hide。
@export_node_path("QuickUiAnimHost") var small_panel_show_host: NodePath
@export_node_path("QuickUiAnimHost") var small_panel_hide_host: NodePath
@export_node_path("QuickUiAnimHost") var large_panel_show_host: NodePath
@export_node_path("QuickUiAnimHost") var large_panel_hide_host: NodePath
@export_group("")
var layout: StarMapLayout
var stars: Array[StarMapStar] = []
var selected := -1
var zoom_level := 0.85
var camera_center := Vector2.ZERO
var focus_index := -1
var hover_index := -1
var gesture := ""
var _gesture_serial := 0
var press_point := Vector2.ZERO
var previous_point := Vector2.ZERO
var press_index := -1
var drag_offset := Vector2.ZERO
var moved := false
var large_open := false
var initial_positions: Array[Vector2] = []
var _focus_window: Window
@onready var world: Node2D = $World
@onready var small_panel: Panel = $SmallPanel
@onready var large_panel: Panel = $LargePanel

func _enter_tree() -> void:
	_focus_window = get_window()
	if not _focus_window.focus_exited.is_connected(cancel_gesture):
		_focus_window.focus_exited.connect(cancel_gesture)

func _exit_tree() -> void:
	cancel_gesture()
	if is_instance_valid(_focus_window) and _focus_window.focus_exited.is_connected(cancel_gesture):
		_focus_window.focus_exited.disconnect(cancel_gesture)
	_focus_window = null

func _ready() -> void:
	for child in $World/Stars.get_children():
		if child is StarMapStar:
			if stars.size() >= StarMapLayout.MAX_NODES:
				child.hide()
				push_warning("StarMapView supports at most 128 stars; excess authored stars are hidden.")
				continue
			stars.append(child)
			initial_positions.append(child.position)
	layout = layout_settings.duplicate(true) if layout_settings != null else StarMapLayout.new()
	layout.configure(initial_positions, edges)
	$SmallPanel.gui_input.connect(_panel_input)
	$SmallPanel/Expand.pressed.connect(open_details)
	$SmallPanel/Close.pressed.connect(clear_selection)
	$LargePanel/Close.pressed.connect(close_details)
	$HUD/Return.pressed.connect(return_to_current)
	$HUD/Overview.pressed.connect(show_overview)
	# 缩放按钮与倍率显示可选：场景删掉后仍可用滚轮缩放。
	var zoom_in := get_node_or_null("HUD/ZoomIn") as BaseButton
	if zoom_in != null: zoom_in.pressed.connect(func(): change_zoom(1.14, size * 0.5))
	var zoom_out := get_node_or_null("HUD/ZoomOut") as BaseButton
	if zoom_out != null: zoom_out.pressed.connect(func(): change_zoom(1.0 / 1.14, size * 0.5))
	gui_input.connect(_map_input)
	visibility_changed.connect(func():
		if not is_visible_in_tree(): cancel_gesture())
	show_overview()
	_sync_visuals(1.0)

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	layout.step(delta)
	if focus_index >= 0 and focus_index < stars.size():
		camera_center = camera_center.lerp(layout.positions[focus_index], 1.0 - exp(-focus_speed * minf(delta, 0.1)))
	world.position = size * 0.5 - camera_center * zoom_level
	world.scale = Vector2.ONE * zoom_level
	_sync_visuals(delta)
	queue_redraw()

## 当前生效的绘制样式。
func get_palette() -> StarMapPalette:
	return palette if palette != null else StarMapPalette.get_default()

## 节点是否处于锁定状态（供连线等绘制查询）。
func is_star_locked(index: int) -> bool:
	return index >= 0 and index < stars.size() and stars[index].status == StarMapStar.Status.LOCKED

func _sync_visuals(delta: float) -> void:
	for i in stars.size():
		stars[i].palette = palette
		stars[i].font_context = self
		stars[i].position = layout.positions[i]
		stars[i].selected = i == selected
		stars[i].current = i == current_star_index
		stars[i].hovered = i == hover_index
		stars[i].view_zoom = zoom_level
		stars[i].sync_presentation()
	for region in $World/Regions.get_children():
		var center := Vector2.ZERO
		var count := 0
		for i in stars.size():
			if stars[i].region_id == region.region_id:
				center += layout.positions[i]
				count += 1
		region.view_zoom = zoom_level
		region.palette = palette
		region.font_context = self
		region.queue_redraw()
		region.visible = count > 0
		if count > 0:
			region.target_centroid = center / float(count)
			region.position = region.position.lerp(region.target_centroid, 1.0 - exp(-region_follow_speed * delta)) if region_follow_speed > 0.0 else region.target_centroid
	$World/Links.queue_redraw()
	if selected >= 0:
		var anchor := world_to_screen(layout.positions[selected])
		var panel_pos := anchor + Vector2(small_panel_gap, -small_panel.size.y * 0.45)
		if panel_pos.x + small_panel.size.x > size.x - 24: panel_pos.x = anchor.x - small_panel.size.x - small_panel_gap
		panel_pos.y = clampf(panel_pos.y, 114, maxf(114, size.y - small_panel.size.y - 72))
		small_panel.position = panel_pos
		$SmallPanel/Title.text = stars[selected].title
		$SmallPanel/Meta.text = "%s   /   %s" % [stars[selected].region_id.to_upper(), stars[selected].category.to_upper()]
	var zoom_value := get_node_or_null("HUD/ZoomValue") as Label
	if zoom_value != null: zoom_value.text = "%d%%" % roundi(zoom_level * 100.0)

func world_to_screen(point: Vector2) -> Vector2:
	return size * 0.5 + (point - camera_center) * zoom_level

func screen_to_world(point: Vector2) -> Vector2:
	return camera_center + (point - size * 0.5) / zoom_level

func pick_star(point: Vector2) -> int:
	var best := -1
	var distance := 24.0
	for i in stars.size():
		var d := point.distance_to(world_to_screen(layout.positions[i]))
		if d < distance:
			distance = d
			best = i
	return best

func select_star(index: int, focus := true) -> void:
	if index < 0 or index >= stars.size(): return
	selected = index
	_present(small_panel, true, small_panel_show_host, small_panel_hide_host)
	close_details()
	if focus: focus_index = index
	star_selected.emit(stars[index])

func clear_selection() -> void:
	cancel_gesture()
	selected = -1
	focus_index = -1
	_present(small_panel, false, small_panel_show_host, small_panel_hide_host)
	close_details()

func open_details() -> void:
	# The small-panel expand button opens the selected node’s detail slot.
	if selected < 0: return
	cancel_gesture()
	large_open = true
	_present(large_panel, true, large_panel_show_host, large_panel_hide_host)
	$LargePanel/Title.text = stars[selected].title
	detail_requested.emit(stars[selected], $LargePanel/ContentSlot)

func close_details() -> void:
	large_open = false
	_present(large_panel, false, large_panel_show_host, large_panel_hide_host)

## 面板显隐：配置了演出宿主时交给宿主播放，否则直接 show / hide。
## 显示宿主负责从隐藏态入场，隐藏宿主负责收起并最终隐藏；每次先取消另一侧，
## 中途反向从当前表现接着播放。
func _present(panel: Control, shown: bool, show_host_path: NodePath, hide_host_path: NodePath) -> void:
	var show_host := get_node_or_null(show_host_path) as QuickUiAnimHost if not show_host_path.is_empty() else null
	var hide_host := get_node_or_null(hide_host_path) as QuickUiAnimHost if not hide_host_path.is_empty() else null
	var host := show_host if shown else hide_host
	var other := hide_host if shown else show_host
	if other != null: other.cancel()
	if host == null:
		panel.visible = shown
		return
	if shown and panel.visible and panel.scale.is_equal_approx(Vector2.ONE):
		return
	if not shown and not panel.visible:
		return
	host.play()

func return_to_current() -> void:
	cancel_gesture()
	if current_star_index >= 0 and current_star_index < stars.size():
		focus_index = current_star_index

func show_overview() -> void:
	cancel_gesture()
	focus_index = -1
	if layout == null or layout.positions.is_empty(): return
	var bounds := Rect2(layout.positions[0], Vector2.ZERO)
	for point in layout.positions: bounds = bounds.expand(point)
	camera_center = bounds.get_center()
	zoom_level = clampf(minf((size.x - 210) / maxf(1, bounds.size.x), (size.y - 250) / maxf(1, bounds.size.y)), minimum_zoom, 0.95)

func change_zoom(factor: float, anchor: Vector2) -> void:
	if not gesture.is_empty(): cancel_gesture()
	var before := screen_to_world(anchor)
	zoom_level = clampf(zoom_level * factor, minimum_zoom, maximum_zoom)
	camera_center = before - (anchor - size * 0.5) / zoom_level
	focus_index = -1

func _map_input(event: InputEvent) -> void:
	if large_open: return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			change_zoom(1.1, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			change_zoom(1 / 1.1, event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed: _begin_gesture(event.position, pick_star(event.position), "map")
			else: _end_gesture()
	elif event is InputEventMouseMotion:
		hover_index = pick_star(event.position)
		_motion(event.position)

func _panel_input(event: InputEvent) -> void:
	if large_open: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed: _begin_gesture(get_global_transform_with_canvas().affine_inverse() * event.global_position, selected, "panel")
		else: _end_gesture()
	elif event is InputEventMouseMotion:
		_motion(get_global_transform_with_canvas().affine_inverse() * event.global_position)

func _begin_gesture(point: Vector2, index: int, source: String) -> void:
	cancel_gesture()
	focus_index = -1 # Freeze easing before capturing the pointer-to-star offset.
	gesture = source
	press_point = point
	previous_point = point
	press_index = index
	moved = false
	if index >= 0: drag_offset = layout.positions[index] - screen_to_world(point)

func _motion(point: Vector2) -> void:
	if gesture.is_empty(): return
	if not moved and point.distance_to(press_point) >= drag_threshold:
		moved = true
		focus_index = -1
	if moved:
		if press_index >= 0:
			layout.pinned[press_index] = screen_to_world(point) + drag_offset
		else:
			camera_center -= (point - previous_point) / zoom_level
	previous_point = point

func _end_gesture() -> void:
	if gesture.is_empty(): return
	var index := press_index
	var was_moved := moved
	var source := gesture
	if was_moved and index >= 0:
		layout.step(0.0) # Sanitize/apply last pin even for motion+release in one frame.
	cancel_gesture()
	if was_moved and index >= 0: drag_finished.emit(stars[index])
	elif not was_moved and source == "map" and index >= 0: select_star(index)

func cancel_gesture() -> void:
	_gesture_serial += 1
	if layout != null and press_index >= 0: layout.pinned.erase(press_index)
	gesture = ""
	press_index = -1
	moved = false

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_gesture()
		if large_open: close_details()
		else: clear_selection()
	# Deferred release gives native GUI handling priority and respects capture generations.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var serial := _gesture_serial
		(func():
			if serial == _gesture_serial: _end_gesture()
		).call_deferred()

func _draw() -> void:
	if selected >= 0 and small_panel.visible:
		var a := world_to_screen(layout.positions[selected])
		var b := small_panel.position + Vector2(0 if small_panel.position.x > a.x else small_panel.size.x, 48)
		draw_line(a, b, get_palette().leader_line_color, 1.0, true)
