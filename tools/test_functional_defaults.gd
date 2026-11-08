extends SceneTree
const Defaults = preload("res://scripts/builder/catalog_defaults.gd")
const Business = preload("res://scripts/builder/business_plan.gd")
const Citizen = preload("res://scripts/builder/citizen_plan.gd")
const Document = preload("res://scripts/builder/document.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const OUTPUT = "res://output/verification/asset_expansion/I01"
var checks: int = 0
var failures: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; print("FAIL: " + message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var library: RefCounted = preload("res://scripts/builder/asset_library.gd").new()
	var overlay: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Defaults.PATH))
	check(overlay["assets"].size() == 12, "Eight reviewed HanX shops plus four reviewed school/garage/civic counters, with no inferred extra facilities")
	for id in overlay["assets"]:
		var expected: String = overlay["assets"][id]["business"]
		check(library.assets.has(id) and library.assets[id]["behavior"].get("entrance", false), "Reviewed model and authored entrance exist: " + id)
		var old: Dictionary = {"asset": id}
		check(Business.profile(old)["kind"] == "none" and Citizen.role(old).is_empty(), "Legacy placement keeps its previous decorative behavior: " + id)
		for mode in ["2d", "3d"]:
			var doc: RefCounted = Document.new(); doc.data = Templates.make(mode, "blank")
			var item: Dictionary = doc.add(id, [0, 0, 0], "SE" if id.begins_with("2d:") else "0")
			check(Defaults.enabled(item) and Business.profile(item)["kind"] == expected and Citizen.role(item) == "shop", "New placement receives reviewed defaults: " + mode + "/" + id)
			var active_copy: Dictionary = JSON.parse_string(JSON.stringify(doc.data))
			check(Document.valid(active_copy, mode, library) and Business.profile(active_copy["objects"][0])["kind"] == expected, "Active reviewed default survives save data: " + mode + "/" + id)
			check(preload("res://scripts/builder/economy_plan.gd").profile(id,library)["kind"] == "building", "Reviewed activity preserves the existing building construction-price category")
			check(not Citizen.settings(doc.data)["enabled"] and not preload("res://scripts/builder/service_plan.gd").settings(doc.data)["enabled"] and not preload("res://scripts/builder/economy_plan.gd").settings(doc.data)["enabled"], "New facility metadata never enables a simulation")
			item["business"] = {"kind": "none", "extension": "keep"}
			check(Business.profile(item)["kind"] == "none" and Citizen.role(item).is_empty(), "Explicit business opt-out wins")
			item["business"]["kind"] = "service"; item["citizen_role"] = "none"
			check(Business.profile(item)["kind"] == "service" and Citizen.role(item).is_empty(), "Manual business type and citizen opt-out win independently")
			var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(doc.data))
			check(Document.valid(roundtrip, mode, library) and roundtrip["objects"][0]["business"]["extension"] == "keep" and Defaults.enabled(roundtrip["objects"][0]), "Optional revision and manual extensions survive JSON round trip")
			item["unrelated_extension"] = {"keep": true}
			for invalid in [true, "1", -1, 0.5, 2, NAN, INF]:
				item[Defaults.FIELD] = invalid
				check(not Document.valid(doc.data, mode, library), "Invalid revision is rejected: " + str(invalid))
				var repair: RefCounted = preload("res://scripts/builder/project_repair.gd").new(library)
				var fixed: Dictionary = repair.world(doc.data, mode, "world", 0)
				check(Document.valid(fixed, mode, library) and fixed["objects"][0][Defaults.FIELD] == 0 and fixed["objects"][0]["unrelated_extension"]["keep"] and not repair.issues.is_empty(), "Repair disables invalid revision and archives the original fragment")
	check(Business.profile({"asset": "3d:HanX_Shop/Unknown_Shop", Defaults.FIELD: 1})["kind"] == "none", "Unknown shop filenames never gain behavior")
	check(Business.profile({"asset":"3d:HanX_School/School_Building", Defaults.FIELD:1})["kind"] == "service" and not "school" in Citizen.ROLES, "School counter uses the existing service visit without inventing pupil schedules")
	check(not Defaults.reviewed("3d:HanX_School/Kindergarten_Building") and not Defaults.reviewed("3d:HanX_City/Parking_Garage"), "Unreviewed school and garage filenames remain decorative")
	await workflow(library, overlay["assets"])
	print("Functional defaults: %d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)

func settle() -> void:
	for frame in 8: await process_frame
	await physics_frame

func workflow(library: RefCounted, reviewed: Dictionary) -> void:
	var store = preload("res://scripts/builder/project_store.gd")
	store.storage_root = OUTPUT + "/history"; store.legacy_autosave = OUTPUT + "/legacy.json"
	var studio: Control = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false; root.add_child(studio)
	while not studio.enhancements_ready: await process_frame
	for mode in ["2d", "3d"]:
		studio.switch_mode(mode); var doc: RefCounted = studio.current()
		for id in reviewed:
			doc.data = Templates.make(mode, "blank")
			var item: Dictionary = doc.add(id, [0, 0, 0], "SE" if id.begins_with("2d:") else "0")
			var uid: String = item["uid"]
			studio.changed(); await settle()
			var manager: Node = studio.business_tools.managers[mode]
			manager.hour = 12.5; manager.set_physics_process(false)
			check(manager.available(uid), "New shop offers actual runtime activities: " + mode + "/" + id)
			studio.set_walking(true)
			var world: Node = studio.worlds[mode]
			world.player.set_physics_process(false)
			world.player.teleport_to(world.exploration.entrance(world.instances[uid]))
			var action: Dictionary = Business.activities(Business.profile(item))[0]
			var previous_count: int = manager.service.inventory.get("player", {}).get(action["item"], 0)
			check(manager.request_player(uid, action["id"])["ok"], "Player can start activity at authored approach")
			manager.step(6, false)
			check(manager.service.inventory.get("player", {}).get(action["item"], 0) == previous_count + 1, "Activity awards exactly one real session item")
			world.exploration.interact(); await settle()
			check(world.exploration.interior != null and world.exploration.interior_uid == uid, "Reviewed facility opens its owned room from the authored approach: " + mode + "/" + id)
			world.exploration.leave_interior()
			studio.set_walking(false)
		# Exercise migration choice on an old placement, through existing commands.
		var uid: String = doc.data["objects"][0]["uid"]
		doc.data["objects"][0]["business"] = {"kind":"none", "extension":"keep"}; doc.data["objects"][0]["citizen_role"] = "none"
		studio.selected_uids.assign([uid]); studio.selected_uid = uid; studio.duplicate_selection(); doc.finish_checkpoint()
		var duplicated: Dictionary = doc.object(studio.selected_uid)
		check(Defaults.enabled(duplicated) and duplicated.get("business", {}).get("kind") == "none" and duplicated.get("business", {}).get("extension") == "keep" and duplicated.get("citizen_role") == "none", "Duplication preserves revision and independent explicit opt-outs")
		studio._command("undo", null)
		doc.data["objects"][0].erase("business"); doc.data["objects"][0].erase("citizen_role"); doc.data["objects"][0].erase(Defaults.FIELD)
		studio.selected_uids.assign([uid]); studio.selected_uid = uid; studio.duplicate_selection(); doc.finish_checkpoint()
		check(not Defaults.enabled(doc.object(studio.selected_uid)) and Business.profile(doc.object(studio.selected_uid))["kind"] == "none", "Copying a legacy placement never silently enables new catalog gameplay")
		studio._command("undo", null)
		var item: Dictionary = doc.data["objects"][0]; item.erase(Defaults.FIELD)
		studio.changed(); studio.selected_uids.assign([uid]); studio.selected_uid = uid
		var tools: RefCounted = studio.business_tools
		tools.refresh_selection()
		check(tools.context.text.contains("Older reviewed buildings"), "Legacy behavior and opt-in are explained without a load-time dialog")
		var before: Dictionary = doc.data.duplicate(true)
		tools.kind.select(0); tools.apply_settings(); doc.finish_checkpoint(); await settle()
		check(Defaults.enabled(doc.data["objects"][0]), "Applying Catalog defaults opts legacy selection in")
		check(doc.undo() and doc.data == before, "Opt-in is one undoable document edit")
		check(doc.redo() and Defaults.enabled(doc.data["objects"][0]), "Redo restores reviewed behavior")
		var history: int = doc.undo_history.size()
		tools.kind.select(0); tools.apply_settings(); doc.finish_checkpoint()
		check(doc.undo_history.size() == history, "Repeated default application makes no empty history entry")
		doc.data["objects"][0]["locked"] = true
		tools.kind.select(4); tools.apply_settings(); doc.finish_checkpoint()
		check(Defaults.enabled(doc.data["objects"][0]) and not doc.data["objects"][0].has("business") and doc.undo_history.size() == history, "Protected selection cannot be changed by default controls")
		doc.data["objects"][0].erase("locked")
		tools.kind.select(4); tools.apply_settings(); doc.finish_checkpoint(); await settle()
		check(Business.profile(doc.data["objects"][0])["kind"] == "none", "No business explicitly disables a reviewed shop")
		var path: String = OUTPUT + "/shops_" + mode + ".isocity.json"
		check(studio.write_project(path) and studio.load_project(path), "Reviewed revision and opt-out save and reopen: " + mode)
		check(Business.profile(studio.current().data["objects"][0])["kind"] == "none", "Explicit opt-out survives reopening")
		for id in reviewed:
			if reviewed[id]["business"] == "service": await resident_counter(studio, mode, id)
		await resident_and_export(studio, mode, reviewed)
	studio.free(); await process_frame; await process_frame

func resident_counter(studio: Control, mode: String, id: String) -> void:
	# These are independent projects; use the same transient reset as project load.
	studio.citizen_tools.reset(); studio.business_tools.reset()
	var doc: RefCounted = studio.current(); doc.data = Templates.make(mode, "blank")
	doc.add("2d:Apartment_Brick" if mode == "2d" else "3d:HanX_City/Apartment_4F_A", [-480, -240, 0] if mode == "2d" else [-30, 0, -30], "SW" if mode == "2d" else "90")
	doc.add(id, [160, 96, 0] if mode == "2d" else [14, 0, 12], "SE" if id.begins_with("2d:") else "0")
	doc.data["citizens"] = {"enabled":true, "population":2, "seed":5, "day_length":3600, "start_hour":12.5}
	studio.changed(); await settle()
	var manager: Node = studio.business_tools.managers[mode]
	var citizens: Node = studio.citizen_tools.managers[mode]
	manager.service.reset(); manager.signature = 0; studio.business_tools.dirty = true
	studio.changed(); await settle()
	citizens.set_physics_process(false); manager.set_physics_process(false); manager.hour = 12.5
	var completed: bool = false
	for frame in 12000:
		citizens.hour = 12.5 # Hold the visit window while traversing differently sized source art.
		citizens.step(1.0 / 60); manager.step(1.0 / 60, false)
		if manager.service.inventory.size() == 2 and manager.service.inventory.values().all(func(items: Dictionary) -> bool: return items.get("Service receipt", 0) == 1): completed = true; break
	check(completed, "Residents physically reach the reviewed counter with no instance override: " + mode + "/" + id)
	if not completed:
		var diagnosis: Dictionary = {"mode":mode, "asset":id, "hour":citizens.hour, "destinations":citizens.plan.get("lookup",{}), "inventory":manager.service.inventory, "residents":[]}
		for resident in citizens.residents:
			diagnosis["residents"].append({"point":str(citizens.point(resident["actor"])), "status":resident["status"], "waiting":resident["waiting"], "target":resident["target"], "blocked":resident["blocked"], "path":str(resident["path"]), "business":resident.get("business_state", "")})
		FileAccess.open(OUTPUT + "/counter_route_" + mode + "_" + id.replace(":", "_").replace("/", "_") + ".json", FileAccess.WRITE).store_string(JSON.stringify(diagnosis,"  "))

func resident_and_export(studio: Control, mode: String, reviewed: Dictionary) -> void:
	studio.citizen_tools.reset(); studio.business_tools.reset()
	var doc: RefCounted = studio.current(); doc.data = Templates.make(mode, "blank")
	doc.add("2d:Apartment_Brick" if mode == "2d" else "3d:HanX_City/Apartment_4F_A", [-160, -96, 0] if mode == "2d" else [-14, 0, -12], "SW" if mode == "2d" else "90")
	var cafe: Dictionary = doc.add("3d:HanX_Shop/Shop_Cafe", [160, 96, 0] if mode == "2d" else [14, 0, 12], "0")
	doc.data["citizens"] = {"enabled": true, "population": 2, "seed": 5, "day_length": 3600, "start_hour": 12.5}
	studio.changed(); await settle()
	var manager: Node = studio.business_tools.managers[mode]
	var citizens: Node = studio.citizen_tools.managers[mode]
	manager.service.reset(); manager.signature = 0; studio.business_tools.dirty = true
	studio.changed(); await settle()
	citizens.set_physics_process(false); manager.set_physics_process(false); manager.hour = 12.5
	var completed: bool = false
	for frame in 6000:
		citizens.step(1.0 / 60); manager.step(1.0 / 60, false)
		if manager.service.inventory.size() == 2 and manager.service.inventory.values().all(func(items: Dictionary) -> bool: return items.get("Coffee", 0) == 1): completed = true; break
	check(completed, "Residents physically visit the new catalog cafe without an instance business override: " + mode)
	studio.set_walking(true)
	var world: Node = studio.worlds[mode]
	world.player.set_physics_process(false); world.player.teleport_to(world.exploration.entrance(world.instances[cafe["uid"]]))
	world.exploration.interact(); await settle()
	check(world.exploration.interior != null and world.exploration.interior_uid == cafe["uid"], "Reviewed cafe opens its owned room from the authored approach: " + mode)
	world.exploration.leave_interior(); studio.set_walking(false)
	# Optional metadata does not add a construction charge or bypass co-op regions.
	var before: Dictionary = doc.data.duplicate(true); before["objects"][1].erase(Defaults.FIELD)
	before["economy"] = {"enabled": true}; before["economy_account"] = preload("res://scripts/builder/economy_plan.gd").account(before, studio.library)
	var after: Dictionary = before.duplicate(true); Defaults.stamp(after["objects"][1])
	var quote: Dictionary = preload("res://scripts/builder/economy_plan.gd").quote(before, after, studio.library)
	check(quote["ok"] and quote["account"]["cash"] == before["economy_account"]["cash"], "Opt-in does not charge for an already owned building")
	before["protected_areas"] = [{"uid": "area", "name": "Shop", "owner": "host", "rect": [-100, -100, 200, 200]}]
	after["protected_areas"] = before["protected_areas"].duplicate(true)
	var worlds: Dictionary = {"2d": Templates.make("2d", "blank"), "3d": Templates.make("3d", "blank")}; worlds[mode] = before
	var next: Dictionary = worlds.duplicate(true); next[mode] = after
	check(not preload("res://scripts/builder/cooperative_plan.gd").allowed(worlds, next, "participant", studio.library).is_empty(), "Co-op protection covers catalog revision edits")
	# A small allowed package carries both new defaults and unchanged old choices.
	doc.data = Templates.make(mode, "blank")
	var index: int = 0
	for id in reviewed:
		doc.add(id, [index * 600, 0, 0] if mode == "2d" else [index * 40, 0, 0], "SE" if id.begins_with("2d:") else "0"); index += 1
	var legacy: Dictionary = doc.add("3d:HanX_Shop/Shop_Grocery", [0, -250, 0] if mode == "2d" else [0, 0, -14], "0"); legacy.erase(Defaults.FIELD); legacy["name"] = "Legacy shop"
	var disabled: Dictionary = doc.add("3d:HanX_Shop/Shop_Bakery", [0, 250, 0] if mode == "2d" else [0, 0, 14], "0"); disabled["business"] = {"kind": "none"}; disabled["name"] = "Disabled shop"
	studio.changed(); await settle()
	var result: Dictionary = preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode], doc.data, studio.library, OUTPUT + "/shops_" + mode + ".zip")
	check(result["ok"], "Reviewed/legacy/disabled shops export together: " + mode + " " + result.get("message", ""))
