extends SceneTree
const OUT="res://output/verification/asset_expansion/U01"
const Plan=preload("res://scripts/builder/templates.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;print("FAIL: "+message)
func _initialize() -> void:call_deferred("run")
func settle() -> void:
	for frame in 8:await process_frame
func key(code: Key) -> void:
	for pressed in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.pressed=pressed;Input.parse_input_event(event);await process_frame
func contrast(a: Color,b: Color) -> float:
	var light: Color=a.srgb_to_linear();var dark: Color=b.srgb_to_linear()
	var first: float=.2126*light.r+.7152*light.g+.0722*light.b;var second: float=.2126*dark.r+.7152*dark.g+.0722*dark.b
	return (maxf(first,second)+.05)/(minf(first,second)+.05)
func run() -> void:
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new()
	var baseline: Dictionary={}
	if FileAccess.file_exists(OUT+"/baseline/library.json"):baseline=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/baseline/library.json"))["assets"]
	else:
		for id in library.assets:baseline[id]={"behavior":JSON.parse_string(JSON.stringify(library.assets[id]["behavior"])),"path":library.assets[id]["path"],"pack":library.pack_name(library.assets[id]),"category":library.assets[id]["category"]}
	# U10 approved mesh walking under the fuel canopy after the U01 snapshot.
	# Retain the original snapshot and apply only that reviewed collision change.
	var canopy: String = "3d:HanX_GasStation/Fuel_Canopy"
	if baseline.has(canopy): baseline[canopy]["behavior"]["collision"] = "mesh"
	library.themes.build(library.assets)
	check(library.assets.size()==6555 and library.themes.definitions.size()==6,"All catalog identities and six collections load")
	var shared: String=""
	for id in library.assets:
		var asset: Dictionary=library.assets[id]
		# The baseline was serialized; compare at the same JSON precision rather
		# than mistaking double-to-decimal roundoff for an entrance change.
		check(baseline.has(id) and baseline[id]["behavior"]==JSON.parse_string(JSON.stringify(asset["behavior"])) and baseline[id]["path"]==asset["path"],"Themes leave geometry and gameplay defaults intact: "+id)
		check(library.themes.tags(asset).size()<=6 and library.themes.matches(asset,""),"Everything includes each asset once: "+id)
		if baseline[id]["pack"]=="Pixel Isometric" and baseline[id]["category"]=="Floors":shared=id
	check(not shared.is_empty() and library.themes.matches(library.assets[shared],"pixel_city") and library.themes.matches(library.assets[shared],"village") and library.themes.matches(library.assets[shared],"historical"),"A real floor tile belongs to multiple collections without being duplicated")
	for theme in library.themes.KEYS:
		var selected: Array=[];var seen: Dictionary={}
		for asset in library.find("all","All assets","",[],false):
			if library.themes.matches(asset,theme):selected.append(asset);seen[asset["id"]]=true
		check(not selected.is_empty() and selected.size()==seen.size(),"Reviewed theme has unique real assets: "+theme)
	var unknown: String=""
	for id in library.themes.members["unclassified"]:unknown=id;break
	check(not unknown.is_empty() and library.themes.tags(library.assets[unknown]).is_empty() and library.themes.describe(library.assets[unknown]).contains("Unclassified"),"Unknown setting remains available with a useful explanation")
	var custom: Dictionary={"id":"2d:Custom/U01_test","mode":"2d","name":"Unknown custom object","category":"Custom","path":library.assets[shared]["path"],"data":{},"behavior":{}}
	library.assets[custom["id"]]=custom;library.rebuild_indexes()
	check(library.themes.matches(custom,"unclassified"),"New custom import refreshes the unclassified index")
	custom["data"]["themes"]=["space","space",true,"unsupported"];library.rebuild_indexes()
	check(library.themes.tags(custom)==["space"] and library.themes.matches(custom,"space"),"Explicit custom tags are validated, deduplicated and indexed")
	custom["data"]["themes"]="space";library.rebuild_indexes();check(library.themes.matches(custom,"unclassified"),"Malformed custom tags safely stay unclassified")
	library.assets.erase(custom["id"]);library.rebuild_indexes()
	var store=preload("res://scripts/builder/project_store.gd");store.storage_root=OUT+"/history";store.legacy_autosave=OUT+"/legacy.json"
	var studio: Control=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio)
	while not studio.enhancements_ready:await process_frame
	var browser: RefCounted=studio.asset_browser;var ui: RefCounted=studio.consumer_shell
	check(ui!=null,"Theme workflow includes both interfaces")
	if not ui:studio.free();quit(1);return
	ui.dismiss_welcome();ui.group="Everything";ui.style_choice.select(1);ui.query.clear();ui.open_drawer("build");ui.group="Everything";ui.refresh_catalog()
	var popup: PopupMenu=ui.theme_choice.get_popup();var hovered: StyleBoxFlat=popup.get_theme_stylebox("hover") as StyleBoxFlat
	check(hovered!=null and contrast(popup.get_theme_color("font_hover_color"),hovered.bg_color)>=4.5,"Keyboard-highlighted theme labels retain readable contrast")
	var before: Dictionary=studio.current().data.duplicate(true);var history: int=studio.current().undo_history.size()
	# Compact task browsing puts less frequent theme controls in scrollable Refine.
	if ui.theme_choice.get_parent()==ui.refine_controls:
		ui.refine.visible=true;ui.layout();ui.refine.ensure_control_visible(ui.theme_choice);await settle()
	ui.theme_choice.grab_focus();await settle();await key(KEY_SPACE);await settle()
	check(ui.theme_choice.get_popup().visible,"Keyboard opens the visual theme selector")
	await key(KEY_DOWN);await key(KEY_ENTER);await settle()
	check(not browser.theme_filter.is_empty() and browser.theme_choice.get_item_metadata(browser.theme_choice.selected)==browser.theme_filter,"Keyboard theme choice synchronizes precision controls")
	ui.theme_canvas.grab_focus();await key(KEY_SPACE);await settle()
	check(ui.drawer_kind.is_empty() and root.gui_get_focus_owner()==studio.canvas,"Keyboard users can return from theme browsing to the canvas")
	ui.open_drawer("build");ui.group="Everything";ui.query.text="industrial";browser.set_theme("industrial");await settle()
	var modes: Dictionary={}
	for asset in ui.matches():modes[asset["mode"]]=true
	check(modes.has("2d") and modes.has("3d") and studio.cards.get_child_count()>0,"A theme query finds actual artwork across source styles")
	if studio.cards.get_child_count()>0:
		var card: Button=studio.cards.get_child(0);browser.show_asset(card.asset_id)
		check(card.tooltip_text.contains("Industrial") and card.tooltip_text.contains("Pack:") and browser.details.text.contains("Themes:"),"Cross-style matches explain their collection and provenance")
		browser.dialog.hide()
	var prior_size: Vector2i=root.size
	ui.query.text="";browser.set_theme("village")
	for size in [Vector2i(1480,900),Vector2i(960,640)]:
		root.size=size
		studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true});ui.layout();await settle()
		check(root.get_visible_rect().encloses(ui.drawer.get_global_rect()) and ui.drawer.get_global_rect().encloses(ui.clear_filters.get_global_rect()),"Theme drawer and Clear filters fit at enlarged text: "+str(size))
		check(not ui.clear_filters.get_global_rect().intersects(ui.theme_choice.get_global_rect()) and ui.result_note.tooltip_text==ui.result_note.text,"Clear filters stays separate and full counts remain available: "+str(size))
	for position in ui.theme_choice.item_count:
		var texture: Texture2D=ui.theme_choice.get_item_icon(position)
		check(texture!=null and texture.get_width()<=32 and texture.get_height()<=32,"Theme artwork is bounded in both dimensions")
	studio.accessibility_settings.restore({"text_scale":1.0,"large_targets":false,"high_contrast":false});root.size=prior_size;ui.layout();await settle()
	ui.set_active(false,false);studio.pack_filter="HanX_Park";studio.search.clear();browser.set_theme("space");await settle()
	check(studio.library_matches().is_empty() and browser.chips.has_node("theme") and browser.clear_filters.is_visible_in_tree(),"Conflicting pack/theme filters stay explicit and Clear remains reachable")
	browser.clear_filters.pressed.emit();await settle()
	check(browser.theme_filter.is_empty() and studio.pack_filter.is_empty() and studio.asset_type.selected==0 and browser.content_scope==2 and not studio.library_matches().is_empty(),"Clear filters restores unrestricted theme/type/pack/content browsing")
	check(studio.current().data==before and studio.current().undo_history.size()==history,"Theme, query and clear operations never mutate the city or its history")
	browser.theme_settings_path=OUT+"/theme_preferences.json";studio.storage_enabled=true;browser.set_theme("village");studio.storage_enabled=false
	browser.theme_filter="";browser.restore_theme();check(browser.theme_filter=="village" and studio.current().data==before,"Theme preference persists locally and separately from authored city state")
	for invalid in [true,2,[],"unknown",null]:
		store.write_json(browser.theme_settings_path,{"theme":invalid});browser.restore_theme();check(browser.theme_filter.is_empty(),"Malformed theme preference defaults to Everything")
	FileAccess.open(OUT+"/blocked_parent.txt",FileAccess.WRITE).store_string("not a directory")
	browser.theme_settings_path=OUT+"/blocked_parent.txt/theme.json";studio.storage_enabled=true;browser.set_theme("space");studio.storage_enabled=false
	check(browser.theme_filter=="space" and studio.status.text.contains("session") and studio.current().data==before,"Failed preference write leaves a usable session and unchanged city")
	var definition: Dictionary=studio.library.themes.definitions
	var ids: Array[String]=["2d:Coffee_Shop",shared,definition["space"]["preview_id"]]
	for mode in ["2d","3d"]:
		studio.switch_mode(mode);var doc: RefCounted=studio.current();doc.data=Plan.make(mode,"blank")
		for index in ids.size():doc.add(ids[index],[index*150,0,0] if mode=="2d" else [index*6,0,0],str(studio.library.directions(ids[index])[0]),1)
		studio.changed();await settle();var authored: Dictionary=doc.data.duplicate(true)
		browser.set_theme("historical");browser.set_theme("unclassified")
		check(doc.data==authored,"Placed IDs/transforms remain intact through theme changes: "+mode)
		var path: String=OUT+"/themes_"+mode+".isocity.json"
		check(studio.write_project(path) and studio.load_project(path) and studio.current().data["objects"]==authored["objects"],"Theme browsing preserves project save/reopen: "+mode)
		var result: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],studio.current().data,studio.library,OUT+"/themes_"+mode+".zip")
		check(result["ok"],"Allowed multi-theme assets export: "+mode+" "+result.get("message",""))
	studio.free();await process_frame;await process_frame
	print("ASSET THEMES: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
