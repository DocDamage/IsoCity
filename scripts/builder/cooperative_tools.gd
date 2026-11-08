extends RefCounted
const Session=preload("res://scripts/builder/cooperative_session.gd")
const Plan=preload("res://scripts/builder/cooperative_plan.gd")
const Merge=preload("res://scripts/builder/cooperative_merge.gd")
const Delta=preload("res://scripts/builder/document_delta.gd")
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
const Terrain=preload("res://scripts/builder/terrain_plan.gd")
var studio: Control
var session: Node
var panel: ScrollContainer
var name_field: LineEdit
var address: LineEdit
var password: LineEdit
var port: SpinBox
var status: Label
var badge: Label
var members: ItemList
var areas: ItemList
var area_name: LineEdit
var area_owner: OptionButton
var coordinates: Array[SpinBox]=[]
var show_areas: CheckButton
var selected: String=""
var applying: bool=false
var participating: bool=false
var dirty: bool=false
var elapsed: float=0
var seen_event: int=-1
var last_view: Dictionary={}
var backup: Dictionary={}
var backup_info: Dictionary={}
var draft: Dictionary={}
var drafts: Array[Dictionary]=[]
var draft_choices: OptionButton
var last_draft_path: String=""
var draft_error: String=""
var failed_edit: bool=false
var draft_request: String=""
var area_stamp: int=0
var member_stamp: int=0
var field_stamp: int=0
var visual_stamps: Dictionary={}
var area_roots: Dictionary={}
var cursor_root: Node
var cursor_stamp: int=0
var asset_count: int=0
var drawing: bool=false
var start_point:=Vector2.ZERO
var end_point:=Vector2.ZERO
func _init(host: Control) -> void:
	studio=host; session=Session.new(); session.name="CooperativeSession"; studio.add_child(session)
	panel=ScrollContainer.new(); panel.name="Co-op"; panel.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; panel.follow_focus=true; studio.workspace_layout.tabs.add_child(panel)
	var box:=VBoxContainer.new(); box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; box.add_theme_constant_override("separation",8); panel.add_child(box)
	studio.label(box,"Cooperative building",17).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	name_field=text(box,"Your display name","Builder"); address=text(box,"Host address","127.0.0.1"); password=text(box,"Session password",""); password.secret=true
	studio.label(box,"TCP port (0 chooses a free host port)",12).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; port=studio.spin(box,0,65535,1,49201)
	button(box,"Host this city",host_game); button(box,"Join host",join_game); button(box,"Leave session",leave)
	status=studio.label(box,"Offline",12); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	members=ItemList.new(); members.custom_minimum_size=Vector2(180,110); box.add_child(members)
	button(box,"Undo my shared edit",func():history(false)); button(box,"Redo my shared edit",func():history(true))
	button(box,"Restore pre-join city",restore_backup)
	studio.label(box,"Local recovery drafts",12); draft_choices=OptionButton.new(); draft_choices.fit_to_longest_item=false; draft_choices.clip_text=true; box.add_child(draft_choices)
	button(box,"Open local draft",restore_draft)
	studio.label(box,"Protected editing areas",15)
	areas=ItemList.new(); areas.custom_minimum_size=Vector2(180,130); box.add_child(areas); areas.item_selected.connect(func(index: int): selected=areas.get_item_metadata(index); field_stamp=0; refresh_area())
	area_name=text(box,"Area name","Protected area"); area_owner=OptionButton.new(); area_owner.fit_to_longest_item=false; area_owner.clip_text=true; box.add_child(area_owner); area_owner.add_item("Host only"); area_owner.set_item_metadata(0,"host")
	for label in ["Center · ground X","Center · ground Z","Width","Depth"]:
		studio.label(box,label,12); coordinates.append(studio.spin(box,-100000 if coordinates.size()<2 else 1,100000 if coordinates.size()<2 else 4096,1,0 if coordinates.size()<2 else 16))
	button(box,"Protect view center",add_center); button(box,"Draw protected area",draw_mode); button(box,"Apply area fields",apply_area); button(box,"Remove selected area",remove_area)
	show_areas=CheckButton.new(); show_areas.text="Show protected areas"; show_areas.button_pressed=true; box.add_child(show_areas)
	studio.label(box,"Open matching asset libraries on a trusted LAN, then host or join using a shared password. The displayed host port is used by everyone joining. Joining opens a local copy of the host city; your current city can be restored after leaving. Edits and cursors are shared in both views, including owned interiors. Only the host assigns protected areas and manages treasury/challenge settings. Areas protect overlapping objects, their rooms, roads, ground, terrain and plans. Green areas allow your edits; amber areas need access. Saved collaborator assignments belong to that session; a later host can reassign them. Undo/Redo affects your own accepted edits and refuses conflicts with newer edits. The last eight local drafts stay in this editor. With recovery enabled, rejected drafts are also listed in project Recovery. The connection is not encrypted and does not provide Internet matchmaking.",12).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	badge=Label.new(); badge.name="CooperativeBadge"; badge.mouse_filter=Control.MOUSE_FILTER_IGNORE; badge.position=Vector2(14,12); badge.add_theme_font_size_override("font_size",14); studio.canvas.add_child(badge); badge.hide()
