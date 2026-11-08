extends RefCounted

const Plan = preload("res://scripts/builder/cooking_plan.gd")
const Floors = preload("res://scripts/builder/floor_plan.gd")
const Layers = preload("res://scripts/builder/layers.gd")
const Palette = preload("res://scripts/builder/asset_palette_policy.gd")
const Protection = preload("res://scripts/builder/cooperative_plan.gd")

var studio: Control
var panel: ScrollContainer
var enabled: CheckButton
var apply_city: Button
var station_enabled: CheckButton
var require_power: CheckButton
var recipe: OptionButton
var apply_station: Button
var selected_label: Label
var recipe_label: Label
var message: Label
var signature: int = -1

func _init(host: Control) -> void:
	studio = host
	panel = ScrollContainer.new()
	panel.name = "Kitchen"
	panel.follow_focus = true
	panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	studio.workspace_layout.tabs.add_child(panel)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",8)
	panel.add_child(body)
	label(body,"Cooking workflows",17)
	enabled = toggle(body,"Enable cooking preview")
	apply_city = button(body,"Apply city setting",save_city)
	selected_label = label(body,"",13)
	station_enabled = toggle(body,"Use as kitchen station")
	label(body,"Preparation recipe",12)
	recipe = OptionButton.new()
	recipe.fit_to_longest_item = false
	recipe.accessibility_name = "Preparation recipe"
	for id in Plan.recipes():
		recipe.add_item(Plan.recipes()[id]["name"])
		recipe.set_item_metadata(recipe.item_count-1,id)
	body.add_child(recipe)
	recipe_label = label(body,"",12)
	recipe.item_selected.connect(func(_index: int): show_recipe())
	require_power = toggle(body,"Use connected power")
	require_power.tooltip_text = "When Power is enabled, connect the stove or the building's power inlet."
	apply_station = button(body,"Apply station setting",save_station)
	message = label(body,"",13)
	label(body,"On one floor, enable a preparation surface, a stove and a serving counter. Use a stove with a pan or place an enabled pan nearby. Add a pantry to restock.",12)
	label(body,"In Walk, use Interact to prepare, cook and plate. Stay at the station during each timed step. Cancelling before heat returns the ingredients. A café serves ready plates from its business menu at the counter.",12)

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

func button(parent: Node, text: String, action: Callable) -> Button:
	var control := Button.new()
	control.text = text
	control.clip_text = true
	control.pressed.connect(action)
	parent.add_child(control)
	return control

func start() -> void:
	for mode in studio.worlds:
		studio.worlds[mode].exploration.cooking.authored_root = func() -> Dictionary:
			return studio.interior_tools.root_document(mode).data

func selected() -> Dictionary:
	var items: Array = studio.selection_items()
	return items[0] if items.size() == 1 and not Plan.profile(items[0]).is_empty() else {}

func show() -> void:
	studio.workspace_presets.set_focus(false)
	if studio.walking: studio.set_walking(false)
	if studio.get_viewport_rect().size.x < 1200: studio.workspace_layout.library_toggle.button_pressed = false
	studio.workspace_layout.inspector_toggle.button_pressed = true
	studio.workspace_layout.tabs.current_tab = panel.get_index()
	studio.workspace_layout.tabs.get_tab_bar().call_deferred("ensure_tab_visible",panel.get_index())
	signature = -1
	refresh()

func refresh() -> void:
	var item: Dictionary = selected()
	var data: Dictionary = studio.current().data
	var root: Dictionary = studio.interior_tools.root_document(studio.mode).data
	var may_city: bool = not studio.interior_tools.editing() and not studio.walking and studio.shared_authority()
	var can_edit: bool = not studio.walking and not item.is_empty() and Layers.editable(data,item,studio.library)
	var next: int = hash([studio.mode,item,may_city,can_edit,Plan.enabled(root)])
	if next == signature: return
	signature = next
	enabled.disabled = not may_city
	enabled.set_pressed_no_signal(Plan.enabled(root))
	apply_city.disabled = not may_city
	var role: String = Plan.profile(item).get("role","")
	selected_label.text = "Select a reviewed kitchen object." if item.is_empty() else "%s · %s" % [
		studio.library.assets[item["asset"]]["name"],role.capitalize()]
	station_enabled.disabled = not can_edit
	apply_station.disabled = not can_edit
	require_power.disabled = not can_edit or role != "cook"
	recipe.disabled = not can_edit or role != "prep"
	var config: Dictionary = Plan.station(item)
	var raw: Dictionary = item.get("cooking",{})
	station_enabled.set_pressed_no_signal(not config.is_empty())
	require_power.set_pressed_no_signal(raw.get("power",false))
	for index in recipe.item_count:
		if recipe.get_item_metadata(index) == raw.get("recipe",Plan.DEFAULT_RECIPE): recipe.select(index)
	show_recipe()

func show_recipe() -> void:
	recipe_label.visible = not recipe.disabled
	if not recipe_label.visible or recipe.selected < 0: return
	var data: Dictionary = Plan.recipes()[recipe.get_item_metadata(recipe.selected)]
	var inputs: PackedStringArray = []
	for key in data["inputs"]: inputs.append("%d %s" % [data["inputs"][key],key])
	recipe_label.text = "Ingredients · "+", ".join(inputs)+"\nPrep %d s · Cook %d s · Plate %d s" % [
		data["seconds"]["prep"],data["seconds"]["cook"],data["seconds"]["serve"]]

func save_city() -> void:
	if apply_city.disabled: return
	var data: Dictionary = studio.current().data.duplicate(true)
	var settings: Dictionary = data.get("cooking",{})
	settings["enabled"] = enabled.button_pressed
	data["cooking"] = settings
	commit(data,"City cooking setting saved.")

func save_station() -> void:
	if apply_station.disabled: return
	var uid: String = selected().get("uid","")
	if uid.is_empty(): return
	var data: Dictionary = studio.current().data.duplicate(true)
	for item in data["objects"]:
		if item["uid"] != uid: continue
		var settings: Dictionary = item.get("cooking",{})
		settings.merge({"enabled":station_enabled.button_pressed,"recipe":recipe.get_item_metadata(recipe.selected),
			"power":not require_power.disabled and require_power.button_pressed},true)
		item["cooking"] = settings
	commit(data,"Kitchen station saved. Undo restores the previous setting.")

func outer_candidate(updated: Dictionary, original: Dictionary) -> Dictionary:
	if not studio.interior_tools.editing(): return updated
	var after: Dictionary = original.duplicate(true)
	for host in after["objects"]:
		if host["uid"] != studio.interior_tools.uid: continue
		var room: Dictionary = Floors.room(host["interior"],studio.current().floor_uid)
		room.assign(updated)
	return after

func commit(updated: Dictionary, success: String) -> void:
	var doc: RefCounted = studio.current()
	if doc.data == updated:
		message.text = "No cooking setting changed."
		return
	var original: Dictionary = studio.interior_tools.root_document(studio.mode).data
	var after: Dictionary = outer_candidate(updated,original)
	var content: Dictionary = Palette.check(original,after,studio.library)
	if not content["ok"]:
		message.text = content["reason"]
		return
	var session: Node = studio.cooperative_tools.session
	if session.connected and session.role == "client":
		var shared: Dictionary = studio.cooperative_tools.snapshot()
		var proposed: Dictionary = shared.duplicate(true)
		proposed[studio.mode] = after
		var reason: String = Protection.allowed(shared,proposed,session.local_id,studio.library)
		if not reason.is_empty():
			message.text = reason
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
	for mode in studio.worlds: studio.worlds[mode].exploration.cooking.reset()
	signature = -1
