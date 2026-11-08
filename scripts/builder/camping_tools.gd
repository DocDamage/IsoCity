extends RefCounted

const Plan = preload("res://scripts/builder/camping_plan.gd")
const Floors = preload("res://scripts/builder/floor_plan.gd")
const Layers = preload("res://scripts/builder/layers.gd")
const Protection = preload("res://scripts/builder/cooperative_plan.gd")

var studio: Control
var panel := ScrollContainer.new()
var enabled: CheckButton
var apply_city: Button
var site_enabled: CheckButton
var overnight: CheckButton
var capacity: SpinBox
var opening: SpinBox
var closing: SpinBox
var checkout: SpinBox
var park := OptionButton.new()
var activity := OptionButton.new()
var apply_site: Button
var selected_label: Label
var message: Label
var signature: int = -1

func _init(host: Control) -> void:
	studio = host
	panel.name = "Camping"
	panel.follow_focus = true
	panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	studio.workspace_layout.tabs.add_child(panel)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",7)
	panel.add_child(body)
	label(body,"Camping visits",17)
	enabled = toggle(body,"Enable camping preview")
	apply_city = button(body,"Apply city setting",save_city)
	selected_label = label(body,"",13)
	site_enabled = toggle(body,"Use as a campsite")
	picker(body,park,"Park arrival")
	picker(body,activity,"Camp activity")
	capacity = number(body,"Sleeping spaces",1,4,1)
	opening = number(body,"Check-in opens",0,23.5,.5)
	closing = number(body,"Check-in closes",0,23.5,.5)
	overnight = toggle(body,"Overnight visits")
	checkout = number(body,"Morning checkout",0,23.5,.5)
	apply_site = button(body,"Apply campsite",save_site)
	message = label(body,"",13)
	label(body,"Link a nearby park destination and a picnic table or fire ring to each shelter. Use one activity per campsite. Indoor rooms can host daytime picnics.",12)
	label(body,"In Walk, reserve at the park, check in at the shelter, use the activity, rest, then return to the park. Overnight rest waits for the shared clock. Camping never advances it.",12)

func label(parent: Node, text: String, size: int) -> Label:
	var control: Label = studio.label(parent,text,size)
	control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return control

func toggle(parent: Node, text: String) -> CheckButton:
	var control := CheckButton.new()
	control.text = text
	control.clip_text = true
	parent.add_child(control)
	return control

func number(parent: Node, text: String, low: float, high: float, step: float) -> SpinBox:
	label(parent,text,12)
	var control := SpinBox.new()
	control.min_value = low
	control.max_value = high
	control.step = step
	control.accessibility_name = text
	parent.add_child(control)
	return control

func picker(parent: Node, control: OptionButton, text: String) -> void:
	label(parent,text,12)
	control.fit_to_longest_item = false
	control.accessibility_name = text
	parent.add_child(control)

func button(parent: Node, text: String, action: Callable) -> Button:
	var control := Button.new()
	control.text = text
	control.clip_text = true
	control.pressed.connect(action)
	parent.add_child(control)
	return control

func start() -> void:
	for mode in studio.worlds:
		var camp: Node = studio.worlds[mode].exploration.camping
		camp.authored_root = func() -> Dictionary: return studio.interior_tools.root_document(mode).data
		camp.audio_allowed = func() -> bool:
			return studio.ambience_tools.managers.has(mode) and not studio.ambience_tools.managers[mode].muted \
				and preload("res://scripts/builder/ambience_plan.gd").settings(camp.root_data())["enabled"]

func selected() -> Dictionary:
	var items: Array = studio.selection_items()
	return items[0] if items.size() == 1 and Plan.shelter(items[0]) > 0 else {}

func show() -> void:
	studio.workspace_presets.set_focus(false)
	if studio.walking: studio.set_walking(false)
	if studio.get_viewport_rect().size.x < 1200: studio.workspace_layout.library_toggle.button_pressed = false
	studio.workspace_layout.inspector_toggle.button_pressed = true
	studio.workspace_layout.tabs.current_tab = panel.get_index()
	studio.workspace_layout.tabs.get_tab_bar().call_deferred("ensure_tab_visible",panel.get_index())
	signature = -1
	refresh()

func fill(control: OptionButton, objects: Array, uid: String, filter: Callable) -> void:
	control.clear()
	control.add_item("Choose an object")
	control.set_item_metadata(0,"")
	for item in objects:
		if not filter.call(item) or not studio.library.assets.has(item["asset"]): continue
		control.add_item(str(item.get("name",studio.library.assets[item["asset"]]["name"])))
		control.set_item_metadata(control.item_count-1,item["uid"])
		if uid == item["uid"]: control.select(control.item_count-1)
	if control.selected < 0: control.select(0)