func button(parent: Node,label: String,callback: Callable) -> void:
	var control:=Button.new(); control.text=label; control.tooltip_text=label; control.clip_text=true; parent.add_child(control); control.pressed.connect(callback)
func text(parent: Node,label: String,value: String) -> LineEdit:
	studio.label(parent,label,12); var control:=LineEdit.new(); control.text=value; parent.add_child(control); return control
func show() -> void:
	studio.workspace_presets.set_focus(false)
	if studio.get_viewport_rect().size.x<1200: studio.workspace_layout.library_toggle.button_pressed=false
	studio.workspace_layout.inspector_toggle.button_pressed=true; studio.workspace_layout.tabs.current_tab=panel.get_index(); refresh()
func snapshot() -> Dictionary:
	studio.interior_tools.flush(); var result: Dictionary={}
	for mode in ["2d","3d"]: result[mode]=studio.interior_tools.root_document(mode).data.duplicate(true)
	if not studio.project_palette_document.data.is_empty():result["project_palette"]=studio.project_palette_document.data.duplicate(true)
	return session.normalize(result) if session.connected else result
func host_game() -> void:
	if session.role!="offline": studio.status.text="Leave the current session before hosting another city."; return
	studio.finish_edit(studio.canvas_pointer()); last_view=snapshot(); participating=false; asset_count=studio.library.assets.size(); session.host(last_view,studio.library,int(port.value),password.text,name_field.text); seen_event=-1; tick(0)
func join_game() -> void:
	if session.role!="offline": studio.status.text="Leave the current session before joining another city."; return
	studio.finish_edit(studio.canvas_pointer()); participating=false; last_view=snapshot(); asset_count=studio.library.assets.size(); session.join(address.text,int(port.value),password.text,name_field.text,studio.library); seen_event=-1; tick(0)
func leave() -> void:
	studio.finish_edit(studio.canvas_pointer())
	if session.connected and snapshot()!=session.data: keep_draft(snapshot(),"Pending edit at disconnect")
	var accepted: Dictionary=session.data.duplicate(true); session.close("Session ended. The last accepted city is kept.")
	if participating and not accepted.is_empty():
		if studio.village_tools: studio.village_tools.reset()
		apply_worlds(accepted); last_view=accepted
	if studio.garden_tools: studio.garden_tools.reset()
	if studio.cooking_tools: studio.cooking_tools.reset()
	if studio.laundry_tools: studio.laundry_tools.reset()
	if studio.fitness_tools: studio.fitness_tools.reset()
	if studio.arcade_tools: studio.arcade_tools.reset()
	if studio.camping_tools: studio.camping_tools.reset()
	if studio.cycling_tools: studio.cycling_tools.reset()
	participating=false; dirty=false; refresh()
func observe() -> void:
	if applying or not session.connected: return
	dirty=true
	if participating and not busy() and session.pending.is_empty() and last_view==session.overlay():
		var current: Dictionary=snapshot(); var change: Dictionary=Delta.between(session.data,current)
		if not change["fields"].is_empty() or not change["collections"].is_empty(): last_view=current.duplicate(true); session.submit(change)
		else: dirty=false
func authority() -> bool: return not session.connected or session.role=="host"
func busy() -> bool:
	return studio.stroke or studio.road_drawing or studio.ground_brush.drawing or studio.transform_handles.dragging or studio.zone_tools.drawing or drawing
