extends RefCounted

const Plan = preload("res://scripts/builder/pet_plan.gd")
const Policy = preload("res://scripts/builder/asset_palette_policy.gd")

var studio: Control
var panel := ScrollContainer.new()
var enabled := CheckButton.new()
var species := OptionButton.new()
var home := OptionButton.new()
var station := OptionButton.new()
var leash := SpinBox.new()
var apply: Button
var notice: Label
var signature: int = -1

func _init(host: Control) -> void:
	studio = host
	panel.name = "Pets"
	panel.follow_focus = true
	panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	studio.workspace_layout.tabs.add_child(panel)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",7)
	panel.add_child(body)
	label(body,"Pet companionship",17)
	enabled.text = "Enable a pet companion"
	enabled.clip_text = true
	body.add_child(enabled)
	picker(body,species,"Companion")
	picker(body,home,"Home resting mat")
	picker(body,station,"Outdoor dog station")
	label(body,"Follow distance",12)
	leash.min_value = Plan.MIN_LEASH
	leash.max_value = Plan.MAX_LEASH
	leash.accessibility_name = "Follow distance"
	body.add_child(leash)
	apply = Button.new()
	apply.text = "Apply companion"
	apply.clip_text = true
	apply.pressed.connect(save)
	body.add_child(apply)
	notice = label(body,"",13)
	label(body,"Place a supported rug to assign a resting mat. Dogs with outdoor homes can also use the HanX Dog Station.",12)
	label(body,"In Walk, approach the pet and interact to follow, stay, come, rest or return home. Pets wait when you leave their floor or enter a vehicle.",12)
	species.item_selected.connect(func(_index: int): refresh_station())
	home.item_selected.connect(func(_index: int): refresh_station())

func label(parent: Node, text: String, size: int) -> Label:
	var result: Label = studio.label(parent,text,size)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return result

func picker(parent: Node, control: OptionButton, text: String) -> void:
	label(parent,text,12)
	control.accessibility_name = text
	control.fit_to_longest_item = false
	parent.add_child(control)

func start() -> void:
	for mode in studio.worlds:
		var runtime: Node = studio.worlds[mode].exploration.pet
		runtime.authored_root = func()->Dictionary: return studio.interior_tools.root_document(mode).data
		runtime.owner_key = func()->String:
			var session: Node = studio.cooperative_tools.session
			return session.local_id if session.connected else "local"
		runtime.interact_label = func()->String: return studio.control_settings.label_for("interact")
		runtime.ui_parent = studio

func reset() -> void:
	signature = -1
	for world in studio.worlds.values(): world.exploration.pet.reset()

func show() -> void:
	studio.workspace_presets.set_focus(false)
	if studio.walking: studio.set_walking(false)
	if studio.get_viewport_rect().size.x < 1200: studio.workspace_layout.library_toggle.button_pressed = false
	studio.workspace_layout.inspector_toggle.button_pressed = true
	studio.workspace_layout.tabs.current_tab = panel.get_index()
	studio.workspace_layout.tabs.get_tab_bar().call_deferred("ensure_tab_visible",panel.get_index())
	signature = -1
	refresh()

func add(control: OptionButton, title: String, value: Variant, wanted: Variant) -> void:
	control.add_item(title)
	control.set_item_metadata(control.item_count-1,value)
	if value == wanted: control.select(control.item_count-1)

func object_title(item: Dictionary) -> String:
	return item.get("name",studio.library.assets.get(item["asset"],{}).get("name",item["asset"])).replace("_"," ")

func add_homes(data: Dictionary, building: String, floor: String, prefix: String, wanted: Array) -> void:
	for item in data.get("objects",[]):
		if Plan.fixture(item,"rest"): add(home,prefix+object_title(item),[building,floor,item["uid"]],wanted)

func selected(control: OptionButton) -> Variant:
	return control.get_item_metadata(maxi(0,control.selected))

func refresh_station() -> void:
	station.disabled = apply.disabled or Plan.species(str(selected(species))) != "dog" or not selected(home)[0].is_empty()

func refresh() -> void:
	var root: Dictionary = studio.interior_tools.root_document(studio.mode).data
	var config: Dictionary = Plan.settings(root)
	var writable: bool = studio.shared_authority() and not studio.walking and not studio.interior_tools.editing()
	var next: int = hash([studio.mode,config,root.get("objects",[]),writable,studio.library.project_palette_ids])
	if next == signature: return
	signature = next
	for control in [species,home,station]: control.clear()
	add(species,"Choose a cat or dog","",config["asset"])
	for kind in Plan.definitions()["species"]:
		for id in Plan.definitions()["species"][kind]:
			if Plan.supported(id,studio.library) and Policy.allowed(id,studio.library):
				add(species,studio.library.assets[id]["name"].replace("_"," "),id,config["asset"])
	var wanted: Array = [config["building"],config["floor"],config["home"]]
	add(home,"Choose a resting mat",["","ground",""],wanted)
	add_homes(root,"","ground","Outdoors · ",wanted)
	for item in root.get("objects",[]):
		if item.get("interior") is Dictionary:
			for floor in Plan.Floors.definitions(item["interior"]):
				add_homes(floor["room"],item["uid"],floor["uid"],object_title(item)+" · "+floor["name"]+" · ",wanted)
	add(station,"No station","",config["park"])
	for item in root.get("objects",[]):
		if Plan.fixture(item,"park"): add(station,object_title(item),item["uid"],config["park"])
	for control in [species,home,station]:
		if control.selected < 0: control.select(0)
	apply.disabled = not writable
	enabled.disabled = not writable
	home.disabled = not writable
	species.disabled = not writable
	leash.editable = writable
	enabled.button_pressed = config["enabled"]
	leash.value = config["leash"]
	refresh_station()
	notice.text = "The host configures the companion." if not studio.shared_authority() else (
		"Return to city Build to edit this companion." if not writable else (
			Plan.eligible(config,root,studio.library) if config["enabled"] else "Pet preview is off."))

func save() -> void:
	if apply.disabled or not studio.shared_authority(): return
	var doc: RefCounted = studio.interior_tools.root_document(studio.mode)
	var setting: Dictionary = Plan.settings(doc.data)
	var scope: Array = selected(home)
	setting.merge({"enabled":enabled.button_pressed,"asset":selected(species),"building":scope[0],"floor":scope[1],
		"home":scope[2],"park":"" if station.disabled else selected(station),"leash":leash.value},true)
	if setting["enabled"]:
		var issue: String = Plan.eligible(setting,doc.data,studio.library)
		if not issue.is_empty():
			notice.text = issue
			return
		if not Policy.allowed(setting["asset"],studio.library):
			notice.text = Policy.excluded(setting["asset"],studio.library)
			return
	if setting == doc.data.get("pet",{}): return
	studio.finish_edit(studio.canvas_pointer())
	doc.checkpoint()
	doc.data["pet"] = setting
	studio.changed()
	doc.finish_checkpoint(true)
	notice.text = "Companion saved. Undo restores its previous settings."
