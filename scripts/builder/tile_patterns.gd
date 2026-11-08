extends RefCounted

static var cache: Dictionary = {}
const Families=preload("res://scripts/builder/terrain_family_plan.gd")
const CELL:=Vector2i(32,16)
static var family_samples: Dictionary={}
static var family_cache: Dictionary={}

static func sample_frames(id: String) -> Array[Image]:
	if family_samples.has(id): return family_samples[id]
	var config: Dictionary=Families.definitions()
	var definition: Array=config.get("samples",{}).get(id,[])
	if definition.size()<2: return []
	var animated: bool=definition.size()==3
	var atlas: Texture2D=load(config["animated_atlas"] if animated else config["atlas"])
	if not atlas: return []
	var image: Image=atlas.get_image()
	if image.is_compressed(): image.decompress()
	var result: Array[Image]=[]
	for frame in int(definition[2] if animated else 1):
		var region:=Rect2i(Vector2i(int(definition[0])+frame*CELL.x,int(definition[1])),CELL)
		if not Rect2i(Vector2i.ZERO,image.get_size()).encloses(region): return []
		result.append(image.get_region(region))
	family_samples[id]=result
	return result

static func family_key(variant: Dictionary) -> Array:
	var id: String=variant["family"]
	var mask: int=variant["mask"]
	return [id,mask,variant.get("inlets",0),int(variant.get("unsupported",0))&mask if id=="shore" else 0]

static func water_pixel(frame: Image,uv: Vector2) -> Color:
	var inside: Vector2=uv.clamp(Vector2.ONE*.12,Vector2.ONE*.88)
	var point:=Vector2(.5+(inside.x-inside.y)*.5,(inside.x+inside.y)*.5)
	return frame.get_pixelv(Vector2i((point*Vector2(CELL)).floor()))

static func family_pattern(variant: Dictionary) -> Dictionary:
	var key: Array=family_key(variant)
	if family_cache.has(key): return family_cache[key]
	if Families.piece(variant).is_empty(): return {}
	var id: String=variant["family"]
	var config: Dictionary=Families.profile(id)
	var grass: Array[Image]=sample_frames("grass")
	var base: Array[Image]=sample_frames({"shore":"water","path":"stone","cliff":"gravel"}[id])
	var sand: Array[Image]=[]
	if id=="shore": sand=sample_frames("sand")
	if grass.is_empty() or base.is_empty() or (id=="shore" and sand.is_empty()): return {}
	var atlas:=Image.create(CELL.x*base.size(),CELL.y,false,Image.FORMAT_RGBA8)
	var textures: Array[Texture2D]=[]
	var durations: Array[float]=[]
	for frame in base.size():
		var cell: Image=base[frame].duplicate()
		for y in CELL.y:
			for x in CELL.x:
				var pixel:=Vector2(x+.5,y+.5)/Vector2(CELL)
				var uv:=Vector2(pixel.y+pixel.x-.5,pixel.y-pixel.x+.5)
				var at:=Vector2i(x,y)
				var floor_color: Color=grass[0].get_pixelv(at)
				var color: Color=cell.get_pixelv(at)
				var distances: Array[float]=[uv.y,1.0-uv.x,1.0-uv.y,uv.x]
				var mask: int=variant["mask"]
				var joined: bool=false
				var padding: bool=true
				if id=="shore":
					# Keep the source rectangle. Fill its near-edge pixels only
					# where another water tile closes the same edge.
					for i in 4:
						if distances[i]<.095 and not (mask&(1<<i)): joined=true
						if distances[i]<0 and (distances[i]<-.052 or mask&(1<<i)): padding=false
				if color.a==0 and floor_color.a==0 and not (joined and padding): continue
				match id:
					"shore":
						var bank: float=INF
						var supported: int=mask&~int(variant.get("unsupported",0))
						for i in 4:
							if supported&(1<<i): bank=minf(bank,distances[i])
							if int(variant.get("inlets",0))&(1<<i):
								var j: int=(i+1)%4
								var corner: float=Vector2(distances[i],distances[j]).length()
								bank=minf(bank,corner*float(config["bank_width"])/float(config["inlet_radius"]))
						if bank<float(config["grass_width"]) and floor_color.a>0: color=floor_color
						elif bank<float(config["bank_width"]):
							var beach: Color=sand[0].get_pixelv(at)
							if beach.a>0: color=beach
						elif joined and padding: color=water_pixel(base[frame],uv)
					"path":
						var half: float=config["half_width"]
						var d: Vector2=(uv-Vector2.ONE*.5).abs()
						var inside: bool=d.x<=half and d.y<=half
						inside=inside or (d.x<=half and ((mask&1 and uv.y<.5) or (mask&4 and uv.y>.5)))
						inside=inside or (d.y<=half and ((mask&8 and uv.x<.5) or (mask&2 and uv.x>.5)))
						if not inside: color=floor_color
					"cliff":
						var drop: float=1.0
						for i in 4:
							if mask&(1<<i): drop=minf(drop,distances[i])
						color=Color(color.r,color.g,color.b,color.a).darkened(.32*(1.0-clampf(drop,0,1)))
				cell.set_pixelv(at,color)
		atlas.blit_rect(cell,Rect2i(Vector2i.ZERO,CELL),Vector2i(frame*CELL.x,0))
		textures.append(ImageTexture.create_from_image(cell))
		durations.append(1.0)
	var result: Dictionary={"atlas":ImageTexture.create_from_image(atlas),"textures":textures,"durations":durations,"speed":4.0}
	if family_cache.size()>=256: family_cache.erase(family_cache.keys()[0])
	family_cache[key]=result
	return result

