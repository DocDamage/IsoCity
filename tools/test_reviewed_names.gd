extends SceneTree
const OUTPUT = "res://output/verification/asset_expansion/I04"
var checks: int = 0
var failures: int = 0
func check(value: bool, message: String) -> void:
	checks+=1
	if not value:failures+=1;print("FAIL: "+message)
func _initialize() -> void:call_deferred("run")
func settle() -> void:
	for frame in 8:await process_frame
func run() -> void:
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new()
	var names: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/catalog/reviewed_names.json"))["assets"]
	check(names.size()==1693,"Explicit visually reviewed name inventory")
	for id in names:
		var asset: Dictionary=library.assets[id]
		check(asset["name"]==names[id]["display_name"] and asset["data"].get("source_name")==names[id]["source_name"],"Display name leaves exact source name intact: "+id)
		check(asset["data"]["aliases"]==names[id]["aliases"] and asset["data"]["name_key"]=="asset."+id,"Aliases and translation key are data, separate from stable ID: "+id)
		if names[id]["source_name"]==null:
			check(asset["data"].get("name_source","").begins_with("res://assets/") and library.pack_name(asset)=="RPG World", "Native imports retain their original pack and show actual source files: "+id)
	var fixtures: Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/catalog/reviewed_name_queries.json"))["queries"]
	for fixture in fixtures:
		var found: Array=library.find("all","All assets",fixture["query"],[],false,fixture["pack"])
		check(found.any(func(asset: Dictionary):return asset["id"]==fixture["id"]),"Ordinary query retrieves reviewed artwork: "+fixture["query"])
		var seen: Dictionary={}
		for asset in found:seen[asset["id"]]=true
		check(seen.size()==found.size(),"Matching several aliases never duplicates a result: "+fixture["query"])
		var original_source: String=names[fixture["id"]]["source_name"] if names[fixture["id"]]["source_name"]!=null else library.assets[fixture["id"]]["data"]["name_source"]
		var exact: Array=library.find("all","All assets",original_source,[],false,fixture["pack"])
		check(exact.any(func(asset: Dictionary):return asset["id"]==fixture["id"]),"Original source-name query remains available: "+fixture["id"])
	var unicode_asset: Dictionary={"id":"fixture:unicode","name":"Café owner's table","category":"Fixture","data":{"aliases":["coffee table","café furniture"]}}
	var search: RefCounted=preload("res://scripts/builder/asset_search.gd").new()
	check(search.rank(unicode_asset,search.words("café owner's"))>0 and search.rank(unicode_asset,search.words("coffee table"))>0,"Unicode and apostrophe labels/aliases are searchable")
	var barrels: Array[String]=[]
	for id in names:
		if names[id]["display_name"]=="Wooden barrel" and names[id]["source_pack"]=="MyPilesetProoject":barrels.append(id)
	check(barrels.size()==2,"Same reviewed human name keeps two different source IDs")
	check(library.find("all","All assets","wooden barrel",barrels,true,"MyPilesetProoject").size()==2,"Both same-name favorites remain concrete results")
	check(library.families.members.size()==75,"Name changes do not merge existing appearance families")
	var studio: Control=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio)
	while not studio.enhancements_ready:await process_frame
	studio.favorites.assign(barrels)
	var id: String=fixtures[1]["id"]
	var doc: RefCounted=studio.current();doc.data=preload("res://scripts/builder/templates.gd").make(studio.mode,"blank")
	doc.add(id,[0,0,0],"SE",1)
	var before: Dictionary=doc.data.duplicate(true);var history: int=doc.undo_history.size()
	studio.asset_browser.show_asset(id)
	check(studio.asset_browser.details.text.contains(names[id]["source_name"]) and studio.asset_browser.details.text.contains("MyPilesetProoject"),"Details retain source name and pack provenance")
	if studio.consumer_shell:
		check(studio.consumer_shell.card_name(studio.library.assets[id])==names[id]["display_name"],"Simple cards use the same reviewed name as precision cards")
	check(doc.data==before and doc.undo_history.size()==history,"Inspecting labels leaves city data and history unchanged")
	studio.asset_browser.dialog.hide()
	studio.asset_browser.show_asset("2d:t1")
	check(studio.asset_browser.details.text.contains(studio.library.assets["2d:t1"]["data"]["name_source"]),"Native imports expose their actual source file without inventing a source-name field")
	studio.asset_browser.dialog.hide()
	var packaged: Array[String]=barrels.duplicate()
	packaged.append("2d:bir")
	for fixture in fixtures:
		if fixture["query"] in ["single pine","water surface","stepping stones"]:packaged.append(fixture["id"])
	check(packaged.size()==6,"Export fixture covers duplicate names, native provenance, scene cells, water fragments and blocks")
	for mode in ["2d","3d"]:
		studio.switch_mode(mode);doc=studio.current();doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
		for index in packaged.size():doc.add(packaged[index],[index*100,0,0] if mode=="2d" else [index*4,0,0],"SE",1)
		studio.changed();await settle()
		var path: String=OUTPUT+"/names_"+mode+".isocity.json"
		check(studio.write_project(path) and studio.load_project(path) and studio.current().data["objects"][0]["asset"]==barrels[0] and studio.current().data["objects"][1]["asset"]==barrels[1],"Name collisions preserve exact asset IDs on save/reopen: "+mode)
		check(studio.favorites==barrels,"Save/reopen keeps exact favorites: "+mode)
		doc=studio.current();doc.checkpoint();var placed: Dictionary=doc.add(id,[1000,0,0] if mode=="2d" else [40,0,0],"SE",1);doc.finish_checkpoint()
		check(doc.undo() and doc.data["objects"].size()==6 and doc.redo() and doc.data["objects"].back()["asset"]==id,"Reviewed names preserve concrete IDs through Undo/Redo: "+mode)
		doc.undo();studio.changed();await settle()
		var result: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],studio.current().data,studio.library,OUTPUT+"/names_"+mode+".zip")
		check(result["ok"],"Allowed reviewed-name objects export: "+mode)
	studio.free();await process_frame;await process_frame
	print("REVIEWED NAMES: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
