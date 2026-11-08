extends SceneTree

const Plan=preload("res://scripts/builder/utility_plan.gd")
const Runtime=preload("res://scripts/builder/utility_runtime.gd")
const Doc=preload("res://scripts/builder/document.gd")
const Templates=preload("res://scripts/builder/templates.gd")
const Protection=preload("res://scripts/builder/cooperative_plan.gd")
const Export=preload("res://scripts/builder/portable_export.gd")
const Economy=preload("res://scripts/builder/economy_plan.gd")
const Repair=preload("res://scripts/builder/project_repair.gd")
const Well="2d:Added_Well_Well_Wall_03fb84ee"
const Tower="2d:Supplemental_Water_towers_toroidal_tank_16bit_flat_a1734b2d"
const Tower_Dither="2d:Supplemental_Water_towers_toroidal_tank_16bit_dither_flat_ae5f51aa"
const Roof="3d:HanX_City/Roof_Water_Tank"
const Pump="3d:Fire_Station_PSX/portable_water_pump"
const Pipe="2d:Added_rendered_modular_pipeline_pack_modular_pipeline_pack_01_666e79e8"

var studio: Control
var checks: int=0
var failures: int=0
var output: String

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL: "+message)

func settle() -> void:
	for frame in 8: await process_frame

func object(asset: String,uid: String,point: Vector2,mode: String,scale: float=1.0) -> Dictionary:
	var directions: Array=studio.library.directions(asset)
	var heading: String="SE" if "SE" in directions else str(directions.front()) if not directions.is_empty() else "0"
	return {"asset":asset,"uid":uid,"name":uid.capitalize(),"position":Plan.Profiles.Traffic.world(point,mode),
		"scale":scale,"direction":heading}

func reference(uid: String,socket: String) -> Dictionary:
	return {"object_uid":uid,"socket":socket}

func edge(id: String,a: String,port_a: String,b: String,port_b: String) -> Dictionary:
	return {"uid":id,"kind":"water","enabled":true,"from":reference(a,port_a),"to":reference(b,port_b)}

func node(uid: String) -> Dictionary:
	return {"uid":"role_"+uid,"object_uid":uid,"kind":"water","enabled":true}

func fixture(mode: String) -> Dictionary:
	var data: Dictionary=Templates.make(mode,"blank")
	data["title"]="Water Network "+mode
	data["objects"]=[
		object(Well,"well",Vector2(-14,0),mode,.6),
		object(Tower if mode=="2d" else Roof,"tank",Vector2.ZERO,mode,.6),
		object("2d:House_Blue" if mode=="2d" else "3d:HanX_City/Row_Houses_A","home",Vector2(14,0),mode,.6),
		object("2d:Coffee_Shop" if mode=="2d" else "3d:HanX_Shop/Shop_Cafe","shop",Vector2(0,14),mode,.6)]
	data["objects"][2]["interior"]=Templates.make(mode,"blank")
	data["objects"][2]["interior"]["interior_room"]=true
	return data

func authored(mode: String) -> Dictionary:
	var data: Dictionary=fixture(mode)
	data["utilities"]={"water":true}
	data["utility_nodes"]=[node("well"),node("tank"),node("home"),node("shop")]
	data["utility_edges"]=[edge("feed","well","outlet","tank","west"),edge("home_run","tank","east","home","inlet"),edge("shop_run","tank","south","shop","inlet")]
	return data

func report(data: Dictionary,stock: Dictionary={}) -> Dictionary:
	return Plan.allocate(Plan.compile(data,studio.library,"water"),stock)

func balance(result: Dictionary) -> bool:
	var b: Dictionary=result["balance"]
	return b["opening"]+b["production"]==b["delivered"]+b["closing"]+b["spill"]

