extends RefCounted
const Plan=preload("res://scripts/builder/scenario_plan.gd")
const Runtime=preload("res://scripts/builder/scenario_runtime.gd")
const Document = preload("res://scripts/builder/document.gd")
var studio: Control
var panel: ScrollContainer
var choice: OptionButton
var description: Label
var status: Label
var goals: Label
var assets: ItemList
var badge: Label
var managers: Dictionary={}
var dirty: bool=true
var elapsed: float=0
var fields_mode: String=""
var construction_fields: VBoxContainer
var construction_site: OptionButton
var construction_supply: OptionButton
var construction_stamp: int=0
var drill_fields: VBoxContainer
var drill_choices: Dictionary = {}
var drill_stamp: int = 0
func _init(host: Control) -> void:
	studio=host; panel=ScrollContainer.new(); panel.name="Challenges"; panel.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; panel.follow_focus=true; studio.workspace_layout.tabs.add_child(panel)
	var box:=VBoxContainer.new(); box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; box.add_theme_constant_override("separation",8); panel.add_child(box)
	studio.label(box,"Scenario challenges",17)
	choice=OptionButton.new(); choice.fit_to_longest_item=false; choice.clip_text=true; box.add_child(choice)
	for id in Plan.definitions(): choice.add_item(Plan.definitions()[id]["title"]); choice.set_item_metadata(choice.item_count-1,id)
	choice.item_selected.connect(func(_index: int): drill_stamp = 0; refresh_description())
	description=studio.label(box,"",12); description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	construction_fields=VBoxContainer.new()
	box.add_child(construction_fields)
	construction_supply=station_choice("Masonry supply container")
	construction_site=station_choice("Construction site office")
	drill_fields = VBoxContainer.new()
	box.add_child(drill_fields)
	for entry in [["station", "Response station"], ["desk", "Dispatch equipment"], ["incident", "Incident building"],
		["kit", "Training kit"], ["perimeter_0", "First perimeter point"], ["perimeter_1", "Second perimeter point"],
		["subject", "Training participant"]]:
		var row := VBoxContainer.new()
		drill_fields.add_child(row)
		drill_choices[entry[0]] = station_choice(entry[1], row)
	button(drill_fields, "Build the chosen practice drill", build_drill)
	var help_drill: Label = studio.label(drill_fields, "A practice drill needs a blank city. It adds the selected training site and enables manual City Services. In Walk, use Interact at the marked objectives. Training progress and receipts belong to the session.", 12)
	help_drill.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button(box,"Start / restart chosen challenge",start_challenge)
	button(box,"Stop challenge",stop_challenge)
	status=studio.label(box,"No active challenge",15); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	goals=studio.label(box,"",12); goals.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	button(box,"Check current goals and routes",recheck)
	button(box,"Edit challenge apartment",edit_apartment)
	studio.label(box,"Assets for the chosen challenge",14)
	assets=ItemList.new(); assets.custom_minimum_size=Vector2(180,200); box.add_child(assets)
	button(box,"Place selected goal asset",place_asset)
	var help: Label=studio.label(box,"Starting a neighborhood challenge keeps the current city. For the apartment challenge, select a visible unlocked building, or clear selection to create a starter apartment. Its room is replaced with an unfurnished shell and the city starts a 600-credit budget. Undo restores the previous room, treasury and challenge. Use the goal-asset list to choose furniture, then place it in the room with the normal tools. All construction spending counts toward the allowance; disabling economy, resetting its budget or adding unpaid furniture prevents completion. Income and demolition refunds do not reduce construction spending. Goals always reflect current content, so removing requirements or blocking a path makes them incomplete again. Walking checks use actual entrance approaches and collision geometry, with one route search per update. Elevated or hidden destinations do not count. Exterior route checks wait until you return from interiors.",12); help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	badge=studio.label(studio.mode_badge.get_parent(),"",13); badge.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; badge.hide(); studio.mode_badge.get_parent().move_child(badge,studio.mode_badge.get_index()+1)
	refresh_description()
func button(parent: Node,title: String,callback: Callable) -> void:
	var control:=Button.new(); control.text=title; control.clip_text=true; parent.add_child(control); control.pressed.connect(callback)
func station_choice(title: String, parent: VBoxContainer = null) -> OptionButton:
	if not parent: parent = construction_fields
	studio.label(parent,title,12)
	var field:=OptionButton.new()
	field.fit_to_longest_item=false
	field.clip_text=true
	field.accessibility_name=title
	parent.add_child(field)
	field.focus_entered.connect(reveal_station.bind(field))
	return field
