extends RefCounted

const Plan = preload("res://scripts/builder/cycling_plan.gd")
const Drive = preload("res://scripts/builder/driving_plan.gd")
const Protection = preload("res://scripts/builder/cooperative_plan.gd")

var studio: Control
var panel := ScrollContainer.new()
var enabled := CheckButton.new()
var opt_in := CheckButton.new()
var npc := CheckButton.new()
var rack := OptionButton.new()
var city: Button
var apply: Button
var notice: Label
var selected: Label
var signature: int = -1

func _init(host: Control) -> void:
	studio = host
	panel.name = "Cycling"
	panel.follow_focus = true
	panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	studio.workspace_layout.tabs.add_child(panel)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",7)
	panel.add_child(body)
	label(body,"Cycling and scooters",17)
	enabled.text = "Enable cycling preview"
	enabled.clip_text = true
	body.add_child(enabled)
	city = button(body,"Apply city setting",save_city)
	button(body,"Draw shared roads",func(): brush(2))
	button(body,"Draw cycle paths",func(): brush(3))
	button(body,"Draw motor roads",func(): brush(1))
	label(body,"Road brushes set access explicitly. Cycle paths exclude motor traffic. Shared roads allow both.",12)
	selected = label(body,"",14)
	opt_in.text = "Use as a rideable cycle"
	opt_in.clip_text = true
	body.add_child(opt_in)
	label(body,"Destination rack",12)
	rack.accessibility_name = "Destination rack"
	rack.fit_to_longest_item = false
	body.add_child(rack)
	npc.text = "Assign to a preview rider"
	npc.clip_text = true
	body.add_child(npc)
	apply = button(body,"Apply cycle",save_cycle)
	notice = label(body,"",13)
	label(body,"Place a cycle on a tagged route and a rack beside it. In Walk, mount with Interact and steer with the driving controls. Use the rack guidance shortcut for an assisted trip. Preview riders use the same route and clearance rules.",12)

func label(parent: Node, text: String, size: int) -> Label:
	var control: Label = studio.label(parent,text,size)
	control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return control

func button(parent: Node, text: String, action: Callable) -> Button:
	var control := Button.new()
	control.text = text
	control.clip_text = true
	control.pressed.connect(action)
	parent.add_child(control)
	return control

func brush(choice: int) -> void:
	if studio.interior_tools.editing():
		notice.text = "Draw cycle routes outdoors."
		return
	studio.road_settings.cycling.select(choice)
	studio._command("tool","road")

func start() -> void:
	for world in studio.worlds.values():
		world.exploration.cycling.guide_key = func()->String: return studio.control_settings.label_for("business")

func reset() -> void:
	signature = -1
	for world in studio.worlds.values():
		if world.exploration.driving.cycling(): world.exploration.driving.reset()
		world.exploration.cycling.reset()

func show() -> void:
	studio.workspace_presets.set_focus(false)
	if studio.walking: studio.set_walking(false)
	if studio.get_viewport_rect().size.x < 1200: studio.workspace_layout.library_toggle.button_pressed = false
	studio.workspace_layout.inspector_toggle.button_pressed = true
	studio.workspace_layout.tabs.current_tab = panel.get_index()
	studio.workspace_layout.tabs.get_tab_bar().call_deferred("ensure_tab_visible",panel.get_index())
	signature = -1
	refresh()

func selected_cycle() -> Dictionary:
	var items: Array = studio.selection_items()
	return items[0] if items.size() == 1 and not Plan.asset_profile(items[0]["asset"],studio.mode).is_empty() else {}

