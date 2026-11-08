extends Node
signal advance_requested(uid: String)
const Plan=preload("res://scripts/builder/zone_plan.gd")
const Stages=preload("res://scripts/builder/zone_stage_plan.gd")
const Terrain=preload("res://scripts/builder/terrain_plan.gd")
var data: Dictionary={}
var library: RefCounted
var container: Node
var visuals: Dictionary={}
var visual_signatures: Dictionary={}
var timers: Dictionary={}
var states: Dictionary={}
var lot_signatures: Dictionary={}
var people: Array[Vector2]=[]
var active: bool=true
var paused: bool=false
var signature: int=0
var poll_time: float=0
var poll_index: int=0
var show_hud: bool=false
var panel: PanelContainer
var summary: Label
var pause_button: Button
var ui_time: float=0
var text_scale: float=1.0
func set_text_scale(value: float) -> void:
	if is_equal_approx(value,text_scale): return
	text_scale=value
	for marker in visuals.values():
		if marker is Node2D: marker.text_scale=value; marker.queue_redraw()
		else:
			for label in marker.find_children("*","Label3D",true,false): label.font_size=roundi(24*value)
func configure(source: Dictionary,assets: RefCounted,parent: Node) -> void:
	library=assets
	if source.get("zones",[]).is_empty():
		reset(); data=source; return
	if is_instance_valid(container) and container.get_parent()!=parent: reset()
	var art: Dictionary=Stages.available(library) if source["zones"].any(Plan.stage_dressed) else {}
	var stamp: int=hash([Plan.Candidates.definitions().get("revision",""),library.project_palette_revision,source["mode"],source.get("zones",[]),source.get("zoning",{}),source["objects"],source.get("roads",[]),source.get("layers",{}),source.get("terrain",{}),source.get("terrain_vertices",[]),source.get("water_cells",[]),source.get("economy",{}),source.get("economy_account",{}).get("cash"),source.get("economy_account",{}).get("construction_total"),art])
	if signature==stamp and is_instance_valid(container): return
	data=source; signature=stamp; states.clear()
	if show_hud and not is_instance_valid(panel): build_hud()
	if not is_instance_valid(container):
		container=Node2D.new() if data["mode"]=="2d" else Node3D.new(); container.name="ZoningLots"; parent.add_child(container)
		if container is Node2D:
			container.z_index=-2
			container.y_sort_enabled=true
	var keep: Dictionary={}
	var heights: Dictionary=Terrain.lookup(data)
	for lot in data.get("zones",[]):
		var uid: String=lot["uid"]; keep[uid]=true
		var terrain_stamp: int=preload("res://scripts/builder/terrain_site.gd").signature(data,Plan.rectangle(lot),heights)
		var changed: int=hash([lot,Plan.settings(data)["seed"],terrain_stamp])
		if lot_signatures.get(uid)!=changed: timers[uid]=0.0
		lot_signatures[uid]=changed
		var visual_stamp: int=hash([lot,terrain_stamp,art if Plan.stage_dressed(lot) else {}])
		if visual_signatures.get(uid)!=visual_stamp:
			if visuals.has(uid): visuals[uid].free(); visuals.erase(uid)
			if lot.get("visible",true): visuals[uid]=make_visual(lot,art,heights)
			visual_signatures[uid]=visual_stamp
	for uid in visual_signatures.keys():
		if keep.has(uid): continue
		if visuals.has(uid): visuals[uid].free(); visuals.erase(uid)
		visual_signatures.erase(uid); lot_signatures.erase(uid); timers.erase(uid)
	container.visible=Plan.Layers.shown(data,"Buildings") and Plan.Layers.shown(data,"Ground")
	poll_time=.5
	update_hud()
func build_hud() -> void:
	var layer:=CanvasLayer.new(); layer.layer=17; add_child(layer)
	panel=PanelContainer.new(); panel.custom_minimum_size=Vector2(280,0); layer.add_child(panel)
	var box:=VBoxContainer.new(); panel.add_child(box)
	summary=Label.new(); summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; summary.custom_minimum_size.x=280; box.add_child(summary)
	pause_button=Button.new(); pause_button.custom_minimum_size.y=36; box.add_child(pause_button); pause_button.pressed.connect(func(): paused=not paused; update_hud())
func update_hud() -> void:
	if not is_instance_valid(panel): return
	panel.visible=show_hud and not data.get("zones",[]).is_empty()
	if not panel.visible: return
	var counts: Array=[0,0,0,0,0]
	for lot in data["zones"]: counts[int(lot.get("stage",0))]+=1
	summary.text="Zoning · %d lots\nVacant %d · foundation %d · framing %d\nFinishing %d · developed %d" % [data["zones"].size(),counts[Plan.Stage.VACANT],counts[Plan.Stage.FOUNDATION],counts[Plan.Stage.FRAMING],counts[Plan.Stage.FINISHING],counts[Plan.Stage.DEVELOPED]]
	if not Plan.settings(data)["enabled"]: summary.text+="\nDevelopment is disabled."
	elif not active: summary.text+="\nOutside development is suspended."
	pause_button.disabled=not Plan.settings(data)["enabled"]
	pause_button.text="Resume development" if paused else "Pause development"
	panel.position=Vector2(20,maxf(220,get_viewport().get_visible_rect().size.y-panel.size.y-20))
func material(color: Color) -> StandardMaterial3D:
	var value:=StandardMaterial3D.new(); value.albedo_color=color; value.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; value.cull_mode=BaseMaterial3D.CULL_DISABLED
	if color.a<1: value.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	return value
