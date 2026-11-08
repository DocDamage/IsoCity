extends RefCounted
const Plan=preload("res://scripts/builder/prop_plan.gd")
var studio: Control
var page: ScrollContainer
var panel: VBoxContainer
var caption: Label
var kind: OptionButton
var action_label: LineEdit
var duration: SpinBox
var reach: SpinBox
var initially_on: CheckButton
var target: OptionButton
var advanced: CheckButton
var anchors: VBoxContainer
var point_checks: Dictionary={}
var point_fields: Dictionary={}
var apply_button: Button
var restore_button: Button
var preview_button: Button
var status: Label
var setup: RefCounted
var dirty: Dictionary={}
var stamp: int=0
var elapsed: float=0
var refreshing: bool=false

func _init(owner_control: Control) -> void:
	studio=owner_control; page=ScrollContainer.new(); page.name="Props"; page.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_SHOW_NEVER; studio.workspace_layout.tabs.add_child(page)
	panel=VBoxContainer.new(); panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL; page.add_child(panel)
	var title: Label=studio.label(panel,"Usable furniture and props",17); title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	caption=studio.label(panel,"Select a prop to edit its interaction.",12); caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	setup=preload("res://scripts/builder/interaction_setup_tools.gd").new(studio,page,panel)
	studio.label(panel,"Interaction",12); kind=OptionButton.new(); kind.add_item("Automatic"); kind.set_item_metadata(0,"auto"); kind.add_item("Disabled"); kind.set_item_metadata(1,"none")
	for value in Plan.KINDS: kind.add_item({"seat":"Sit / stand","swing":"Swing ride","slide":"Slide ride","switch":"Power switch","appliance":"Appliance cycle"}[value]); kind.set_item_metadata(kind.item_count-1,value)
	kind.accessibility_name="Prop interaction"
	panel.add_child(kind); kind.item_selected.connect(func(_index: int): mark("kind"); refresh_defaults())
	studio.label(panel,"Action name (optional)",12); action_label=LineEdit.new(); action_label.placeholder_text="Automatic action name"; action_label.accessibility_name="Interaction action name"; action_label.max_length=160; panel.add_child(action_label); action_label.text_changed.connect(func(_text: String):mark("label"))
	duration=field(panel,"Cycle seconds",.5,60,.5); duration.value_changed.connect(func(_value: float):mark("duration"))
	reach=field(panel,"Interaction range · ground units",.5,6,.1); reach.value_changed.connect(func(_value: float):mark("reach"))
	initially_on=CheckButton.new(); initially_on.text="Start powered"; panel.add_child(initially_on); initially_on.toggled.connect(func(_value: bool):mark("initial_on"))
	studio.label(panel,"Switch target · same room / floor",12); target=OptionButton.new(); target.accessibility_name="Switch target"; panel.add_child(target); target.item_selected.connect(func(_index: int):mark("target"); refresh_defaults())
	advanced=CheckButton.new(); advanced.text="Source anchors"; panel.add_child(advanced); advanced.toggled.connect(func(value: bool):anchors.visible=value)
	anchors=VBoxContainer.new(); anchors.visible=false; panel.add_child(anchors)
	for key in Plan.POINTS:
		var names: Dictionary={"point":"Use point","approach":"Operator approach","end":"Slide landing","exit":"Exit","facing":"Look toward","customer":"Customer position"}
		var check:=CheckButton.new(); check.text={"point":"Use point override","approach":"Approach override","end":"Landing override","exit":"Exit override","facing":"Facing override","customer":"Customer override"}[key]; check.accessibility_name=names[key]+" override"; check.tooltip_text=names[key]+" in asset source coordinates"; anchors.add_child(check); point_checks[key]=check
		var fields: Array[SpinBox]=[]
		for axis in ["X","Height","Depth"]:
			var input: SpinBox=field(anchors,axis,-64,64,.05); input.accessibility_name=names[key]+" · "+axis; input.value_changed.connect(func(_value: float):mark(key)); fields.append(input)
		point_fields[key]=fields; check.toggled.connect(func(value: bool):mark(key); enable_point(key,value))
	var help: Label=studio.label(anchors,"Offsets use the asset's source centre and heading. Sprite views, rotation and scale transform these points. Use points follow visible artwork; approach and exit use walking clearance. Look toward is a target point. Customer position is a separate setup marker; it does not create a customer or job. Leave overrides off for calibrated defaults.",12); help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	apply_button=button("Apply changes",apply_settings); restore_button=button("Restore automatic",restore_selected); preview_button=button("Explore prop",preview_selected)
	status=studio.label(panel,"Use Interact while walking beside a prop. Use it again to stand, stop or cancel. Completed appliance cycles award session results. Switches may control a light or appliance on the same floor.",12); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var note: Label=studio.label(panel,"Only changed controls apply to the selection. Edits share normal Undo, including inside owned rooms. Use poses, power states and results are session-only; loading a project clears them. Hidden, missing or blocked props cannot be used.",12); note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	studio.workspace_layout.prepare_controls(panel)
	studio.get_viewport().gui_focus_changed.connect(reveal_focus)

