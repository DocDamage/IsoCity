extends RefCounted
const Plan=preload("res://scripts/builder/blueprint_plan.gd")
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
const Terrain=preload("res://scripts/builder/terrain_plan.gd")
var studio: Control
var panel: ScrollContainer
var list: ItemList
var detail: Label
var selected: String=""
var dragging: bool=false
var start: Vector2i
var end: Vector2i
var containers: Dictionary={}
var stamps: Dictionary={}
var list_stamp: int=0
var assembly_road: String=""
const Costs = preload("res://scripts/builder/construction_cost.gd")
var reviewed: String=""
var cost_scan: RefCounted
var review_ids: Array = []
var quote_stamp: String = ""
var quote_elapsed: float = 0.0
var review_label: Label
var review_button: Button
var require_sockets: CheckButton
func _init(host: Control) -> void:
	studio=host; panel=ScrollContainer.new(); panel.name="Blueprints"; panel.follow_focus=true; panel.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; studio.workspace_layout.tabs.add_child(panel)
	var box:=VBoxContainer.new(); box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; panel.add_child(box)
	studio.label(box,"Blueprint planning",17)
	require_sockets=CheckButton.new()
	require_sockets.text="Keep existing outside socket links"
	require_sockets.accessibility_name="Require existing outside socket connections in the assembly"
	require_sockets.tooltip_text="Keep links from the selection to existing city sockets. Those sockets must be free before construction."
	require_sockets.clip_text=true
	box.add_child(require_sockets)
	button(box,"Copy to blueprint",capture_assembly)
	button(box,"Add assembly road",sketch_assembly_road)
	button(box,"Sketch building footprints",func(): activate("blueprint_building"))
	button(box,"Sketch roads (use Roads settings)",func(): activate("blueprint_road"))
	button(box,"Add building footprint at view center",add_center)
	button(box,"Stop sketching",func(): cancel(); studio.set_tool("select"))
	list=ItemList.new(); list.custom_minimum_size=Vector2(160,156); list.accessibility_name="Construction proposals"; box.add_child(list)
	list.item_selected.connect(func(index: int):
		selected=list.get_item_metadata(index)
		reviewed=""
		review_ids.clear()
		quote_stamp=""
		review_label.text=""
	)
	button(box,"Locate selected proposal",locate)
	button(box,"Move selected proposal to view center",move_selected)
	button(box,"Rotate selected building",rotate_selected)
	button(box,"Apply current road settings to selected",resurface)
	review_button=button(box,"Review construction costs",func(): review(ids(false)))
	review_label=studio.label(box,"",12); review_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; review_label.accessibility_name="Construction review"; review_label.focus_mode=Control.FOCUS_ALL
	button(box,"Commit selected proposal",func(): construct(false))
	button(box,"Commit all proposals",func(): construct(true))
	button(box,"Discard selected proposal",func(): discard(false))
	button(box,"Discard all proposals",func(): discard(true))
	detail=studio.label(box,"",12); detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	studio.label(box,"Choose a building in the library, then activate footprint sketching and click the canvas. Drag to sketch roads using the Roads tab width, surface and sidewalks. Right-click cancels a drag. Proposals are translucent, saved with the city and support Undo. Construction charges the current budget only when committed; a failed commit keeps every proposal. Use Copy to blueprint to include saved rooms and interactions. Move the copy clear of its source, add roads, then review the total cost. Planning is available in the exterior city.",12).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	studio.get_viewport().gui_focus_changed.connect(reveal_focus)
	panel.resized.connect(func(): reveal_focus(studio.get_viewport().gui_get_focus_owner()))

func reveal_focus(control: Control) -> void:
	if not is_instance_valid(control) or not panel.is_ancestor_of(control): return
	for frame in 2: await studio.get_tree().process_frame
	if not is_instance_valid(control) or not control.has_focus() or not panel.is_visible_in_tree() or not panel.is_ancestor_of(control): return
	panel.ensure_control_visible(control)
	var outer: ScrollContainer=studio.accessibility_settings.root_scroll
	if is_instance_valid(outer) and outer.is_ancestor_of(control): outer.ensure_control_visible(control)

