extends SceneTree
const Collections=preload("res://scripts/builder/asset_collections.gd")
const Policy=preload("res://scripts/builder/asset_palette_policy.gd")
const Templates=preload("res://scripts/builder/templates.gd")
const Rooms=preload("res://scripts/builder/interiors.gd")
const Zones=preload("res://scripts/builder/zone_plan.gd")
var library: RefCounted
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func policy(ids: Array,restricted: bool=true) -> Dictionary:
	var result: Dictionary=Collections.project_empty();result["restricted"]=restricted
	for id in ids:result["collection"]["entries"].append(Collections.asset_entry(id,library)["entry"])
	return result
func object(id: String,uid: String="original") -> Dictionary:return {"uid":uid,"asset":id,"position":[0,0,0],"direction":library.directions(id)[0],"scale":1.0}
func room_layout(value: Dictionary) -> Dictionary:
	var result: Dictionary=value.duplicate(true)
	for item in result.get("objects",[]):item.erase("uid")
	return result
func fixture(mode: String) -> Dictionary:
	var data: Dictionary=Templates.make(mode,"blank");data["zoning"]={"enabled":true,"stage_seconds":12,"seed":7};data["zones"]=[{"uid":"lot","kind":"residential","rect":[-24,8,48,48],"stage":0}];data["roads"]=[]
	for x in range(-8,9):data["roads"].append({"cell":[x,0]})
	return data