func refresh() -> void:
	var data: Dictionary = studio.current().data
	var item: Dictionary = selected_cycle()
	var outdoors: bool = not studio.interior_tools.editing() and not data.get("interior_room",false)
	var allowed: bool = outdoors and not studio.walking and not item.is_empty() and Plan.Utility.Layers.editable(data,item,studio.library)
	var authority: bool = outdoors and not studio.walking and studio.shared_authority()
	var next: int = hash([data.get("cycling",{}),data.get("objects",[]),data.get("roads",[]),item,outdoors,allowed,authority])
	if next == signature: return
	signature = next
	enabled.button_pressed = Plan.enabled(data)
	enabled.disabled = not authority
	city.disabled = not authority
	var setting: Dictionary = item.get("cycling",{})
	opt_in.button_pressed = setting.get("enabled",false)
	npc.button_pressed = setting.get("npc",false)
	rack.clear()
	rack.add_item("Choose a bicycle rack")
	rack.set_item_metadata(0,"")
	for other in data["objects"]:
		if not Plan.rack(other) or not studio.library.assets.has(other["asset"]): continue
		rack.add_item(other.get("name",studio.library.assets[other["asset"]]["name"]))
		rack.set_item_metadata(rack.item_count-1,other["uid"])
		if other["uid"] == setting.get("rack",""): rack.select(rack.item_count-1)
	if rack.selected < 0: rack.select(0)
	for control in [opt_in,npc,rack,apply]: control.disabled = not allowed
	selected.text = "Choose a supported bicycle or scooter." if item.is_empty() else studio.library.assets[item["asset"]]["name"]
	if not outdoors: notice.text = "Cycles stay parked indoors. Return to city Build to configure riding."
	elif item.is_empty(): notice.text = "Use a HanX bicycle or scooter in either world, or a supported Pixel cycle in Pixel worlds."
	elif not setting.get("enabled",false): notice.text = "This cycle is parked."
	elif not Plan.enabled(data): notice.text = "Turn on cycling for this city to preview rides."
	else: notice.text = route_notice(item,data)

func route_notice(item: Dictionary, data: Dictionary) -> String:
	var profile: Dictionary = Plan.profile(item,data)
	if profile.is_empty(): return "Use a supported cycle scale from 65% to 150%."
	var plan: Dictionary = Plan.compile(data)
	var center: Vector2 = Drive.center(item,studio.library,studio.mode)
	var extent: Vector2 = Drive.dimensions(item,studio.library,studio.mode,profile)
	var route: Dictionary = Plan.rack_route(data,plan,item,profile,extent,center,studio.library)
	return "Rack route ready." if route["reason"].is_empty() else route["reason"]

func save_city() -> void:
	if city.disabled: return
	var data: Dictionary = studio.current().data.duplicate(true)
	var setting: Dictionary = data.get("cycling",{})
	setting["enabled"] = enabled.button_pressed
	data["cycling"] = setting
	commit(data)

func save_cycle() -> void:
	if apply.disabled: return
	var selected_item: Dictionary = selected_cycle()
	if selected_item.is_empty(): return
	var data: Dictionary = studio.current().data.duplicate(true)
	var item: Dictionary = Plan.object(data,selected_item["uid"])
	var setting: Dictionary = item.get("cycling",{})
	setting.merge({"enabled":opt_in.button_pressed,"npc":npc.button_pressed,"rack":rack.get_item_metadata(rack.selected)},true)
	if setting["npc"] and setting["rack"].is_empty():
		notice.text = "Choose a rack before assigning a preview rider."
		return
	item["cycling"] = setting
	commit(data)

func commit(data: Dictionary) -> void:
	var doc: RefCounted = studio.current()
	if doc.data == data: return
	var session: Node = studio.cooperative_tools.session
	if session.connected and session.role == "client":
		var before: Dictionary = studio.cooperative_tools.snapshot()
		var proposal: Dictionary = before.duplicate(true)
		proposal[studio.mode] = data
		var issue: String = Protection.allowed(before,proposal,session.local_id,studio.library)
		if not issue.is_empty():
			notice.text = issue
			return
	studio.finish_edit(studio.canvas_pointer())
	doc.checkpoint()
	doc.data = data
	studio.changed()
	doc.finish_checkpoint(true)
	signature = -1
	refresh()