func tick(delta: float) -> void:
	elapsed+=delta
	if session.connected and not participating:
		if session.role=="client":
			backup=snapshot(); backup_info={"project_id":studio.project_id,"project_path":studio.project_path,"saved_digest":studio.saved_digest,"mode":studio.mode}
			if studio.storage_enabled: studio.autosave()
			studio.project_id=studio.Store.new_id(); studio.project_path=""; studio.saved_digest=""
		if studio.village_tools: studio.village_tools.reset()
		participating=true; dirty=false; apply_worlds(session.overlay()); last_view=session.overlay().duplicate(true); seen_event=session.event_serial
		if studio.garden_tools: studio.garden_tools.reset()
		if studio.cooking_tools: studio.cooking_tools.reset()
		if studio.laundry_tools: studio.laundry_tools.reset()
		if studio.fitness_tools: studio.fitness_tools.reset()
		if studio.arcade_tools: studio.arcade_tools.reset()
		if studio.camping_tools: studio.camping_tools.reset()
		if studio.cycling_tools: studio.cycling_tools.reset()
	if participating and not busy() and seen_event!=session.event_serial:
		var current: Dictionary=snapshot(); var extra: Dictionary=Delta.between(last_view,current)
		var target: Dictionary=session.overlay(); var skip_accounts: bool=session.role!="host"
		if session.role=="host":
			var economy=preload("res://scripts/builder/economy_plan.gd")
			for mode in ["2d","3d"]:
				if economy.settings(last_view[mode])==economy.settings(current[mode]) and economy.inventory(last_view[mode],studio.library)!=economy.inventory(current[mode],studio.library): skip_accounts=true
		var rebased: Dictionary=Merge.apply(target,extra,true,skip_accounts)
		if not session.connected:
			if current!=session.data: keep_draft(current,"Unconfirmed changes at disconnect")
			rebased={"ok":true,"data":session.data}
		if not session.rejected_delta.is_empty():
			if draft_request!=session.rejected_request or draft.is_empty(): keep_draft(session.rejected_view if not session.rejected_view.is_empty() else current,"Rejected shared edit",delta_mode(session.rejected_delta))
			session.rejected_delta.clear(); failed_edit=true
		if session.pending.has("delta"):
			var optimistic: Dictionary=Merge.apply(session.data,session.pending["delta"],true,true)
			if not optimistic["ok"] and draft_request!=session.pending["request"]: keep_draft(current,"Conflicting local edit",delta_mode(session.pending["delta"])); draft_request=session.pending["request"]
		if rebased["ok"]: target=rebased["data"]
		else: keep_draft(current,"Unmerged local changes"); draft_request=session.pending.get("request",session.rejected_request); session.fail(rebased["reason"]+" A local draft was retained."); failed_edit=true
		if not session.connected and studio.village_tools: studio.village_tools.reset()
		apply_worlds(target); last_view=session.overlay().duplicate(true); seen_event=session.event_serial; dirty=target!=session.data; studio.status.text="Co-op · "+session.notice
		if not session.connected: participating=false; dirty=false
	if session.connected and participating and dirty and not busy() and session.pending.is_empty() and elapsed>=.15:
		elapsed=0; var current: Dictionary=snapshot(); var change: Dictionary=Delta.between(session.data,current)
		if not change["fields"].is_empty() or not change["collections"].is_empty():
			last_view=current.duplicate(true); session.submit(change)
		else: dirty=false
	if session.connected and studio.library.assets.size()!=asset_count: asset_count=studio.library.assets.size(); session.refresh_assets()
	if session.connected: session.local_cursor=cursor()
	update_visuals(); refresh()
func clear_history(doc: RefCounted) -> void:
	doc.undo_history.clear(); doc.redo_history.clear(); doc.pending_before={}; doc.pending_redo.clear(); doc.economy_accepted={}; doc.economy_complimentary={}
func apply_worlds(value: Dictionary) -> void:
	if value.is_empty(): return
	applying=true; studio.finish_edit(studio.canvas_pointer()); var interior: RefCounted=studio.interior_tools
	if interior.editing():
		var owner: Dictionary={}
		for item in value[interior.dimension]["objects"]:
			if item["uid"]==interior.uid: owner=item; break
		if not owner.get("interior") is Dictionary: interior.leave()
	for mode in ["2d","3d"]:
		var doc: RefCounted=interior.root_document(mode); doc.data=value[mode].duplicate(true); clear_history(doc)
	studio.project_palette_document.restore(value.get("project_palette",{}))
	if interior.editing():
		var owned: Dictionary=interior.outer.object(interior.uid)["interior"]; interior.restore_owned(owned); clear_history(studio.current().canonical); clear_history(studio.current())
	studio.selected_uids.assign(studio.selected_uids.filter(func(uid: String):return not studio.current().object(uid).is_empty())); studio.selected_uid=studio.selected_uids[0] if not studio.selected_uids.is_empty() else ""
	studio.changed()
	for mode in ["2d","3d"]:
		if mode!=studio.mode: studio.worlds[mode].apply(studio.documents[mode].data)
	applying=false
