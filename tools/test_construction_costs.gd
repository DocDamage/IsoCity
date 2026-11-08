extends SceneTree

const Document = preload("res://scripts/builder/document.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const Economy = preload("res://scripts/builder/economy_plan.gd")
const Costs = preload("res://scripts/builder/construction_cost.gd")
const Tools = preload("res://scripts/builder/construction_cost_tools.gd")
const Blueprint = preload("res://scripts/builder/blueprint_plan.gd")
const Portable = preload("res://scripts/builder/portable_export.gd")
const Paint = preload("res://scripts/builder/part_colors.gd")
const SHIP = "3d:Supplemental_Spaceships_II/hammerhead_cruiser"
const PATH = "res://output/verification/asset_expansion/U20/"
var studio: Control
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, what: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + what)
	return ok

func frames(count: int = 6) -> void:
	for frame in count: await process_frame

func capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	await frames(10)
	for frame in 4: await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	check(image.save_png(PATH + name + ".png") == OK, "Captured " + name)

func select(uid: String) -> void:
	studio.selected_uid = uid
	studio.selected_uids.assign([uid])

func account(doc: RefCounted) -> Dictionary:
	return doc.data["economy_account"]

# New placement and starter-room IDs are allocated at commit. Compare the
# paid amounts and ledger while allowing those fresh identities.
func paid_values(value: Dictionary) -> Array:
	var result: Array = []
	for unit in value["holdings"].values(): result.append(JSON.stringify(unit))
	result.sort()
	return [value["cash"], value["construction_total"], value["refund_total"], value["ledger"], result]

