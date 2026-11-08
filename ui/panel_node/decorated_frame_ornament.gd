@tool
class_name DecoratedFrameOrnament
extends Resource
## 固定原生尺寸的边框装饰。锚点采用边框矩形内的相对坐标。
@export var texture: Texture2D
@export var anchor := Vector2(0.5, 0.0)
@export var offset := Vector2.ZERO