func history(redo: bool) -> void:
	studio.finish_edit(studio.canvas_pointer())
	if dirty or not session.pending.is_empty(): studio.status.text="Wait for your current shared edit to finish before Undo/Redo."; return
	session.request_undo(redo)
func restore_backup() -> void:
	if session.role!="offline": studio.status.text="Leave the session before restoring your pre-join city."; return
	if backup.is_empty(): studio.status.text="There is no pre-join city in this editor session."; return
	apply_worlds(backup)
	if studio.mode!=backup_info["mode"]: studio.switch_mode(backup_info["mode"])
	studio.project_id=backup_info["project_id"]; studio.project_path=backup_info["project_path"]; studio.saved_digest=backup_info["saved_digest"]; studio.dirty=studio.content_digest()!=studio.saved_digest; studio.update_save_badge(); last_view=backup.duplicate(true)
func delta_mode(change: Dictionary) -> String:
	for mode in ["2d","3d"]:
		if change.get("fields",{}).has(mode): return mode
	return studio.mode
func keep_draft(value: Dictionary,label: String,mode: String="") -> void:
	if value.is_empty(): return
	var digest: String=(studio.project_id+JSON.stringify(value)).sha256_text()
	for index in drafts.size():
		if drafts[index]["digest"]==digest: draft=drafts[index]["data"].duplicate(true); draft_choices.select(index); return
	var entry: Dictionary={"data":value.duplicate(true),"label":label,"mode":studio.mode if mode.is_empty() else mode,"digest":digest}
	drafts.append(entry)
	if drafts.size()>8: drafts.pop_front()
	draft=value.duplicate(true); draft_choices.clear()
	for index in drafts.size(): draft_choices.add_item(str(index+1)+" · "+drafts[index]["label"]+" · "+drafts[index]["mode"]); draft_choices.set_item_metadata(index,index)
	draft_choices.select(drafts.size()-1)
	if studio.storage_enabled:
		var document: Dictionary={"version":1,"grid_version":2,"project_id":studio.project_id,"active_mode":entry["mode"],"documents":{"2d":value["2d"],"3d":value["3d"]}}
		if value.has("project_palette"):document["project_palette"]=value["project_palette"].duplicate(true)
		last_draft_path=studio.Store.snapshot(document,"Co-op draft · "+label,null,true,studio.project_path)
		draft_error="" if not last_draft_path.is_empty() else "The draft is held in this editor, but its recovery copy could not be written."
func restore_draft() -> void:
	if session.role!="offline": studio.status.text="Leave the session before opening a rejected draft."; return
	if draft.is_empty(): studio.status.text="No rejected or pending draft is available."; return
	var entry: Dictionary=drafts[clampi(draft_choices.selected,0,drafts.size()-1)] if not drafts.is_empty() else {"data":draft,"mode":studio.mode}
	if studio.interior_tools.editing(): studio.interior_tools.leave()
	apply_worlds(entry["data"])
	if studio.mode!=entry["mode"]: studio.switch_mode(entry["mode"])
	studio.project_id=studio.Store.new_id(); studio.project_path=""; studio.saved_digest=""; studio.dirty=true; studio.autosave_pending=true; studio.update_save_badge(); last_view=entry["data"].duplicate(true)
func area() -> Dictionary:
	for value in studio.interior_tools.root_document(studio.mode).data.get("protected_areas",[]):
		if value["uid"]==selected: return value
	return {}
func can_assign() -> bool:
	if studio.interior_tools.editing(): studio.status.text="Assign areas in the exterior city; protected buildings include their rooms."; return false
	if session.connected and session.role!="host": studio.status.text="Only the host assigns protected areas."; return false
	return true
