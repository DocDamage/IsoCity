extends SceneTree
const OUT="res://output/verification/asset_expansion/U05"
const Capabilities=preload("res://scripts/builder/asset_capabilities.gd")
const Defaults=preload("res://scripts/builder/catalog_defaults.gd")
const Document=preload("res://scripts/builder/document.gd")
const Templates=preload("res://scripts/builder/templates.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;print("FAIL: "+message)
func _initialize() -> void:call_deferred("run")
func settle() -> void:
	for frame in 12:await process_frame
	await physics_frame
func badge(report: Dictionary,key: String) -> Dictionary:
	for entry in report["badges"]:
		if entry["label"]==key:return entry
	return {}
func run() -> void:
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new()
	var capabilities: RefCounted=library.capabilities
	check(capabilities.defaults.size()==6555,"Every catalog identity has a bounded potential index")
	for id in library.assets:
		var item: Dictionary={"asset":id,"uid":"test"};Defaults.stamp(item)
		var expected: Array=[]
		var behavior: Dictionary=library.assets[id]["behavior"]
		if behavior.get("building",false):expected.append("Enter")
		if not preload("res://scripts/builder/driving_plan.gd").profile(item).is_empty():expected.append("Drive")
		if behavior.get("door",false) or not preload("res://scripts/builder/prop_plan.gd").profile(item).is_empty():expected.append("Use")
		if not preload("res://scripts/builder/citizen_plan.gd").role(item).is_empty():expected.append("Citizens")
		if preload("res://scripts/builder/business_plan.gd").profile(item)["kind"]!="none":expected.append("Business")
		if preload("res://scripts/builder/service_plan.gd").profile(item)["kind"]!="none":expected.append("Services")
		check(capabilities.potential(id)==expected,"Potential agrees with actual runtime profiles: "+id)
	var reviewed: String="3d:HanX_Shop/Shop_Cafe"
	var doc: RefCounted=Document.new();doc.data=Templates.make("2d","blank")
	var item: Dictionary=doc.add(reviewed,[0,0,0],"0")
	var before: Dictionary=doc.data.duplicate(true)
	var history: int=doc.undo_history.size()
	check(capabilities.potential(reviewed).has("Business") and badge(capabilities.selected(item,library,doc.data),"Business")["state"]=="Supported","New reviewed business has potential; access is not assumed ready")
	item["business"]={"kind":"none"}
	var report: Dictionary=capabilities.selected(item,library,doc.data)
	check(badge(report,"Business").is_empty() and report["potential"].has("Business") and report["inactive"].has("Business"),"Disabled business loses its current badge and keeps its potential")
	item.erase("business");item.erase(Defaults.FIELD)
	check(badge(capabilities.selected(item,library,doc.data),"Business").is_empty() and not item.has(Defaults.FIELD),"Describing old placements never upgrades saved behavior")
	item={"asset":"2d:U05_Animated_Drive_Shop_Character","uid":"custom","position":[0,0,0],"direction":"SE","scale":1}
	library.assets[item["asset"]]={"id":item["asset"],"mode":"2d","path":library.assets["2d:Coffee_Shop"]["path"],"name":"Drive animated shop","category":"Custom","data":{},"behavior":{}}
	library.rebuild_indexes()
	check(capabilities.potential(item["asset"]).is_empty(),"Art names and animated labels never confer capabilities")
	item["prop"]={"kind":"appliance"}
	check(Capabilities.profiles(item,library)==["Use"],"A generic object gains Use through an explicit valid interaction")
	item["prop"]={"kind":"appliance","enabled":false}
	check(Capabilities.profiles(item,library).is_empty(),"Disabled custom interaction removes its badge")
	item["prop"]={"kind":"not-supported"}
	check(Capabilities.profiles(item,library).is_empty(),"Malformed interaction does not advertise Use")
	library.assets[item["asset"]]["path"]="res://missing_u05_runtime.tscn";item["prop"]={"kind":"appliance"}
	report=capabilities.selected(item,library,doc.data)
	check(badge(report,"Use")["state"]=="Unavailable" and report["unavailable"].contains("runtime dependency"),"Missing prepared dependency has an explanatory unavailable state")
	check(capabilities.describe(item["asset"],library).contains("Unavailable:"),"Library tooltip explains missing runtime dependencies")
	library.assets[item["asset"]]["path"]=library.assets["2d:Coffee_Shop"]["path"]
	library.assets[item["asset"]]["data"]={"source_path":"missing-original.blend","preview_path":"res://missing-source.gif"}
	check(Capabilities.dependency_reason(item,library).is_empty(),"Absent raw sources and optional previews do not invalidate a working prepared scene")
	library.assets.erase(item["asset"]);library.rebuild_indexes()
	check(not capabilities.defaults.has(item["asset"]),"Removing a custom import refreshes the capability index")
	doc.data=before;history=doc.undo_history.size()
	for count in 20:capabilities.selection_text(doc.data["objects"][0],library,doc.data)
	check(doc.data==before and doc.undo_history.size()==history,"Repeated inspection leaves authored data and Undo history unchanged")
	check(not Capabilities.Citizens.settings(doc.data)["enabled"] and not Capabilities.Services.settings(doc.data)["enabled"] and not preload("res://scripts/builder/economy_plan.gd").settings(doc.data)["enabled"],"Badges retain disabled simulation defaults")
	await workflow(reviewed)
	print("ASSET CAPABILITIES: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

func workflow(reviewed: String) -> void:
	var store=preload("res://scripts/builder/project_store.gd");store.storage_root=OUT+"/history";store.legacy_autosave=OUT+"/legacy.json"
	var studio: Control=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio)
	while not studio.enhancements_ready:await process_frame
	var ui: RefCounted=studio.consumer_shell
	check(ui!=null,"Both browsing interfaces participate")
	if not ui:studio.free();return
	ui.dismiss_welcome()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode);var doc: RefCounted=studio.current();doc.data=Templates.make(mode,"blank")
		var item: Dictionary=doc.add(reviewed,[0,0,0],"0");var uid: String=item["uid"]
		studio.changed();await settle();studio.selected_uids.assign([uid]);studio.selected_uid=uid;studio.refresh_controls();await settle()
		var manager: Node=studio.business_tools.managers[mode];manager.hour=12;manager.set_physics_process(false)
		studio.refresh_capabilities()
		check(studio.capability_note.text.contains("Business · Supported") and studio.capability_note.text.contains("Open. Walk"),"Selection distinguishes supported from player access: "+mode)
		studio.set_walking(true);var world: Node=studio.worlds[mode];world.player.set_physics_process(false);world.player.teleport_to(world.exploration.entrance(world.instances[uid]))
		studio.refresh_capabilities()
		check(studio.capability_note.text.contains("Business · Ready now") and studio.capability_note.text.contains("Enter · Supported"),"Actual open business is ready at approach; untested interior landing stays supported: "+mode)
		manager.hour=2;studio.refresh_capabilities();check(studio.capability_note.text.contains("Closed at the current city time") and not studio.capability_note.text.contains("Business · Ready now"),"Closing hours remove readiness: "+mode)
		manager.hour=12
		for n in Capabilities.Business.profile(item)["capacity"]:manager.service.visits[str(n)]={"business":uid,"state":"active"}
		studio.refresh_capabilities();check(studio.capability_note.text.contains("all service places are occupied"),"Capacity removes current readiness: "+mode)
		manager.service.visits.clear();studio.set_walking(false)
		doc.checkpoint();item["business"]={"kind":"none"};studio.changed();studio.refresh_controls()
		check(not studio.capability_note.text.contains("Business · Supported") and studio.capability_note.text.contains("Inactive on this object: Citizens · Business") and studio.capability_note.text.contains("Default potential: Enter · Citizens · Business"),"Inspector removes disabled capabilities while retaining their catalog potential: "+mode)
		check(doc.undo(),"Business override remains undoable: "+mode);studio.changed();studio.refresh_controls()
		check(studio.capability_note.text.contains("Business · Supported"),"Undo restores current capability: "+mode)
		check(doc.redo(),"Business override remains redoable: "+mode);studio.changed();studio.refresh_controls()
		check(not studio.capability_note.text.contains("Business · Supported"),"Redo disables current capability: "+mode)
		doc.undo();studio.changed();await settle()
		for index in 3:
			var asset: String=["2d:Park_Bench","2d:Hatchback_Yellow","2d:Police"][index]
			doc.add(asset,[(index+1)*200,0,0] if mode=="2d" else [(index+1)*12,0,0],"SE")
		studio.changed();await settle()
		studio.selected_uids.assign([uid,doc.data["objects"][1]["uid"]]);studio.refresh_controls()
		check(studio.capability_note.text.contains("Mixed selection"),"Multiple objects never inherit the first object's readiness: "+mode)
		studio.selected_uids.assign([uid]);studio.selected_uid=uid;studio.refresh_controls()
		var authored: Dictionary=doc.data.duplicate(true);var undo: int=doc.undo_history.size();var runtime_before: int=hash([manager.service.visits,manager.service.queues,manager.service.inventory,world.exploration.nearby])
		for n in 10:studio.refresh_capabilities()
		check(doc.data==authored and doc.undo_history.size()==undo and hash([manager.service.visits,manager.service.queues,manager.service.inventory,world.exploration.nearby])==runtime_before,"Inspection is read-only for city, history, economy and interaction/visit session: "+mode)
		var path: String=OUT+"/capabilities_"+mode+".isocity.json"
		var wrote: bool=studio.write_project(path);var loaded: bool=studio.load_project(path) if wrote else false
		check(wrote and loaded and studio.current().data["objects"]==JSON.parse_string(JSON.stringify(authored["objects"])) and studio.repair_report.get("issues",[]).is_empty(),"Capabilities preserve exact IDs, transforms and overrides on save/reopen without repair: "+mode)
		var result: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],studio.current().data,studio.library,OUT+"/capabilities_"+mode+".zip")
		check(result["ok"],"Allowed capability-bearing object exports: "+mode+" "+result.get("message",""))
	await availability(studio)
	studio.switch_mode("2d");ui.set_active(true,false);ui.open_drawer("build");studio.asset_browser.clear_all_filters();ui.query.text="coffee";ui.refresh_catalog();await settle()
	for size in [Vector2i(1480,900),Vector2i(960,640)]:
		root.size=size;studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true});ui.layout();await settle()
		check(studio.cards.get_child_count()>0,"Capability search renders cards: "+str(size))
		for card in studio.cards.get_children():
			check(card.capability_note.mouse_filter==Control.MOUSE_FILTER_IGNORE and card.tooltip_text.contains("Default potential:"),"Badge decoration preserves card input and full keyboard tooltip")
			check(not card.capability_note.get_rect().intersects(card.caption.get_rect()) and card.get_rect().size.y>=card.capability_note.get_rect().end.y,"Compact card capability line is separate and contained at enlarged text")
			break
	studio.free();await process_frame;await process_frame