func reveal_station(field: OptionButton) -> void:
	panel.ensure_control_visible(field)
	await studio.get_tree().process_frame
	if not is_instance_valid(field) or not field.has_focus(): return
	var scroll: ScrollContainer=studio.accessibility_settings.root_scroll
	if not is_instance_valid(scroll) or not scroll.is_ancestor_of(field): return
	scroll.ensure_control_visible(field)
	await studio.get_tree().process_frame
	if not is_instance_valid(field) or not field.has_focus(): return
	var shell: RefCounted=studio.consumer_shell
	if not shell or shell.active or not shell.expert_return.visible: return
	var bounds: Rect2=field.get_global_rect()
	var overlay: Rect2=shell.expert_return.get_global_rect()
	if bounds.intersects(overlay): scroll.scroll_vertical+=ceili(bounds.end.y-overlay.position.y+8)
func root_document() -> RefCounted: return studio.interior_tools.root_document(studio.mode)
func start() -> void:
	for mode in ["2d","3d"]:
		var manager:=Runtime.new(); studio.worlds[mode].add_child(manager); managers[mode]=manager
func show(requested: String = "") -> void:
	studio.workspace_presets.set_focus(false)
	if studio.walking: studio.set_walking(false)
	studio.workspace_layout.inspector_toggle.button_pressed = true
	studio.workspace_layout.tabs.current_tab = panel.get_index()
	sync_fields()
	if Plan.Emergency.recognized(requested):
		for index in choice.item_count:
			if choice.get_item_metadata(index) == requested: choice.select(index); break
		drill_stamp = 0
		refresh_description()
		if studio.get_viewport_rect().size.x < 1200 and not studio.consumer_shell.active:
			studio.workspace_layout.library_toggle.button_pressed = false
		choice.grab_focus()
	refresh()
func sync_fields() -> void:
	var id: String=root_document().data.get("scenario",{}).get("id","")
	for index in choice.item_count:
		if choice.get_item_metadata(index)==id: choice.select(index)
	construction_stamp=0
	drill_stamp = 0
	refresh_description(); fields_mode=studio.mode
func refresh_description() -> void:
	var id: String=choice.get_item_metadata(choice.selected); description.text=Plan.definitions()[id]["description"]
	construction_fields.visible=id=="construction"
	drill_fields.visible = Plan.Emergency.recognized(id)
	assets.clear()
	if id=="construction":
		refresh_construction_choices()
		var recipe: Dictionary=Plan.Construction.recipe()
		for key in ["supply","site"]:
			if studio.library.assets.has(recipe.get(key)): add_asset(recipe[key],"Place and configure in Local Deliveries")
	elif drill_fields.visible:
		refresh_drill_choices()
		var recipe: Dictionary = Plan.Emergency.definitions()[id]
		for role in ["station", "desk", "kit", "barriers", "subject"]:
			for asset in recipe.get(role, []):
				if studio.library.assets.has(asset): add_asset(asset, role.capitalize())
		if studio.library.assets.has("2d:House_Blue"): add_asset("2d:House_Blue", "Incident building")
	elif id=="apartment":
		for kind in Plan.definitions()[id]["furniture"]:
			for asset in Plan.definitions()[id]["furniture"][kind]:
				if studio.library.assets.has(asset) and studio.library.assets[asset]["mode"]==studio.mode: add_asset(asset,kind.capitalize())
	else:
		for asset in studio.library.assets:
			var role: String=preload("res://scripts/builder/citizen_plan.gd").role({"asset":asset})
			if not role.is_empty() and studio.library.assets[asset]["mode"]==studio.mode: add_asset(asset,role.capitalize())
func refresh_construction_choices() -> void:
	if not construction_fields.visible: return
	var data: Dictionary=root_document().data
	var recipe: Dictionary=Plan.Construction.recipe()
	var records: Array=data["objects"].filter(func(item: Dictionary)->bool:return item["asset"] in [recipe.get("supply"),recipe.get("site")])
	var config: Dictionary=data.get("scenario",{})
	var stamp: int=hash([studio.mode,records,config])
	if stamp==construction_stamp: return
	var fresh: bool=construction_stamp==0
	construction_stamp=stamp
	for entry in [[construction_supply,"supply","pickup_uid"],[construction_site,"site","host_uid"]]:
		var field: OptionButton=entry[0]
		var previous: String=station_value(field)
		var selected: String=config.get(entry[2],previous) if fresh else previous
		field.clear()
		field.add_item("Choose a placed station")
		field.set_item_metadata(0,"")
		for item in records:
			if item["asset"]!=recipe[entry[1]]: continue
			var asset: Dictionary=studio.library.assets.get(item["asset"],{})
			field.add_item(str(item.get("name",asset.get("name",item["asset"].get_file()))).replace("_"," ")+" · "+item["uid"].right(6))
			var index: int=field.item_count-1
			field.set_item_metadata(index,item["uid"])
			if item["uid"]==selected: field.select(index)
