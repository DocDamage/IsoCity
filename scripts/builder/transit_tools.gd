extends RefCounted
const Plan=preload("res://scripts/builder/transit_plan.gd")
const Layers=preload("res://scripts/builder/layers.gd")
var studio: Control
var panel: ScrollContainer
var enabled: CheckButton
var automatic: CheckButton
var population: SpinBox
var speed: SpinBox
var interval: SpinBox
var seed: SpinBox
var paused: CheckButton
var lines: OptionButton
var stops: OptionButton
var destination: OptionButton
var ordered: ItemList
var name_input: LineEdit
var color_input: ColorPickerButton
var line_enabled: CheckButton
var school_bus: CheckButton
var headway: SpinBox
var dwell: SpinBox
var offset: SpinBox
var capacity: SpinBox
var status: Label
var timetable: Label
var managers: Dictionary={}
var draft: Array[String]=[]
var selected: String=""
var fields_mode: String=""
var authored_stamp: int=0
var settings_stamp: int=-1
var line_stamp: int=-1
var dirty: bool=true
var elapsed: float=0
func _init(host: Control) -> void:
	studio=host; panel=ScrollContainer.new(); panel.name="Transit"; panel.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; panel.follow_focus=true; studio.workspace_layout.tabs.add_child(panel)
	var box:=VBoxContainer.new(); box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; box.add_theme_constant_override("separation",8); panel.add_child(box)
	studio.label(box,"Public transit",17)
	status=studio.label(box,"Public transit is off.",12); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	enabled=toggle(box,"Enable public transit"); automatic=toggle(box,"Generate passenger journeys")
	population=field(box,"Maximum active passengers",0,128,1); interval=field(box,"Seconds between passenger requests",5,600,1); speed=field(box,"Bus speed (units / second)",1,8,.5); seed=field(box,"Passenger seed",1,2147483647,1)
	button(box,"Apply transit settings",apply_settings)
	paused=toggle(box,"Pause transit preview"); paused.toggled.connect(func(value: bool): managers[studio.mode].paused=value)
	button(box,"Restart transit preview",restart)
	studio.label(box,"Stops",15)
	button(box,"Add stop near view center",add_stop)
	button(box,"Mark selection as bus stops",func(): mark_stops(true)); button(box,"Remove selected stop designations",func(): mark_stops(false))
	stops=choice(box); button(box,"Locate chosen stop",func(): locate(choice_id(stops)))
	studio.label(box,"Bus routes",15)
	lines=choice(box); lines.item_selected.connect(func(index: int): selected=lines.get_item_metadata(index); load_line())
	button(box,"New route",new_line)
	studio.label(box,"Route name",12); name_input=LineEdit.new(); name_input.placeholder_text="Route name"; name_input.max_length=128; box.add_child(name_input)
	line_enabled=toggle(box,"Run this route")
	school_bus=toggle(box,"Use the school bus")
	studio.label(box,"Route color",12); color_input=ColorPickerButton.new(); color_input.custom_minimum_size.y=36; box.add_child(color_input)
	headway=field(box,"Seconds between departures",10,900,1); dwell=field(box,"Minimum stop time (seconds)",2,60,1); offset=field(box,"Service start offset (seconds)",0,899,1); capacity=field(box,"Passenger seats per bus",1,64,1)
	ordered=ItemList.new(); ordered.custom_minimum_size=Vector2(160,140); box.add_child(ordered)
	button(box,"Append chosen stop to route",append_stop); button(box,"Move route stop up",func(): move_stop(-1)); button(box,"Move route stop down",func(): move_stop(1)); button(box,"Remove route stop",remove_stop)
	button(box,"Save route",save_line); button(box,"Delete route",delete_line)
	timetable=studio.label(box,"",12); timetable.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	studio.label(box,"Passenger connection preview",15)
	studio.label(box,"From the chosen stop above to:",12); destination=choice(box)
	button(box,"Send a passenger",send_passenger)
	var help: Label=studio.label(box,"Draw standard-width connected roads, then place at least two stops outside their sidewalks. Routes cycle through their ordered stops and return to the first. Share a stop between routes to create a transfer. Timetables show seconds since preview start; traffic and boarding can delay actual departures. Buses keep their passengers and reroute toward the same stop when a safe lane is available. If the route becomes disconnected, they wait for a connection. Route settings and stop designations save with the city and support Undo. Positions, queues and elapsed time restart on load.",12); help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
func field(parent: Node,title: String,low: float,high: float,step: float) -> SpinBox:
	studio.label(parent,title,12); return studio.spin(parent,low,high,step,low)
func toggle(parent: Node,title: String) -> CheckButton:
	var control:=CheckButton.new(); control.text=title; parent.add_child(control); return control
