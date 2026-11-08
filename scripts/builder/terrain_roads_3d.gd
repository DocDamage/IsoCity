extends RefCounted
const Plan=preload("res://scripts/builder/terrain_plan.gd")
# Split road triangles on the same grid and diagonal as the terrain. Merely
# lifting a road's corners would bridge depressions and intersect sharp banks.
static func cut(polygon: Array,axis: Vector2,limit: float) -> Array:
	var result: Array=[]
	if polygon.is_empty(): return result
	var previous: Dictionary=polygon[-1]; var distance: float=axis.dot(Vector2(previous["p"].x,previous["p"].z))-limit
	for current in polygon:
		var next: float=axis.dot(Vector2(current["p"].x,current["p"].z))-limit
		if (distance<=.000001)!=(next<=.000001):
			var t: float=distance/(distance-next)
			result.append({"p":previous["p"].lerp(current["p"],t),"color":previous["color"].lerp(current["color"],t),"uv":previous["uv"].lerp(current["uv"],t)})
		if next<=.000001: result.append(current)
		previous=current; distance=next
	return result
static func deform(section: StaticBody3D,data: Dictionary,heights: Dictionary) -> void:
	var collision:=PackedVector3Array(); var area: Rect2i=Plan.bounds(data)
	for child in section.get_children():
		if not child is MeshInstance3D or not child.mesh: continue
		var output:=ArrayMesh.new()
		for surface in child.mesh.get_surface_count():
			var source: Array=child.mesh.surface_get_arrays(surface); var vertices: PackedVector3Array=source[Mesh.ARRAY_VERTEX]; var indices: PackedInt32Array=source[Mesh.ARRAY_INDEX] if source[Mesh.ARRAY_INDEX]!=null else PackedInt32Array(); var colors: PackedColorArray=source[Mesh.ARRAY_COLOR] if source[Mesh.ARRAY_COLOR]!=null else PackedColorArray(); var uvs: PackedVector2Array=source[Mesh.ARRAY_TEX_UV] if source[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
			var points:=PackedVector3Array(); var normals:=PackedVector3Array(); var tints:=PackedColorArray(); var texcoords:=PackedVector2Array()
			for start in range(0,indices.size() if not indices.is_empty() else vertices.size(),3):
				var triangle: Array=[]; var low:=Vector2(INF,INF); var high:=Vector2(-INF,-INF)
				for offset in 3:
					var index: int=indices[start+offset] if not indices.is_empty() else start+offset; var point: Vector3=child.transform*vertices[index]+section.position
					triangle.append({"p":point,"color":colors[index] if not colors.is_empty() else Color.WHITE,"uv":uvs[index] if not uvs.is_empty() else Vector2.ZERO}); low=low.min(Vector2(point.x,point.z)); high=high.max(Vector2(point.x,point.z))
				var first:=Vector2i((low/Plan.CELL_SIZE).floor()); var last:=Vector2i(((high-Vector2.ONE*.00001)/Plan.CELL_SIZE).floor()).max(first)
				for x in range(first.x,last.x+1):
					for z in range(first.y,last.y+1):
						var polygon: Array=cut(triangle,Vector2.LEFT,-x*Plan.CELL_SIZE); polygon=cut(polygon,Vector2.RIGHT,(x+1)*Plan.CELL_SIZE); polygon=cut(polygon,Vector2.UP,-z*Plan.CELL_SIZE); polygon=cut(polygon,Vector2.DOWN,(z+1)*Plan.CELL_SIZE)
						for half in 2:
							var diagonal: float=(x+z+1)*Plan.CELL_SIZE; var clipped: Array=cut(polygon,Vector2.ONE if half==0 else -Vector2.ONE,diagonal if half==0 else -diagonal)
							for index in range(1,clipped.size()-1):
								var face: Array=[clipped[0],clipped[index],clipped[index+1]]; var positions: Array[Vector3]=[]
								for vertex in face:
									var p: Vector3=vertex["p"]; p.y+=Plan.sample(data,Vector2(p.x,p.z),heights)["height"] if area.has_point(Vector2i(x,z)) else 0.0; positions.append(p-section.position)
								var normal: Vector3=(positions[2]-positions[0]).cross(positions[1]-positions[0]).normalized()
								if normal.is_zero_approx(): continue
								for vertex_index in 3: points.append(positions[vertex_index]); normals.append(normal); tints.append(face[vertex_index]["color"]); texcoords.append(face[vertex_index]["uv"]); collision.append(positions[vertex_index])
			if not points.is_empty():
				var arrays: Array=[]; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX]=points; arrays[Mesh.ARRAY_NORMAL]=normals; arrays[Mesh.ARRAY_COLOR]=tints; arrays[Mesh.ARRAY_TEX_UV]=texcoords; output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays); output.surface_set_material(output.get_surface_count()-1,child.mesh.surface_get_material(surface))
		child.mesh=output; child.transform=Transform3D.IDENTITY
	for child in section.get_children():
		if child is CollisionShape3D:
			var shape:=ConcavePolygonShape3D.new(); shape.set_faces(collision); child.shape=shape; child.transform=Transform3D.IDENTITY
