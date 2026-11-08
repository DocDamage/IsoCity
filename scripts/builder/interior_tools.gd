extends RefCounted

const Rooms = preload("res://scripts/builder/interiors.gd")
var studio: Control
var outer: RefCounted
var uid: String = ""
var dimension: String = ""
var outside_position: Variant
var bar: HBoxContainer
var caption: Label
var edit_button: Button
var return_button: Button
var selected_edit: Button
var empty_button: Button
var starter_hint: Label
var kit_chooser: RefCounted
var kit_button: Button
var room_kit_button: Button
var exit_marker: Node
var previous_redo: Array = []
var floor_tools: RefCounted
var walk_camera: Dictionary={}

func _init(owner_control: Control, entrance_panel: Node, center: Node) -> void:
	studio = owner_control
	selected_edit = Button.new()
	selected_edit.text = "Edit this building's interior"
	entrance_panel.add_child(selected_edit)
	selected_edit.pressed.connect(func():
		var item: Dictionary = studio.entrance_tools.active()
		if not item.is_empty(): start(item["uid"])
	)
	starter_hint=studio.label(entrance_panel,"",12);starter_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	empty_button=Button.new();empty_button.text="Start empty room";empty_button.accessibility_name="Create a new empty interior";entrance_panel.add_child(empty_button)
	empty_button.pressed.connect(func():
		var item: Dictionary=studio.entrance_tools.active()
		if not item.is_empty() and not item.has("interior"):start(item["uid"],"ground","empty")
	)
	bar = HBoxContainer.new()
	center.add_child(bar)
	center.move_child(bar,1)
	caption = studio.label(bar,"",13)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.clip_text = true
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	edit_button = Button.new()
	edit_button.text = "Edit this room"
	bar.add_child(edit_button)
	edit_button.pressed.connect(func():
		var exploration: Node=studio.worlds[studio.mode].exploration
		start(exploration.interior_uid,exploration.active_floor())
	)
	return_button = Button.new()
	return_button.text = "Back to city"
	bar.add_child(return_button)
	return_button.pressed.connect(func():
		if editing(): leave()
		else: studio.worlds[studio.mode].exploration.leave_interior(); refresh()
	)
	bar.visible = false
	floor_tools=load("res://scripts/builder/floor_tools.gd").new(studio,center)
	kit_chooser=load("res://scripts/builder/interior_kit_tools.gd").new(studio)
	kit_button=Button.new();kit_button.text="Preview interior layouts…";entrance_panel.add_child(kit_button);kit_button.pressed.connect(kit_chooser.show)
	room_kit_button=Button.new();room_kit_button.text="Room layouts…";bar.add_child(room_kit_button);room_kit_button.pressed.connect(kit_chooser.show)

func editing() -> bool:
	return outer != null

func root_document(key: String) -> RefCounted:
	return outer if editing() and key == dimension else studio.documents[key]

func prepare(uid_value: String, key: String) -> void:
	var doc: RefCounted = studio.documents[key]
	var item: Dictionary = doc.object(uid_value)
	if item.is_empty() or item.has("interior"): return
	var checked: Dictionary=Rooms.creation_check(item,key,studio.library)
	if not checked["ok"]:studio.status.text=checked["reason"];return
	if "small_prop_tools" in studio and studio.small_prop_tools:studio.small_prop_tools.leave()
	doc.checkpoint()
	Rooms.ensure(item,key,studio.library)
	doc.complimentary_room(uid_value,studio.library)
	studio.changed()

