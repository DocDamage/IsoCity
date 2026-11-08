extends "res://tools/test_zone_plan.gd"
const Candidates=preload("res://scripts/builder/zone_candidates.gd")
const ZoneWorkflow=preload("res://tools/test_zone_workflow.gd")
func run() -> void:
	var output: String=ZoneWorkflow.fixture_output(ZoneWorkflow.EXPECTATION_OUTPUT)+"/"
	DirAccess.make_dir_recursive_absolute(output);library=preload("res://scripts/builder/asset_library.gd").new();var original_catalog: Dictionary=Candidates.definitions().duplicate(true);var selections: Dictionary={}
	for mode in ["2d","3d"]:
		for seed_value in range(1,65):
			var data: Dictionary=fixture(mode,"residential");data["zoning"]["seed"]=seed_value;data["zones"][0]["max_price"]=2000;var state: Dictionary=Plan.evaluate(data,data["zones"][0],library)
			check(state["ok"] and state["cost"]==2000,"Price eligibility precedes seeded design selection: "+mode+str(seed_value))
			if state["ok"]:selections[mode+"/"+state["selection"]["family"]]=true
		check(selections.keys().filter(func(key: String):return key.begins_with(mode+"/")).size()>=3,"Several distinct reviewed designs can grow without changing the theme: "+mode)
		var data: Dictionary=fixture(mode,"residential");data["economy"]={"enabled":true,"starting_cash":10000};data["economy_account"]=Economy.fresh_account(data,library);var first: Dictionary=Plan.advance(data,data["zones"][0]["uid"],library,"retained_growth");check(first["ok"],"Expanded choice creates a saved ordinary foundation: "+mode)
		if not first["ok"]:continue
		var selected: Dictionary=first["data"]["zones"][0]["proposal"].duplicate(true);var notes: Dictionary=first["data"]["zones"][0]["selection"].duplicate(true);var cost: int=Economy.profile(selected["asset"],library)["construction"]
		check(Plan.Citizen.role(selected)=="home" and selected.get("citizen_role")=="home","Residential construction stamps its authored household role independently of catalog price/income: "+mode)
		var retired: Dictionary=original_catalog.duplicate(true);retired["revision"]="ab".repeat(32);retired["families"]=retired["families"].filter(func(entry: Dictionary):return entry["id"]!=notes["family"]);Candidates.cached=retired
		check(preload("res://scripts/builder/document.gd").valid(first["data"],mode,library),"Saved construction remains valid after its candidate family is retired: "+mode)
		var second: Dictionary=Plan.advance(first["data"],first["data"]["zones"][0]["uid"],library);check(second["ok"] and second["data"]["zones"][0]["proposal"]==selected and second["data"]["zones"][0]["selection"]==notes,"Catalog changes never reselect an existing unfinished building or its saved provenance: "+mode)
		if not second["ok"]:Candidates.cached=original_catalog;continue
		var poor: Dictionary=second["data"].duplicate(true);poor["economy_account"]["cash"]=0;var poor_copy: String=JSON.stringify(poor);var refused: Dictionary=Plan.advance(poor,poor["zones"][0]["uid"],library)
		check(not refused["ok"] and refused["reason"].contains("budget") and JSON.stringify(poor)==poor_copy,"Insufficient completion funds retain the exact saved framing plan and original data: "+mode)
		var finishing: Dictionary=Plan.advance(second["data"],second["data"]["zones"][0]["uid"],library)
		check(finishing["ok"] and finishing["data"]["zones"][0]["stage"]==Plan.Stage.FINISHING and finishing["data"]["zones"][0]["proposal"]==selected,"The retired design retains its exact selection through finishing: "+mode)
		var third: Dictionary=Plan.advance(finishing["data"],finishing["data"]["zones"][0]["uid"],library);check(third["ok"] and third["data"]["objects"].back()==selected and third["data"]["economy_account"]["cash"]==10000-cost,"Retired design still completes as the exact chosen object at its normal price: "+mode)
		if third["ok"]:
			var completed: Dictionary=third["data"].duplicate(true);completed["objects"].back()["asset"]="2d:House_Blue";completed["objects"].back()["direction"]="SE";var copy: String=JSON.stringify(completed)
			check(Plan.evaluate(completed,completed["zones"][0],library).get("complete",false) and JSON.stringify(completed)==copy,"Manual replacement of a completed zoned object stays editable and never respawns the old selection: "+mode)
			completed["objects"].pop_back();var vacant: Dictionary=Plan.advance(completed,completed["zones"][0]["uid"],library)
			check(vacant["ok"] and vacant["data"]["zones"][0]["stage"]==0 and not vacant["data"]["zones"][0].has("proposal") and not vacant["data"]["zones"][0].has("selection"),"Removing a completed building starts a later cycle without stale selection notes or immediate rebuilding: "+mode)
		var damaged: Dictionary=first["data"].duplicate(true);damaged["zones"][0].merge({"theme":[],"density":true,"max_price":-2,"selection":{"version":true}},true);var repair=preload("res://scripts/builder/project_repair.gd").new(library);var recovered: Dictionary=repair.world(damaged,mode,"world",0)
		check(recovered["zones"].size()==1 and recovered["zones"][0]["stage"]==1 and recovered["zones"][0]["proposal"]==selected and not recovered["zones"][0].has("selection") and repair.issues.size()>=4,"Repair isolates unreadable filters/notes without discarding a usable selected building: "+mode)
		Candidates.cached=original_catalog
	# Real missing dependency behind a cached prepared-scene descriptor.
	var root_path: String=output+"candidate_root.tscn";var child_path: String=output+"candidate_child.tscn";var child_text: String='[gd_scene format=3]\n[node name="PrivateDependency" type="Node3D"]\n';FileAccess.open(child_path,FileAccess.WRITE).store_string(child_text);FileAccess.open(root_path,FileAccess.WRITE).store_string('[gd_scene load_steps=2 format=3]\n[ext_resource type="PackedScene" path="'+child_path+'" id="1"]\n[node name="PrivateRoot" instance=ExtResource("1")]\n')
	check(Candidates.source_ready(root_path),"Prepared dependency graph is initially valid");var cached_scene: PackedScene=load(root_path);check(cached_scene!=null,"Fixture has an actual Godot resource cached before its source disappears")
	var absolute: String=ProjectSettings.globalize_path(child_path);check(absolute.begins_with(ProjectSettings.globalize_path(output)) and DirAccess.remove_absolute(absolute)==OK,"Only the explicit private dependency fixture is removed")
	check(not Candidates.source_ready(root_path),"An in-memory Godot scene cannot conceal a missing prepared dependency");FileAccess.open(child_path,FileAccess.WRITE).store_string(child_text);check(Candidates.source_ready(root_path),"Restoring the actual dependency recovers without restarting the editor")
	var source_id: String="3d:HanX_City/Row_Houses_A";var saved_descriptor: Dictionary=library.assets[source_id].duplicate(true);library.assets[source_id]["path"]=root_path;var pending: Dictionary=fixture("3d","residential");pending["zones"][0]["stage"]=1;pending["zones"][0]["proposal"]={"uid":"forced_check","asset":source_id,"zone_uid":pending["zones"][0]["uid"],"direction":"0","scale":1.0,"position":[0,0,32]}
	check(Candidates.source_ready(root_path),"Transaction regression starts with a warmed good dependency graph");DirAccess.remove_absolute(absolute);var pending_before: String=JSON.stringify(pending);var result: Dictionary=Plan.advance(pending,pending["zones"][0]["uid"],library)
	check(not result["ok"] and result["reason"].contains("dependencies") and JSON.stringify(pending)==pending_before,"Immediate construction forces source validation even inside the advisory cache window");FileAccess.open(child_path,FileAccess.WRITE).store_string(child_text);library.assets[source_id]=saved_descriptor
	var file:=FileAccess.open(output+"expanded_seed_choices.json",FileAccess.WRITE);file.store_string(JSON.stringify(selections.keys(),"\t"));file.close();print("ZONE EXPANSION: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
