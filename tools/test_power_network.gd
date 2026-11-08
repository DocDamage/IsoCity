extends "res://tools/test_water_network.gd"

const Battery="2d:Added_rendered_power_plants_battery_storage_2dd8800d"
const Gas="2d:Added_rendered_power_plants_gas_plant_18bbafda"
const Generator="3d:HanX_Construction/Generator"
const Substation="2d:Added_rendered_electrical_substation_electrical_substation_6b41edc6"
const Solar="2d:Added_rendered_power_plants_solar_pv_ef87763b"
const Wind="2d:Added_rendered_power_plants_wind_farm_d9e48f68"
const PropPlan=preload("res://scripts/builder/prop_plan.gd")

func power_edge(id: String,a: String,port_a: String,b: String,port_b: String) -> Dictionary:
	return {"uid":id,"kind":"power","enabled":true,"from":reference(a,port_a),"to":reference(b,port_b)}

func power_fixture(mode: String) -> Dictionary:
	var data: Dictionary=Templates.make(mode,"blank")
	data["title"]="Power Network "+mode
	var pixel: bool=mode=="2d"
	data["objects"]=[
		object(Gas if pixel else Generator,"generator",Vector2(-15,0),mode,.50),
		object(Substation if pixel else "2d:Electrical_Box","relay",Vector2.ZERO,mode,.55),
		object(Battery,"battery",Vector2(0,-14),mode,.55),
		object("2d:House_Blue" if pixel else "3d:HanX_City/Row_Houses_A","home",Vector2(15,0),mode,.65),
		object("2d:Coffee_Shop" if pixel else "3d:HanX_Shop/Shop_Cafe","shop",Vector2(0,15),mode,.6),
		object("2d:Park_Lamp" if pixel else "3d:HanX_Park/Lamp_Park","lamp",Vector2(-12,-14),mode,.75),
		object("2d:EV_Charger" if pixel else "3d:HanX_GasStation/EV_Charger","charger",Vector2(14,12),mode,.75),
		object("2d:Sedan_Blue" if pixel else "3d:HanX_Traffic/Car_Sedan","car",Vector2(24,18),mode,.75)]
	data["objects"][4]["business"]={"kind":"cafe","open_hour":0.0,"close_hour":24.0}
	data["objects"][6]["vehicle_bay"]={"enabled":true,"price":12,"seconds":2}
	data["objects"][7]["vehicle_care"]={"enabled":true,"energy":"charge","capacity":70,"initial":20}
	var room: Dictionary=Templates.make(mode,"blank")
	room["interior_room"]=true
	room["objects"]=[object("2d:Floor_Lamp" if pixel else "3d:HanX_Park/Lamp_Bollard","hall_lamp",Vector2(-2,-4),mode)]
	var upper: Dictionary=Templates.make(mode,"blank")
	upper["interior_room"]=true
	upper["objects"]=[object("2d:Fridge_White" if pixel else "3d:HanX_Shop/Fridge_Drinks","fridge",Vector2(2,-4),mode)]
	room["floors"]=[{"uid":"upper","name":"Upper","height":3,"room":upper}]
	data["objects"][3]["interior"]=room
	return data

func authored_power(mode: String) -> Dictionary:
	var data: Dictionary=power_fixture(mode)
	data["utilities"]={"power":true}
	data["utility_nodes"]=[]
	for item in data["objects"].slice(0,7):
		var role: Dictionary={"uid":"role_"+item["uid"],"object_uid":item["uid"],"kind":"power","enabled":true}
		if item["uid"]=="generator": role["quantity"]=32
		data["utility_nodes"].append(role)
	data["utility_edges"]=power_edges()
	return data

func power_edges() -> Array:
	return [
		power_edge("feed","generator","output","relay","west"),
		power_edge("store","relay","north","battery","south"),
		power_edge("home_run","relay","east","home","input"),
		power_edge("shop_run","relay","south","shop","input"),
		power_edge("lamp_run","battery","west","lamp","input"),
		power_edge("charger_run","battery","east","charger","input")]