func add_center() -> void:
	if not can_assign(): return
	var center: Vector2=Traffic.metric(studio.worlds[studio.mode].point(studio.canvas.size*.5,false,0),studio.mode)
	add_bounds(Rect2(center-Vector2(coordinates[2].value,coordinates[3].value)*.5,Vector2(coordinates[2].value,coordinates[3].value)))
func selected_owner() -> String: return str(area_owner.get_item_metadata(maxi(0,area_owner.selected)))
func add_bounds(bounds: Rect2) -> void:
	if not can_assign() or bounds.size.x<1 or bounds.size.y<1: return
	var value: Dictionary={"uid":"area_"+str(Time.get_ticks_usec())+"_"+str(randi()),"name":area_name.text.substr(0,128),"owner":selected_owner(),"rect":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y]}
	var doc: RefCounted=studio.current(); doc.finish_checkpoint(); var entries: Array=doc.data.get("protected_areas",[]).duplicate(true); entries.append(value)
	if not Plan.valid_areas(entries): studio.status.text="Use up to 128 areas, each 1–4096 ground units wide/deep."; return
	var before: Dictionary=doc.data.duplicate(true); doc.data["protected_areas"]=entries; doc.record_completed_change(before); selected=value["uid"]; studio.changed(); refresh()
func apply_area() -> void:
	if not can_assign() or area().is_empty(): return
	studio.finish_edit(studio.canvas_pointer()); var doc: RefCounted=studio.current(); doc.finish_checkpoint(); var before: Dictionary=doc.data.duplicate(true); var value: Dictionary=area(); value["name"]=area_name.text.substr(0,128); value["owner"]=selected_owner(); value["rect"]=[coordinates[0].value-coordinates[2].value*.5,coordinates[1].value-coordinates[3].value*.5,coordinates[2].value,coordinates[3].value]; doc.record_completed_change(before); studio.changed()
func remove_area() -> void:
	if not can_assign() or area().is_empty(): return
	studio.finish_edit(studio.canvas_pointer()); var doc: RefCounted=studio.current(); doc.finish_checkpoint(); var before: Dictionary=doc.data.duplicate(true); doc.data["protected_areas"].erase(area()); doc.record_completed_change(before); studio.changed()
func draw_mode() -> void:
	if not can_assign(): return
	studio.finish_edit(studio.canvas_pointer()); studio.set_walking(false); studio.set_tool("protect_area"); studio.status.text="Drag a protected editing area; right-click cancels."
func input(event: InputEvent) -> bool:
	if studio.tool!="protect_area" or studio.walking: return false
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and event.pressed: cancel_draw(); return true
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not can_assign(): return true
			start_point=Traffic.metric(studio.worlds[studio.mode].point(event.position,false,0),studio.mode).snapped(Vector2.ONE); end_point=start_point; drawing=true; studio.stroke=true
		elif drawing:
			end_point=Traffic.metric(studio.worlds[studio.mode].point(event.position,false,0),studio.mode).snapped(Vector2.ONE); var bounds:=Rect2(start_point,end_point-start_point).abs(); cancel_draw(); add_bounds(bounds)
		return true
	if event is InputEventMouseMotion and drawing: end_point=Traffic.metric(studio.worlds[studio.mode].point(event.position,false,0),studio.mode).snapped(Vector2.ONE); return true
	return false
func cancel_draw() -> void: drawing=false; studio.stroke=false; visual_stamps.clear()
func refresh_area() -> void:
	var value: Dictionary=area()
	if value.is_empty() or field_stamp==hash(value): return
	field_stamp=hash(value); area_name.text=value["name"]; var bounds: Rect2=Plan.rect(value); coordinates[0].set_value_no_signal(bounds.get_center().x); coordinates[1].set_value_no_signal(bounds.get_center().y); coordinates[2].set_value_no_signal(bounds.size.x); coordinates[3].set_value_no_signal(bounds.size.y)
	select_owner(value["owner"])
func select_owner(id: String) -> void:
	for index in area_owner.item_count:
		if area_owner.get_item_metadata(index)==id: area_owner.select(index); return
	area_owner.add_item("Offline owner · "+id.right(6)); area_owner.set_item_metadata(area_owner.item_count-1,id); area_owner.select(area_owner.item_count-1)
