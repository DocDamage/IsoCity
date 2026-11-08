extends SceneTree
const Tiles=preload("res://scripts/builder/terrain_tiles_2d.gd")
const Strip=preload("res://scripts/builder/terrain_strip_2d.gd")
const Plan=preload("res://scripts/builder/terrain_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 5: await process_frame
	await physics_frame
func run() -> void:
	var image:=Image.create(64,16,false,Image.FORMAT_RGBA8)
	for x in 64:
		for y in 16:
			var colors: Array=[Color.RED,Color.GREEN,Color.BLUE,Color.YELLOW] if x<32 else [Color.CYAN,Color.MAGENTA,Color.ORANGE,Color.WHITE]
			image.set_pixel(x,y,colors[(0 if posmod(x,32)<16 else 1)+(0 if y<8 else 2)])
	var atlas:=TileSetAtlasSource.new(); atlas.texture=ImageTexture.create_from_image(image); atlas.texture_region_size=Vector2i(32,16); atlas.create_tile(Vector2i.ZERO); atlas.set_tile_animation_columns(Vector2i.ZERO,2); atlas.set_tile_animation_frames_count(Vector2i.ZERO,2); atlas.set_tile_animation_frame_duration(Vector2i.ZERO,0,1); atlas.set_tile_animation_frame_duration(Vector2i.ZERO,1,2); atlas.set_tile_animation_speed(Vector2i.ZERO,4)
	var ground:=TileMapLayer.new(); ground.tile_set=TileSet.new(); ground.tile_set.add_source(atlas,1); ground.set_cell(Vector2i.ZERO,1,Vector2i.ZERO); root.add_child(ground)
	var descriptions: Dictionary=Tiles.descriptions(ground,{Vector2i.ZERO:{"direction":"SE"}}); var description: Dictionary=descriptions[Vector2i.ZERO]; var frames: Array[Texture2D]=Tiles.textures(description)
	check(frames.size()==2 and frames[0].get_width()==32 and frames[0].get_height()==16,"Terrain extracts every native atlas animation frame")
	check(frames[0].get_image().get_pixel(4,2)==Color.RED and frames[1].get_image().get_pixel(4,2)==Color.CYAN,"Atlas frame regions preserve their distinct source pixels")
	check(Tiles.textures(description)[0]==frames[0],"Unchanged tile treatments reuse generated texture resources")
	var rotated: Dictionary=description.duplicate(); rotated["direction"]="SW"; var turned: Image=Tiles.textures(rotated)[0].get_image()
	check(turned.get_pixel(4,2)==Color.BLUE and turned.get_pixel(24,2)==Color.RED and turned.get_pixel(4,12)==Color.YELLOW and turned.get_pixel(24,12)==Color.GREEN,"Quarter turns preserve isometric ground-plane orientation")
	rotated["direction"]="37"; turned=Tiles.textures(rotated)[0].get_image(); check(turned.get_pixel(0,0).a==0 and turned.get_pixel(16,8).a==1,"Free-angle tile rotation clips within its original atlas cell")
	var face: Dictionary={"textures":frames,"durations":description["durations"],"speed":description["speed"]}
	check(Strip.frame_at(face,0)==0 and Strip.frame_at(face,.25)==1 and Strip.frame_at(face,.74)==1 and Strip.frame_at(face,.75)==0,"Projected tiles honor animation speed and unequal frame durations")
	ground.free()
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	studio.switch_mode("2d"); var doc=preload("res://scripts/builder/document.gd").new(); doc.data=preload("res://scripts/builder/templates.gd").make("2d","blank"); doc.data["objects"]=[]; doc.data["roads"]=[]; doc.data["tiles"]=[{"cell":[0,5],"asset":"2d:Brick_Pavers","direction":"SW"}]; doc.data["terrain"]={"enabled":true,"bounds":[-8,-8,16,16]}; doc.data["terrain_vertices"]=[]; doc.data["water_cells"]=[]
	doc.data=Plan.brush(doc.data,"raise",Vector2.ZERO,8,2)["data"]
	doc.data=Plan.brush(doc.data,"basin",Vector2(-10,8),4,3)["data"]
	for x in range(-2,3): doc.data["roads"].append({"cell":[x,0]})
	for id in studio.worlds["2d"].tile_lookup:
		if studio.worlds["2d"].tile_lookup[id]["source"]==1 and studio.library.assets.has(id): doc.data["tiles"].append({"cell":[1,5],"asset":id,"direction":"37"}); break
	studio.documents["2d"]=doc; studio.changed(); await settle(); var world: Node=studio.worlds["2d"]; var surface: Node=world.terrain
	check(not world.ground.visible and not surface.strips.is_empty() and not world.grid.visible,"Normal isometric cities replace flat ground with textured terrain: "+str([world.ground.visible,surface.strips.size(),world.grid.visible]))
	var painted: Array=[]; var road_faces: int=0
	for strip in surface.strips.values():
		for item in strip.faces:
			if item.has("textures"):
				if item["cell"]==Vector2i(0,5): painted.append(item)
				else: road_faces+=1
	check(road_faces>20 and painted.size()==2,"Existing roads and painted floor cells enter the terrain geometry")
	var original_center: Vector2=world.ground.position+world.ground.map_to_local(Vector2i(0,5)); var terrain_center: Vector2=Plan.project_2d(Vector3(1,0,11))
	check(original_center.distance_to(terrain_center)<.001,"Projected cells retain their original tilemap ground centers: "+str([original_center,terrain_center]))
	check(not world.terrain_outside.get_used_cells().is_empty() and world.terrain_outside.get_used_cells().all(func(cell: Vector2i):return not Plan.bounds(doc.data).has_point(cell)),"Painted ground outside the sculpted boundary remains visible in its original flat layer")
	check(painted[0]["uv"]==PackedVector2Array([Vector2(.5,0),Vector2(0,.5),Vector2(1,.5)]),"Ground UVs follow the same diamond triangle as the terrain")
	var animated: bool=false
	for strip in surface.strips.values():
		for item in strip.faces:
			if item["cell"]==Vector2i(1,5) and item.has("textures"): animated=strip.animated and strip.is_processing() and item["textures"].size()>1
	check(animated,"Native animated ground keeps updating while projected onto terrain")
	var animation_node: Node; var animation_face: Dictionary
	for strip in surface.strips.values():
		for item in strip.faces:
			if item["cell"]==Vector2i(1,5) and item.has("textures"): animation_node=strip; animation_face=item
	surface.elapsed=animation_face["durations"][0]/animation_face["speed"]+.001; var phase: int=Strip.frame_at(animation_face,animation_node.current_time()); var animation_id: int=animation_node.get_instance_id()
	doc.data=Plan.brush(doc.data,"raise",Vector2(2,10),1,.25)["data"]; world.apply(doc.data)
	for strip in surface.strips.values():
		for item in strip.faces:
			if item["cell"]==Vector2i(1,5) and item.has("textures"): animation_node=strip; animation_face=item
	check(animation_node.get_instance_id()!=animation_id and phase==1 and Strip.frame_at(animation_face,animation_node.current_time())==phase,"Rebuilding a terrain strip preserves the shared ground-animation phase")
	var texture: Texture2D=painted[0]["textures"][0]; var retained: Dictionary={}
	for id in surface.strips: retained[id]=surface.strips[id].get_instance_id()
	world.apply(doc.data); check(surface.last_rebuilt==0 and surface.strips.keys().all(func(id: String):return surface.strips[id].get_instance_id()==retained[id]),"Unrelated world refreshes retain textured terrain strips")
	var source_path: String="res://assets/pixel_isometric/"+studio.library.assets["2d:Brick_Pavers"]["data"]["directions"]["SE"]["file"]; var raw: Texture2D=load(source_path)
	doc.data["tiles"][0]["colors"]=[{"kind":"pixels","texture":source_path,"pixels":Array(range(raw.get_width()*raw.get_height())),"color":[1,0,1,1]}]; studio.changed(); await settle()
	painted=[]
	for strip in surface.strips.values():
		for item in strip.faces:
			if item.get("cell")==Vector2i(0,5) and item.has("textures"): painted.append(item)
	check(painted[0]["textures"][0]!=texture and painted[0]["textures"][0].get_image().get_pixel(16,8).is_equal_approx(Color.MAGENTA),"Terrain retains authored pixel-color treatments after projection and rotation")
	var home: Dictionary=doc.add("2d:House_Blue",preload("res://scripts/builder/traffic_plan.gd").world(Vector2(8,-8),"2d"),"SE"); studio.changed(); await settle()
	studio.set_walking(true); world.player.set_physics_process(false); world.player.teleport_to(world.exploration.entrance(world.instances[home["uid"]])); world.exploration.interact(); await settle(); world.apply(doc.data)
	check(world.exploration.interior!=null and not surface.visible and not world.ground.visible and not world.terrain_outside.visible,"Owned interiors suspend terrain and both ground layers through exterior refreshes")
	world.exploration.leave_interior(); studio.set_walking(false); await settle()
	check(surface.visible and world.terrain_outside.visible and not world.ground.visible,"Returning outside restores projected ground without exposing the flat source tilemap")
	var before: Dictionary=doc.data.duplicate(true); var scene_path: String="res://output/terrain_city_2d.tscn"
	check(studio.Exporter.save_scene(world,doc.data,studio.library,scene_path)==OK,"Textured terrain cities export as runnable scenes")
	var viewport:=SubViewport.new(); viewport.size=Vector2i(1000,700); root.add_child(viewport); var playable: Node=load(scene_path).instantiate(); viewport.add_child(playable); await settle(); playable.player.set_physics_process(false)
	var exported_faces: int=0; var exported_paint: bool=false
	for strip in playable.terrain.strips.values():
		for item in strip.faces:
			if item.has("textures"):
				exported_faces+=1
				if item["cell"]==Vector2i(0,5): exported_paint=item["textures"][0].get_image().get_pixel(16,8).is_equal_approx(Color.MAGENTA)
	check(not playable.get_node("Ground").visible and exported_faces==road_faces+2 and exported_paint,"Playable terrain rebuilds all road and painted textures from its packaged tilemap")
	check(playable.get_node("TerrainOutside").get_used_cells()==world.terrain_outside.get_used_cells(),"Playable scenes retain the same flat ground outside the terrain boundary")
	check(doc.data==before and JSON.parse_string(JSON.stringify(playable.studio_data))==JSON.parse_string(JSON.stringify(before)),"Terrain texture rendering/export preserves authoritative project data")
	viewport.free(); doc.data["terrain"]["enabled"]=false; studio.changed(); await settle()
	check(world.ground.visible and surface.strips.is_empty(),"Disabling terrain restores the original flat tilemap")
	doc.data["tiles"][0]["direction"]="NW"; studio.changed(); await settle(); doc.data["terrain"]["enabled"]=true; studio.changed(); await settle()
	check(world.terrain_tiles[Vector2i(0,5)]["direction"]=="NW","Ground edits while terrain is disabled refresh the projected texture cache when re-enabled")
	var portable: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(world,doc.data,studio.library,"res://output/terrain_2d.zip")
	check(portable["ok"],"Portable terrain packages include projected ground and owned-room dependencies")
	world.camera.position=Vector2(0,-20); world.camera.zoom=Vector2.ONE*2
	if "--capture" in OS.get_cmdline_user_args():
		root.size=Vector2i(1480,900); await settle(); await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png("res://output/terrain_roads_2d.png")
	studio.free(); print("TERRAIN TILES 2D: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
