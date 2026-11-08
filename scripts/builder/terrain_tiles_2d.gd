extends RefCounted
const Rotation=preload("res://scripts/iso_tile_rotation.gd")
static var images: Dictionary={}
static var cache: Dictionary={}
static func update_outside(outside: TileMapLayer,ground: TileMapLayer,area: Rect2i) -> void:
	outside.tile_set=ground.tile_set; outside.position=ground.position; outside.z_index=-6; outside.collision_enabled=false
	var keep: Dictionary={}
	for cell in ground.get_used_cells():
		if area.has_point(cell): continue
		keep[cell]=true; var source: int=ground.get_cell_source_id(cell); var atlas: Vector2i=ground.get_cell_atlas_coords(cell); var alternative: int=ground.get_cell_alternative_tile(cell)
		if outside.get_cell_source_id(cell)!=source or outside.get_cell_atlas_coords(cell)!=atlas or outside.get_cell_alternative_tile(cell)!=alternative: outside.set_cell(cell,source,atlas,alternative)
	for cell in outside.get_used_cells():
		if not keep.has(cell): outside.erase_cell(cell)
static func descriptions(ground: TileMapLayer,records: Dictionary={}) -> Dictionary:
	var result: Dictionary={}
	for cell in ground.get_used_cells():
		var source: TileSetAtlasSource=ground.tile_set.get_source(ground.get_cell_source_id(cell)); var atlas: Vector2i=ground.get_cell_atlas_coords(cell)
		var count: int=maxi(1,source.get_tile_animation_frames_count(atlas)); var regions: Array[Rect2i]=[]; var durations: Array[float]=[]
		for frame in count:
			regions.append(source.get_tile_texture_region(atlas,frame)); durations.append(maxf(.001,source.get_tile_animation_frame_duration(atlas,frame)))
		var tile: Dictionary=records.get(cell,{})
		var direction: String="SE" if tile.has("family") else tile.get("direction",Rotation.DIRECTIONS[posmod(ground.get_cell_alternative_tile(cell),4)])
		result[cell]={"texture":source.texture,"regions":regions,"durations":durations,"speed":source.get_tile_animation_speed(atlas),"direction":direction,"family":tile.get("family","")}
	return result
static func textures(description: Dictionary) -> Array[Texture2D]:
	var identity: int=hash([description["texture"].get_instance_id(),description["regions"],description["direction"]])
	if cache.has(identity): return cache[identity]
	var source_id: int=description["texture"].get_instance_id()
	if not images.has(source_id):
		if images.size()>=8: images.erase(images.keys()[0])
		var raw: Image=description["texture"].get_image()
		if raw.is_compressed(): raw.decompress()
		images[source_id]=raw
	var result: Array[Texture2D]=[]; var angle: float=deg_to_rad(Rotation.degrees(description["direction"])); var cosine: float=cos(angle); var sine: float=sin(angle)
	for region in description["regions"]:
		var tile: Image=images[source_id].get_region(region); var size:=Vector2i(tile.get_width(),tile.get_height()); var image:=Image.create(size.x,size.y,false,Image.FORMAT_RGBA8); var middle:=Vector2(size)*.5; var ratio: float=float(size.x)/size.y
		for x in size.x:
			for y in size.y:
				var point:=Vector2(x+.5,y+.5)-middle; var from:=Vector2(cosine*point.x+sine*point.y*ratio,-sine*point.x/ratio+cosine*point.y)+middle
				if from.x<0 or from.y<0 or from.x>=size.x or from.y>=size.y: image.set_pixel(x,y,Color.TRANSPARENT)
				else: image.set_pixel(x,y,tile.get_pixel(clampi(floori(from.x),0,size.x-1),clampi(floori(from.y),0,size.y-1)))
		result.append(ImageTexture.create_from_image(image))
	if cache.size()>=512: cache.erase(cache.keys()[0])
	cache[identity]=result; return result
