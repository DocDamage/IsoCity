@tool
extends Button

var scene_path: String = ""

func _get_drag_data(_at_position: Vector2) -> Variant:
	if scene_path.is_empty():
		return null
		
	var preview := TextureRect.new()
	preview.texture = icon
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.custom_minimum_size = Vector2(48, 48)
	preview.modulate = Color(1, 1, 1, 0.85)
	set_drag_preview(preview)
	
	# Godot 2D & 3D Viewport native drag & drop accepts {"type": "files", "files": [path]}
	return {
		"type": "files",
		"files": [scene_path]
	}