func button(parent: Node,title: String,callback: Callable) -> Button:
	var value:=Button.new()
	value.text=title
	value.tooltip_text=title
	value.accessibility_name=title
	value.clip_text=true
	parent.add_child(value)
	value.pressed.connect(callback)
	return value
func show() -> void:
	studio.workspace_presets.set_focus(false); studio.set_walking(false); studio.workspace_layout.inspector_toggle.button_pressed=true; studio.workspace_layout.tabs.current_tab=panel.get_index()
func editable() -> bool:
	if studio.interior_tools.editing(): studio.status.text="Plan construction from the exterior city."; return false
	if studio.walking: return false
	for layer in ["Buildings","Ground"]:
		if preload("res://scripts/builder/layers.gd").locked(studio.current().data,layer) or not preload("res://scripts/builder/layers.gd").shown(studio.current().data,layer): studio.status.text="Show and unlock Buildings and Ground to edit blueprints."; return false
	return true
func activate(tool: String) -> void:
	if not editable(): return
	assembly_road=""
	studio.finish_edit(studio.canvas_pointer()); studio.clear_assembly(); studio.set_tool(tool); studio.status.text="Blueprint · click a building footprint or drag a road proposal."
func cancel() -> void:
	dragging=false; studio.stroke=false; stamps.clear()
func ids(all_entries: bool) -> Array:
	var result: Array=[]
	for entry in studio.current().data.get("blueprints",[]):
		if all_entries or entry["uid"]==selected: result.append(entry["uid"])
	return result
func entry() -> Dictionary:
	for value in studio.current().data.get("blueprints",[]):
		if value["uid"]==selected: return value
	return {}
func commit(before: Dictionary) -> bool:
	var doc: RefCounted=studio.current()
	var ok: bool=doc.record_completed_change(before); studio.changed()
	if ok: doc.economy_error=""
	elif not doc.economy_error.is_empty(): studio.status.text=doc.economy_error
	return ok
func add(value: Dictionary) -> void:
	if not editable(): return
	var doc: RefCounted=studio.current(); doc.finish_checkpoint()
	if doc.data.get("blueprints",[]).size()>=Plan.LIMIT: studio.status.text="The city already has 512 proposals."; return
	value["uid"]="plan_%s_%s" % [Time.get_ticks_usec(),randi()]
	var candidates: Array=doc.data.get("blueprints",[]).duplicate(); candidates.append(value)
	if not Plan.valid(candidates,studio.mode,studio.library): studio.status.text="Invalid proposal: each road supports 256 sections, with 4096 planned sections per city."; return
	var before: Dictionary=doc.data.duplicate(true)
	if not doc.data.has("blueprints"): doc.data["blueprints"]=[]
	doc.data["blueprints"].append(value); selected=value["uid"]; commit(before)
func capture_assembly() -> void:
	if not editable(): return
	var items: Array=studio.selection_items()
	if items.is_empty():
		studio.status.text="Select the objects to copy into a functional assembly."
		return
	var names: Dictionary={}
	var groups: Dictionary=studio.current().data.get("group_names",{})
	for item in items:
		var group: String=item.get("group","")
		if groups.has(group): names[group]=groups[group]
	var title: String=items[0].get("name",studio.library.assets[items[0]["asset"]]["name"])
	var copies: Array=items.duplicate(true)
	for copy in copies: copy.erase("traffic_control")
	add({"kind":"assembly","version":1,"name":(title+" assembly").left(128),"objects":copies,"group_names":names,"roads":[],"connections":capture_connections(items),"external_targets":Plan.Assembly.external_targets(items)})
	reviewed=""
	review_label.text="Move this assembly to an open site and review it before construction."

