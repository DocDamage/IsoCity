extends Button

var item_id: String = ""

func _get_drag_data(_at_position: Vector2) -> Variant:
	if item_id.is_empty():
		return null
		
	var preview := TextureRect.new()
	preview.texture = icon
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.custom_minimum_size = Vector2(48, 48)
	preview.modulate = Color(1, 1, 1, 0.8)
	set_drag_preview(preview)
	
	return {
		"type": "iso_item",
		"item_id": item_id
	}