func reveal_focus(control: Control) -> void:
	if not is_instance_valid(control) or not page.is_ancestor_of(control):return
	for frame in 2:await studio.get_tree().process_frame
	if not is_instance_valid(control) or not control.has_focus() or not page.is_ancestor_of(control):return
	page.ensure_control_visible(control)
	var outer: ScrollContainer=studio.accessibility_settings.root_scroll
	if is_instance_valid(outer) and outer.is_ancestor_of(control):outer.ensure_control_visible(control)

func field(parent: VBoxContainer,title: String,low: float,high: float,step: float) -> SpinBox:
	studio.label(parent,title,12); var result: SpinBox=studio.spin(parent,low,high,step,low); result.accessibility_name=title; return result
func button(title: String,callback: Callable) -> Button:
	var result:=Button.new(); result.text=title; result.clip_text=true; panel.add_child(result); result.pressed.connect(callback); return result
func start() -> void: refresh()
func mark(key: String) -> void:
	if not refreshing: dirty[key]=true; apply_button.disabled=studio.selection_items().is_empty()
func enable_point(key: String,value: bool) -> void:
	for input in point_fields[key]: input.editable=value
func chosen_kind() -> String: return str(kind.get_item_metadata(kind.selected))
func show() -> void:
	studio.set_walking(false); studio.workspace_presets.set_focus(false)
	if studio.get_viewport_rect().size.x<1200: studio.workspace_layout.library_toggle.button_pressed=false
	studio.workspace_layout.inspector_toggle.button_pressed=true; studio.workspace_layout.tabs.current_tab=page.get_index(); stamp=0; refresh()
func refresh() -> void:
	if studio.documents.is_empty(): return
	var items: Array=studio.selection_items(); var targets: Array=[]; var records: Array=[]
	for item in items: records.append([item["uid"],item["asset"],item["direction"],item.get("prop",{})])
	for item in studio.current().data.get("objects",[]):
		if Plan.power_device(item): targets.append([item["uid"],item.get("name",studio.library.assets.get(item["asset"],{}).get("name",item["asset"])),item.get("prop",{})])
	var next: int=hash([studio.mode,studio.interior_tools.uid,studio.current().get("floor_uid"),records,targets])
	if next==stamp: return
	stamp=next; dirty.clear(); refreshing=true; var item: Dictionary=items[0] if not items.is_empty() else {}; var raw: Dictionary=item.get("prop",{})
	var selected: String=raw.get("kind","auto") if raw.get("enabled",true) else "none"
	for index in kind.item_count:
		if kind.get_item_metadata(index)==selected: kind.select(index)
	action_label.text=raw.get("label",""); initially_on.set_pressed_no_signal(raw.get("initial_on",false))
	target.clear(); target.add_item("This prop"); target.set_item_metadata(0,"")
	for value in targets:
		if items.size()==1 and value[0]==item["uid"]: continue
		target.add_item(str(value[1])); target.set_item_metadata(target.item_count-1,value[0]); target.set_item_tooltip(target.item_count-1,str(value[1])+" · "+str(value[0]))
	var target_uid: String=raw.get("target",""); var found: bool=target_uid.is_empty()
	for index in target.item_count:
		if target.get_item_metadata(index)==target_uid: target.select(index); found=true
	if not found: target.add_item("Unavailable target"); target.set_item_metadata(target.item_count-1,target_uid); target.select(target.item_count-1)
	for key in point_checks: point_checks[key].set_pressed_no_signal(raw.has(key)); enable_point(key,raw.has(key))
	var mixed: bool=items.any(func(value: Dictionary)->bool:return value.get("prop",{})!=raw)
	caption.text="Select an editable object to author its interaction." if items.is_empty() else "%d selected%s · only changed controls apply."%[items.size()," · settings differ" if mixed else ""]
	apply_button.disabled=true; restore_button.disabled=items.is_empty(); preview_button.disabled=items.size()!=1; refreshing=false; refresh_defaults()
