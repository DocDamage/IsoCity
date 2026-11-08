extends RefCounted

const Plan=preload("res://scripts/builder/utility_plan.gd")
const Runtime=preload("res://scripts/builder/utility_runtime.gd")
const Protection=preload("res://scripts/builder/cooperative_plan.gd")
const Identity=preload("res://scripts/builder/owned_room_copy.gd")
const Layers=preload("res://scripts/builder/layers.gd")
var kind: String
var title: String
var run_name: String

var studio: Control
var panel: ScrollContainer
var managers: Dictionary={}
var dirty: bool=true
var settings_stamp: Array=[]
var facility_stamp: Array=[]
var ports_stamp: Array=[]
var enabled: CheckButton
var apply_enabled: Button
var paused: CheckButton
var summary: Label
var facility: Label
var facility_enabled: CheckButton
var quantity: SpinBox
var priority: SpinBox
var apply_facility_button: Button
var remove_facility_button: Button
var first: OptionButton
var second: OptionButton
var markers_visible: CheckButton
var navigation: Array[Button]=[]
var navigation_note: String=""
var reviewed: Dictionary={}
var join_button: Button
var links: OptionButton
var remove_link_button: Button
var status: Label

func _init(host: Control,service: String="water") -> void:
	studio=host
	kind=service
	title=kind.capitalize()
	run_name="cable" if kind=="power" else "pipe run"
	panel=ScrollContainer.new()
	panel.name=title
	panel.follow_focus=true
	panel.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	studio.workspace_layout.tabs.add_child(panel)
	var box:=VBoxContainer.new()
	box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation",8)
	panel.add_child(box)
	caption(box,title+" network",17)
	enabled=check(box,"Enable "+kind+" simulation")
	apply_enabled=button(box,"Apply "+kind+" settings",apply_settings)
	paused=check(box,"Pause "+kind+" preview")
	paused.toggled.connect(func(value: bool):manager().paused=value)
	button(box,"Reset "+kind+" preview",func():manager().reset_preview())
	summary=caption(box,"")
	caption(box,"Selected facility",17)
	facility=caption(box,"")
	facility_enabled=check(box,"Operate this facility")
	quantity=number(box,"Source output or demand (units per tick)",Plan.MAX_QUANTITY)
	priority=number(box,"Consumer priority (0–100)",100)
	apply_facility_button=button(box,"Apply facility settings",apply_facility)
	remove_facility_button=button(box,"Remove "+kind+" role",remove_facility)
	caption(box,"Cables" if kind=="power" else "Pipe runs",17)
	caption(box,"Choose two reviewed ports. A run joins their shared budget. Each port accepts one connection.")
	first=picker(box,"Source "+kind+" port")
	second=picker(box,"Target "+kind+" port")
	first.item_selected.connect(port_selected)
	second.item_selected.connect(port_selected)
	var nav:=HBoxContainer.new()
	box.add_child(nav)
	for step in [-1,1]:
		var action: Button=button(nav,"Previous" if step<0 else "Next",cycle.bind(step))
		action.accessibility_name="Previous connection target" if step<0 else "Next connection target"
		action.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		navigation.append(action)
	markers_visible=check(box,"Connection markers")
	markers_visible.accessibility_name="Show connection markers"
	markers_visible.button_pressed=true
	join_button=button(box,"Connect ports",connect_ports)
	status=caption(box,"")
	status.accessibility_name="Connection status"
	links=picker(box,"Existing "+kind+" connection")
	links.item_selected.connect(func(_index: int):update_actions())
	remove_link_button=button(box,"Disconnect selected connection",disconnect_run)
	button(box,"Toggle "+kind+" network overlay",func():
		var diagnostics: RefCounted=studio.simulation_diagnostic_tools
		diagnostics.choose("off" if diagnostics.kind==kind else kind))

func caption(parent: Node,title: String,size: int=12) -> Label:
	var label: Label=studio.label(parent,title,size)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	return label

func check(parent: Node,title: String) -> CheckButton:
	var control:=CheckButton.new()
	control.text=title
	control.custom_minimum_size.y=38
	parent.add_child(control)
	return control

func button(parent: Node,title: String,action: Callable) -> Button:
	var control:=Button.new()
	control.text=title
	control.custom_minimum_size.y=38
	parent.add_child(control)
	control.pressed.connect(action)
	return control