func power_graph(data: Dictionary) -> Dictionary:
	return Plan.compile(data,studio.library,"power")

func power_solver(mode: String) -> void:
	var data: Dictionary=authored_power(mode)
	check(Doc.valid(data,mode,studio.library),"Authored electrical city validates "+mode)
	var graph: Dictionary=power_graph(data)
	for link in graph["links"].values():
		check(link["reason"].is_empty(),"Compiled cable "+link["uid"]+" "+mode+" "+link["reason"])
	var charged: Dictionary=Plan.allocate(graph,{})
	check(charged["allocations"]=={"home":6,"shop":4,"charger":8,"lamp":1} and graph["nodes"]["home"]["fixtures"]==3,
		"Every load and both floors are included in one component "+mode+" "+str(charged))
	check(charged["balance"]=={"opening":0,"production":32,"delivered":19,"closing":8,"spill":5} and balance(charged),
		"Input limit and spill conserve energy "+mode)
	var full: Dictionary=Plan.allocate(graph,{"role_battery":48})
	check(full["balance"]=={"opening":48,"production":32,"delivered":19,"closing":48,"spill":13},"Full batteries accept no new energy "+mode)
	data["utility_nodes"][0]["quantity"]=0
	var limited: Dictionary=Plan.allocate(power_graph(data),{"role_battery":30})
	check(limited["allocations"]=={"home":6,"shop":4,"charger":0,"lamp":0} and limited["balance"]["closing"]==20 and balance(limited),
		"Discharge limit applies before priorities and the component stays balanced "+mode)
	var zero: Dictionary=graph.duplicate(true)
	zero["nodes"]["battery"]["capacity"]=0
	check(Plan.allocate(zero,{})["stock"]["role_battery"]==0 and Plan.allocate(zero,{})["balance"]["spill"]==13,
		"A zero-capacity storage device spills all unused production "+mode)
	data["utility_nodes"][0]["quantity"]=8
	var partial: Dictionary=Plan.allocate(power_graph(data),{})
	check(partial["allocations"]=={"home":6,"shop":2,"charger":0,"lamp":0} and balance(partial),"Priority produces a deterministic brownout "+mode)
	data["utility_nodes"].reverse()
	data["utility_edges"].reverse()
	check(Plan.allocate(power_graph(data),{})==partial,"Record ordering cannot change a brownout "+mode)
	data["utility_nodes"].reverse()
	data["utility_nodes"][3]["enabled"]=false
	var switched: Dictionary=Plan.allocate(power_graph(data),{})
	check(switched["allocations"]=={"home":0,"shop":4,"charger":4,"lamp":0},"Switching the household off frees supply for lower priorities "+mode)
	var source: Dictionary=studio.library.assets[data["objects"][0]["asset"]]
	source["unavailable"]=true
	var offline: Dictionary=Plan.allocate(power_graph(data),{})
	source.erase("unavailable")
	check(offline["balance"]["production"]==0 and offline["balance"]["delivered"]==0,"Unavailable generation is safely excluded "+mode)

func renewable_tests() -> void:
	var data: Dictionary=authored_power("2d")
	data["objects"][0]["asset"]=Solar
	data["utility_nodes"][0].erase("quantity")
	var day: Dictionary=power_graph(data)
	data["night"]=true
	check(day["nodes"]["generator"]["production"]==24 and power_graph(data)["nodes"]["generator"]["production"]==0,
		"Solar power follows the existing day and night setting.")
	data["night"]=false
	data["weather"]={"enabled":true,"condition":"rain","intensity":1.0}
	check(power_graph(data)["nodes"]["generator"]["production"]==6,"Rain lowers solar output using authored weather.")
	data["objects"][0]["asset"]=Wind
	data["weather"]={"enabled":true,"condition":"wind","intensity":1.0,"wind":0.0}
	var windy: int=power_graph(data)["nodes"]["generator"]["production"]
	data["weather"]["condition"]="clear"
	check(windy==24 and power_graph(data)["nodes"]["generator"]["production"]==0,"Wind generation follows effective wind strength.")
	for asset in Plan.Profiles.catalog("power")["assets"]:
		check(studio.library.assets.has(asset),"Power profile resolves prepared asset "+asset)

