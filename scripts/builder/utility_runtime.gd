extends Node

const Plan=preload("res://scripts/builder/utility_plan.gd")
var kind: String="water"
var graph: Dictionary={}
var signature: int=0
var revision: int=0
var stock: Dictionary={}
var storage_identity: Dictionary={}
var report: Dictionary={}
var tick_count: int=0
var retired_stock: int=0
var elapsed: float=0
var paused: bool=false
var active: bool=true
var forecast: bool=true
var show_hud: bool=false
var panel: PanelContainer
var caption: Label
var pause_button: Button

func configure(data: Dictionary,library: RefCounted,force: bool=false) -> void:
	var stamp: int=Plan.stamp(data,library,kind)
	if not force and not graph.is_empty() and stamp==signature: return
	signature=stamp
	revision+=1
	graph=Plan.compile(data,library,kind)
	var current: Dictionary={}
	for node in graph["nodes"].values():
		if node["role"]!="storage": continue
		var family: String=library.assets.get(node["asset"],{}).get("data",{}).get("family_id","")
		current[node["uid"]]=[node["object_uid"],family if not family.is_empty() else node["asset"],node["capacity"]]
	for id in stock.keys():
		var amount: int=stock[id]
		if not current.has(id) or current[id]!=storage_identity.get(id):
			retired_stock+=amount
			stock.erase(id)
	storage_identity=current
	publish(true)

func publish(projected: bool) -> void:
	report=Plan.allocate(graph,stock)
	forecast=projected
	if not projected: stock=report["stock"].duplicate()
	update_hud()

func step(delta: float) -> void:
	if not active or paused or not graph.get("enabled",false) or not is_finite(delta) or delta<=0: return
	elapsed+=minf(delta,.25)
	if elapsed<Plan.SECONDS_PER_TICK: return
	elapsed-=Plan.SECONDS_PER_TICK
	tick_count+=1
	publish(false)

func reset_preview() -> void:
	stock.clear()
	tick_count=0
	retired_stock=0
	elapsed=0
	if not graph.is_empty(): publish(true)

func served(uid: String) -> int:
	return int(report.get("allocations",{}).get(uid,0))

func requirement(uid: String,effect: String) -> String:
	if not graph.get("enabled",false): return ""
	var node: Dictionary=graph["nodes"].get(uid,{})
	if node.get("effect","")!=effect: return ""
	if not node["reason"].is_empty(): return "Electricity unavailable · "+node["reason"]
	if served(uid)<node["quantity"]: return "Electricity unavailable · "+describe(uid)
	return ""

func stored() -> int:
	var total: int=0
	for amount in stock.values(): total+=int(amount)
	return total

func describe(uid: String) -> String:
	var node: Dictionary=graph.get("nodes",{}).get(uid,{})
	if node.is_empty(): return ""
	if not node["reason"].is_empty(): return node["reason"]
	if not graph["enabled"]: return "Enable the utility simulation to operate this facility."
	match node["role"]:
		"source":
			var amount: String=str(node["production"]) if node["production"]==node["quantity"] else "%d / %d"%[node["production"],node["quantity"]]
			return "%s %s units per tick."%[amount,kind]
		"storage":
			var text: String="%d / %d %s units stored."%[stock.get(node["uid"],0),node["capacity"],kind]
			if kind=="power": text+=" Charge up to %d and discharge up to %d per tick."%[node["charge"],node["discharge"]]
			return text
		"relay": return "Joins connected power ports into one component."
		"consumer":
			var amount: int=served(uid)
			var state: String="Outage" if amount==0 and node["quantity"]>0 else ("Brownout" if kind=="power" else "Shortage") if amount<node["quantity"] else "Supplied"
			var text: String="%s · %d / %d %s units per tick."%[state,amount,node["quantity"],kind]
			if node["fixtures"]>0: text+=" Includes %d units for fixtures on all floors."%node["fixtures"]
			return text
	return ""

func build_hud() -> void:
	var layer:=CanvasLayer.new()
	layer.layer=16
	add_child(layer)
	panel=PanelContainer.new()
	layer.add_child(panel)
	var box:=VBoxContainer.new()
	panel.add_child(box)
	caption=Label.new()
	caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	caption.custom_minimum_size.x=225
	box.add_child(caption)
	pause_button=Button.new()
	pause_button.accessibility_name="Pause "+kind+" preview"
	pause_button.custom_minimum_size.y=38
	box.add_child(pause_button)
	pause_button.pressed.connect(func():paused=not paused;update_hud())

func update_hud() -> void:
	if not show_hud: return
	if not is_instance_valid(panel):
		if not graph.get("enabled",false): return
		build_hud()
	panel.visible=graph.get("enabled",false)
	if not panel.visible: return
	var total: int=0
	var unserved: int=0
	for node in graph["nodes"].values():
		if node["role"]!="consumer": continue
		total+=node["quantity"]
		if served(node["object_uid"])<node["quantity"]: unserved+=1
	caption.text="%s · %d/%d units per tick\n%d stored · %d short"%[
		kind.capitalize(),report.get("balance",{}).get("delivered",0),total,stored(),unserved]
	if forecast: caption.text+="\nNext tick estimate"
	pause_button.text="Resume "+kind if paused else "Pause "+kind
	panel.reset_size()
	panel.position=Vector2(260 if kind=="power" else 16,130)

func _process(delta: float) -> void:
	step(delta)
