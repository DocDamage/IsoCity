extends RefCounted

const Setup=preload("res://scripts/builder/interaction_setup_plan.gd")
const Floors=preload("res://scripts/builder/floor_plan.gd")
const Layers=preload("res://scripts/builder/layers.gd")
var studio: Control
var page: ScrollContainer
var panel: VBoxContainer
var results: ItemList
var summary: Label
var detail: Label
var show_passed: CheckButton
var inspect_button: Button
var stamp: int=-1
var active_report: Dictionary={}

func _init(host: Control,scroll: ScrollContainer,parent: VBoxContainer) -> void:
	studio=host;page=scroll;page.follow_focus=true
	var open_button:=Button.new();open_button.text="Check interaction setup";open_button.accessibility_name="Check interaction setup";parent.add_child(open_button)
	open_button.pressed.connect(func():
		if panel.visible:panel.hide()
		else:open_review()
	)
	panel=VBoxContainer.new();parent.add_child(panel);panel.hide()
	summary=studio.label(panel,"Select one fixture or a furnished building.",12);summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;summary.accessibility_name="Interaction setup summary"
	show_passed=CheckButton.new();show_passed.text="Include passed checks";panel.add_child(show_passed);show_passed.toggled.connect(func(_on: bool):stamp=-1;refresh())
	results=ItemList.new();results.custom_minimum_size=Vector2(140,156);results.accessibility_name="Interaction setup checklist";results.tooltip_text="Enter to inspect the saved scope. Tab for the full issue text.";results.allow_reselect=true;panel.add_child(results)
	results.item_selected.connect(select_result)
	results.item_activated.connect(func(index: int):inspect_result(index,true))
	detail=studio.label(panel,"Select a check for details.",12);detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;detail.focus_mode=Control.FOCUS_ALL;detail.accessibility_name="Interaction setup issue details"
	inspect_button=Button.new();inspect_button.text="Inspect fixture";inspect_button.accessibility_name="Inspect fixture and floor";inspect_button.clip_text=true;panel.add_child(inspect_button)
	inspect_button.pressed.connect(func():
		var selected: PackedInt32Array=results.get_selected_items()
		if not selected.is_empty():inspect_result(selected[0],true)
	)
	var retry:=Button.new();retry.text="Check again";panel.add_child(retry);retry.pressed.connect(func():stamp=-1;refresh())

func blocked() -> bool:
	return studio.walking or studio.modal_visible() or studio.stroke or studio.moved_selection or studio.marquee_active or studio.road_drawing or studio.panning or studio.orbiting or studio.transform_handles.dragging or studio.ground_brush.drawing or studio.zone_tools.drawing or studio.cooperative_tools.drawing or not studio.prop_tools.dirty.is_empty()

func open_review() -> bool:
	if blocked():studio.status.text="Return to Build and finish the current edit before checking setup.";return false
	panel.show();stamp=-1;refresh();call_deferred("focus_review");return true

func focus_review() -> void:
	if not is_instance_valid(studio) or not results.is_visible_in_tree():return
	results.grab_focus()

func context() -> Dictionary:
	if studio.documents.is_empty() or studio.selected_uids.size()>1:return {}
	var doc: RefCounted=studio.current();var selected: Dictionary=doc.object(studio.selected_uid)
	if studio.interior_tools.editing():
		return {"room":doc.canonical.data,"options":{"building":studio.interior_tools.uid,"floor":doc.floor_uid,"object":selected.get("uid","")}}
	if selected.is_empty():return {}
	if selected.get("interior") is Dictionary:return {"room":selected["interior"],"options":{"building":selected["uid"]}}
	return {"room":doc.data,"options":{"city":not doc.data.get("interior_room",false),"floor":"ground","object":selected["uid"]}}

func live_state() -> Dictionary:
	var world: Node=studio.worlds[studio.mode];var pool: RefCounted=world.get_meta("activity_reservations",null) if world.has_meta("activity_reservations") else null
	var manager: Node=studio.citizen_tools.managers.get(studio.mode)
	if is_instance_valid(manager) and manager.activities:pool=manager.activities.scheduler.reservations
	var tokens: Array=[]
	if pool:
		for key in pool.entries.keys():tokens.append([key,pool.current(key).get("token",0)])
	var animation: Dictionary={}
	if studio.mode=="2d" and world.player.authored_animation:
		var animator: RefCounted=world.player.authored_animation;animation={"clips":animator.clips,"actions":animator.actions}
	return {"pool":pool,"tokens":tokens,"animation":animation}

