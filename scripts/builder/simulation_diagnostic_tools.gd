extends RefCounted

const Common=preload("res://scripts/builder/simulation_diagnostics.gd")
const Sources=preload("res://scripts/builder/simulation_diagnostic_sources.gd")
const Overlay=preload("res://scripts/builder/simulation_diagnostic_overlay.gd")
const Setup=preload("res://scripts/builder/interaction_setup_plan.gd")
const Layers=preload("res://scripts/builder/layers.gd")
const COMMANDS: Dictionary={"traffic":"traffic","transit":"transit","services":"services","residents":"citizens",
	"fixtures":"interaction_setup","zoning":"zoning","challenges":"challenges","deliveries":"deliveries",
	"vehicle_care":"vehicle_care","businesses":"businesses","markets":"markets","water":"water","power":"power"}
var studio: Control
var panel: ScrollContainer
var selector: OptionButton
var legend: Label
var summary: Label
var results: ItemList
var detail: Label
var inspect: Button
var overlay: Control
var kind: String="off"
var epoch: int=0
var active_scope: String=""
var elapsed: float=0
var selected: Array=[]
var snapshot: Dictionary={}
var list_stamp: int=-1
var fixture_stamp: int=-1
var fixture_report: Dictionary={}
var projection_stamp: int=-1

func _init(editor: Control) -> void:
	studio=editor
	overlay=Overlay.new()
	overlay.studio=studio
	studio.canvas.add_child(overlay)
	studio.canvas.move_child(overlay,studio.overlay.get_index())
	panel=ScrollContainer.new()
	panel.name="Diagnostics"
	panel.follow_focus=true
	panel.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	studio.workspace_layout.tabs.add_child(panel)
	var content:=VBoxContainer.new()
	content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	panel.add_child(content)
	studio.label(content,"Simulation diagnostics",17)
	selector=OptionButton.new()
	selector.fit_to_longest_item=false
	selector.clip_text=true
	selector.accessibility_name="Simulation overlay"
	content.add_child(selector)
	for key in Common.OVERLAYS:
		selector.add_item(Common.OVERLAYS[key][0])
		selector.set_item_metadata(selector.item_count-1,key)
	selector.item_selected.connect(func(index: int): choose(selector.get_item_metadata(index)))
	selector.focus_entered.connect(reveal.bind(selector))
	legend=studio.label(content,"Choose an overlay to inspect the current simulation.",12)
	legend.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	summary=studio.label(content,"",12)
	summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	summary.accessibility_name="Diagnostic findings summary"
	results=ItemList.new()
	results.custom_minimum_size=Vector2(120,112)
	results.accessibility_name="Simulation findings"
	results.allow_reselect=true
	results.item_selected.connect(select_row)
	results.item_activated.connect(func(index: int): navigate(row_at(index),true))
	results.focus_entered.connect(reveal.bind(results))
	content.add_child(results)
	detail=studio.label(content,"",12)
	detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	detail.focus_mode=Control.FOCUS_ALL
	detail.accessibility_name="Diagnostic finding details"
	detail.focus_entered.connect(reveal.bind(detail))
	inspect=Button.new()
	inspect.text="Open controls"
	inspect.accessibility_name="Open controls for this finding"
	inspect.disabled=true
	inspect.pressed.connect(func(): navigate(chosen_row(),true))
	inspect.focus_entered.connect(reveal.bind(inspect))
	content.add_child(inspect)

func reveal(control: Control) -> void:
	panel.ensure_control_visible(control)
	await studio.get_tree().process_frame
	if not is_instance_valid(control) or not control.has_focus(): return
	var scroll: ScrollContainer=studio.accessibility_settings.root_scroll
	if not is_instance_valid(scroll) or not scroll.is_ancestor_of(control): return
	scroll.ensure_control_visible(control)
	await studio.get_tree().process_frame
	if not is_instance_valid(control) or not control.has_focus(): return
	var shell: RefCounted=studio.consumer_shell
	if shell and not shell.active and shell.expert_return.visible:
		var back: Rect2=shell.expert_return.get_global_rect()
		var bounds: Rect2=control.get_global_rect()
		if bounds.intersects(back): scroll.scroll_vertical+=ceili(bounds.end.y-back.position.y+8)

func show() -> void:
	studio.workspace_presets.set_focus(false)
	studio.workspace_layout.inspector_toggle.button_pressed=true
	studio.workspace_layout.tabs.current_tab=panel.get_index()
	selector.grab_focus.call_deferred()