func solver(mode: String) -> void:
	var library: RefCounted=studio.library
	var data: Dictionary=authored(mode)
	check(Doc.valid(data,mode,library),"Reviewed roles and optional document schema validate in "+mode)
	var graph: Dictionary=Plan.compile(data,library,"water")
	for link in graph["links"].values():
		check(link["reason"].is_empty(),"Valid service run "+link["uid"]+" "+mode+" "+link["reason"])
	var first: Dictionary=report(data)
	check(first["allocations"]=={"home":5,"shop":4} and first["balance"]["closing"]==1 and balance(first),"Initial delivery and surplus stock "+mode+" "+str(first))
	var capacity: int=graph["nodes"].get("tank",{}).get("capacity",-1)
	var full: Dictionary=report(data,{"role_tank":capacity})
	check(full["balance"]["spill"]==1 and full["balance"]["closing"]==capacity and balance(full),"Full tank spills only surplus "+mode)
	data["utility_edges"].pop_front()
	var reserve: Dictionary=report(data,{"role_tank":6})
	check(reserve["allocations"]=={"home":5,"shop":1} and reserve["balance"]["closing"]==0 and reserve["balance"]["spill"]==10 and balance(reserve),"Isolated well and stored supply with deterministic shortage "+mode)
	check(report(data)["allocations"]=={"home":0,"shop":0},"Empty isolated tank leaves outage "+mode)
	data["utility_edges"].push_front(edge("feed","well","outlet","tank","west"))
	data["utility_nodes"][0]["quantity"]=6
	for config in data["utility_nodes"]:
		if config["object_uid"] in ["home","shop"]: config["priority"]=50
	var tie: Dictionary=report(data)
	data["utility_nodes"].reverse()
	data["utility_edges"].reverse()
	check(tie==report(data) and tie["allocations"]=={"home":5,"shop":1},"UID resolves equal priorities independent of record order "+mode)
	data["utilities"]["water"]=false
	var off: Dictionary=report(data,{"role_tank":7})
	check(off["balance"]=={"opening":7,"production":0,"delivered":0,"closing":7,"spill":0},"Disabled water preserves existing stock "+mode)
	data["utilities"]["water"]=true
	data["utility_nodes"][0]["quantity"]=-1
	check(not Doc.valid(data,mode,library),"Negative quantities rejected "+mode)
	data=authored(mode)
	data["utility_edges"][0]["capacity"]=20
	check(not Doc.valid(data,mode,library),"Unsupported edge capacity rejected "+mode)
	var room: Dictionary=data["objects"][2]["interior"]
	room["utilities"]={"water":true}
	var documents: Dictionary={"2d":Templates.make("2d","blank"),"3d":Templates.make("3d","blank")}
	documents[mode]=data
	var fixed: Dictionary=Repair.new(library).session({"version":1,"grid_version":2,"active_mode":mode,"documents":documents})
	check(fixed.get("ok",false) and fixed["changed"] and fixed["content"]["documents"][mode]["utility_edges"].size()==2
		and not fixed["content"]["documents"][mode]["objects"][2]["interior"].has("utilities"),
		"Repair archives invalid runs and interior settings while preserving valid records "+mode)
	data=authored(mode)
	data["objects"].append(object(Well,"second_well",Vector2(-7,-13),mode,.5))
	data["utility_nodes"].append(node("second_well"))
	data["utility_edges"].append(edge("ring","second_well","outlet","tank","north"))
	# The second tank closes the loop without pairing two outlets.
	data["objects"].append(object(Roof if mode=="3d" else Tower_Dither,"loop_tank",Vector2(-20,-12),mode,.5))
	data["utility_nodes"].append(node("loop_tank"))
	data["utility_edges"].append(edge("loop_well","well","outlet_west","loop_tank","south"))
	data["utility_edges"].append(edge("loop_second","second_well","outlet_west","loop_tank","east"))
	var cycle: Dictionary=report(data)
	check(cycle["balance"]["production"]==20 and cycle["balance"]["delivered"]==9 and balance(cycle),"Loop with two sources counts both exactly once "+mode)
	var loop_graph: Dictionary=Plan.compile(data,library,"water")
	check(loop_graph["components"].size()==1 and loop_graph["links"].values().all(func(link: Dictionary)->bool:return link["reason"].is_empty()),"Every edge in the cycle is active "+mode)
	if mode=="2d":
		check(capacity==64 and loop_graph["nodes"]["loop_tank"]["capacity"]==capacity,"Two palettes share the reviewed family capacity")
	var runtime:=Runtime.new()
	runtime.configure(data,library)
	for tick in 8: runtime.step(.25)
	var tank_stock: int=runtime.stored()
	check(runtime.tick_count==1 and tank_stock==11,"Two-second runtime tick commits private stock "+mode)
	data["objects"].pop_back()
	Plan.normalize(data,library)
	runtime.configure(data,library)
	check(not data["utility_nodes"].any(func(n: Dictionary)->bool:return n["object_uid"]=="loop_tank") and balance(runtime.report),"Removal prunes authored references and recompiles "+mode)
	var access: Dictionary=authored(mode)
	access["terrain"]={"enabled":true}
	var point: Vector2=graph["ports"]["home"]["inlet"]["point"]
	var cell:=Vector2i((point/Plan.Profiles.Terrain.CELL_SIZE).floor())
	access["water_cells"]=[{"cell":[cell.x,cell.y],"level":2}]
	check(report(access)["allocations"]["home"]==0 and not Plan.compile(access,library,"water")["nodes"]["home"]["reason"].is_empty(),"Flooded consumer port interrupts service "+mode)
	data=authored(mode)
	data["objects"].pop_front()
	Plan.normalize(data,library)
	check(report(data)["balance"]["production"]==0 and report(data)["allocations"]["home"]==0 and data["utility_edges"].size()==2,
		"Removing the source prunes its run and stops delivery without reserve "+mode)
	if mode=="2d": physical_joints()
	else: pump_access()
	runtime.free()

