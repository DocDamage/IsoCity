extends RefCounted
static var images: Dictionary={}
static var projected: Dictionary={}
static var image_bytes: int=0
static var projected_bytes: int=0

static func source_image(texture: Texture2D) -> Image:
	var key: int=texture.get_instance_id()
	if images.has(key) and images[key]["source"].get_ref()==texture: return images[key]["image"]
	var picture: Image=texture.get_image()
	if picture.is_compressed(): picture.decompress()
	var bytes: int=picture.get_data_size()
	while not images.is_empty() and image_bytes+bytes>64*1024*1024:
		var oldest: Variant=images.keys()[0]; image_bytes-=images[oldest]["bytes"]; images.erase(oldest)
	if bytes<=64*1024*1024:
		images[key]={"source":weakref(texture),"image":picture,"bytes":bytes}; image_bytes+=bytes
	return picture

# Bake the Sprite2D transform, never its source file. This keeps sprite cards in
# 3D consistent with calibrated art and per-instance pixel painting in 2D.
static func frame(sprite: Sprite2D) -> Dictionary:
	var key: String=str(sprite.texture.get_instance_id())+":"+str(sprite.frame)+":"+str(sprite.transform)+":"+str(sprite.get_rect())
	if projected.has(key) and projected[key]["source"].get_ref()==sprite.texture: return projected[key]["result"]
	var result: Dictionary=make_frame(sprite); var bytes: int=result["texture"].get_width()*result["texture"].get_height()*4
	while not projected.is_empty() and projected_bytes+bytes>32*1024*1024:
		var oldest: Variant=projected.keys()[0]; projected_bytes-=projected[oldest]["bytes"]; projected.erase(oldest)
	if bytes<=32*1024*1024:
		projected[key]={"source":weakref(sprite.texture),"result":result,"bytes":bytes}; projected_bytes+=bytes
	return result

static func make_frame(sprite: Sprite2D) -> Dictionary:
	var rect: Rect2 = sprite.get_rect()
	var transform: Transform2D = sprite.transform
	if transform.is_equal_approx(Transform2D.IDENTITY):
		# 3D materials sample the underlying RID, so an AtlasTexture does not crop their UVs.
		var picture: Image=source_image(sprite.texture)
		var area:=Rect2i(Vector2i(Vector2(sprite.frame_coords)*rect.size),Vector2i(rect.size))
		return {"texture":ImageTexture.create_from_image(picture.get_region(area)),"rect":rect}
	var corners: Array[Vector2] = [rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y)]
	var projected := Rect2(transform * corners[0], Vector2.ZERO)
	for corner in corners: projected = projected.expand(transform * corner)
	var start: Vector2 = projected.position.floor()
	var size_value := Vector2i((projected.end.ceil() - start).max(Vector2.ONE))
	var image := Image.create(size_value.x, size_value.y, false, Image.FORMAT_RGBA8)
	var source: Image = source_image(sprite.texture)
	var inverse: Transform2D = transform.affine_inverse()
	var offset: Vector2 = Vector2(sprite.frame_coords) * rect.size
	for y in size_value.y:
		for x in size_value.x:
			var point: Vector2 = inverse * (start + Vector2(x, y) + Vector2.ONE * 0.5)
			if rect.has_point(point):
				var pixel := Vector2i((point - rect.position + offset).floor())
				if pixel.x >= 0 and pixel.y >= 0 and pixel.x < source.get_width() and pixel.y < source.get_height():
					image.set_pixel(x, y, source.get_pixelv(pixel))
	return {"texture": ImageTexture.create_from_image(image), "rect": Rect2(start, Vector2(size_value))}