func choose(value: String) -> void:
	if not Common.OVERLAYS.has(value) or kind==value: return
	kind=value
	for index in selector.item_count:
		if selector.get_item_metadata(index)==kind: selector.select(index); break
	legend.text=("Choose an overlay to inspect the current simulation." if kind=="off" else Common.OVERLAYS[kind][1]+
		" Triangles mark issues. Diamonds mark pending checks. Circles mark locations.")
	invalidate()

func scope_key() -> String:
	if studio.interior_tools.editing():
		return Common.scope(studio.mode,studio.interior_tools.uid,studio.current().floor_uid)
	var walk: Node=studio.worlds[studio.mode].exploration
	if walk.interior: return Common.scope(studio.mode,walk.interior_uid,walk.active_floor())
	if studio.current().data.get("interior_room",false): return Common.scope(studio.mode,"standalone","ground")
	return Common.scope(studio.mode)

func invalidate() -> void:
	epoch+=1
	snapshot={}
	selected=[]
	overlay.clear()
	inspect.disabled=true
	fixture_stamp=-1
	list_stamp=-1
	elapsed=Common.PERIOD
	results.clear()
	summary.text="" if kind=="off" else "Waiting for the current simulation."
	detail.text=""

func suspended() -> bool:
	var world: Node=studio.worlds[studio.mode]
	return (world.exploration.photo.active or studio.modal_visible() or studio.stroke or studio.road_drawing
		or studio.transform_handles.dragging or studio.ground_brush.drawing or studio.terrain_tools.drawing
		or studio.zone_tools.drawing or studio.cooperative_tools.drawing)

func tick(delta: float) -> void:
	if kind=="off": return
	var next_scope: String=scope_key()
	if active_scope!=next_scope:
		active_scope=next_scope
		invalidate()
	if suspended():
		overlay.hide()
		elapsed=Common.PERIOD
		return
	elapsed+=delta
	if elapsed>=Common.PERIOD:
		elapsed=0
		refresh()
	overlay.contrast=studio.accessibility_settings.high_contrast
	overlay.text_scale=studio.accessibility_settings.text_scale
	overlay.visible=snapshot.get("shapes",0)>0
	if overlay.visible:
		var camera: Node=studio.worlds[studio.mode].camera
		var projection: Variant=studio.viewport.get_canvas_transform() if studio.mode=="2d" else [camera.global_transform,camera.fov,camera.size,camera.projection]
		var stamp: int=hash([projection,studio.viewport.size,overlay.size,overlay.contrast,overlay.text_scale])
		if stamp!=projection_stamp:
			projection_stamp=stamp
			overlay.queue_redraw()

func interaction_report() -> Dictionary:
	var setup: RefCounted=studio.prop_tools.setup
	var current: Dictionary=setup.context()
	if current.is_empty(): return {}
	var live: Dictionary=setup.live_state()
	var options: Dictionary=current["options"].duplicate()
	options["visual"]=true
	var stamp: int=hash([Setup.revision(current["room"],studio.library,options),live["tokens"],live["animation"]])
	if stamp!=fixture_stamp:
		fixture_stamp=stamp
		fixture_report=Setup.report(current["room"],studio.library,options,live["pool"],live["animation"])
	return fixture_report

func refresh() -> void:
	var source:=Sources.new(studio,active_scope,epoch)
	snapshot=source.collect(kind,interaction_report() if kind=="fixtures" else {})
	var ordered: Array[Dictionary]=[]
	for severity in ["error","warning","pending","info","ok"]:
		for row in snapshot["rows"]:
			if row["severity"]==severity: ordered.append(row)
	snapshot["rows"]=ordered
	overlay.rows=ordered
	var stamp: int=hash(ordered.map(func(row: Dictionary)->Array:return [Common.identity(row),row["severity"],row["details"]["title"],row["details"]["message"]]))
	if stamp!=list_stamp:
		list_stamp=stamp
		var previous: float=results.get_v_scroll_bar().value
		results.clear()
		var index: int=-1
		for row in ordered:
			var added: int=results.add_item(Common.label(row))
			results.set_item_tooltip(added,row["details"]["message"])
			if Common.identity(row)==selected: index=added
		if index>=0: results.select(index)
		results.get_v_scroll_bar().set_deferred("value",previous)
	summary.text="No current findings." if ordered.is_empty() else "1 finding" if ordered.size()==1 else "%d findings"%ordered.size()
	if snapshot["limited"]: summary.text+=" · Display limit reached"
	var chosen: Dictionary=chosen_row()
	if chosen.is_empty():
		selected=[]
		detail.text="Select a finding to frame it. Enter opens its controls."
	else: detail.text=chosen["details"]["message"]
	inspect.disabled=chosen.is_empty() or chosen["details"]["entity"].is_empty() or studio.walking
	overlay.selected=selected
	overlay.queue_redraw()

