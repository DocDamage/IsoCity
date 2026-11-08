extends RefCounted

const Plan=preload("res://scripts/builder/fleet_plan.gd")
const Policy=preload("res://scripts/builder/asset_palette_policy.gd")
const TITLES=["Ordinary traffic","Public transit","Fire crews","Medical crews","Police crews","Sanitation crews"]
var studio: Control
var panel: ScrollContainer
var roles: OptionButton
var list: VBoxContainer
var notice: Label
var apply_button: Button
var reset_button: Button
var entries: Dictionary={}
var opened_mode: String=""
var opened_doc: RefCounted
var opened_selection: Variant
var pending: bool=false

func _init(host: Control) -> void:
	studio=host
	panel=ScrollContainer.new()
	panel.name="Fleets"
	panel.follow_focus=true
	panel.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	studio.workspace_layout.tabs.add_child(panel)
	var box:=VBoxContainer.new()
	box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation",8)
	panel.add_child(box)
	studio.label(box,"Vehicle fleets",17)
	roles=OptionButton.new()
	roles.fit_to_longest_item=false
	roles.clip_text=true
	roles.accessibility_name="Vehicle fleet role"
	for title in TITLES:
		roles.add_item(title)
	box.add_child(roles)
	roles.item_selected.connect(func(_index: int): load_choices())
	apply_button=button(box,"Apply fleet choices",apply.bind(false))
	reset_button=button(box,"Use default fleet",apply.bind(true))
	button(box,"Reload saved choices",load_choices)
	notice=studio.label(box,"",12)
	notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	notice.accessibility_name="Fleet setup status"
	var help: Label=studio.label(box,"Weight controls how often an eligible model is chosen. A zero weight keeps its selection saved. Existing vehicles keep their model. Restart traffic to replace ordinary cars.",12)
	help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	list=VBoxContainer.new()
	list.add_theme_constant_override("separation",8)
	box.add_child(list)
	studio.get_viewport().gui_focus_changed.connect(reveal_focus)
	panel.resized.connect(func(): reveal_focus(studio.get_viewport().gui_get_focus_owner()))

func button(parent: Node,title: String,callback: Callable) -> Button:
	var control:=Button.new()
	control.text=title
	control.tooltip_text=title
	control.accessibility_name=title
	control.clip_text=true
	parent.add_child(control)
	control.pressed.connect(callback)
	return control

func reveal_focus(control: Control) -> void:
	if not is_instance_valid(control) or not panel.is_ancestor_of(control): return
	for frame in 2: await studio.get_tree().process_frame
	if not is_instance_valid(control) or not control.has_focus() or not panel.is_visible_in_tree(): return
	panel.ensure_control_visible(control)
	var outer: ScrollContainer=studio.accessibility_settings.root_scroll
	if is_instance_valid(outer) and outer.is_ancestor_of(control): outer.ensure_control_visible(control)

func show() -> void:
	if studio.interior_tools.editing():
		studio.status.text="Configure vehicle fleets in the exterior city."
		return
	studio.workspace_presets.set_focus(false)
	if studio.walking: studio.set_walking(false)
	studio.workspace_layout.inspector_toggle.button_pressed=true
	studio.workspace_layout.tabs.current_tab=panel.get_index()
	load_choices()
	roles.grab_focus()

func role() -> String:
	return Plan.ROLES[roles.selected]

func saved() -> Variant:
	return studio.current().data.get("fleet",{}).get(role())

func load_choices() -> void:
	if studio.documents.is_empty(): return
	opened_mode=studio.mode
	opened_doc=studio.current()
	var current: Variant=saved()
	opened_selection=current.duplicate(true) if current is Array else null
	pending=false
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	entries.clear()
	var selected: Dictionary={}
	for entry in Plan.selections(studio.current().data,role()):
		selected[entry["asset"]]=entry["weight"]
	var ids: Array=Plan.offered(studio.mode,role())
	for id in selected:
		if id not in ids: ids.append(id)
	for id in ids:
		add_entry(id,selected)
	refresh_notice()

func add_entry(id: String, selected: Dictionary) -> void:
	var asset: Dictionary=studio.library.assets.get(id,{})
	var profile: Dictionary=Plan.definitions().get(id,{})
	var title: String=asset.get("name",id)
	var available: bool=Plan.usable(id,studio.mode,role(),studio.library)
	var checked:=CheckButton.new()
	checked.text=title
	checked.tooltip_text=title
	checked.clip_text=true
	checked.accessibility_name="Include "+title
	checked.button_pressed=selected.has(id)
	checked.disabled=not available and not selected.has(id)
	list.add_child(checked)
	var description: String="%.2f × %.2f units · up to %.1f units/s"%[profile["length"],profile["width"],profile["speed"]] if available else "Unavailable for this role · "+id
	if available and not asset["data"].get("source_export_allowed",true):
		description+=" · Source ZIP restricted"
	studio.label(list,description,12).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var weight: SpinBox=studio.spin(list,0,100,1,selected.get(id,profile.get("weight",50)))
	weight.accessibility_name="Weight for "+title
	weight.editable=checked.button_pressed and available
	entries[id]={"enabled":checked,"weight":weight,"available":available}
	checked.toggled.connect(func(value: bool):
		weight.editable=value and available
		pending=true
		refresh_notice()
	)
	weight.value_changed.connect(func(_value: float):
		pending=true
		refresh_notice()
	)

func choices() -> Array:
	var result: Array=[]
	for id in entries:
		var entry: Dictionary=entries[id]
		if entry["enabled"].button_pressed:
			result.append({"asset":id,"weight":int(entry["weight"].value)})
	result.sort_custom(func(a: Dictionary,b: Dictionary): return a["asset"]<b["asset"])
	return result

func refresh_notice() -> void:
	var positive: int=0
	for id in entries:
		var entry: Dictionary=entries[id]
		if entry["available"] and entry["enabled"].button_pressed and entry["weight"].value>0:
			positive+=1
	notice.text="No available model has a positive weight. New vehicles for this role will wait." if positive==0 else "%d available model%s with positive weight."%[positive,"" if positive==1 else "s"]

func apply(reset: bool) -> void:
	if studio.interior_tools.editing() or studio.mode!=opened_mode or studio.current()!=opened_doc:
		return
	studio.finish_edit(studio.canvas_pointer())
	if saved()!=opened_selection:
		notice.text="The saved fleet changed. Reload its choices before applying."
		return
	var doc: RefCounted=studio.current()
	var candidate: Dictionary=doc.data.duplicate(true)
	var config: Dictionary=candidate.get("fleet",{})
	if reset:
		config.erase(role())
	else:
		var selection: Array=choices()
		if not config.has(role()) and selection==Plan.selections(doc.data,role()):
			notice.text="The current default fleet already uses these choices."
			return
		config[role()]=selection
	if config.is_empty(): candidate.erase("fleet")
	else: candidate["fleet"]=config
	if candidate==doc.data:
		notice.text="The saved fleet already uses these choices."
		return
	var reviewed: Dictionary=Policy.check(doc.data,candidate,studio.library)
	if not reviewed["ok"]:
		notice.text=reviewed["reason"]
		return
	doc.checkpoint()
	doc.data=candidate
	studio.changed()
	doc.finish_checkpoint()
	load_choices()
	studio.status.text="Fleet choices saved. Existing vehicles keep their model."

func tick() -> void:
	if not panel.is_visible_in_tree(): return
	if studio.mode!=opened_mode or studio.current()!=opened_doc or not pending and saved()!=opened_selection:
		load_choices()
