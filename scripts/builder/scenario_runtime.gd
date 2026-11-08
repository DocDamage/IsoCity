extends Node
const Plan=preload("res://scripts/builder/scenario_plan.gd")
const Citizen=preload("res://scripts/builder/citizen_plan.gd")
const Entrances=preload("res://scripts/builder/entrance_anchors.gd")
var active: bool=true
var construction: Node
var emergency: Node
var active_scenario: String=""
var signature: int=0
var progress: Dictionary={"goals":[],"complete":false,"checking":false,"notices":[]}
var destinations: Dictionary={}
var connections: Dictionary={}
var queue: Array=[]
var obstacles: Array[Rect2]=[]
var checked: int=0
var failures: Dictionary={}
var title: String=""
var show_hud: bool=false
var panel: PanelContainer
var summary: Label
var detail: Label
var elapsed: float=0
func _ready() -> void:
	var layer:=CanvasLayer.new(); layer.layer=18; add_child(layer)
	panel=PanelContainer.new(); layer.add_child(panel)
	var box:=VBoxContainer.new(); panel.add_child(box)
	summary=Label.new(); summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; box.add_child(summary)
	detail=Label.new(); detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; box.add_child(detail); panel.hide()
func configure(data: Dictionary,library: RefCounted,instances: Dictionary,visible_only: bool=true) -> void:
	var scenario: Dictionary=data.get("scenario",{})
	if not Plan.valid(scenario):
		if signature!=0 or not progress["goals"].is_empty(): reset()
		return
	var stamp: int=hash([data["mode"],data["objects"],data.get("layers",{}),scenario,data.get("economy",{}) if scenario.get("id")=="apartment" else {},data.get("economy_account",{}) if scenario.get("id")=="apartment" else {},visible_only])
	if signature==stamp: return
	reset(); signature=stamp
	active_scenario=scenario["id"]
	title=Plan.definitions()[scenario["id"]]["title"]
	if active_scenario=="construction": progress=Plan.construction_progress(construction); update_ui(); return
	if Plan.Emergency.recognized(active_scenario) and emergency:
		progress = emergency.progress()
		update_ui()
		return
	if scenario["id"]=="apartment": progress=Plan.apartment(data,library); update_ui(); return
	var helper:=preload("res://scripts/builder/citizen_runtime.gd").new()
	var arrivals: Dictionary={}
	for item in data["objects"]:
		if not instances.has(item["uid"]) or not Plan.visible(item,data,library): continue
		var node: Node=instances[item["uid"]]
		if visible_only and not node.visible: continue
		helper.collect_obstacles(node)
		if Citizen.role(item).is_empty(): continue
		var point: Variant=Entrances.position_for(node,item,data["mode"],library)
		arrivals[item["uid"]]=[point.x,point.y,item["position"][2]] if data["mode"]=="2d" else [point.x,point.y,point.z]
	obstacles.assign(helper.obstacles); helper.free()
	destinations=Plan.destinations(data,library,arrivals); queue=Plan.requests(destinations)
	progress=Plan.walkable(destinations,connections,not queue.is_empty()); update_ui()
func step() -> void:
	if active and Plan.Emergency.recognized(active_scenario) and emergency:
		var training: Dictionary = emergency.progress()
		if training != progress: progress = training; update_ui()
		return
	if active and active_scenario=="construction":
		var next: Dictionary=Plan.construction_progress(construction)
		if progress!=next: progress=next; update_ui()
		return
	if not active or queue.is_empty(): return
	while not queue.is_empty():
		var request: Dictionary=queue.pop_front()
		if connections.get(request["home"],{}).has(request["kind"]): continue
		var route: Dictionary=Citizen.route(request["from"],request["to"],obstacles); checked+=1
		if Plan.route_ok(request,route):
			if not connections.has(request["home"]): connections[request["home"]]={}
			connections[request["home"]][request["kind"]]={"target":request["target"],"length":Plan.route_length(route["path"]),"path":route["path"]}
			failures.erase(request["home"]+":"+request["kind"])
		else: failures[request["home"]+":"+request["kind"]]=request["kind"].capitalize()+": "+Plan.route_issue(request,route)
		break
	progress=Plan.walkable(destinations,connections,not queue.is_empty())
	progress["notices"].assign(failures.values().slice(0,6)); update_ui()
static func status_name(value: Dictionary) -> String:
	if value.get("state") == "failed": return "Failed"
	if value["complete"]: return "Complete"
	return "Checking routes…" if value["checking"] else "In progress"

func update_ui() -> void:
	if not is_instance_valid(panel): return
	panel.visible=show_hud and not progress["goals"].is_empty()
	if not panel.visible: return
	var width: float=minf(300,get_viewport().get_visible_rect().size.x*.42)
	panel.custom_minimum_size.x=width; panel.size.x=width; panel.position=Vector2(get_viewport().get_visible_rect().size.x-width-20,80)
	summary.text=title+" · "+status_name(progress)
	var rows: PackedStringArray=[]
	for goal in progress["goals"]: rows.append(("✓ " if goal["complete"] else "○ ")+goal["title"]+" (%d/%d)" % [goal["current"],goal["required"]])
	for notice in progress["notices"].slice(0,3): rows.append(notice)
	detail.text="\n".join(rows)
func reset() -> void:
	active_scenario=""
	signature=0; queue.clear(); connections.clear(); obstacles.clear(); destinations.clear(); failures.clear(); checked=0; title=""
	progress={"goals":[],"complete":false,"checking":false,"notices":[]}
	if is_instance_valid(panel): panel.hide()
func _process(delta: float) -> void:
	elapsed+=delta
	if elapsed>=.03: elapsed=0; step()
