extends SceneTree
const OUT="res://output/verification/asset_expansion/U09"
const Styles=preload("res://scripts/builder/asset_styles.gd")
const Templates=preload("res://scripts/builder/templates.gd")
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;print("FAIL: "+message)
func settle() -> void:
	for frame in 8:await process_frame
func ids(items: Array) -> Array:
	var result: Array=[]
	for item in items:result.append(item["id"])
	result.sort();return result
func run() -> void:
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new()
	check(library.styles.index.size()==6555 and library.styles.evidence.size()==619,"All identities have style profiles and every prepared model has source-verified measurements")
	for id in library.assets:
		var info: Dictionary=library.styles.profile(id)
		check(info["id"]==id and info["themes"]==library.themes.tags(library.assets[id]),"Styles preserve identity and explicit collection tags: "+id)
		check(not Styles.compare(info,info,"3d")["suggested"],"An asset is a context, not its own suggestion: "+id)
	var modern: Dictionary=library.styles.profile("3d:HanX_Shop/Shop_Cafe")
	var space: Dictionary=library.styles.profile("3d:Supplemental_Satellites/03_cubesat_3u")
	check(not modern["materials"].is_empty() and not space["materials"].is_empty() and library.styles.index.values().any(func(info: Dictionary):return info["kind"]=="3d" and not info["materials"].is_empty() and info["materials"]!=modern["materials"]),"Measured material conventions retain actual similarities and differences without inventing source-style distinctions")
	var a: Dictionary={"id":"a","kind":"3d","themes":["space"],"palette":"village/voyager","span":[2,2],"layer":"Buildings","materials":["solid_color","lit_pbr"]}
	var b: Dictionary=a.duplicate(true);b["id"]="b"
	var best: Dictionary=Styles.compare(a,b,"3d")
	check(best["suggested"] and best["reasons"].size()>=5,"Reviewed theme, palette, projection, measured scale and material evidence all contribute")
	for field in ["themes","palette","span","materials"]:
		var partial: Dictionary=a.duplicate(true);partial[field]="" if field=="palette" else []
		check(Styles.compare(partial,b,"3d")["score"]<best["score"],"Missing explicit evidence reduces ranking: "+field)
	var flat: Dictionary=a.duplicate(true);flat["kind"]="2d";flat["projection"]="isometric"
	check(Styles.compare(flat,b,"3d")["cautions"].has("This remains a flat sprite card in 3D.") and Styles.compare(flat,b,"3d")["score"]<best["score"],"Mixed-mode sprites remain flat and projection mismatch is explained")
	var huge: Dictionary=a.duplicate(true);huge["span"]=[200,200]
	check(Styles.compare(huge,b,"3d")["score"]<best["score"],"Very different prepared spans are not promised to fit")
	check(not Styles.compare({"id":"unknown","kind":"2d"},{"id":"theme","themes":[]},"2d")["suggested"],"Unknown styles are never inferred from filenames or representation alone")
	check(Styles.presentation({"themes":["space"]},"3d")=="unknown","Theme-only context does not invent a projection")
	var path: String=OUT+"/source_evidence.txt";FileAccess.open(path,FileAccess.WRITE).store_string("first")
	var entry: Dictionary={"sources":{path:{"sha256":FileAccess.get_sha256(path),"size":5}}}
	library.styles.hashes.clear();check(library.styles.sources_valid(entry),"Source evidence validates by content hash")
	FileAccess.open(path,FileAccess.WRITE).store_string("other");library.styles.hashes.clear()
	check(not library.styles.sources_valid(entry),"Same-length source edits invalidate evidence even within the same timestamp second")
	entry["sources"][path]["sha256"]=FileAccess.get_sha256(path)
	var import_config:=ConfigFile.new();import_config.set_value("params","meshes/light_baking",1);import_config.save(path+".import")
	entry["sources"][path]["import_parameters"]=Styles.import_parameters(path)
	library.styles.hashes.clear();check(library.styles.sources_valid(entry),"Matching import parameters retain measured evidence")
	import_config.set_value("params","meshes/light_baking",2);import_config.save(path+".import")
	check(not library.styles.sources_valid(entry),"Changed import parameters invalidate measurements before stale dimensions are suggested")
	DirAccess.remove_absolute(path+".import");DirAccess.remove_absolute(path)
	check(not library.styles.sources_valid(entry),"Unavailable source evidence remains partial rather than invented")
	for malformed in [[],{}, {path:{"sha256":"x".repeat(64),"size":5}}, {path:true}]:
		check(not library.styles.sources_valid({"sources":malformed}),"Malformed source evidence is rejected safely")
	var custom: Dictionary={"id":"2d:Custom/U09","mode":"2d","name":"Metallic isometric space shader","category":"Custom","path":library.assets["2d:Coffee_Shop"]["path"],"data":{},"behavior":{}}
	library.assets[custom["id"]]=custom;library.rebuild_indexes()
	check(library.styles.profile(custom["id"])["projection"]=="unknown" and library.styles.profile(custom["id"])["palette"].is_empty(),"Custom names never manufacture style metadata")
	custom["data"]["style_profile"]={"projection":"frontal","palette_family":"custom-reviewed","materials":["unlit","unknown"],"span":[2,3]};library.rebuild_indexes()
	check(library.styles.profile(custom["id"])["projection"]=="frontal" and library.styles.profile(custom["id"])["materials"]==["unlit"] and library.styles.profile(custom["id"])["span"]==[2,3],"Validated explicit custom metadata supplements partial imports")
	custom["data"]["style_profile"]={"projection":false,"materials":{},"span":[NAN,1]};library.rebuild_indexes()
	check(library.styles.profile(custom["id"])["projection"]=="unknown" and library.styles.profile(custom["id"])["span"].is_empty(),"Invalid optional custom fields fall back to partial metadata")
	library.assets.erase(custom["id"]);library.rebuild_indexes()
	await workflow()
	print("STYLE SUGGESTIONS: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

func workflow() -> void:
	var store=preload("res://scripts/builder/project_store.gd");store.storage_root=OUT+"/history";store.legacy_autosave=OUT+"/legacy.json"
	var studio: Control=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio)
	while not studio.enhancements_ready:await process_frame
	var browser: RefCounted=studio.asset_browser;var controller: RefCounted=browser.compatibility;var ui: RefCounted=studio.consumer_shell
	check(ui!=null,"Both interfaces expose compatibility ordering")
	if not ui:studio.free();return
	ui.dismiss_welcome();ui.set_active(false,false);browser.clear_all_filters();controller.explicit_id="3d:HanX_Shop/Shop_Cafe"
	var found: Array[Dictionary]=studio.library.find("all","All assets","cafe",[],false)
	controller.include_all=true;var original: Array=controller.order(found,"cafe")
	controller.include_all=false;var suggested: Array=controller.order(found,"cafe")
	check(ids(original)==ids(suggested) and original.size()==suggested.size(),"Every cross-style search match survives suggestion ordering")
	var terms: PackedStringArray=studio.library.search_index.words("cafe")
	var last: int=2147483647
	for asset in suggested:
		var rank: int=studio.library.search_index.rank(asset,terms);check(rank<=last,"Text relevance remains ahead of style hints");last=rank
	var before: Dictionary=studio.current().data.duplicate(true);var history: int=studio.current().undo_history.size()
	for active in [false,true]:
		ui.set_active(active,false)
		if active:ui.open_drawer("build");ui.group="Everything";ui.style_choice.select(1);ui.query.text="cafe";ui.refresh_catalog()
		else:studio.search.text="cafe";studio.refresh_library()
		var included: Array=ids(studio.library_matches());controller.set_include_all(true);await settle()
		check(ids(studio.library_matches())==included,"All-styles choice preserves the complete result set: "+str(active))
		controller.set_include_all(false);await settle()
		check(ids(studio.library_matches())==included and studio.current().data==before and studio.current().undo_history.size()==history,"Style choices never replace assets, place content or add history: "+str(active))
		check(studio.cards.get_children().any(func(card: Node):return card.inspect_button.text=="Suggested"),"Cards explicitly say Suggested rather than promising compatibility")
	ui.set_active(false,false);controller.settings_path=OUT+"/preferences.json";studio.storage_enabled=true;controller.set_include_all(true);studio.storage_enabled=false
	controller.include_all=false;controller.restore();check(controller.include_all and studio.current().data==before,"All-styles preference survives a local round trip without authoring world data")
	for malformed in [4,[],"unknown",null]:
		store.write_json(controller.settings_path,{"include_all_styles":malformed});controller.restore();check(not controller.include_all,"Invalid stored ordering choice falls back safely")
	FileAccess.open(OUT+"/blocked_parent.txt",FileAccess.WRITE).store_string("not a directory");controller.settings_path=OUT+"/blocked_parent.txt/preferences.json";studio.storage_enabled=true;controller.set_include_all(true);studio.storage_enabled=false
	check(controller.include_all and studio.status.text.contains("session"),"Failed preference write preserves a usable all-styles session")
	controller.explicit_id="";controller.include_all=false;browser.set_theme("space");studio.search.text="cubesat 3u";studio.refresh_library();await settle()
	check(controller.suggested_count<3 and controller.note.text.contains("Limited matching"),"Sparse filtered collections explain limited suggestions honestly")
	browser.clear_all_filters();controller.anchor("3d:HanX_Shop/Shop_Cafe")
	for mode in ["2d","3d"]:
		studio.switch_mode(mode);var doc: RefCounted=studio.current();doc.data=Templates.make(mode,"blank")
		for index in 2:
			var id: String=["3d:HanX_Shop/Shop_Cafe","3d:Supplemental_Satellites/03_cubesat_3u"][index];doc.add(id,[index*200,0,0] if mode=="2d" else [index*10,0,0],"0")
		studio.changed();await settle();var authored: Dictionary=doc.data.duplicate(true)
		controller.anchor(doc.data["objects"][0]["asset"]);controller.set_include_all(true);controller.set_include_all(false)
		check(doc.data==authored,"Intentional mixed styles remain unchanged: "+mode)
		var path: String=OUT+"/styles_"+mode+".isocity.json"
		check(studio.write_project(path) and studio.load_project(path) and studio.current().data["objects"]==JSON.parse_string(JSON.stringify(authored["objects"])) and studio.repair_report.get("issues",[]).is_empty(),"Mixed-style IDs/transforms save and reopen without repairs: "+mode)
		var result: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],studio.current().data,studio.library,OUT+"/styles_"+mode+".zip")
		check(result["ok"],"Export retains only selected style evidence and needed sources: "+mode+" "+result.get("message",""))
	studio.free();await process_frame;await process_frame