func run() -> void:
	library=preload("res://scripts/builder/asset_library.gd").new()
	var allowed: String="3d:HanX_School/Student_Chair";var excluded: String="3d:HanX_School/Teacher_Chair"
	check(not Policy.restricted(library) and Policy.allowed(excluded,library),"Legacy library defaults remain unrestricted")
	var config: Dictionary=policy([allowed],false);check(library.set_project_palette(config) and Policy.allowed(excluded,library),"Advisory recommendation allows unrelated construction")
	config["restricted"]=true;check(library.set_project_palette(config) and not Policy.allowed(excluded,library),"Explicit restriction uses saved concrete IDs")
	var revision: int=library.project_palette_revision;config["collection"]["entries"].clear()
	check(Policy.allowed(allowed,library),"Library owns an immutable snapshot of incoming palette metadata")
	check(library.set_project_palette(library.project_palette.duplicate(true)) and library.project_palette_revision==revision,"Identical metadata does not invalidate runtime eligibility")
	check(not library.set_project_palette({"restricted":false}) and not Policy.allowed(excluded,library),"Malformed metadata cannot silently disable a restriction")
	var doc: RefCounted=preload("res://scripts/builder/document.gd").new();doc.data=Templates.make("3d","blank");doc.content_library=library
	doc.data["objects"].append(object(excluded));var original: Dictionary=doc.data.duplicate(true)
	doc.checkpoint();doc.object("original")["position"][0]=7;check(doc.reconcile_economy(library),"Existing excluded object remains editable");doc.finish_checkpoint()
	check(doc.undo() and doc.data==original,"Ordinary Undo restores an existing excluded object");var redo: Array=doc.redo_history.duplicate(true)
	doc.checkpoint();doc.add(excluded,[3,0,0],library.directions(excluded)[0]);check(not doc.reconcile_economy(library) and doc.data==original and doc.economy_error.contains("Teacher Chair"),"Rejected new construction restores exact data with a named reason");doc.finish_checkpoint()
	check(doc.undo_history.is_empty() and doc.redo_history==redo,"Denied construction adds no empty history and preserves the redo branch")
	check(doc.redo() and doc.object("original")["position"][0]==7,"Historical restoration remains available after palette narrowing")
	doc.checkpoint();var added: Dictionary=doc.add(allowed,[10,0,0],library.directions(allowed)[0]);var uid: String=added["uid"];check(doc.reconcile_economy(library),"Allowed creative construction is accepted")
	var accepted: Dictionary=doc.data.duplicate(true);doc.add(excluded,[12,0,0],library.directions(excluded)[0]);check(not doc.reconcile_economy(library) and doc.data==accepted,"A later denied part preserves earlier accepted parts of the same gesture");doc.finish_checkpoint()
	check(doc.undo() and doc.object(uid).is_empty() and doc.redo() and doc.object(uid)==added,"Accepted creative transaction has exact ordinary Undo and Redo")
	var before: Dictionary=doc.data.duplicate(true);doc.data["objects"].append(object(excluded,"copied"));check(not doc.record_completed_change(before,true) and doc.data==before,"Completed financial transactions cannot bypass content policy")
	var canonical: RefCounted=preload("res://scripts/builder/document.gd").new();canonical.data=Templates.make("3d","blank");canonical.content_library=library;canonical.checkpoint();canonical.add(excluded,[0,0,0],library.directions(excluded)[0]);canonical.finish_checkpoint()
	check(canonical.data["objects"].is_empty() and canonical.undo_history.is_empty() and canonical.economy_library==null,"Owned canonical content guard creates no second treasury or rejected history")
	var floor_doc: RefCounted=preload("res://scripts/builder/floor_document.gd").new();floor_doc.configure(Templates.make("3d","blank"));floor_doc.canonical.content_library=library;floor_doc.checkpoint();floor_doc.add(allowed,[0,0,0],library.directions(allowed)[0]);floor_doc.finish_checkpoint();var floor_history: Array=floor_doc.canonical.undo_history.duplicate(true)
	floor_doc.checkpoint();floor_doc.add(excluded,[2,0,0],library.directions(excluded)[0]);floor_doc.finish_checkpoint();floor_doc.flush_room()
	check(floor_doc.data["objects"].size()==1 and floor_doc.canonical.data["objects"].size()==1 and floor_doc.canonical.undo_history==floor_history,"Rejected canonical construction rebinds the visible floor without reintroducing content or retagging prior history")
	var before_config: Dictionary=library.project_palette.duplicate(true)
	for mode in ["2d","3d"]:
		library.set_project_palette(policy([]));var building: String="2d:House_Blue" if mode=="2d" else "3d:HanX_City/Row_Houses_A";var item: Dictionary=object(building);var untouched: Dictionary=item.duplicate(true)
		var room: Dictionary=Rooms.make_for(item,mode,library);var creation: Dictionary=Rooms.creation_check(item,mode,library)
		check(not creation["ok"] and item==untouched and Rooms.ensure(item,mode,library).is_empty() and item==untouched,"Denied lazy room creation is read-only and leaves no partial room: "+mode)
		var ids: Array=[]
		for id in Collections.records(room).values():
			if not ids.has(id):ids.append(id)
		library.set_project_palette(policy(ids));check(Rooms.creation_check(item,mode,library)["ok"] and not item.has("interior"),"Full room dependency permission review stays read-only: "+mode)
		var saved_room: Dictionary=Rooms.ensure(item,mode,library);check(room_layout(saved_room)==room_layout(room) and item["interior"]==saved_room,"Allowed lazy room is created with exact supplied furnishings and transforms: "+mode)
		library.set_project_palette(policy([]));check(Rooms.ensure(item,mode,library)==saved_room,"Saved rooms remain visitable after restrictions narrow: "+mode)
		var data: Dictionary=fixture(mode);var lot: Dictionary=data["zones"][0];var empty: Dictionary=data.duplicate(true)
		check(not Zones.evaluate(data,lot,library)["ok"] and Zones.evaluate(data,lot,library)["reason"].contains("restriction") and data==empty,"Zoning explains an entirely excluded candidate set without modulo errors: "+mode)
		library.set_project_palette({});var proposed: Dictionary=Zones.evaluate(data,lot,library)
		check(proposed["ok"],"Unrestricted zoning fixture has an actual fitting candidate: "+mode)
		if not proposed["ok"]:continue
		var candidate: String=proposed["proposal"]["asset"];library.set_project_palette(policy([candidate]));var first: Dictionary=Zones.advance(data,"lot",library,"new_growth")
		check(first["ok"] and first["data"]["zones"][0]["proposal"]["asset"]==candidate,"Restricted zoning selects only an exact allowed fitting candidate: "+mode)
		if not first["ok"]:continue
		library.set_project_palette(policy([]));check(not Zones.advance(first["data"],"lot",library)["ok"],"Narrowing the palette suspends an existing incomplete growth proposal: "+mode)
		check(not Policy.check(data,first["data"],library)["ok"],"Host transaction guard includes newly reserved zoning proposals: "+mode)
		library.set_project_palette(policy([candidate]))
		var completed: Dictionary=first
		for stage in range(2,Zones.STAGE_SEQUENCE.size()):
			completed=Zones.advance(completed["data"],"lot",library)
			if not completed["ok"]: break
		var buildings: Array=completed.get("data",{}).get("objects",[])
		check(completed["ok"] and buildings.size()==1 and buildings[0]["asset"]==candidate,"Allowed zoning completes without substitutions: "+mode)
		if completed["ok"]:
			var final_data: Dictionary=completed["data"]
			library.set_project_palette(policy([]))
			check(Zones.evaluate(final_data,final_data["zones"][0],library).get("complete",false),"Already developed buildings remain intact when excluded later: "+mode)
		data=Templates.make(mode,"blank");var proposal: Dictionary=object(building);proposal.erase("uid");data["blueprints"]=[{"uid":"planned","kind":"building","item":proposal}]
		check(not preload("res://scripts/builder/blueprint_plan.gd").construct(data,["planned"],library)["ok"] and data["objects"].is_empty(),"Direct blueprint construction cannot bypass explicit restrictions: "+mode)
		library.set_project_palette(policy([building]));check(preload("res://scripts/builder/blueprint_plan.gd").construct(data,["planned"],library)["ok"],"Allowed blueprint construction retains ordinary behavior: "+mode)
	library.set_project_palette(before_config)
	print("PROJECT PALETTE POLICY: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