func real_network_crossing() -> void:
	var data: Dictionary=authored_power("2d")
	data["utilities"]["water"]=true
	data["objects"].append_array([object(Well,"well",Vector2(-14,8),"2d",.45),
		object(Tower,"tank",Vector2(14,8),"2d",.45),object(Pipe,"decorative_pipe",Vector2(1,8),"2d",.2)])
	data["utility_nodes"].append_array([node("well"),node("tank"),node("home")])
	data["utility_nodes"][-1]["uid"]="water_home"
	data["utility_edges"].append_array([edge("water_feed","well","outlet","tank","west"),edge("water_home","tank","north","home","inlet")])
	var electricity: Dictionary=power_graph(data)
	var water: Dictionary=Plan.compile(data,studio.library,"water")
	var cable: Array=electricity["links"][[false,"shop_run"]]["positions"]
	var pipe: Array=water["links"][[false,"water_feed"]]["positions"]
	if cable.size()==2 and pipe.size()==2:
		var a:=Vector2(cable[0][0],cable[0][1])
		var b:=Vector2(cable[1][0],cable[1][1])
		var c:=Vector2(pipe[0][0],pipe[0][1])
		var d:=Vector2(pipe[1][0],pipe[1][1])
		check(Geometry2D.segment_intersects_segment(a,b,c,d)!=null,"Real water and power runs cross in the pixel city.")
	else: check(false,"Real power and water runs have two endpoints.")
	check(Doc.valid(data,"2d",studio.library) and not electricity["ports"].has("decorative_pipe") and
		Plan.allocate(electricity,{})["allocations"]["shop"]==4 and Plan.allocate(water,{})["allocations"]["home"]==5,
		"Real crossing networks share the city and home identity while decorative pipes conduct only water.")
	data["utility_edges"].remove_at(3)
	check(Plan.allocate(power_graph(data),{})["allocations"]["shop"]==0 and report(data)["allocations"]["home"]==5,
		"Disconnecting power from the shop leaves the crossing water network supplied.")

func prop_candidate(exploration: Node,uid: String) -> Dictionary:
	var context: Dictionary=PropPlan.context(exploration)
	for item in context["data"]["objects"]:
		if item["uid"]!=uid: continue
		context.merge({"item":item,"node":context["instances"].get(uid),"profile":PropPlan.profile(item)})
		return context
	return {}

