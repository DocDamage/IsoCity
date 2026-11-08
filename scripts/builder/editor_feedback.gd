extends RefCounted

var studio: Control
var observed: String=""
var remaining: float=0
var records: Array[String]=[]
var dialog: AcceptDialog
var list: ItemList
var detail: RichTextLabel
var walk_prompt: Label
var rejection: String=""
var rejection_time: float=0
var revision: int=0
var surface_key: String=""
var surfaces: Dictionary={}

func _init(host: Control,center: Node) -> void:
	studio=host
	var parent: Node=studio.status.get_parent()
	var index: int=studio.status.get_index()
	var row:=HBoxContainer.new()
	parent.add_child(row)
	parent.move_child(row,index)
	studio.label(row,"Action",12)
	studio.status.reparent(row)
	studio.status.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	studio.status.clip_text=true
	var history:=Button.new()
	history.text="Recent actions"
	row.add_child(history)
	history.pressed.connect(show_history)
	walk_prompt=studio.label(center,"",13)
	walk_prompt.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	center.move_child(walk_prompt,1)
	walk_prompt.hide()
	dialog=AcceptDialog.new()
	dialog.title="Recent action feedback"
	dialog.size=Vector2i(720,460)
	studio.add_child(dialog)
	var box:=VBoxContainer.new()
	dialog.add_child(box)
	list=ItemList.new()
	list.custom_minimum_size=Vector2(320,220)
	list.size_flags_vertical=Control.SIZE_EXPAND_FILL
	box.add_child(list)
	detail=RichTextLabel.new()
	detail.bbcode_enabled=false
	detail.custom_minimum_size=Vector2(320,100)
	box.add_child(detail)
	list.item_selected.connect(func(i: int): detail.text=str(list.get_item_metadata(i)))

func tick(delta: float) -> void:
	rejection_time=maxf(0,rejection_time-delta)
	if studio.status.text!=observed:
		observed=studio.status.text
		remaining=8 if not observed.is_empty() else 0
		studio.status.tooltip_text=observed
		if not observed.is_empty():
			records.push_front(Time.get_time_string_from_system()+" · "+observed)
			if records.size()>40: records.resize(40)
	elif remaining>0:
		remaining=maxf(0,remaining-delta)
		if remaining==0: studio.status.text=""; observed=""; studio.status.tooltip_text=""

func show_history() -> void:
	tick(0)
	list.clear()
	for text in records:
		list.add_item(text)
		list.set_item_metadata(list.item_count-1,text)
	detail.text=records[0] if not records.is_empty() else "No action feedback yet. Save state remains above the canvas."
	var size: Vector2i=studio.get_window().size
	dialog.popup_centered(Vector2i(mini(720,size.x-48),mini(460,size.y-80)))

func reject(message: String) -> void:
	rejection=message
	rejection_time=8

func invalidate() -> void:
	revision+=1
	surface_key=""

func blocked_reason() -> String:
	var ground: bool=studio.tool in ["road","road_erase","crossing"] or studio.ground_brush.active()
	var id: String=studio.asset_id
	if not ground and (studio.tool!="place" or id.is_empty()): return ""
	if not ground and (not studio.library.assets.has(id) or studio.library.assets[id].get("unavailable",false)): return "Source asset is unavailable · restore its files or choose another asset"
	var layer: String="Ground" if ground else studio.Layers.classify(id,studio.library)
	var states: Array[String]=[]
	if not studio.Layers.shown(studio.current().data,layer): states.append("hidden")
	if studio.Layers.locked(studio.current().data,layer): states.append("locked")
	return layer+" layer is "+" and ".join(states)+" · change it in Layers" if not states.is_empty() else ""