func capture_connections(items: Array) -> Array:
	var links: Array=studio.selection_connections(items)
	if not require_sockets.button_pressed:
		return links
	var selected_ids: Dictionary={}
	for item in items:
		selected_ids[item["uid"]]=true
	for link in studio.current().data.get("connections",[]):
		var from_selected: bool=selected_ids.has(link["from"]["object_uid"])
		var to_selected: bool=selected_ids.has(link["to"]["object_uid"])
		if from_selected==to_selected:
			continue
		var required: Dictionary=link.duplicate(true)
		var side: String="to" if from_selected else "from"
		required[side]["external"]=true
		links.append(required)
	return links

func sketch_assembly_road() -> void:
	if not editable() or entry().get("kind")!="assembly":
		studio.status.text="Select an assembly proposal to add a road."
		return
	var target: String=selected
	activate("blueprint_road")
	assembly_road=target
	studio.status.text="Drag a road run for the selected assembly."

func finish_road(road: Dictionary) -> void:
	if assembly_road.is_empty():
		var legacy: Dictionary=road.duplicate()
		legacy["kind"]="road"
		add(legacy)
		return
	var doc: RefCounted=studio.current()
	doc.finish_checkpoint()
	var before: Dictionary=doc.data.duplicate(true)
	for proposal in doc.data.get("blueprints",[]):
		if proposal["uid"]!=assembly_road or proposal["kind"]!="assembly": continue
		proposal["roads"].append(road)
		if not Plan.valid(doc.data["blueprints"],studio.mode,studio.library):
			doc.data=before
			studio.status.text="The road run exceeds the assembly or city limit."
			return
		commit(before)
		reviewed=""
		review_label.text="Road added. Review the assembly again."
		return
	studio.status.text="The assembly changed. Select it again to add a road."

func fingerprint(data: Dictionary, selected_ids: Array) -> String:
	var session: Node=studio.cooperative_tools.session
	return JSON.stringify([data,selected_ids,studio.library.project_palette_revision,session.revision,session.local_id]).sha256_text()

func checked(data: Dictionary, selected_ids: Array) -> Dictionary:
	var result: Dictionary=Plan.construct(data,selected_ids,studio.library)
	var session: Node=studio.cooperative_tools.session
	if result["ok"] and session.connected and session.role=="client":
		var before: Dictionary=studio.cooperative_tools.snapshot()
		var after: Dictionary=before.duplicate(false)
		after[studio.mode]=result["data"]
		var reason: String=preload("res://scripts/builder/cooperative_plan.gd").allowed(before,after,session.local_id,studio.library)
		if not reason.is_empty(): return Plan.Assembly.failure(reason)
	return result

func review(selected_ids: Array) -> void:
	var data: Dictionary=studio.current().data
	var result: Dictionary=checked(data,selected_ids)
	reviewed=""
	review_ids = selected_ids.duplicate()
	quote_stamp = fingerprint(data, selected_ids)
	if not cost_scan: cost_scan = Costs.new(studio.library)
	if not result["ok"]:
		review_label.text = result["reason"] if not result.has("quote") else cost_text(data, result)
		return
	if not result.get("changed",false):
		review_label.text="Select a proposal to review."
		return
	review_label.text = cost_text(data, result) + "\nConstruction is ready. Commit when ready."
	var external_count: int=0
	var socket_count: int=0
	for proposal in data.get("blueprints",[]):
		if proposal["uid"] not in selected_ids:
			continue
		external_count+=proposal.get("external_targets",[]).size()
		for edge in proposal.get("connections",[]):
			if edge["from"].get("external",false) or edge["to"].get("external",false):
				socket_count+=1
	if external_count==1: review_label.text+=" Uses one existing device."
	elif external_count>1: review_label.text+=" Uses %d existing devices."%external_count
	if socket_count==1: review_label.text+=" Uses one existing socket."
	elif socket_count>1: review_label.text+=" Uses %d existing sockets."%socket_count
	reviewed=quote_stamp

func cost_text(before: Dictionary, result: Dictionary) -> String:
	return Costs.quote_text(result["quote"]) + "\n\n" + cost_scan.render_text(before, result["data"])

func building_item(pose: Dictionary) -> Dictionary:
	var item: Dictionary=studio.placement_record(); item["position"]=pose["position"]; item["direction"]=pose["direction"]; item["scale"]=studio.scale_input.value; return item