func set_door(host_uid: String, door_uid: String, opened: bool, key: String, floor_uid: String="ground") -> void:
	var doc: RefCounted = studio.documents[key]
	if editing() and key==dimension and host_uid==uid and studio.worlds[key].exploration.preview:
		doc.finish_checkpoint()
		var room: Dictionary=preload("res://scripts/builder/floor_plan.gd").room(doc.canonical.data,floor_uid)
		for item in room.get("objects",[]):
			if item["uid"]!=door_uid or item.get("open",false)==opened: continue
			var before: Dictionary=doc.canonical.data.duplicate(true); item["open"]=opened
			if doc.canonical.record_completed_change(before): doc.canonical.undo_history.back()["floor_uid"]=floor_uid
			flush(); studio.worlds[key].exploration.apply_room(floor_uid)
			studio.dirty=studio.content_digest()!=studio.saved_digest; studio.autosave_pending=true; studio.update_save_badge()
			return
		return
	var host: Dictionary = doc.object(host_uid)
	if not host.has("interior"): return
	for item in preload("res://scripts/builder/floor_plan.gd").room(host["interior"],floor_uid).get("objects",[]):
		if item["uid"] != door_uid: continue
		doc.checkpoint()
		item["open"] = opened
		studio.worlds[key].exploration.apply_room(floor_uid)
		studio.dirty = studio.content_digest() != studio.saved_digest
		studio.autosave_pending = true
		studio.update_save_badge()
		return

func start(uid_value: String, floor_uid: String="ground",starter_choice: String="") -> void:
	if editing() or uid_value.is_empty(): return
	var item: Dictionary = studio.current().object(uid_value)
	if item.is_empty() or not studio.Layers.editable(studio.current().data,item,studio.library): return
	if not preload("res://scripts/builder/exploration.gd").has_room(item,studio.library): return
	var checked: Dictionary=Rooms.creation_check(item,studio.mode,studio.library,starter_choice)
	if not checked["ok"]:studio.status.text=checked["reason"];return
	studio.finish_edit(studio.canvas.get_local_mouse_position())
	studio.set_walking(false)
	studio.capture_workspace()
	dimension = studio.mode
	uid = uid_value
	outside_position = studio.worlds[dimension].exploration.entrance(studio.worlds[dimension].instances[uid])
	outer = studio.documents[dimension]
	previous_redo = outer.redo_history.duplicate(true)
	outer.checkpoint()
	var doc: RefCounted = load("res://scripts/builder/floor_document.gd").new()
	var starter_room: bool=not item.has("interior")
	if starter_room:item["interior"]=checked["room"]
	doc.configure(Rooms.ensure(item,dimension,studio.library))
	doc.canonical.content_library=studio.library
	doc.switch_floor(floor_uid)
	if starter_room: outer.complimentary_room(uid_value,studio.library)
	studio.documents[dimension] = doc
	studio.template_choice.select(["city","room","blank"].find(doc.data.get("template","room")))
	clear_selection()
	studio.worlds[dimension].apply(doc.data)
	studio.worlds[dimension].reset_camera("room")
	studio.worlds[dimension].player.teleport_to(exit_point())
	studio.search.text = ""
	studio.page = 0
	for index in studio.category.item_count:
		if studio.category.get_item_text(index) == ("Living Room" if dimension == "2d" else "Shop"): studio.category.select(index)
	studio.refresh_library()
	studio.changed()
	refresh()
	if starter_room:
		var info: Dictionary=doc.data.get("starter_kit",{})
		if info.has("missing"):studio.status.text="Some starter furnishings are unavailable. Created a clear empty shell; existing source files are unchanged."
		elif info.get("id")=="empty":studio.status.text="Created an empty interior with a clear exit."
		else:studio.status.text="Created "+str(preload("res://scripts/builder/interior_kits.gd").definitions()["kits"].get(info.get("id",""),{}).get("name","standard room"))+" interior. Default starter furnishings are complimentary."
	else:studio.status.text="Opened the saved interior; existing furnishings are preserved."

func clear_selection() -> void:
	studio.selected_uid = ""
	studio.selected_uids.clear()
	studio.selected_cell = null
	studio.clear_assembly()
	studio.clear_placement()
	studio.set_tool("select")

func exit_point() -> Variant:
	var values: Array = studio.current().data.get("exit",[0,60,0] if studio.mode == "2d" else [0,.2,2.5])
	return Vector2(values[0],values[1]) if studio.mode == "2d" else Vector3(values[0],values[1],values[2])