func refresh() -> void:
	var item: Dictionary = selected()
	var data: Dictionary = studio.current().data
	var root: Dictionary = studio.interior_tools.root_document(studio.mode).data
	var may_city: bool = not studio.interior_tools.editing() and not studio.walking and studio.shared_authority()
	var can_edit: bool = not studio.walking and not item.is_empty() and Layers.editable(data,item,studio.library)
	var next: int = hash([studio.mode,item,may_city,can_edit,Plan.enabled(root),data["objects"]])
	if next == signature: return
	signature = next
	enabled.disabled = not may_city
	enabled.set_pressed_no_signal(Plan.enabled(root))
	apply_city.disabled = not may_city
	var config: Dictionary = Plan.config(item)
	selected_label.text = "Select a reviewed tent or shelter." if item.is_empty() else \
		"%s · up to %d sleeping spaces" % [studio.library.assets[item["asset"]]["name"],Plan.shelter(item)]
	site_enabled.disabled = not can_edit
	site_enabled.set_pressed_no_signal(config["enabled"])
	overnight.disabled = not can_edit or studio.interior_tools.editing()
	overnight.set_pressed_no_signal(config["overnight"])
	for control in [capacity,opening,closing,checkout]: control.editable = can_edit
	capacity.max_value = maxi(1,Plan.shelter(item))
	capacity.set_value_no_signal(maxi(1,int(config["capacity"])))
	opening.set_value_no_signal(config["open_hour"])
	closing.set_value_no_signal(config["close_hour"])
	checkout.set_value_no_signal(config["checkout"])
	park.disabled = not can_edit
	activity.disabled = not can_edit
	fill(park,data["objects"],config["park"],func(record: Dictionary)->bool: return Plan.Citizens.role(record)=="park")
	fill(activity,data["objects"],config["activity"],func(record: Dictionary)->bool: return not Plan.activity(record).is_empty())
	apply_site.disabled = not can_edit

func save_city() -> void:
	if apply_city.disabled: return
	var data: Dictionary = studio.current().data.duplicate(true)
	var config: Dictionary = data.get("camping",{})
	config["enabled"] = enabled.button_pressed
	data["camping"] = config
	commit(data,"Camping preview setting saved.")

func save_site() -> void:
	if apply_site.disabled: return
	if site_enabled.button_pressed and (park.selected <= 0 or activity.selected <= 0):
		message.text = "Choose a park arrival and an activity."
		return
	var uid: String = selected().get("uid","")
	if uid.is_empty(): return
	var data: Dictionary = studio.current().data.duplicate(true)
	for item in data["objects"]:
		if item["uid"] != uid: continue
		var config: Dictionary = item.get("camping",{})
		config.merge({"enabled":site_enabled.button_pressed,"capacity":int(capacity.value),"open_hour":opening.value,
			"close_hour":closing.value,"checkout":checkout.value,"overnight":overnight.button_pressed and not overnight.disabled,
			"park":park.get_item_metadata(park.selected),"activity":activity.get_item_metadata(activity.selected)},true)
		item["camping"] = config
		break
	commit(data,"Campsite saved. Undo restores its previous settings.")
	var local: Dictionary = Plan.compile(studio.current().data,studio.library,not studio.interior_tools.editing())
	var reason: String = local.get(uid,{}).get("reason","")
	if not reason.is_empty(): message.text += "\n"+reason

func commit(updated: Dictionary, success: String) -> void:
	var doc: RefCounted = studio.current()
	if doc.data == updated:
		message.text = "No campsite setting changed."
		return
	var session: Node = studio.cooperative_tools.session
	if session.connected and session.role == "client":
		var shared: Dictionary = studio.cooperative_tools.snapshot()
		var proposed: Dictionary = shared.duplicate(true)
		if studio.interior_tools.editing():
			for host in proposed[studio.mode]["objects"]:
				if host["uid"] != studio.interior_tools.uid: continue
				Floors.room(host["interior"],doc.floor_uid).assign(updated)
				break
		else: proposed[studio.mode] = updated
		var issue: String = Protection.allowed(shared,proposed,session.local_id,studio.library)
		if not issue.is_empty():
			message.text = issue
			return
	studio.finish_edit(studio.canvas_pointer())
	doc.checkpoint()
	doc.data = updated
	studio.changed()
	doc.finish_checkpoint(true)
	message.text = success
	signature = -1
	refresh()

func reset() -> void:
	for mode in studio.worlds: studio.worlds[mode].exploration.camping.reset()
	signature = -1
