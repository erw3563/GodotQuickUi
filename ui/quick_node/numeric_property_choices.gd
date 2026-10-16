@tool
class_name NumericPropertyChoices
extends RefCounted
## 为数值观察器提供共享的只读 Inspector 属性反射。
static func list_properties(target: Variant, include_builtin: bool = false) -> Array[StringName]:
	var names: Array[StringName] = []
	if not is_instance_valid(target):
		return names
	var script := target.get_script() as Script
	var properties: Array[Dictionary] = []
	if include_builtin:
		properties = target.get_property_list()
	elif script != null:
		properties = script.get_script_property_list()
	for info in properties:
		if int(info.type) in [TYPE_INT, TYPE_FLOAT] and (int(info.usage) & PROPERTY_USAGE_EDITOR) != 0:
			var key := StringName(info.name)
			if not names.has(key):
				names.append(key)
	return names

static func choices(target: Variant, include_builtin: bool, selected: String) -> PackedStringArray:
	var names := PackedStringArray(list_properties(target, include_builtin))
	if not selected.is_empty() and not names.has(selected):
		names.append(selected)
	return names
