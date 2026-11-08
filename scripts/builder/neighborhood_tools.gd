extends RefCounted
const Plan=preload("res://scripts/builder/neighborhood_plan.gd")
var studio: Control
var panel: VBoxContainer
var dialog: AcceptDialog
var seed_input: SpinBox
var density: SpinBox
var blocks: SpinBox
var pattern: OptionButton
var theme: OptionButton
var origin_x: SpinBox
var origin_z: SpinBox
var summary: Label
var viewport: SubViewport
var preview_world: Node
var pending: Dictionary={}
var preview_digest: String=""
var preview_mode: String=""
var preview_ready: bool=false
var preview_generation: int=0
var theme_note: Label

func _init(owner_control: Control) -> void:
	studio=owner_control
	panel=VBoxContainer.new(); panel.name="Generate"; studio.workspace_layout.tabs.add_child(panel)
	studio.label(panel,"Procedural neighborhoods",17)
	var open:=Button.new(); open.text="Generate neighborhood…"; open.pressed.connect(show); panel.add_child(open)
	var help: Label=studio.label(panel,"Preview editable streets and themed buildings from a seed. Choose density, district size and road layout, then add the result as one Undo step.",13); help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	dialog=AcceptDialog.new(); dialog.title="Generate a neighborhood"; dialog.min_size=Vector2i(760,480); dialog.dialog_hide_on_ok=false; studio.add_child(dialog)
	dialog.get_ok_button().text="Add neighborhood"; dialog.get_ok_button().disabled=true; dialog.confirmed.connect(commit)
	dialog.visibility_changed.connect(func(): if not dialog.visible: clear_preview())
	var scroll:=ScrollContainer.new(); scroll.custom_minimum_size=Vector2(720,400); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; dialog.add_child(scroll)
	var row:=HBoxContainer.new(); row.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_theme_constant_override("separation",16); scroll.add_child(row)
	var fields:=VBoxContainer.new(); fields.custom_minimum_size.x=240; row.add_child(fields)
	seed_input=field(fields,"Seed",1,2147483647,1); density=field(fields,"Occupied parcels (%)",0,100,1); blocks=field(fields,"Block groups per side",1,4,1)
	studio.label(fields,"Road layout",13); pattern=OptionButton.new();pattern.accessibility_name="Neighborhood road layout"; fields.add_child(pattern)
	for text in ["Grid streets","Staggered junctions","Courtyard lanes"]: pattern.add_item(text)
	studio.label(fields,"Architectural theme",13); theme=OptionButton.new();theme.fit_to_longest_item=false;theme.accessibility_name="Neighborhood architectural theme"; fields.add_child(theme)
	for id in Plan.themes(): theme.add_item(Plan.themes()[id]["label"]); theme.set_item_metadata(theme.item_count-1,id)
	theme_note=studio.label(fields,"",12);theme_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	origin_x=field(fields,"Origin X · road-grid cells",-128,128,1); origin_z=field(fields,"Origin Z · road-grid cells",-128,128,1)
	var beside:=Button.new(); beside.text="Place beside existing city"; fields.add_child(beside); beside.pressed.connect(beside_city)
	var preview:=Button.new(); preview.text="Preview neighborhood"; fields.add_child(preview); preview.pressed.connect(generate)
	var preview_column:=VBoxContainer.new(); preview_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(preview_column)
	var zoom_controls:=HFlowContainer.new();preview_column.add_child(zoom_controls)
	for amount in [1.4,1.0/1.4]:
		var button:=Button.new();button.text="Zoom preview in" if amount>1 else "Zoom preview out";button.accessibility_name=button.text;zoom_controls.add_child(button);button.pressed.connect(func():zoom_preview(amount))
	var container:=SubViewportContainer.new(); container.stretch=true; container.custom_minimum_size=Vector2(420,260); container.size_flags_horizontal=Control.SIZE_EXPAND_FILL; container.size_flags_vertical=Control.SIZE_EXPAND_FILL; container.mouse_filter=Control.MOUSE_FILTER_IGNORE; preview_column.add_child(container)
	viewport=SubViewport.new(); viewport.size=Vector2i(640,360); viewport.own_world_3d=true; viewport.world_2d=World2D.new(); viewport.gui_disable_input=true; container.add_child(viewport)
	summary=studio.label(preview_column,"Choose settings, then preview. The city changes only when you add the neighborhood.",13); summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var notes: Label=studio.label(preview_column,"Each block group spans 80 ground units and contains four building parcels. Courtyard lanes merge cross-streets into longer blocks. Density 0% creates vacant streets. One road-grid cell is 8 ground units. Existing objects, lots and roads reserve their area. Generation keeps existing paving and rejects flooded or steep roads. Generated buildings, block groups, ground and roads remain editable.",12); notes.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	for control in [seed_input,density,blocks,origin_x,origin_z]: control.value_changed.connect(func(_value: float): invalidate())
	for control in [pattern,theme]: control.item_selected.connect(func(_index: int): invalidate();refresh_theme_note())