func row_at(index: int) -> Dictionary:
	var rows: Array=snapshot.get("rows",[])
	return rows[index] if index>=0 and index<rows.size() else {}

func chosen_row() -> Dictionary:
	for row in snapshot.get("rows",[]):
		if Common.identity(row)==selected: return row
	return {}

func select_row(index: int) -> void:
	var row: Dictionary=row_at(index)
	if row.is_empty(): return
	selected=Common.identity(row)
	overlay.selected=selected
	overlay.queue_redraw()
	detail.text=row["details"]["message"]
	inspect.disabled=row["details"]["entity"].is_empty() or studio.walking
	navigate(row,false)

func current_row(row: Dictionary) -> bool:
	if row.is_empty() or row["revision"].get_slice(":",0)!=str(epoch) or scope_key()!=active_scope: return false
	for candidate in snapshot.get("rows",[]):
		if candidate["revision"]==row["revision"] and Common.identity(candidate)==Common.identity(row): return true
	return false

func navigate(row: Dictionary,open_controls: bool) -> bool:
	if row.is_empty() or row["details"]["entity"].is_empty(): return false
	if studio.prop_tools.setup.blocked():
		detail.text=row["details"]["message"]+" Return to Build and finish the current edit to inspect it."
		return false
	if not current_row(row):
		detail.text="The simulation changed. Select a current finding."
		return false
	refresh()
	if not current_row(row):
		detail.text="The simulation changed. Select a current finding."
		return false
	var details: Dictionary=row["details"]
	var uid: String=row["object_uid"]
	if details["entity"]=="fixture":
		if open_controls: studio._command("interaction_setup",null)
		return studio.prop_tools.setup.focus_record(details["setup"],open_controls)
	var anchor: Variant=details.get("anchor")
	var doc: RefCounted=studio.current()
	var item: Dictionary={}
	match details["entity"]:
		"object","service_target":
			item=doc.object(uid)
			if item.is_empty(): return false
			anchor=Vector3(item["position"][0],item["position"][1],item["position"][2])
		"lot":
			if not doc.data.get("zones",[]).any(func(lot: Dictionary)->bool:return lot["uid"]==uid): return false
		"line":
			if not doc.data.get("transit_lines",[]).any(func(line: Dictionary)->bool:return line["uid"]==uid): return false
		"traffic_actor":
			var found: bool=false
			for vehicle in studio.traffic_tools.managers[studio.mode].vehicles:
				if vehicle["id"]!=uid or not is_instance_valid(vehicle["actor"]): continue
				var position: Variant=vehicle["actor"].position
				anchor=Vector3(position.x,position.y,0) if studio.mode=="2d" else position
				found=true
				break
			if not found: return false
	if anchor is Vector3: frame(anchor)
	if not open_controls: return true
	if not item.is_empty() and Layers.editable(doc.data,item,studio.library):
		studio.selected_uid=uid
		studio.selected_uids.assign([uid])
		studio.selected_cell=null
		studio.refresh_controls()
	studio._command(COMMANDS[kind],null)
	select_control(details["entity"],uid,details)
	studio.status.text=details["message"]
	return true

func frame(at: Vector3) -> void:
	var world: Node=studio.worlds[studio.mode]
	if studio.mode=="2d": world.camera.position=Vector2(at.x,at.y-at.z*8.0)
	else:
		world.target=at
		world.update_camera()

func select_control(entity: String,uid: String,details: Dictionary) -> void:
	match entity:
		"utility_run":
			var tools: RefCounted=studio.power_tools if kind=="power" else studio.utility_tools
			var runs: OptionButton=tools.links
			for index in runs.item_count:
				if runs.get_item_metadata(index)==details.get("key"):
					runs.select(index)
					tools.update_actions()
					runs.grab_focus()
					break
		"lot":
			studio.zone_tools.selected=uid
			studio.zone_tools.fields_stamp=0
			studio.zone_tools.refresh()
		"line":
			studio.transit_tools.selected=uid
			studio.transit_tools.authored_stamp=0
			studio.transit_tools.refresh_authored()
			studio.transit_tools.load_line()
		"service_target":
			var tools: RefCounted=studio.service_tools
			for index in tools.targets.item_count:
				if tools.targets.get_item_metadata(index)==uid: tools.targets.select(index); break
			var service: int=tools.Plan.KINDS.find(details.get("kind",""))
			if service>=0: tools.request_kind.select(service)
			tools.tick(.4)
		"traffic_actor":
			var tools: RefCounted=studio.traffic_tools
			tools.tick(.4)
			var vehicles: Array=tools.managers[studio.mode].vehicles
			for index in vehicles.size():
				if vehicles[index]["id"]==uid: tools.list.select(index); break