func flush() -> void:
	if not editing(): return
	var data: Dictionary = studio.documents[dimension].data
	data["interior_room"] = true
	if not data.has("exit"): data["exit"] = [0,60,0] if dimension == "2d" else [0,.2,2.5]
	studio.documents[dimension].flush_room()
	outer.object(uid)["interior"] = studio.documents[dimension].canonical.data

func restore_owned(data: Dictionary) -> void:
	if editing(): studio.documents[dimension].restore_owned(data)

func leave() -> void:
	if not editing(): return
	if "small_prop_tools" in studio and studio.small_prop_tools:studio.small_prop_tools.leave()
	studio.finish_edit(studio.canvas.get_local_mouse_position())
	studio.set_walking(false)
	flush()
	studio.documents[dimension] = outer
	outer.finish_checkpoint()
	if not outer.undo_history.is_empty() and outer.undo_history.back().get("fields",{}).is_empty() and outer.undo_history.back().get("collections",{}).is_empty():
		outer.undo_history.pop_back()
		outer.redo_history.assign(previous_redo)
	previous_redo.clear()
	outer = null
	if is_instance_valid(exit_marker): exit_marker.free()
	exit_marker = null
	clear_selection()
	studio.selected_uid = uid
	studio.selected_uids.assign([uid])
	studio.worlds[dimension].apply(studio.current().data)
	studio.template_choice.select(["city","room","blank"].find(studio.current().data.get("template","city")))
	studio.worlds[dimension].player.teleport_to(outside_position)
	studio.restore_workspace()
	studio.changed()
	refresh()

func interact_exit() -> bool:
	var exploration: Node=studio.worlds[studio.mode].exploration
	if exploration.preview: return false
	if not at_exit(): return false
	leave()
	studio.set_walking(true)
	return true

func at_exit() -> bool:
	return editing() and studio.worlds[studio.mode].exploration.interior == null and studio.worlds[studio.mode].player.position.distance_to(exit_point()) <= (45 if studio.mode == "2d" else 2.5)

func walk_prompt() -> String:
	var message: String = "E · Return outside" if at_exit() else "Walk inside · return to EXIT to leave · Tab to edit this room"
	var hint: String = studio.worlds[studio.mode].player.movement_hint()
	return message + (" · " + hint if not hint.is_empty() else "")

func refresh() -> void:
	for key in studio.worlds:
		studio.worlds[key].exploration.editor_scope="room:"+uid+":"+studio.documents[key].floor_uid+":" if editing() and key==dimension else ""
	if floor_tools: floor_tools.refresh()
	var exploration: Node = studio.worlds[studio.mode].exploration
	var inside: bool = exploration.interior != null
	var standalone: bool=not editing() and (studio.current().data.get("template")=="room" or studio.current().data.get("interior_room",false))
	studio.title_input.editable=not exploration.preview
	if exploration.preview: studio.title_input.text=exploration.room_world().data_state["title"]
	bar.visible = editing() or inside or (standalone and not studio.walking)
	return_button.visible=editing() or inside
	edit_button.visible = inside and not editing()
	selected_edit.disabled = editing() or studio.entrance_tools.active().is_empty()
	var selected: Dictionary=studio.entrance_tools.active();var can_create: bool=not editing() and not selected.is_empty() and not selected.has("interior")
	kit_button.disabled=editing() or selected.is_empty();room_kit_button.visible=(editing() or standalone) and not studio.walking
	empty_button.visible=can_create;starter_hint.visible=can_create
	if can_create:
		var kit: String=preload("res://scripts/builder/interior_kits.gd").default_for(selected["asset"])
		starter_hint.text="First creation: "+str(preload("res://scripts/builder/interior_kits.gd").definitions()["kits"].get(kit,{}).get("name","Standard room"))+". Starter furnishings are complimentary; later edits and duplicates use ordinary construction prices. Existing rooms are preserved."
	if editing():
		caption.text = ("Walking · "+exploration.room_world().data_state["title"]) if exploration.preview else "Editing · " + studio.current().data["title"]
		if not is_instance_valid(exit_marker):
			exit_marker = Label.new() if dimension == "2d" else Label3D.new()
			exit_marker.text = "EXIT · E"
			studio.worlds[dimension].add_child(exit_marker)
			if dimension == "2d": exit_marker.z_index = 100
			else: exit_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		exit_marker.position = exit_point() + (Vector2(0,15) if dimension == "2d" else Vector3.UP)
		exit_marker.visible=not inside
	elif inside: caption.text = "Inside · " + exploration.room_world().data_state["title"]
	elif standalone:caption.text="Editing room · "+studio.current().data["title"]

