extends SceneTree
const Content = preload("res://scripts/builder/asset_content.gd")
const Document = preload("res://scripts/builder/document.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const OUTPUT = "res://output/verification/asset_expansion/I03"
const LEGACY = "2d:Added_ship_Ship_sprPlayer_strip16_56b1db61"
const SHIP = "2d:Reviewed_sailing_ship_turntable"
const FLAG = "2d:Reviewed_rodwan_flag_0"
const BENCH = "2d:Reviewed_village_bench_0"
const TILE = "2d:Reviewed_village_floor_3_v1_0_1"
var checks: int = 0
var failures: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; print("FAIL: " + message)

func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 8: await process_frame

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var library: RefCounted = preload("res://scripts/builder/asset_library.gd").new()
	var reviewed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/catalog/reviewed_registry.json"))
	check(reviewed["items"].size() == 322 and reviewed["legacy_content"].size() == 293, "Explicit reviewed inventory, including exact native copies")
	for id in reviewed["legacy_content"]:
		check(library.assets.has(id) and Content.kind(library.assets[id]) == reviewed["legacy_content"][id]["content_kind"], "Legacy identity remains available with reviewed classification: " + id)
	for name in reviewed["items"]:
		var id: String = "2d:" + name
		var asset: Dictionary = library.assets[id]
		check(library.icon(id) != null, "Prepared preview loads: " + id)
		check(preload("res://scripts/builder/business_plan.gd").profile({"asset":id})["kind"] == "none" and preload("res://scripts/builder/citizen_plan.gd").role({"asset":id}).is_empty(), "Cropped art does not invent gameplay capability: " + id)
		for mode in ["2d", "3d"]:
			var node: Node = preload("res://scripts/builder/asset_instance.gd").make(library, id, mode); root.add_child(node)
			var source: Node = node if mode == "2d" else node.source
			check(source is IsoObject and source.get_node("Sprite2D").texture != null, "Actual mixed-world instance loads: " + mode + "/" + id)
			for direction in asset["data"]["directions"]:
				if mode=="3d":node.direction=direction
				else:source.direction = direction
				var sprite: Sprite2D = source.get_node("Sprite2D")
				var view: Dictionary = asset["data"]["directions"][direction]
				check(sprite.hframes == view["frames"] and source.origin_offset == Vector2(view["origin"][0],view["origin"][1]), "Supplied view/frame group and contact are used: " + id + "/" + str(direction))
				if mode=="3d" and id in [SHIP,FLAG,BENCH,"2d:Reviewed_myart_leafy_tree_cutout","2d:Reviewed_myart_campfire"]:
					check(art_above_ground(node),"Opaque sprite artwork stays above the actual 3D foundation: "+id+"/"+str(direction))
			node.free()
	var state: Dictionary = library.assets["2d:Reviewed_village_coffee_door"]["data"]
	check(state["animation_status"] == "static_sprite" and state["animation_note"].contains("states") and state["directions"].keys() == ["Closed","Ajar","Open"], "Opening states are not reported as movement or facing animation")
	check(library.assets[SHIP]["data"]["animation_status"] == "directional_sprite" and library.directions(SHIP).size() == 16, "Sixteen ship views are a turntable, not sixteen animation frames")
	var pivots: Array = library.assets[SHIP]["data"]["directions"].values().map(func(v: Dictionary): return v["origin"])
	check(pivots.all(func(value: Array): return value == pivots[0]), "Ship views retain one common pivot")
	for id in ["2d:Reviewed_village_tree_wind_29","2d:Reviewed_village_tree_wind_30","2d:Reviewed_myart_grass_wind_31","2d:Reviewed_myart_grass_wind_35"]:
		check(library.assets[id]["data"]["frames"]>1 and Content.kind(library.assets[id])=="object", "Canopy/blade strips stay one reviewed loop instead of separate ordinary objects")
	check(Content.kind(library.assets["2d:Reviewed_village_tree_30_0"])=="reference" and library.assets["2d:Reviewed_village_tree_30_0"]["data"]["replacement_ids"]==["2d:Reviewed_village_tree_wind_30"],"Earlier reviewed frame IDs stay recoverable with an explicit loop alternative")
	var flag: Node = load(library.assets[FLAG]["path"]).instantiate(); root.add_child(flag)
	flag.set_process(false); flag._process(.11)
	check(flag.get_node("Sprite2D").frame == 1 and flag.animation_fps == 10 and flag.total_frames == 8, "Supplied flag timing animates one flag instead of three flags together")
	flag.free()
	for id in [FLAG,"2d:Reviewed_myart_leafy_tree_cutout"]:
		var image: Image = library.icon(id).get_image()
		check(image.get_pixel(0,0).a == 0, "Approved flat background is transparent: " + id)
	await workflow(library)
	print("REVIEWED SPRITES: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func art_above_ground(instance: Node) -> bool:
	var image: Image=instance.material.albedo_texture.get_image()
	if image.is_compressed():image.decompress()
	var lowest: int=-1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x,y).a>=.5:lowest=y
	if lowest<0:return false
	var bottom: float=instance.mesh.position.y+instance.mesh.mesh.size.y*.5-float(lowest+1)/32.0
	return bottom>=-.04

func workflow(library: RefCounted) -> void:
	var store = preload("res://scripts/builder/project_store.gd")
	store.storage_root = OUTPUT + "/history"; store.legacy_autosave = OUTPUT + "/legacy.json"
	var studio: Control = load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled = false; root.add_child(studio)
	while not studio.enhancements_ready: await process_frame
	var browser: RefCounted = studio.asset_browser
	var doc: RefCounted = studio.current(); doc.data = Templates.make(studio.mode,"blank")
	var old: Dictionary = doc.add(LEGACY,[0,0,0],"SE",.25); old["extension"] = {"keep":true}; old["angle"] = 15
	studio.changed(); await settle()
	var before: Dictionary = doc.data.duplicate(true); var history: int = doc.undo_history.size()
	studio.asset_type.select(0); studio.category.select(0); studio.search.clear(); studio.pack_filter = "ship"
	if studio.consumer_shell: studio.consumer_shell.set_active(false,false)
	browser.set_content_scope(0)
	check(studio.library_matches().all(func(a: Dictionary):return Content.kind(a)=="object") and studio.library_matches().any(func(a: Dictionary):return a["id"]==SHIP), "Precision browsing defaults to the single reviewed ship")
	browser.set_content_scope(2)
	check(studio.library_matches().any(func(a: Dictionary):return a["id"]==LEGACY), "All content keeps the original strip accessible")
	studio.favorites.assign([LEGACY]);studio.favorites_only.button_pressed=true;browser.set_content_scope(0)
	check(studio.library_matches().size()==1 and studio.library_matches()[0]["id"]==LEGACY, "A legacy favorite is never hidden by the object filter")
	studio.favorites_only.button_pressed=false;studio.pack_filter=""
	if studio.consumer_shell:
		var ui: RefCounted = studio.consumer_shell;ui.dismiss_welcome();ui.set_active(true,false);ui.group="Everything";ui.style_choice.select(1);ui.query.clear()
		check(ui.matches().all(func(a: Dictionary):return Content.kind(a)=="object"), "Simple browsing shares the object policy")
		ui.content_choice.select(2);ui.content_choice.item_selected.emit(2)
		check(browser.content_scope==2 and browser.content_choice.selected==2 and ui.matches().any(func(a: Dictionary):return a["id"]==LEGACY), "Simple and precision content controls stay synchronized")
		ui.set_active(false,false)
	check(doc.data==before and doc.undo_history.size()==history, "Content filters never mutate a city or its history")
	var prior_window: Vector2i = root.size
	root.size = Vector2i(960,640); browser.filters_manual=false
	await settle(); browser.fit_filters(); await settle()
	check(not browser.filter_scroll.visible and studio.search.is_visible_in_tree() and browser.filter_refine.is_visible_in_tree(), "Compact precision browsing keeps search and Refine visible while closing secondary filters")
	check(studio.cards.get_parent().size.y>=100, "Compact precision gallery retains enough height to show artwork beneath card actions")
	browser.filter_refine.button_pressed=true;await settle()
	check(browser.filter_scroll.visible and browser.filter_refine.text=="Done", "Compact Refine explicitly opens every secondary filter")
	browser.filter_refine.button_pressed=false;await settle()
	check(not browser.filter_scroll.visible and doc.data==before and doc.undo_history.size()==history, "Closing compact filters restores browsing without changing project history")
	root.size=prior_window;browser.filters_manual=false;await settle();browser.fit_filters()
	for scale_value in [1.0,1.5]:
		studio.accessibility_settings.restore({"text_scale":scale_value,"large_targets":scale_value>1,"high_contrast":scale_value>1})
		studio.refresh_library();await settle()
		for card in studio.cards.get_children():
			check(not card.artwork.get_rect().intersects(card.favorite_button.get_rect()) and not card.artwork.get_rect().intersects(card.inspect_button.get_rect()), "Header actions never cover the source artwork at any tested text size")
			check(card.caption.get_rect().position.y>=card.artwork.get_rect().end.y, "Names remain below the image rather than covering its base")
	studio.accessibility_settings.restore({"text_scale":1.0,"large_targets":false,"high_contrast":false})
	browser.content_settings_path = OUTPUT + "/content_preferences.json"
	studio.storage_enabled=true;browser.set_content_scope(1);studio.storage_enabled=false
	browser.content_scope=0;browser.restore_content_scope()
	check(browser.content_scope==1 and doc.data==before, "Content preference writes and restores separately from the project")
	for invalid in [true,"2",-1,3,1.5]:
		store.write_json(browser.content_settings_path,{"scope":invalid});browser.restore_content_scope();check(browser.content_scope==0,"Invalid content preference safely defaults to objects")
	FileAccess.open(OUTPUT + "/blocked_parent.txt",FileAccess.WRITE).store_string("This is a file, not a directory.")
	browser.content_settings_path = OUTPUT + "/blocked_parent.txt/preferences.json"
	studio.storage_enabled=true;browser.set_content_scope(2);studio.storage_enabled=false
	check(browser.content_scope==2 and studio.status.text.contains("session") and doc.data==before, "A failed preference write leaves the session usable and the city untouched")
	browser.show_asset(LEGACY)
	check(browser.reviewed_parts.item_count==2 and browser.details.text.contains("Atlas"), "Legacy strip explains its content and offers its reviewed counterpart")
	browser.reviewed_parts.select(1);browser.reviewed_parts.item_selected.emit(1)
	check(browser.selected_id==SHIP and browser.original_source.visible and doc.data==before, "Inspecting a reviewed part preserves the original placement")
	browser.views.select(3);browser.views.item_selected.emit(3);browser.choose_for_placement()
	check(studio.asset_id==SHIP and studio.direction=="View_04" and doc.data==before, "New placement retains the chosen supplied ship view without replacing the legacy strip")
	for mode in ["2d","3d"]:
		studio.switch_mode(mode);doc=studio.current();doc.data=Templates.make(mode,"blank")
		var legacy: Dictionary = doc.add(LEGACY,[0,0,0],"SE",.25);legacy["extension"]={"keep":true}
		doc.checkpoint();var crop: Dictionary=doc.add(BENCH,[200,0,0] if mode=="2d" else [8,0,0],"SW",.5);studio.changed();doc.finish_checkpoint()
		check(doc.undo() and doc.data["objects"].size()==1 and doc.data["objects"][0]["asset"]==LEGACY and doc.data["objects"][0]["extension"]["keep"], "Undoing new art preserves legacy data: "+mode)
		check(doc.redo() and doc.data["objects"][1]["asset"]==BENCH, "Reviewed placement uses ordinary Redo: "+mode)
		var path: String=OUTPUT+"/reviewed_"+mode+".isocity.json"
		check(studio.write_project(path) and studio.load_project(path) and studio.current().data["objects"][0]["asset"]==LEGACY and studio.current().data["objects"][1]["asset"]==BENCH, "Legacy and reviewed identities save/reopen together: "+mode)
		var prior: Dictionary=Templates.make(mode,"blank");prior["economy"]={"enabled":true};prior["economy_account"]=preload("res://scripts/builder/economy_plan.gd").account(prior,library)
		var next: Dictionary=prior.duplicate(true);next["objects"]=[crop.duplicate(true)]
		var quote: Dictionary=preload("res://scripts/builder/economy_plan.gd").quote(prior,next,library)
		check(quote["ok"] and quote["construction"]>0 and quote["account"]["cash"]==prior["economy_account"]["cash"]-quote["construction"], "Reviewed art uses normal construction charging: "+mode)
		prior["protected_areas"]=[{"uid":"area","name":"Protected","owner":"host","rect":[-1000,-1000,2000,2000]}];next["protected_areas"]=prior["protected_areas"].duplicate(true)
		var worlds: Dictionary={"2d":Templates.make("2d","blank"),"3d":Templates.make("3d","blank")};worlds[mode]=prior;var changed: Dictionary=worlds.duplicate(true);changed[mode]=next
		check(not preload("res://scripts/builder/cooperative_plan.gd").allowed(worlds,changed,"participant",library).is_empty(), "Protected regions cover reviewed-object placement: "+mode)
		doc=studio.current();doc.data=Templates.make(mode,"blank")
		for index in [LEGACY,SHIP,FLAG,BENCH,TILE]:
			var i: int=doc.data["objects"].size();doc.add(index,[i*120,0,0] if mode=="2d" else [i*5,0,0],str(library.directions(index)[0]),library.assets[index]["data"].get("default_scale",1))
		studio.changed();await settle()
		var result: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],doc.data,library,OUTPUT+"/reviewed_"+mode+".zip")
		check(result["ok"],"Allowed legacy/cropped sprites export together: "+mode+" "+result.get("message",""))
	studio.free();await process_frame;await process_frame
