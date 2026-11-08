extends SceneTree
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for i in 4: await process_frame
	await physics_frame
func capture(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/"+name+".png")
func run() -> void:
	var studio: Control=load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled=false
	root.add_child(studio)
	await settle()
	var picker: RefCounted=studio.overlap_picker
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		var doc: RefCounted=preload("res://scripts/builder/document.gd").new()
		doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
		studio.documents[mode]=doc
		studio.template_choice.select(2)
		var id: String="2d:Coffee_Shop" if mode=="2d" else "3d:HanX_Park/Bench_Park"
		var a: Dictionary=doc.add(id,[0,0,0],"SE" if mode=="2d" else "0")
		var b: Dictionary=doc.add(id,[0,0,0],a["direction"])
		var c: Dictionary=doc.add("3d:HanX_Park/Bench_Park" if mode=="2d" else "2d:Sofa_Teal",[0,0,0],"0" if mode=="2d" else "SE")
		a["name"]="Under the stack"
		b["name"]="Stack member"
		c["name"]="Mixed asset"
		a["group"]="stack"
		b["group"]="stack"
		doc.data["group_names"]={"stack":"Stacked group"}
		studio.clear_placement()
		studio.worlds[mode].apply(doc.data)
		studio.worlds[mode].reset_camera("room")
		if mode=="3d": studio.worlds[mode].distance=12; studio.worlds[mode].target=Vector3(0,.5,0); studio.worlds[mode].update_camera()
		await settle()
		var area: Rect2=studio.screen_bounds(a["uid"]).intersection(studio.screen_bounds(b["uid"])).intersection(studio.screen_bounds(c["uid"]))
		var at: Vector2=area.get_center()
		var found: bool=false
		for x in 11:
			for y in 11:
				var point: Vector2=area.position+area.size*Vector2((x+.5)/11.0,(y+.5)/11.0)
				var ids: Array[String]=picker.candidates(point)
				if ids.has(a["uid"]) and ids.has(b["uid"]) and ids.has(c["uid"]): at=point; found=true; break
			if found: break
		check(found,"All overlapping mixed assets can be enumerated at a common point: "+mode)
		if not found: continue
		var ids: Array[String]=picker.candidates(at)
		check(ids.size()==3,"Each object is returned once despite nested collision bodies: "+mode)
		if mode=="2d": check(ids[0]==c["uid"],"Equal-depth 2D overlaps use sibling drawing order")
		var before: Dictionary=doc.data.duplicate(true)
		var history: int=doc.undo_history.size()
		var seen: Array[String]=[]
		for i in ids.size(): picker.cycle(at); seen.append(studio.selected_uid)
		check(seen.size()==3 and seen.has(a["uid"]) and seen.has(b["uid"]) and seen.has(c["uid"]),"Repeated cycling visits every overlapping object: "+mode)
		picker.cycle(at)
		check(studio.selected_uid==seen[0],"Cycling wraps to its first object: "+mode)
		picker.cycle(at,-1)
		check(studio.selected_uid==seen.back(),"Reverse cycling returns to the preceding object: "+mode)
		picker.choose(a["uid"])
		check(studio.selected_uids==[a["uid"]],"A group member can be selected individually through the picker: "+mode)
		var click:=InputEventMouseButton.new()
		click.button_index=MOUSE_BUTTON_LEFT
		click.position=at
		click.alt_pressed=true
		click.pressed=true
		studio._canvas_input(click)
		check(studio.selected_uid!=a["uid"] and not studio.stroke,"Alt-click selects the next object without beginning a drag: "+mode)
		picker.show(at)
		await settle()
		var object_rows: int=0
		var action_rows: int=0
		for index in picker.popup.item_count:
			var metadata: Variant=picker.popup.get_item_metadata(index)
			if metadata is String:object_rows+=1
			elif metadata is Dictionary:action_rows+=1
		check(studio.modal_visible() and object_rows==3 and action_rows==3,"Pointer list contains each candidate and temporary view actions: "+mode)
		var choice: int=-1
		for index in picker.popup.item_count:
			var metadata: Variant=picker.popup.get_item_metadata(index)
			if metadata is String and metadata==a["uid"]: choice=index
		check(choice>=0 and picker.popup.get_item_text(choice).contains("Under the stack") and picker.popup.get_item_text(choice).contains("Stacked group"),"List labels identify named objects and groups: "+mode)
		await capture("editor_overlap_picker_"+mode)
		picker.popup.id_pressed.emit(choice)
		check(studio.selected_uid==a["uid"] and not picker.popup.visible,"Choosing a list row selects the intended object: "+mode)
		check(doc.data==before and doc.undo_history.size()==history,"Picking changes no project data or undo history: "+mode)
		b["locked"]=true
		c["visible"]=false
		studio.worlds[mode].apply(doc.data)
		await settle()
		ids=picker.candidates(at)
		check(ids==[a["uid"]],"Hidden and locked objects are excluded: "+mode)
		b["locked"]=false
		c["visible"]=true
		var layer: String=studio.Layers.layer(a,studio.library)
		studio.Layers.set_state(doc.data,layer,"locked",true)
		studio.worlds[mode].apply(doc.data)
		await settle()
		ids=picker.candidates(at)
		check(not ids.has(a["uid"]) and not ids.has(b["uid"]),"Locked layers are excluded: "+mode)
		studio.Layers.set_state(doc.data,layer,"locked",false)
		studio.worlds[mode].apply(doc.data)
		await settle()
		picker.show(at)
		# Candidates are revalidated if the document changes while a menu exists.
		doc.data["objects"].erase(a)
		picker.choose(a["uid"])
		check(not picker.popup.visible and doc.object(studio.selected_uid).is_empty(),"Stale menu choices cannot select deleted objects: "+mode)
		picker.show(Vector2(-10000,-10000))
		check(picker.popup.is_item_disabled(0),"Empty points offer an explicit disabled message: "+mode)
		picker.popup.hide()
		if mode=="2d":
			for index in 40:
				var extra: Dictionary=doc.add(id,[0,0,0],"SE")
				extra["name"]="A long overlapping object name that should still fit the picker "+str(index)
			studio.worlds[mode].apply(doc.data)
			await settle()
			picker.show(at)
			await settle()
			check(picker.popup.item_count==46 and picker.popup.size.y<=340 and picker.popup.size.x<=560,"Large overlap lists retain all 42 objects and stay bounded and scrollable")
			await capture("editor_overlap_picker_many")
			picker.popup.hide()
		studio.set_walking(true)
		var selected: String=studio.selected_uid
		picker.cycle(at)
		picker.show(at)
		check(studio.selected_uid==selected and not picker.popup.visible,"Walking cannot open the editing picker: "+mode)
		studio.set_walking(false)
	studio.free()
	print("OVERLAP PICKER: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
