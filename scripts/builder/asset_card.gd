extends Button

var asset_id: String
var preview_texture: Texture2D
var artwork: TextureRect
var caption: Label
var favorite_button: Button
var inspect_button: Button
var capability_note: Label

func reflow(thumbnail_size: int, text_scale: float = 1.0) -> void:
	if not is_instance_valid(artwork) or not is_instance_valid(caption) or not is_instance_valid(favorite_button): return
	var favorite_size: Vector2 = favorite_button.get_combined_minimum_size().max(Vector2(30,30))
	var inspect_size: Vector2 = inspect_button.get_combined_minimum_size().max(Vector2(30,30)) if is_instance_valid(inspect_button) else Vector2.ZERO
	var width: float = maxf(thumbnail_size, favorite_size.x + inspect_size.x + 12)
	var header: float = maxf(favorite_size.y, inspect_size.y) + 12
	var art_height: float = maxf(44, thumbnail_size - 28)
	var name_height: float = maxf(40, ceilf(3 * 12 * text_scale * 1.3))
	var capability_height: float=maxf(18,ceilf(12*text_scale*1.3)) if is_instance_valid(capability_note) else 0
	custom_minimum_size = Vector2(width, header + art_height + 8 + name_height + 8 + capability_height)
	favorite_button.position = Vector2(width - favorite_size.x - 4, 4); favorite_button.size = favorite_size
	if is_instance_valid(inspect_button): inspect_button.position = Vector2(4,4); inspect_button.size = inspect_size
	artwork.position = Vector2(10,header); artwork.size = Vector2(width - 20,art_height)
	caption.position = Vector2(8,header + art_height + 8); caption.size = Vector2(width - 16,name_height)
	caption.max_lines_visible = 3; caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if is_instance_valid(capability_note):
		capability_note.position=Vector2(8,caption.position.y+name_height+4);capability_note.size=Vector2(width-16,capability_height)

func _get_drag_data(_position: Vector2) -> Variant:
	var preview := TextureRect.new()
	preview.texture = preview_texture
	preview.custom_minimum_size = Vector2(96, 96)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	set_drag_preview(preview)
	return {"type": "builder_asset", "asset_id": asset_id}