func refresh_drill_choices() -> void:
	if not drill_fields.visible: return
	var id: String = choice.get_item_metadata(choice.selected)
	var recipe: Dictionary = Plan.Emergency.definitions()[id]
	var data: Dictionary = root_document().data
	var config: Dictionary = data.get("scenario", {}) if data.get("scenario", {}).get("id") == id else {}
	var stamp: int = hash([studio.mode, id, data["objects"], data.get("layers", {}), config])
	if stamp == drill_stamp: return
	var fresh: bool = drill_stamp == 0
	drill_stamp = stamp
	for key in drill_choices:
		var field: OptionButton = drill_choices[key]
		var perimeter: bool = key.begins_with("perimeter_")
		var role: String = "perimeter" if perimeter else key
		var index: int = int(key.get_slice("_", 1)) if perimeter else -1
		field.get_parent().visible = (not perimeter or index < int(recipe["perimeter_count"])) and (key != "kit" or recipe.has("kit"))
		if not field.get_parent().visible: continue
		var selected: String = station_value(field)
		if fresh:
			var saved: Array = config.get("perimeter", [])
			selected = (saved[index] if index < saved.size() else "") if perimeter else config.get(key, "")
		field.clear()
		field.add_item("Choose a placed object")
		field.set_item_metadata(0, "")
		for item in data["objects"]:
			if not Plan.Emergency.eligible(recipe, role, item, data, studio.library): continue
			field.add_item(item.get("name", studio.library.assets[item["asset"]]["name"]))
			field.set_item_metadata(field.item_count - 1, item["uid"])
			if item["uid"] == selected: field.select(field.item_count - 1)
		if field.selected < 0: field.select(0)

func drill_selection(id: String) -> Dictionary:
	var result: Dictionary = {"perimeter": []}
	for role in Plan.Emergency.fields(id): result[role] = station_value(drill_choices[role])
	for index in int(Plan.Emergency.definitions()[id]["perimeter_count"]):
		result["perimeter"].append(station_value(drill_choices["perimeter_%d" % index]))
	return result

func build_drill() -> void:
	if not studio.shared_authority() or studio.interior_tools.editing():
		studio.status.text = "The host builds practice drills in the exterior city."
		return
	studio.finish_edit(studio.canvas_pointer())
	studio.set_walking(false)
	var doc: RefCounted = root_document()
	doc.finish_checkpoint()
	var id: String = choice.get_item_metadata(choice.selected)
	var draft: Dictionary = Plan.Emergency.practice(doc.data, studio.library, id, Document.new_uid())
	if not draft["ok"]:
		studio.status.text = draft["reason"]
		return
	var before: Dictionary = doc.data.duplicate(true)
	doc.data = draft["data"]
	var accepted: bool = doc.record_completed_change(before)
	if accepted: doc.economy_error = ""
	studio.changed()
	if not accepted:
		studio.status.text = doc.economy_error
		return
	var spawn: Array = doc.data["spawn"]
	var world: Node = studio.worlds[studio.mode]
	world.player.teleport_to(Vector2(spawn[0], spawn[1]) if studio.mode == "2d" else Vector3(spawn[0], spawn[1], spawn[2]))
	studio.neighborhood_tools.frame(world, Rect2(-16, -20, 72, 40), Vector2i(studio.canvas.size))
	sync_fields()
	studio.status.text = "Practice drill ready. Enter Walk and check in at the marked dispatch desk."

func station_value(field: OptionButton) -> String:
	return str(field.get_item_metadata(field.selected)) if field.selected>=0 else ""
func add_asset(asset: String,kind: String) -> void:
	assets.add_item(kind+" · "+studio.library.assets[asset]["name"]); assets.set_item_metadata(assets.item_count-1,asset)
func commit(before: Dictionary) -> void:
	root_document().record_completed_change(before,true); studio.changed(); dirty=true; refresh()