func box(parent: Node3D,position: Vector3,size: Vector3,color: Color) -> void:
	var mesh:=MeshInstance3D.new(); var shape:=BoxMesh.new(); shape.size=size; mesh.mesh=shape; mesh.material_override=material(color); mesh.position=position; mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; parent.add_child(mesh)
func frame(parent: Node3D,bounds: Rect2,height: float,color: Color) -> void:
	var center: Vector2=bounds.get_center()
	for x in [bounds.position.x,bounds.end.x]: box(parent,Vector3(x,height,center.y),Vector3(.12,.12,bounds.size.y),color)
	for y in [bounds.position.y,bounds.end.y]: box(parent,Vector3(center.x,height,y),Vector3(bounds.size.x,.12,.12),color)
func make_visual(lot: Dictionary,art: Dictionary={},heights: Dictionary={}) -> Node:
	var layout: Dictionary=Stages.layout(data,lot,library,art,heights)
	if data["mode"]=="2d":
		var drawing:=preload("res://scripts/builder/zone_visual_2d.gd").new()
		drawing.lot=lot.duplicate(true)
		drawing.text_scale=text_scale
		drawing.terrain_data=data
		drawing.heights=heights if not heights.is_empty() else Terrain.lookup(data)
		drawing.stage_layout=layout
		drawing.y_sort_enabled=true
		container.add_child(drawing)
		add_scenery(drawing,layout)
		drawing.queue_redraw()
		return drawing
	var root:=StaticBody3D.new(); root.collision_layer=0; root.collision_mask=0; container.add_child(root)
	var bounds: Rect2=Plan.rectangle(lot); var center: Vector2=bounds.get_center(); var color:=Color(Plan.definitions()[lot["kind"]]["color"])
	box(root,Vector3(center.x,.065,center.y),Vector3(bounds.size.x,.035,bounds.size.y),Color(color,.12)); frame(root,bounds,.1,color)
	var stage: int=int(lot.get("stage",0))
	var footprint: Rect2=layout["pad"]
	if footprint.has_area():
		var at: Vector2=footprint.get_center()
		box(root,Vector3(at.x,.065,at.y),Vector3(footprint.size.x,.09,footprint.size.y),Stages.pad_color(stage))
		if layout["fallback"] and stage==Plan.Stage.FRAMING:
			frame(root,footprint,4,Color("e6b977"))
			for x in [footprint.position.x,footprint.end.x]:
				for y in [footprint.position.y,footprint.end.y]: box(root,Vector3(x,2,y),Vector3(.18,4,.18),Color("d49c55"))
		elif layout["fallback"] and stage==Plan.Stage.FINISHING:
			var size: Vector2=footprint.size*.32
			for side in [-1,1]:
				box(root,Vector3(at.x+size.x*.68*side,.23,at.y),Vector3(size.x,.32,size.y),Color("c98751"))
	var label:=Label3D.new(); label.text=Plan.definitions()[lot["kind"]]["label"]+" · "+Plan.stage_name(lot); label.billboard=BaseMaterial3D.BILLBOARD_ENABLED; label.font_size=roundi(24*text_scale); label.pixel_size=.025; label.outline_size=5; label.position=Vector3(bounds.position.x,4.5 if layout["fallback"] and stage==Plan.Stage.FRAMING else .8,bounds.position.y); root.add_child(label)
	if Terrain.settings(data)["enabled"]:
		var levels: Dictionary=heights if not heights.is_empty() else Terrain.lookup(data)
		preload("res://scripts/builder/terrain_roads_3d.gd").deform(root,data,levels)
		label.position.y+=Terrain.sample(data,bounds.position,levels)["height"]
	add_scenery(root,layout)
	return root
func add_scenery(root: Node,layout: Dictionary) -> void:
	root.set_meta("stage_scenery_missing",layout["missing"])
	root.set_meta("stage_scenery_fallback",layout["fallback"])
	Stages.present(root,layout["props"],data["mode"],library,data.get("night",false))
func step(delta: float) -> void:
	if not active or paused or data.is_empty() or library==null or not Plan.settings(data)["enabled"] or not is_finite(delta) or delta<=0: return
	var lots: Array=data.get("zones",[])
	if lots.is_empty(): return
	var tick: float=minf(delta,.25); poll_time+=tick
	if poll_time>=.5:
		poll_time=0; poll_index=posmod(poll_index,lots.size()); var lot: Dictionary=lots[poll_index]; poll_index+=1
		states[lot["uid"]]=Plan.evaluate(data,lot,library,people)
	for lot in lots:
		var uid: String=lot["uid"]; var state: Dictionary=states.get(uid,{})
		if not state.get("ok",false) or state.get("complete",false): continue
		timers[uid]=float(timers.get(uid,0))+tick*float(state.get("rate",0))
		if timers[uid]>=Plan.settings(data)["stage_seconds"]:
			timers[uid]=Plan.settings(data)["stage_seconds"]; states.erase(uid); advance_requested.emit(uid); return
func reset() -> void:
	if is_instance_valid(container): container.free()
	container=null; data={}; visuals.clear(); visual_signatures.clear(); timers.clear(); states.clear(); lot_signatures.clear(); people.clear(); signature=0; poll_time=0; poll_index=0
	if is_instance_valid(panel): panel.hide()
func _process(delta: float) -> void:
	step(delta); ui_time+=delta
	if ui_time>=.4: ui_time=0; update_hud()
func _notification(what: int) -> void:
	if what==NOTIFICATION_PREDELETE: reset()
