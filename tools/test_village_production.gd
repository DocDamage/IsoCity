extends SceneTree

const Plan = preload("res://scripts/builder/village_plan.gd")
const Ledger = preload("res://scripts/builder/village_ledger.gd")
const Delivery = preload("res://scripts/builder/delivery_plan.gd")
const Garden = preload("res://scripts/builder/garden_plan.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const Document = preload("res://scripts/builder/document.gd")
const Repair = preload("res://scripts/builder/project_repair.gd")
const Portable = preload("res://scripts/builder/portable_export.gd")
const OUTPUT = "res://output/verification/asset_expansion/N17"
const IDS = {"farm":"3d:HanX_City/Ground_Garden","granary":"3d:HanX_Construction/Shipping_Container",
	"mill":"3d:HanX_Construction/Site_Office","smith":"3d:HanX_Construction/Tool_Box"}
const LINKS = {"farm":"granary","granary":"mill","mill":"bakery","bakery":"market","smith":"market"}

var studio: Control
var world: Node
var runtime: Node
var tools: RefCounted
var checks: int
var failures: int

func _initialize() -> void: call_deferred("run")

func check(ok: bool, description: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: "+description)
	return ok

func settle() -> void:
	for frame in 8: await process_frame
	await physics_frame

func place(uid: String, asset: String, point: Vector2) -> Dictionary:
	var item: Dictionary = studio.current().add(asset,Plan.Traffic.world(point,studio.mode),studio.library.directions(asset)[0],.72)
	item["uid"] = uid
	item["name"] = uid.capitalize()
	return item

func setup(mode: String) -> void:
	studio.switch_mode(mode)
	var next := Document.new()
	next.data = Templates.make(mode,"blank")
	studio.documents[mode] = next
	var data: Dictionary = studio.current().data
	data["title"] = "Village production test"
	data["economy"] = {"enabled":true,"starting_cash":50000}
	studio.economy_tools.pauses[mode] = true
	place("farm",IDS["farm"],Vector2(-25,0))
	place("granary",IDS["granary"],Vector2(-14,0))
	place("mill",IDS["mill"],Vector2(-3,0))
	place("bakery","2d:Bakery" if mode == "2d" else "3d:HanX_Shop/Shop_Bakery",Vector2(8,0))
	place("market","2d:Produce_Stand" if mode == "2d" else "3d:HanX_Shop/Stall_Vegetable",Vector2(20,0))
	place("smith",IDS["smith"],Vector2(12,12))
	studio.changed()
	world = studio.worlds[mode]
	runtime = world.exploration.village
	runtime.reset()
	runtime.set_physics_process(false)
	tools = studio.village_tools

func author(uid: String) -> void:
	studio.selected_uid = uid
	studio.selected_uids.assign([uid])
	studio._command("village",null)
	tools.use_site.button_pressed = true
	for index in tools.destination.item_count:
		if tools.destination.get_item_metadata(index) == LINKS.get(uid,""): tools.destination.select(index)
	tools.apply_site.pressed.emit()

func stock_fixture(book: RefCounted, uid: String, good: String, units: int) -> void:
	var staged: Dictionary = book.exchange(book.ticket("fixture"),{Plan.key(uid,good):units},0,{"kind":"fixture"})
	if check(staged["ok"],"Fixture supply fits "+uid+" "+good): book.account = staged["account"]

func steps(count: int, season: String = "summer", book: RefCounted = null) -> void:
	if book == null: book = runtime.book
	for frame in count: book.tick(.25,season)

func walk() -> void:
	studio.set_walking(true)
	world.player.set_physics_process(false)
	await settle()

func open(uid: String) -> bool:
	if not runtime.book.sites.has(uid) or runtime.book.sites[uid]["points"].is_empty(): return check(false,"No approach for "+uid)
	for point in runtime.book.sites[uid]["points"]:
		world.player.teleport_to(world.player.get_parent().to_local(runtime.position(point)))
		await physics_frame
		if not world.exploration.interaction_prompt().contains(uid.capitalize()+" supplies"): continue
		world.exploration.interact()
		return check(runtime.has_menu() and runtime.selected == uid and not world.exploration.walk_allowed(),"E opens "+uid+" supplies "+studio.mode)
	return check(false,"No normal E prompt for "+uid+" "+studio.mode+" "+world.exploration.interaction_prompt())

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	studio = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	while not studio.enhancements_ready: await process_frame
	if studio.consumer_shell: studio.consumer_shell.dismiss_welcome()
	catalog()
	for mode in ["2d","3d"]: await chain(mode)
	await supplied_village()
	await truck()
	studio.free()
	await process_frame
	print("VILLAGE PRODUCTION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func catalog() -> void:
	var counts: Dictionary = {}
	for id in studio.library.assets:
		var family: String = studio.library.assets[id]["data"].get("family_id","")
		if not Plan.definitions()["families"].has(family): continue
		var profile: Dictionary = Plan.profile({"asset":id},studio.library)
		if check(profile.get("family") == family and profile.get("role") == Plan.definitions()["families"][family],"Palette shares base role "+id):
			counts[family] = counts.get(family,0)+1
	check(counts.size() == 7 and counts.values().all(func(count: int)->bool: return count == 18),"Seven reviewed source families each cover 18 supplied variants "+str(counts))
	for id in Plan.definitions()["assets"]:
		check(studio.library.assets.has(id),"Approved native fixture resolves "+id)

func chain(mode: String) -> void:
	setup(mode)
	var doc: RefCounted = studio.current()
	check(not Plan.enabled(doc.data) and runtime.book.sites.is_empty(),"Village remains disabled by default "+mode)
	studio._command("village",null)
	tools.enabled.button_pressed = true
	tools.apply_city.pressed.emit()
	for uid in ["farm","granary","mill","bakery","market","smith"]: author(uid)
	check(Plan.enabled(doc.data) and doc.object("mill")["village"]["destination"] == "bakery","Author city setting, reviewed facilities and links "+mode)
	var after: Dictionary = doc.data.duplicate(true)
	studio._command("undo",null)
	check(not doc.object("smith").has("village"),"Undo restores the previous facility record "+mode)
	studio._command("redo",null)
	check(doc.data == after,"Redo restores the exact authored configuration "+mode)
	await settle()
	var book: RefCounted = runtime.book
	if not check(book.sites.size() == 6,"Compile six village facilities "+mode): return
	for uid in LINKS:
		if not check(book.sites[uid]["link"]["reason"].is_empty() and not book.sites[uid]["link"]["path"].is_empty(),
			"Porter routes "+uid+" "+mode+" "+str(book.sites[uid]["link"])): return
	var treasury: Dictionary = doc.data.get("economy_account",{}).duplicate(true)
	await capture_authoring()
	await walk()
	for frame in 48: book.tick(.25,"winter")
	check(book.stock("farm","grain") == 0 and book.states["farm"].contains("dormant") and book.states["mill"] == "Needs grain."
		and book.states["bakery"] == "Needs flour." and book.order("market").is_empty(),"Winter and missing ingredients stall without consuming stock "+mode)
	for frame in 560:
		runtime.step(.25)
		if not book.order("market").is_empty(): break
	if not check(book.order("market").get("goods") == "bread","Grain resumes in season and the actual chain delivers bread "+mode+" "+str(book.states)): return
	var milling: Array = book.account["receipts"].values().filter(func(row: Dictionary)->bool: return row.get("kind") == "batch" and row.get("site") == "mill")
	var baking: Array = book.account["receipts"].values().filter(func(row: Dictionary)->bool: return row.get("kind") == "batch" and row.get("site") == "bakery")
	check(milling.size() >= 2 and baking.size() >= 2 and milling[0]["stock"] == {Plan.key("mill","grain"):-2,Plan.key("mill","flour"):1}
		and baking[0]["stock"] == {Plan.key("bakery","flour"):-1,Plan.key("bakery","bread"):1},"Grain to flour to bread conserves ingredients at each step "+mode)
	if await open("market"):
		await capture_market()
		var offer: Dictionary = book.order("market").duplicate()
		var prior: int = book.stock("market","bread")
		var cash: int = book.account["cash"]
		runtime.view.buttons["sell"].pressed.emit()
		var sale: Dictionary = book.sell("market",offer["id"])
		check(sale.get("credits") == 14 and book.stock("market","bread") == prior-2 and book.account["cash"] == cash+14,
			"Normal sale and retry credit each market delivery exactly once "+mode)
		runtime.close()
	if await open("smith"):
		runtime.view.buttons["forge"].pressed.emit()
		check(book.stock("smith","iron") == 2 and book.stock("smith","fuel") == 2,"Order abstract bar iron and charcoal "+mode)
		runtime.close()
		steps(48,"summer",book)
		var receipts: Array = book.account["receipts"].values().filter(func(row: Dictionary)->bool: return row.get("kind") == "batch" and row.get("site") == "smith")
		check(receipts.size() == 2 and receipts[0]["stock"] == {Plan.key("smith","iron"):-1,Plan.key("smith","fuel"):-1,Plan.key("smith","tools"):1},
			"Smith consumes reviewed abstract inputs for each tool "+mode)
	studio.set_walking(false)
	var frozen: Dictionary = book.account.duplicate(true)
	runtime.step(.5)
	check(book.account == frozen and doc.data.get("economy_account",{}) == treasury,"Build pauses production and authored treasury stays exact "+mode)
	var path: String = OUTPUT+"/village_"+mode
	check(studio.write_project(path+".isocity.json",false),"Normal Save writes authored village "+mode)
	var repair: RefCounted = Repair.new(studio.library)
	var saved: Dictionary = repair.read(path+".isocity.json")
	check(saved["ok"] and repair.issues.is_empty() and Plan.enabled(saved["content"]["documents"][mode]),"Normal Save reopens cleanly "+mode+" "+str(repair.issues))
	if "--portable" in OS.get_cmdline_user_args():
		var result: Dictionary = Portable.new().save(world,doc.data,studio.library,path+".zip")
		check(result["ok"],"The native village is allowed to package "+mode+" "+result.get("message",""))
	check(studio.load_project(path+".isocity.json") and runtime.book.sites.size() == 6 and runtime.book.stock("market","bread") == 0,"Reopen starts a fresh preview "+mode)
	await edge_cases(mode)

func edge_cases(mode: String) -> void:
	var data: Dictionary = studio.current().data.duplicate(true)
	var sites: Dictionary = Plan.compile(data,studio.library)
	var book := Ledger.new()
	book.configure(sites,false)
	var market_cap: int = sites["market"]["profile"]["capacity"]
	stock_fixture(book,"market","bread",market_cap)
	stock_fixture(book,"bakery","bread",2)
	check(not book.begin_transfer("full","bakery","porter")["ok"] and book.stock("bakery","bread") == 2,"Full receiver leaves pickup stock untouched "+mode)
	check(book.supply("smith",{"iron":2,"fuel":2},999)["credits"] == 0 and book.account["cash"] == -1,"Creative keeps finite stock and bypasses price "+mode)
	stock_fixture(book,"market","bread",-market_cap)
	check(book.begin_transfer("remove-destination","bakery","porter")["ok"] and not book.begin_transfer("remove-destination","bakery","porter")["ok"]
		and not book.complete_transfer("remove-destination")["ok"],"An in-flight transfer rejects duplicate dispatch and premature settlement "+mode)
	var removed: Dictionary = sites.duplicate()
	removed.erase("market")
	book.configure(removed,false)
	book.cancel_transfer("remove-destination","Duplicate cancellation.")
	check(book.stock("bakery","bread") == 2 and book.transfers.is_empty(),"Demolishing a destination returns cargo once "+mode)
	book.configure(sites,false)
	check(book.begin_transfer("remove-source","bakery","porter")["ok"],"Dispatch before pickup demolition "+mode)
	removed = sites.duplicate()
	removed.erase("bakery")
	book.configure(removed,false)
	check(book.lost.get("bread") == 2 and book.transfers.is_empty() and book.stock("market","bread") == 0,"Pickup demolition accounts for cargo once "+mode)
	book.configure(sites,false)
	stock_fixture(book,"bakery","flour",1)
	steps(4,"summer",book)
	var revised: Dictionary = data.duplicate(true)
	for item in revised["objects"]:
		if item["uid"] == "bakery": item["village"]["recipe"] = "tomato_loaf"
	book.configure(Plan.compile(revised,studio.library),false)
	steps(26,"summer",book)
	check(book.stock("bakery","flour") == 1 and book.stock("bakery","bread") == 0 and book.states["bakery"] == "Needs tomatoes.",
		"Changing the recipe mid-batch preserves input and requires the new recipe "+mode)
	var malformed: Dictionary = revised.duplicate(true)
	malformed["village"] = {"enabled":"yes","extra":"retain"}
	malformed["objects"][0]["village"] = {"enabled":true,"destination":23,"extra":"retain"}
	var repair: RefCounted = Repair.new(studio.library)
	var clean: Dictionary = repair.world(malformed,mode,"village",0)
	check(not Plan.enabled(clean) and clean["village"]["extra"] == "retain" and clean["objects"][0]["village"] == {"enabled":false,"extra":"retain"}
		and Document.valid(clean,mode,studio.library),"Repair disables malformed village records and preserves placed art and extension data "+mode)
	var copied: Dictionary = {"village":{"destination":"mill"}}
	Plan.copy_link(copied,{"mill":"mill-copy"})
	check(copied["village"]["destination"] == "mill-copy","Copies remap internal links "+mode)
	Plan.copy_link(copied,{})
	check(copied["village"]["destination"] == "","Copies clear external links "+mode)
	var duplicate: Dictionary = studio.current().object("granary").duplicate(true)
	duplicate["uid"] = "loop"
	duplicate["position"] = Plan.Traffic.world(Vector2(-12,-14),mode)
	duplicate["village"]["destination"] = "granary"
	data["objects"].append(duplicate)
	for item in data["objects"]:
		if item["uid"] == "granary": item["village"]["destination"] = "loop"
	var cycle: Dictionary = Plan.compile(data,studio.library)
	check(cycle["granary"]["link"]["reason"].contains("Circular") and cycle["loop"]["link"]["reason"].contains("Circular"),"Circular links halt both ends "+mode)
	if mode == "2d": await optional_adapters(revised)

func optional_adapters(revised: Dictionary) -> void:
	var doc: RefCounted = studio.current()
	doc.finish_checkpoint(true)
	doc.data = revised
	doc.data["garden"] = {"enabled":true}
	doc.data["cooking"] = {"enabled":true}
	var bakery: Dictionary = doc.object("bakery")
	bakery["interior"] = Templates.make("2d","room")
	var room: Dictionary = bakery["interior"]
	room["objects"] = [{"uid":"pantry","asset":"2d:Fridge_White","position":[128,96,0],"direction":"SE","scale":1.0,"cooking":{"enabled":true}}]
	var bed: Dictionary = place("tomato_bed","2d:Planter_Box",Vector2(10,-22))
	bed["garden"] = {"enabled":true,"crop":"tomato"}
	studio.changed()
	await walk()
	var kit: Node = world.exploration.garden
	kit.set_process(false)
	var site: Dictionary = kit.sites.get("tomato_bed",{})
	if not check(not site.is_empty() and site["reason"].is_empty(),"A real garden planter compiles with the village bakery."): return
	var point: Vector2 = Garden.Utility.side_point(site["rect"],"south",.6)
	world.player.teleport_to(kit.world_point(world.instances["tomato_bed"],point,bed))
	await physics_frame
	check(kit.interact("tomato_bed")["ok"],"Plant the tomatoes in a real N06 bed.")
	for elapsed in 24:
		if not kit.crops.has("tomato_bed") or kit.is_ripe(kit.crops["tomato_bed"]): break
		if kit.crops["tomato_bed"]["moisture"] <= 2: kit.interact("tomato_bed")
		for tick in 4: kit.advance(.25)
	var harvest: Dictionary = kit.interact("tomato_bed")
	var harvest_count: int = kit.account["stock"].get("produce/tomato",0)
	check(harvest.get("kind") == "harvest" and harvest_count > 0,"Harvest ripe tomatoes through the existing garden interaction.")
	stock_fixture(runtime.book,"bakery","flour",2)
	if await open("bakery"):
		runtime.view.buttons["tomatoes"].pressed.emit()
		check(kit.account["stock"]["produce/tomato"] == harvest_count-1 and runtime.book.stock("bakery","tomato") == 1,"Garden tomato moves into bakery stock without duplication "+runtime.notice+" "+str(runtime.book.sites["bakery"]["config"]))
		runtime.view.buttons["kitchen"].pressed.emit()
		check(world.exploration.cooking.stock_for("room:bakery:ground:").get("flour") == 5 and runtime.book.stock("bakery","flour") == 1,
			"Owned kitchen pantry accepts one unreserved village flour "+runtime.notice)
		runtime.close()
	studio.set_walking(false)

func supplied_village() -> void:
	setup("2d")
	var doc: RefCounted = studio.current()
	doc.data["village"] = {"enabled":true}
	var asset_ids: Array = studio.library.assets.keys()
	asset_ids.sort()
	var aliases: Dictionary = {}
	for uid in ["farm","granary","mill","bakery","market","smith"]:
		var variants: Array = []
		for id in asset_ids:
			var profile: Dictionary = Plan.profile({"asset":id},studio.library)
			if profile.get("role") == uid and profile.get("family","").begins_with("supplemental/village/"):
				variants.append(id)
		if not check(variants.size() >= 2,"Supplied village asset exists for "+uid): return
		var item: Dictionary = doc.object(uid)
		item["asset"] = variants[0]
		item["direction"] = studio.library.directions(variants[0])[0]
		item["village"] = {"enabled":true,"destination":LINKS.get(uid,"")}
		aliases[uid] = variants[1]
	studio.changed()
	var book: RefCounted = runtime.book
	if not check(book.sites.size() == 6,"Six actual supplied village assets compile as facilities."): return
	await walk()
	for frame in 560:
		runtime.step(.25)
		if not book.order("market").is_empty(): break
	check(book.order("market").get("goods") == "bread","Actual supplied art supports a complete production chain.")
	studio.set_walking(false)
	var stock: int = book.stock("market","bread")
	var market: Dictionary = doc.object("market")
	market["asset"] = aliases["market"]
	market["direction"] = studio.library.directions(market["asset"])[0]
	studio.changed()
	check(stock > 0 and book.stock("market","bread") == stock and book.sites["market"]["profile"]["role"] == "market",
		"Changing the market palette preserves its role and existing stock.")
	if not studio.library.assets[market["asset"]]["data"].get("source_export_allowed",true):
		var result: Dictionary = Portable.new().save(world,doc.data,studio.library,OUTPUT+"/restricted_should_be_refused.zip")
		check(not result["ok"] and not FileAccess.file_exists(OUTPUT+"/restricted_should_be_refused.zip"),
			"Supplied village packs keep their existing source-export rules.")

func truck() -> void:
	setup("3d")
	var doc: RefCounted = studio.current()
	doc.data["village"] = {"enabled":true}
	doc.data["title"] = "Village truck test"
	doc.data["objects"] = []
	doc.data["roads"] = []
	for index in range(-2,9): doc.data["roads"].append({"cell":[0,index]})
	var start: Vector2 = Plan.Traffic.center(Vector2i.ZERO,"3d")+Vector2(-1.5,0)
	var finish: Vector2 = start+Vector2(0,40)
	for config in [["granary",start],["mill",finish]]:
		var uid: String = config[0]
		var pad: Vector2 = config[1]
		var item: Dictionary = place(uid,IDS[uid],pad+Vector2(12,0))
		item["village"] = {"enabled":true,"destination":"mill" if uid == "granary" else "","transport":"truck"}
		item["delivery_site"] = {"enabled":true,"capacity":12,"stock":{}}
		var offset: Vector2 = pad-Delivery.loading_point(item,"3d",studio.library)
		item["delivery_site"].merge({"offset_x":offset.x,"offset_z":offset.y})
	var van: Dictionary = place("van","3d:HanX_Traffic/Van_Delivery",start)
	van["delivery_vehicle"] = {"enabled":true,"capacity":8}
	studio.changed()
	await settle()
	var delivery: RefCounted = world.exploration.driving.delivery
	var book: RefCounted = runtime.book
	if not check(delivery.offers.get("granary",{}).has("village_route"),"N03 exposes the authored route on approved delivery pads "+str(delivery.sites)): return
	check(Plan.required_delivery_art(doc.data) == ["3d:HanX_Shop/Cardboard_Boxes"],"Truck crate dependency is explicit")
	if "--portable" in OS.get_cmdline_user_args():
		var package: Dictionary = Portable.new().save(world,doc.data,studio.library,OUTPUT+"/village_truck.zip")
		check(package["ok"],"Allowed truck route packages its crates "+package.get("message",""))
	var from: Dictionary = {"point":start,"speed":0.0,"height":0.0,"extent":Vector2(.95,2.3)}
	var to: Dictionary = {"point":finish,"speed":0.0,"height":0.0,"extent":Vector2(.95,2.3)}
	check(not delivery.request("van",from,12) and delivery.message.contains("Waiting"),"Truck waits for village stock")
	stock_fixture(book,"granary","grain",4)
	if not check(delivery.request("van",from,12),"Truck dispatch on approved route "+delivery.message): return
	for frame in 40: delivery.step(.25,"van",from,12)
	if not check(delivery.job.get("phase") == "carrying" and book.stock("granary","grain") == 2,"Existing route validates and physically loads two village units "+delivery.message): return
	delivery.cancel()
	check(book.stock("granary","grain") == 4 and delivery.inventory("granary").is_empty(),"Cancel returns exact village cargo and leaves ordinary pad stock untouched")
	check(delivery.request("van",from,12),"Truck can accept a fresh shipment")
	for frame in 40: delivery.step(.25,"van",from,12)
	var ticket: String = delivery.job.get("id","")
	check(delivery.request("van",to,12),"Unload via the actual stopped-vehicle delivery command "+delivery.message)
	for frame in 12: delivery.step(.25,"van",to,12)
	var receipt: Dictionary = delivery.complete(ticket,"van",to,12)
	check(receipt.get("quantity") == 2 and receipt.get("reward") == 0 and book.stock("mill","grain") == 2
		and delivery.inventory("mill").is_empty() and delivery.reward_total == 0,"N03 completes and retries exactly once into village stock")
	steps(16,"summer",book)
	check(book.stock("mill","grain") == 0 and book.stock("mill","flour") == 1,"Truck delivery resumes milling")

func capture_authoring() -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	studio.selected_uid = "mill"
	studio.selected_uids.assign(["mill"])
	for simple in [false,true]:
		studio.consumer_shell.set_active(simple,false)
		if studio.consumer_shell: studio.consumer_shell.dismiss_welcome()
		for width in [1480,960]:
			viewport_size(width)
			studio._command("village",null)
			await settle()
			tools.apply_site.grab_focus()
			await settle()
			check(tools.apply_site.has_focus() and tools.panel.get_global_rect().encloses(tools.apply_site.get_global_rect()),"Village authoring retains keyboard access "+str([studio.mode,simple,width]))
			capture("authoring",simple,width)
			tools.apply_site.release_focus()
	viewport_size(1480)
	studio.consumer_shell.set_active(false,false)

func capture_market() -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	for simple in [false,true]:
		studio.consumer_shell.set_active(simple,false)
		if studio.consumer_shell: studio.consumer_shell.dismiss_welcome()
		if not studio.walking: await walk()
		if not runtime.has_menu() and not await open("market"): return
		for width in [1480,960]:
			viewport_size(width)
			await settle()
			var sell: Button = runtime.view.buttons["sell"]
			sell.grab_focus()
			check(sell.has_focus() and sell.size.y >= 44 and runtime.view.panel.get_global_rect().encloses(sell.get_global_rect())
				and sell.accessibility_name == "Sell ready order","Market sale target fits and has a keyboard and accessibility name "+str([studio.mode,simple,width]))
			capture("market",simple,width)
	viewport_size(1480)
	studio.consumer_shell.set_active(false,false)
	if not studio.walking: await walk()
	if not runtime.has_menu(): await open("market")

func viewport_size(width: int) -> void:
	root.size = Vector2i(width,900 if width == 1480 else 640)
	studio.accessibility_settings.restore({"text_scale":1.5,"high_contrast":true,"large_targets":true} if width == 960 else {})

func capture(phase: String, simple: bool, width: int) -> void:
	RenderingServer.force_draw(false)
	RenderingServer.force_draw(false)
	var file: String = "%s_%s_%s_%d.png" % [phase,studio.mode,"simple" if simple else "precision",width]
	check(root.get_texture().get_image().save_png(OUTPUT+"/"+file) == OK,"Captured "+file)


