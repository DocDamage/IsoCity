extends Node2D
const Plan=preload("res://scripts/builder/terrain_plan.gd")
const Families=preload("res://scripts/builder/terrain_family_plan.gd")
const Patterns=preload("res://scripts/builder/tile_patterns.gd")
const STRIP_SIZE: int=16
var strips: Dictionary={}
var signatures: Dictionary={}
var signature: int=0
var last_rebuilt: int=0
var source: Dictionary={}
var elapsed: float=0
var floor_holes: Array=[]
var family_warnings: Dictionary={}
var rock_faces: Dictionary={}
func _ready() -> void: set_process(false)
func _process(delta: float) -> void:
	if is_visible_in_tree(): elapsed+=delta
func configure(data: Dictionary,tiles: Dictionary={}) -> void:
	last_rebuilt=0; source=data; y_sort_enabled=true
	if not Plan.settings(data)["enabled"] or not Plan.Layers.shown(data,"Ground"): clear(); return
	var stamp: int=hash([data.get("terrain",{}),data.get("terrain_vertices",[]),data.get("water_cells",[]),tiles,floor_holes])
	if stamp==signature and not strips.is_empty(): return
	var area: Rect2i=Plan.bounds(data); var heights: Dictionary=Plan.lookup(data); var waters: Dictionary=Plan.lookup(data,true); var groups: Dictionary={}
	var settings: Dictionary=Plan.settings(data)
	var connected_water: Dictionary={}
	if settings["connected_shores"]:
		for record in waters.values():
			var cell: Vector2i=Families.cell_of(record)
			var samples: Array=cell_heights(cell,heights)
			if float(samples.min())<float(record["level"])-.001: connected_water[cell]=record["level"]
	family_warnings.clear()
	rock_faces.clear()
	for x in range(area.position.x,area.end.x):
		for y in range(area.position.y,area.end.y):
			var cell:=Vector2i(x,y); var id: String=str(x+y)+":"+str(floori(float(x)/STRIP_SIZE))
			if not groups.has(id): groups[id]=[]
			var samples: Array=cell_heights(cell,heights)
			var shore: Dictionary=Families.shoreline(cell,connected_water) if connected_water.has(cell) else {}
			var rock: Dictionary=Families.cliff(samples) if settings["connected_cliffs"] and not tiles.has(cell) else {}
			if not rock.is_empty(): rock_faces[cell]=rock
			if shore.get("unsupported",0)!=0: family_warnings[cell]="Water at different levels · transition unavailable"
			elif not rock.is_empty() and Families.piece(rock).is_empty(): family_warnings[cell]="No reviewed rock face for this height transition"
			groups[id].append([cell,samples,waters.get(Plan.key(cell),{}).get("level"),tiles.get(cell,{}),shore,rock])
	var keep: Dictionary={}; var land:=Color(settings["land_color"]); var water:=Color(settings["water_color"]); water.a*=.72
	for id in groups:
		keep[id]=true; var group_stamp: int=hash([groups[id],land,water,floor_holes])
		if signatures.get(id)==group_stamp and is_instance_valid(strips.get(id)): continue
		if is_instance_valid(strips.get(id)): strips[id].free()
		var strip=preload("res://scripts/builder/terrain_strip_2d.gd").new(); strip.clock=self; strip.name=("Terrain_"+id).validate_node_name(); strip.position=Vector2(0,(int(id.get_slice(":",0))+2)*Plan.CELL_SIZE*4)
		for record in groups[id]:
			var cell: Vector2i=record[0]
			var rock: Dictionary=Patterns.family_pattern(record[5]) if not record[5].is_empty() else {}
			var shore: Dictionary=Patterns.family_pattern(record[4]) if not record[4].is_empty() else {}
			for face in Plan.triangles(data,cell,heights):
				var normal: Vector3=(face[1]-face[0]).cross(face[2]-face[0]).normalized(); var brightness: float=.65+.35*maxf(0,normal.dot(Vector3(-.5,1,-.4).normalized()))
				var tint: Color=land.lerp(Color("a38d67"),clampf((1-normal.y)*.8,0,.65)); tint=Color(tint.r*brightness,tint.g*brightness,tint.b*brightness,tint.a)
				for polygon in preload("res://scripts/builder/floor_terrain_plan.gd").fragments(face,floor_holes):
					var points:=PackedVector2Array()
					for point in polygon: points.append(Plan.project_2d(point)-strip.position)
					if absf((points[1]-points[0]).cross(points[2]-points[0]))>.000001:
						var item: Dictionary={"points":points,"color":tint,"kind":"land","cell":cell}
						if tiles.has(cell):
							var tile: Dictionary=tiles[cell].duplicate()
							tile["textures"]=preload("res://scripts/builder/terrain_tiles_2d.gd").textures(tile)
							surface_texture(item,tile,polygon,cell,Color(brightness,brightness,brightness,1))
						elif not rock.is_empty():
							surface_texture(item,rock,polygon,cell,Color(brightness,brightness,brightness,1))
						strip.animated=strip.animated or item.get("textures",[]).size()>1
						strip.faces.append(item)
			for polygon in Plan.water_polygons(data,cell,heights,waters):
				for fragment in preload("res://scripts/builder/floor_terrain_plan.gd").fragments(polygon,floor_holes):
					var points:=PackedVector2Array()
					for point in fragment: points.append(Plan.project_2d(point)-strip.position)
					var item: Dictionary={"points":points,"color":water,"kind":"water","cell":cell}
					if not shore.is_empty():
						surface_texture(item,shore,fragment,cell,Color.WHITE)
						strip.animated=true
					strip.faces.append(item)
		add_child(strip); strips[id]=strip; signatures[id]=group_stamp; last_rebuilt+=1
	for id in strips.keys():
		if not keep.has(id): strips[id].free(); strips.erase(id); signatures.erase(id)
	signature=stamp
	set_process(strips.values().any(func(strip: Node):return strip.animated))
func cell_heights(cell: Vector2i,heights: Dictionary) -> Array:
	return [Plan.vertex(heights,cell).y,Plan.vertex(heights,cell+Vector2i.RIGHT).y,
		Plan.vertex(heights,cell+Vector2i.DOWN).y,Plan.vertex(heights,cell+Vector2i.ONE).y]
func surface_texture(item: Dictionary,pattern: Dictionary,polygon: PackedVector3Array,cell: Vector2i,tint: Color) -> void:
	item["textures"]=pattern["textures"]
	item["durations"]=pattern["durations"]
	item["speed"]=pattern["speed"]
	item["tint"]=tint
	var uv:=PackedVector2Array()
	for point in polygon:
		var local: Vector2=Vector2(point.x,point.z)/Plan.CELL_SIZE-Vector2(cell)
		uv.append(Vector2(.5+(local.x-local.y)*.5,(local.x+local.y)*.5))
	item["uv"]=uv
func pick(pixel: Vector2,include_water: bool=false) -> Dictionary:
	if strips.is_empty() or not is_visible_in_tree(): return Plan.failure("Terrain is not visible.")
	return Plan.pick_2d(source,to_local(pixel),include_water)
func clear() -> void:
	for strip in strips.values():
		if is_instance_valid(strip): strip.free()
	strips.clear(); signatures.clear(); signature=0; set_process(false)
	family_warnings.clear()
	rock_faces.clear()