func locate() -> void:
	if entry().is_empty(): return
	var bounds: Array[Rect2]=Plan.rectangles(entry(),studio.mode,studio.library)
	if bounds.is_empty(): return
	var combined: Rect2=bounds[0]
	for rect in bounds: combined=combined.merge(rect)
	if entry()["kind"]=="assembly":
		frame_assembly(combined.grow(1))
		return
	var at: Array=Traffic.world(combined.get_center(),studio.mode)
	if studio.mode=="2d": studio.worlds[studio.mode].camera.position=Vector2(at[0],at[1])
	else: studio.worlds[studio.mode].target=Vector3(at[0],0,at[2]); studio.worlds[studio.mode].update_camera()
func frame_assembly(bounds: Rect2) -> void:
	var world: Node=studio.worlds[studio.mode]
	var canvas_size: Vector2=studio.canvas.size
	var visible:=Rect2(Vector2.ZERO,canvas_size)
	var shell: RefCounted=studio.consumer_shell
	if shell and shell.active and shell.details.visible:
		var top: float=maxf(shell.header.get_rect().end.y,shell.header_actions.get_rect().end.y)
		if shell.status_panel.visible: top=maxf(top,shell.status_panel.get_rect().end.y)
		var right: float=shell.details.position.x-12
		var bottom: float=shell.hint_panel.position.y-12
		var available:=Rect2(Vector2(12,top+12),Vector2(right-12,bottom-top-12))
		if available.size.x>=180 and available.size.y>=140:
			visible=available
	studio.neighborhood_tools.frame(world,bounds,Vector2i(visible.size))
	if visible.size==canvas_size: return
	if studio.mode=="2d":
		world.camera.position+=(canvas_size*.5-visible.get_center())/world.camera.zoom
	else:
		world.distance*=maxf(canvas_size.x/visible.size.x,canvas_size.y/visible.size.y)
		world.update_camera()
		var center: Vector3=world.camera.project_position(canvas_size*.5,world.distance)
		var destination: Vector3=world.camera.project_position(visible.get_center(),world.distance)
		world.target+=center-destination
		world.update_camera()

func add_center() -> void:
	if not editable(): return
	if not preload("res://scripts/builder/asset_behavior.gd").for_asset(studio.asset_id,studio.library).get("building",false): studio.status.text="Choose a building asset first."; return
	var pose: Dictionary=studio.placement(studio.canvas.size*.5)
	add({"kind":"building","item":building_item(pose)})
func input(event: InputEvent) -> bool:
	if not studio.tool in ["blueprint_building","blueprint_road"] or studio.walking: return false
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_RIGHT and event.pressed: cancel(); return true
		if event.button_index!=MOUSE_BUTTON_LEFT: return false
		if not editable(): return true
		if studio.tool=="blueprint_building":
			if event.pressed:
				if not preload("res://scripts/builder/asset_behavior.gd").for_asset(studio.asset_id,studio.library).get("building",false): studio.status.text="Choose a building asset before sketching its footprint."; return true
				var pose: Dictionary=studio.placement(event.position)
				add({"kind":"building","item":building_item(pose)})
		else:
			var cell: Vector2i=Plan.Roads.cell_at(studio.worlds[studio.mode].point(event.position,false,0),studio.mode)
			if event.pressed: start=cell; end=cell; dragging=true; studio.stroke=true
			elif dragging:
				end=cell; cancel(); finish_road({"start":[start.x,start.y],"end":[end.x,end.y],"settings":studio.road_settings.settings()})
		return true
	if event is InputEventMouseMotion and dragging:
		end=Plan.Roads.cell_at(studio.worlds[studio.mode].point(event.position,false,0),studio.mode); return true
	return false