func choice(parent: Node) -> OptionButton:
	var control:=OptionButton.new(); control.fit_to_longest_item=false; control.clip_text=true; parent.add_child(control); return control
func button(parent: Node,title: String,callback: Callable) -> void:
	var control:=Button.new(); control.text=title; control.clip_text=true; parent.add_child(control); control.pressed.connect(callback)
func start() -> void:
	for mode in ["2d","3d"]:
		var manager=preload("res://scripts/builder/transit_runtime.gd").new(); studio.worlds[mode].add_child(manager); managers[mode]=manager
	refresh_settings(); refresh_authored(); new_line()
func document() -> RefCounted: return studio.interior_tools.root_document(studio.mode)
func editable() -> bool:
	if studio.interior_tools.editing() or studio.worlds[studio.mode].exploration.interior!=null: studio.status.text="Edit public transit from the exterior city."; return false
	return true
func show() -> void:
	studio.workspace_presets.set_focus(false)
	if studio.walking: studio.set_walking(false)
	studio.workspace_layout.inspector_toggle.button_pressed=true; studio.workspace_layout.tabs.current_tab=panel.get_index(); refresh_settings(); refresh_authored()
	studio.workspace_layout.tabs.get_tab_bar().call_deferred("ensure_tab_visible",panel.get_index())
func commit(before: Dictionary) -> void:
	document().record_completed_change(before); studio.changed(); dirty=true; authored_stamp=0; refresh_authored(); studio.workspace_layout.tabs.current_tab=panel.get_index()
func before_edit() -> Dictionary:
	studio.finish_edit(studio.canvas_pointer()); document().finish_checkpoint(); return document().data.duplicate(true)
func refresh_settings() -> void:
	if studio.documents.is_empty(): return
	var config: Dictionary=Plan.settings(document().data); settings_stamp=hash(config)
	enabled.set_pressed_no_signal(config["enabled"]); automatic.set_pressed_no_signal(config["automatic"]); population.set_value_no_signal(config["population"]); interval.set_value_no_signal(config["interval"]); speed.set_value_no_signal(config["speed"]); seed.set_value_no_signal(config["seed"])
	paused.set_pressed_no_signal(managers[studio.mode].paused if managers.has(studio.mode) else false)
func apply_settings() -> void:
	if not editable(): return
	var value: Dictionary={"enabled":enabled.button_pressed,"automatic":automatic.button_pressed,"population":int(population.value),"interval":interval.value,"speed":speed.value,"seed":int(seed.value)}
	if value==Plan.settings(document().data): return
	var before: Dictionary=before_edit(); var config: Dictionary=document().data.get("transit",{}).duplicate(true); config.merge(value,true); document().data["transit"]=config; commit(before); refresh_settings()
func choice_id(control: OptionButton) -> String: return control.get_item_metadata(control.selected) if control.selected>=0 else ""
func refresh_authored() -> void:
	var data: Dictionary=document().data; var stamp: int=hash([studio.mode,data.get("transit_lines",[]),data["objects"]])
	if stamp==authored_stamp: return
	authored_stamp=stamp
	for control in [stops,destination]:
		var previous: String=choice_id(control); control.clear()
		for item in data["objects"]:
			if not Plan.is_stop(item): continue
			control.add_item(item.get("name",studio.library.assets.get(item["asset"],{}).get("name",item["uid"]))); control.set_item_metadata(control.item_count-1,item["uid"])
			if item["uid"]==previous: control.select(control.item_count-1)
	lines.clear()
	for item in data.get("transit_lines",[]):
		lines.add_item(item.get("name","Bus route")); lines.set_item_metadata(lines.item_count-1,item["uid"])
		if item["uid"]==selected: lines.select(lines.item_count-1)
	if not selected.is_empty() and hash(line())!=line_stamp: load_line()
	refresh_draft()
func line() -> Dictionary:
	for item in document().data.get("transit_lines",[]):
		if item["uid"]==selected: return item
	return {}
func new_line() -> void:
	selected=""; draft.clear(); name_input.text="Bus route"; color_input.color=Color("77b8ff"); line_enabled.set_pressed_no_signal(true); school_bus.set_pressed_no_signal(false); headway.set_value_no_signal(60); dwell.set_value_no_signal(6); offset.set_value_no_signal(0); capacity.set_value_no_signal(16); line_stamp=-1; refresh_draft()
func load_line() -> void:
	var item: Dictionary=line()
	if item.is_empty(): new_line(); return
	line_stamp=hash(item); var config: Dictionary=Plan.line_settings(item)
	draft.assign(item["stops"]); name_input.text=item.get("name","Bus route"); color_input.color=Color(config["color"]); line_enabled.set_pressed_no_signal(config["enabled"]); school_bus.set_pressed_no_signal(config["school_bus"]); headway.set_value_no_signal(config["headway"]); dwell.set_value_no_signal(config["dwell"]); offset.set_value_no_signal(config["offset"]); capacity.set_value_no_signal(config["capacity"]); refresh_draft()
