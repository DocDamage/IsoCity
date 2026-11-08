extends RefCounted
const Plan=preload("res://scripts/builder/prop_plan.gd")
var candidate: Dictionary={}
var exploration: Node
var canvas: Node2D
var rig: Node3D
var seat: MeshInstance3D
var ropes: Array[MeshInstance3D]=[]
var meshes: Array[Dictionary]=[]
var sprite: Sprite2D
var original_texture: Texture2D
var masked_texture: Texture2D
var owner_node: WeakRef

func start(value: Dictionary,visit: Node) -> void:
	candidate=value; exploration=visit; owner_node=weakref(value["node"])
	var source_sprite: bool=value["item"]["asset"].begins_with("2d:")
	if source_sprite: hide_sprite_seat()
	else: hide_model_seat()
	if visit.dimension=="2d":
		canvas=preload("res://scripts/builder/prop_swing_2d.gd").new(); value["node"].add_child(canvas); canvas.color=Color("e9584d") if source_sprite else Color("48b98c")
	else:
		rig=Node3D.new(); rig.name="SwingUseRig"; value["node"].add_child(rig)
		seat=MeshInstance3D.new(); seat.mesh=BoxMesh.new(); var material:=StandardMaterial3D.new(); material.albedo_color=Color("e9584d") if source_sprite else Color("48b98c"); seat.material_override=material; rig.add_child(seat)
		for index in 2:
			var rope:=MeshInstance3D.new(); var cylinder:=CylinderMesh.new(); cylinder.top_radius=.012; cylinder.bottom_radius=.012; cylinder.radial_segments=6; cylinder.rings=1; rope.mesh=cylinder
			var metal:=StandardMaterial3D.new(); metal.albedo_color=Color("a8afb8"); rope.material_override=metal; rig.add_child(rope); ropes.append(rope)
	step(0)

func hide_sprite_seat() -> void:
	var node: Node=candidate["node"]; sprite=preload("res://scripts/builder/part_colors.gd").sprite_for(node)
	var rect: Array=candidate["profile"].get("seat_masks",{}).get(candidate["item"]["direction"],[])
	if not sprite or rect.size()!=4: return
	original_texture=sprite.texture; var image: Image=original_texture.get_image().duplicate(); image.convert(Image.FORMAT_RGBA8)
	for y in range(maxi(0,rect[1]),mini(image.get_height(),rect[1]+rect[3])):
		for x in range(maxi(0,rect[0]),mini(image.get_width(),rect[0]+rect[2])):
			var c: Color=image.get_pixel(x,y)
			if (c.r>c.g*1.5 and c.r>c.b*1.3) or (absf(c.r-c.g)<.12 and absf(c.b-c.g)<.15 and c.r>.12): image.set_pixel(x,y,Color(0,0,0,0))
	masked_texture=ImageTexture.create_from_image(image); masked_texture.set_meta("paint_base",original_texture.get_meta("paint_base",original_texture)); sprite.texture=masked_texture
	if node.has_method("mixed_bounds"): node.last_frame=""; node.update_visual()

func hide_model_seat() -> void:
	if Plan.definitions()["assets"].get(candidate["item"]["asset"],{}).get("kind")!="swing": return
	var root: Node3D=preload("res://scripts/builder/part_colors.gd").model_root(candidate["node"])
	var original_profile: Dictionary=Plan.profile({"asset":candidate["item"]["asset"]})
	var center: Vector3=Plan.source(original_profile,candidate["item"],exploration.library,"point"); var length: float=original_profile["rope_length"]
	for node in root.find_children("*","MeshInstance3D",true,false):
		if not node.mesh: continue
		var original: Mesh=node.mesh; var result:=ArrayMesh.new(); var overrides: Array=[]; var selected: Array=[]; var removed: int=0
		for surface in original.get_surface_count():
			var arrays: Array=original.surface_get_arrays(surface); var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]; var indices: PackedInt32Array=preload("res://scripts/builder/part_colors.gd").indices_for(arrays); var kept:=PackedInt32Array()
			for triangle in range(0,indices.size(),3):
				var point: Vector3=Vector3.ZERO
				for corner in 3: point+=root.to_local(node.to_global(vertices[indices[triangle+corner]]))/3
				if absf(point.x-center.x)<.42 and absf(point.z-center.z)<.7 and point.y>center.y-.25 and point.y<center.y+length-.12: removed+=1; continue
				for corner in 3: kept.append(indices[triangle+corner])
			overrides.append(node.get_surface_override_material(surface))
			if kept.is_empty(): continue
			arrays=arrays.duplicate(); arrays[Mesh.ARRAY_INDEX]=kept; result.add_surface_from_arrays(original.surface_get_primitive_type(surface),arrays); result.surface_set_material(result.get_surface_count()-1,original.surface_get_material(surface)); selected.append(surface)
		if removed==0: continue
		meshes.append({"node":weakref(node),"original":original,"masked":result,"overrides":overrides,"removed":removed}); node.mesh=result
		for index in selected.size(): node.set_surface_override_material(index,overrides[selected[index]])
	redraw()

