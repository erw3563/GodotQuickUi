@tool
## Pixel Composer 风格的 MapPath 内部 Add；输出 RGBA 再以普通混合显示。
## 每个实例独占透明画布，父节点颜色调制仅作用于最终显示。
class_name MapPathAddMesh2D
extends MapPathMesh2D

## 每个输出像素覆盖的本地尺寸；1 为原分辨率，越大像素阶梯越明显。
@export_range(1, 32, 1) var pixel_size: int = 1:
	set(value):
		pixel_size = clampi(value, 1, 32)
		queue_redraw()

var _surface: SubViewport
var _surface_mesh: MeshInstance2D
var _output: Sprite2D
var _surface_rect := Rect2()
var _sync_queued := false
var _uv_material: ShaderMaterial
var _flow_offset := Vector2.ZERO

@export_group("UV 流动")
## 起始采样偏移，U 沿路径，V 跨路径宽度。
@export var uv_offset := Vector2.ZERO:
	set(value):
		uv_offset = value
		_sync_uv_parameters()
## 每秒偏移的贴图周期数；正数使图案朝对应 UV 的负方向移动。
@export var uv_flow_speed := Vector2(0.25, 0.0)
@export var uv_flow_enabled := false
## 编辑器显式预览；运行时仍由 uv_flow_enabled 控制。
@export var preview_uv_flow := false
@export var uv_repeat_u := true:
	set(value):
		uv_repeat_u = value
		_sync_uv_parameters()
@export var uv_repeat_v := false:
	set(value):
		uv_repeat_v = value
		_sync_uv_parameters()
@export_tool_button("重置流动") var reset_flow_button: Callable = reset_uv_flow

func _process(delta: float) -> void:
	if uv_flow_enabled and (not Engine.is_editor_hint() or preview_uv_flow):
		advance_uv_flow(delta)

## 手动推进用于外部时间轴；使用时关闭自动流动，避免重复推进。
func advance_uv_flow(delta: float) -> void:
	if not is_finite(delta) or delta < 0.0:
		return
	_flow_offset += uv_flow_speed * delta
	if uv_repeat_u:
		_flow_offset.x = fposmod(_flow_offset.x, 1.0)
	if uv_repeat_v:
		_flow_offset.y = fposmod(_flow_offset.y, 1.0)
	_sync_uv_parameters()

## 暂停用 uv_flow_enabled=false；重播前调用本方法回到起始偏移。
func reset_uv_flow() -> void:
	_flow_offset = Vector2.ZERO
	_sync_uv_parameters()

func get_uv_flow_offset() -> Vector2:
	return uv_offset + _flow_offset

func _sync_uv_parameters() -> void:
	if not is_instance_valid(_uv_material):
		return
	_uv_material.set_shader_parameter("uv_offset", get_uv_flow_offset())
	_uv_material.set_shader_parameter("repeat_u", uv_repeat_u)
	_uv_material.set_shader_parameter("repeat_v", uv_repeat_v)

func _draw() -> void:
	# 基类的贴图 setter / 网格重建均会触发重绘。
	if not _sync_queued:
		_sync_queued = true
		_sync_surface.call_deferred()

func _sync_surface() -> void:
	_sync_queued = false
	if not is_inside_tree():
		return
	var mesh := get_build_mesh()
	if texture == null or mesh == null or mesh.get_surface_count() == 0:
		if is_instance_valid(_output):
			_output.visible = false
			_surface_mesh.mesh = null
			_surface.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if not is_instance_valid(_surface):
		_create_surface()
	var bounds := mesh.get_aabb()
	# 对齐本地原点的固定像素格，避免包围盒变化时采样网格漂移。
	var start := (Vector2(bounds.position.x, bounds.position.y) / pixel_size).floor() - Vector2.ONE
	var end := (Vector2(bounds.end.x, bounds.end.y) / pixel_size).ceil() + Vector2.ONE
	var render_size := Vector2i(end - start)
	start *= pixel_size
	end *= pixel_size
	_surface_rect = Rect2(start, end - start)
	# 限制实际渲染分辨率，避免无界显存分配。
	if render_size.x > 4096 or render_size.y > 4096:
		_output.visible = false
		_surface.render_target_update_mode = SubViewport.UPDATE_DISABLED
		push_warning("MapPath Add 画布超过 4096 像素，请缩小路径范围。")
		return
	_surface.size = render_size
	_surface_mesh.position = -start / pixel_size
	_surface_mesh.scale = Vector2.ONE / pixel_size
	_surface_mesh.mesh = mesh
	_surface_mesh.texture = texture
	# UV 平铺范围由网格决定；采样循环按轴交给 Shader，非循环轴钳制边缘。
	_surface_mesh.texture_repeat = TEXTURE_REPEAT_DISABLED
	_output.position = start
	_output.scale = Vector2.ONE * pixel_size
	_output.visible = true
	_surface.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE

func _create_surface() -> void:
	_surface = SubViewport.new()
	_surface.name = "AddSurface"
	_surface.transparent_bg = true
	_surface.disable_3d = true
	_surface.world_2d = World2D.new()
	_surface.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_surface.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_surface, false, Node.INTERNAL_MODE_BACK)
	_surface_mesh = MeshInstance2D.new()
	_uv_material = ShaderMaterial.new()
	_uv_material.shader = load("res://addons/gdbase/ui/procedural_animation/map_path_add_uv.gdshader")
	_surface_mesh.material = _uv_material
	_sync_uv_parameters()
	_surface.add_child(_surface_mesh)
	_output = Sprite2D.new()
	_output.name = "AddOutput"
	_output.centered = false
	_output.texture_filter = TEXTURE_FILTER_NEAREST
	_output.texture = _surface.get_texture()
	var output_material := CanvasItemMaterial.new()
	output_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_output.material = output_material
	add_child(_output, false, Node.INTERNAL_MODE_BACK)

## 原始累加图：RGB 累加 src.rgb * src.a，Alpha 累加 src.a²（LDR 钳制）。
func get_add_texture() -> Texture2D:
	return _surface.get_texture() if is_instance_valid(_surface) else null

func get_add_rect() -> Rect2:
	return _surface_rect
