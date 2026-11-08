extends "res://tools/test_small_prop_view.gd"
const OUT="res://output/verification/asset_expansion/U18/"
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio);await settle(16)
	for mode in ["2d","3d"]:
		studio.switch_mode(mode);var doc: RefCounted=Document.new();doc.data=Templates.make(mode,"blank");studio.documents[mode]=doc
		var assets: Array=["3d:Fire_Station_PSX/bench_vise","3d:HanX_Shop/Cafe_Counter","3d:HanX_Shop/Shelf_Wall"]
		for index in assets.size():
			var item: Dictionary=doc.add(assets[index],[index*64,0,0] if mode=="2d" else [index*2,0,0],str(studio.library.directions(assets[index])[0]));item["name"]="Prop · "+str(index)
			if index==2:item["visible"]=false
		var layer_hidden: Dictionary=doc.add(assets[0],[192,0,0] if mode=="2d" else [6,0,0],str(studio.library.directions(assets[0])[0]));layer_hidden["layer"]="Vehicles";layer_hidden["name"]="Layer-hidden prop";studio.Layers.set_state(doc.data,"Vehicles","visible",false)
		studio.changed();studio.worlds[mode].reset_camera("room");await settle();studio.overlap_picker.choose(doc.data["objects"][0]["uid"])
		var original: Dictionary=doc.data.duplicate(true);var camera: Dictionary=studio.small_prop_tools.camera_state();var history: int=doc.undo_history.size();var previews: Dictionary={}
		for id in assets:
			var path: String=studio.library.assets[id]["data"].get("preview_path","res://resources/previews_3d/"+id.trim_prefix("3d:")+".png")
			if FileAccess.file_exists(path):previews[id]={"path":path,"sha256":FileAccess.get_sha256(path)}
		check(previews.size()==assets.size(),"Every authored source has a measured preview dependency: "+mode)
		check(Document.valid(original,mode,studio.library),"Export fixture uses supported source directions and authored visibility: "+mode)
		studio._command("small_props_isolate",null);await settle(12)
		var result: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],doc.data,studio.library,OUT+"isolated_"+mode+".zip")
		check(result["ok"],"Allowed portable export succeeds while isolated: "+mode+" "+result["message"])
		check(studio.small_prop_tools.active and not studio.worlds[mode].instances[original["objects"][1]["uid"]].visible,"Lower-level export preserves current personal editing view: "+mode)
		var scene_path: String=OUT+"scene_"+mode+".tscn";studio._command("export",null);studio.file_dialog.hide();studio._file_selected(scene_path);await settle()
		check(FileAccess.file_exists(scene_path) and not studio.small_prop_tools.active and studio.small_prop_tools.camera_state()==camera,"Normal scene export restores original camera before choosing destination: "+mode)
		studio.overlap_picker.choose(original["objects"][0]["uid"]);studio._command("small_props_isolate",null);await settle();studio._command("export_portable",null);studio.file_dialog.hide();studio._file_selected(OUT+"props_"+mode+".zip");await settle()
		check(FileAccess.file_exists(OUT+"props_"+mode+".zip") and not studio.small_prop_tools.active,"Normal portable command exits temporary view: "+mode)
		check(doc.data==original and doc.undo_history.size()==history,"Both export routes preserve coordinates, visibility and history: "+mode)
		check(studio.write_project(OUT+"props_"+mode+".isocity.json"),"Normal project save remains valid after export: "+mode)
		FileAccess.open(OUT+"expected_"+mode+".json",FileAccess.WRITE).store_string(JSON.stringify({"source":original,"previews":previews},"\t"))
		if mode=="2d" and result["ok"]:
			var restricted: RefCounted=Document.new();restricted.data=Templates.make("2d","blank");var knife_id: String="2d:Supplemental_Kitchen_cookware_kit_chef_knife_67e36712";restricted.add(knife_id,[0,0,0],str(studio.library.directions(knife_id)[0]));var good_hash: String=FileAccess.get_sha256(OUT+"isolated_2d.zip")
			var refused: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],restricted.data,studio.library,OUT+"isolated_2d.zip")
			check(not refused["ok"] and refused["message"].contains("license") and FileAccess.get_sha256(OUT+"isolated_2d.zip")==good_hash,"Restricted cookware refuses raw source export and preserves the good permitted ZIP")
			var metadata: Dictionary={"title":"Tiny kitchen layout","author":"Local verification","description":"Requires the locally installed supplied cookware.","license":"Layout only; supplied artwork keeps its own terms.","source_url":"","kind":"city"};var share: Dictionary=preload("res://scripts/builder/creation_share.gd").prepare({"kind":"city","document":restricted.data},metadata,studio.library.icon(knife_id).get_image(),studio.library)
			check(share["ok"],"Restricted tiny kitchen art remains available through permitted layout-only sharing")
	studio.free();await settle();print("SMALL PROP EXPORTS: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
