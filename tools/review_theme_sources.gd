extends SceneTree
const OUT="res://output/verification/asset_expansion/U01"
func _initialize() -> void:
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new();var packs: Dictionary={};var samples: Array=[]
	var ids: Array=library.assets.keys();ids.sort()
	DirAccess.make_dir_recursive_absolute(OUT+"/source_icons")
	for id in ids:
		var asset: Dictionary=library.assets[id];var pack: String=library.pack_name(asset)
		if packs.has(pack):continue
		packs[pack]=true
		var texture: Texture2D=library.icon(id)
		if texture:
			var picture: Image=texture.get_image()
			if picture.is_compressed():picture.decompress()
			var file: String=str(samples.size())+".png";picture.save_png(OUT+"/source_icons/"+file)
			samples.append({"id":id,"pack":pack,"file":file,"name":asset["name"]})
	FileAccess.open(OUT+"/source_samples.json",FileAccess.WRITE).store_string(JSON.stringify(samples,"\t"))
	print("Captured ",samples.size()," actual source-group icons");quit()