func field(parent: Node,text: String,low: float,high: float,step: float) -> SpinBox:
	studio.label(parent,text,13); var input: SpinBox=studio.spin(parent,low,high,step,low); input.accessibility_name=text; return input

func settings() -> Dictionary:
	return {"seed":int(seed_input.value),"density":int(density.value),"blocks":int(blocks.value),"pattern":Plan.PATTERNS[pattern.selected],"theme":theme.get_item_metadata(theme.selected),"origin":[int(origin_x.value),int(origin_z.value)]}

func show() -> void:
	if studio.interior_tools.editing() or studio.worlds[studio.mode].exploration.interior!=null: studio.status.text="Generate neighborhoods from the exterior city."; return
	studio.finish_edit(studio.canvas_pointer()); studio.set_walking(false); studio.current().finish_checkpoint(); clear_preview()
	var value: Dictionary=studio.current().data.get("neighborhood_generator",Plan.defaults())
	if not Plan.valid_settings(value): value=Plan.defaults()
	seed_input.set_value_no_signal(value["seed"]); density.set_value_no_signal(value["density"]); blocks.set_value_no_signal(value["blocks"])
	pattern.select(Plan.PATTERNS.find(value["pattern"]))
	for index in theme.item_count:
		if theme.get_item_metadata(index)==value["theme"]: theme.select(index)
	refresh_theme_note()
	var origin: Array=value["origin"] if studio.current().data.has("neighborhood_generator") else Plan.beside_city(studio.current().data,int(blocks.value),studio.library)
	origin_x.set_value_no_signal(origin[0]); origin_z.set_value_no_signal(origin[1]); summary.text="Preview before adding. Use ‘Place beside existing city’ to find space for another neighborhood."
	dialog.popup_centered(Vector2i(mini(1000,studio.get_viewport_rect().size.x-32),mini(650,studio.get_viewport_rect().size.y-48)))

func beside_city() -> void:
	var origin: Array=Plan.beside_city(studio.current().data,int(blocks.value),studio.library)
	origin_x.set_value_no_signal(origin[0]); origin_z.set_value_no_signal(origin[1]); invalidate()

func invalidate() -> void:
	clear_preview(); summary.text="Settings changed. Preview the neighborhood before adding it."

func refresh_theme_note() -> void:
	theme_note.text=Plan.themes()[theme.get_item_metadata(theme.selected)].get("note","Original neighborhood palette. Supplied source scale and ordinary editable buildings are preserved.")

func clear_preview() -> void:
	preview_generation+=1;preview_ready=false
	if is_instance_valid(preview_world): preview_world.free()
	preview_world=null; pending={}; preview_digest=""; preview_mode=""
	if dialog: dialog.get_ok_button().disabled=true

func generate() -> void:
	clear_preview()
	if studio.interior_tools.editing(): summary.text="Return to the exterior city first."; return
	var result: Dictionary=Plan.generate(studio.current().data,settings(),studio.library)
	if not result["ok"]: summary.text=result["reason"]; return
	var dependencies: Dictionary=Plan.Palettes.dependency_snapshot(studio.current().data,result["data"],studio.library)
	if not dependencies["ok"]:summary.text=dependencies["reason"];return
	result["dependencies"]=dependencies["files"]
	pending=result; preview_digest=studio.content_digest(); preview_mode=studio.mode
	preview_world=load("res://scripts/builder/world_"+studio.mode+".gd").new(); preview_world.library=studio.library; viewport.add_child(preview_world)
	var display: Dictionary=result["data"].duplicate(true)
	for field in ["citizens","traffic","businesses","services","economy","scenario","zoning","transit","weather","ambience"]:
		if display.get(field) is Dictionary:display[field]["enabled"]=false
	preview_world.apply(display)
	preview_world.grid.visible=false; preview_world.selection.visible=false; preview_world.player.set_physics_process(false); preview_world.player.visible=false
	frame(preview_world,result["bounds"],viewport.size)
	# Keep real collision shapes, but stop private actors, camera callbacks,
	# animations and input from changing this authored proposal during review.
	for child in [preview_world]+preview_world.find_children("*","",true,false):
		child.set_process(false);child.set_physics_process(false);child.set_process_input(false);child.set_process_unhandled_input(false);child.set_process_unhandled_key_input(false)
	summary.text="%d block groups · %d buildings · %d road sections · %d new ground tiles\n"%[result["blocks"],result["buildings"],result["roads"],result["ground_tiles"]]
	if result["parks"]+result["props"]>0:summary.text+="%d shared courtyard/park subjects · %d street props\n"%[result["parks"],result["props"]]
	if result["skipped_scenery"]>0:summary.text+="%d optional scenery choices omitted to preserve permissions and clear approaches.\n"%result["skipped_scenery"]
	if not result["note"].is_empty():summary.text+=result["note"]+"\n"
	if not result["appearance"].is_empty():summary.text+="%s · %s lighting\n"%[result["appearance"]["palette_id"].replace("_"," ").capitalize(),result["appearance"]["lighting_id"].replace("_"," ")]
	summary.text+=("Cost: %d credits.\n"%result["quote"].get("net",result["quote"].get("construction",0))) if result["quote"].get("enabled",true) else "Creative mode · unlimited construction.\n"
	summary.text+="Preparing rendered preview…" if result["affordable"] else result["quote"]["reason"]
	finish_preview.call_deferred(preview_world.get_instance_id(),preview_generation)