func start_challenge() -> void:
	if not studio.shared_authority(): studio.status.text="The host manages shared challenge settings."; return
	if studio.interior_tools.editing(): studio.status.text="Return to the city before starting a challenge."; return
	studio.finish_edit(studio.canvas_pointer()); studio.set_walking(false)
	var doc: RefCounted=root_document(); doc.finish_checkpoint()
	var id: String=choice.get_item_metadata(choice.selected)
	var host_uid: String=studio.selected_uid if id=="apartment" else station_value(construction_site) if id=="construction" else ""
	var pickup: String=station_value(construction_supply) if id=="construction" else ""
	var position: Array=studio.worlds[studio.mode].point(studio.canvas.size*.5,true,0)
	var value: Dictionary=Plan.begin(doc.data,id,studio.library,Document.new_uid(),host_uid,position,pickup,drill_selection(id) if Plan.Emergency.recognized(id) else {})
	if not value["ok"]: studio.status.text=value["reason"]; return
	var before: Dictionary=doc.data.duplicate(true); doc.data=value["data"]
	studio.selected_uid=""; studio.selected_uids.clear(); studio.selected_cell=null
	commit(before)
	if studio.economy_tools: studio.economy_tools.reset()
	studio.status.text="Challenge started. Undo restores the previous city and treasury."
func stop_challenge() -> void:
	if not studio.shared_authority(): studio.status.text="The host manages shared challenge settings."; return
	if studio.interior_tools.editing(): studio.status.text="Return to the city before stopping the challenge."; return
	studio.finish_edit(studio.canvas_pointer()); var doc: RefCounted=root_document(); doc.finish_checkpoint()
	if not doc.data.has("scenario"): return
	var before: Dictionary=doc.data.duplicate(true); doc.data.erase("scenario"); commit(before)
	studio.status.text="Challenge stopped. The city and treasury remain editable."
func edit_apartment() -> void:
	var scenario: Dictionary=root_document().data.get("scenario",{})
	if scenario.get("id")!="apartment": studio.status.text="Start the apartment challenge first."; return
	if studio.interior_tools.editing(): return
	studio.interior_tools.start(scenario["host_uid"])
func place_asset() -> void:
	var selected: PackedInt32Array=assets.get_selected_items()
	if selected.is_empty(): studio.status.text="Choose an asset from the challenge list."; return
	if choice.get_item_metadata(choice.selected)=="apartment":
		edit_apartment()
		if not studio.interior_tools.editing(): return
	studio.select_asset(assets.get_item_metadata(selected[0]))
func recheck() -> void:
	managers[studio.mode].signature=0
	var world: Node = studio.worlds[studio.mode]
	world.exploration.emergency.signature = 0
	world.exploration.emergency.configure(root_document().data, world.instances)
	dirty=true; tick(.4)
func tick(delta: float) -> void:
	if managers.is_empty(): return
	if fields_mode!=studio.mode: sync_fields()
	for mode in managers:
		managers[mode].active=mode==studio.mode and not studio.modal_visible() and studio.worlds[mode].exploration.interior==null
		managers[mode].construction=studio.worlds[mode].exploration.driving.construction
		managers[mode].emergency=studio.worlds[mode].exploration.emergency
	var doc: RefCounted=root_document(); var apartment: bool=doc.data.get("scenario",{}).get("id")=="apartment"
	if dirty and not studio.stroke and not studio.road_drawing and not studio.ground_brush.drawing and not studio.transform_handles.dragging and studio.worlds[studio.mode].exploration.interior==null and (apartment or not studio.interior_tools.editing()):
		managers[studio.mode].configure(doc.data,studio.library,studio.worlds[studio.mode].instances); dirty=false
	elapsed+=delta
	if elapsed>=.3:
		elapsed=0
		if panel.is_visible_in_tree():
			refresh_construction_choices()
			refresh_drill_choices()
		refresh()
func refresh() -> void:
	if managers.is_empty(): return
	var manager: Node=managers[studio.mode]; var value: Dictionary=manager.progress
	badge.visible=not value["goals"].is_empty()
	if not badge.visible: status.text="No active challenge"; goals.text=""; return
	var done: int=value["goals"].filter(func(item: Dictionary):return item["complete"]).size()
	var state: String = Runtime.status_name(value)
	status.text = manager.title + " · " + state
	badge.text = "Challenge · " + manager.title + " · " + (state if state in ["Complete", "Failed"] else "%d/%d goals" % [done, value["goals"].size()])
	var rows: PackedStringArray=[]
	for item in value["goals"]: rows.append(("✓ " if item["complete"] else "○ ")+item["title"]+" · %d/%d" % [item["current"],item["required"]]+("\n"+item["detail"] if not item["detail"].is_empty() else ""))
	goals.text="\n\n".join(rows)
	if not value["notices"].is_empty(): goals.text+="\n\n"+"\n".join(value["notices"])
func reset() -> void:
	for mode in managers:
		managers[mode].reset()
		var world: Node = studio.worlds[mode]
		if not is_instance_valid(world.exploration): continue
		var emergency: Node = world.exploration.emergency
		emergency.reset_session()
		emergency.configure(studio.interior_tools.root_document(mode).data, world.instances)
	dirty=true; fields_mode=""
