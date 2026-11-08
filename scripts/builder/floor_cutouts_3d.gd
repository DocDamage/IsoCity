extends RefCounted

# Subtract convex shaft footprints from triangles, interpolating every supported
# static-mesh attribute. Mesh resources from the asset library stay untouched.
static func blend(a: Dictionary,b: Dictionary,t: float) -> Dictionary:
	var result: Dictionary={}
	for key in a:
		result[key]=a[key].lerp(b[key],t) if key!="tangent_w" else a[key]
	return result

static func half_plane(polygon: Array,a: Vector2,b: Vector2,inside: bool) -> Array:
	var result: Array=[]
	if polygon.is_empty(): return result
	var edge: Vector2=b-a; var previous: Dictionary=polygon[-1]
	var distance: float=edge.cross(previous["plane"]-a)
	for current in polygon:
		var next: float=edge.cross(current["plane"]-a)
		var keep_previous: bool=distance>=-0.000001 if inside else distance<=0.000001
		var keep_current: bool=next>=-0.000001 if inside else next<=0.000001
		if keep_previous!=keep_current:
			result.append(blend(previous,current,clampf(distance/(distance-next),0,1)))
		if keep_current: result.append(current)
		previous=current; distance=next
	return result

static func subtract(polygon: Array,hole: PackedVector2Array) -> Array:
	var outside: Array=[]; var remainder: Array=polygon
	for index in hole.size():
		var a: Vector2=hole[index]; var b: Vector2=hole[(index+1)%hole.size()]
		var fragment: Array=half_plane(remainder,a,b,false)
		if fragment.size()>=3: outside.append(fragment)
		remainder=half_plane(remainder,a,b,true)
		if remainder.size()<3: break
	return outside

static func polygon(start: Vector2,end: Vector2,width: float,extension: float=0) -> PackedVector2Array:
	var direction: Vector2=(end-start).normalized(); var side:=Vector2(-direction.y,direction.x)*width*0.5
	if direction.is_zero_approx():
		direction=Vector2.DOWN; side=Vector2.LEFT*width*0.5
	var points:=PackedVector2Array([start-direction*extension+side,end+direction*extension+side,end+direction*extension-side,start-direction*extension-side])
	var area: float=0
	for index in points.size(): area+=points[index].cross(points[(index+1)%points.size()])
	if area<0: points.reverse()
	return points

static func holes(root: Dictionary,uid: String) -> Array:
	var result: Array=[]; var height: float=0
	for floor in root.get("floors",[]):
		if floor["uid"]==uid: height=float(floor["height"])
	var heights: Dictionary={"ground":0.0}
	for floor in root.get("floors",[]): heights[floor["uid"]]=float(floor["height"])
	for link in root.get("floor_links",[]):
		var start:=Vector2(link["start"][0],link["start"][1]); var end:=Vector2(link["end"][0],link["end"][1])
		if link["kind"]=="stairs" and link["upper"]==uid:
			# Leave room behind the first riser for the capsule's upward step sweep,
			# especially beneath the minimum-height storey's low ceiling.
			result.append(polygon(start,end,float(link["width"])+0.12,0.45))
		elif link["kind"]=="elevator" and height>=heights[link["lower"]] and height<=heights[link["upper"]]:
			result.append(polygon(start+Vector2(0,-float(link["width"])*0.5),start+Vector2(0,float(link["width"])*0.5),float(link["width"])+0.26,0.13))
	return result

static func vertex(arrays: Array,index: int,frame: Transform3D) -> Dictionary:
	var point: Vector3=arrays[Mesh.ARRAY_VERTEX][index]; var projected: Vector3=frame*point
	var result: Dictionary={"p":point,"plane":Vector2(projected.x,projected.z)}
	for entry in [[Mesh.ARRAY_NORMAL,"normal"],[Mesh.ARRAY_COLOR,"color"],[Mesh.ARRAY_TEX_UV,"uv"],[Mesh.ARRAY_TEX_UV2,"uv2"]]:
		if arrays[entry[0]]!=null and arrays[entry[0]].size()>index: result[entry[1]]=arrays[entry[0]][index]
	if arrays[Mesh.ARRAY_TANGENT]!=null and arrays[Mesh.ARRAY_TANGENT].size()>index*4+3:
		var values: PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT]
		result["tangent"]=Vector3(values[index*4],values[index*4+1],values[index*4+2]); result["tangent_w"]=values[index*4+3]
	return result

