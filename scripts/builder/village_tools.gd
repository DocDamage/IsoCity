extends RefCounted

const Plan = preload("res://scripts/builder/village_plan.gd")
const Palette = preload("res://scripts/builder/asset_palette_policy.gd")
const Protection = preload("res://scripts/builder/cooperative_plan.gd")

var studio: Control
var panel := ScrollContainer.new()
var enabled := CheckButton.new()
var use_site := CheckButton.new()
var recipe := OptionButton.new()
var destination := OptionButton.new()
var transport := OptionButton.new()
var apply_city: Button
var apply_site: Button
var selection: Label
var notice: Label
var live: Label
var signature: int = -1

func _init(host: Control) -> void:
	studio = host
	panel.name = "Village"
	panel.follow_focus = true
	panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	studio.workspace_layout.tabs.add_child(panel)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",7)
	panel.add_child(body)
	label(body,"Village production",17)
	toggle(body,enabled,"Enable village preview")
	apply_city = button(body,"Apply city setting",save_city)
	selection = label(body,"",14)
	toggle(body,use_site,"Use as a village facility")
	picker(body,recipe,"Recipe")
	picker(body,destination,"Ship stock to")
	picker(body,transport,"Transfer method")
	transport.add_item("Local porter")
	transport.add_item("Player delivery truck")
	apply_site = button(body,"Apply facility",save_site)
	notice = label(body,"",13)
	live = label(body,"",13)
	label(body,"Connect a farm to a granary, mill, bakery and market. Porters carry two units along a dry walking route. Truck routes use the local delivery controls and approved loading pads.",12)
	label(body,"In Walk, interact at a facility approach to inspect stock, sell an order or supply a kitchen. Village credits belong to the preview wallet.",12)

func label(parent: Node, text: String, size: int) -> Label:
	var result: Label = studio.label(parent,text,size)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return result

func toggle(parent: Node, button_value: CheckButton, text: String) -> void:
	button_value.text = text
	button_value.clip_text = true
	parent.add_child(button_value)

func picker(parent: Node, control: OptionButton, text: String) -> void:
	label(parent,text,12)
	control.accessibility_name = text
	control.fit_to_longest_item = false
	parent.add_child(control)

func button(parent: Node, text: String, action: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.clip_text = true
	result.pressed.connect(action)
	parent.add_child(result)
	return result

func start() -> void:
	for mode in studio.worlds:
		var runtime: Node = studio.worlds[mode].exploration.village
		runtime.authored_root = func()->Dictionary: return studio.interior_tools.root_document(mode).data
		runtime.interact_label = func()->String: return studio.control_settings.label_for("interact")
		runtime.ui_parent = studio

func reset() -> void:
	signature = -1
	for world in studio.worlds.values(): world.exploration.village.reset()

func show() -> void:
	studio.workspace_presets.set_focus(false)
	if studio.walking: studio.set_walking(false)
	if studio.get_viewport_rect().size.x < 1200: studio.workspace_layout.library_toggle.button_pressed = false
	studio.workspace_layout.inspector_toggle.button_pressed = true
	studio.workspace_layout.tabs.current_tab = panel.get_index()
	studio.workspace_layout.tabs.get_tab_bar().call_deferred("ensure_tab_visible",panel.get_index())
	signature = -1
	refresh()

func item() -> Dictionary:
	var items: Array = studio.selection_items()
	return items[0] if items.size() == 1 and not Plan.profile(items[0],studio.library).is_empty() else {}

func append(control: OptionButton, text: String, value: String, wanted: String) -> void:
	control.add_item(text)
	control.set_item_metadata(control.item_count-1,value)
	if wanted == value: control.select(control.item_count-1)

func refresh() -> void:
	var data: Dictionary = studio.current().data
	var placed: Dictionary = item()
	var uid: String = placed.get("uid","")
	var runtime: Node = studio.worlds[studio.mode].exploration.village
	var outside: bool = not studio.interior_tools.editing() and not data.get("interior_room",false)
	var can_city: bool = outside and not studio.walking and studio.shared_authority()
	var can_site: bool = outside and not studio.walking and not placed.is_empty() and Plan.Utility.Layers.editable(data,placed,studio.library)
	var next: int = hash([data.get("objects",[]),data.get("village",{}),uid,can_city,can_site,outside])
	live.text = runtime.stock_text(uid)+"\n"+runtime.status(uid) if runtime.book.sites.has(uid) else ""
	if next == signature: return
	signature = next
	enabled.disabled = not can_city
	enabled.button_pressed = Plan.enabled(data)
	apply_city.disabled = not can_city
	apply_site.disabled = not can_site
	use_site.disabled = not can_site
	var facility: Dictionary = Plan.profile(placed,studio.library)
	var setting: Dictionary = Plan.config(placed,facility) if not facility.is_empty() else Plan.DEFAULTS
	use_site.button_pressed = setting["enabled"]
	recipe.clear()
	for id in facility.get("recipes",[]):
		append(recipe,Plan.definitions()["recipes"][id]["name"],id,setting["recipe"])
	if recipe.item_count == 0: append(recipe,"Storage or sales","",setting["recipe"])
	if recipe.selected < 0: recipe.select(0)
	recipe.disabled = not can_site or facility.get("recipes",[]).is_empty()
	destination.clear()
	append(destination,"No destination","",setting["destination"])
	var good: String = facility.get("ships","")
	if not good.is_empty():
		for other in data.get("objects",[]):
			if other["uid"] == uid: continue
			var target: Dictionary = Plan.profile(other,studio.library)
			if good in target.get("accepts",[]):
				append(destination,str(other.get("name",target["name"])),other["uid"],setting["destination"])
	if destination.selected < 0: destination.select(0)
	destination.disabled = not can_site or good.is_empty()
	transport.disabled = destination.disabled
	transport.select(1 if setting["transport"] == "truck" else 0)
	selection.text = "Select a reviewed village building." if placed.is_empty() else str(placed.get("name",facility["name"]))+" Â· "+facility["name"]
	notice.text = "Configure outdoor village facilities from city Build." if not outside else ""

func save_city() -> void:
	if apply_city.disabled: return
	var data: Dictionary = studio.current().data.duplicate(true)
	var config: Dictionary = data.get("village",{})
	config["enabled"] = enabled.button_pressed
	data["village"] = config
	commit(data)

func save_site() -> void:
	if apply_site.disabled: return
	var current: Dictionary = item()
	if current.is_empty(): return
	var data: Dictionary = studio.current().data.duplicate(true)
	for placed in data["objects"]:
		if placed["uid"] != current["uid"]: continue
		var settings: Dictionary = placed.get("village",{})
		settings.merge({"enabled":use_site.button_pressed,"recipe":recipe.get_item_metadata(recipe.selected),
			"destination":destination.get_item_metadata(destination.selected),"transport":"truck" if transport.selected == 1 else "porter"},true)
		placed["village"] = settings
		break
	commit(data)

func commit(data: Dictionary) -> void:
	var doc: RefCounted = studio.current()
	if doc.data == data: return
	var allowed: Dictionary = Palette.check(doc.data,data,studio.library)
	if not allowed["ok"]:
		notice.text = allowed["reason"]
		return
	var session: Node = studio.cooperative_tools.session
	if session.connected and session.role == "client":
		var old: Dictionary = studio.cooperative_tools.snapshot()
		var next: Dictionary = old.duplicate(true)
		next[studio.mode] = data
		var issue: String = Protection.allowed(old,next,session.local_id,studio.library)
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
	notice.text = "Saved village settings. Undo restores the previous setup."