func diagnostics(at: Vector2,info: Dictionary) -> Dictionary:
	var blocked: String=blocked_reason()
	if not blocked.is_empty(): return {"text":"Blocked · "+blocked,"blocked":true,"warning":true}
	if rejection_time>0 and studio.asset_id.is_empty(): return {"text":rejection,"blocked":true,"warning":true}
	if studio.tool in ["road","crossing"]:
		var terrain=preload("res://scripts/builder/terrain_plan.gd")
		if terrain.settings(studio.current().data)["enabled"]:
			var cell: Vector2i=studio.Roads.cell_at(studio.worlds[studio.mode].point(at,false,0),studio.mode); var center: Vector2=preload("res://scripts/builder/traffic_plan.gd").center(cell,studio.mode)
			var reason: String=preload("res://scripts/builder/terrain_road_policy.gd").reason(studio.current().data,center,terrain.lookup(studio.current().data),terrain.lookup(studio.current().data,true))
			if not reason.is_empty(): return {"text":"Traffic closed · "+reason,"blocked":false,"warning":true}
	if studio.tool in ["crossing","road_erase"]:
		var cell: Vector2i=studio.Roads.cell_at(studio.worlds[studio.mode].point(at,false,0),studio.mode)
		var present: bool=studio.Roads.lookup(studio.current().data).has(studio.Roads.key(cell))
		if not present: return {"text":"No road section here · draw a road first" if studio.tool=="crossing" else "No road section here · empty sections are skipped","blocked":studio.tool=="crossing","warning":true}
	if studio.tool!="place" or studio.asset_id.is_empty(): return {}
	var socket: Dictionary = info.get("socket", {})
	if socket.get("blocked", false):
		return {"text": socket["reason"], "blocked": true, "warning": true}
	if socket.get("ok", false):
		return {"text": socket["reason"], "blocked": false, "warning": false}

	for number in info.get("position",[]):
		if not is_finite(float(number)) or absf(float(number))>1000000: return {"text":"Blocked · position exceeds the supported coordinate range","blocked":true,"warning":true}
	var messages: Array[String]=[]
	var warning: bool=false
	if studio.ground_brush.active() and (studio.ground_brush.operation.selected==3 or studio.ground_brush.replace_only.button_pressed):
		var brush: RefCounted=studio.ground_brush
		var key: String=str([studio.current().get_instance_id(),revision,studio.asset_id,brush.step,brush.elevation])
		if key!=surface_key: surfaces=brush.surface_index(); surface_key=key
		var cell: Vector2i=brush.cell_at(at)
		if not surfaces.has(cell):
			messages.append("Flood fill needs existing ground under the pointer" if brush.operation.selected==3 else "Replace-only · empty cells will be skipped")
			warning=true
		elif not surfaces[cell].get("editable",true):
			var item: Dictionary=surfaces[cell].get("item",{})
			var name: String=item.get("name",studio.library.assets.get(item.get("asset",""),{}).get("name","Ground object"))
			if item.get("locked",false): messages.append(name+" is locked · unlock it in Scene")
			elif not item.get("visible",true): messages.append(name+" is hidden · show it in Scene")
			else: messages.append(studio.Layers.layer(item,studio.library)+" layer is protected · change it in Layers")
			warning=true
	if studio.mode=="3d" and studio.surface_input.button_pressed and not studio.worlds["3d"].surface_feedback.is_empty(): messages.append(studio.worlds["3d"].surface_feedback)
	var vehicle: bool=studio.library.assets[studio.asset_id].get("behavior",{}).get("vehicle",false)
	if vehicle and studio.lanes_input.button_pressed:
		if studio.arrange_tools.target()!="base": messages.append("Lane snap bypassed · the chosen anchor takes priority")
		elif not info.get("snapped",false): messages.append("No nearby road lane · using grid or free placement")
		elif studio.rotation_manual: messages.append("Lane position snapped · manual facing is kept")
	if info.get("tile_cell",false) and studio.arrange_tools.target()!="base": messages.append("Native ground tiles use fixed cell anchors")
	elif info.get("ground_cell",false) and studio.arrange_tools.target()!="base": messages.append("Ground brushing uses fixed cell anchors · turn off Paint ground cells for free object placement")
	if not studio.snap_input.button_pressed:
		if info.get("ground_cell",false) or info.get("tile_cell",false): messages.append("Cell painting keeps its cell grid even when Grid snap is off")
		elif info.get("snapped",false): messages.append("Grid snap is off · road lane position is still snapped")
		else: messages.append("Grid snap is off · free placement")
	return {"text":"\n".join(messages),"blocked":false,"warning":warning}
