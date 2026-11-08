extends SceneTree
const Parts=preload("res://scripts/builder/part_colors.gd")
const Patterns=preload("res://scripts/builder/tile_patterns.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var library=preload("res://scripts/builder/asset_library.gd").new()
	var raw: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/catalog/supplemental_registry.json"))
	var pixels:=Image.create(12,4,false,Image.FORMAT_RGBA8); pixels.fill(Color.RED); pixels.fill_rect(Rect2i(4,0,4,4),Color.GREEN); pixels.fill_rect(Rect2i(8,0,4,4),Color.BLUE)
	var texture:=ImageTexture.create_from_image(pixels); var region_view:=AtlasTexture.new(); region_view.atlas=texture; region_view.region=Rect2(4,0,8,4)
	var sample:=Sprite2D.new(); sample.texture=region_view; sample.hframes=2; root.add_child(sample)
	for frame in 2:
		sample.frame=frame; var projected: Dictionary=preload("res://scripts/builder/sprite_projection.gd").frame(sample)
		check(projected["texture"].get_size()==Vector2(4,4) and projected["texture"].get_image().get_pixel(2,2).is_equal_approx(Color.GREEN if frame==0 else Color.BLUE),"3D projection contains only the selected frame inside an offset atlas strip")
	sample.free()
	check(raw["items"].size()>=1701,"Prepared supplemental sprites enter the actual catalog")
	var packs: Dictionary={}
	for ident in raw["items"]:
		var id: String="2d:"+ident; var asset: Dictionary=library.assets[id]; packs[asset["data"]["source_pack"]]=id
		check(asset["behavior"]==asset["data"]["behavior"],"Explicit supplemental behavior is retained: "+id)
	check(packs.size()>=28,"Supplemental packs remain individually filterable")
	for id in packs.values():
		var asset: Dictionary=library.assets[id]; var node: Node2D=load(asset["path"]).instantiate(); root.add_child(node)
		var directions: Array=asset["data"]["directions"].keys(); var original: Texture2D
		for direction in ([directions[0]] if directions.size()==1 else [directions[0],directions[-1]]):
			node.direction=direction; var sprite: Sprite2D=node.get_node("Sprite2D"); var view: Dictionary=asset["data"]["directions"][direction]
			check(sprite.texture is AtlasTexture and sprite.texture.get_width()==view["frame_width"]*view["frames"] and sprite.texture.get_height()==view["frame_height"],"Shared atlas selects exactly the authored strip: "+id+"/"+direction)
			check(library.directional_icon(id,direction).get_size()==Vector2(view["frame_width"],view["frame_height"]),"Directional icons show one frame from the selected atlas region")
			var pattern: Dictionary=Patterns.from_asset(library,id,direction); var picture: Image=Patterns.picture(pattern)
			var area: Array=view["region"]
			check(picture!=null and not picture.is_empty() and Vector2(pattern["region"][0],pattern["region"][1])==Vector2(area[0],area[1]) and (pattern["diamond"] or picture.get_size()==Vector2i(view["frame_width"],view["frame_height"])),"Tile treatments crop the selected source view, not the atlas origin")
		var sprite: Sprite2D=node.get_node("Sprite2D"); original=Parts.base_texture(sprite); var image: Image=original.get_image(); var picked: Vector2i=Vector2i(-1,-1)
		for y in int(sprite.get_rect().size.y):
			for x in int(sprite.get_rect().size.x):
				if image.get_pixel(x,y).a>.5: picked=Vector2i(x,y); break
			if picked.x>=0: break
		check(picked.x>=0,"Authored source view contains visible artwork")
		var edit: Dictionary=Parts.pixels(sprite,sprite.get_rect().position+Vector2(picked),.01,true)
		check(not edit.is_empty() and edit.has("atlas_region") and FileAccess.file_exists(edit.get("texture","")) and Parts.valid([edit]),"Painting stores a real atlas path and the selected region")
		edit["color"]=[1.0,0.0,1.0,1.0]; var colored: Texture2D=Parts.recolored_texture(original,[edit]); check(colored!=original and colored.get_image().get_pixelv(picked).r>.99,"Pixel painting applies inside the selected atlas region")
		check(Parts.edit_texture(edit).get_size()==original.get_size(),"Saved pixel selection resolves to the same view strip")
		if directions.size()>1:
			node.direction=directions[0]; var different: Texture2D=Parts.base_texture(sprite)
			check(Parts.recolored_texture(different,[edit])==different,"Painting one source view does not recolor another region of the atlas")
		node.free(); await process_frame
	await test_models(raw,library); await test_actors(raw,library)
	print("Supplemental assets: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
func test_models(raw: Dictionary,library: RefCounted) -> void:
	check(raw["models"].size()==119,"All 119 distinct GLBs are registered")
	for id in raw["models"]:
		check(library.assets.has(id) and library.assets[id]["data"].has("source_pack"),"Model keeps source-pack, attribution and preview metadata: "+id)
		var model: Node3D=load(library.assets[id]["path"]).instantiate(); root.add_child(model); var bounds: AABB=preload("res://scripts/model_bounds.gd").get_bounds(model)
		check(absf(bounds.position.y)<.001 and bounds.size.is_finite() and bounds.size.length()>.01,"Model pivot sits exactly on the ground: "+id)
		check(absf(bounds.get_center().x)<.001 and absf(bounds.get_center().z)<.001,"Model is centered around its placement pivot: "+id)
		model.free(); await process_frame
func test_actors(raw: Dictionary,library: RefCounted) -> void:
	var actors: Array=raw["items"].keys().filter(func(id: String):return raw["items"][id].get("kind")=="char")
	check(actors.size()==9,"Nine reusable character families accompany the individual action clips")
	var selected_style: String=""
	for ident in actors:
		var item: Dictionary=raw["items"][ident]; var actor: Node2D=load(item["scene_path"]).instantiate(); root.add_child(actor)
		var idle_sprite: Sprite2D=actor.get_node("Sprite2D"); var idle_frame: Image=idle_sprite.texture.get_image().get_region(Rect2i(0,0,int(idle_sprite.texture.get_width()/idle_sprite.hframes),idle_sprite.texture.get_height()))
		check(absf(idle_frame.get_used_rect().size.y*idle_sprite.scale.y*actor.scale.y-28)<.1,"Reusable citizen families share a consistent visible height: "+ident)
		check(actor is IsoCharacter and actor.authored_animation!=null,"Character uses its authored animation controller: "+ident)
		actor.action="walk"; actor._update_animation(.2); var sprite: Sprite2D=actor.get_node("Sprite2D")
		var view: Dictionary=actor.authored_animation.current_view
		check(sprite.hframes==int(view["frames"]) and sprite.hframes>1 and sprite.frame<int(view["frames"]),"Walking uses the complete authored clip and cadence: "+ident)
		actor.move_character(.1,Vector2(1,.5)); check(actor.action=="walk" and not actor.velocity.is_zero_approx(),"Character retains existing acceleration and collision movement: "+ident)
		if item["source_pack"]=="Characters · Businessman": selected_style="2d:"+ident
		actor.free(); await process_frame
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio)
	for frame in 6: await process_frame
	studio.current().data=preload("res://scripts/builder/templates.gd").make("2d","blank")
	var plan=preload("res://scripts/builder/citizen_plan.gd"); var home: String=""
	for id in studio.library.assets:
		if id.begins_with("2d:") and plan.role({"asset":id})=="home": home=id; break
	studio.current().add(home,[0,0,0],str(studio.library.directions(home)[0]),1); studio.changed()
	var ui: RefCounted=studio.citizen_tools; ui.refresh_fields(); ui.enabled.button_pressed=true; ui.population.value=1
	for index in ui.appearance.item_count:
		if ui.appearance.get_item_metadata(index)==selected_style: ui.appearance.select(index); break
	ui.apply_settings()
	for frame in 12: await physics_frame
	var manager: Node=ui.managers["2d"]
	check(studio.current().data["citizens"].get("appearance")==selected_style and manager.residents.size()==1 and is_instance_valid(manager.residents[0]["actor"]) and manager.residents[0]["actor"].item_id==selected_style.trim_prefix("2d:"),"Actual Citizens inspector spawns the selected supplemental character for daily routines")
	check(preload("res://scripts/builder/cooperative_plan.gd").used_assets(studio.current().data).has(selected_style),"Cooperative/shared cities include selected citizen appearance in their asset requirements")
	var path: String="res://output/supplemental_actor_style.isocity.json"; studio.write_project(path); var missing: Dictionary=studio.library.assets[selected_style]; studio.library.assets.erase(selected_style)
	var repair=preload("res://scripts/builder/project_repair.gd").new(studio.library); var restored: Dictionary=repair.read(path)
	check(restored["ok"] and not restored["content"]["documents"]["2d"]["citizens"].has("appearance") and not repair.issues.is_empty(),"A missing appearance repairs to the default citizen while preserving city content")
	studio.library.assets[selected_style]=missing; studio.free(); await process_frame; await process_frame
