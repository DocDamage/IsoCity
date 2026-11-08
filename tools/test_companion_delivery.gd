extends SceneTree
const OUT="res://output/verification/asset_expansion/U10/"
const Plan=preload("res://scripts/builder/companion_plan.gd")
const Shell=preload("res://scripts/builder/interior_kit_plan.gd")
const Floors=preload("res://scripts/builder/floor_plan.gd")
const Economy=preload("res://scripts/builder/economy_plan.gd")
const Store=preload("res://scripts/builder/project_store.gd")
const Props=preload("res://scripts/builder/prop_plan.gd")
var studio: Control
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func settle() -> void:
	for frame in 16:await process_frame
func ready() -> void:
	for frame in 900:
		var proposal: Dictionary=studio.companion_tools.proposal
		if proposal.has("ok") and (not proposal["ok"] or proposal.get("geometry_checked",false)):return
		await process_frame
	check(false,"Companion delivery review completes")
func select(uid: String) -> void:studio.selected_uid=uid;studio.selected_uids.assign([uid]);studio.refresh_controls()
func normalized(data: Dictionary) -> Dictionary:return JSON.parse_string(JSON.stringify(data))
func fixture(key: String,mode: String,at: Array) -> Dictionary:
	var id: String=Plan.definitions()["relationships"][key]["source"]
	return {"asset":id,"position":at,"direction":str(studio.library.directions(id)[0]),"scale":studio.library.assets[id]["data"].get("default_scale",1)}
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT);FileAccess.open(OUT+".gdignore",FileAccess.WRITE).close();Store.storage_root=OUT+"history";Store.legacy_autosave=OUT+"legacy.json"
	studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio);await settle();await settle();studio.consumer_shell.dismiss_welcome()
	var tools: RefCounted=studio.companion_tools
	for mode in ["2d","3d"]:
		studio.switch_mode(mode);var city:=preload("res://scripts/builder/document.gd").new();city.data=preload("res://scripts/builder/templates.gd").make(mode,"blank");studio.documents[mode]=city
		var owner: Dictionary=city.add("3d:HanX_School/School_Building",[0,0,0],"0");var uid: String=owner["uid"];owner["interior"]=Shell.shell(mode,studio.library)
		var upper: Dictionary=Floors.put_floor(owner["interior"],{"uid":"companion_upper","name":"Upper classroom","height":3,"room":Shell.shell(mode,studio.library)})
		check(upper["ok"],"Owned fixture has two ordinary empty floors");owner["interior"]=upper["data"];city.data["economy"]={"enabled":true,"starting_cash":100000};city.data["economy_account"]=Economy.fresh_account(city.data,studio.library);studio.changed();await settle()
		for floor_uid in ["ground","companion_upper"]:
			studio.interior_tools.start(uid,floor_uid);await settle();var doc: RefCounted=studio.current();var source: Dictionary=doc.add("3d:HanX_School/Student_Desk",[0,0,0] if mode=="2d" else [0,.12,0],"0",1);source["name"]="Personal desk "+floor_uid;studio.changed();doc.finish_checkpoint();select(source["uid"]);await settle()
			var original: Dictionary=source.duplicate(true);var before: Dictionary=city.data.duplicate(true);var history: int=doc.undo_history.size();var treasury: int=city.data["economy_account"]["cash"]
			tools.start();await ready();check(tools.proposal.get("ok",false) and tools.proposal.get("issues",[{}]).is_empty() and not tools.dialog.get_ok_button().disabled,"Owned floor offers a clear missing-chair proposal: "+mode+" "+floor_uid)
			if tools.dialog.get_ok_button().disabled:printerr("DELIVERY REVIEW DIAGNOSTIC: "+mode+" "+floor_uid+" "+tools.message.text+" "+JSON.stringify(tools.proposal.get("issues",[])))
			var quote: Dictionary=tools.proposal.get("quote",{}).duplicate(true);tools.apply();await settle()
			check(doc.object(source["uid"])==original and doc.undo_history.size()==history+1 and city.data["economy_account"]["cash"]==treasury-quote.get("net",0),"Canonical floor apply preserves source and charges exactly once")
			var applied: Dictionary=city.data.duplicate(true);studio._command("undo",null);await settle();check(city.data==before,"Owned companion Undo restores full city, other floor and treasury");studio._command("redo",null);await settle();check(city.data==applied,"Owned companion Redo preserves every identity and account value")
			var chairs: Array=doc.data["objects"].filter(func(item: Dictionary):return item["asset"]=="3d:HanX_School/Student_Chair")
			if chairs.is_empty():tools.dialog.hide();studio.interior_tools.leave();continue
			var chair: Dictionary=chairs[0]
			studio.set_walking(true);await settle();var exploration: Node=studio.worlds[mode].exploration;var context: Dictionary=Props.context(exploration);var candidate: Dictionary={"item":chair,"node":context["instances"][chair["uid"]],"profile":Props.profile(chair)};var at: Variant=Props.ground_point(candidate,exploration,"approach")
			exploration.player.teleport_to(exploration.player.get_parent().to_local(at));await physics_frame;exploration.player.set_physics_process(false)
			var clear: bool=Props.standing_clear(exploration,at);var used: bool=exploration.props.interact(candidate)
			if not clear or not used:printerr("CHAIR DIAGNOSTIC: "+JSON.stringify({"mode":mode,"floor":floor_uid,"clear":clear,"used":used,"at":str(at),"player":str(exploration.player.global_position),"notice":exploration.props.notice,"mask":exploration.player.collision_mask,"profile":candidate["profile"],"active_context":Props.context(exploration)["scope"]}))
			check(clear and used and not exploration.props.active.is_empty(),"Actual player can use the reviewed chair beside its desk")
			check(exploration.props.finish() and exploration.props.active.is_empty(),"Actual chair exit clears the paired desk");studio.set_walking(false)
			studio.interior_tools.leave();await settle()
		studio.interior_tools.start(uid,"companion_upper");await settle();var expected: Dictionary=city.data.duplicate(true)
		check(studio.write_project(OUT+"companion_owned_"+mode+".isocity.json"),"Save succeeds from the applied upper floor")
		var repair=preload("res://scripts/builder/project_repair.gd").new(studio.library);var reopened: Dictionary=repair.read(OUT+"companion_owned_"+mode+".isocity.json")
		check(reopened["ok"] and repair.issues.is_empty() and reopened["content"]["documents"][mode]==normalized(expected),"Owned companion project reopens without repairs or changed source settings")
		check(studio.autosave(),"Recovery writes while editing the upper companion floor");reopened=repair.read(Store.autosave_path(studio.project_id));check(reopened["ok"] and reopened["content"]["documents"][mode]==normalized(expected),"Recovery preserves the complete owning city and both paired floors")
		FileAccess.open(OUT+"blocked_parent.txt",FileAccess.WRITE).store_string("file");check(not studio.write_project(OUT+"blocked_parent.txt/project.json") and city.data==expected,"Failed write preserves live owned companions and money")
		studio.interior_tools.leave();await settle();check(studio.load_project(OUT+"companion_owned_"+mode+".isocity.json"),"Normal companion project load succeeds");await settle();if studio.interior_tools.editing():studio.interior_tools.leave()
		check(normalized(studio.current().data)==normalized(expected),"Normal reopen preserves exact authored companion records")
		# A source changed after real review must never be applied from stale geometry.
		city=preload("res://scripts/builder/document.gd").new();city.data=preload("res://scripts/builder/templates.gd").make(mode,"blank");studio.documents[mode]=city;var desk: Dictionary=city.add("3d:HanX_School/Student_Desk",[0,0,0],"0",1);studio.changed();select(desk["uid"]);await settle()
		var chair_id: String="3d:HanX_School/Student_Chair";var descriptor: Dictionary=studio.library.assets[chair_id].duplicate(true);studio.library.assets[chair_id]["path"]=OUT+"missing_chair.tscn";tools.start();await ready();check(not tools.proposal.get("ok",false) and tools.dialog.get_ok_button().disabled and not tools.message.text.is_empty(),"Missing companion has an actionable blocked review")
		studio.library.assets[chair_id]=descriptor.duplicate(true);tools.refresh_review();await ready();check(tools.proposal.get("geometry_checked",false) and not tools.dialog.get_ok_button().disabled,"Restored prepared companion refreshes the actual review")
		var copied: String=OUT+"private_chair_"+mode+".tscn";FileAccess.open(copied,FileAccess.WRITE).store_string(FileAccess.get_file_as_string(descriptor["path"]));studio.library.assets[chair_id]["path"]=copied;tools.refresh_review();await ready();var before: Dictionary=city.data.duplicate(true);var history: int=city.undo_history.size()
		FileAccess.open(copied,FileAccess.WRITE).store_string(FileAccess.get_file_as_string(descriptor["path"])+"\n; changed after exact review\n");tools.apply();check(city.data==before and city.undo_history.size()==history and tools.message.text.contains("changed"),"Changed prepared file invalidates Apply without partial construction or history");tools.dialog.hide();studio.library.assets[chair_id]=descriptor
		# Build permitted source sets without changing any source export flag.
		city.data=preload("res://scripts/builder/templates.gd").make(mode,"blank");var index: int=0
		for recipe in ["classroom_desk","covered_pump","shelf_stock"]:
			var at: Array=[index*640,0,0] if mode=="2d" else [index*20,0,0];var proposal: Dictionary=Plan.propose(city.data,{},recipe,"",fixture(recipe,mode,at),studio.library);check(proposal["ok"],"Permitted native source set prepares: "+recipe);city.data=Plan.materialize(proposal)["data"];index+=1
		studio.clear_placement();studio.changed();await settle();check(Store.write_json(OUT+"expected_companions_"+mode+".json",city.data),"Permitted source-set expectation saved")
		var exported: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],city.data,studio.library,OUT+"companions_"+mode+".zip");check(exported["ok"],"All three permitted paired source sets export together")
		var camp: Dictionary=Plan.propose(city.data,{},"camp_cooking","",fixture("camp_cooking",mode,[1920,0,0] if mode=="2d" else [60,0,0]),studio.library);check(camp["ok"],"Restricted camping companions remain available for local editing");city.data=Plan.materialize(camp)["data"];studio.changed();await settle();exported=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],city.data,studio.library,OUT+"restricted_camping_"+mode+".zip");check(not exported["ok"] and not FileAccess.file_exists(OUT+"restricted_camping_"+mode+".zip"),"Camping source permissions reject the complete portable export")
	studio.free();await process_frame;await process_frame;print("COMPANION DELIVERY: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
