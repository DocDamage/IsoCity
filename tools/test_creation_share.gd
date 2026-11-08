extends SceneTree
const Share=preload("res://scripts/builder/creation_share.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var library=preload("res://scripts/builder/asset_library.gd").new()
	var doc=preload("res://scripts/builder/document.gd").new(); doc.data=preload("res://scripts/builder/templates.gd").make("2d","blank"); doc.add("2d:Sedan_Blue",[0,0,0],"SE",1)
	var image:=Image.create(800,500,false,Image.FORMAT_RGBA8); image.fill(Color.SEA_GREEN)
	var meta: Dictionary={"title":"A <city>","author":"Builder","description":"Test","license":"CC BY 4.0","source_url":"","kind":"city"}
	var prepared: Dictionary=Share.prepare({"kind":"city","document":doc.data},meta,image,library)
	check(prepared["ok"],"Native city can be prepared for sharing")
	if prepared["ok"]:
		var value: Dictionary=prepared["creation"]; check(Share.inspect(value,library)["ok"],"Prepared source passes strict import review")
		var folder: String="res://output/creation_gallery_test_"+Share.Store.new_id(); DirAccess.make_dir_recursive_absolute(folder); var published: Dictionary=Share.publish(value,folder,library)
		check(published["ok"] and FileAccess.file_exists(published.get("index","")),"Publishing creates a static gallery and download")
		check(Share.read(published["path"],library)["ok"],"Published creation reopens")
		check(FileAccess.get_file_as_string(published["index"]).contains("A &lt;city&gt;") and not FileAccess.get_file_as_string(published["index"]).contains("<city>"),"Gallery escapes creator-supplied HTML")
		var invalid: Dictionary=value.duplicate(true); invalid["source"]="{}"; check(not Share.inspect(invalid,library)["ok"],"Source checksum detects corruption")
		invalid=value.duplicate(true); invalid["source"]='{"kind":"city","document":[]}'; invalid["source_sha256"]=invalid["source"].sha256_text(); check(not Share.inspect(invalid,library)["ok"],"Malformed source types fail without executing source")
		for patch in [{"format":"Other"},{"version":99},{"id":"../bad"},{"metadata":[]},{"requirements":[]},{"requirements":[{}]},{"preview_png":"invalid"},{"attribution":[]},{"source":42},{"credits":[{}]}]:
			invalid=value.duplicate(true); invalid.merge(patch,true); check(not Share.inspect(invalid,library)["ok"],"Malformed share field is refused: "+str(patch.keys()[0]))
		var entry: Dictionary=library.assets["2d:Sedan_Blue"]; library.assets.erase("2d:Sedan_Blue"); var missing: Dictionary=Share.inspect(value,library)
		check(missing["ok"] and missing["missing"]==["2d:Sedan_Blue"],"Missing assets remain reviewable with explicit requirements")
		check(not Share.publish(value,folder,library)["ok"],"Unavailable assets prevent publication")
		library.assets["2d:Sedan_Blue"]=entry
		check(Share.publish(value,folder,library)["ok"] and Share.entries(folder).size()==1,"Publishing identical content updates one gallery card")
		check(not Share.publish(value,folder+"/absent",library)["ok"],"Invalid destination fails without altering a gallery")
		invalid=value.duplicate(true); invalid["requirements"].append(invalid["requirements"][0].duplicate()); check(not Share.inspect(invalid,library)["ok"],"Duplicate asset declarations are refused")
		var credited: Dictionary=doc.data.duplicate(true); credited["creation_credits"]=Share.imported_credits(value); var revised_meta: Dictionary=meta.duplicate(); revised_meta["author"]="Next builder"
		var revised: Dictionary=Share.prepare({"kind":"city","document":credited},revised_meta,image,library)
		check(revised["ok"] and Share.inspect(revised["creation"],library)["ok"] and revised["creation"]["attribution"].contains("Creator: Builder"),"Re-sharing retains original creation author and license")
		var glb_doc=preload("res://scripts/builder/document.gd").new(); glb_doc.data=preload("res://scripts/builder/templates.gd").make("3d","blank"); glb_doc.add("3d:HanX_Traffic/Car_Sedan",[0,0,0],"0",1)
		var notices: String=Share.attribution(Share.required_assets(glb_doc.data,library),library)
		check(notices.contains("assets/hanx_lowpoly/") and notices.length()>300,"Model attribution follows prefab dependencies to supplied pack notices")
		check(value["attribution"].contains("CC0 1.0 Universal"),"Sprite attribution includes supplied pack notices")
		var raw:=FileAccess.open(folder+"/broken.isocity-share.json",FileAccess.WRITE); raw.store_string("{broken"); raw.close(); check(not Share.read(folder+"/broken.isocity-share.json",library)["ok"],"Broken JSON fails safely")
		for bad_source in [{"kind":"city","document":{"mode":[]}},{"kind":"assembly","assembly":[]},{"kind":"assembly","assembly":{"mode":"4d","objects":[],"name":"Bad"}}]:
			invalid=value.duplicate(true); invalid["source"]=JSON.stringify(bad_source); invalid["source_sha256"]=invalid["source"].sha256_text(); check(not Share.inspect(invalid,library)["ok"],"Malformed source structure fails safely")
	var arguments: PackedStringArray=OS.get_cmdline_user_args()
	for mode in ["2d","3d"]:
		var nested=preload("res://scripts/builder/document.gd").new(); nested.data=preload("res://scripts/builder/templates.gd").make(mode,"blank"); var building_id: String=""
		for id in library.assets:
			if id.begins_with(mode+":") and library.assets[id]["behavior"].get("building",false): building_id=id; break
		var building: Dictionary=nested.add(building_id,[0,0,0],str(library.directions(building_id)[0]),1); var interior: Dictionary=preload("res://scripts/builder/interiors.gd").make(mode,"Shared rooms")
		var upper: Dictionary=preload("res://scripts/builder/interiors.gd").make(mode,"Upper"); interior=preload("res://scripts/builder/floor_plan.gd").put_floor(interior,{"uid":"upper","name":"Upper","height":3.2,"room":upper})["data"]; building["interior"]=interior
		nested.data["blueprints"]=[{"uid":"unbuilt","kind":"building","item":{"asset":building_id,"position":[100,0,0],"direction":str(library.directions(building_id)[0]),"scale":1}}]
		var shared: Dictionary=Share.prepare({"kind":"city","document":nested.data},meta,image,library); check(shared["ok"],"Owned rooms, upper floors and deferred blueprints can be shared: "+mode)
		var restored: Dictionary=Share.inspect(shared["creation"],library); check(restored["ok"] and restored["source"]["document"]["objects"][0]["interior"]["floors"].size()==1,"Multifloor source survives sharing intact: "+mode)
		check(shared["creation"]["requirements"].size()>1 and shared["creation"]["requirements"].any(func(entry: Dictionary):return entry["id"]==building_id),"Asset requirements include owned-room furnishings and planned construction: "+mode)
	var import_plan=preload("res://scripts/builder/asset_import_plan.gd"); var custom=preload("res://scripts/builder/custom_assets.gd"); var original_registry: String=custom.registry_override; custom.registry_override="res://output/creation_custom_registry.json"
	var custom_image:=Image.create(32,32,false,Image.FORMAT_RGBA8); custom_image.fill(Color.CORAL); custom_image.save_png("res://output/creation_custom_source.png")
	var settings: Dictionary=import_plan.defaults(); settings["name"]="Shared custom sprite"; settings["author"]="Sprite artist"; settings["license"]="Fixture license"; settings["source_url"]="https://example.com/sprite"; var raw_source: Dictionary=import_plan.inspect("res://output/creation_custom_source.png"); var installed: Dictionary=import_plan.install(raw_source,settings,custom_image)
	check(installed["ok"],"A real wizard-imported custom sprite is available for sharing")
	if installed["ok"]:
		library.assets[installed["asset"]["id"]]=installed["asset"]; var custom_doc=preload("res://scripts/builder/document.gd").new(); custom_doc.data=preload("res://scripts/builder/templates.gd").make("2d","blank"); custom_doc.add(installed["asset"]["id"],[0,0,0],"SE",1)
		var shared: Dictionary=Share.prepare({"kind":"city","document":custom_doc.data},meta,image,library)
		check(shared["ok"] and shared["creation"]["requirements"][0]["author"]=="Sprite artist" and shared["creation"]["attribution"].contains("Fixture license"),"Custom asset author, license, source and required ID remain in the download")
		library.assets.erase(installed["asset"]["id"]); var missing: Dictionary=Share.inspect(shared["creation"],library); check(missing["ok"] and missing["missing"]==[installed["asset"]["id"]],"A recipient without the imported custom asset sees its exact requirement")
	custom.registry_override=original_registry; import_plan.release(raw_source)
	if "--refresh-gallery" in arguments:
		var folder: String=arguments[arguments.find("--refresh-gallery")+1]; check(Share.write_text(folder.path_join("index.html"),Share.gallery_page(Share.entries(folder))),"Existing static gallery can be regenerated")
	for index in arguments.size():
		if arguments[index]=="--download": check(Share.read(arguments[index+1],library)["ok"],"Actual browser download passes engine import validation")
	print("Creation sharing: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