func physical_joints() -> void:
	var connector=Plan.Connector
	var data: Dictionary=authored("2d")
	var left: Dictionary=object(Pipe,"left_pipe",Vector2(-8,0),"2d",.2)
	var right: Dictionary=object(Pipe,"right_pipe",Vector2.ZERO,"2d",.2)
	var target: Array=connector.frames(left,"2d")
	var source: Array=connector.frames(right,"2d")
	var solution: Dictionary=connector.solve(right,source[0],target[1],"2d",data,{})
	check(solution["ok"],"Measured pipe sections align at their flanges.")
	if not solution["ok"]: return
	right=solution["pose"]
	data["objects"].append_array([left,right])
	data["connections"]=[{"uid":"snap_joint","kind":"water","from":reference("left_pipe",target[1]["socket"]),"to":reference("right_pipe",source[0]["socket"])}]
	data["utility_edges"].pop_front()
	data["utility_edges"].append_array([edge("well_to_pipe","well","outlet","left_pipe",target[0]["socket"]),
		edge("pipe_to_tank","right_pipe",source[1]["socket"],"tank","west")])
	check(Doc.valid(data,"2d",studio.library) and report(data)["allocations"]["home"]==5,
		"Existing I08 socket record carries service through connected pipe sections.")
	data["connections"].clear()
	check(report(data)["allocations"]["home"]==0,"Visually touching pipe art does not carry service after its saved joint is removed.")

func pump_access() -> void:
	var data: Dictionary=authored("3d")
	var pump: Dictionary=object(Pump,"well",Vector2(-14,0),"3d",.6)
	data["objects"][0]=pump
	data["terrain"]={"enabled":true}
	check(report(data)["balance"]["production"]==0,"The reviewed pump produces nothing at a dry intake.")
	var bounds: Rect2=Plan.Profiles.footprint(pump,studio.library,"3d")
	var intake: Vector2=Plan.Profiles.side_point(bounds,"north",2.0)
	var cell:=Vector2i((intake/Plan.Profiles.Terrain.CELL_SIZE).floor())
	data["water_cells"]=[{"cell":[cell.x,cell.y],"level":1}]
	check(Doc.valid(data,"3d",studio.library) and report(data)["balance"]["production"]==16 and report(data)["allocations"]["home"]==5,
		"The pump feeds the network with a wet intake and dry service ports.")

