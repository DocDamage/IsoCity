extends SceneTree
const Plan=preload("res://scripts/builder/floor_plan.gd")
const Doc=preload("res://scripts/builder/document.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func press(parent: Node,text: String) -> void:
	for button in parent.find_children("*","Button",true,false):
		if button.text==text: button.pressed.emit(); return
	check(false,"Button exists: "+text)
func choose(tools: RefCounted,uid: String) -> void:
	for index in tools.choice.item_count:
		if tools.choice.get_item_metadata(index)==uid: tools.choice.select(index); tools.choice.item_selected.emit(index); return
	check(false,"Floor exists in selector: "+uid)
func run() -> void:
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio)
	for frame in 5: await process_frame
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		var outer: RefCounted=studio.current(); var before: Dictionary=outer.data.duplicate(true)
		var building: Dictionary=outer.data["objects"].filter(func(item: Dictionary)->bool:return studio.library.assets[item["asset"]]["behavior"].get("building",false))[0]
		var building_uid: String=building["uid"]
		studio.interior_tools.start(building_uid)
		var doc: RefCounted=studio.current(); var tools: RefCounted=studio.interior_tools.floor_tools
		check(tools.row.visible and tools.choice.item_count==1 and doc.floor_uid=="ground","Owned interior starts on its original ground floor: "+mode)
		var ground_count: int=doc.data["objects"].size()
		tools.manage.pressed.emit(); tools.new_name.text="Apartment"; tools.new_height.value=3
		press(tools.dialog,"Add floor")
		var upper: String=doc.floor_uid
		check(upper!="ground" and tools.choice.item_count==2 and doc.data["objects"].is_empty(),"Add floor creates and selects a separately editable empty room: "+mode)
		check(doc.canonical.data["objects"].size()==ground_count and Plan.valid(doc.canonical.data),"Adding upstairs leaves the ground room intact: "+mode)
		tools.dialog.hide()
		doc.checkpoint(); var furniture: Dictionary=doc.add("2d:Sofa_Teal",[40,20,0] if mode=="2d" else [2,0,1],"SE"); var furniture_uid: String=furniture["uid"]; studio.changed()
		check(studio.worlds[mode].instances.has(furniture_uid),"Upper-floor furnishing uses normal editor rendering: "+mode)
		choose(tools,"ground")
		check(doc.data["objects"].size()==ground_count and not studio.worlds[mode].instances.has(furniture_uid),"Switching floors shows only that room's editable contents: "+mode)
		doc.checkpoint(); var ground_prop: Dictionary=doc.add("2d:Plant_Monstera",[60,20,0] if mode=="2d" else [3,0,1],"SE"); var ground_uid: String=ground_prop["uid"]; studio.changed()
		studio._command("undo",null)
		check(doc.floor_uid=="ground" and doc.object(ground_uid).is_empty(),"Undo removes the latest ground edit: "+mode)
		studio._command("undo",null)
		check(doc.floor_uid==upper and doc.object(furniture_uid).is_empty() and tools.choice.get_item_metadata(tools.choice.selected)==upper,"Undo follows the preceding edit upstairs and updates the selector: "+mode)
		studio._command("undo",null)
		check(doc.floor_uid=="ground" and doc.canonical.data.get("floors",[]).is_empty(),"Undo removes the original floor addition after its edits: "+mode)
		studio._command("redo",null)
		check(doc.floor_uid==upper and doc.data["objects"].is_empty(),"Redo recreates and selects the added floor: "+mode)
		studio._command("redo",null)
		check(doc.floor_uid==upper and not doc.object(furniture_uid).is_empty(),"Redo restores the upstairs furnishing: "+mode)
		studio._command("redo",null)
		check(doc.floor_uid=="ground" and not doc.object(ground_uid).is_empty(),"Redo returns to the following ground edit: "+mode)
		var history_size: int=doc.undo_history.size()
		choose(tools,upper); choose(tools,"ground"); choose(tools,upper)
		check(doc.undo_history.size()==history_size,"Floor navigation adds no history entries: "+mode)
		choose(tools,"ground"); tools.manage.pressed.emit()
		check(not tools.height_input.editable and tools.remove_button.disabled and studio.modal_visible(),"Ground height/removal are protected and the floor dialog suspends canvas shortcuts: "+mode)
		tools.name_input.text="Lobby"; press(tools.dialog,"Apply name and height"); tools.dialog.hide()
		check(doc.canonical.data["floor_name"]=="Lobby" and not Plan.room(doc.canonical.data,upper).is_empty(),"Renaming ground retains every additional floor: "+mode)
		studio._command("undo",null); check(not doc.canonical.data.has("floor_name"),"Ground names participate in the shared history: "+mode)
		choose(tools,upper)
		tools.manage.pressed.emit(); tools.name_input.text="Upper apartment"; tools.height_input.value=3.5; press(tools.dialog,"Apply name and height")
		check(doc.canonical.data["floors"][0]["name"]=="Upper apartment" and doc.canonical.data["floors"][0]["height"]==3.5,"Name and height edits use the selected floor: "+mode)
		tools.height_input.value=1; press(tools.dialog,"Apply name and height")
		check(doc.canonical.data["floors"][0]["height"]==3.5 and not tools.message.text.is_empty(),"Invalid height keeps existing floor content and displays an explanation: "+mode)
		tools.dialog.hide()
		var room_before: Dictionary=doc.data.duplicate(true); doc.object(furniture_uid)["position"][0]+=10
		check(doc.record_completed_change(room_before),"Completed transform gestures record an upstairs change: "+mode)
		studio.changed(); studio._command("undo",null)
		check(doc.floor_uid==upper and doc.object(furniture_uid)["position"]==room_before["objects"][0]["position"],"Undo rebinds the active room after a completed transform: "+mode)
		doc.checkpoint(); doc.object(furniture_uid)["name"]="Independent upstairs sofa"; studio.changed(); doc.finish_checkpoint()
		check(doc.redo_history.is_empty() and studio.redo_button.disabled,"A new edit clears redo across all floors: "+mode)
		var saved: Dictionary=studio.session_data()
		check(Doc.valid(saved["documents"][mode],mode,studio.library) and saved["documents"][mode]["objects"].filter(func(item: Dictionary):return item["uid"]==building_uid)[0]["interior"]["objects"].size()==ground_count+1,"Saving upstairs serializes the complete exterior and ground room: "+mode)
		var path: String="user://floor_workflow_"+mode+".isocity.json"
		check(studio.write_project(path) and not studio.dirty,"Project saves while an upper floor is active: "+mode)
		tools.manage.pressed.emit(); press(tools.dialog,"Remove selected floor and its contents")
		check(doc.floor_uid=="ground" and doc.canonical.data.get("floors",[]).is_empty(),"Removing the active upper floor returns to ground: "+mode)
		tools.dialog.hide(); studio._command("undo",null)
		check(not Plan.room(doc.canonical.data,upper).is_empty() and Plan.room(doc.canonical.data,upper)["objects"][0]["name"]=="Independent upstairs sofa","Undo restores a removed floor and all authored contents: "+mode)
		choose(tools,upper)
		if "--capture" in OS.get_cmdline_user_args():
			tools.manage.pressed.emit()
			for frame in 5: await process_frame
			RenderingServer.force_draw(false); RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png("res://output/floor_editor_"+mode+".png")
			tools.dialog.hide()
		studio.interior_tools.leave()
		check(studio.current()==outer and not tools.row.visible,"Returning to city restores its document and hides floor controls: "+mode)
		check(outer.undo() and outer.data==before,"The entire multi-floor visit is one city undo step: "+mode)
		check(outer.redo() and Plan.room(outer.object(building_uid)["interior"],upper)["objects"][0]["name"]=="Independent upstairs sofa","City redo restores all floors and furnishings: "+mode)
		studio.changed(); studio.interior_tools.start(building_uid); choose(tools,upper)
		check(doc!=studio.current() and studio.current().object(furniture_uid)["name"]=="Independent upstairs sofa","Reopening a building retains its independently furnished upper floor: "+mode)
		check(studio.load_project(path) and not studio.interior_tools.editing(),"A saved multi-floor project reopens in city context: "+mode)
		check(Plan.room(studio.current().object(building_uid)["interior"],upper)["objects"][0]["name"]=="Independent upstairs sofa","Project reopen retains the saved upstairs contents: "+mode)
		var city: RefCounted=studio.current(); city.data["economy"]={"enabled":true,"starting_cash":0}
		city.data["economy_account"]=preload("res://scripts/builder/economy_plan.gd").fresh_account(city.data,studio.library); studio.changed()
		studio.interior_tools.start(building_uid); choose(tools,upper)
		doc=studio.current(); var count: int=doc.data["objects"].size(); var history_before: int=doc.undo_history.size()
		doc.checkpoint(); doc.add("2d:Sofa_Teal",[80,40,0] if mode=="2d" else [4,0,2],"SE"); studio.changed(); doc.finish_checkpoint()
		check(doc.floor_uid==upper and doc.data["objects"].size()==count and not city.economy_error.is_empty(),"An upstairs budget rejection restores that floor without replacing it with ground: "+mode)
		check(doc.undo_history.size()==history_before,"Rejected upstairs placement leaves no empty history step: "+mode)
		var costly_room: Dictionary=preload("res://scripts/builder/interiors.gd").make(mode,"Unaffordable")
		var costly: Dictionary={"uid":"costly","name":"Unaffordable","height":6,"room":costly_room}
		tools.commit(Plan.put_floor(doc.canonical.data,costly),"costly")
		check(Plan.room(doc.canonical.data,"costly").is_empty() and doc.floor_uid=="ground" and not tools.message.text.is_empty(),"A rejected furnished floor addition restores the owned plan and reports its budget failure: "+mode)
		check(doc.undo_history.size()==history_before,"Rejected floor creation leaves no misleading Undo entry: "+mode)
		var original_size: Vector2i=root.size
		studio.accessibility_settings.restore({"text_scale":1.5,"high_contrast":true,"large_targets":true,"shape_markers":true})
		root.size=Vector2i(960,640)
		for frame in 8: await process_frame
		tools.manage.pressed.emit()
		for frame in 5: await process_frame
		check(tools.dialog.size.x<=960 and tools.dialog.size.y<=600,"Floor management fits the minimum viewport with enlarged text and targets: "+mode)
		tools.dialog.hide(); studio.accessibility_settings.restore({}); root.size=original_size
		studio.interior_tools.leave()
	studio.queue_free(); await process_frame
	print("FLOOR WORKFLOW: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
