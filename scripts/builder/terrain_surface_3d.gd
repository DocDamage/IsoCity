extends Node3D
const Plan=preload("res://scripts/builder/terrain_plan.gd")
const CHUNK_SIZE: int=16
var chunks: Dictionary={}
var signatures: Dictionary={}
var last_rebuilt: int=0
var source: Dictionary={}
var signature: int=0
var boundary: Node3D
var boundary_signature: int=0
var floor_bounds:=Rect2()
var floor_holes: Array=[]
func configure(data: Dictionary) -> void:
	source=data; last_rebuilt=0
	if not Plan.settings(data)["enabled"] or not Plan.Layers.shown(data,"Ground"): clear(); return
	var input_stamp: int=hash([data.get("terrain",{}),data.get("terrain_vertices",[]),data.get("water_cells",[]),floor_bounds,floor_holes,preload("res://scripts/builder/city_foundation.gd").bounds(data)])
	if input_stamp==signature and not chunks.is_empty(): return
	var area: Rect2i=Plan.bounds(data); var buckets: Dictionary={}
	for water in [false,true]:
		for record in data.get("water_cells" if water else "terrain_vertices",[]):
			var cell:=Vector2i(record["cell"][0],record["cell"][1]); var base:=Vector2i(floori(float(cell.x)/CHUNK_SIZE),floori(float(cell.y)/CHUNK_SIZE)); var owners: Array[Vector2i]=[base]
			if not water:
				if posmod(cell.x,CHUNK_SIZE)==0: owners.append(base+Vector2i.LEFT)
				if posmod(cell.y,CHUNK_SIZE)==0: owners.append(base+Vector2i.UP)
				if posmod(cell.x,CHUNK_SIZE)==0 and posmod(cell.y,CHUNK_SIZE)==0: owners.append(base-Vector2i.ONE)
			for owner in owners:
				var id: String=Plan.key(owner)
				if not buckets.has(id): buckets[id]=[]
				buckets[id].append([water,record["cell"],record["level" if water else "height"]])
	var settings: Dictionary=Plan.settings(data); var keep: Dictionary={}; var heights: Dictionary=Plan.lookup(data); var waters: Dictionary=Plan.lookup(data,true)
	configure_boundary(data,heights)
	for x in range(floori(float(area.position.x)/CHUNK_SIZE),ceili(float(area.end.x)/CHUNK_SIZE)):
		for y in range(floori(float(area.position.y)/CHUNK_SIZE),ceili(float(area.end.y)/CHUNK_SIZE)):
			var cell:=Vector2i(x,y); var id: String=Plan.key(cell); var region: Rect2i=Rect2i(cell*CHUNK_SIZE,Vector2i.ONE*CHUNK_SIZE).intersection(area)
			var stamp: int=hash([region,buckets.get(id,[]),settings["land_color"],settings["water_color"],floor_holes]); keep[id]=true
			if signatures.get(id)==stamp and is_instance_valid(chunks.get(id)): continue
			if is_instance_valid(chunks.get(id)): chunks[id].free()
			var chunk: Node3D=make_chunk(data,region,heights,waters,floor_holes); chunk.name=("Terrain_"+id).validate_node_name(); add_child(chunk); chunks[id]=chunk; signatures[id]=stamp; last_rebuilt+=1
	for id in chunks.keys():
		if not keep.has(id): chunks[id].free(); chunks.erase(id); signatures.erase(id)
	signature=input_stamp