static func mesh(source: Mesh,frame: Transform3D,openings: Array) -> ArrayMesh:
	var result:=ArrayMesh.new()
	var surfaces:=PackedInt32Array()
	var bounds: AABB=frame*source.get_aabb(); var footprint:=Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z))
	var relevant: Array=[]
	for opening in openings:
		var low:=Vector2(INF,INF); var high:=Vector2(-INF,-INF)
		for point in opening: low=low.min(point); high=high.max(point)
		if footprint.intersects(Rect2(low,high-low),true): relevant.append(opening)
	if relevant.is_empty() and source is ArrayMesh: return source
	for surface in source.get_surface_count():
		var input: Array=source.surface_get_arrays(surface)
		var primitive: int=source.surface_get_primitive_type(surface) if source is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES
		if primitive!=Mesh.PRIMITIVE_TRIANGLES or relevant.is_empty():
			result.add_surface_from_arrays(primitive,input)
			surfaces.append(surface)
			result.surface_set_material(result.get_surface_count()-1,source.surface_get_material(surface)); continue
		var vertices:=PackedVector3Array(); var normals:=PackedVector3Array(); var colors:=PackedColorArray(); var uv:=PackedVector2Array(); var uv2:=PackedVector2Array(); var tangents:=PackedFloat32Array()
		var indices: PackedInt32Array=input[Mesh.ARRAY_INDEX] if input[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		var count: int=indices.size() if not indices.is_empty() else input[Mesh.ARRAY_VERTEX].size()
		for start in range(0,count-2,3):
			var triangle: Array=[]
			for offset in 3: triangle.append(vertex(input,indices[start+offset] if not indices.is_empty() else start+offset,frame))
			var fragments: Array=[triangle]
			for opening in relevant:
				var next: Array=[]
				for fragment in fragments: next.append_array(subtract(fragment,opening))
				fragments=next
			for fragment in fragments:
				for index in range(1,fragment.size()-1):
					var points: Array=[fragment[0],fragment[index],fragment[index+1]]
					if (points[1]["p"]-points[0]["p"]).cross(points[2]["p"]-points[0]["p"]).length_squared()<1e-14: continue
					for point in points:
						vertices.append(point["p"])
						if point.has("normal"): normals.append(point["normal"].normalized())
						if point.has("color"): colors.append(point["color"])
						if point.has("uv"): uv.append(point["uv"])
						if point.has("uv2"): uv2.append(point["uv2"])
						if point.has("tangent"):
							var tangent: Vector3=point["tangent"].normalized()
							tangents.append_array(PackedFloat32Array([tangent.x,tangent.y,tangent.z,point["tangent_w"]]))
		if vertices.is_empty(): continue
		var output: Array=[]; output.resize(Mesh.ARRAY_MAX); output[Mesh.ARRAY_VERTEX]=vertices
		if not normals.is_empty(): output[Mesh.ARRAY_NORMAL]=normals
		if not colors.is_empty(): output[Mesh.ARRAY_COLOR]=colors
		if not uv.is_empty(): output[Mesh.ARRAY_TEX_UV]=uv
		if not uv2.is_empty(): output[Mesh.ARRAY_TEX_UV2]=uv2
		if not tangents.is_empty(): output[Mesh.ARRAY_TANGENT]=tangents
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,output)
		surfaces.append(surface)
		result.surface_set_material(result.get_surface_count()-1,source.surface_get_material(surface))
	result.set_meta("floor_source_surfaces",surfaces)
	return result
