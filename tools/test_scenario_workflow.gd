extends SceneTree
const Plan=preload("res://scripts/builder/scenario_plan.gd")
const Citizen=preload("res://scripts/builder/citizen_plan.gd")
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
func finish(manager: Node) -> void:
	for i in 200:
		if manager.queue.is_empty(): break
		manager.step()
func export_and_check(studio: Control,manager: Node,kind: String,mode: String) -> void:
	var path: String="res://output/scenario_"+kind+"_"+mode
	check(studio.Exporter.save_scene(studio.worlds[mode],studio.current().data,studio.library,path+".tscn")==OK,"Challenge exports as an actual playable scene: "+kind+" "+mode)
	var viewport:=SubViewport.new(); viewport.size=Vector2i(800,600); viewport.own_world_3d=true; root.add_child(viewport)
	var exported: Node=load(path+".tscn").instantiate(); viewport.add_child(exported); await settle(); exported.scenario.set_process(false); finish(exported.scenario)
	check(exported.scenario.progress["complete"] and exported.scenario.panel.visible,"Playable exports recompute actual challenge goals and display completion: "+kind+" "+mode)
	viewport.free(); await settle()
	var value: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],studio.current().data,studio.library,path+".zip")
	check(value["ok"],"Portable challenge exports include their evaluator and goal metadata: "+kind+" "+mode)
