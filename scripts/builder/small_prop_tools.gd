extends RefCounted
const Fit=preload("res://scripts/builder/asset_scale_preview.gd")
const Model2D=preload("res://scripts/builder/model_in_2d.gd")
var studio: Control
var active: bool=false
var isolated: bool=false
var changing: bool=false
var scope: String=""
var dimension: String=""
var previous: Dictionary={}
var previous_focus: bool=false
var pending_frame: int=0
var pending_magnify: bool=true
var panel: PanelContainer
var note: Label
var isolate_button: Button
var return_button: Button
var controls: HFlowContainer
func _init(owner_control: Control) -> void:
	studio=owner_control
	var actions:=HFlowContainer.new();actions.name="SmallPropActions";studio.height_input.get_parent().add_child(actions)
	for spec in [["Frame selection","small_props_focus"],["Magnify props","small_props_magnify"],["Isolate selection","small_props_isolate"]]:
		var button:=Button.new();button.text=spec[0];button.accessibility_name=spec[0];button.tooltip_text="Temporary editing view. Original object transforms and saved visibility are preserved.";actions.add_child(button);button.pressed.connect(func():studio._command(spec[1],null))
	var layer:=CanvasLayer.new();layer.name="SmallPropView";layer.layer=26;studio.add_child(layer)
	panel=PanelContainer.new();panel.name="TemporaryDetailView";panel.mouse_filter=Control.MOUSE_FILTER_STOP;layer.add_child(panel);panel.hide()
	var box:=VBoxContainer.new();panel.add_child(box);note=Label.new();note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(note);controls=HFlowContainer.new();box.add_child(controls)
	for spec in [["Frame","small_props_focus"],["Magnify","small_props_magnify"],["Show others","small_props_isolate"],["Return","small_props_return"]]:
		var button:=Button.new();button.text=spec[0];button.accessibility_name="Return to previous view" if spec[1]=="small_props_return" else spec[0];button.tooltip_text=button.accessibility_name;button.custom_minimum_size.y=44;controls.add_child(button);button.pressed.connect(func():studio._command(spec[1],null))
		if spec[1]=="small_props_isolate":isolate_button=button
		if spec[1]=="small_props_return":return_button=button
func context() -> String:
	var doc: RefCounted=studio.current()
	return studio.mode+":"+str(doc.get_instance_id())+(":"+str(doc.floor_uid) if "floor_uid" in doc else "")
func camera_state() -> Dictionary:
	var world: Node=studio.worlds[studio.mode]
	if studio.mode=="2d":return {"position":world.camera.position,"zoom":world.camera.zoom}
	return {"target":world.target,"distance":world.distance,"yaw":world.yaw,"pitch":world.pitch,"near":world.camera.near}
func stored_camera() -> Array:
	if dimension=="2d":return [previous["position"].x,previous["position"].y,previous["zoom"].x]
	return [previous["target"].x,previous["target"].y,previous["target"].z,previous["yaw"],previous["pitch"],previous["distance"]]
func selected_ids() -> Array:
	return studio.selection_items().map(func(item: Dictionary):return item["uid"])
func over_ui(at: Vector2) -> bool:
	return panel.is_visible_in_tree() and panel.get_global_rect().has_point(at)
func begin(magnify: bool=true,hide_others: Variant=null) -> void:
	if changing:return
	if studio.walking:studio.status.text="Return to Build before editing small props.";return
	changing=true;studio.finish_edit(studio.canvas_pointer());studio.set_tool("select")
	var ids: Array=selected_ids()
	if ids.is_empty():changing=false;studio.status.text="Select a prop or group first. Use the overlap list for objects on counters and shelves.";return
	studio.asset_id="";studio.selected_cell=null;studio.worlds[studio.mode].preview("",[0,0,0],"",1.0,false)
	if active and scope!=context():leave(false,false)
	if not active:
		scope=context();dimension=studio.mode;previous=camera_state();previous_focus=studio.workspace_presets.focused;active=true
		studio.workspace_presets.set_focus(true)
	if hide_others is bool:isolated=hide_others
	var world: Node=studio.worlds[dimension];world.detail_view_active=true
	if dimension=="3d":world.camera.near=minf(previous["near"],.01)
	frame(magnify);pending_frame=3;pending_magnify=magnify;synchronize();changing=false
	if studio.consumer_shell and studio.consumer_shell.active:studio.consumer_shell.close_overlays()
	return_button.grab_focus();studio.status.text="Temporary small-prop view. Edit at the original world scale; Return or Escape restores the previous view."