func construct(all_entries: bool) -> void:
	if not editable(): return
	studio.finish_edit(studio.canvas_pointer()); var doc: RefCounted=studio.current(); doc.finish_checkpoint()
	var selected_ids: Array=ids(all_entries)
	if selected_ids.is_empty(): return
	var has_assembly: bool=doc.data.get("blueprints",[]).any(func(value: Dictionary):return value["kind"]=="assembly" and value["uid"] in selected_ids)
	if has_assembly and reviewed!=fingerprint(doc.data,selected_ids):
		review(selected_ids)
		studio.status.text=review_label.text
		return
	var result: Dictionary=checked(doc.data,selected_ids)
	if not result["ok"]:
		studio.status.text = result["reason"]
		if result.has("quote"): doc.economy_error = result["reason"]
		return
	if not result.get("changed",false): return
	var before: Dictionary=doc.data.duplicate(true); doc.data=result["data"]
	if commit(before):
		reviewed=""
		review_ids.clear()
		quote_stamp=""
		review_label.text=""
		studio.status.text="Blueprint construction committed."
func discard(all_entries: bool) -> void:
	if not editable(): return
	if ids(all_entries).is_empty(): return
	var doc: RefCounted=studio.current(); doc.finish_checkpoint(); var before: Dictionary=doc.data.duplicate(true); var removed: Array=ids(all_entries)
	doc.data["blueprints"]=doc.data.get("blueprints",[]).filter(func(value: Dictionary): return not value["uid"] in removed); commit(before)
func move_selected() -> void:
	if not editable() or entry().is_empty(): return
	var doc: RefCounted=studio.current(); doc.finish_checkpoint(); var before: Dictionary=doc.data.duplicate(true); var value: Dictionary=entry()
	var at: Array=studio.worlds[studio.mode].point(studio.canvas.size*.5,true,0)
	if value["kind"]=="building": value["item"]["position"]=at
	elif value["kind"]=="assembly":
		var moved: Dictionary=Plan.moved_assembly(value,at,studio.mode)
		doc.data["blueprints"][doc.data["blueprints"].find(value)]=moved
		if not Plan.valid(doc.data["blueprints"],studio.mode,studio.library):
			doc.data=before
			studio.status.text="Move the assembly within the construction limits."
			return
		reviewed=""
		review_label.text="Review the new site before construction."
	else:
		var cell: Vector2i=Plan.Roads.cell_at(at,studio.mode); var offset: Vector2i=cell-Vector2i(value["start"][0],value["start"][1]); value["start"]=[cell.x,cell.y]; value["end"]=[value["end"][0]+offset.x,value["end"][1]+offset.y]
	commit(before)
func rotate_selected() -> void:
	if not editable() or entry().get("kind")!="building": return
	var doc: RefCounted=studio.current(); doc.finish_checkpoint(); var before: Dictionary=doc.data.duplicate(true); var item: Dictionary=entry()["item"]; var choices: Array=studio.library.directions(item["asset"]); item["direction"]=str(choices[(choices.find(item["direction"])+1)%choices.size()]); commit(before)
func resurface() -> void:
	if not editable() or entry().get("kind")!="road": return
	var doc: RefCounted=studio.current(); doc.finish_checkpoint(); var before: Dictionary=doc.data.duplicate(true); entry()["settings"]=studio.road_settings.settings(); commit(before)