func refresh_draft() -> void:
	ordered.clear()
	for uid in draft:
		var item: Dictionary=document().object(uid); ordered.add_item(str(ordered.item_count+1)+". "+item.get("name",studio.library.assets.get(item.get("asset",""),{}).get("name","Missing stop: "+uid)))
func append_stop() -> void:
	var uid: String=choice_id(stops)
	if uid.is_empty() or uid in draft or draft.size()>=Plan.MAX_LINE_STOPS: return
	draft.append(uid); refresh_draft(); ordered.select(draft.size()-1)
func move_stop(amount: int) -> void:
	var indexes: PackedInt32Array=ordered.get_selected_items()
	if indexes.is_empty(): return
	var index: int=indexes[0]; var target: int=index+amount
	if target<0 or target>=draft.size(): return
	var uid: String=draft[index]; draft.remove_at(index); draft.insert(target,uid); refresh_draft(); ordered.select(target)
func remove_stop() -> void:
	var indexes: PackedInt32Array=ordered.get_selected_items()
	if not indexes.is_empty(): draft.remove_at(indexes[0]); refresh_draft()
func save_line() -> void:
	if not editable(): return
	var value: Dictionary=line().duplicate(true)
	value.merge({"uid":selected if not selected.is_empty() else "line_"+str(Time.get_ticks_usec()),"name":name_input.text.strip_edges() if not name_input.text.strip_edges().is_empty() else "Bus route","stops":Array(draft),"enabled":line_enabled.button_pressed,"color":color_input.color.to_html(),"headway":headway.value,"dwell":dwell.value,"offset":offset.value,"capacity":int(capacity.value)},true)
	if school_bus.button_pressed: value["school_bus"]=true
	else: value.erase("school_bus")
	var proposed: Array=document().data.get("transit_lines",[]).duplicate(true)
	var index: int=proposed.find_custom(func(item: Dictionary):return item["uid"]==value["uid"])
	if index>=0: proposed[index]=value
	else: proposed.append(value)
	if not Plan.valid_lines(proposed): studio.status.text="Use 2–16 distinct stops, a valid hex color and an offset smaller than the departure interval. Maximum 16 routes."; return
	if proposed==document().data.get("transit_lines",[]): return
	var before: Dictionary=before_edit(); document().data["transit_lines"]=proposed; selected=value["uid"]; commit(before); load_line(); studio.status.text="Bus route saved. Operating buses will use safe connections to their next available scheduled stop."
func delete_line() -> void:
	if not editable() or line().is_empty(): return
	var before: Dictionary=before_edit(); document().data["transit_lines"].erase(line()); new_line(); commit(before)
func mark_stops(value: bool) -> void:
	if not editable(): return
	var items: Array=studio.selection_items().filter(func(item: Dictionary):return Plan.is_stop(item)!=value and (not value or Plan.stop_allowed(item,studio.library)))
	if items.is_empty(): studio.status.text="Select editable street props to change their stop designation."; return
	var before: Dictionary=before_edit()
	for item in items: item["transit_stop"]=value
	commit(before)
func add_stop() -> void:
	if not editable(): return
	if not Layers.shown(document().data,"Decorations") or Layers.locked(document().data,"Decorations"): studio.status.text="Show and unlock Decorations to add a bus stop."; return
	var world: Node=studio.worlds[studio.mode]; var location: Variant=world.camera.position if studio.mode=="2d" else world.target
	var center: Vector2=Plan.Traffic.metric([location.x,location.y,0] if studio.mode=="2d" else [location.x,location.y,location.z],studio.mode)
	var asset: String="2d:Bus_Stop_Sign" if studio.mode=="2d" else "3d:HanX_Traffic/Bus_Stop"
	var item: Dictionary={"uid":"stop_"+str(Time.get_ticks_usec()),"asset":asset,"position":[0,0,0],"direction":studio.library.directions(asset)[0],"scale":1.0}
	var box: Rect2=Plan.Zones.footprint(item,studio.mode,studio.library); var network: Dictionary=Plan.Traffic.build(document().data)
	var best: Dictionary={}; var candidates: Array[Vector2]=[]
	for section in network["sections"].values():
		if section["neighbors"].size()!=2 or section["width"]<3.6 or section["crossing"]: continue
		var axis:=Vector2(network["sections"][section["neighbors"][0]]["cell"]-section["cell"]); var right:=Vector2(-axis.y,axis.x)
		for side in [-1,1]:
			var point: Vector2=Plan.Traffic.center(section["cell"],studio.mode)+right*side*(section["width"]*.5+2+(absf(right.x)*box.size.x+absf(right.y)*box.size.y)*.5)
			candidates.append(point)
	candidates.sort_custom(func(a: Vector2,b: Vector2):return a.distance_squared_to(center)<b.distance_squared_to(center))
	for point in candidates:
		var proposal: Dictionary=item.duplicate(true); proposal["position"]=Plan.Traffic.world(point-box.get_center(),studio.mode)
		var footprint: Rect2=Plan.Zones.footprint(proposal,studio.mode,studio.library).grow(.5)
		if document().data["objects"].any(func(other: Dictionary):return not preload("res://scripts/builder/asset_behavior.gd").for_asset(other["asset"],studio.library).get("ground",false) and footprint.intersects(Plan.Zones.footprint(other,studio.mode,studio.library))): continue
		if not Plan.stop(document().data,proposal,studio.library,network)["ok"]: continue
		best=proposal; break
	if best.is_empty(): studio.status.text="Draw standard-width straight roads and clear space outside the sidewalk first."; return
	var before: Dictionary=before_edit(); best["name"]="Bus stop "+str(document().data["objects"].filter(func(other: Dictionary):return Plan.is_stop(other)).size()+1); document().data["objects"].append(best); studio.selected_uids.assign([best["uid"]]); studio.selected_uid=best["uid"]; studio.set_tool("select"); commit(before); studio.status.text="Bus stop added. Move or rotate it with Select / move."