func availability(studio: Control) -> void:
	studio.switch_mode("2d");var doc: RefCounted=studio.current();doc.data=Templates.make("2d","blank")
	var services=Capabilities.Services;var traffic=services.Traffic
	doc.data["services"]={"enabled":true,"automatic":false};doc.data["roads"]=[]
	for x in 7:doc.data["roads"].append({"cell":[x,0]})
	var center: Vector2=traffic.center(Vector2i.ZERO,"2d")
	var station: Dictionary=doc.add("2d:Fire_Station1_-_Copie",traffic.world(center+Vector2(0,-6),"2d"),"SE")
	station["city_service"]={"kind":"fire","radius":96,"units":1}
	var house: Dictionary=doc.add("2d:House_Blue",traffic.world(center+Vector2(48,6),"2d"),"SE")
	studio.changed();await settle()
	var runtime: Node=studio.service_tools.managers["2d"];runtime.set_physics_process(false);runtime.active=true;runtime.paused=false
	runtime.dispatch.plan=services.build(doc.data,studio.library)
	var caps: RefCounted=studio.library.capabilities;var runtimes: Dictionary={"Services":runtime}
	var report: Dictionary=caps.selected(station,studio.library,doc.data,studio.worlds["2d"],runtimes)
	check(badge(report,"Services")["state"]=="Supported" and badge(report,"Services")["reason"].contains("No eligible target route"),"A station beside a road is not ready until a target route is verified")
	check(services.choose(runtime.dispatch.plan,"fire",house["uid"])["ok"],"Dispatch verifies an actual road route in the fixture")
	var plan_before: int=hash(runtime.dispatch.plan)
	report=caps.selected(station,studio.library,doc.data,studio.worlds["2d"],runtimes)
	check(badge(report,"Services")["state"]=="Ready now" and hash(runtime.dispatch.plan)==plan_before,"A verified target route and free unit produce readiness without route work or dispatch mutation")
	runtime.dispatch.units["busy"]=station["uid"]
	report=caps.selected(station,studio.library,doc.data,studio.worlds["2d"],runtimes)
	check(badge(report,"Services")["state"]=="Supported" and badge(report,"Services")["reason"].contains("busy"),"Busy station crews remove service readiness")
	runtime.dispatch.units.clear();runtime.paused=true
	check(badge(caps.selected(station,studio.library,doc.data,studio.worlds["2d"],runtimes),"Services")["state"]=="Supported","Pausing services removes readiness without removing potential")
	station["visible"]=false
	check(badge(caps.selected(station,studio.library,doc.data,studio.worlds["2d"],runtimes),"Services")["reason"].contains("hidden"),"Hidden object cannot be advertised ready")
	station["visible"]=true;doc.data["services"]["enabled"]=false;studio.changed();await settle()
	var home: Dictionary=doc.add("2d:Park_Bench",[-800,-500,0],"SE");home["citizen_role"]="home"
	var work: Dictionary=doc.add("2d:Park_Bench",[-500,-500,0],"SE");work["citizen_role"]="work"
	doc.data["citizens"]={"enabled":true,"population":1,"start_hour":9,"day_length":3600};studio.changed();await settle()
	var citizens: Node=studio.citizen_tools.managers["2d"];citizens.set_physics_process(false);citizens.hour=9;citizens.step(.01)
	var citizen_before: int=hash([citizens.route_cache,citizens.route_attempts,citizens.plan,doc.data])
	report=caps.selected(work,studio.library,doc.data,studio.worlds["2d"],{"Citizens":citizens})
	check(badge(report,"Citizens")["state"]=="Ready now" and hash([citizens.route_cache,citizens.route_attempts,citizens.plan,doc.data])==citizen_before,"A live citizen's verified route yields readiness without building another path")
	citizens.paused=true
	check(badge(caps.selected(work,studio.library,doc.data,studio.worlds["2d"],{"Citizens":citizens}),"Citizens")["state"]=="Supported","Paused citizen preview removes readiness")
	doc.data["citizens"]["enabled"]=false;studio.changed();await settle()
	var car: Dictionary=doc.add("2d:Hatchback_Yellow",[800,500,0],"SE");studio.changed();await settle()
	studio.selected_uids.assign([car["uid"]]);studio.selected_uid=car["uid"];studio.refresh_controls();studio.driving_tools.preview_selected();await settle();studio.refresh_capabilities()
	check(studio.capability_note.text.contains("Drive · Ready now"),"A vehicle already entered through the driving surface checks has verified readiness")
	studio.set_walking(false);studio.refresh_capabilities()
	check(studio.capability_note.text.contains("Drive · Supported") and not studio.capability_note.text.contains("Drive · Ready now"),"Parked vehicle retains support without assuming its current approach is clear")
	var item: Dictionary=doc.add("2d:Park_Bench",[-500,500,0],"SE");item["prop"]={"kind":"appliance"};studio.changed();await settle()
	studio.selected_uids.assign([item["uid"]]);studio.selected_uid=item["uid"];studio.refresh_controls();studio.prop_tools.preview_selected();await settle()
	var world: Node=studio.worlds["2d"];world.player.set_physics_process(false)
	var before: int=hash([world.exploration.nearby,world.exploration.props.states,doc.data]);studio.refresh_capabilities()
	check(studio.capability_note.text.contains("Use · Ready now") and hash([world.exploration.nearby,world.exploration.props.states,doc.data])==before,"Actual clear prop approach yields readiness without changing candidates, power or saved records")
	world.player.position+=Vector2(1000,1000);studio.refresh_capabilities()
	check(studio.capability_note.text.contains("Use · Supported") and not studio.capability_note.text.contains("Use · Ready now"),"Moving out of reach removes prop readiness")
	studio.set_walking(false)
