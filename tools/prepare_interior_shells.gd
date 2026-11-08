extends SceneTree
const OUT="res://resources/catalog/interior_shells.json"
func _initialize() -> void:
	var result: Dictionary={"version":1,"sources":{},"rooms":{}}
	for path in ["res://scripts/builder/templates.gd","res://scripts/builder/interiors.gd"]:result["sources"][path]=FileAccess.get_sha256(path)
	for mode in ["2d","3d"]:
		var room: Dictionary=preload("res://scripts/builder/interiors.gd").make(mode,"Room")
		room["objects"]=room["objects"].filter(func(item: Dictionary):return item["asset"] in ["2d:Wall_White","3d:HanX_Shop/Floor_Tile_Store","3d:HanX_Shop/Wall_Store_Segment"])
		for index in room["objects"].size():room["objects"][index]["uid"]="shell_"+str(index)
		result["rooms"][mode]=room
	var encoded: String=JSON.stringify(result,"\t",true)+"\n"
	if "--check" in OS.get_cmdline_user_args():
		if FileAccess.get_file_as_string(OUT)!=encoded:printerr("FAIL: prepared interior shells are stale");quit(1);return
	else:
		var file:=FileAccess.open(OUT,FileAccess.WRITE)
		if not file:printerr("FAIL: cannot write interior shells");quit(1);return
		file.store_string(encoded)
	print("INTERIOR SHELLS: both canonical room shells prepared without furnishing changes");quit()