func refresh() -> void:
	status.text=session.notice+"\n"+("Host" if session.role=="host" else "Client" if session.role=="client" else session.role.capitalize())+" · revision "+str(session.revision)
	if not draft_error.is_empty(): status.text+="\n"+draft_error
	badge.visible=session.role!="offline"; badge.text="CO-OP · "+str(session.roster.size())+" builders · "+("sending…" if not session.pending.is_empty() else "revision "+str(session.revision)); badge.tooltip_text=session.notice
	if failed_edit: badge.text+=" · draft available"
	var roster_view: Dictionary={}
	for id in session.roster: roster_view[id]=[session.roster[id]["name"],session.roster[id].get("cursor",{}).get("mode",""),session.roster[id].get("cursor",{}).get("scope","")]
	var stamp: int=hash(roster_view)
	if stamp!=member_stamp:
		member_stamp=stamp; members.clear(); var chosen: String=selected_owner(); area_owner.clear(); area_owner.add_item("Host only"); area_owner.set_item_metadata(0,"host")
		for id in session.roster:
			var member: Dictionary=session.roster[id]; var cursor_value: Dictionary=member.get("cursor",{}); members.add_item(member["name"]+" · "+str(cursor_value.get("mode",""))+" · "+("exterior" if cursor_value.get("scope","city")=="city" else "room/floor"))
			if id!="host": area_owner.add_item(member["name"]+" · "+id.right(6)); area_owner.set_item_metadata(area_owner.item_count-1,id)
		select_owner(chosen)
	var values: Array=studio.interior_tools.root_document(studio.mode).data.get("protected_areas",[]); stamp=hash([studio.mode,values,roster_view.keys()])
	if stamp!=area_stamp:
		area_stamp=stamp; areas.clear()
		for value in values:
			areas.add_item(value["name"]+" · "+("host" if value["owner"]=="host" else str(session.roster.get(value["owner"],{}).get("name","offline collaborator")))); areas.set_item_metadata(areas.item_count-1,value["uid"])
			if value["uid"]==selected: areas.select(areas.item_count-1)
	refresh_area()
func scope() -> String:
	if studio.interior_tools.editing(): return "room:"+studio.interior_tools.uid+":"+studio.current().floor_uid
	var exploration: Node=studio.worlds[studio.mode].exploration
	if exploration.interior: return "room:"+exploration.interior_uid+":"+exploration.active_floor()
	return "city"
func cursor() -> Dictionary:
	var at: Vector2=studio.canvas_pointer(); var visible_cursor: bool=Rect2(Vector2.ZERO,studio.canvas.size).has_point(at) and not studio.modal_visible(); var point: Array
	if studio.walking:
		var world: Node=preload("res://scripts/builder/prop_plan.gd").context(studio.worlds[studio.mode].exploration)["world"]; var position: Variant=world.to_local(studio.worlds[studio.mode].player.global_position)
		point=[position.x,position.y,0] if studio.mode=="2d" else [position.x,position.y,position.z]; visible_cursor=true
	else: point=studio.worlds[studio.mode].surface_point(at,false,0) if studio.mode=="3d" else studio.worlds[studio.mode].point(at,false,0)
	return {"mode":studio.mode,"scope":scope(),"point":point,"visible":visible_cursor}