func configure_boundary(data: Dictionary,heights: Dictionary) -> void:
	var grid: Rect2i=Plan.bounds(data); var area:=Rect2(Vector2(grid.position)*Plan.CELL_SIZE,Vector2(grid.size)*Plan.CELL_SIZE)
	var edges: Array[Vector3]=[]
	for x in range(grid.position.x,grid.end.x+1):
		edges.append(Plan.vertex(heights,Vector2i(x,grid.position.y))); edges.append(Plan.vertex(heights,Vector2i(x,grid.end.y)))
	for y in range(grid.position.y,grid.end.y+1):
		edges.append(Plan.vertex(heights,Vector2i(grid.position.x,y))); edges.append(Plan.vertex(heights,Vector2i(grid.end.x,y)))
	var foundation: Rect2=floor_bounds if floor_bounds.has_area() else preload("res://scripts/builder/city_foundation.gd").bounds(data)
	var stamp: int=hash([area,edges,Plan.settings(data)["land_color"],floor_bounds,floor_holes,foundation])
	if stamp==boundary_signature and is_instance_valid(boundary): return
	if is_instance_valid(boundary): boundary.free()
	boundary=Node3D.new(); boundary.name="Boundary"; add_child(boundary); boundary_signature=stamp
	var points:=PackedVector3Array(); var normals:=PackedVector3Array(); var colors:=PackedColorArray(); var color:=Color(Plan.settings(data)["land_color"])
	# Preserve the existing city foundation outside the sculpted rectangle.
	var overlap: Rect2=foundation.intersection(area); var rectangles: Array[Rect2]=[]
	if not foundation.intersects(area): rectangles.append(foundation)
	else:
		rectangles.append(Rect2(foundation.position,Vector2(foundation.size.x,overlap.position.y-foundation.position.y)))
		rectangles.append(Rect2(Vector2(foundation.position.x,overlap.end.y),Vector2(foundation.size.x,foundation.end.y-overlap.end.y)))
		rectangles.append(Rect2(Vector2(foundation.position.x,overlap.position.y),Vector2(overlap.position.x-foundation.position.x,overlap.size.y)))
		rectangles.append(Rect2(Vector2(overlap.end.x,overlap.position.y),Vector2(foundation.end.x-overlap.end.x,overlap.size.y)))
	for rect in rectangles:
		if rect.size.x<=0 or rect.size.y<=0: continue
		var a:=Vector3(rect.position.x,0,rect.position.y); var b:=Vector3(rect.end.x,0,rect.position.y); var c:=Vector3(rect.position.x,0,rect.end.y); var d:=Vector3(rect.end.x,0,rect.end.y)
		for point in [a,b,c,b,d,c]: points.append(point); normals.append(Vector3.UP); colors.append(color)
	# Close exposed raised or depressed edges to the outside datum. Both faces
	# receive collision, so an abrupt boundary behaves as a wall from either side.
	for index in range(0,edges.size()-2,2):
		if index==2*grid.size.x: continue
		for side in 2:
			var a: Vector3=edges[index+side]; var b: Vector3=edges[index+2+side]; var c:=Vector3(a.x,0,a.z); var d:=Vector3(b.x,0,b.z)
			for face in [[a,b,c],[b,d,c]]:
				var normal: Vector3=(face[1]-face[0]).cross(face[2]-face[0]).normalized()
				if normal.is_zero_approx(): continue
				for order in [[0,1,2],[0,2,1]]:
					for vertex_index in order: points.append(face[vertex_index]); normals.append(normal if order[1]==1 else -normal); colors.append(color.darkened(.18))
	if points.is_empty(): return
	var material:=StandardMaterial3D.new(); material.vertex_color_use_as_albedo=true; material.roughness=1
	var body:=StaticBody3D.new(); body.name="Surface"; body.collision_layer=2; body.collision_mask=0; boundary.add_child(body)
	var land:=MeshInstance3D.new(); land.name="Land"; land.mesh=mesh(points,normals,colors,material)
	if not floor_holes.is_empty(): land.mesh=preload("res://scripts/builder/floor_cutouts_3d.gd").mesh(land.mesh,Transform3D.IDENTITY,floor_holes)
	body.add_child(land)
	if land.mesh.get_surface_count()>0:
		var shape:=CollisionShape3D.new(); shape.shape=land.mesh.create_trimesh_shape(); body.add_child(shape)
static func mesh(points: PackedVector3Array,normals: PackedVector3Array,colors: PackedColorArray,material: Material) -> ArrayMesh:
	var result:=ArrayMesh.new()
	if points.is_empty(): return result
	var arrays: Array=[]; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX]=points; arrays[Mesh.ARRAY_NORMAL]=normals; arrays[Mesh.ARRAY_COLOR]=colors; result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays); result.surface_set_material(0,material); return result
static func make_chunk(data: Dictionary,area: Rect2i,heights: Dictionary,waters: Dictionary,holes: Array=[]) -> Node3D:
	var result:=Node3D.new(); var points:=PackedVector3Array(); var normals:=PackedVector3Array(); var colors:=PackedColorArray(); var water_points:=PackedVector3Array(); var water_normals:=PackedVector3Array(); var water_colors:=PackedColorArray()
	var config: Dictionary=Plan.settings(data); var land_color:=Color(config["land_color"]); var water_color:=Color(config["water_color"]); water_color.a*=.72
	for x in range(area.position.x,area.end.x):
		for y in range(area.position.y,area.end.y):
			var cell:=Vector2i(x,y)
			for face in Plan.triangles(data,cell,heights):
				var normal: Vector3=(face[1]-face[0]).cross(face[2]-face[0]).normalized(); var tint: Color=land_color.lerp(Color("a38d67"),clampf((1-normal.y)*.8,0,.65))
				# Godot uses clockwise front faces; the planning triangles retain
				# mathematical upward winding for interpolation and clipping.
				for polygon in preload("res://scripts/builder/floor_terrain_plan.gd").fragments(face,holes):
					for index in range(1,polygon.size()-1):
						for point in [polygon[0],polygon[index+1],polygon[index]]: points.append(point); normals.append(normal); colors.append(tint)
			for polygon in Plan.water_polygons(data,cell,heights,waters):
				for fragment in preload("res://scripts/builder/floor_terrain_plan.gd").fragments(polygon,holes):
					for index in range(1,fragment.size()-1):
						for point in [fragment[0],fragment[index+1],fragment[index]]: water_points.append(point); water_normals.append(Vector3.UP); water_colors.append(water_color)
	var land_material:=StandardMaterial3D.new(); land_material.vertex_color_use_as_albedo=true; land_material.roughness=1
	var land:=MeshInstance3D.new(); land.name="Land"; land.mesh=mesh(points,normals,colors,land_material)
	var body:=StaticBody3D.new(); body.name="Surface"; body.collision_layer=2; body.collision_mask=0; result.add_child(body); body.add_child(land)
	if land.mesh.get_surface_count()>0:
		var collider:=CollisionShape3D.new(); collider.name="TerrainCollision"; collider.shape=land.mesh.create_trimesh_shape(); body.add_child(collider)
	if not water_points.is_empty():
		var material:=StandardMaterial3D.new(); material.vertex_color_use_as_albedo=true; material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; material.roughness=.25
		var water:=MeshInstance3D.new(); water.name="Water"; water.mesh=mesh(water_points,water_normals,water_colors,material); water.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; result.add_child(water)
	return result
func clear() -> void:
	if is_instance_valid(boundary): boundary.free()
	boundary=null; boundary_signature=0
	for chunk in chunks.values():
		if is_instance_valid(chunk): chunk.free()
	chunks.clear(); signatures.clear(); signature=0