func number(parent: Node,title: String,maximum: int) -> SpinBox:
	caption(parent,title)
	var control:=SpinBox.new()
	control.max_value=maximum
	control.step=1
	control.custom_minimum_size.y=38
	control.get_line_edit().accessibility_name=title
	parent.add_child(control)
	return control

func picker(parent: Node,title: String) -> OptionButton:
	caption(parent,title)
	var control:=OptionButton.new()
	control.fit_to_longest_item=false
	control.clip_text=true
	control.accessibility_name=title
	control.custom_minimum_size.y=38
	parent.add_child(control)
	return control

func start() -> void:
	for mode in ["2d","3d"]:
		var runtime:=Runtime.new()
		runtime.kind=kind
		runtime.set_process(false)
		studio.add_child(runtime)
		managers[mode]=runtime
		if kind=="power": studio.worlds[mode].exploration.power=runtime
		elif kind=="water": studio.worlds[mode].exploration.garden.water_network=runtime

func root(mode: String="") -> RefCounted:
	return studio.interior_tools.root_document(studio.mode if mode.is_empty() else mode)

func manager() -> Node:
	return managers.get(studio.mode)

func show() -> void:
	studio.workspace_presets.set_focus(false)
	if studio.walking: studio.set_walking(false)
	studio.workspace_layout.inspector_toggle.button_pressed=true
	studio.workspace_layout.tabs.current_tab=panel.get_index()
	tick(0)
	enabled.grab_focus()

func reset() -> void:
	for runtime in managers.values():runtime.reset_preview()
	dirty=true

func tick(delta: float) -> void:
	if managers.is_empty(): return
	if dirty:
		for mode in managers: managers[mode].configure(root(mode).data,studio.library)
		dirty=false
	manager().step(delta)
	if panel.is_visible_in_tree(): refresh()

func selected_item() -> Dictionary:
	if not editable(): return {}
	var selected: Array=studio.selection_items()
	return selected[0] if selected.size()==1 else {}

func editable() -> bool:
	return (not studio.interior_tools.editing() and not studio.walking and not root().data.get("interior_room",false)
		and not studio.worlds[studio.mode].exploration.photo.active)

func item_editable(uid: String,objects: Dictionary) -> bool:
	var item: Dictionary=objects.get(uid,{})
	return not item.is_empty() and Layers.editable(root().data,item,studio.library)

func node_for(uid: String) -> Dictionary:
	for node in root().data.get("utility_nodes",[]):
		if node["kind"]==kind and node["object_uid"]==uid: return node
	return {}

func choose_options(control: OptionButton,options: Array,empty: String) -> void:
	var old: Variant=choice(control)
	control.clear()
	control.add_item(empty)
	control.set_item_metadata(0,null)
	for option in options:
		control.add_item(option[0])
		control.set_item_tooltip(control.item_count-1,option[0])
		control.set_item_metadata(control.item_count-1,option[1])
		if old==option[1]: control.select(control.item_count-1)

func choice(control: OptionButton) -> Variant:
	return control.get_item_metadata(control.selected) if control.selected>=0 else null

func port_label(reference: Dictionary,objects: Dictionary) -> String:
	var item: Dictionary=objects.get(reference["object_uid"],{})
	var name: String=item.get("name",studio.library.assets.get(item.get("asset",""),{}).get("name",reference["object_uid"]))
	return name.replace("_"," ")+" · "+reference["socket"].replace("_"," ")

