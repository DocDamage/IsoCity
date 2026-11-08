extends Control

@export var editor_path: NodePath
@onready var editor = get_node(editor_path)

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if data is Dictionary and data.get("type", "") == "iso_item":
		return true
	return false

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if data is Dictionary and data.get("type", "") == "iso_item":
		var item_id: String = data.get("item_id", "")
		if editor and editor.has_method("place_object_at"):
			editor.select_item(item_id)
			var tile: Vector2i = IsoMath.world_to_tile(editor.get_global_mouse_position(), editor.current_elevation)
			editor.place_object_at(tile, item_id)