func run() -> void:
	root.size=Vector2i(1480,900)
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		var doc: RefCounted=preload("res://scripts/builder/document.gd").new(); doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
		var ids: Array[String]=[]; var roles: Array=["home","home","work","shop","park"]
		var positions: Array=[Vector2(-16,0),Vector2.ZERO,Vector2(16,0),Vector2(0,18),Vector2(16,18)]
		var assets: Array=["2d:House_Blue","2d:House_Blue","2d:Office_Tower","2d:Coffee_Shop","2d:Park_Bench"] if mode=="2d" else ["3d:HanX_City/Row_Houses_A","3d:HanX_City/Row_Houses_A","3d:HanX_City/Office_Tower","3d:HanX_City/Cafe_Small","3d:HanX_Park/Bench_Park"]
		for index in 5:
			var item: Dictionary=doc.add(assets[index],Citizen.world(positions[index],mode),studio.library.directions(assets[index])[0]); item["name"]=roles[index].capitalize()+str(index); ids.append(item["uid"])
		studio.documents[mode]=doc; studio.changed(); await settle()
		for index in 5:
			var item: Dictionary=doc.object(ids[index]); var point: Variant=studio.worlds[mode].exploration.entrance(studio.worlds[mode].instances[ids[index]])
			var actual: Vector2=Citizen.metric([point.x,point.y,0] if mode=="2d" else [point.x,point.y,point.z],mode)
			item["position"]=Citizen.world(Citizen.metric(item["position"],mode)+positions[index]-actual,mode)
		studio.changed(); await settle()
		var tools: RefCounted=studio.scenario_tools; var manager: Node=tools.managers[mode]; manager.set_process(false); tools.show(); tools.choice.select(0); tools.start_challenge(); tools.tick(.4); finish(manager); tools.refresh()
		check(manager.progress["complete"] and manager.checked>=6 and doc.data["objects"].size()==5,"A real two-home neighborhood completes only after its work, shop and park walking links are checked: "+mode+str(manager.progress))
		check(not manager.obstacles.is_empty() and manager.connections.size()==2 and tools.badge.visible and "Complete" in tools.badge.text,"Challenge evaluation uses actual building collisions and keeps visible progress: "+mode)
		await capture("scenario_walkable_"+mode)
		var home_node: Node=studio.worlds[mode].instances[ids[0]]; var approach: Variant=studio.worlds[mode].exploration.entrance(home_node)
		var blocker: Node
		if mode=="2d":
			blocker=StaticBody2D.new(); var shape:=CollisionShape2D.new(); var rect:=RectangleShape2D.new(); rect.size=Vector2(256,128); shape.shape=rect; blocker.add_child(shape); home_node.add_child(blocker); blocker.global_position=approach
		else:
			blocker=StaticBody3D.new(); var shape:=CollisionShape3D.new(); var box:=BoxShape3D.new(); box.size=Vector3(8,2,8); shape.shape=box; blocker.add_child(shape); home_node.add_child(blocker); blocker.global_position=approach
		tools.recheck(); finish(manager)
		check(not manager.progress["complete"] and manager.connections.size()<=2,"Blocking an actual entrance cannot retain an earlier neighborhood success: "+mode)
		blocker.free(); tools.recheck(); finish(manager)
		check(manager.progress["complete"],"Clearing the physical entrance restores valid route progress: "+mode)
		doc.checkpoint(); doc.object(ids[3])["visible"]=false; studio.changed(); tools.tick(.4); finish(manager)
		check(not manager.progress["complete"],"Hiding the actual shop invalidates its challenge goal: "+mode)
		studio._command("undo",null); await settle(); tools.tick(.4); finish(manager)
		check(manager.progress["complete"],"Undo restores the shop and recomputes usable routes: "+mode)
		tools.recheck(); var checked: int=manager.checked
		studio.switch_mode("3d" if mode=="2d" else "2d"); tools.tick(.4); manager.step()
		check(manager.checked==checked,"Inactive worlds suspend their incremental route checks: "+mode)
		studio.switch_mode(mode); await settle(); tools.tick(.4); finish(manager)
		await export_and_check(studio,manager,"walkable",mode)
		studio.selected_uid=ids[0]; studio.selected_uids.assign([ids[0]]); tools.show(); tools.choice.select(1); tools.start_challenge(); tools.tick(.4)
		studio.economy_tools.paused.button_pressed=true
		check(doc.data["scenario"]["id"]=="apartment" and doc.data["scenario"]["host_uid"]==ids[0] and doc.data["economy_account"]["cash"]==600 and not manager.progress["complete"],"The selected apartment starts with an empty owned room, a dedicated budget and incomplete furniture goals: "+mode)
		var attempt: String=doc.data["scenario"]["attempt"]
		studio._command("undo",null); await settle(); tools.tick(.4); finish(manager)
		check(doc.data["scenario"]["id"]=="walkable" and not doc.data.has("economy_account") and not doc.object(ids[0]).has("interior"),"Undo restores the previous challenge, room and treasury after apartment setup: "+mode)
		studio._command("redo",null); await settle(); tools.tick(.4)
		check(doc.data["scenario"]["attempt"]==attempt and doc.data["economy_account"]["cash"]==600,"Redo restores the exact apartment attempt and budget once: "+mode)
		tools.show(); tools.edit_apartment(); await settle()
		check(studio.interior_tools.editing(),"The challenge opens its actual owned-room editor: "+mode)
		var points: Array=[Vector2(-3,-3),Vector2(-1,-3),Vector2(1,-3),Vector2(2,1)]; var index: int=0
		for kind in Plan.definitions()["apartment"]["furniture"]:
			var asset: String=Plan.definitions()["apartment"]["furniture"][kind].filter(func(id: String):return studio.library.assets[id]["mode"]==mode)[0]
			for row in tools.assets.item_count:
				if tools.assets.get_item_metadata(row)==asset: tools.assets.select(row); break
			tools.place_asset()
			check(studio.asset_id==asset,"Goal-asset controls select real placeable "+kind+": "+mode)
			studio.scale_input.value=1; var raw: Array
			if mode=="2d":
				var pixel: Vector2=preload("res://scripts/builder/grid_fit.gd").pixels(points[index]); raw=[pixel.x,pixel.y,0]
			else: raw=[points[index].x,0,points[index].y]
			studio.drop_asset(asset,studio.overlay_position(raw)); index+=1; await settle(); tools.tick(.4)
		tools.refresh()
		check(manager.progress["complete"] and doc.data["economy_account"]["construction_total"]==400 and doc.data["economy_account"]["cash"]==200,"Actual room placement completes all furnishing goals within the shared 600-credit allowance: "+mode+str(manager.progress))
		check("200 credits" in studio.economy_tools.badge.text,"The treasury badge updates immediately with the final furniture purchase: "+mode)
		await capture("scenario_apartment_"+mode)
		studio.interior_tools.leave(); await settle(); tools.tick(.4)
		check(manager.progress["complete"],"Leaving the room retains proven challenge completion: "+mode)
		studio.economy_tools.restart(); tools.tick(.4)
		check(not manager.progress["complete"],"Resetting the economy invalidates the original challenge budget: "+mode)
		studio._command("undo",null); await settle(); tools.tick(.4)
		check(manager.progress["complete"],"Undo restores the original treasury proof and challenge completion: "+mode)
		var saved: String="res://output/scenario_"+mode+".isocity.json"
		check(studio.write_project(saved),"Challenge attempts and their purchase proof save with the city: "+mode)
		tools.stop_challenge(); tools.tick(.4)
		check(not doc.data.has("scenario") and manager.progress["goals"].is_empty() and doc.data["economy_account"]["cash"]==200,"Stopping a challenge keeps the authored city and treasury: "+mode)
		check(studio.load_project(saved),"Saved challenge projects reopen: "+mode); await settle(); doc=studio.current(); tools.tick(.4)
		check(manager.progress["complete"] and doc.data["scenario"]["host_uid"]==ids[0],"Reopening recomputes completion from saved room content and treasury: "+mode)
		await export_and_check(studio,manager,"apartment",mode)
	root.size=Vector2i(960,640); studio.scenario_tools.show(); studio.scenario_tools.refresh(); await settle()
	check(studio.scenario_tools.panel.get_child(0).size.x<=studio.scenario_tools.panel.size.x,"Challenge controls fit the scrolling inspector at 960×640")
	await capture("scenario_small_window")
	studio.queue_free(); await process_frame
	print("SCENARIO WORKFLOW: %d checks, %d failures" % [checks,failures]); quit(0 if failures==0 else 1)