func refresh() -> void:
	var data: Dictionary=root().data
	var runtime: Node=manager()
	var graph: Dictionary=runtime.graph
	var may_edit: bool=editable()
	var can_enable: bool=may_edit and studio.shared_authority()
	var configured: bool=Plan.enabled(data,kind)
	var settings: Array=[studio.mode,configured,can_enable]
	if settings_stamp!=settings:
		settings_stamp=settings
		enabled.set_pressed_no_signal(configured)
	enabled.disabled=not can_enable
	apply_enabled.disabled=not can_enable
	paused.set_pressed_no_signal(runtime.paused)
	var balance: Dictionary=runtime.report["balance"]
	summary.text=(title+" off" if not configured else ("Next tick estimate" if runtime.forecast else (title+" tick %d")%runtime.tick_count))
	summary.text+="\n%d delivered · %d stored · %d spilled\n%d opening + %d produced = %d delivered + %d closing + %d spilled"%[
		balance["delivered"],runtime.stored(),balance["spill"],balance["opening"],balance["production"],balance["delivered"],balance["closing"],balance["spill"]]
	if runtime.retired_stock>0: summary.text+="\n%d units retired with removed storage"%runtime.retired_stock
	var item: Dictionary=selected_item()
	var uid: String=item.get("uid","")
	var profile: Dictionary=Plan.Profiles.profile(item,studio.library,kind)
	var node: Dictionary=node_for(uid)
	var role: String=profile.get("role","")
	var can_set: bool=may_edit and not role.is_empty() and Layers.editable(data,item,studio.library)
	var signature: Array=[studio.mode,uid,profile,node.duplicate()]
	if facility_stamp!=signature:
		facility_stamp=signature
		facility_enabled.set_pressed_no_signal(node.get("enabled",true))
		quantity.set_value_no_signal(node.get("quantity",profile.get("quantity",0)))
		priority.set_value_no_signal(node.get("priority",profile.get("priority",0)))
	facility.text=("Select a reviewed generator, solar or wind source, battery, relay or consumer." if kind=="power" else "Select a reviewed well, pump, tower, home or shop.") if role.is_empty() else role.capitalize()
	if not node.is_empty(): facility.text+=" · "+runtime.describe(uid)
	elif role=="storage": facility.text+=" · %d units capacity"%profile["capacity"]
	facility_enabled.disabled=not can_set
	quantity.editable=can_set and role in ["source","consumer"]
	priority.editable=can_set and role=="consumer"
	apply_facility_button.disabled=not can_set
	remove_facility_button.disabled=not can_set or node.is_empty()
	var options_signature: Array=[studio.mode,runtime.revision,may_edit]
	if ports_stamp!=options_signature:
		ports_stamp=options_signature
		var objects: Dictionary=Plan.objects(data)
		var ports: Array=[]
		for id in graph["ports"]:
			for socket in graph["ports"][id]:
				var reference: Dictionary={"object_uid":id,"socket":socket}
				ports.append([port_label(reference,objects),reference])
		ports.sort_custom(func(a: Array,b: Array)->bool:
			var comparison: int=a[0].naturalnocasecmp_to(b[0])
			return Plan.Connector.socket_key(a[1])<Plan.Connector.socket_key(b[1]) if comparison==0 else comparison<0)
		choose_options(first,ports,"Choose source port")
		choose_options(second,ports,"Choose target port")
		var runs: Array=[]
		for key in graph["links"]:
			var link: Dictionary=graph["links"][key]
			runs.append([port_label(link["from"],objects)+" ↔ "+port_label(link["to"],objects),key])
		choose_options(links,runs,"Choose a "+run_name)
		navigation_note=""
	update_actions()

func port_selected(_index: int) -> void:
	navigation_note=""
	update_actions()

func cycle(step: int) -> void:
	if not panel.is_visible_in_tree() or not editable() or studio.modal_visible(): return
	tick(0)
	var a: Variant=choice(first)
	if a==null: return
	var objects: Dictionary=Plan.objects(root().data)
	var targets: Array[int]=[]
	for index in range(1,second.item_count):
		var b: Dictionary=second.get_item_metadata(index)
		if join_reason(a,b,objects).is_empty(): targets.append(index)
	if targets.is_empty():
		navigation_note="No compatible target. Check the selected port's reason."
	else:
		var current: int=targets.find(second.selected)
		var index: int=posmod(current+step if current>=0 else (0 if step>0 else -1),targets.size())
		second.select(targets[index])
		navigation_note="Compatible target %d of %d"%[index+1,targets.size()]
	update_actions()

