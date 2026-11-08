extends RefCounted

const Plan = preload("res://scripts/builder/arcade_plan.gd")
const Floors = preload("res://scripts/builder/floor_plan.gd")
const Layers = preload("res://scripts/builder/layers.gd")
const Protection = preload("res://scripts/builder/cooperative_plan.gd")
const OPTIONS = ["demo","auto","sprint","signals"]

var studio: Control
var panel := ScrollContainer.new()
var enabled: CheckButton
var apply_city: Button
var game := OptionButton.new()
var apply_cabinet: Button
var selected_label: Label
var message: Label
var signature: int = -1

func _init(host: Control) -> void:
	studio = host
	panel.name = "Arcade"
	panel.follow_focus = true
	panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	studio.workspace_layout.tabs.add_child(panel)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",8)
	panel.add_child(body)
	label(body,"Arcade games",17)
	enabled = CheckButton.new()
	enabled.text = "Enable playable arcade preview"
	enabled.clip_text = true
	body.add_child(enabled)
	apply_city = button(body,"Apply city setting",save_city)
	selected_label = label(body,"",13)
	label(body,"Cabinet game",12)
	game.fit_to_longest_item = false
	game.accessibility_name = "Cabinet game"
	for text in ["Demo or display","Use catalog assignment",Plan.title("sprint"),Plan.title("signals")]: game.add_item(text)
	body.add_child(game)
	apply_cabinet = button(body,"Apply cabinet game",save_cabinet)
	message = label(body,"",13)
	label(body,"Enable the city preview, then select a cabinet and choose a game. Catalog assignments use the reviewed cabinet type. Demo or display keeps the original interaction.",12)
	label(body,"In Walk, approach the front of the cabinet and use Interact. The overlay uses your movement keys, Interact and Cancel, plus on-screen buttons. Finished runs submit scores for this preview.",12)

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

func start() -> void:
	for mode in studio.worlds:
		var arcade: Node = studio.worlds[mode].exploration.arcade
		arcade.ui_parent = studio
		arcade.controls = studio.control_settings
		arcade.authored_root = func() -> Dictionary:
			return studio.interior_tools.root_document(mode).data

func tick() -> void:
	var arcade: Node = studio.worlds[studio.mode].exploration.arcade
	arcade.ui_scale = studio.accessibility_settings.text_scale
	arcade.high_contrast = studio.accessibility_settings.high_contrast
	arcade.large_targets = studio.accessibility_settings.large_targets
	if panel.is_visible_in_tree(): refresh()

func selected() -> Dictionary:
	var items: Array = studio.selection_items()
	return items[0] if items.size() == 1 and Plan.reviewed(items[0]) else {}

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
	game.disabled = not can_edit
	apply_cabinet.disabled = not can_edit
	selected_label.text = "Select a reviewed arcade cabinet."
	if not item.is_empty():
		var recommendation: String = Plan.title(Plan.recommended(item))
		selected_label.text = "%s\nCatalog assignment · %s" % [studio.library.assets[item["asset"]]["name"],
			recommendation if not recommendation.is_empty() else "Demo"]
	var config: Dictionary = item.get("arcade",{})
	game.select(maxi(0,OPTIONS.find(config.get("game","demo"))))

func save_city() -> void:
	if apply_city.disabled: return
	var data: Dictionary = studio.current().data.duplicate(true)
	var config: Dictionary = data.get("arcade",{})
	config["enabled"] = enabled.button_pressed
	data["arcade"] = config
	commit(data,"Arcade preview setting saved.")

func save_cabinet() -> void:
	if apply_cabinet.disabled: return
	var uid: String = selected().get("uid","")
	if uid.is_empty(): return
	var data: Dictionary = studio.current().data.duplicate(true)
	for item in data["objects"]:
		if item["uid"] != uid: continue
		var config: Dictionary = item.get("arcade",{})
		config["game"] = OPTIONS[game.selected]
		item["arcade"] = config
		break
	commit(data,"Cabinet game saved. Undo restores its previous setting.")

func commit(updated: Dictionary, success: String) -> void:
	var doc: RefCounted = studio.current()
	if doc.data == updated:
		message.text = "No arcade setting changed."
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
	for mode in studio.worlds: studio.worlds[mode].exploration.arcade.reset()
	signature = -1