func finish_preview(world_id: int,request: int) -> void:
	if request!=preview_generation:return
	var world: Node=instance_from_id(world_id)
	if not is_instance_valid(world) or world!=preview_world:return
	for iteration in 4:
		await studio.get_tree().physics_frame
		if request!=preview_generation or not is_instance_valid(world) or world!=preview_world:return
	for iteration in 3:
		await studio.get_tree().process_frame
		if request!=preview_generation or not is_instance_valid(world) or world!=preview_world:return
	if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw
	if request!=preview_generation or not is_instance_valid(world) or world!=preview_world:return
	preview_ready=true;summary.text=summary.text.replace("Preparing rendered preview…","Ready to add as one Undo step.");dialog.get_ok_button().disabled=not pending["affordable"]

func zoom_preview(amount: float) -> void:
	if not is_instance_valid(preview_world):return
	if preview_world is Node2D:preview_world.camera.zoom=(preview_world.camera.zoom*amount).clamp(Vector2.ONE*.01,Vector2.ONE*30)
	else:preview_world.distance=clampf(preview_world.distance/amount,3,2000);preview_world.update_camera()

func frame(world: Node,area: Rect2,size: Vector2i) -> void:
	var point: Array=Plan.Traffic.world(area.get_center(),world.data_state["mode"])
	if world is Node2D:
		world.camera.position=Vector2(point[0],point[1]); var span: Vector2=Vector2((area.size.x+area.size.y)*8,(area.size.x+area.size.y)*4)
		world.camera.zoom=Vector2.ONE*minf(float(size.x)/span.x,float(size.y)/(span.y+160))*.85
	else:
		world.target=Vector3(point[0],0,point[2]); world.distance=area.size.length(); world.update_camera()

func commit() -> void:
	if pending.is_empty() or not preview_ready or not pending["affordable"]: return
	if preview_mode!=studio.mode or pending["config"]!=settings() or preview_digest!=studio.content_digest(): invalidate(); summary.text="The city changed. Preview again before adding this neighborhood."; return
	for path in pending["dependencies"]:
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path)!=pending["dependencies"][path]:invalidate();summary.text="The district's source assets or reviewed palette changed. Preview again before adding it.";return
	var dependencies: Dictionary=Plan.Palettes.dependency_snapshot(studio.current().data,pending["data"],studio.library)
	if not dependencies["ok"]:invalidate();summary.text=dependencies["reason"];return
	var old_size: int=studio.current().data["objects"].size();var people: Array[Vector2]=studio.zone_tools.occupied(studio.mode)
	for item in pending["data"]["objects"].slice(old_size):
		var box: Rect2=Plan.Zone.footprint(item,studio.mode,studio.library)
		if people.any(func(point: Vector2):return box.grow(.7).has_point(point)):summary.text="Waiting for people or vehicles to clear the proposed district. Add it again once the site is clear.";return
	var doc: RefCounted=studio.current(); doc.finish_checkpoint(); var before: Dictionary=doc.data.duplicate(true); var result: Dictionary=pending
	doc.data=result["data"]
	if not doc.record_completed_change(before,true): doc.data=before; summary.text="No neighborhood changes were recorded."; return
	studio.set_tool("select"); studio.clear_placement(); studio.selected_uids.clear()
	for item in doc.data["objects"].slice(before["objects"].size()): studio.selected_uids.append(item["uid"])
	studio.selected_uid=studio.selected_uids[0] if not studio.selected_uids.is_empty() else ""; dialog.hide(); studio.changed()
	frame(studio.worlds[studio.mode],result["bounds"],Vector2i(studio.canvas.size)); studio.status.text="Added %d editable buildings and %d road sections. Undo removes this neighborhood."%[result["buildings"],result["roads"]]

func cancel() -> void:
	dialog.hide(); clear_preview()
