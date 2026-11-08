extends SceneTree

const Plan = preload("res://scripts/builder/blueprint_plan.gd")
const Doc = preload("res://scripts/builder/document.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const Rooms = preload("res://scripts/builder/interiors.gd")
const Economy = preload("res://scripts/builder/economy_plan.gd")
const Traffic = preload("res://scripts/builder/traffic_plan.gd")
var checks: int = 0
var failures: int = 0
var output: String = "res://output/functional_assembly_fixture"

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: " + message)

func settle() -> void:
	for frame in 8:
		await process_frame
	await physics_frame

func item(uid: String, asset: String, at: Array, scale_value: float = 1.0) -> Dictionary:
	return {"uid": uid, "asset": asset, "position": at, "direction": "0", "scale": scale_value}

func furnished(mode: String, host_asset: String, position: Array) -> Dictionary:
	var host: Dictionary = item("host", host_asset, position, .25)
	host["citizen_role"] = "work"
	host["business"] = {"kind": "service", "capacity": 1, "open_hour": 0, "close_hour": 23.9, "duration_scale": 1}
	var room: Dictionary = Rooms.make(mode, "Assembly fixture")
	room["objects"] = []
	var upper: Dictionary = room.duplicate(true)
	upper["objects"] = [
		item("chair", "3d:HanX_School/Student_Chair", [0,-32,0] if mode=="2d" else [-2,.12,-2]),
		item("switch", "3d:HanX_School/Student_Chair", [112,-32,0] if mode=="2d" else [5,.12,-2]),
		item("device", "3d:HanX_School/Student_Chair", [160,-48,0] if mode=="2d" else [7,.12,-2])
	]
	upper["objects"][1]["prop"] = {"kind": "switch", "target": "device"}
	upper["objects"][2]["prop"] = {"kind": "appliance"}
	room["floors"] = [{"uid": "upper", "name": "Workroom", "height": 3, "room": upper}]
	room["floor_links"] = [{"uid": "stairs", "kind": "stairs", "lower": "ground", "upper": "upper", "start": [0,0], "end": [0,6], "width": 1.2}]
	host["interior"] = room
	return host

func rejection_edges(data: Dictionary, uid: String, library: RefCounted, mode: String) -> void:
	var poor: Dictionary = data.duplicate(true)
	poor["economy_account"]["cash"] = 0
	var before: Dictionary = poor.duplicate(true)
	var rejected: Dictionary = Plan.construct(poor,[uid],library)
	check(not rejected["ok"] and rejected["reason"].contains("budget") and poor==before,"Insufficient funds leave the proposal and city intact: "+mode)
	var broken: Dictionary = data.duplicate(true)
	broken["blueprints"][0]["objects"][0]["interior"]["floors"][0]["room"]["objects"][1]["prop"]["target"]="outside-room"
	before=broken.duplicate(true)
	rejected=Plan.construct(broken,[uid],library)
	check(not rejected["ok"] and rejected["reason"].contains("outside its floor") and broken==before,"Manual cross-floor target cannot partly construct: "+mode)
	var utility: Dictionary = data.duplicate(true)
	utility["blueprints"][0]["connections"]=[{"uid":"edge_supply","kind":"water","from":{"object_uid":"host","socket":"supply"},"to":{"object_uid":"city-main","socket":"tap"}}]
	before=utility.duplicate(true)
	rejected=Plan.construct(utility,[uid],library)
	check(not rejected["ok"] and rejected["reason"].contains("utility") and utility==before,"Unresolved utility connection retains the exact assembly: "+mode)
	var undeclared: Dictionary=data.duplicate(true)
	undeclared["blueprints"][0]["external_targets"]=[]
	check(not Plan.construct(undeclared,[uid],library)["ok"],"An undeclared city target never binds by coincidence: "+mode)
	var removed: Dictionary=data.duplicate(true)
	removed["objects"]=removed["objects"].filter(func(value: Dictionary):return value["uid"]!="external_device")
	check(not Plan.construct(removed,[uid],library)["ok"],"A declared external target must still exist at review time: "+mode)
	var missing: Dictionary = data.duplicate(true)
	missing["blueprints"][0]["objects"][0]["interior"]["floors"][0]["room"]["objects"][0]["asset"]="3d:Absent_Pack/Seat"
	before=missing.duplicate(true)
	check(not Plan.construct(missing,[uid],library)["ok"] and missing==before,"A missing nested source cannot construct the rest: "+mode)
	var desk: Dictionary=library.assets["3d:HanX_School/Teacher_Desk"]
	var existing_path: String=desk["path"]
	desk["path"]="res://scenes/items_3d/Absent_Teacher_Desk.tscn"
	rejected=Plan.construct(data,[uid],library)
	desk["path"]=existing_path
	check(not rejected["ok"] and rejected["reason"].contains("Teacher_Desk"),"A catalogued fixture whose scene is missing cannot construct: "+mode)
	var repair=preload("res://scripts/builder/project_repair.gd").new(library)
	var recovered: Dictionary=repair.world(missing,mode,"assembly",0)
	check(recovered["blueprints"].size()==1 and Doc.valid(recovered,mode,library) and not repair.issues.is_empty(),"Reopening a missing pack retains the repairable assembly: "+mode)
	check(not Plan.construct(recovered,[uid],library)["ok"],"A recovered placeholder still prevents construction: "+mode)
	var limits: Dictionary = data.duplicate(true)
	var floors: Array = limits["blueprints"][0]["objects"][0]["interior"]["floors"]
	for index in 7:
		var duplicate: Dictionary=floors[0].duplicate(true)
		duplicate["uid"]="extra_"+str(index)
		duplicate["height"]=6+3*index
		floors.append(duplicate)
	check(not Plan.construct(limits,[uid],library)["ok"],"Nested floor limits apply before construction: "+mode)
	var locked: Dictionary=data.duplicate(true)
	locked["layers"]={"Buildings":{"locked":true}}
	check(not Plan.construct(locked,[uid],library)["ok"],"Locked destination layer blocks the entire assembly: "+mode)

func run() -> void:
	if OS.has_environment("ISOCITY_ASSEMBLY_FIXTURE_OUTPUT"):
		output=OS.get_environment("ISOCITY_ASSEMBLY_FIXTURE_OUTPUT")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var studio: Control = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	await settle()
	if studio.consumer_shell: studio.consumer_shell.dismiss_welcome()
	for mode in ["2d", "3d"]:
		studio.switch_mode(mode)
		var doc: RefCounted=Doc.new()
		doc.data=Templates.make(mode,"blank")
		studio.documents[mode]=doc
		doc.economy_library=studio.library
		doc.content_library=studio.library
		studio.economy_tools.pauses[mode]=true
		doc.data["economy"]={"enabled":true,"starting_cash":1000000,"period_seconds":60}
		var school: Dictionary=furnished(mode,"3d:HanX_School/School_Building",Traffic.world(Vector2(0,0),mode))
		var shop: Dictionary=furnished(mode,"3d:HanX_Shop/Shop_Cafe",Traffic.world(Vector2(20,0),mode))
		var garage: Dictionary=furnished(mode,"3d:HanX_GasStation/Repair_Garage",Traffic.world(Vector2(40,0),mode))
		shop["uid"]="shop"
		garage["uid"]="garage"
		var device: Dictionary=item("external_device","3d:HanX_School/Student_Chair",Traffic.world(Vector2(-20,10),mode))
		device["prop"]={"kind":"appliance"}
		var control: Dictionary=item("control","3d:HanX_School/Student_Chair",Traffic.world(Vector2(15,9),mode))
		control["prop"]={"kind":"switch","target":"external_device"}
		doc.data["objects"]=[school,shop,garage,device,control]
		doc.data["economy_account"]=Economy.fresh_account(doc.data,studio.library)
		studio.changed()
		await settle()
		studio.selected_uid="host"
		studio.selected_uids.assign(["host","shop","garage","control"])
		studio._command("blueprints",null)
		var ui: RefCounted=studio.blueprint_tools
		var unchanged: Array=doc.data["objects"].duplicate(true)
		var cash: int=doc.data["economy_account"]["cash"]
		ui.capture_assembly()
		check(ui.entry().get("kind","")=="assembly" and doc.data["objects"]==unchanged and doc.data["economy_account"]["cash"]==cash,"The normal capture action stages a furnished assembly for free: "+mode)
		if ui.entry().is_empty(): continue
		var uid: String=ui.selected
		ui.review([uid])
		check(ui.reviewed.is_empty() and ui.review_label.text.contains("overlap"),"The original occupied location is rejected before commit: "+mode+" "+ui.review_label.text)
		var proposal: Dictionary=Plan.moved_assembly(ui.entry(),Traffic.world(Vector2(64,56),mode),mode)
		proposal["objects"][0]["interior"]["floors"][0]["room"]["objects"].append(item("planned_desk","3d:HanX_School/Teacher_Desk",[-48,-16,0] if mode=="2d" else [-6,.12,-4]))
		doc.data["blueprints"][0]=proposal
		ui.sketch_assembly_road()
		ui.finish_road({"start":[8,9],"end":[13,9],"settings":{"style":"gravel","width":6,"sidewalks":false}})
		studio.set_tool("select")
		studio.selected_uid=""
		studio.selected_uids.clear()
		studio.refresh_controls()
		studio._command("blueprints",null)
		await settle()
		var visuals: Array=ui.containers[mode].get_children().filter(func(node: Node):return node.has_meta("blueprint_member"))
		check(visuals.size()==4 and ui.entry()["roads"].size()==1,"The assembly renders all four translated poses and the attached road: "+mode)
		if visuals.size()==4:
			var expected: Array=proposal["objects"][0]["position"]
			check(visuals[0].position.is_equal_approx(Vector2(expected[0],expected[1])) if mode=="2d" else visuals[0].position.is_equal_approx(Vector3(expected[0],expected[1],expected[2])),"The first rendered ghost uses the proposed native pose: "+mode)
		if "--capture" in OS.get_cmdline_user_args():
			ui.locate()
			var shell: String="simple" if studio.consumer_shell and studio.consumer_shell.active else "precision"
			for dimensions in [Vector2i(1480,900),Vector2i(960,640)]:
				root.size=dimensions
				studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true} if dimensions.x==960 else {})
				if dimensions.x==960: studio.workspace_layout.library_toggle.button_pressed=false
				await settle()
				ui.locate()
				ui.review_button.grab_focus()
				ui.review_button.pressed.emit()
				await settle()
				var focused: Rect2=ui.review_button.get_global_rect()
				check(ui.review_button.has_focus() and Rect2(Vector2.ZERO,Vector2(root.size)).encloses(focused) and ui.panel.get_global_rect().encloses(focused),"The Review assembly action stays visible with focus: "+mode+" "+str(dimensions))
				var tab:=InputEventKey.new()
				tab.keycode=KEY_TAB
				tab.physical_keycode=KEY_TAB
				tab.pressed=true
				Input.parse_input_event(tab)
				await process_frame
				tab=tab.duplicate()
				tab.pressed=false
				Input.parse_input_event(tab)
				await settle()
				var note: Rect2=ui.review_label.get_global_rect()
				check(ui.review_label.has_focus() and ui.review_label.text.contains("credits") and Rect2(Vector2.ZERO,Vector2(root.size)).encloses(note) and ui.panel.get_global_rect().encloses(note),"Tab reveals the complete construction quote: "+mode+" "+str(dimensions))
				RenderingServer.force_draw(false)
				RenderingServer.force_draw(false)
				check(root.get_texture().get_image().save_png((output+"/assembly_%s_%s_%d.png")%[mode,shell,dimensions.x])==OK,"Native assembly preview captured: "+mode)
			root.size=Vector2i(1480,900)
			studio.accessibility_settings.restore({})
		var source: Dictionary=doc.data.duplicate(true)
		var candidate: Dictionary=Plan.construct(source,[uid],studio.library)
		check(candidate["ok"],"Furnished shop, classroom and service compound validate together: "+mode+" "+candidate.get("reason",""))
		if not candidate["ok"]: continue
		var expected_cash: int=candidate["quote"]["account"]["cash"]
		check(candidate["quote"]["construction"]>0 and expected_cash<cash and source==doc.data,"Preview computes complete construction without changing the document: "+mode)
		rejection_edges(source,uid,studio.library,mode)
		ui.review([uid])
		doc.data["blueprints"][0]["name"]="Edited after review"
		var modified: Dictionary=doc.data.duplicate(true)
		var history: int=doc.undo_history.size()
		ui.construct(false)
		check(doc.data==modified and doc.undo_history.size()==history and not ui.reviewed.is_empty(),"An edited proposal requires a fresh review before building: "+mode)
		var pending_path: String=output+"/assembly_pending_"+mode
		check(studio.write_project(pending_path+".isocity.json",false),"A deferred assembly saves through the real project writer: "+mode)
		var repair=preload("res://scripts/builder/project_repair.gd").new(studio.library)
		var reopened: Dictionary=repair.read(pending_path+".isocity.json")
		check(reopened["ok"] and repair.issues.is_empty() and reopened["content"]["documents"][mode]["blueprints"][0]["uid"]==uid,"A deferred assembly reopens with its authored identity: "+mode)
		studio._command("export_portable",null)
		studio.file_dialog.hide()
		studio._file_selected(pending_path+".zip")
		check(FileAccess.file_exists(pending_path+".zip"),"An allowed deferred assembly exports with dependencies: "+mode)
		ui.construct(false)
		check(doc.data["blueprints"].is_empty() and doc.data["objects"].size()==9 and doc.data.get("roads",[]).size()==6 and doc.data["economy_account"]["cash"]==expected_cash,"One commit creates and charges the entire assembly: "+mode)
		if not doc.data["blueprints"].is_empty(): continue
		var maps: Dictionary=candidate["remaps"][uid]
		var built: Dictionary=doc.object(maps["objects"]["host"])
		var interior: Dictionary=built["interior"]
		var upper: Dictionary=interior["floors"][0]
		var furnishings: Array=upper["room"]["objects"]
		check(upper["uid"]!="upper" and interior["floor_links"][0]["upper"]==upper["uid"] and furnishings[1]["prop"]["target"]==furnishings[2]["uid"] and furnishings[2]["uid"]!="device","Nested floor and prop targets point to their new identities: "+mode)
		check(doc.object(maps["objects"]["control"])["prop"]["target"]=="external_device" and doc.object("host")==school and built["business"]==school["business"],"External city target, original objects and business definitions remain scoped: "+mode)
		var committed: Dictionary=doc.data.duplicate(true)
		ui.construct(false)
		check(doc.data==committed and doc.undo_history.size()==history+1,"A repeat commit makes no history, charge or objects: "+mode)
		studio._command("undo",null)
		check(doc.data==modified,"One Undo restores exact proposals and balance: "+mode)
		studio._command("redo",null)
		check(doc.data==committed,"One Redo restores the same built identities and account: "+mode)
		var path: String=output+"/assembly_built_"+mode
		check(studio.write_project(path+".isocity.json",false),"Built assembly saves normally: "+mode)
		studio._command("export_portable",null)
		studio.file_dialog.hide()
		studio._file_selected(path+".zip")
		check(FileAccess.file_exists(path+".zip"),"Built assembly exports normally: "+mode)
		check(studio.load_project(path+".isocity.json"),"Built assembly reopens normally: "+mode)
		await settle()
		check(JSON.parse_string(JSON.stringify(studio.current().data))==JSON.parse_string(JSON.stringify(committed)),"Save and reopen retain remapped references and treasury: "+mode)
	studio.free()
	await settle()
	print("FUNCTIONAL ASSEMBLIES: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
