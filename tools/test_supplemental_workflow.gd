extends SceneTree
const Driving=preload("res://scripts/builder/driving_plan.gd")
const Props=preload("res://scripts/builder/prop_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 6: await physics_frame
	await process_frame
func run() -> void:
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	while not studio.enhancements_ready: await process_frame
	var library: RefCounted=studio.library
	for mode in ["2d","3d"]:
		studio.switch_mode(mode); var original: Dictionary=studio.current().data.duplicate(true)
		studio._command("supplemental_showcase",null); await settle()
		check(preload("res://scripts/builder/document.gd").valid(studio.current().data,mode,library) and studio.current().data["objects"].size()>=28,"Command opens a valid editable pack sampler: "+mode)
		studio._command("undo",null); check(studio.current().data==original,"Showcase Undo restores the prior layout: "+mode)
		studio.current().data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
		var chosen: Dictionary={}
		for id in library.assets:
			var info: Dictionary=library.assets[id]["data"]; var pack: String=info.get("source_pack","")
			if pack.begins_with("Characters") and info.get("kind")!="char": continue
			if not chosen.has(pack) and pack in ["Bonsai trees","Arcade machines","Characters · Businessman"]: chosen[pack]=id
		for pack in chosen:
			var id: String=chosen[pack]; studio.current().add(id,[0,0,0],str(library.directions(id)[0]),library.assets[id]["data"].get("default_scale",1))
		if mode=="2d" and chosen.has("Characters · Businessman"): studio.current().data["citizens"]={"enabled":false,"appearance":chosen["Characters · Businessman"]}
		studio.changed(); await settle()
		var packaged: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],studio.current().data,library,"res://output/supplemental_"+mode+".zip")
		check(packaged["ok"],"Allowed supplemental atlas, model and character assets package together: "+mode+" "+packaged.get("message",""))
		var archive:=ZIPReader.new(); check(archive.open("res://output/supplemental_"+mode+".zip")==OK,"Portable archive opens")
		check(archive.get_files().has("resources/catalog/supplemental_registry.json"),"Portable archive includes a selected supplemental model registry")
		archive.close()
		for id in Driving.definitions()["assets"]:
			if not library.assets[id]["data"].has("view_yaws"): continue
			var item: Dictionary={"uid":"fleet","asset":id,"position":[0,0,0],"scale":1,"direction":"SW"}
			for direction in library.directions(id):
				item["direction"]=direction; check(Driving.direction(item,Driving.yaw(item))==direction,"Every supplied car heading round-trips: "+direction)
			var data: Dictionary=preload("res://scripts/builder/templates.gd").make(mode,"blank"); data["roads"]=[{"cell":[0,0]},{"cell":[1,0]}]
			var aligned: Dictionary=preload("res://scripts/builder/roads.gd").lane(data,[0,0,0],"SW",library,id)
			check(aligned["snapped"] and aligned["direction"] in ["SE","NW"],"Align cars uses actual fleet heading on an east-west lane: "+mode)
			studio.current().data=preload("res://scripts/builder/templates.gd").make(mode,"blank"); studio.current().data["objects"]=[item]; studio.changed(); await settle()
			var world: Node=studio.worlds[mode]; var exploration: Node=world.exploration; var runtime: Node=exploration.driving
			var center: Vector2=Driving.center(item,library,mode); var extent: Vector2=Driving.dimensions(item,library,mode)
			studio.set_walking(true); world.player.teleport_to(Driving.world(center+Vector2(extent.x+.5,0),mode)); world.player.set_physics_process(false); runtime.set_physics_process(false); await settle()
			exploration.interact(); check(not runtime.active.is_empty(),"Walk mode enters supplied fleet car: "+mode)
			if not runtime.active.is_empty():
				for frame in 90: runtime.step(1.0/60,Vector2(0,1),false)
				check(runtime.active["point"].distance_to(center)>4,"Supplied fleet car accelerates through actual world: "+mode)
			studio.set_walking(false)
			break
		var kinds: Dictionary={}
		for id in Props.definitions()["assets"]:
			if not id.contains("Supplemental_"): continue
			var profile: Dictionary=Props.profile({"asset":id}); var kind: String=profile["kind"]
			if kinds.has(kind): continue
			kinds[kind]=true; studio.current().data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
			var item: Dictionary=studio.current().add(id,[0,0,0],str(library.directions(id)[0]),library.assets[id]["data"].get("default_scale",1)); studio.changed(); await settle()
			var world: Node=studio.worlds[mode]; var exploration: Node=world.exploration; var runtime: Node=exploration.props
			studio.set_walking(true); world.player.teleport_to(Props.anchor(world.instances[item["uid"]],item,library,mode,profile,"approach")); world.player.set_physics_process(false); await settle()
			var found: Dictionary=Props.nearby(exploration); check(found.get("item",{}).get("uid")==item["uid"],"Authored supplemental prop approach is reachable: "+mode+"/"+kind)
			exploration.interact(); check(not runtime.active.is_empty() if kind!="switch" else runtime.notice.length()>0,"Normal interaction operates supplemental prop: "+mode+"/"+kind)
			studio.set_walking(false)
		var restricted: String=""
		for id in library.assets:
			if library.assets[id]["data"].get("source_export_allowed",true)==false: restricted=id; break
		check(not restricted.is_empty(),"Supplied redistribution restrictions are represented")
		studio.current().data=preload("res://scripts/builder/templates.gd").make(mode,"blank"); studio.current().add(restricted,[0,0,0],str(library.directions(restricted)[0]),1); studio.changed()
		var refused: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],studio.current().data,library,"res://output/supplemental_restricted_"+mode+".zip")
		check(not refused["ok"],"Raw asset packaging honors supplied redistribution restrictions")
		var requirements: Array=preload("res://scripts/builder/creation_share.gd").required_assets(studio.current().data,library)
		check(requirements.size()==1 and requirements[0]["id"]==restricted and not requirements[0]["author"].is_empty(),"Layout-only sharing retains restricted asset requirements and attribution")
	studio.free(); await process_frame; await process_frame
	print("Supplemental workflow: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