func fixture(mode: String, credits: int = 30000) -> RefCounted:
	studio.switch_mode(mode)
	var doc := Document.new()
	doc.data = Templates.make(mode, "blank")
	doc.data["economy"] = {"enabled": true, "starting_cash": credits, "period_seconds": 300, "refund_percent": 40}
	doc.data["economy_account"] = Economy.fresh_account(doc.data, studio.library)
	studio.documents[mode] = doc
	studio.economy_tools.pauses[mode] = true
	studio.changed()
	return doc

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PATH))
	root.size = Vector2i(1480, 900)
	studio = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	while not studio.enhancements_ready: await process_frame
	studio.consumer_shell.dismiss_welcome()
	for mode in ["2d", "3d"]: await workflow(mode)
	await appearance()
	studio.free()
	await frames()
	print("CONSTRUCTION COSTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func workflow(mode: String) -> void:
	var doc: RefCounted = fixture(mode)
	var tools: RefCounted = studio.construction_cost_tools
	studio._command("construction_costs", null)
	await frames()
	var home: String = "2d:House_Blue" if mode == "2d" else "3d:HanX_City/Row_Houses_A"
	studio.select_asset(home)
	var at: Vector2 = studio.canvas.size * .5
	var original: Dictionary = doc.data.duplicate(true)
	var quote: Dictionary = tools.changed_candidate(0, at)
	if not check(quote.has("quote"), mode + " shows a place quote"): return
	check(quote["quote"]["construction"] == 2000 and doc.data == original and doc.undo_history.is_empty(), mode + " previews placement without touching data, history or treasury")
	studio.drop_asset(home, at)
	await frames()
	check(paid_values(account(doc)) == paid_values(quote["quote"]["account"]), mode + " charges exactly the quoted placement")
	var uid: String = doc.data["objects"][0]["uid"]
	studio.set_tool("select")
	select(uid)
	quote = tools.changed_candidate(3, at)
	check(quote["quote"]["construction"] == 0 and not Costs.change(quote["before"], quote["after"])["added"].is_empty(), mode + " starter furnishings render while the build quote is free")
	studio.interior_tools.prepare(uid, mode)
	doc.finish_checkpoint()
	check(paid_values(account(doc)) == paid_values(quote["quote"]["account"]), mode + " starter holdings match the free quote")
	var interior: Dictionary = doc.object(uid)["interior"]
	var room: Dictionary = Templates.make(mode, "room")
	room["objects"].append(Document.placement_item("nested_prop", "2d:crate", [20, 0, 20], "SE", 1))
	interior["floors"] = [{"uid": "upper", "room": room, "name": "Upper", "height": 3.0}]
	quote = tools.changed_candidate(1, at)
	var delta: Dictionary = Costs.change(quote["before"], quote["after"])
	check(quote["quote"]["construction"] > 2000 and delta["added"].size() > interior["objects"].size() + 1, mode + " duplication quotes nested furnishings")
	var before_cash: int = account(doc)["cash"]
	studio.duplicate_selection()
	doc.finish_checkpoint()
	await frames()
	check(account(doc)["cash"] == before_cash - quote["quote"]["net"], mode + " duplicate uses the full quote once")
	var clone: String = doc.data["objects"].back()["uid"]
	select(clone)
	quote = tools.changed_candidate(2, at)
	check(quote["quote"]["refund"] > 800 and quote["quote"]["net"] < 0, mode + " removal quotes the recorded nested purchase bases")
	studio.remove_selection()
	doc.finish_checkpoint()
	await frames()
	check(account(doc) == quote["quote"]["account"], mode + " demolition refunds exactly the quote")
	studio._command("undo", null)
	await frames()
	check(not doc.object(clone).is_empty() and account(doc) == quote["before"]["economy_account"], mode + " Undo restores paid objects and exact account")
	studio._command("redo", null)
	await frames()
	check(doc.object(clone).is_empty() and account(doc) == quote["quote"]["account"], mode + " Redo restores removal and refund once")
	studio.interior_tools.start(uid)
	studio.interior_tools.floor_tools.switch_floor("upper")
	studio.select_asset("2d:crate")
	at = studio.canvas.size * .42
	quote = tools.changed_candidate(0, at)
	check(studio.current().floor_uid == "upper" and quote["quote"]["construction"] == Economy.profile("2d:crate", studio.library)["construction"],
		mode + " upper-room placement uses the exterior treasury")
	studio.drop_asset("2d:crate", at)
	check(paid_values(account(doc)) == paid_values(quote["quote"]["account"]), mode + " upper-floor purchase matches the quote")
	studio.interior_tools.leave()
	var proposals := [
		{"uid": "build_home", "kind": "building", "item": Document.placement_item("", home, [144, 0, 25], studio.library.directions(home)[0], 1)},
		{"uid": "build_road", "kind": "road", "start": [2, 2], "end": [3, 2], "settings": studio.road_settings.settings()}
	]
	doc.data["blueprints"] = proposals
	var ids := ["build_home", "build_road"]
	var plan: Dictionary = Blueprint.construct(doc.data, ids, studio.library)
	check(plan["ok"] and plan["quote"]["construction"] > 2000, mode + " ordinary building and road proposals have one combined quote")
	var drafts: RefCounted = studio.blueprint_tools
	drafts.show()
	drafts.review(ids)
	check("Exact economy quote" in drafts.review_label.text and "Approximate render cost" in drafts.review_label.text, mode + " Blueprint presents finance and rendering separately")
	doc.data["economy_account"]["cash"] = 0
	await frames(25)
	check("Insufficient" in drafts.review_label.text and doc.data["blueprints"].size() == 2, mode + " quote refreshes after treasury change and leaves proposals in place")
	doc.data["economy_account"]["cash"] = 28000
	plan = Blueprint.construct(doc.data, ids, studio.library)
	drafts.construct(true)
	check(account(doc) == plan["quote"]["account"] and doc.data["blueprints"].is_empty(), mode + " Blueprint commit charges the exact combined quote once")
	studio._command("construction_costs", null)
	studio.set_tool("road")
	at = studio.canvas.size * .55
	quote = tools.changed_candidate(0, at)
	var pointer := InputEventMouseButton.new()
	pointer.button_index = MOUSE_BUTTON_LEFT
	pointer.pressed = true
	pointer.position = at
	studio._canvas_input(pointer)
	studio.finish_edit(at)
	check(account(doc) == quote["quote"]["account"], mode + " active road quote matches the actual stroke")
	var ground: String = "2d:Grass" if mode == "2d" else ""
	if not studio.library.assets.has(ground) or not studio.library.is_ground_tile(ground):
		for id in studio.library.assets:
			if studio.library.is_ground_tile(id):
				ground = id
				break
	studio.select_asset(ground)
	studio.ground_brush.operation.select(2)
	at = studio.canvas.size * .67
	quote = tools.changed_candidate(0, at)
	doc.checkpoint()
	studio.ground_brush.begin(at)
	studio.ground_brush.finish(at)
	doc.finish_checkpoint()
	check(paid_values(account(doc)) == paid_values(quote["quote"]["account"]), mode + " same ground planner quotes and commits the rectangle's first cell")
	studio.select_asset(home)
	doc.data["economy_account"]["cash"] = 0
	quote = tools.changed_candidate(0, studio.canvas.size * .35)
	original = doc.data.duplicate(true)
	check(not quote["quote"]["ok"] and quote["quote"]["construction"] == 2000, mode + " insufficient budget keeps exact cost and rejection reason")
	studio.drop_asset(home, studio.canvas.size * .35)
	await frames()
	check(doc.data == original, mode + " rejected placement leaves the city and account intact")

func appearance() -> void:
	var doc: RefCounted = fixture("2d")
	var tools: RefCounted = studio.construction_cost_tools
	studio.drop_asset(Tools.MODEL_CRATE, studio.canvas.size * .5)
	var source: Dictionary = doc.data["objects"][0]
	var source_uid: String = source["uid"]
	studio.set_tool("select")
	select(source_uid)
	studio._command("construction_costs", null)
	var before: Dictionary = doc.data.duplicate(true)
	var history: int = doc.undo_history.size()
	tools.review_comparison()
	await frames()
	check(tools.comparison.dialog.visible and tools.comparison.gallery.get_child_count() == 2, "Lighter crate compares two real scenes")
	check(not tools.comparison.replace.disabled and "fewer private live views" in tools.comparison.note.text, "Lighter replacement presents a cost difference and requires review")
	check(doc.data == before and doc.undo_history.size() == history, "Private comparison leaves city and treasury intact")
	await capture("replacement_2d")
	var target: Dictionary = tools.comparison.target_item.duplicate(true)
	var draft: Dictionary = tools.replacement_draft(source, target)
	if not check(draft.has("quote") and draft["quote"]["ok"], "The reviewed replacement can be applied"): return
	doc.data["economy_account"]["cash"] += 1
	tools.comparison.replace.pressed.emit()
	check(doc.object(source_uid)["asset"] == Tools.MODEL_CRATE and tools.comparison.replace.disabled, "A stale comparison leaves the original and requires review again")
	doc.data["economy_account"]["cash"] -= 1
	tools.comparison.dialog.hide()
	tools.review_comparison()
	tools.comparison.replace.pressed.emit()
	doc.finish_checkpoint()
	await frames()
	check(doc.object(source_uid)["asset"] == Tools.SPRITE_CRATE and doc.object(source_uid)["position"] == source["position"] and account(doc) == draft["quote"]["account"], "Replacement keeps identity, position and the exact treasury quote")
	studio._command("undo", null)
	await frames()
	check(doc.object(source_uid)["asset"] == Tools.MODEL_CRATE and account(doc) == before["economy_account"], "Undo restores the original asset and its paid basis")
	studio._command("redo", null)
	await frames()
	check(doc.object(source_uid)["asset"] == Tools.SPRITE_CRATE and account(doc) == draft["quote"]["account"], "Redo restores only the reviewed transaction")
	if not "--capture" in OS.get_cmdline_user_args():
		var portable: Dictionary = Portable.new().save(studio.worlds["2d"], doc.data, studio.library, PATH + "costs_2d.zip")
		check(portable["ok"], "Replaced crate and its treasury export to a portable project")
		check(studio.write_project(PATH + "costs_2d.isocity.json"), "Replacement and account save in the project")
	for mode in ["2d", "3d"]:
		doc = fixture(mode)
		var a: Dictionary = doc.add(SHIP, [0, 0, 0], "0")
		var b: Dictionary = doc.add(SHIP, [64, 32, 0] if mode == "2d" else [8, 0, 0], "0")
		var c: Dictionary = doc.add(SHIP, [-64, 32, 0] if mode == "2d" else [-8, 0, 0], "45")
		doc.data["economy_account"] = Economy.fresh_account(doc.data, studio.library)
		studio.changed()
		var painted_model: Node3D = Paint.model_root(studio.worlds[mode].instances[c["uid"]])
		var mesh: MeshInstance3D = painted_model.find_children("*", "MeshInstance3D", true, false)[0]
		c["colors"] = [{"kind": "faces", "color": [.8, .3, .3, 1], "mesh": str(painted_model.get_path_to(mesh)), "surface": 0, "faces": [0]}]
		studio.changed()
		check(mesh.mesh != Paint.original_mesh(mesh) and Paint.valid(c["colors"]), mode + " test exercises a real painted mesh surface")
		studio.set_tool("select")
		select(a["uid"])
		var cabinet := {"asset": "3d:Supplemental_Arcade/01_arcade_01_upright_woodgrain", "direction": "0"}
		var one_cabinet: Dictionary = tools.scan.estimate({"a": cabinet}, mode)
		var four_cabinets: Dictionary = tools.scan.estimate({"a": cabinet, "b": cabinet, "c": cabinet, "d": cabinet}, mode)
		check(one_cabinet["textures"] == 2 and four_cabinets["textures"] == 2 and one_cabinet["texture_bytes"] == four_cabinets["texture_bytes"],
			mode + " two distinct source textures are shared across four model instances")
		var separate: Dictionary = tools.scan.estimate({"a": a}, mode)
		var together: Dictionary = tools.scan.estimate({"a": a, "b": b, "c": c}, mode)
		check(separate["textures"] > 0 and together["textures"] == separate["textures"] and together["texture_bytes"] == separate["texture_bytes"], mode + " shared source textures count once")
		check(together["triangles"] == separate["triangles"] * 3 and together["painted"] == 1, mode + " triangle burden follows instance count and paint adds a separate estimate")
		if mode == "2d":
			check(together["shared"] == 1 and together["live"] == 1, "Identical Pixel poses share one view while paint uses a private live view")
		studio._command("construction_costs", null)
		tools.operation.select(1)
		tools.refresh()
		check("credits" in tools.quote.text and "Approximate render cost" in tools.estimate.text, mode + " inspector labels the estimates separately")
		for simple in [true, false]:
			studio.consumer_shell.set_active(simple, false)
			for compact in [false, true]:
				root.size = Vector2i(960, 640) if compact else Vector2i(1480, 900)
				studio.accessibility_settings.text_scale = 1.5 if compact else 1.0
				studio.accessibility_settings.high_contrast = compact
				studio.accessibility_settings.large_targets = compact
				studio.accessibility_settings.apply()
				studio._command("construction_costs", null)
				await frames()
				var flavor: String = ("simple" if simple else "precision") + ("_960" if compact else "_1480")
				check(tools.operation.has_focus() and tools.panel.follow_focus, mode + " keyboard focus opens in " + flavor)
				check(not compact or tools.operation.custom_minimum_size.y >= 44, mode + " compact view respects larger targets")
				check(tools.operation.get_global_rect().end.x <= root.size.x + 2,
					mode + " full quote control is within the visible " + flavor + " viewport")
				await capture("quote_" + mode + "_" + flavor)
				if simple and compact:
					tools.review_comparison()
					await frames()
					check(tools.comparison.dialog.visible and not tools.comparison.replace.visible and tools.comparison.gallery.is_ancestor_of(tools.comparison.dialog.gui_get_focus_owner()), mode + " actual low and full editions open at compact size with keyboard focus")
					check(tools.comparison.scroller.size.y >= 240 and tools.comparison.gallery.size.x > 280,
						mode + " compact comparison leaves room for both rendered editions")
					await capture("editions_" + mode)
					tools.comparison.dialog.hide()
		if mode == "3d" and not "--capture" in OS.get_cmdline_user_args():
			doc.data["objects"].erase(c)
			studio.changed()
			var portable: Dictionary = Portable.new().save(studio.worlds[mode], doc.data, studio.library, PATH + "costs_3d.zip")
			check(portable["ok"], "Reviewed model and its treasury export to a portable Model project")
