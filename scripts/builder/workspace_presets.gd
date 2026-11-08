extends RefCounted

const NAMES: Array[String]=["custom","building","painting","exploring"]
const TOOLS: Array[String]=["select","place","erase","color","road","crossing","road_erase"]
var studio: Control
var center: Control
var choice: OptionButton
var focus_button: Button
var walk_button: Button
var mode_label: Label
var preset: String="custom"
var custom: Dictionary={}
var return_workspace: Dictionary={}
var focused: bool=false
var applying: bool=false
var suspended: bool=false
var header: Control
var toolbar: Control

func _init(host: Control,parent: Control) -> void:
	studio=host
	center=parent
	header=studio.dimension.get_parent()
	toolbar=studio.tools["erase"].get_parent()
	var row:=HFlowContainer.new()
	row.name="WorkspacePresets"
	center.add_child(row)
	center.move_child(row,1)
	choice=OptionButton.new()
	for name in ["Custom","Building","Painting","Exploring"]: choice.add_item(name)
	choice.fit_to_longest_item=false
	choice.clip_text=true
	choice.custom_minimum_size.x=112
	row.add_child(choice)
	choice.item_selected.connect(func(index: int): apply_preset(NAMES[index]))
	focus_button=Button.new()
	focus_button.text="Focus · F10"
	focus_button.clip_text=true
	focus_button.custom_minimum_size.x=116
	focus_button.toggle_mode=true
	focus_button.tooltip_text="Temporarily maximize the canvas; F10 restores the workspace. Saved state and actions remain visible."
	row.add_child(focus_button)
	focus_button.toggled.connect(set_focus)
	walk_button=Button.new()
	row.add_child(walk_button)
	walk_button.pressed.connect(func(): studio.set_walking(not studio.walking))
	mode_label=studio.label(row,"",12)
	for control in [studio.workspace_layout.library_toggle,studio.workspace_layout.inspector_toggle,studio.workspace_layout.advanced_toggle]:
		control.toggled.connect(func(_value: bool): mark_custom())
	for divider in [studio.workspace_layout.library_split,studio.workspace_layout.inspector_split]:
		divider.dragged.connect(func(_value: int): mark_custom())
	refresh()

func tab_title() -> String:
	var tabs: TabContainer=studio.workspace_layout.tabs
	return tabs.get_tab_title(tabs.current_tab) if tabs.current_tab>=0 else "Selection"

func snapshot() -> Dictionary:
	return {"layout":studio.workspace_layout.settings(),"tool":studio.tool,"tab":tab_title(),"walking":studio.walking,"preset":preset}

func mark_custom() -> void:
	if applying or suspended: return
	preset="custom"
	refresh()

func show_tab(title: String) -> void:
	var tabs: TabContainer=studio.workspace_layout.tabs
	for index in tabs.get_tab_count():
		if tabs.get_tab_title(index)==title and not tabs.is_tab_hidden(index): tabs.current_tab=index; return
	tabs.current_tab=0

func restore_snapshot(data: Dictionary) -> void:
	studio.set_walking(false)
	var tool: String=str(data.get("tool","select"))
	studio.set_tool(tool if TOOLS.has(tool) else "select")
	studio.workspace_layout.restore(data.get("layout",{}))
	show_tab(str(data.get("tab","Selection")))
	if data.get("walking",false) is bool and data.get("walking",false): studio.set_walking(true)

func apply_preset(name: String,remember: bool=true) -> void:
	if not NAMES.has(name): name="custom"
	studio.finish_edit(studio.ground_brush.last_pointer if studio.ground_brush.drawing else studio.canvas.get_local_mouse_position())
	if focused: set_focus(false)
	if name=="exploring" and preset=="exploring": refresh(); return
	if remember and preset=="custom": custom=snapshot()
	if name=="exploring" and remember:
		return_workspace=snapshot()
		return_workspace["walking"]=false
	applying=true
	preset=name
	match name:
		"custom": restore_snapshot(custom)
		"building":
			studio.set_walking(false)
			studio.set_tool("select")
			studio.workspace_layout.restore({"library_open":true,"inspector_open":true,"library_width":320,"inspector_width":280,"advanced":false})
			show_tab("Selection")
		"painting":
			studio.set_walking(false)
			studio.set_tool("color")
			studio.workspace_layout.restore({"library_open":false,"inspector_open":true,"library_width":296,"inspector_width":360,"advanced":false})
			show_tab("Colors")
		"exploring":
			studio.workspace_layout.restore({"library_open":false,"inspector_open":false})
			studio.set_walking(true)
	applying=false
	refresh()
	studio.status.text="Workspace · "+name.capitalize()+". Use Focus to maximize the canvas."

func walking_changed(enabled: bool) -> void:
	if not applying and not suspended and not enabled and preset=="exploring":
		applying=true
		var data: Dictionary=return_workspace if not return_workspace.is_empty() else custom
		preset=str(data.get("preset","custom"))
		if preset not in NAMES or preset=="exploring": preset="custom"
		restore_snapshot(data)
		applying=false
	refresh()

func set_focus(value: bool) -> void:
	if not value and "small_prop_tools" in studio and studio.small_prop_tools and studio.small_prop_tools.active and not studio.small_prop_tools.changing:
		studio.small_prop_tools.leave();return
	if value!=focused: studio.finish_edit(studio.ground_brush.last_pointer if studio.ground_brush.drawing else studio.canvas.get_local_mouse_position())
	focused=value
	studio.workspace_layout.focus_mode=value
	studio.workspace_layout.refresh()
	refresh()

func refresh() -> void:
	var focus_key: String=studio.control_settings.label_for("focus_canvas") if studio.control_settings else "F10"
	choice.select(maxi(0,NAMES.find(preset)))
	choice.tooltip_text="Workspace preset · "+preset.capitalize()+". Custom restores your panel settings; "+focus_key+" temporarily focuses the canvas."
	focus_button.set_pressed_no_signal(focused)
	focus_button.text=("Exit focus · " if focused else "Focus · ")+focus_key
	focus_button.tooltip_text="Temporarily maximize the canvas; "+focus_key+" restores the workspace. Saved state and actions remain visible."
	walk_button.text="Back to Build" if studio.walking else "Walk"
	walk_button.visible=focused or studio.walking
	mode_label.text="WALK" if studio.walking else "BUILD"
	mode_label.visible=focused
	header.visible=not focused
	toolbar.visible=not focused
	studio.mode_badge.visible=not focused
	studio.mode_template_bar.visible=not focused and not studio.walking
	studio.mode_road_bar.visible=not focused and not studio.walking

func settings() -> Dictionary:
	if preset=="custom": custom=snapshot()
	return {"preset":preset,"custom":custom.duplicate(true),"return_workspace":return_workspace.duplicate(true)}

func restore(value: Variant) -> void:
	var data: Dictionary=value if value is Dictionary else {}
	applying=true
	set_focus(false)
	custom=data.get("custom",{}).duplicate(true) if data.get("custom",{}) is Dictionary else {}
	return_workspace=data.get("return_workspace",{}).duplicate(true) if data.get("return_workspace",{}) is Dictionary else {}
	preset="custom"
	var name: String=str(data.get("preset","custom"))
	if NAMES.has(name) and name!="custom": apply_preset(name,false)
	else: studio.set_walking(false)
	applying=false
	refresh()
