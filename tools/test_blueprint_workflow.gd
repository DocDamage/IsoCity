extends SceneTree
const Plan=preload("res://scripts/builder/blueprint_plan.gd")
const Doc=preload("res://scripts/builder/document.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 5: await physics_frame
func run() -> void:
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode); var doc: RefCounted=studio.current(); var ui: RefCounted=studio.blueprint_tools
		var asset: String=""
		for id in studio.library.assets:
			if id.begins_with(mode+":") and studio.library.assets[id]["behavior"].get("building",false): asset=id; break
		check(not asset.is_empty(),"A native building is available: "+mode)
		var item: Dictionary={"asset":asset,"position":[0,0,0],"direction":str(studio.library.directions(asset)[0]),"scale":1.0}
		var objects: Array=doc.data["objects"].duplicate(true); var roads: Array=doc.data.get("roads",[]).duplicate(true)
		studio._command("blueprints",null); check(ui.panel.is_visible_in_tree(),"Command opens the planning controls: "+mode)
		ui.add({"kind":"building","item":item}); var building_uid: String=ui.selected
		ui.add({"kind":"road","start":[20,20],"end":[23,20],"settings":{"width":2,"style":"brick","sidewalks":false}})
		await settle()
		check(doc.data["objects"]==objects and doc.data.get("roads",[])==roads,"Sketching does not construct objects or roads: "+mode)
		check(Doc.valid(doc.data,mode,studio.library),"Proposals survive normal document validation: "+mode)
		check(is_instance_valid(ui.containers[mode]) and ui.containers[mode].get_child_count()==5,"Both building and road footprints render: "+mode)
		var first: Node=ui.containers[mode].get_child(0)
		check(first.polygons.size()==1 if mode=="2d" else first.mesh.surface_get_material(0).albedo_color.a<1,"Footprint visuals are translucent: "+mode)
		var serialized: Dictionary=JSON.parse_string(JSON.stringify(doc.data)); check(Doc.valid(serialized,mode,studio.library),"JSON round-trip retains plans: "+mode)
		var plans: Array=doc.data["blueprints"].duplicate(true); var history: int=doc.undo_history.size(); ui.construct(true)
		check(doc.data["blueprints"].is_empty() and doc.data["objects"].size()==objects.size()+1 and doc.data["roads"].size()==roads.size()+4,"Commit creates the exact proposed construction: "+mode)
		check(doc.undo_history.size()==history+1,"Committing all proposals is one undo transaction: "+mode)
		var built: Dictionary=doc.object("built_"+building_uid); check(built["position"]==item["position"] and built["direction"]==item["direction"] and built["scale"]==item["scale"],"Construction preserves the proposed pose: "+mode)
		studio._command("undo",null); check(doc.data["blueprints"]==plans and doc.data["objects"]==objects and doc.data.get("roads",[])==roads,"Undo restores proposals and removes construction together: "+mode)
		studio._command("redo",null); check(doc.data["blueprints"].is_empty(),"Redo restores construction: "+mode); studio._command("undo",null)
		ui.selected=building_uid; ui.rotate_selected(); check(doc.data["blueprints"][0]["item"]["direction"]!=item["direction"],"Selected building proposal can be revised: "+mode); studio._command("undo",null)
		var cash_before: Dictionary=doc.data.duplicate(true); doc.data["economy"]={"enabled":true,"starting_cash":0,"refund_percent":25,"period_seconds":60}; var poor: Dictionary=doc.data.duplicate(true); ui.construct(true)
		check(doc.data==poor and not doc.economy_error.is_empty(),"Insufficient budget preserves every proposal and existing construction: "+mode)
		doc.data=cash_before; ui.selected=building_uid; ui.discard(false); check(doc.data["blueprints"].size()==1,"Discard selected preserves other plans: "+mode); studio._command("undo",null)
		var malformed: Array=plans.duplicate(true); malformed[1]["end"]=[10000,10000]; check(not Plan.valid(malformed,mode,studio.library),"Overlong road proposals cannot silently truncate: "+mode)
		var opposite: String="3d" if mode=="2d" else "2d"
		for id in studio.library.assets:
			if id.begins_with(opposite+":") and studio.library.assets[id]["behavior"].get("building",false):
				ui.add({"kind":"building","item":{"asset":id,"position":[100,0,100],"direction":str(studio.library.directions(id)[0]),"scale":1.0}}); break
		await settle(); check(doc.data["blueprints"].size()==3 and ui.containers[mode].get_child_count()==6,"Mixed sprite/model footprints render beside native proposals: "+mode)
		studio.select_asset(asset); ui.add_center(); check(doc.data["blueprints"].size()==4,"Keyboard-accessible center action creates a building proposal: "+mode); studio._command("undo",null)
		ui.activate("blueprint_road"); var click:=InputEventMouseButton.new(); click.button_index=MOUSE_BUTTON_LEFT; click.pressed=true; click.position=studio.canvas.size*.5; studio._canvas_input(click)
		check(ui.dragging and studio.stroke,"Actual canvas input starts a deferred road gesture: "+mode)
		var cancel:=InputEventMouseButton.new(); cancel.button_index=MOUSE_BUTTON_RIGHT; cancel.pressed=true; studio._canvas_input(cancel); check(not ui.dragging and doc.data["blueprints"].size()==3,"Right-click cancels the unfinished road without construction or history: "+mode)
		ui.selected=doc.data["blueprints"][1]["uid"]; ui.locate(); await settle()
		if "--capture" in OS.get_cmdline_user_args():
			RenderingServer.force_draw(false); RenderingServer.force_draw(false); studio.worlds[mode].get_viewport().get_texture().get_image().save_png("res://output/blueprint_road_"+mode+".png")
		ui.selected=building_uid; ui.locate(); studio.set_tool("select")
		var path: String="res://output/blueprint_"+mode
		check(studio.write_project(path+".isocity.json"),"Saving includes deferred plans: "+mode)
		var repair=preload("res://scripts/builder/project_repair.gd").new(studio.library); var reopened: Dictionary=repair.read(path+".isocity.json")
		check(reopened["ok"] and repair.issues.is_empty(),"Saved proposals reopen without repair: "+mode)
		studio.show_file_dialog("export"); studio.file_dialog.hide(); studio._file_selected(path+".tscn"); studio._command("export_portable",null); studio.file_dialog.hide(); studio._file_selected(path+".zip")
		check(FileAccess.file_exists(path+".tscn") and FileAccess.file_exists(path+".zip"),"Both export actions retain proposal data and dependencies: "+mode)
		studio.changed(); await settle()
		if "--capture" in OS.get_cmdline_user_args():
			RenderingServer.force_draw(false); RenderingServer.force_draw(false); studio.worlds[mode].get_viewport().get_texture().get_image().save_png(path+".png")
	studio.queue_free(); await process_frame; await process_frame
	print("Blueprint workflow: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
