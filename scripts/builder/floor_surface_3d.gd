extends Node3D

const Cut=preload("res://scripts/builder/floor_cutouts_3d.gd")
var openings: Array=[]
var bounds: Rect2
var world: Node3D
var platform: StaticBody3D
var clipped: Dictionary={}
var passages: Array=[]
var road_cache: Dictionary={}

func configure(owner_world: Node3D,area: Rect2,holes: Array,terrain_passages: Array=[]) -> void:
	world=owner_world; bounds=area; openings=holes; passages=terrain_passages
	platform=StaticBody3D.new(); platform.name="FloorPlatform"; platform.collision_layer=2; add_child(platform)
	var box:=BoxMesh.new(); box.size=Vector3(area.size.x,0.16,area.size.y)
	var offset:=Transform3D(Basis.IDENTITY,Vector3(area.get_center().x,-0.08,area.get_center().y))
	var mesh:=MeshInstance3D.new(); mesh.mesh=Cut.mesh(box,offset,holes); mesh.transform=offset
	var foundation: Node=world.get_node("Foundation")
	mesh.material_override=foundation.get_child(0).material_override
	platform.add_child(mesh)
	add_platform_collision(area,holes)
	rebuild()

func add_platform_collision(area: Rect2,holes: Array) -> void:
	# Keep the exact flat slab/opening volume without concave triangle seams
	# that can depenetrate a capsule sideways across a clipped mesh T-junction.
	# Authored mesh/road collisions continue to use their actual source meshes.
	var rectangle: Array=[]
	for corner in [area.position,Vector2(area.end.x,area.position.y),area.end,Vector2(area.position.x,area.end.y)]:rectangle.append({"plane":corner})
	var pieces: Array=[rectangle]
	for hole in holes:
		var next: Array=[]
		for piece in pieces:next.append_array(Cut.subtract(piece,hole))
		pieces=next
	for piece in pieces:
		var polygon:=PackedVector2Array()
		for vertex in piece:
			if polygon.is_empty() or not polygon[-1].is_equal_approx(vertex["plane"]):polygon.append(vertex["plane"])
		if polygon.size()>1 and polygon[0].is_equal_approx(polygon[-1]):polygon.resize(polygon.size()-1)
		if polygon.size()<3:continue
		var twice_area: float=0
		for index in polygon.size():twice_area+=polygon[index].cross(polygon[(index+1)%polygon.size()])
		if absf(twice_area)<.000001:continue
		var points:=PackedVector3Array()
		for point in polygon:
			points.append(Vector3(point.x,0,point.y));points.append(Vector3(point.x,-.16,point.y))
		var shape:=CollisionShape3D.new();var hull:=ConvexPolygonShape3D.new();hull.points=points;hull.margin=.001;shape.shape=hull;platform.add_child(shape)

func add_collision(parent: Node,mesh: Mesh,pose: Transform3D) -> void:
	if mesh.get_surface_count()==0: return
	var shape:=CollisionShape3D.new(); shape.shape=mesh.create_trimesh_shape(); shape.transform=pose; parent.add_child(shape)

func restore_instance(instance: Node3D) -> void:
	var meshes: Array=instance.find_children("*","MeshInstance3D",true,false)
	if instance is MeshInstance3D: meshes.push_front(instance)
	for mesh in meshes: restore_mesh(mesh)
	clipped.erase(str(instance.get_meta("builder_uid","")))

func restore_mesh(mesh: MeshInstance3D) -> void:
	if not mesh.has_meta("floor_cut_mesh") or not is_same(mesh.mesh,mesh.get_meta("floor_cut_mesh")): return
	mesh.mesh=mesh.get_meta("floor_source_mesh")
	var overrides: Array=mesh.get_meta("floor_source_overrides",[])
	for index in mini(overrides.size(),mesh.mesh.get_surface_count()): mesh.set_surface_override_material(index,overrides[index])
	mesh.remove_meta("floor_cut_mesh")