func update_actions() -> void:
	var graph: Dictionary=manager().graph
	var a: Variant=choice(first)
	var b: Variant=choice(second)
	var edge: Dictionary=graph["links"].get(choice(links),{})
	reviewed=proposal(a,b)
	var why: String=reviewed["reason"]
	join_button.disabled=not why.is_empty()
	first.disabled=not editable()
	second.disabled=not editable()
	links.disabled=not editable()
	for action in navigation: action.disabled=not editable() or a==null
	remove_link_button.disabled=not editable() or edge.is_empty()
	status.text="Connect the two marked ports." if why.is_empty() else why
	if reviewed.has("positions"):
		status.text=title+" · "+first.get_item_text(first.selected)+" → "+second.get_item_text(second.selected)+"\n"+reviewed["mating"]+"\n"+status.text
	if not navigation_note.is_empty(): status.text+="\n"+navigation_note
	if not edge.is_empty() and not edge["reason"].is_empty(): status.text+="\nSelected run · "+edge["reason"]
	second.tooltip_text=status.text
	join_button.tooltip_text=status.text

func join_reason(a: Variant,b: Variant,objects: Dictionary={}) -> String:
	if not editable(): return "Edit "+kind+" connections from the exterior city."
	if a==null: return "Choose a source port."
	if b==null: return "Choose a target port or use Next target."
	if objects.is_empty(): objects={a["object_uid"]:root().object(a["object_uid"]),b["object_uid"]:root().object(b["object_uid"])}
	if not item_editable(a["object_uid"],objects) or not item_editable(b["object_uid"],objects):
		return "Show and unlock both endpoint objects and layers."
	var reason: String=Plan.join_reason(manager().graph,a,b)
	if not reason.is_empty(): return reason
	if not studio.shared_authority():
		var actor: String=studio.cooperative_tools.session.local_id
		for area in root().data.get("protected_areas",[]):
			if area["owner"]==actor: continue
			var bounds: Rect2=Protection.rect(area).grow(.001)
			for item in [objects[a["object_uid"]],objects[b["object_uid"]]]:
				if bounds.intersects(Protection.object_rect(item,studio.mode,studio.library)):
					return "Protected area · "+area["name"]+". The host can assign editing access."
	if root().data.get("utility_edges",[]).size()>=Plan.MAX_EDGES: return "This city has reached its utility connection limit."
	return ""

func proposal(a: Variant,b: Variant) -> Dictionary:
	var result: Dictionary={"from":a,"to":b,"reason":join_reason(a,b)}
	if a==null or b==null: return result
	var ports: Dictionary=manager().graph
	var start: Dictionary=Plan.endpoint(ports,a)
	var end: Dictionary=Plan.endpoint(ports,b)
	if start.is_empty() or end.is_empty(): return result
	var port_names: Dictionary={"out":"output","in":"input","tap":"tap"}
	result["positions"]=[start["position"],end["position"]]
	result["normals"]=[start["normal"],end["normal"]]
	var source_role: String=port_names[start["polarity"]]
	var target_role: String=port_names[end["polarity"]]
	result["mating"]="Mating · %s %s %s"%[source_role,"↔" if source_role==target_role else "←" if source_role=="input" or target_role=="output" else "→",target_role]
	return result

func preview() -> Dictionary:
	if not panel.is_visible_in_tree() or not editable() or not reviewed.has("positions"): return {}
	return reviewed

func markers() -> Array:
	var draft: Dictionary=preview()
	if draft.is_empty() or not markers_visible.button_pressed: return []
	var result: Array=[]
	for index in 2:
		var position: Array=draft["positions"][index]
		var normal: Vector3=draft["normals"][index]
		var at: Vector2=project(position)
		var tip: Vector2=project([position[0]+normal.x,position[1]+normal.y,position[2]+normal.z])
		var reference: Dictionary=draft["from"] if index==0 else draft["to"]
		var label: String=("Source " if index==0 else "Target ")+reference["socket"].replace("_"," ")
		result.append({"at":at,"direction":tip-at if tip.is_finite() and at.is_finite() else Vector2.ZERO,
			"kind":kind,"label":label,"source":index==0,"blocked":index==1 and not draft["reason"].is_empty()})
	return result

func project(position: Array) -> Vector2:
	if studio.mode=="3d" and studio.worlds["3d"].camera.is_position_behind(Plan.Connector.vector(position)): return Vector2.INF
	return studio.overlay_position(position,0.0)

func begin() -> Dictionary:
	if not editable() or studio.modal_visible(): return {}
	studio.finish_edit(studio.canvas_pointer())
	root().finish_checkpoint()
	tick(0)
	return root().data.duplicate(true)