func device_effects(mode: String,doc: RefCounted,ui: RefCounted) -> void:
	var world: Node=studio.worlds[mode]
	var walk: Node=world.exploration
	var runtime: Node=ui.manager()
	var source: Dictionary=doc.data.duplicate(true)
	var outage: Dictionary=source.duplicate(true)
	outage["utility_edges"].pop_front()
	runtime.reset_preview()
	studio.set_walking(true)
	await settle()
	var lamp: Dictionary=prop_candidate(walk,"lamp")
	check(not lamp.is_empty(),"The exterior lamp has a real interactive placement "+mode)
	if not lamp.is_empty():
		var lamp_approach: Variant=PropPlan.ground_point(lamp,walk,"approach")
		walk.player.teleport_to(walk.player.get_parent().to_local(lamp_approach))
		var key: String=walk.props.key_for(lamp)
		check(walk.props.interact(lamp) and walk.props.power_state(lamp) and light_visible(walk.props,key),
			"Reviewed lamp switches on its light when supplied "+mode)
		runtime.configure(outage,studio.library)
		walk.props.sync_effects()
		check(not light_visible(walk.props,key) and walk.props.prompt(lamp).contains("Electricity unavailable"),
			"Lamp loses its visible light with a cable outage "+mode)
		runtime.configure(source,studio.library)
		walk.props.sync_effects()
		check(walk.props.power_state(lamp) and light_visible(walk.props,key),"A requested lamp relights after reconnect "+mode)
		check(walk.props.interact(lamp) and not light_visible(walk.props,key),"Manual switch keeps the lamp dark while supplied "+mode)
	var business: Node=studio.business_tools.managers[mode]
	check(business.service.request("shop","power_probe","coffee",12)["ok"],"Supplied business admits a visit "+mode)
	var care=walk.driving.care
	var bay: Dictionary=care.bays.get("charger",{})
	check(not bay.is_empty() and care.vehicles.has("car"),"Prepared charge station and vehicle are usable "+mode)
	var pose: Dictionary={}
	if not bay.is_empty():
		pose={"point":bay["center"],"heading":bay["axis"],"extent":Vector2(.6,1),"speed":0.0}
		check(care.request("car","charger",pose)["ok"],"Supplied charger starts a session "+mode)
	runtime.configure(outage,studio.library)
	business.service.step(.25,12)
	check(business.service.result("power_probe").get("state")=="cancelled" and not business.service.inventory.has("power_probe"),
		"Business outage cancels active service without granting an item "+mode)
	check(business.service.request("shop","second_probe","coffee",12).get("reason","").contains("Electricity unavailable"),
		"Business outage blocks new service "+mode)
	if not pose.is_empty():
		care.step(.25,func(_uid: String)->Dictionary:return pose)
		check(not care.jobs.has("car") and care.receipts.is_empty() and care.state("car")["energy"]==20,
			"Charger outage cancels the job before settlement "+mode)
		check(care.request("car","charger",pose).get("reason","").contains("Electricity unavailable"),"Charger explains the shortage "+mode)
	runtime.configure(source,studio.library)
	check(business.service.request("shop","second_probe","coffee",12)["ok"],"Business reopens when power returns "+mode)
	if not pose.is_empty():
		check(care.request("car","charger",pose)["ok"],"Restored power admits a new charging session "+mode)
		for step in 8: care.step(.25,func(_uid: String)->Dictionary:return pose)
		check(care.receipts.size()==1 and care.state("car")["energy"]==70,"Charging recovers and completes exactly once "+mode)
	walk.nearby={"item":doc.object("home"),"entry":{"uid":"","floor":"upper"}}
	walk.enter_interior()
	await settle()
	check(walk.interior!=null and walk.active_floor()=="upper","The ordinary room loader can enter the supplied upper floor "+mode)
	if walk.interior and walk.active_floor()=="upper":
		var fridge: Dictionary=prop_candidate(walk,"fridge")
		check(not fridge.is_empty() and walk.props.power_reason(fridge).is_empty(),"Upper-floor appliance receives building service "+mode)
		if not fridge.is_empty():
			runtime.configure(outage,studio.library)
			check(not walk.props.interact(fridge) and walk.props.notice.contains("Electricity unavailable"),"Disconnected building blocks an appliance on the upper floor "+mode)
			runtime.configure(source,studio.library)
			var at: Variant=PropPlan.ground_point(fridge,walk,"approach")
			walk.player.teleport_to(walk.player.get_parent().to_local(at))
			check(walk.props.interact(fridge),"Appliance starts its ordinary cycle after reconnection "+mode)
			if not walk.props.active.is_empty():
				var state: Dictionary=walk.props.state_for(fridge)
				runtime.configure(outage,studio.library)
				var remaining: float=state["remaining"]
				walk.props._physics_process(.2)
				check(state["remaining"]==remaining,"Outage pauses a running appliance without a completion "+mode)
				runtime.configure(source,studio.library)
				walk.props._physics_process(.2)
				check(state["remaining"]<remaining,"Appliance cycle resumes after power returns "+mode)
		walk.leave_interior()
	studio.set_walking(false)

func light_visible(props: Node,key: String) -> bool:
	var light: Node=props.effects.entries.get(key,{}).get("light")
	return is_instance_valid(light) and light.visible

