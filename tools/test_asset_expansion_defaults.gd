extends SceneTree

const Templates = preload("res://scripts/builder/templates.gd")
const Document = preload("res://scripts/builder/document.gd")
const Store = preload("res://scripts/builder/project_store.gd")
const Citizens = preload("res://scripts/builder/citizen_plan.gd")
const Traffic = preload("res://scripts/builder/traffic_plan.gd")
const Services = preload("res://scripts/builder/service_plan.gd")
const Transit = preload("res://scripts/builder/transit_plan.gd")
const Economy = preload("res://scripts/builder/economy_plan.gd")
const Zones = preload("res://scripts/builder/zone_plan.gd")
const School = preload("res://scripts/builder/school_plan.gd")
const Care = preload("res://scripts/builder/vehicle_service_plan.gd")
const Delivery = preload("res://scripts/builder/delivery_plan.gd")
const Utility = preload("res://scripts/builder/utility_plan.gd")
const Garden = preload("res://scripts/builder/garden_plan.gd")
const Market = preload("res://scripts/builder/market_plan.gd")
const Cooking = preload("res://scripts/builder/cooking_plan.gd")
const Laundry = preload("res://scripts/builder/laundry_plan.gd")
const Fitness = preload("res://scripts/builder/fitness_plan.gd")
const Arcade = preload("res://scripts/builder/arcade_plan.gd")
const Camping = preload("res://scripts/builder/camping_plan.gd")
const Pets = preload("res://scripts/builder/pet_plan.gd")
const Harbor = preload("res://scripts/builder/harbor_plan.gd")
const Cycling = preload("res://scripts/builder/cycling_plan.gd")
const Scenarios = preload("res://scripts/builder/scenario_plan.gd")
const Village = preload("res://scripts/builder/village_plan.gd")
const Outpost = preload("res://scripts/builder/space_outpost_plan.gd")

const OUTPUT = "res://output/verification/asset_expansion/P7/defaults"
const SCHOOL = "3d:HanX_School/School_Building"
const ASSETS = {
	"2d": [SCHOOL, "2d:EV_Charger", "2d:Delivery_Van", "2d:Supermarket"],
	"3d": [SCHOOL, "3d:HanX_GasStation/Fuel_Pump", "3d:HanX_Traffic/Van_Delivery", "3d:HanX_Shop/Shop_Grocery"],
}

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)
	return ok

func check_world(data: Dictionary, description: String) -> void:
	var citizens: Dictionary = Citizens.settings(data)
	var switches := {
		"citizens": citizens["enabled"],
		"resident activities": citizens["interior_activities"],
		"traffic": Traffic.settings(data)["enabled"],
		"city services": Services.settings(data)["enabled"],
		"transit": Transit.settings(data)["enabled"],
		"economy": Economy.settings(data)["enabled"],
		"zoning": Zones.settings(data)["enabled"],
		"water": Utility.enabled(data, "water"),
		"power": Utility.enabled(data, "power"),
		"garden": Garden.settings(data),
		"cooking": Cooking.enabled(data),
		"laundry": Laundry.enabled(data),
		"fitness": Fitness.enabled(data),
		"arcade": Arcade.enabled(data),
		"camping": Camping.enabled(data),
		"pet": Pets.settings(data)["enabled"],
		"harbor": Harbor.enabled(data),
		"cycling": Cycling.enabled(data),
		"construction and emergency scenarios": Scenarios.valid(data.get("scenario", {})),
		"village production": Village.enabled(data),
		"space outpost": Outpost.settings(data)["enabled"],
	}
	for feature in switches:
		check(switches[feature] == false, description + " leaves " + feature + " disabled")

func decorate(data: Dictionary, library: RefCounted, legacy: bool) -> void:
	var ids: Array = ASSETS[data["mode"]]
	for index in ids.size():
		var asset: String = ids[index]
		if not check(library.assets.has(asset), "Fixture has prepared asset " + asset): continue
		var at := [-80 + index * 32, -48, 0] if data["mode"] == "2d" else [-18 + index * 12, 0, -10]
		var record: Dictionary = Document.placement_item("default_probe_" + str(index), asset, at, library.directions(asset)[0], 1.0)
		if legacy: record.erase("catalog_behavior_revision")
		data["objects"].append(record)

