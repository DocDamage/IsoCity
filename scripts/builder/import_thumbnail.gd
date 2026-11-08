extends RefCounted
# A small software rasterizer also works when Studio runs without a GPU.
const SIZE=192
static func sprite(image: Image) -> Image:
	var copy: Image=image.duplicate(); var factor: float=minf(176.0/copy.get_width(),176.0/copy.get_height()); copy.resize(maxi(1,roundi(copy.get_width()*factor)),maxi(1,roundi(copy.get_height()*factor)),Image.INTERPOLATE_NEAREST)
	var result:=Image.create_empty(SIZE,SIZE,false,Image.FORMAT_RGBA8); result.fill(Color.TRANSPARENT); result.blit_rect(copy,Rect2i(Vector2i.ZERO,copy.get_size()),(Vector2i(SIZE,SIZE)-copy.get_size())/2); return result
static func collect(node: Node3D,parent: Transform3D,triangles: Array) -> void:
	var transform: Transform3D=parent*node.transform
	if node is MeshInstance3D and node.mesh:
		for surface in node.mesh.get_surface_count():
			if node.mesh.surface_get_primitive_type(surface)!=Mesh.PRIMITIVE_TRIANGLES: continue
			var arrays: Array=node.mesh.surface_get_arrays(surface); var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]; var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			var material: Material=node.material_override if node.material_override else node.get_active_material(surface)
			var color:=Color(.72,.78,.85)
			if material is BaseMaterial3D: color=material.albedo_color
			var image: Image
			if material is BaseMaterial3D and material.albedo_texture:
				image=material.albedo_texture.get_image()
				if image and image.is_compressed(): image.decompress()
			var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
			var total: int=indices.size() if not indices.is_empty() else vertices.size()
			for face in range(0,total-2,3):
				if triangles.size()>=100000: return
				var points: Array[Vector3]=[]; var coordinates: Array[Vector2]=[]
				for corner in 3:
					var index: int=indices[face+corner] if not indices.is_empty() else face+corner; points.append(transform*vertices[index])
					if uv.size()==vertices.size(): coordinates.append(uv[index])
				triangles.append({"points":points,"color":color,"image":image,"uv":coordinates})
	for child in node.get_children():
		if child is Node3D: collect(child,transform,triangles)
static func projected(point: Vector3) -> Vector3:
	return Vector3((point.x-point.z)*.70710678,-point.y*.81649658+(point.x+point.z)*.40824829,(point.x+point.y+point.z)*.57735027)
static func edge(a: Vector2,b: Vector2,p: Vector2) -> float: return (p.x-a.x)*(b.y-a.y)-(p.y-a.y)*(b.x-a.x)
static func model(root: Node3D) -> Image:
	var triangles: Array=[]; collect(root,Transform3D.IDENTITY,triangles)
	var low:=Vector2(INF,INF); var high:=Vector2(-INF,-INF)
	for triangle in triangles:
		for point in triangle["points"]:
			var p: Vector3=projected(point); low=low.min(Vector2(p.x,p.y)); high=high.max(Vector2(p.x,p.y))
	var result:=Image.create_empty(SIZE,SIZE,false,Image.FORMAT_RGBA8); result.fill(Color.TRANSPARENT)
	if triangles.is_empty(): return result
	var extent: Vector2=high-low; var factor: float=176.0/maxf(.001,maxf(extent.x,extent.y)); var offset: Vector2=Vector2.ONE*SIZE*.5-(low+high)*.5*factor
	var depths:=PackedFloat32Array(); depths.resize(SIZE*SIZE); depths.fill(-INF)
	for triangle in triangles:
		var points: Array[Vector3]=triangle["points"]; var a: Vector3=projected(points[0]); var b: Vector3=projected(points[1]); var c: Vector3=projected(points[2]); var pa:=Vector2(a.x,a.y)*factor+offset; var pb:=Vector2(b.x,b.y)*factor+offset; var pc:=Vector2(c.x,c.y)*factor+offset
		var area: float=edge(pa,pb,pc)
		if absf(area)<.001: continue
		var start: Vector2i=Vector2i((pa.min(pb).min(pc)).floor()).max(Vector2i.ZERO); var end: Vector2i=Vector2i((pa.max(pb).max(pc)).ceil()).min(Vector2i(SIZE-1,SIZE-1))
		var normal: Vector3=(points[1]-points[0]).cross(points[2]-points[0]).normalized(); var shade: float=.4+.6*absf(normal.dot(Vector3(-.4,.8,.5).normalized())); var color: Color=triangle["color"]; color=Color(color.r*shade,color.g*shade,color.b*shade,color.a)
		for y in range(start.y,end.y+1):
			for x in range(start.x,end.x+1):
				var p:=Vector2(x+.5,y+.5); var u: float=edge(pb,pc,p)/area; var v: float=edge(pc,pa,p)/area; var w: float=1-u-v
				if u<0 or v<0 or w<0: continue
				var depth: float=a.z*u+b.z*v+c.z*w; var index: int=y*SIZE+x
				if depth<=depths[index] or color.a<=.01: continue
				var pixel: Color=color
				if triangle["image"] and triangle["uv"].size()==3:
					var image: Image=triangle["image"]; var uv: Vector2=triangle["uv"][0]*u+triangle["uv"][1]*v+triangle["uv"][2]*w
					pixel*=image.get_pixel(clampi(int(fposmod(uv.x,1.0)*image.get_width()),0,image.get_width()-1),clampi(int(fposmod(uv.y,1.0)*image.get_height()),0,image.get_height()-1))
				if pixel.a<=.01: continue
				depths[index]=depth; result.set_pixel(x,y,pixel)
	return result
static func make(source: Dictionary,config: Dictionary) -> Image:
	if source["mode"]=="2d": return sprite(source["image"])
	var root: Node3D=preload("res://scripts/builder/asset_import_plan.gd").model_scene(source,config); var image: Image=model(root); root.free(); return image
