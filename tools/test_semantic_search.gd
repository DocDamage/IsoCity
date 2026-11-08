extends SceneTree
const OUT="res://output/verification/asset_expansion/U16"
const Search=preload("res://scripts/builder/asset_search.gd")
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func settle() -> void:
	for frame in 8:await process_frame
func ids(found: Array) -> Array:
	var result: Array=[]
	for asset in found:result.append(asset["id"])
	result.sort();return result
func run() -> void:
	var terms: Array[String]=[""]
	for length in 3:
		var more: Array[String]=[]
		for text in terms:
			if text.length()==length:
				for letter in ["a","b","c"]:more.append(text+letter)
		terms.append_array(more)
	for a in terms:
		for b in terms:
			for limit in [1,2]:
				var exact: int=Search.distance(a,b);var bounded: int=Search.near_distance(a,b,limit)
				check((bounded==exact if exact<=limit else bounded>limit),"Bounded edit matching agrees with full adjacent-transposition distance: "+a+" / "+b)
	check(Search.words("Café naïve Straße Æther œuf")==Search.words("Cafe naive Strasse Aether oeuf") and Search.words("café")==Search.words("café"),"Precomposed, combining and common Latin accents normalize consistently")
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new()
	check(library.assets.size()==6555 and library.search_index.index.size()==6555 and library.search_index.semantics.size()==113,"All catalog identities are preindexed alongside explicit reviewed semantics")
	for id in library.search_index.semantics:
		check(library.assets.has(id) and not library.search_index.use_groups(id).is_empty(),"Every reviewed use points to an actual catalog identity: "+id)
	var expected: Array=ids(library.find("all","All assets","school chair",[],false))
	for query in ["chair school","school chairs","shcool chair"]:check(ids(library.find("all","All assets",query,[],false))==expected,"Order/plurals/transposed letters retain school chair results: "+query)
	check("3d:HanX_School/Student_Chair" in expected and "3d:HanX_School/Teacher_Chair" in expected,"Classroom seating finds the concrete student and teacher chairs")
	for fixture in [["benches","3d:HanX_Park/Bench_Park"],["shop shelves","3d:HanX_Shop/Shelf_Wall"],["school buses","3d:HanX_School/School_Bus"]]:
		check(library.find("all","All assets",fixture[0],[],false).any(func(asset: Dictionary):return asset["id"]==fixture[1]),"Common plural endings and irregular furnishing words remain searchable: "+fixture[0])
	for query in ["classroom seating","furnish classroom"]:
		check(library.find("all","All assets",query,[],false).any(func(asset: Dictionary):return asset["id"]=="3d:HanX_School/Student_Chair"),"Reviewed task/semantic tags find the intended artwork: "+query)
	check(library.find("all","All assets","repair workshop",[],false).any(func(asset: Dictionary):return asset["id"]=="3d:HanX_GasStation/Workbench"),"Workshop task finds actual prepared workshop artwork")
	check(ids(library.find("all","All assets","cafe",[],false))==ids(library.find("all","All assets","café",[],false)),"Accented and unaccented cafe queries have equal result sets")
	for id in ["3d:HanX_School/Student_Chair","2d:Coffee_Shop"]:
		var found: Array=library.find("all","All assets",id,[],false)
		check(not found.is_empty() and found[0]["id"]==id,"Exact mode-prefixed ID is first: "+id)
	var source: Array=library.find("all","All assets","03_cubesat_3u.glb",[],false)
	check(not source.is_empty() and source[0]["id"]=="3d:Supplemental_Satellites/03_cubesat_3u","Supplied filename remains searchable")
	var fake: Dictionary={"a":{"id":"a","name":"Café","category":"Custom","data":{}},"b":{"id":"b","name":"Other","category":"Custom","data":{"aliases":["cafe"]}},"c":{"id":"c","name":"Partial import","category":"Custom","data":{"aliases":false,"tags":{}}}}
	var search: RefCounted=Search.new();search.build(fake)
	check(search.rank(fake["a"],search.words("cafe"))>search.rank(fake["b"],search.words("cafe")),"Exact normalized human names rank ahead of semantic/alias matches")
	check(search.use_matches("c","unreviewed") and search.rank(fake["c"],search.words("partial"))>0,"Partial/custom imports remain searchable without invented uses")
	for index in 70:search.rank(fake["a"],search.words("unlikely "+str(index)))
	check(search.queries.size()<=32 and search.scores.size()<=16384,"Repeated typing retains bounded query and edit-distance caches")
	fake.erase("a");search.build(fake);check(not search.index.has("a") and search.rank(fake["b"],search.words("cafe"))>0,"Index rebuild removes deleted assets and refreshes cached matches")
	await workflow()
	print("SEMANTIC SEARCH: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

func workflow() -> void:
	var store=preload("res://scripts/builder/project_store.gd");store.storage_root=OUT+"/history";store.legacy_autosave=OUT+"/legacy.json"
	var studio: Control=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio)
	while not studio.enhancements_ready:await process_frame
	var browser: RefCounted=studio.asset_browser;var tools: RefCounted=browser.semantic_search;var ui: RefCounted=studio.consumer_shell
	check(ui!=null,"Both interfaces expose reviewed use groups")
	if not ui:studio.free();return
	ui.dismiss_welcome();browser.clear_all_filters()
	var authored: Dictionary=studio.current().data.duplicate(true);var history: int=studio.current().undo_history.size();var dirty: bool=studio.dirty
	for active in [false,true]:
		ui.set_active(active,false);browser.clear_all_filters();tools.set_use("classroom");browser.set_theme("space")
		if active:ui.open_drawer("build");ui.group="Everything";ui.style_choice.select(1);ui.query.text="school chair";ui.refresh_catalog()
		else:studio.search.text="school chair";studio.refresh_library()
		await settle();check(studio.cards.get_child_count()==0,"Intentional restrictive filters can produce an empty result: "+str(active))
		var panel: VBoxContainer=tools.simple_panel if active else tools.precision_panel
		check(panel.visible and panel.get_node("Explanation").text.contains("theme Space") and panel.get_node("Explanation").text.contains("use Classroom") and panel.get_node("Broaden").visible,"Empty results identify actual restrictive filters and offer broader search")
		var previous: Dictionary=tools.snapshot();panel.get_node("Broaden").pressed.emit();await settle()
		check(studio.cards.get_child_count()>0 and (ui.query.text if active else studio.search.text)=="school chair" and not tools.saved_filters.is_empty(),"Broader search retains the query and finds matches")
		var card: Control=studio.cards.get_child(0);var tooltip: String=card.tooltip_text
		for refresh in 40:
			if active:ui.update_catalog_notes()
			else:tools.refresh()
		check(card.tooltip_text==tooltip,"Repeated status refresh leaves one stable semantic explanation per card")
		(ui.clear_filters if active else browser.clear_filters).pressed.emit();await settle()
		check(tools.snapshot()==previous and studio.cards.get_child_count()==0,"Restore filters returns to the exact prior filter/page state")
		check(studio.current().data==authored and studio.current().undo_history.size()==history and studio.dirty==dirty,"Searching/grouping/broadening never changes authored state/history/dirty status")
	ui.set_active(false,false);browser.clear_all_filters();tools.settings_path=OUT+"/preferences.json";studio.storage_enabled=true;tools.set_use("workshop");studio.storage_enabled=false;tools.use_filter="";tools.restore()
	check(tools.use_filter=="workshop","Reviewed use preference survives a local round trip")
	for invalid in [false,[],"unknown",null]:
		store.write_json(tools.settings_path,{"use":invalid});tools.restore();check(tools.use_filter.is_empty(),"Malformed or obsolete saved use safely falls back to All uses")
	FileAccess.open(OUT+"/blocked.txt",FileAccess.WRITE).store_string("not a directory");tools.settings_path=OUT+"/blocked.txt/preferences.json";studio.storage_enabled=true;tools.set_use("garden");studio.storage_enabled=false
	check(tools.use_filter=="garden" and studio.status.text.contains("session"),"Failed preference write retains usable session grouping")
	browser.clear_all_filters()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode);var doc: RefCounted=studio.current();doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
		for index in 2:
			var id: String=["3d:HanX_School/Student_Chair","3d:HanX_GasStation/Workbench"][index];doc.add(id,[index*150,0,0] if mode=="2d" else [index*6,0,0],"0")
		studio.changed();await settle();var before: Dictionary=doc.data.duplicate(true)
		tools.set_use("classroom");tools.broaden();tools.restore_filters()
		check(doc.data==before,"Task grouping never stamps or replaces placed objects: "+mode)
		var path: String=OUT+"/semantic_"+mode+".isocity.json"
		check(studio.write_project(path) and studio.load_project(path) and studio.current().data["objects"]==JSON.parse_string(JSON.stringify(before["objects"])) and studio.repair_report.get("issues",[]).is_empty(),"Save/reopen preserves exact placed identities and transforms without repairs: "+mode)
		var result: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],studio.current().data,studio.library,OUT+"/semantic_"+mode+".zip")
		check(result["ok"],"Portable package includes selected reviewed search metadata: "+mode+" "+result.get("message",""))
	studio.free();await process_frame;await process_frame
