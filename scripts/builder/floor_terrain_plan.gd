extends RefCounted
const Cut=preload("res://scripts/builder/floor_cutouts_3d.gd")

static func passages(root: Dictionary,uid: String) -> Array:
	var result: Array=Cut.holes(root,uid)
	for link in root.get("floor_links",[]):
		if link["kind"]=="stairs" and link["lower"]==uid:
			result.append(Cut.polygon(Vector2(link["start"][0],link["start"][1]),Vector2(link["end"][0],link["end"][1]),float(link["width"])+.12,.45))
	# Floor connections retain the native isometric room grid. Terrain's
	# horizontal world units use half that spacing in the 2D projection.
	if root.get("mode")=="2d":
		for index in result.size():
			var polygon: PackedVector2Array=result[index].duplicate()
			for point in polygon.size(): polygon[point]*=2
			result[index]=polygon
	return result

static func contains(regions: Array,point: Vector2) -> bool:
	for polygon in regions:
		if Geometry2D.is_point_in_polygon(point,polygon): return true
	return false

static func fragments(points: Variant,holes: Array) -> Array:
	if holes.is_empty(): return [points]
	var polygon: Array=[]
	for point in points: polygon.append({"p":point,"plane":Vector2(point.x,point.z)})
	var area:=Rect2(polygon[0]["plane"],Vector2.ZERO)
	for vertex in polygon: area=area.expand(vertex["plane"])
	var pieces: Array=[polygon]
	for hole in holes:
		var bounds:=Rect2(hole[0],Vector2.ZERO)
		for point in hole: bounds=bounds.expand(point)
		if not area.intersects(bounds,true): continue
		var next: Array=[]
		for piece in pieces: next.append_array(Cut.subtract(piece,hole))
		pieces=next
	var result: Array=[]
	for piece in pieces:
		var vertices: Array=[]
		for vertex in piece: vertices.append(vertex["p"])
		var area_sum: float=0
		for index in vertices.size(): area_sum+=Vector2(vertices[index].x,vertices[index].z).cross(Vector2(vertices[(index+1)%vertices.size()].x,vertices[(index+1)%vertices.size()].z))
		if vertices.size()>=3 and absf(area_sum)>.000001: result.append(vertices)
	return result

static func landing_allowed(helper: Node,point: Variant) -> bool:
	if not preload("res://scripts/builder/layers.gd").shown(helper.data,"Ground"): return false
	if not helper.enabled: return true
	return helper.safe_position(point) and absf(helper.sample_at(helper.metric(point))["height"])<=.35