func begin_walk() -> void:
	if not editing() or studio.current().canonical.data.get("floors",[]).is_empty(): return
	var exploration: Node=studio.worlds[dimension].exploration
	if exploration.interior: return
	studio.current().finish_checkpoint(); flush()
	floor_tools.dialog.hide(); floor_tools.connections.dialog.hide(); floor_tools.entrances.dialog.hide()
	var point: Variant=studio.worlds[dimension].player.position
	var world: Node=studio.worlds[dimension]
	walk_camera={"position":world.camera.position,"zoom":world.camera.zoom} if dimension=="2d" else {"target":world.target,"distance":world.distance,"yaw":world.yaw,"pitch":world.pitch}
	exploration.enter_preview(outer.object(uid),studio.current().canonical.data,studio.current().floor_uid,point)
	refresh()

func finish_walk(floor_uid: String,point: Variant,notice: String,key: String) -> void:
	if not editing() or dimension!=key: return
	if studio.walking: studio.set_walking(false)
	studio.current().switch_floor(floor_uid)
	clear_selection()
	var world: Node=studio.worlds[key]
	world.apply(studio.current().data); world.player.teleport_to(point)
	if key=="2d" and not walk_camera.is_empty(): world.camera.position=walk_camera["position"]; world.camera.zoom=walk_camera["zoom"]
	elif key=="3d" and not walk_camera.is_empty():
		world.target=walk_camera["target"]; world.distance=walk_camera["distance"]; world.yaw=walk_camera["yaw"]; world.pitch=walk_camera["pitch"]; world.update_camera()
	walk_camera={}
	studio.template_choice.select(["city","room","blank"].find(studio.current().data.get("template","room")))
	studio.refresh_controls()
	if not notice.is_empty(): studio.status.text=notice

func exit_preview(entry: Dictionary,key: String) -> void:
	if not editing() or dimension!=key: return
	var host_uid: String=uid
	leave(); studio.set_walking(true)
	var world: Node=studio.worlds[key]; var host: Dictionary=studio.current().object(host_uid)
	world.player.teleport_to(preload("res://scripts/builder/floor_entrances.gd").outside(world.instances[host_uid],host,entry,key,studio.library))

func walk_night() -> void:
	var exploration: Node=studio.worlds[dimension].exploration
	var doc: RefCounted=studio.current(); doc.finish_checkpoint()
	var floor_uid: String=exploration.active_floor()
	var before: Dictionary=doc.canonical.data.duplicate(true)
	var room: Dictionary=preload("res://scripts/builder/floor_plan.gd").room(doc.canonical.data,floor_uid); room["night"]=not room["night"]
	if doc.canonical.record_completed_change(before): doc.canonical.undo_history.back()["floor_uid"]=floor_uid
	flush(); exploration.apply_room(floor_uid)
	studio.dirty=studio.content_digest()!=studio.saved_digest; studio.autosave_pending=true; studio.update_save_badge()

func walk_home() -> void:
	# Close travel and chooser ownership before restarting at this floor's home.
	# A transit cancellation selects its safe source floor in finish_walk.
	studio.set_walking(false)
	studio.worlds[dimension].player.teleport_to(exit_point())
	studio.set_walking(true)