func crossed_kinds() -> void:
	var data: Dictionary=authored("3d")
	var generator_asset: String="3d:HanX_City/Row_Houses_A"
	var load_asset: String="3d:HanX_Shop/Shop_Cafe"
	# Temporary profiles exercise the shared graph before production power art is reviewed.
	var original: Dictionary=Plan.Profiles.catalog("power")
	Plan.Profiles.catalogs["power"]={"assets":{
		generator_asset:{"role":"source","quantity":12,"ports":{"outlet":"south"}},
		load_asset:{"role":"consumer","quantity":8,"priority":70,"ports":{"inlet":"north"}}}}
	data["objects"].append_array([object(generator_asset,"generator",Vector2(7,-10),"3d",.4),
		object(load_asset,"load",Vector2(7,10),"3d",.4)])
	data["utilities"]["power"]=true
	for uid in ["generator","load"]:
		var power_node: Dictionary=node(uid)
		power_node["kind"]="power"
		data["utility_nodes"].append(power_node)
	var wire: Dictionary=edge("crossing_wire","generator","outlet","load","inlet")
	wire["kind"]="power"
	data["utility_edges"].append(wire)
	var water: Dictionary=Plan.compile(data,studio.library,"water")
	var power: Dictionary=Plan.compile(data,studio.library,"power")
	var pipe: Dictionary=water["links"][[false,"home_run"]]
	var cable: Dictionary=power["links"][[false,"crossing_wire"]]
	var pipe_points: Array=pipe["positions"].map(func(at: Array)->Vector2:return Plan.Profiles.Traffic.metric(at,"3d"))
	var wire_points: Array=cable["positions"].map(func(at: Array)->Vector2:return Plan.Profiles.Traffic.metric(at,"3d"))
	check(Geometry2D.segment_intersects_segment(pipe_points[0],pipe_points[1],wire_points[0],wire_points[1])!=null,
		"Water and power runs actually cross in the shared graph fixture.")
	check(Plan.allocate(water,{})["allocations"]=={"home":5,"shop":4} and Plan.allocate(power,{})["allocations"]=={"load":8},
		"Crossing service kinds retain separate occupancy and budgets.")
	data["utility_edges"].remove_at(1)
	check(report(data)["allocations"]["home"]==0 and Plan.allocate(Plan.compile(data,studio.library,"power"),{})["allocations"]["load"]==8,
		"Removing the crossing pipe leaves power supply intact.")
	Plan.Profiles.catalogs["power"]=original

func choose(control: OptionButton,wanted: Variant) -> bool:
	for index in control.item_count:
		if control.get_item_metadata(index)==wanted:
			control.select(index)
			control.item_selected.emit(index)
			return true
	return false

func add_run(ui: RefCounted,a: Dictionary,b: Dictionary) -> bool:
	if not choose(ui.first,a) or not choose(ui.second,b): return false
	var preview: Dictionary=ui.preview()
	if ui.join_button.disabled or preview.is_empty() or not preview["reason"].is_empty(): return false
	ui.join_button.pressed.emit()
	for link in ui.manager().graph["links"].values():
		if link["from"]==a and link["to"]==b: return link["positions"]==preview["positions"]
	return false