func clip_mesh(mesh: MeshInstance3D,frame: Transform3D,holes: Array=[]) -> void:
	restore_mesh(mesh)
	var source: Mesh=mesh.mesh; var overrides: Array=[]
	for index in source.get_surface_count(): overrides.append(mesh.get_surface_override_material(index))
	mesh.set_meta("floor_source_mesh",source); mesh.set_meta("floor_source_overrides",overrides)
	mesh.mesh=Cut.mesh(source,frame,openings if holes.is_empty() else holes)
	var surfaces: PackedInt32Array=mesh.mesh.get_meta("floor_source_surfaces",PackedInt32Array())
	for index in mesh.mesh.get_surface_count(): mesh.set_surface_override_material(index,overrides[surfaces[index] if not surfaces.is_empty() else index])
	mesh.set_meta("floor_cut_mesh",mesh.mesh)

func rebuild() -> void:
	if not world: return
	world.get_node("Foundation").visible=false; world.get_node("Foundation").collision_layer=0
	var sculpted: bool=preload("res://scripts/builder/terrain_plan.gd").settings(world.data_state)["enabled"]
	var shown: bool=preload("res://scripts/builder/layers.gd").shown(world.data_state,"Ground")
	platform.visible=not sculpted and shown; platform.collision_layer=2 if not sculpted and shown else 0
	world.terrain.floor_bounds=bounds; world.terrain.floor_holes=passages; world.terrain.configure(world.data_state)
	world.terrain_traversal.exclusions=passages
	clip_roads(shown)
	if openings.is_empty(): return
	var keep: Dictionary={}
	for item in world.data_state.get("objects",[]):
		if preload("res://scripts/builder/layers.gd").layer(item,world.library)!="Ground" or not world.instances.has(item["uid"]): continue
		var instance: Node3D=world.instances[item["uid"]]
		keep[item["uid"]]=true
		if instance.has_signal("before_visual_update") and not instance.has_meta("floor_visual_bound"):
			instance.set_meta("floor_visual_bound",true)
			instance.before_visual_update.connect(restore_instance.bind(instance))
			instance.visual_updated.connect(rebuild)
		for body in [instance]+instance.find_children("*","CollisionObject3D",true,false):
			if body is CollisionObject3D:
				var layer: int=(2 if instance.visible else 0) if body.name=="FloorCutCollision" else 0
				if body.collision_layer!=layer: body.collision_layer=layer
		var signature: int=hash([item,openings,instance.global_transform,instance.visible,world.data_state.get("night",false)])
		if clipped.has(item["uid"]) and clipped[item["uid"]]["node"]==instance and clipped[item["uid"]]["signature"]==signature: continue
		var old: Node=instance.get_node_or_null("FloorCutCollision")
		if old: old.free()
		for body in [instance]+instance.find_children("*","CollisionObject3D",true,false):
			if body is CollisionObject3D: body.collision_layer=0
		var collision:=StaticBody3D.new(); collision.name="FloorCutCollision"; collision.collision_layer=2 if instance.visible else 0; instance.add_child(collision)
		var meshes: Array=instance.find_children("*","MeshInstance3D",true,false)
		if instance is MeshInstance3D: meshes.push_front(instance)
		for mesh in meshes:
			if not mesh.mesh and not mesh.has_meta("floor_source_mesh"): continue
			var frame: Transform3D=world.global_transform.affine_inverse()*mesh.global_transform
			clip_mesh(mesh,frame)
			add_collision(collision,mesh.mesh,instance.global_transform.affine_inverse()*mesh.global_transform)
		clipped[item["uid"]]={"node":instance,"signature":signature}
	for uid in clipped.keys():
		if not keep.has(uid): clipped.erase(uid)

func clip_roads(shown: bool) -> void:
	for key in road_cache.keys():
		if not is_instance_valid(road_cache[key]): road_cache.erase(key)
	if passages.is_empty() or not is_instance_valid(world.road_node): return
	for section in world.road_node.get_children():
		var id: int=section.get_instance_id()
		for body in [section]+section.find_children("*","CollisionObject3D",true,false):
			if body is CollisionObject3D: body.collision_layer=2 if body.name=="FloorRoadCutCollision" and shown else 0
		if road_cache.has(id): continue
		var collision:=StaticBody3D.new(); collision.name="FloorRoadCutCollision"; collision.collision_layer=2 if shown else 0; section.add_child(collision)
		for mesh in section.find_children("*","MeshInstance3D",true,false):
			if not mesh.mesh: continue
			clip_mesh(mesh,world.global_transform.affine_inverse()*mesh.global_transform,passages)
			add_collision(collision,mesh.mesh,section.global_transform.affine_inverse()*mesh.global_transform)
		road_cache[id]=section
