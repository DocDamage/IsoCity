extends SceneTree
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;print("FAIL: "+message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new()
	var barrels: Array=[]
	for asset in library.assets.values():
		if asset["data"].get("name_key","").contains("Added_MyPilesetProoject"):barrels.append(asset)
	check(barrels.size()==2,"Only the two selected reviewed labels are packaged")
	for asset in barrels:
		check(asset["name"]=="Wooden barrel" and asset["data"]["source_pack"]=="MyPilesetProoject" and not asset["data"]["source_name"].is_empty(),"Independent export retains display name and original provenance")
		check(asset["data"].get("aliases",[]).has("cask") and library.icon(asset["id"])!=null,"Independent export retains aliases and artwork")
	check(library.find("all","All assets","cask",[],false,"MyPilesetProoject").size()==2,"Independent alias search keeps both source IDs")
	var reviewed: int=0
	for asset in library.assets.values():
		if asset["data"].has("name_key"):reviewed+=1
	check(reviewed==6,"Only selected reviewed names and dependencies are packaged")
	check(library.assets.has("2d:bir") and library.assets["2d:bir"]["data"].get("name_source","").ends_with("/bir.png") and library.pack_name(library.assets["2d:bir"])=="RPG World","Native source-file provenance and original pack survive independently")
	for fixture in [["isometricStrategy","single pine"],["water tileset by Rodwan","water surface"],["CATS ISOMETRIC ASSET PACK","stepping stones"]]:
		var found: Array=library.find("all","All assets",fixture[1],[],false,fixture[0])
		check(found.size()==1,"Reviewed ordinary query works independently: "+fixture[1])
		if found.size()==1:check(library.icon(found[0]["id"])!=null and not found[0]["data"].get("source_name","").is_empty(),"Selected cell keeps artwork and source identity: "+fixture[1])
	check(not FileAccess.file_exists("res://resources/catalog/reviewed_names.json"),"Subset metadata does not copy the full reviewed-name manifest")
	print("REVIEWED NAMES PORTABLE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