func capture(mode: String,ui: RefCounted,kind: String="water") -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	for simple in [false,true]:
		studio.consumer_shell.set_active(simple,false)
		for size in [Vector2i(1480,900),Vector2i(960,640)]:
			root.size=size
			studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true} if size.x==960 else {})
			if size.x==960: studio.workspace_layout.library_toggle.button_pressed=false
			studio._command(kind,null)
			await settle()
			studio.simulation_diagnostic_tools.choose(kind)
			studio.simulation_diagnostic_tools.tick(.3)
			var bounds:=Rect2(Vector2.ZERO,Vector2(size))
			check(ui.enabled.has_focus() and bounds.encloses(ui.enabled.get_global_rect()) and studio.simulation_diagnostic_tools.overlay.visible,
				kind.capitalize()+" keyboard focus and overlay visible at "+str([simple,mode,size]))
			RenderingServer.force_draw(false)
			RenderingServer.force_draw(false)
			var path: String=output+"/%s_%s_%s_%d.png"%[kind,"simple" if simple else "precision",mode,size.x]
			check(root.get_texture().get_image().save_png(path)==OK,"Captured "+path)
			if size.x==960:
				ui.second.grab_focus()
				await settle()
				var return_button: Button=studio.consumer_shell.expert_return
				var picker_bounds: Rect2=ui.second.get_global_rect()
				check(ui.second.has_focus() and bounds.encloses(picker_bounds) and (not return_button.visible or not return_button.get_global_rect().intersects(picker_bounds)),
					"Compact "+kind+" panel reveals the keyboard-focused port picker "+str([simple,mode]))
				RenderingServer.force_draw(false)
				RenderingServer.force_draw(false)
				check(root.get_texture().get_image().save_png(path.replace(".png","_ports.png"))==OK,"Captured focused port picker "+str([simple,mode]))
				ui.second.release_focus()
			ui.enabled.release_focus()
	root.size=Vector2i(1480,900)
	studio.accessibility_settings.restore({})