func redraw() -> void:
	var node: Node=owner_node.get_ref()
	if is_instance_valid(node) and node.has_method("ground_polygon"): node.viewport.render_target_update_mode=SubViewport.UPDATE_ONCE

func step(phase: float) -> void:
	if not is_instance_valid(owner_node.get_ref()): return
	var length: float=candidate["profile"]["rope_length"]; var offset:=Vector3(0,length*(1-cos(phase)),sin(phase)*length)
	var center: Variant=Plan.global_point(candidate,exploration,"point",offset)
	var top_left: Variant=Plan.global_point(candidate,exploration,"point",Vector3(-.24,length,0)); var top_right: Variant=Plan.global_point(candidate,exploration,"point",Vector3(.24,length,0))
	var bottom_left: Variant=Plan.global_point(candidate,exploration,"point",offset+Vector3(-.24,0,0)); var bottom_right: Variant=Plan.global_point(candidate,exploration,"point",offset+Vector3(.24,0,0))
	if canvas:
		canvas.ropes.assign([canvas.to_local(top_left),canvas.to_local(bottom_left),canvas.to_local(top_right),canvas.to_local(bottom_right)])
		var polygon:=PackedVector2Array()
		for corner in [Vector3(-.3,0,-.16),Vector3(.3,0,-.16),Vector3(.3,0,.16),Vector3(-.3,0,.16)]: polygon.append(canvas.to_local(Plan.global_point(candidate,exploration,"point",offset+corner)))
		canvas.seat=polygon; canvas.queue_redraw()
	else:
		var width: float=bottom_left.distance_to(bottom_right); var axis: Vector3=bottom_right-bottom_left; axis.y=0; axis=axis.normalized()
		if axis.is_zero_approx(): axis=Vector3.RIGHT
		var scale: Vector3=candidate["node"].global_basis.get_scale()
		seat.global_transform=Transform3D(Basis(axis,Vector3.UP,axis.cross(Vector3.UP)).scaled(Vector3(maxf(.05,width*1.25),.07*scale.y,maxf(.07,width*.65))),center-Vector3.UP*.04*scale.y)
		for index in 2:
			var start: Vector3=top_left if index==0 else top_right; var end: Vector3=bottom_left if index==0 else bottom_right; var direction: Vector3=(end-start).normalized(); var right: Vector3=direction.cross(Vector3.FORWARD).normalized()
			if right.is_zero_approx(): right=Vector3.RIGHT
			var basis:=Basis(right,direction,right.cross(direction)).orthonormalized(); ropes[index].global_transform=Transform3D(basis.scaled(Vector3(scale.x,start.distance_to(end)/2,scale.x)),(start+end)*.5)

func reset() -> void:
	if is_instance_valid(sprite) and sprite.texture==masked_texture: sprite.texture=original_texture
	for record in meshes:
		var node: MeshInstance3D=record["node"].get_ref()
		if not is_instance_valid(node) or node.mesh!=record["masked"]: continue
		node.mesh=record["original"]
		for index in record["overrides"].size(): node.set_surface_override_material(index,record["overrides"][index])
	if owner_node:
		var node: Node=owner_node.get_ref()
		if is_instance_valid(node) and node.is_inside_tree() and node.has_method("mixed_bounds"): node.last_frame=""; node.update_visual()
		redraw()
	if is_instance_valid(canvas): canvas.free()
	if is_instance_valid(rig): rig.free()
	canvas=null; rig=null; seat=null; ropes.clear(); meshes.clear(); sprite=null; original_texture=null; masked_texture=null; candidate={}; owner_node=null