func refresh_defaults() -> void:
	var items: Array=studio.selection_items()
	if items.is_empty(): return
	var item: Dictionary=items[0].duplicate(true); var raw: Dictionary=item.get("prop",{}).duplicate(true)
	if dirty.has("kind"): raw["kind"]=chosen_kind(); raw["enabled"]=true
	if dirty.has("target"): raw["target"]=target.get_item_metadata(target.selected)
	item["prop"]=raw; var profile: Dictionary=Plan.profile(item)
	if profile.is_empty(): profile=Plan.definitions()["kinds"]["seat"].duplicate(true); profile["kind"]="none"
	refreshing=true
	if not dirty.has("duration"): duration.set_value_no_signal(profile["duration"])
	if not dirty.has("reach"): reach.set_value_no_signal(profile["reach"])
	for key in point_fields:
		if dirty.has(key): continue
		var point: Vector3=Plan.edit_point(profile,item,studio.library,key)
		for axis in 3: point_fields[key][axis].set_value_no_signal(point[axis])
	var linked: bool=profile["kind"]=="switch" and not str(profile.get("target","")).is_empty()
	duration.editable=profile["kind"] in ["appliance","slide"]; initially_on.disabled=profile["kind"] not in ["appliance","switch"] or linked; target.disabled=profile["kind"]!="switch"
	initially_on.tooltip_text="Set starting power on the target prop." if linked else "Power state when this device first enters an exploration session."
	if linked: initially_on.set_pressed_no_signal(false); dirty.erase("initial_on")
	elif not dirty.has("initial_on"): initially_on.set_pressed_no_signal(raw.get("initial_on",false))
	refreshing=false
	preview_button.disabled=items.size()!=1 or profile["kind"]=="none"
func apply_settings() -> void:
	if dirty.is_empty(): return
	change_selected(false)
func restore_selected() -> void: change_selected(true)
func change_selected(automatic: bool) -> void:
	studio.finish_edit(studio.canvas_pointer()); var items: Array=studio.selection_items()
	if items.is_empty(): return
	var doc: RefCounted=studio.current(); doc.checkpoint()
	for item in items:
		if automatic: item.erase("prop"); continue
		var raw: Dictionary=item.get("prop",{}).duplicate(true)
		for key in dirty:
			match key:
				"kind": raw["kind"]=chosen_kind(); raw["enabled"]=true
				"label":
					if action_label.text.strip_edges().is_empty(): raw.erase("label")
					else: raw["label"]=action_label.text.strip_edges()
				"duration": raw["duration"]=duration.value
				"reach": raw["reach"]=reach.value
				"initial_on": raw["initial_on"]=initially_on.button_pressed
				"target": raw["target"]=target.get_item_metadata(target.selected)
				_:
					if point_checks[key].button_pressed: raw[key]=[point_fields[key][0].value,point_fields[key][1].value,point_fields[key][2].value]
					else: raw.erase(key)
		item["prop"]=raw
	doc.finish_checkpoint(); studio.changed(); stamp=0; refresh(); studio.status.text="Restored automatic interaction." if automatic else "Saved changed interaction controls for %d objects."%items.size()
func preview_selected() -> void:
	if not dirty.is_empty(): apply_settings()
	var items: Array=studio.selection_items()
	if items.size()!=1 or Plan.profile(items[0]).is_empty(): studio.status.text="Choose an interaction type before exploring this prop."; return
	var item: Dictionary=items[0]; var world: Node=studio.worlds[studio.mode]; var node: Node=world.instances.get(item["uid"])
	if not is_instance_valid(node): return
	var candidate: Dictionary={"item":item,"node":node,"profile":Plan.profile(item)}
	var global_point: Variant=Plan.ground_point(candidate,world.exploration,"approach"); var choices: Array=[global_point]; var found: bool=false
	var old_mask: int=world.player.collision_mask; world.player.collision_mask=1 if studio.mode=="2d" else 3
	for radius in ([12.0,24.0,36.0] if studio.mode=="2d" else [.4,.8,1.2]):
		for turn in 8:
			var offset: Vector2=Vector2.RIGHT.rotated(turn*TAU/8)*float(radius)
			choices.append(global_point+(offset if studio.mode=="2d" else Vector3(offset.x,0,offset.y)))
	for point in choices:
		var clear: bool
		if studio.mode=="2d": clear=world.player.clear_at(point)
		else:
			var transform: Transform3D=world.player.global_transform; transform.origin=point; clear=world.player.clear_at(transform)
		if clear and (not world.player.terrain_position_safe.is_valid() or world.player.terrain_position_safe.call(point)): global_point=point; found=true; break
	world.player.collision_mask=old_mask
	if not found: studio.status.text="The prop approach is blocked. Clear a standing space or adjust its approach anchor."; return
	world.player.teleport_to(world.player.get_parent().to_local(global_point)); studio.set_walking(true)
	studio.status.text="Use "+studio.control_settings.label_for("interact")+" beside the selected prop. Use it again to stop or stand."
func tick(delta: float) -> void:
	elapsed+=delta
	if elapsed>=.2: elapsed=0; refresh(); setup.refresh()
func reset() -> void: stamp=0; dirty.clear()
