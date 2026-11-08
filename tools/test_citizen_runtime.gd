extends SceneTree
const Plan=preload("res://scripts/builder/citizen_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for i in 6: await process_frame
	await physics_frame
func capture(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await settle(); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/"+name+".png")
func run() -> void:
	root.size=Vector2i(1480,900)
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		var doc: RefCounted=preload("res://scripts/builder/document.gd").new()
		doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
		studio.documents[mode]=doc
		var ids: Dictionary={}
		var roles: Array=["home","work","shop","park"]
		var locations: Array=[[-96,-32,0],[96,-32,0],[96,48,0],[-96,48,0]] if mode=="2d" else [[-6,0,-4],[6,0,-4],[6,0,4],[-6,0,4]]
		for i in 4:
			var item: Dictionary=doc.add("2d:Park_Bench" if mode=="2d" else "3d:HanX_Park/Bench_Park",locations[i],"SE" if mode=="2d" else "0")
			item["uid"]="citizens_"+mode+"_"+roles[i]
			item["citizen_role"]=roles[i]; item["name"]=roles[i].capitalize(); ids[roles[i]]=item["uid"]
		studio.changed(); studio.citizen_tools.dirty=true; await settle()
		var tools: RefCounted=studio.citizen_tools
		tools.show(); tools.enabled.button_pressed=true; tools.population.value=2; tools.seed.value=42; tools.length.value=3600; tools.hour.value=9; tools.apply_settings(); await settle()
		var manager: Node=tools.managers[mode]; manager.set_physics_process(false)
		check(manager.residents.size()==2 and manager.container.get_child_count()==2,"Enabling simulation creates real resident actors: "+mode)
		check(manager.residents[0]["actor"].position!=manager.residents[1]["actor"].position,"Residents receive separate safe positions around a shared home: "+mode)
		check(manager.obstacles.size()>0,"Actual placed collision shapes inform routing: "+mode)
		check(manager.residents.all(func(r: Dictionary):return is_instance_valid(r["actor"]) and r["actor"].has_meta("citizen_id") and not r["actor"].has_meta("builder_uid")),"Residents are transient actors rather than editable objects: "+mode)
		var before: Dictionary=doc.data.duplicate(true); var history: int=doc.undo_history.size()
		var actor_ids: Array=[]
		for r in manager.residents: actor_ids.append(r["actor"].get_instance_id())
		for destination in [[9,"work"],[12.5,"shop"],[17.5,"park"],[21.5,"home"]]:
			doc.data["citizens"]["start_hour"]=destination[0]
			manager.configure(doc.data,studio.library,studio.worlds[mode].instances,studio.worlds[mode].objects)
			check(manager.residents[0]["actor"].get_instance_id()==actor_ids[0],"Clock jumps preserve live actor positions: "+mode+destination[1])
			var arrived: bool=false
			for frame in 1800:
				manager.step(1.0/60)
				if manager.residents.all(func(r: Dictionary):return r["target"]==ids[destination[1]] and r["index"]>=r["path"].size() and r["status"].begins_with("At ")): arrived=true; break
				if frame==60: await capture("editor_citizens_walking_"+mode)
			check(arrived,"Residents physically arrive for their daily "+destination[1]+" activity: "+mode+" · "+manager.summary()+" · "+str(manager.residents.map(func(r: Dictionary):return r["status"])))
		check(manager.residents.all(func(r: Dictionary):return r["visits"].has(ids["work"]) and r["visits"].has(ids["shop"]) and r["visits"].has(ids["park"]) and r["visits"].has(ids["home"])),"Live routines visit all four destination types: "+mode)
		before["citizens"]["start_hour"]=21.5
		check(doc.data==before and doc.undo_history.size()==history,"Walking and daily progression do not edit the city or grow undo history: "+mode)
		doc.data["weather"]={"enabled":true,"condition":"rain","intensity":1.0,"affect_activity":true}
		manager.configure(doc.data,studio.library,studio.worlds[mode].instances,studio.worlds[mode].objects); manager.hour=17.5; manager.step(1.0/60)
		check(manager.residents.all(func(r: Dictionary):return r["target"]==ids["home"]),"Optional heavy weather keeps actual park visitors at home: "+mode)
		doc.data["weather"]["affect_activity"]=false; manager.step(1.0/60)
		check(manager.residents.all(func(r: Dictionary):return r["target"]==ids["park"]),"Disabling weather activity effects restores actual park routes: "+mode)
		doc.data["weather"]["affect_activity"]=true; manager.hour=9; manager.step(1.0/60)
		check(manager.residents.all(func(r: Dictionary):return r["target"]==ids["work"]),"Heavy weather preserves actual workplace routes: "+mode)
		doc.data.erase("weather"); manager.hour=21.5; manager.step(1.0/60)
		check(doc.data==before and doc.undo_history.size()==history,"Weather shelter and route changes leave authored city/history intact: "+mode)
		var time: float=manager.hour; var at: Variant=manager.residents[0]["actor"].position
		manager.paused=true; manager.step(5)
		check(manager.hour==time and manager.residents[0]["actor"].position==at,"Pausing freezes the clock and actors: "+mode)
		manager.paused=false
		tools.tick(.5); await capture("editor_citizens_panel_"+mode)
		var path: String="res://output/citizens_"+mode+".isocity.json"
		check(studio.write_project(path),"Citizen settings and destinations save normally: "+mode)
		var written: Dictionary=studio.Store.read_json(path,{})
		check(written["documents"][mode]["objects"].size()==4 and written["documents"][mode]["citizens"]["population"]==2,"Saves contain configuration and roles without transient actor records: "+mode)
		var scene_path: String="res://output/citizens_play_"+mode+".tscn"
		check(preload("res://scripts/builder/exporter.gd").save_scene(studio.worlds[mode],doc.data,studio.library,scene_path)==OK,"Runnable citizen scene exports: "+mode)
		var viewport:=SubViewport.new(); viewport.size=Vector2i(640,480); viewport.own_world_3d=true; root.add_child(viewport)
		var exported: Node=load(scene_path).instantiate(); viewport.add_child(exported); await settle()
		var simulation: Node=exported.citizens; simulation.set_physics_process(false); simulation.hour=9
		check(simulation.residents.size()==2,"Exported scenes instantiate the configured population: "+mode)
		var export_arrived: bool=false
		for frame in 1800:
			simulation.step(1.0/60)
			if simulation.residents.all(func(r: Dictionary):return r["target"]==ids["work"] and r["index"]>=r["path"].size() and r["status"].begins_with("At ")): export_arrived=true; break
		check(export_arrived,"Citizens walk to work in the actual exported scene: "+mode)
		viewport.free(); await settle()
		var portable: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],doc.data,studio.library,"res://output/citizens_"+mode+".zip")
		check(portable["ok"],"Citizen configurations export as portable Godot projects: "+mode)
		var zip:=ZIPReader.new(); zip.open("res://output/citizens_"+mode+".zip")
		check(["scripts/builder/citizen_runtime.gd","scripts/builder/citizen_plan.gd","resources/catalog/citizen_roles.json"].all(func(path: String):return zip.file_exists(path)),"Portable packages include the complete citizen runtime and role metadata: "+mode)
		zip.close()
		var positions: Array=manager.residents.map(func(r: Dictionary):return r["actor"].position)
		var existing: int=manager.residents[0]["actor"].get_instance_id()
		doc.data["objects"][1]["name"]="Renamed workplace"; studio.changed(); await settle()
		check(manager.residents[0]["actor"].get_instance_id()==existing and manager.residents[0]["actor"].position==positions[0],"City edits retain existing residents instead of respawning the population: "+mode)
		var collision_actor: Node=manager.residents[0]["actor"]
		var collision_position: Variant=collision_actor.position
		var blocked_object: Dictionary=doc.add("2d:Coffee_Shop" if mode=="2d" else "3d:HanX_Park/Bench_Park",[collision_position.x,collision_position.y,0] if mode=="2d" else [collision_position.x,0,collision_position.z],"SE" if mode=="2d" else "0")
		studio.changed(); await settle()
		check(manager.residents[0]["actor"].position==collision_position and manager.residents[0]["blocked"],"Construction over a resident pauses it instead of teleporting through the new obstruction: "+mode)
		doc.data["objects"].erase(blocked_object); studio.changed(); await settle()
		check(not manager.residents[0]["blocked"] and manager.residents[0]["actor"].get_instance_id()==existing,"Clearing construction restores that resident's ability to route: "+mode)
		manager.set_physics_process(false)
		if mode=="3d":
			doc.object(ids["work"])["position"][1]=3.0; manager.hour=9; studio.changed(); await settle()
			for frame in 1800: manager.step(1.0/60)
			check(manager.residents.all(func(r: Dictionary):return "walking surface" in r["status"] and r["visits"].back()!=ids["work"]),"Standing below an elevated entrance does not falsely count as visiting it")
		check(studio.load_project(path),"Saved citizen projects reopen: "+mode); await settle()
		check(manager.residents.size()==2 and Plan.settings(studio.current().data)["enabled"],"Project reopening restores live simulation configuration: "+mode)
		check(absf(manager.hour-21.5)<.01,"Loading restarts the preview at its saved start hour: "+mode)
		doc=studio.current()
		var unchanged_history: int=doc.undo_history.size()
		tools.apply_settings(); await settle()
		check(doc.undo_history.size()==unchanged_history,"Reapplying unchanged simulation settings resets time without an undo entry: "+mode)
		studio.selected_uids.assign([ids["home"],ids["work"]]); studio.selected_uid=ids["work"]; tools.refresh_role()
		check(tools.role_choice.selected==6,"Different destination overrides display a mixed selection: "+mode)
		tools.assign_role()
		check(doc.undo_history.size()==unchanged_history and doc.object(ids["home"])["citizen_role"]=="home","Mixed selection cannot accidentally overwrite roles without choosing a role: "+mode)
		studio.selected_uids.assign([ids["work"]]); studio.selected_uid=ids["work"]; studio.set_tool("select")
		tools.role_choice.select(3); tools.assign_role(); await settle()
		check(doc.object(ids["work"])["citizen_role"]=="shop","The authoring control assigns a destination role: "+mode)
		studio._command("undo",null); await settle()
		check(doc.object(ids["work"])["citizen_role"]=="work","Destination role assignments use normal Undo: "+mode)
		doc.object(ids["work"])["locked"]=true
		studio.selected_uids.assign([ids["work"]]); studio.selected_uid=ids["work"]
		tools.assign_role()
		check(doc.object(ids["work"])["citizen_role"]=="work","Destination authoring respects protected selections: "+mode)
		doc.object(ids["work"]).erase("locked")
		tools.enabled.button_pressed=false; tools.apply_settings(); await settle()
		check(manager.residents.is_empty() and manager.container==null,"Disabling citizens removes all transient actors: "+mode)
		studio._command("undo",null); await settle()
		check(manager.residents.size()==2,"Undoing a simulation setting restores the population: "+mode)
	var repair=preload("res://scripts/builder/project_repair.gd").new(studio.library)
	var damaged: Dictionary=studio.session_data().duplicate(true)
	damaged["documents"]["2d"]["citizens"]={"enabled":"yes","population":999,"seed":-4,"day_length":0,"start_hour":50,"extension":"keep"}
	damaged["documents"]["2d"]["objects"][0]["citizen_role"]=["home"]
	var repaired: Dictionary=repair.session(damaged)
	check(repaired["ok"] and repaired["changed"],"Damaged citizen settings and roles can be repaired")
	var fixed: Dictionary=repaired["content"]["documents"]["2d"]
	check(Plan.valid_settings(fixed["citizens"]) and fixed["citizens"]["extension"]=="keep" and fixed["objects"][0]["citizen_role"]=="none","Repair validates citizen data while preserving unrelated extensions")
	check(not Plan.valid_settings({"population":2.5}) and not Plan.valid_settings({"enabled":1}) and Plan.valid_settings({"enabled":true,"custom":"preserved"}),"Citizen validation rejects malformed known fields and permits extensions")
	studio.queue_free(); await process_frame
	print("CITIZEN RUNTIME: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
