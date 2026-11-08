extends SceneTree
const Plan=preload("res://scripts/builder/neighborhood_plan.gd")
const Palettes=preload("res://scripts/builder/neighborhood_palettes.gd")
const Document=preload("res://scripts/builder/document.gd")
var checks: int=0
var failures: int=0
var library: RefCounted
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func run() -> void:
	library=preload("res://scripts/builder/asset_library.gd").new();check(Palettes.valid(Palettes.definitions()),"Reviewed catalog is bounded and readable")
	for mode in ["2d","3d"]:
		for theme in Palettes.palettes():
			var source: Dictionary=preload("res://scripts/builder/templates.gd").make(mode,"blank");var before: String=JSON.stringify(source);var config: Dictionary=Plan.defaults();config.merge({"theme":theme,"blocks":1,"density":100,"seed":17},true)
			var result: Dictionary=Plan.generate(source,config,library);var label: String=mode+"/"+theme
			if not mode in Palettes.palettes()[theme]["modes"]:
				check(not result["ok"] and result["reason"].contains("3D"),"Unsupported source representation has a useful limitation: "+label);config["density"]=0;var vacant: Dictionary=Plan.generate(source,config,library);check(vacant["ok"] and vacant["data"]["objects"].is_empty(),"Zero density still makes editable vacant streets without inventing buildings: "+label);continue
			check(result["ok"],"Reviewed theme produces safe actual source designs: "+label+result.get("reason",""))
			if not result["ok"]:continue
			check(JSON.stringify(source)==before and Document.valid(result["data"],mode,library),"Generation is private and returns a valid authored document: "+label)
			check(Plan.generate(source,config,library)["data"]==result["data"],"Current revision and seed reproduce exact appearance and scenery records: "+label)
			check(result["buildings"]==4 and result["data"]["objects"].size()==4+result["parks"]+result["props"],"Density counts building parcels independently of reviewed scenery: "+label)
			for item in result["data"]["objects"]:
				var selection: Dictionary=item.get("neighborhood_palette_selection",{});check(Palettes.valid_selection(selection) and selection["theme"]==theme and selection["revision"]==Palettes.palettes()[theme]["revision"] and selection["member"]==item["asset"],"Exact authored selection provenance remains valid: "+label)
				check(item["asset"] in Palettes.palettes()[theme][mode] if selection["role"]=="building" else item["asset"] in Palettes.palettes()[theme]["parks" if selection["role"]=="park" else "props"],"Every generated subject belongs to the explicit architectural palette: "+label)
				check(Palettes.matches_appearance(item["asset"],result["appearance"],library),"Building and scenery appearances share the district's seeded palette and lighting: "+label)
			check(not Plan.Zone.Citizen.settings(result["data"])["enabled"] and not Plan.Zone.Traffic.settings(result["data"])["enabled"] and not Plan.Zone.settings(result["data"])["enabled"],"Generation never enables simulations: "+label)
			var decoded: Dictionary=JSON.parse_string(JSON.stringify(result["data"]));check(Document.valid(decoded,mode,library),"Saved selection metadata accepts JSON integer normalization: "+label)
			var damaged: Dictionary=decoded.duplicate(true);damaged["objects"][0]["neighborhood_palette_selection"]={"version":false};check(not Document.valid(damaged,mode,library),"Unreadable saved notes are rejected: "+label);var repair=preload("res://scripts/builder/project_repair.gd").new(library);var fixed: Dictionary=repair.world(damaged,mode,"world",0);check(Document.valid(fixed,mode,library) and fixed["objects"][0]["asset"]==decoded["objects"][0]["asset"] and fixed["objects"][0]["position"]==decoded["objects"][0]["position"] and not fixed["objects"][0].has("neighborhood_palette_selection") and not repair.issues.is_empty(),"Recovery archives bad notes while retaining generated artwork and geometry: "+label)
	print("NEIGHBORHOOD PALETTES: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
