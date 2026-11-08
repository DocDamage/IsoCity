extends SceneTree
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 6: await process_frame
	await physics_frame
func run() -> void:
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle(); studio.switch_mode("2d")
	var doc=preload("res://scripts/builder/document.gd").new(); doc.data=preload("res://scripts/builder/templates.gd").make("2d","blank"); doc.data["objects"]=[]; doc.data["terrain"]={"enabled":true,"bounds":[-8,-8,16,16]}; doc.data["terrain_vertices"]=[]
	for x in range(-8,9):
		for z in range(-8,9): doc.data["terrain_vertices"].append({"cell":[x,z],"height":2})
	var item: Dictionary=doc.add("2d:House_Blue",Traffic.world(Vector2(-4,-4),"2d"),"SE",.75); item["angle"]=37; studio.documents["2d"]=doc; studio.changed(); await settle(); var world: Node=studio.worlds["2d"]
	var raw: Array=Traffic.world(Vector2.ZERO,"2d",1); var expected: Vector2=studio.viewport.get_canvas_transform()*Vector2(raw[0],raw[1]-24)
	check(studio.overlay_position(raw).distance_to(expected)<.001,"Projected points combine manual elevation with actual terrain height")
	studio.selected_uid=item["uid"]; studio.selected_uids.assign([item["uid"]]); studio.set_tool("select"); studio.transform_handles.tick(); var pivot: Vector3=studio.transform_handles.pivot
	expected=studio.viewport.get_canvas_transform()*Vector2(pivot.x,pivot.y-(pivot.z+2)*8)
	check(studio.transform_handles.origin.distance_to(expected)<.001 and studio.transform_handles.handles.size()==3,"Transform handles align with raised, rotated/scaled props")
	var axis: Vector2=studio.transform_handles.project(pivot+Vector3.RIGHT)-studio.transform_handles.project(pivot)
	check(axis.distance_to(studio.viewport.get_canvas_transform().basis_xform(Vector2.RIGHT))<.001,"Handle drag axes remain a rigid logical projection above terrain")
	studio.update_overlay(true); check(studio.overlay.pivot_point.distance_to(expected)<.001,"The selected pivot marker uses the same height as its handles")
	var relative: Dictionary=item.duplicate(true); relative["position"]=[0,0,1]; studio.assemblies=[{"mode":"2d","name":"Terrain assembly","objects":[relative]}]; studio.show_assemblies(); studio.assembly_list.select(0); studio.choose_assembly(); studio.control_settings.cursor_active=true; studio.control_settings.cursor_position=studio.viewport.get_canvas_transform()*Vector2(0,-16); studio.update_assembly_preview(true)
	var ghost: Node=studio.assembly_ghosts[0]; var sprite: Sprite2D=ghost.get_node("Sprite2D"); var delta: Vector2=sprite.global_transform.basis_xform(ghost.terrain_visual_offset)
	check(delta.distance_to(Vector2(0,-16))<.001,"Assembly member previews receive terrain height in addition to their own elevation")
	studio.clear_assembly(); doc.data["terrain"]["enabled"]=false; studio.changed(); await settle(); check(studio.overlay_position(raw).distance_to(studio.viewport.get_canvas_transform()*Vector2(raw[0],raw[1]-8))<.001,"Disabled terrain restores the original point projection")
	studio.free(); print("TERRAIN EDITOR FEEDBACK: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