func check_decorations(data: Dictionary, description: String) -> void:
	var by_asset := {}
	for item in data["objects"]:
		by_asset[item["asset"]] = item
	var ids: Array = ASSETS[data["mode"]]
	if not check(ids.all(func(id: String) -> bool: return by_asset.has(id)), description + " retains all four placed assets"): return
	var school: Dictionary = by_asset[ids[0]]
	var bay: Dictionary = by_asset[ids[1]]
	var van: Dictionary = by_asset[ids[2]]
	var market: Dictionary = by_asset[ids[3]]
	check(School.eligible(school) and not School.enabled(school), description + " school has no schedule")
	check(Care.site_asset(bay) and Care.bay(bay).is_empty(), description + " station has no enabled service bay")
	check(Care.vehicle_asset(van) and Care.vehicle(van).is_empty(), description + " van has no enabled vehicle-care profile")
	check(Delivery.eligible(van, "delivery_vehicle") and not Delivery.enabled(van, "delivery_vehicle"),
		description + " van has no delivery activation")
	check(Delivery.eligible(market, "delivery_site") and not Delivery.enabled(market, "delivery_site")
		and not Delivery.enabled(market, "delivery_contract"), description + " store has no delivery site or contract")
	check(Market.eligible(market) and not Market.enabled(market), description + " market host has no schedule")
	check(School.required_bus(data).is_empty() and Delivery.required_assets(data).is_empty()
		and Market.required_assets(data).is_empty() and Outpost.required(data).is_empty(),
		description + " requires no future activity assets for ordinary placements")

func run() -> void:
	var studio: Control = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	while not studio.enhancements_ready: await process_frame
	if studio.consumer_shell: studio.consumer_shell.dismiss_welcome()
	var library: RefCounted = studio.library
	var legacy := {"version": 1, "grid_version": 1, "active_mode": "2d", "documents": {}}
	for mode in ["2d", "3d"]:
		for kind in ["blank", "city", "room"]:
			var data: Dictionary = Templates.make(mode, kind)
			check_world(data, mode + " new " + kind)
		var placed: Dictionary = Templates.make(mode, "blank")
		decorate(placed, library, false)
		check(Document.valid(placed, mode, library), mode + " fresh placements pass document validation")
		check_world(placed, mode + " new city with placements")
		check_decorations(placed, mode + " fresh placement")
		var old: Dictionary = Templates.make(mode, "city")
		old.erase("template_revision")
		decorate(old, library, true)
		legacy["documents"][mode] = old
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var path := OUTPUT + "/legacy_format_%d.isocity.json" % OS.get_process_id()
	if check(Store.write_json(path, legacy) and studio.load_project(path), "Studio opens the version-one grid fixture"):
		print("Legacy defaults fixture: ", ProjectSettings.globalize_path(path))
		for mode in ["2d", "3d"]:
			studio.switch_mode(mode)
			for step in range(5): await process_frame
			var loaded: Dictionary = studio.current().data
			check(loaded.get("template_revision") == 2, mode + " legacy city used its normal template upgrade")
			check_world(loaded, mode + " reopened legacy city")
			check_decorations(loaded, mode + " reopened legacy city")
			check(studio.citizen_tools.managers[mode].residents.is_empty()
				and studio.traffic_tools.managers[mode].vehicles.is_empty()
				and studio.worlds[mode].exploration.outpost.job.is_empty(), mode + " starts without new runtime actors or an outpost job")
		check(Store.read_json(path, {}) == JSON.parse_string(JSON.stringify(legacy)),
			"Opening the legacy fixture preserves its saved content")
	studio.free()
	await process_frame
	print("ASSET EXPANSION DEFAULTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