func toggle_isolation() -> void:
	if not active:begin(true,true);return
	isolated=not isolated;synchronize()
func frame(magnify: bool) -> void:
	var world: Node=studio.worlds[dimension];var ids: Array=selected_ids();var area: Vector2=Vector2(world.get_viewport().size)*.65
	area.y=minf(area.y,maxf(80,world.get_viewport().size.y-2*(panel.size.y+24)))
	if dimension=="2d":
		var bounds:=Rect2();var found: bool=false
		for id in ids:
			if not world.instances.has(id):continue
			var node: Node2D=world.instances[id];var box: Rect2=Fit.projected_geometry(node) if node.get_script()==Model2D else Fit.screen_bounds(node);bounds=bounds.merge(box) if found else box;found=true
		if not found:return
		bounds=bounds.grow(8 if magnify else 80);world.camera.position=bounds.get_center();world.camera.zoom=Vector2.ONE*clampf(minf(area.x/maxf(1,bounds.size.x),area.y/maxf(1,bounds.size.y)),.1,64 if magnify else 7)
	else:
		var bounds:=AABB();var found: bool=false
		for id in ids:
			if not world.instances.has(id):continue
			var box: AABB=Fit.render_bounds(world.instances[id]);bounds=bounds.merge(box) if found else box;found=true
		if not found:return
		var low:=Vector2(INF,INF);var high: Vector2=-low;var basis: Basis=world.camera.global_basis.inverse()
		for corner in 8:
			var point: Vector3=basis*(bounds.get_endpoint(corner)-bounds.get_center());low=low.min(Vector2(point.x,point.y));high=high.max(Vector2(point.x,point.y))
		var span: Vector2=high-low;world.target=bounds.get_center();world.distance=clampf(maxf(span.y,span.x/maxf(.1,area.x/area.y))*world.get_viewport().size.y/area.y,.08 if magnify else 4,120);world.update_camera()
func synchronize() -> void:
	if not active:return
	if scope!=context():leave(false,false);return
	var ids: Array=selected_ids()
	if ids.is_empty():leave(true,false);return
	studio.worlds[dimension].set_editor_focus(ids if isolated else [])
	isolate_button.text="Show others" if isolated else "Isolate"
	note.text="Temporary prop view · %d selected%s"%[ids.size()," · other objects hidden" if isolated else ""]
func leave(restore_camera: bool=true,finish: bool=true) -> void:
	if not active:return
	var same_scope: bool=scope==context()
	if finish and same_scope and not changing:
		changing=true;studio.finish_edit(studio.canvas_pointer());changing=false
	active=false;isolated=false;pending_frame=0;panel.hide()
	studio.workspace_presets.set_focus(previous_focus)
	var world: Node=studio.worlds.get(dimension)
	if is_instance_valid(world):
		world.set_editor_focus([]);world.detail_view_active=false
		if dimension=="3d":world.camera.near=previous["near"]
		if restore_camera and same_scope:
			if dimension=="2d":world.camera.position=previous["position"];world.camera.zoom=previous["zoom"]
			else:world.target=previous["target"];world.distance=previous["distance"];world.yaw=previous["yaw"];world.pitch=previous["pitch"];world.update_camera()
	scope="";previous={}
func tick() -> void:
	if not active:return
	if scope!=context():leave(false,false);return
	if studio.walking or studio.tool!="select" or studio.worlds[dimension].exploration.photo.active:leave(true,false);return
	synchronize()
	if not active:return
	if pending_frame>0:
		pending_frame-=1
		if pending_frame==0:frame(pending_magnify)
	panel.theme=studio.theme
	return_button.tooltip_text="Return to previous view · "+studio.control_settings.label_for("cancel")
	panel.visible=not studio.modal_visible()
	var rect: Rect2=studio.canvas.get_global_rect();var width: float=maxf(220,minf(760,rect.size.x-24));panel.size=Vector2(width,0)
	panel.position=Vector2(rect.position.x+(rect.size.x-width)*.5,maxf(rect.position.y+12,rect.end.y-panel.size.y-12))