func locate(uid: String) -> void:
	var item: Dictionary=document().object(uid)
	if item.is_empty(): return
	var point: Array=item["position"]
	if studio.mode=="2d": studio.worlds[studio.mode].camera.position=Vector2(point[0],point[1])
	else: studio.worlds[studio.mode].target=Vector3(point[0],point[1],point[2]); studio.worlds[studio.mode].update_camera()
func send_passenger() -> void:
	if not editable(): return
	var manager: Node=managers[studio.mode]; var plan: Dictionary=manager.passengers.plan; var from: String=choice_id(stops); var to: String=choice_id(destination)
	if not plan.get("stops",{}).has(from) or not plan.get("stops",{}).has(to) or from==to: studio.status.text="Choose two usable, connected transit stops and enable transit."; return
	var result: Dictionary=manager.request(plan["stops"][from]["platform"]+plan["stops"][from]["right"]*2,plan["stops"][to]["platform"]+plan["stops"][to]["right"]*2)
	studio.status.text="Passenger journey started." if result["ok"] else result["reason"]
func restart() -> void:
	managers[studio.mode].reset(); dirty=true
func reset() -> void:
	for manager in managers.values(): manager.reset(); manager.paused=false
	fields_mode=""; settings_stamp=-1; authored_stamp=0; new_line(); dirty=true
func tick(delta: float) -> void:
	if managers.is_empty(): return
	for mode in managers:
		var manager: Node=managers[mode]
		manager.set_text_scale(studio.accessibility_settings.text_scale)
		studio.traffic_tools.managers[mode].transit=manager
		studio.citizen_tools.managers[mode].transit=manager
		manager.active=mode==studio.mode and not studio.modal_visible() and not studio.interior_tools.editing() and studio.worlds[mode].exploration.interior==null and not studio.stroke and not studio.road_drawing and not studio.ground_brush.drawing and not studio.transform_handles.dragging
		if is_instance_valid(manager.helper.container): manager.helper.container.visible=mode==studio.mode and not studio.interior_tools.editing() and studio.worlds[mode].exploration.interior==null
	if fields_mode!=studio.mode: fields_mode=studio.mode; selected=""; authored_stamp=0; refresh_settings(); new_line(); dirty=true
	if settings_stamp!=hash(Plan.settings(document().data)): refresh_settings()
	if dirty and managers[studio.mode].active:
		var world: Node=studio.worlds[studio.mode]; managers[studio.mode].configure(document().data,studio.library,world.instances,world.objects,studio.traffic_tools.managers[studio.mode],studio.service_tools.managers[studio.mode]); dirty=false
	elapsed+=delta
	if elapsed<.4: return
	elapsed=0; refresh_authored()
	var manager: Node=managers[studio.mode]; status.text=manager.summary()+"\n"+"\n".join(manager.passengers.plan.get("notices",[]))+manager.notice
	var compiled: Dictionary=manager.passengers.plan.get("lines",{}).get(selected,{})
	timetable.text="Save and enable a usable route to see its timetable."
	if not compiled.is_empty():
		timetable.text="%d buses · %.0f-second cycle\nNext scheduled departures:"%[compiled["fleet"],compiled["cycle"]]
		for index in compiled["stops"].size(): timetable.text+="\n"+manager.passengers.plan["stops"][compiled["stops"][index]]["name"]+" · %.1f s"%Plan.next_departure(compiled,index,manager.elapsed)["time"]
