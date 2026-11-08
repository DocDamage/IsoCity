extends RefCounted

# Model thumbnails only. Flat sprite tiles are valid art and bypass this check.
# The library caches the resulting texture, so this never runs per frame.
static func meaningful(texture: Texture2D) -> bool:
	if not texture: return false
	var image: Image = texture.get_image()
	return meaningful_image(image)

static func meaningful_image(image: Image) -> bool:
	if image == null or image.is_empty(): return false
	if image.is_compressed() and image.decompress() != OK: return false
	# Native alpha counting preserves thin poles/hooks that a 32-pixel sampling
	# grid can miss entirely. Invisible RGB noise never counts as artwork.
	var mask:=BitMap.new();mask.create_from_image_alpha(image,8.0/255.0)
	var actual_visible: int=mask.get_true_bit_count()
	if actual_visible<16:return false
	if actual_visible<image.get_width()*image.get_height()*.98:return true
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	var visible: int = 0
	var colors: Dictionary={}
	for y in range(0, image.get_height(), maxi(1, image.get_height() / 32)):
		for x in range(0, image.get_width(), maxi(1, image.get_width() / 32)):
			var color: Color = image.get_pixel(x, y)
			if color.a <= 8.0 / 255.0: continue
			visible += 1
			var rgb := Vector3(color.r, color.g, color.b)
			low = low.min(rgb); high = high.max(rgb)
			var bucket:=Vector3i(int(color.r*255)/8,int(color.g*255)/8,int(color.b*255)/8)
			colors[bucket]=colors.get(bucket,0)+1
	if visible < 2: return false
	var span: Vector3 = high - low
	var dominant: int=0
	for count in colors.values():dominant=maxi(dominant,count)
	return maxf(span.x,maxf(span.y,span.z))>=8.0/255.0 and dominant<visible*.995

static func read_image(path: String) -> Image:
	if not FileAccess.file_exists(path):return null
	var result:=Image.new()
	# Corrupt user/source images are diagnostic input, not an engine failure.
	# The caller reports the returned failure; restore normal logging immediately.
	var logging: bool=Engine.print_error_messages;Engine.print_error_messages=false
	var error: Error=result.load(path)
	Engine.print_error_messages=logging
	return result if error==OK and not result.is_empty() else null

static func texture_file(path: String) -> Texture2D:
	var image: Image=read_image(path)
	return ImageTexture.create_from_image(image) if image else null

static func import_current(path: String) -> bool:
	if path.get_extension().to_lower() not in ["glb","gltf","png","jpg","jpeg","webp","svg","tga","bmp"]:return true
	var config:=ConfigFile.new()
	if not FileAccess.file_exists(path+".import") or config.load(path+".import")!=OK:return false
	var imported: Variant=config.get_value("remap","path","")
	if not imported is String or imported.is_empty() or not FileAccess.file_exists(imported):return false
	var md5: String=imported.get_basename()+".md5"
	return FileAccess.file_exists(md5) and ('source_md5="'+FileAccess.get_md5(path)+'"') in FileAccess.get_file_as_string(md5)
