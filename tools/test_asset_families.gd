extends SceneTree
const Document = preload("res://scripts/builder/document.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const OUTPUT = "res://output/verification/asset_expansion/I02"
var checks: int = 0
var failures: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; print("FAIL: " + message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var start: int = Time.get_ticks_usec()
	var library: RefCounted = preload("res://scripts/builder/asset_library.gd").new()
	var build_ms: float = (Time.get_ticks_usec() - start) / 1000.0
	check(library.families.members.size() == 75, "75 explicit reviewed design families")
	check(library.search_index.index.size() == library.assets.size(), "Search corpus is built once with the library")
	for spec in [["Village buildings", 450], ["Water towers", 450], ["Bonsai trees", 250]]:
		var found: Array[Dictionary] = library.find("all", "All assets", "", [], false, spec[0])
		check(found.size() == spec[1], "Every exact member remains accessible: " + spec[0])
		var collapsed: Array[Dictionary] = library.families.collapse(found)
		check(collapsed.size() == 25, "Grouped design count: " + spec[0])
		for asset in collapsed:
			check(asset["data"]["palette_id"] == "nopalette" and asset["data"]["lighting_id"] == "studio", "Deterministic default prefers unquantized studio art")
		var concrete: String = found[0]["id"]
		check(library.find("all", "All assets", "", [concrete], true).size() == 1 and library.find("all", "All assets", "", [concrete], true)[0]["id"] == concrete, "Favorite variants remain concrete IDs")
		for mode in ["2d", "3d"]:
			var doc: RefCounted = Document.new(); doc.data = Templates.make(mode, "blank")
			doc.add(concrete, [0, 0, 0], str(library.directions(concrete)[0]))
			var copy: Dictionary = JSON.parse_string(JSON.stringify(doc.data))
			check(Document.valid(copy, mode, library) and copy["objects"][0]["asset"] == concrete, "Saved placements preserve exact appearance IDs: " + mode)
	var family: String = "supplemental/village/apothecary"
	var ids: Array = library.families.members[family]
	var source: Dictionary = library.assets[ids[0]]
	check(library.find("all", "All assets", source["data"]["source_name"], [], false, "Village buildings").size() == 1, "Exact source-name query reveals a concrete appearance member")
	check(library.find("all", "All assets", "", [ids[0], ids[1]], true).size() == 2, "Two favorites from the same family remain separate")
	library.families.remember(source)
	var grouped: Array[Dictionary] = library.families.collapse(library.find("all", "All assets", "", [], false, "Village buildings"))
	check(grouped.all(func(asset: Dictionary) -> bool: return asset["data"]["palette_id"] == source["data"]["palette_id"] and asset["data"]["lighting_id"] == source["data"]["lighting_id"]), "Chosen palette and lighting carry across compatible designs")
	var filtered: Array[Dictionary] = library.find("all", "All assets", "apothecary 24bit", [], false, "Village buildings")
	check(filtered.size() == 3 and library.families.collapse(filtered).size() == 1 and library.families.collapse(filtered)[0]["data"]["palette_id"] == "24bit", "Filtered family uses an actual matching member")
	var incomplete: Array[Dictionary] = [source]
	check(library.families.collapse(incomplete).size() == 1, "Incomplete families do not invent missing combinations")
	var rigged: int = 0
	for asset in library.assets.values():
		if asset["data"].get("rigged", false):
			rigged += 1
			check(asset["data"].get("animation_status") == "rigged_without_clips" and asset["data"].get("supplied_clips", []).is_empty(), "A SWAT rig is not advertised as supplied animation")
	check(rigged == 3, "All three supplied skinned SWAT models are covered")
	check(library.assets["2d:Office_Worker"]["data"]["animation_status"] == "animated_sprite", "Native authored character clips are recognized")
	check(library.assets["2d:Coffee_Shop"]["data"]["animation_status"] == "directional_sprite", "Day/night artwork is not labelled walking animation")
	await workflow(library, ids)
	var query_times: Array[float] = []
	for iteration in 5:
		var query_start: int = Time.get_ticks_usec()
		library.find("all", "All assets", "apothecary 24bit", [], false, "Village buildings")
		query_times.append((Time.get_ticks_usec() - query_start) / 1000.0)
	query_times.sort()
	var metrics := FileAccess.open(OUTPUT + "/metrics.json", FileAccess.WRITE)
	metrics.store_string(JSON.stringify({"library_build_ms": build_ms, "warm_query_median_ms": query_times[2], "warm_query_max_ms": query_times[4], "assets": library.assets.size(), "families": library.families.members.size()}, "\t")); metrics.close()
	print("Asset families: %d checks, %d failures; library + indexes %.2f ms" % [checks, failures, build_ms]); quit(1 if failures else 0)

func settle() -> void:
	for frame in 8: await process_frame

func workflow(library: RefCounted, ids: Array) -> void:
	var store = preload("res://scripts/builder/project_store.gd")
	store.storage_root = OUTPUT + "/history"; store.legacy_autosave = OUTPUT + "/legacy.json"
	var studio: Control = load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled = false; root.add_child(studio)
	while not studio.enhancements_ready: await process_frame
	var browser: RefCounted = studio.asset_browser
	var doc: RefCounted = studio.current(); doc.data = Templates.make(studio.mode, "blank")
	var item: Dictionary = doc.add(ids[0], [0, 0, 0], str(library.directions(ids[0])[0]))
	item["extension"] = {"keep": true}; item["angle"] = 15.0
	item["interior"] = Templates.make(studio.mode, "room")
	studio.changed(); studio.selected_uids.assign([item["uid"]]); studio.selected_uid = item["uid"]
	var before: Dictionary = doc.data.duplicate(true); var history: int = doc.undo_history.size()
	browser.show_asset(ids[0]); await settle()
	check(browser.appearance_row.visible and browser.palette.item_count == 6 and browser.lighting.item_count == 3, "Palette and baked lighting are independent controls")
	var next_palette: int = (browser.palette.selected + 1) % browser.palette.item_count
	browser.palette.select(next_palette); browser.palette.item_selected.emit(next_palette); await settle()
	var destination: String = browser.selected_id
	check(destination != ids[0] and doc.data == before and doc.undo_history.size() == history, "Inspecting another appearance does not edit city/history")
	check(browser.views.item_count == library.directions(destination).size(), "Source angles remain separate from appearance choices")
	browser.apply_appearance(); await settle()
	check(doc.data["objects"][0]["asset"] == destination and doc.data["objects"][0]["angle"] == 15.0 and doc.data["objects"][0]["extension"]["keep"] and doc.data["objects"][0]["interior"] == before["objects"][0]["interior"], "Explicit replacement preserves transform, UID, owned rooms and extensions")
	check(doc.undo() and doc.data == before, "Appearance replacement is one undoable gesture")
	check(doc.redo() and doc.data["objects"][0]["asset"] == destination, "Appearance replacement supports Redo")
	# Different source atlases cannot safely reuse exact painted pixel masks.
	var painted: Dictionary = doc.data["objects"][0]
	painted["colors"] = [{"kind": "pixels", "texture": "res://old_pixels.png"}]
	check(browser.replacement_reason([painted], ids[0]).contains("Custom paint"), "Incompatible paint is explained instead of silently discarded")
	painted.erase("colors")
	check(browser.replacement_reason([painted, painted], ids[0]).contains("Mixed"), "Mixed selection cannot be replaced accidentally")
	doc.data["economy"] = {"enabled": true, "starting_cash": 0}
	doc.data["economy_account"] = preload("res://scripts/builder/economy_plan.gd").account(doc.data, studio.library)
	var unfunded: Dictionary = doc.data.duplicate(true)
	browser.show_asset(ids[0]); browser.apply_appearance(); await settle()
	check(doc.data == unfunded and not studio.status.text.contains("Selected appearance replaced"), "Unaffordable replacement rolls back and retains a useful explanation")
	browser.show_asset("3d:Supplemental_SWAT/SWAT_Commander")
	check(browser.details.text.contains("no supplied animation clips"), "Rigged-without-clips status is visible in actual details")
	browser.dialog.hide()
	root.size = Vector2i(960, 640); browser.show_asset(ids[0]); await settle()
	check(browser.dialog.position.y >= 0 and browser.dialog.position.y + browser.dialog.size.y <= root.size.y, "Appearance controls fit the minimum window")
	var current_palette: String = studio.library.assets[ids[0]]["data"]["palette_id"]
	var missing_id: String = ""
	for id in ids:
		var data: Dictionary = studio.library.assets[id]["data"]
		if data["palette_id"] == current_palette and data["lighting_id"] == "sun": missing_id = id; break
	var removed: Dictionary = studio.library.assets[missing_id]
	studio.library.assets.erase(missing_id); studio.library.rebuild_indexes(); browser.show_asset(ids[0])
	for index in browser.lighting.item_count:
		if browser.lighting.get_item_metadata(index) == "sun": check(browser.lighting.is_item_disabled(index) and not browser.lighting.get_popup().get_item_tooltip(index).is_empty(), "Absent palette/lighting combination is disabled with a reason")
	studio.library.assets[missing_id] = removed; studio.library.rebuild_indexes()
	browser.show_asset(ids[0]); browser.views.select(1); browser.views.item_selected.emit(1)
	var chosen_view: String = browser.views.get_item_text(1)
	var unchanged: Dictionary = doc.data.duplicate(true)
	browser.choose_for_placement()
	check(studio.asset_id == ids[0] and studio.direction == chosen_view and doc.data == unchanged, "Choose for placement keeps the independently previewed source angle without editing existing objects")
	var saved_member: String = doc.data["objects"][0]["asset"]
	var saved_view: String = doc.data["objects"][0]["direction"]
	check(studio.write_project(OUTPUT + "/family.isocity.json") and studio.load_project(OUTPUT + "/family.isocity.json"), "Concrete family appearances save and reopen through the actual project workflow")
	check(studio.current().data["objects"][0]["asset"] == saved_member and studio.current().data["objects"][0]["direction"] == saved_view, "Project reopening preserves exact appearance and source view")
	browser.dialog.hide(); studio.free(); await process_frame; await process_frame