func workflow(mode: String) -> void:
	studio.switch_mode(mode)
	var doc: RefCounted=studio.current()
	doc.data=fixture(mode)
	studio.economy_tools.pauses[mode]=true
	doc.data["economy"]={"enabled":true,"starting_cash":1000000,"period_seconds":60}
	doc.data["economy_account"]=Economy.fresh_account(doc.data,studio.library)
	var account: Dictionary=doc.data["economy_account"].duplicate(true)
	doc.undo_history.clear()
	doc.redo_history.clear()
	studio.changed()
	await settle()
	studio._command("water",null)
	var ui: RefCounted=studio.utility_tools
	check(ui.panel.is_visible_in_tree() and not ui.manager().graph["enabled"],"Water panel opens with simulation off "+mode)
	for uid in ["well","tank","home","shop"]:
		studio.selected_uid=uid
		studio.selected_uids.assign([uid])
		ui.refresh()
		check(not ui.apply_facility_button.disabled,"Select reviewed role "+uid+" "+mode)
		ui.apply_facility_button.pressed.emit()
	check(doc.data.get("utility_nodes",[]).size()==4,"Apply facility settings to four placements "+mode)
	ui.enabled.button_pressed=true
	ui.apply_enabled.pressed.emit()
	check(Plan.enabled(doc.data,"water"),"Opt in from the Water panel "+mode)
	check(add_run(ui,reference("well","outlet"),reference("tank","west")),"Author well run at previewed ports "+mode)
	check(add_run(ui,reference("tank","east"),reference("home","inlet")),"Author home run at previewed ports "+mode)
	check(add_run(ui,reference("tank","south"),reference("shop","inlet")),"Author shop run at previewed ports "+mode)
	var runtime: Node=ui.manager()
	runtime.reset_preview()
	for i in 8: runtime.step(.25)
	check(runtime.served("home")==5 and runtime.stored()==1 and studio.worlds[mode].exploration.interior==null,
		"Unloaded owned interior consumes its building demand "+mode)
	var source: Dictionary=doc.data.duplicate(true)
	var home_run: Dictionary={}
	for connection in doc.data.get("utility_edges",[]):
		if connection["to"]["object_uid"]=="home": home_run=connection
	if not home_run.is_empty() and choose(ui.links,[false,home_run["uid"]]):
		ui.remove_link_button.pressed.emit()
		check(runtime.served("home")==0 and runtime.describe("home").contains("Outage"),"Disconnect visibly interrupts service "+mode)
		studio.simulation_diagnostic_tools.choose("water")
		studio.simulation_diagnostic_tools.tick(.3)
		check(studio.simulation_diagnostic_tools.snapshot.get("rows",[]).any(func(row: Dictionary)->bool:
			return row["object_uid"]=="home" and row["severity"]=="error"),"Water overlay records the outage "+mode)
		studio._command("undo",null)
		ui.tick(0)
		check(doc.data==source and runtime.served("home")==5,"Undo restores exact pipe and service "+mode)
		studio._command("redo",null)
		ui.tick(0)
		check(runtime.served("home")==0,"Redo restores the outage "+mode)
		check(add_run(ui,reference("tank","east"),reference("home","inlet")) and runtime.served("home")==5,"Reconnect restores delivery "+mode)
	else: check(false,"Select saved home run "+mode)
	var current: Dictionary=doc.data.duplicate(true)
	check(current["economy_account"]==account,"Water authoring and delivery leave treasury balances unchanged "+mode)
	var before: Dictionary={"2d":Templates.make("2d","blank"),"3d":Templates.make("3d","blank")}
	before[mode]=current.duplicate(true)
	var rect: Rect2=Protection.object_rect(doc.object("home"),mode,studio.library)
	before[mode]["protected_areas"]=[{"uid":"block","owner":"host","name":"Home block","rect":[rect.position.x-1,rect.position.y-1,rect.size.x+2,rect.size.y+2]}]
	var next: Dictionary=before.duplicate(true)
	next[mode]["utility_edges"]=next[mode]["utility_edges"].filter(func(run: Dictionary)->bool:return run["to"]["object_uid"]!="home")
	check(Protection.allowed(before,next,"guest",studio.library).contains("Home block") and Protection.allowed(before,next,"host",studio.library).is_empty(),"Co-op authority protects both endpoints "+mode)
	next=before.duplicate(true)
	next[mode]["utilities"]["water"]=false
	check(Protection.allowed(before,next,"guest",studio.library).contains("host"),"Only host changes shared water switch "+mode)
	await capture(mode,ui)
	studio.selected_uids.assign(["well","tank"])
	studio.selected_uid="well"
	studio.duplicate_selection()
	check(doc.data.get("utility_nodes",[]).size()==6 and doc.data.get("utility_edges",[]).size()==4 and Doc.valid(doc.data,mode,studio.library),
		"Duplicate remaps internal service references only "+mode)
	studio._command("undo",null)
	ui.tick(0)
	check(doc.data==current,"Undo duplicate restores water authoring "+mode)
	check(not doc.data.has("stock") and not doc.data.has("allocations"),"Runtime service never enters authored data "+mode)
	var path: String=output+"/water_"+mode+".isocity.json"
	check(studio.write_project(path,false) and studio.load_project(path),"Save and reopen authored water city "+mode)
	ui.tick(0)
	check(studio.current().data.get("utility_nodes",[])==current["utility_nodes"] and studio.current().data.get("utility_edges",[])==current["utility_edges"]
		and Plan.enabled(studio.current().data,"water") and ui.manager().stored()==0 and ui.manager().served("home")==5,
		"Saved configuration reloads with an empty private tank and current forecast "+mode)
	if "--portable" in OS.get_cmdline_user_args():
		var export: Dictionary=Export.new().save(studio.worlds[mode],current,studio.library,output+"/water_"+mode+".zip")
		check(export.get("ok",false),"Water portable export created "+mode+" "+str(export.get("message","")))

func run() -> void:
	output=OS.get_environment("ISOCITY_WATER_OUTPUT")
	if output.is_empty(): output="res://output/verification/asset_expansion/N04"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	studio=load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled=false
	root.add_child(studio)
	await settle()
	if studio.consumer_shell: studio.consumer_shell.dismiss_welcome()
	for mode in ["2d","3d"]:
		solver(mode)
		await workflow(mode)
	crossed_kinds()
	studio.free()
	await settle()
	print("WATER NETWORK: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
