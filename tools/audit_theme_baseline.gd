extends SceneTree
func _initialize() -> void:
	if FileAccess.file_exists("res://output/verification/asset_expansion/U01/baseline/library.json"):
		printerr("Theme baseline already exists; refusing to overwrite it.");quit(1);return
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new()
	var assets: Dictionary={};var packs: Dictionary={}
	for id in library.assets:
		var asset: Dictionary=library.assets[id];var pack: String=library.pack_name(asset)
		assets[id]={"name":asset["name"],"pack":pack,"category":asset["category"],"path":asset["path"],"mode":asset["mode"],"behavior":asset["behavior"],"source_name":asset["data"].get("source_name","")}
		packs[pack]=packs.get(pack,0)+1
	var output: FileAccess=FileAccess.open("res://output/verification/asset_expansion/U01/baseline/library.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"assets":assets,"packs":packs},"\t"));output.close()
	print("Theme baseline: ",assets.size()," assets; ",packs.size()," source groups");quit()