func tick(delta: float) -> void:
	var doc: RefCounted=studio.current(); var proposals: Array=doc.data.get("blueprints",[])
	if panel.is_visible_in_tree() and not review_ids.is_empty() and not studio.interior_tools.editing():
		quote_elapsed += delta
		if quote_elapsed >= .35:
			quote_elapsed = 0
			if quote_stamp != fingerprint(doc.data, review_ids):
				var before: String = reviewed
				review(review_ids)
				# Refresh the numbers while still requiring a deliberate review
				# for an assembly whose site, settings or dependencies changed.
				reviewed = before if before != quote_stamp else reviewed
	if list_stamp!=hash([studio.mode,proposals]):
		list_stamp=hash([studio.mode,proposals]); list.clear()
		for value in proposals:
			list.add_item("Road" if value["kind"]=="road" else value["name"] if value["kind"]=="assembly" else studio.library.assets[value["item"]["asset"]]["name"]); list.set_item_metadata(list.item_count-1,value["uid"])
			if value["uid"]==selected: list.select(list.item_count-1)
		detail.text="%d proposals · construction is deferred" % proposals.size()
	for mode in ["2d","3d"]:
		var source: Dictionary=studio.documents[mode].data
		var values: Array=source.get("blueprints",[]).duplicate(true)
		if mode==studio.mode and dragging: values.append({"kind":"road","start":[start.x,start.y],"end":[end.x,end.y],"settings":studio.road_settings.settings()})
		var stamp: int=hash([values,selected if mode==studio.mode else "",source.get("night",false),source.get("terrain_vertices",[]),source.get("terrain",{}),studio.interior_tools.editing(),studio.walking,source.get("layers",{})])
		if stamps.get(mode)==stamp: continue
		stamps[mode]=stamp
		if is_instance_valid(containers.get(mode)): containers[mode].free()
		var root: Node=Node2D.new() if mode=="2d" else Node3D.new(); root.name="BlueprintProposals"; root.set_meta("photo_hide",true); studio.worlds[mode].objects.add_child(root); containers[mode]=root
		root.visible=not studio.walking and not studio.interior_tools.editing()
		var heights: Dictionary=Terrain.lookup(source)
		for value in values:
			for rect in Plan.rectangles(value,mode,studio.library): draw_rect(root,rect,mode,source,heights)
			if root.visible and mode==studio.mode and value["kind"]=="assembly" and value["uid"]==selected:
				for item in value["objects"]: draw_object(root,item,mode,source,heights)
func draw_rect(root: Node,rect: Rect2,mode: String,source: Dictionary,heights: Dictionary) -> void:
	var corners: Array[Vector2]=[rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
	if mode=="2d":
		var visual:=preload("res://scripts/builder/blueprint_visual.gd").new(); var polygon:=PackedVector2Array()
		for point in corners:
			var at: Array=Traffic.world(point,mode); polygon.append(Vector2(at[0],at[1]-Terrain.sample(source,point,heights)["height"]*8-1))
		visual.polygons.append(polygon); root.add_child(visual)
	else:
		var mesh:=ImmediateMesh.new(); var material:=StandardMaterial3D.new(); material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; material.cull_mode=BaseMaterial3D.CULL_DISABLED; material.albedo_color=Color(.15,.65,1,.3)
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES,material)
		for index in [0,1,2,0,2,3]:
			var point: Vector2=corners[index]; mesh.surface_add_vertex(Vector3(point.x,Terrain.sample(source,point,heights)["height"]+.08,point.y))
		mesh.surface_end(); var visual:=MeshInstance3D.new(); visual.mesh=mesh; visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; root.add_child(visual)


func draw_object(root: Node,item: Dictionary,mode: String,source: Dictionary,heights: Dictionary) -> void:
	if not studio.library.assets.has(item["asset"]) or item.has("missing_asset"): return
	var factory=preload("res://scripts/builder/asset_instance.gd")
	var ghost: Node=factory.make(studio.library,item["asset"],mode)
	ghost.process_mode=Node.PROCESS_MODE_DISABLED
	ghost.set_meta("blueprint_member",item["uid"])
	root.add_child(ghost)
	preload("res://scripts/builder/layers.gd").collision_visibility(ghost,false)
	factory.pose(ghost,item,source.get("night",false))
	preload("res://scripts/builder/part_colors.gd").apply(ghost,item)
	var at: Array=item["position"]
	var terrain_height: float=Terrain.sample(source,Traffic.metric(at,mode),heights)["height"]
	if mode=="2d":
		ghost.position=Vector2(at[0],at[1]-(at[2]+terrain_height)*8.0)
		ghost.scale=Vector2.ONE*item["scale"]
		ghost.modulate.a=.45
	else:
		ghost.position=Vector3(at[0],at[1],at[2])
		ghost.scale=Vector3.ONE*item["scale"]
		for mesh in ghost.find_children("*","MeshInstance3D",true,false):
			mesh.transparency=.55
			mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