func commit(candidate: Dictionary) -> bool:
	var doc: RefCounted=root()
	if candidate==doc.data: return false
	if not Plan.valid(candidate,studio.library,0):
		studio.status.text=title+" settings contain an unsupported or conflicting record."
		return false
	if not studio.shared_authority():
		var before: Dictionary={"2d":root("2d").data,"3d":root("3d").data}
		var next: Dictionary=before.duplicate()
		next[studio.mode]=candidate
		var reason: String=Protection.allowed(before,next,studio.cooperative_tools.session.local_id,studio.library)
		if not reason.is_empty():
			studio.status.text=reason
			status.text=reason
			return false
	var old: Dictionary=doc.data
	doc.data=candidate
	if not doc.record_completed_change(old):
		if not doc.economy_error.is_empty(): studio.status.text=doc.economy_error
		return false
	studio.changed()
	tick(0)
	return true

func apply_settings() -> void:
	if not studio.shared_authority(): return
	var on: bool=enabled.button_pressed
	var candidate: Dictionary=begin()
	if candidate.is_empty() or Plan.enabled(candidate,kind)==on: return
	if not candidate.has("utilities"): candidate["utilities"]={}
	candidate["utilities"][kind]=on
	commit(candidate)

func apply_facility() -> void:
	var item: Dictionary=selected_item()
	var profile: Dictionary=Plan.Profiles.profile(item,studio.library,kind)
	if profile.is_empty() or not Layers.editable(root().data,item,studio.library): return
	var existing: Dictionary=node_for(item["uid"])
	var node: Dictionary={"uid":existing["uid"] if not existing.is_empty() else Identity.identity(),
		"object_uid":item["uid"],"kind":kind,"enabled":facility_enabled.button_pressed}
	if profile["role"] in ["source","consumer"]: node["quantity"]=int(quantity.value)
	if profile["role"]=="consumer": node["priority"]=int(priority.value)
	var candidate: Dictionary=begin()
	if candidate.is_empty(): return
	if not candidate.has("utility_nodes"): candidate["utility_nodes"]=[]
	var index: int=candidate["utility_nodes"].find(existing)
	if index>=0: candidate["utility_nodes"][index]=node
	elif candidate["utility_nodes"].size()<Plan.MAX_NODES: candidate["utility_nodes"].append(node)
	else:
		studio.status.text="This city has reached its utility facility limit."
		return
	commit(candidate)

func remove_facility() -> void:
	var item: Dictionary=selected_item()
	if item.is_empty() or not Layers.editable(root().data,item,studio.library): return
	var node: Dictionary=node_for(item["uid"])
	if node.is_empty(): return
	var candidate: Dictionary=begin()
	if candidate.is_empty(): return
	candidate["utility_nodes"].erase(node)
	Plan.normalize(candidate,studio.library)
	commit(candidate)

func connect_ports() -> void:
	var a: Variant=choice(first)
	var b: Variant=choice(second)
	var shown: Dictionary=reviewed
	var candidate: Dictionary=begin()
	if candidate.is_empty(): return
	var actual: Dictionary=proposal(a,b)
	if not actual["reason"].is_empty():
		studio.status.text=actual["reason"]
		return
	if shown!=actual or a!=choice(first) or b!=choice(second):
		studio.status.text="Connection changed. Review the updated ports before connecting."
		return
	if not candidate.has("utility_edges"): candidate["utility_edges"]=[]
	candidate["utility_edges"].append({"uid":Identity.identity(),"kind":kind,"enabled":true,"from":a.duplicate(),"to":b.duplicate()})
	if commit(candidate): studio.status.text=title+" connection added."

func disconnect_run() -> void:
	var id: Variant=choice(links)
	var candidate: Dictionary=begin()
	if candidate.is_empty() or id==null: return
	var link: Dictionary=manager().graph["links"].get(id,{})
	if link.is_empty(): return
	var objects: Dictionary=Plan.objects(candidate)
	for side in ["from","to"]:
		var uid: String=link[side]["object_uid"]
		if objects.has(uid) and not item_editable(uid,objects): return
	var field: String="connections" if id[0] else "utility_edges"
	candidate[field]=candidate[field].filter(func(entry: Dictionary)->bool:return entry["uid"]!=id[1])
	commit(candidate)