func power_workflow(mode: String) -> void:
	studio.switch_mode(mode)
	var doc: RefCounted=studio.current()
	doc.data=power_fixture(mode)
	studio.economy_tools.pauses[mode]=true
	doc.data["economy"]={"enabled":true,"starting_cash":1000000,"period_seconds":60}
	doc.data["economy_account"]=Economy.fresh_account(doc.data,studio.library)
	var account: Dictionary=doc.data["economy_account"].duplicate(true)
	doc.undo_history.clear()
	studio.changed()
	await settle()
	studio._command("power",null)
	var ui: RefCounted=studio.power_tools
	check(ui.panel.is_visible_in_tree() and not ui.manager().graph["enabled"],"Power is disabled in the normal panel by default "+mode)
	for uid in ["generator","relay","battery","home","shop","lamp","charger"]:
		studio.selected_uid=uid
		studio.selected_uids.assign([uid])
		ui.refresh()
		if uid=="generator": ui.quantity.value=32
		check(not ui.apply_facility_button.disabled,"Editor enables reviewed role "+uid+" "+mode)
		ui.apply_facility_button.pressed.emit()
	ui.enabled.button_pressed=true
	ui.apply_enabled.pressed.emit()
	for wire in power_edges():
		check(add_run(ui,wire["from"],wire["to"]),"Authored cable uses the previewed ports "+wire["uid"]+" "+mode)
	var runtime: Node=ui.manager()
	runtime.reset_preview()
	check(runtime.served("home")==6 and runtime.served("charger")==8 and doc.data["economy_account"]==account,
		"Authored supply is live and leaves authored treasury unchanged "+mode)
	var source: Dictionary=doc.data.duplicate(true)
	studio.selected_uid="charger"
	studio.selected_uids.assign(["charger"])
	ui.refresh()
	ui.facility_enabled.button_pressed=false
	ui.apply_facility_button.pressed.emit()
	check(runtime.served("charger")==0 and runtime.served("home")==6 and runtime.describe("charger").contains("disabled"),
		"Switching off a consumer in the ordinary panel removes its demand "+mode)
	studio._command("undo",null)
	ui.tick(0)
	check(doc.data==source and runtime.served("charger")==8,"Undo restores the consumer switch and exact record "+mode)
	var charger_run: Dictionary=source["utility_edges"][-1]
	check(choose(ui.links,[false,charger_run["uid"]]),"Select the exact charger cable "+mode)
	ui.remove_link_button.pressed.emit()
	check(runtime.describe("charger").contains("Outage") and runtime.served("charger")==0,"Cable removal produces an immediate outage "+mode)
	studio.simulation_diagnostic_tools.choose("power")
	studio.simulation_diagnostic_tools.tick(.3)
	check(studio.simulation_diagnostic_tools.snapshot.get("rows",[]).any(func(row: Dictionary)->bool:
		return row["object_uid"]=="charger" and row["severity"]=="error"),"Overlay points out the affected charger "+mode)
	studio._command("undo",null)
	ui.tick(0)
	check(doc.data==source and runtime.served("charger")==8,"Undo restores the cable and the exact project "+mode)
	await device_effects(mode,doc,ui)
	await capture(mode,ui,"power")
	var path: String=output+"/power_"+mode+".isocity.json"
	check(studio.write_project(path,false) and studio.load_project(path),"Normal save and reopen preserve the electric layout "+mode)
	ui.tick(0)
	check(studio.current().data.get("utility_edges")==source["utility_edges"] and ui.manager().stored()==0 and ui.manager().served("home")==6,
		"Save preserves cables and demand while reopening with clean private stock "+mode)
	if "--portable" in OS.get_cmdline_user_args():
		var result: Dictionary=Export.new().save(studio.worlds[mode],source,studio.library,output+"/power_"+mode+".zip")
		check(result.get("ok",false),"Portable power package "+mode+" "+result.get("message",""))

func run() -> void:
	output=OS.get_environment("ISOCITY_POWER_OUTPUT")
	if output.is_empty(): output="res://output/verification/asset_expansion/N05"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	studio=load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled=false
	root.add_child(studio)
	await settle()
	if studio.consumer_shell: studio.consumer_shell.dismiss_welcome()
	renewable_tests()
	real_network_crossing()
	for mode in ["2d","3d"]:
		power_solver(mode)
		await power_workflow(mode)
	studio.free()
	await settle()
	print("POWER NETWORK: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