static func from_asset(library: RefCounted, id: String, direction: String = "SE") -> Dictionary:
	if not library.assets.has(id) or not id.begins_with("2d:"): return {}
	var item: Dictionary = library.assets[id]["data"]
	var views: Dictionary = item.get("directions", {})
	if views.is_empty(): return {}
	var view: Dictionary = views.get(direction, views.get("SE", views.values()[0]))
	var file: String = view["file"]
	var path: String = "res://assets/" + file.trim_prefix("../../") if file.begins_with("../../") else "res://assets/pixel_isometric/" + file
	var texture: Texture2D = load(path)
	var area: Rect2=preload("res://scripts/sprite_view.gd").region(view,texture)
	var result: Dictionary = {"asset": id, "texture": path, "region": [int(area.position.x), int(area.position.y), int(view.get("frame_width", area.size.x)), int(view.get("frame_height", area.size.y))], "diamond": library.is_ground_tile(id) and item.get("ground_shape", "diamond") == "diamond", "scale": 1.0, "angle": 0.0, "offset": [0.0, 0.0], "projection": "artwork"}
	if result["diamond"] and view.has("alignment_base"):
		var base: Array = view["alignment_base"]
		var back := Vector2(base[0][0] + base[2][0] - base[1][0], base[0][1] + base[2][1] - base[1][1])
		result["basis"] = [back.x, back.y, base[2][0] - back.x, base[2][1] - back.y, base[0][0] - back.x, base[0][1] - back.y]
	return result

static func picture(pattern: Dictionary) -> Image:
	var key: String = pattern["texture"] + str(pattern["region"]) + str(pattern["diamond"]) + str(pattern.get("basis", []))
	if cache.has(key): return cache[key]["image"]
	var texture: Texture2D = load(pattern["texture"])
	if not texture: return null
	var source: Image = texture.get_image()
	var r: Array = pattern["region"]
	var region := Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
	if not Rect2i(Vector2i.ZERO, source.get_size()).encloses(region): return null
	var result: Image = source.get_region(region)
	if pattern["diamond"]:
		var size: int = mini(256, maxi(16, region.size.x))
		result = Image.create(size, size, false, Image.FORMAT_RGBA8)
		for y in size:
			for x in size:
				var uv := (Vector2(x, y) + Vector2.ONE * 0.5) / size
				var diamond := Vector2(0.5 + (uv.x - uv.y) * 0.5, (uv.x + uv.y) * 0.5)
				var point: Vector2 = diamond * Vector2(region.size)
				if pattern.has("basis"):
					var b: Array = pattern["basis"]
					point = Vector2(b[0], b[1]) + uv.x * Vector2(b[2], b[3]) + uv.y * Vector2(b[4], b[5])
				var sample := Vector2i(point.floor()) + region.position
				if region.has_point(sample): result.set_pixel(x, y, source.get_pixelv(sample))
	if cache.size() >= 64: cache.erase(cache.keys()[0])
	cache[key] = {"image": result, "texture": ImageTexture.create_from_image(result)}
	return result

static func texture(pattern: Dictionary) -> Texture2D:
	if not picture(pattern): return null
	var key: String = pattern["texture"] + str(pattern["region"]) + str(pattern["diamond"]) + str(pattern.get("basis", []))
	return cache[key]["texture"]

static func uv(point: Vector2, pattern: Dictionary) -> Vector2:
	return point.rotated(-deg_to_rad(pattern["angle"])) / float(pattern["scale"]) + Vector2(pattern["offset"][0], pattern["offset"][1])

static func sprite_uv(point: Vector2, pattern: Dictionary) -> Vector2:
	match pattern["projection"]:
		"roof": point = Vector2(point.x / 32.0 + point.y / 16.0, point.y / 16.0 - point.x / 32.0)
		"left wall": point = Vector2(point.x / 32.0, (point.y - point.x * 0.5) / 32.0)
		"right wall": point = Vector2(point.x / 32.0, (point.y + point.x * 0.5) / 32.0)
		_: point /= 32.0
	return uv(point, pattern)

static func mesh_uv(point: Vector3, axis: int, pattern: Dictionary) -> Vector2:
	var flat := Vector2(point.x, point.z) if axis == 1 else (Vector2(point.z, -point.y) if axis == 0 else Vector2(point.x, -point.y))
	return uv(flat, pattern)

static func valid(value: Variant) -> bool:
	if not value is Dictionary: return false
	if not value.get("texture") is String or not value["texture"].begins_with("res://assets/") or ".." in value["texture"] or not ResourceLoader.exists(value["texture"], "Texture2D"): return false
	if not value.get("diamond") is bool or not value.get("region") is Array or value["region"].size() != 4: return false
	for number in value["region"]:
		if not (number is int or number is float) or not is_finite(number) or number < 0 or number > 32768 or floorf(number) != number: return false
	if value["region"][2] < 1 or value["region"][3] < 1: return false
	var source: Texture2D = load(value["texture"])
	if not source or value["region"][0] + value["region"][2] > source.get_width() or value["region"][1] + value["region"][3] > source.get_height(): return false
	if value.has("basis"):
		if not value["basis"] is Array or value["basis"].size() != 6: return false
		for number in value["basis"]:
			if not (number is int or number is float) or not is_finite(number) or absf(number) > 32768: return false
	for name in ["scale", "angle"]:
		var number: Variant = value.get(name)
		if not (number is int or number is float) or not is_finite(number): return false
	if value["scale"] < 0.05 or value["scale"] > 64 or absf(value["angle"]) > 360000: return false
	if not value.get("offset") is Array or value["offset"].size() != 2: return false
	for number in value["offset"]:
		if not (number is int or number is float) or not is_finite(number) or absf(number) > 100000: return false
	return value.get("projection") in ["artwork", "roof", "left wall", "right wall"]