func update_visuals() -> void:
	for mode in ["2d","3d"]:
		var source: Dictionary=studio.interior_tools.root_document(mode).data; var values: Array=source.get("protected_areas",[]).duplicate(true)
		if drawing and mode==studio.mode:
			var bounds:=Rect2(start_point,end_point-start_point).abs()
			if bounds.size.x>=1 and bounds.size.y>=1: values.append({"rect":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y]})
		var stamp: int=hash([values,source.get("terrain_vertices",[]),source.get("terrain",{}),studio.accessibility_settings.text_scale,session.local_id])
		if visual_stamps.get(mode)!=stamp:
			visual_stamps[mode]=stamp
			if is_instance_valid(area_roots.get(mode)): area_roots[mode].free()
			var root: Node=Node2D.new() if mode=="2d" else Node3D.new(); root.name="ProtectedAreas"; root.set_meta("photo_hide",true); studio.worlds[mode].objects.add_child(root); area_roots[mode]=root
			var heights: Dictionary=Terrain.lookup(source)
			for value in values:
				var bounds: Rect2=Plan.rect(value); studio.blueprint_tools.draw_rect(root,bounds,mode,source,heights); var visual: Node=root.get_child(root.get_child_count()-1); var permitted: bool=value.get("owner","host")==session.local_id or session.role=="host"; var tint:=Color("6ddba9") if permitted else Color("ffbc66")
				if mode=="2d": visual.fill_tint=Color(tint,.16); visual.outline_tint=Color(tint,.85); visual.queue_redraw()
				else: visual.mesh.surface_get_material(0).albedo_color=Color(tint,.25)
				var at: Array=Traffic.world(bounds.position,mode); var height: float=Terrain.sample(source,bounds.position,heights)["height"]; var caption: String="Protected · "+str(value.get("name","New area"))
				if mode=="2d":
					var label:=Label.new(); label.mouse_filter=Control.MOUSE_FILTER_IGNORE; label.text=caption; label.add_theme_font_size_override("font_size",roundi(14*studio.accessibility_settings.text_scale)); label.position=Vector2(at[0],at[1]-height*8-20); label.modulate=tint; root.add_child(label)
				else:
					var label:=Label3D.new(); label.text=caption; label.billboard=BaseMaterial3D.BILLBOARD_ENABLED; label.no_depth_test=true; label.modulate=tint; label.font_size=roundi(22*studio.accessibility_settings.text_scale); label.pixel_size=.025; label.position=Vector3(at[0],height+.6,at[2]); root.add_child(label)
		area_roots[mode].visible=show_areas.button_pressed and mode==studio.mode and not studio.walking and not studio.interior_tools.editing() and studio.worlds[mode].exploration.interior==null and not studio.worlds[mode].exploration.photo.capture_busy
	var active: Dictionary=preload("res://scripts/builder/prop_plan.gd").context(studio.worlds[studio.mode].exploration)
	var camera: Node=studio.worlds[studio.mode].camera; var view_height: float=maxf(1,camera.get_viewport().get_visible_rect().size.y)
	var stamp: int=hash([session.roster,studio.mode,scope(),studio.accessibility_settings.text_scale,active["world"].get_instance_id(),camera.zoom if studio.mode=="2d" else camera.size,view_height])
	if is_instance_valid(cursor_root): cursor_root.visible=not studio.worlds[studio.mode].exploration.photo.capture_busy
	if stamp==cursor_stamp: return
	cursor_stamp=stamp
	if is_instance_valid(cursor_root): cursor_root.free()
	cursor_root=Node2D.new() if studio.mode=="2d" else Node3D.new(); cursor_root.name="CollaboratorCursors"; cursor_root.set_meta("photo_hide",true); cursor_root.visible=not studio.worlds[studio.mode].exploration.photo.capture_busy; active["world"].objects.add_child(cursor_root)
	if cursor_root is Node2D: cursor_root.z_index=4000
	for id in session.roster:
		if id==session.local_id: continue
		var member: Dictionary=session.roster[id]; var value: Dictionary=member.get("cursor",{})
		if value.get("mode")!=studio.mode or value.get("scope")!=scope() or not value.get("visible",false): continue
		var tint:=Color.from_hsv(float(posmod(id.hash(),360))/360.0,.55,1)
		if studio.mode=="2d":
			var marker:=preload("res://scripts/builder/cooperative_cursor_2d.gd").new(); marker.caption=member["name"]; marker.tint=tint; marker.text_scale=studio.accessibility_settings.text_scale; marker.position=Vector2(value["point"][0],value["point"][1]); marker.scale=Vector2.ONE/maxf(.01,camera.zoom.x); cursor_root.add_child(marker)
		else:
			var root:=Node3D.new(); root.position=Vector3(value["point"][0],value["point"][1]+.03,value["point"][2]); root.scale=Vector3.ONE*clampf(camera.size/view_height*22/.55,.2,40); cursor_root.add_child(root); var mesh:=MeshInstance3D.new(); var cone:=CylinderMesh.new(); cone.top_radius=0; cone.bottom_radius=.2; cone.height=.55; mesh.mesh=cone; mesh.position.y=.275; mesh.rotation.z=PI; var material:=StandardMaterial3D.new(); material.albedo_color=tint; material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; material.no_depth_test=true; mesh.material_override=material; mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; root.add_child(mesh)
			var label:=Label3D.new(); label.text=member["name"]; label.font_size=roundi(24*studio.accessibility_settings.text_scale); label.billboard=BaseMaterial3D.BILLBOARD_ENABLED; label.no_depth_test=true; label.pixel_size=.025; label.position.y=1.15; root.add_child(label)
