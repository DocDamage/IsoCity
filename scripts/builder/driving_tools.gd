extends RefCounted
const Plan=preload("res://scripts/builder/driving_plan.gd")
var studio: Control
var page: ScrollContainer
var caption: Label
var enabled: CheckButton
var fields: Dictionary={}
var dirty: Dictionary={}
var loading: bool=false
var stamp: int=0
var elapsed: float=0
var apply_button: Button
var preview_button: Button
func _init(owner_control: Control) -> void:
	studio=owner_control; page=ScrollContainer.new(); page.name="Driving"; page.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; page.follow_focus=true; studio.workspace_layout.tabs.add_child(page)
	var box:=VBoxContainer.new(); box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; box.add_theme_constant_override("separation",8); page.add_child(box)
	studio.label(box,"Drive placed vehicles",17); caption=studio.label(box,"Select a road vehicle.",12); caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var explanation: Label=studio.label(box,"Use Interact beside a car to enter or exit. Forward/back accelerate and reverse; left/right steer. The Jump control brakes. Stop beside clear walking space to exit. Driving is a play-session activity; Build restores the layout.",12); explanation.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	enabled=CheckButton.new(); enabled.text="Allow driving"; box.add_child(enabled); enabled.toggled.connect(func(_value: bool): if not loading: dirty["enabled"]=true)
	for spec in [["max_speed","Forward m/s",.5,24,.5],["reverse_speed","Reverse m/s",.5,24,.5],["acceleration","Acceleration",.5,20,.5],["braking","Braking",.5,20,.5],["steering","Steering",.2,4,.1],["reach","Entry reach",.5,6,.1]]:
		var row:=VBoxContainer.new(); box.add_child(row); studio.label(row,spec[1],12)
		var field:=SpinBox.new(); field.min_value=spec[2]; field.max_value=spec[3]; field.step=spec[4]; field.size_flags_horizontal=Control.SIZE_EXPAND_FILL; field.accessibility_name=spec[1]; row.add_child(field); fields[spec[0]]=field
		var key: String=spec[0]; field.value_changed.connect(func(_value: float): if not loading: dirty[key]=true)
	apply_button=button(box,"Apply changes",apply_settings); button(box,"Restore defaults",restore_selected); preview_button=button(box,"Drive selected vehicle",preview_selected)
func button(parent: Node,title: String,callback: Callable) -> Button:
	var control:=Button.new(); control.text=title; control.custom_minimum_size.y=36; parent.add_child(control); control.pressed.connect(callback); return control
func items() -> Array:
	return studio.selection_items().filter(func(item: Dictionary)->bool:return Plan.definitions()["assets"].has(item["asset"]))
func show() -> void:
	if studio.walking: studio.set_walking(false)
	if studio.get_viewport_rect().size.x<1200: studio.workspace_layout.library_toggle.button_pressed=false
	studio.workspace_presets.set_focus(false); studio.workspace_layout.inspector_toggle.button_pressed=true
	studio.workspace_layout.tabs.current_tab=page.get_index(); stamp=0; refresh()
func refresh() -> void:
	if studio.documents.is_empty(): return
	var selected: Array=items(); var next_stamp: int=hash([studio.mode,studio.interior_tools.editing(),selected])
	if next_stamp==stamp: return
	stamp=next_stamp; dirty.clear(); loading=true
	var config: Dictionary=Plan.definitions()["defaults"].duplicate(true)
	if not selected.is_empty(): config.merge(selected[0].get("driving",{}),true)
	enabled.set_pressed_no_signal(config["enabled"])
	for key in fields: fields[key].set_value_no_signal(config[key]); fields[key].editable=not selected.is_empty()
	var mixed: bool=not selected.is_empty() and selected.any(func(item: Dictionary)->bool:return item.get("driving",{})!=selected[0].get("driving",{}))
	caption.text=("%d editable vehicles · values differ; only changed fields apply." if mixed else "%d editable vehicles selected.")%selected.size()
	if studio.interior_tools.editing(): caption.text="Drive vehicles in the exterior city."
	enabled.disabled=selected.is_empty() or studio.interior_tools.editing(); apply_button.disabled=enabled.disabled; preview_button.disabled=selected.size()!=1 or studio.interior_tools.editing(); loading=false
func change(restore: bool) -> void:
	if studio.interior_tools.editing(): return
	var selected: Array=items()
	if selected.is_empty() or (dirty.is_empty() and not restore): return
	var changes: Array=[]
	for item in selected:
		var raw: Dictionary=item.get("driving",{}).duplicate(true)
		for key in dirty: raw[key]=enabled.button_pressed if key=="enabled" else fields[key].value
		if (restore and item.has("driving")) or (not restore and raw!=item.get("driving",{})): changes.append({"item":item,"raw":raw})
	if changes.is_empty(): return
	studio.finish_edit(studio.canvas_pointer()); studio.current().checkpoint()
	for entry in changes:
		if restore: entry["item"].erase("driving")
		else: entry["item"]["driving"]=entry["raw"]
	studio.current().finish_checkpoint(); studio.changed(); stamp=0; refresh(); studio.status.text="Driving settings saved for %d vehicles."%changes.size()
func apply_settings() -> void: change(false)
func restore_selected() -> void: change(true)
func preview_selected() -> void:
	if not dirty.is_empty(): apply_settings()
	var selected: Array=items()
	if selected.size()!=1 or studio.interior_tools.editing(): return
	var item: Dictionary=selected[0]
	if Plan.profile(item).is_empty(): studio.status.text="Enable driving for the selected vehicle first."; return
	var world: Node=studio.worlds[studio.mode]; var player: Node=world.player; var center: Vector2=Plan.center(item,studio.library,studio.mode); var extent: Vector2=Plan.dimensions(item,studio.library,studio.mode); var forward: Vector2=Plan.heading(Plan.yaw(item)); var right:=Vector2(forward.y,-forward.x)
	var terrain=preload("res://scripts/builder/terrain_plan.gd"); var heights: Dictionary=terrain.lookup(studio.current().data); var found: bool=false; var destination: Variant
	var old_mask: int=player.collision_mask; player.collision_mask=1 if studio.mode=="2d" else 3
	for offset in [right*(extent.x+.8),-right*(extent.x+.8),forward*(extent.y+.8),-forward*(extent.y+.8)]:
		var point: Vector2=center+offset; var height: float=terrain.sample(studio.current().data,point,heights)["height"] if terrain.settings(studio.current().data)["enabled"] else 0.0
		var at: Variant=world.to_global(Plan.world(point,studio.mode,height)); var clear: bool
		if studio.mode=="3d":
			var supported: Variant=world.terrain_traversal.start_candidate(point,at,false)
			if supported==null: continue
			at=supported
		if studio.mode=="2d": clear=player.clear_at(at)
		else:
			var transform: Transform3D=player.global_transform; transform.origin=at; clear=player.clear_at(transform)
		if clear and (not player.terrain_position_safe.is_valid() or player.terrain_position_safe.call(at)): destination=at; found=true; break
	player.collision_mask=old_mask
	if not found: studio.status.text="Vehicle entry is blocked. Clear walking space beside the vehicle."; return
	player.teleport_to(player.get_parent().to_local(destination)); studio.set_walking(true)
	var candidate: Dictionary=world.exploration.driving.nearby(item["uid"])
	if not candidate.is_empty() and candidate["item"]["uid"]==item["uid"]: world.exploration.driving.interact(candidate)
	studio.status.text="Use "+studio.control_settings.label_for("interact")+" to exit after stopping."
func tick(delta: float) -> void:
	elapsed+=delta
	if elapsed>=.2: elapsed=0; refresh()