func refresh() -> void:
	if not panel.is_visible_in_tree() or not page.is_visible_in_tree() or blocked():return
	var scope: Dictionary=context();var live: Dictionary=live_state()
	var revision: String="" if scope.is_empty() else Setup.revision(scope["room"],studio.library,scope["options"])
	var next: int=hash([revision,show_passed.button_pressed,live["tokens"],live["animation"]])
	if next==stamp:return
	stamp=next;var old_selection: PackedInt32Array=results.get_selected_items();var old_row: Dictionary=results.get_item_metadata(old_selection[0]) if not old_selection.is_empty() else {};results.clear()
	active_report={} if scope.is_empty() else Setup.report(scope["room"],studio.library,scope["options"],live["pool"],live["animation"])
	var rows: Array=active_report.get("records",[]);var issues: int=0;var preserved: int=-1
	for row in rows:
		if row["severity"] in ["error","warning"]:issues+=1
		if row["severity"]=="ok" and not show_passed.button_pressed:continue
		var values: Dictionary=row["details"];var name: String=check_name(row["code"])
		var index: int=results.add_item(("Pass · " if row["severity"]=="ok" else "")+name+" · "+values["object_name"])
		results.set_item_metadata(index,row);results.set_item_tooltip(index,values["floor_name"]+" · "+values["message"])
		if row["scope"]==old_row.get("scope") and row["object_uid"]==old_row.get("object_uid") and row["code"]==old_row.get("code"):preserved=index
	summary.text="Select one fixture or a furnished building." if scope.is_empty() else "%d fixtures · %d issues%s"%[active_report["objects"],issues," · Select a specific fixture for more checks" if active_report["limited"] else ""]
	inspect_button.disabled=preserved<0
	detail.text="No problems in the current setup checks." if not rows.is_empty() and results.item_count==0 else "Select a check to frame its fixture. Inspect opens its saved room or floor."
	if preserved>=0:results.select(preserved);describe(preserved)

func check_name(code: String) -> String:
	return {"action":"Action","animation":"Pose","missing_asset":"Missing asset","hidden":"Hidden fixture","protected":"Locked or hidden","required_target":"Linked device","station_capacity":"Capacity","station_overlap":"Shared approach","station_support":"Walking surface","station_clearance":"Standing space","approach_route":"Entrance route","return_route":"Return route"}.get(code,"Setup check")

func describe(index: int) -> void:
	var row: Dictionary=results.get_item_metadata(index);var values: Dictionary=row["details"]
	detail.text=values["object_name"]+" · "+values["floor_name"]+"\n"+values["message"];inspect_button.disabled=false

func select_result(index: int) -> void:
	describe(index);inspect_result(index,false)

func frame(item: Dictionary) -> void:
	var world: Node=studio.worlds[studio.mode];var at: Array=item["position"]
	if studio.mode=="2d":world.camera.position=Vector2(at[0],at[1])
	else:world.target=Vector3(at[0],at[1],at[2]);world.update_camera()

func inspect_result(index: int,open_scope: bool) -> bool:
	if index<0 or index>=results.item_count:return false
	return focus_record(results.get_item_metadata(index),open_scope)

func focus_record(record: Dictionary,open_scope: bool) -> bool:
	if blocked():detail.text="Finish the current edit before framing a fixture.";return false
	var current: Dictionary=context();var values: Dictionary=record["details"]
	if current.is_empty() or values["mode"]!=studio.mode or record["revision"]!=Setup.revision(current["room"],studio.library,current["options"]):
		stamp=-1;refresh();detail.text="The setup changed. Select a current check and try again.";return false
	var doc: RefCounted=studio.current();var building: String=values["building_uid"];var floor_uid: String=values["floor_uid"];var uid: String=record["object_uid"]
	if record["scope"].begins_with("room:") and building!="standalone":
		if not studio.interior_tools.editing():
			var host: Dictionary=doc.object(building)
			if host.is_empty():return false
			frame(host)
			if not open_scope:return true
			if not Layers.editable(doc.data,host,studio.library):detail.text="Show and unlock this building before opening its room.";return false
			studio.interior_tools.start(building,floor_uid)
			if not studio.interior_tools.editing():return false
		elif studio.interior_tools.uid!=building:return false
		elif doc.floor_uid!=floor_uid:
			if not open_scope:return false
			studio.interior_tools.floor_tools.switch_floor(floor_uid)
		doc=studio.current()
	var item: Dictionary=doc.object(uid)
	if item.is_empty():return false
	frame(item)
	if open_scope:
		if Layers.editable(doc.data,item,studio.library):studio.selected_uid=uid;studio.selected_uids.assign([uid]);studio.refresh_controls()
		studio.workspace_layout.tabs.current_tab=page.get_index()
		stamp=-1;refresh()
	return true
