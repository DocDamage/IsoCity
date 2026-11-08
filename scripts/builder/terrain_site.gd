extends RefCounted
const Terrain=preload("res://scripts/builder/terrain_plan.gd")
static func clip(polygon: PackedVector3Array,axis: Vector2,limit: float) -> PackedVector3Array:
	var result:=PackedVector3Array()
	if polygon.is_empty(): return result
	var previous: Vector3=polygon[-1]; var distance: float=axis.dot(Vector2(previous.x,previous.z))-limit
	for current in polygon:
		var next: float=axis.dot(Vector2(current.x,current.z))-limit
		if (distance<=.000001)!=(next<=.000001): result.append(previous.lerp(current,distance/(distance-next)))
		if next<=.000001: result.append(current)
		previous=current; distance=next
	return result
static func foundation(data: Dictionary,rect: Rect2,heights: Dictionary={},waters: Dictionary={}) -> Dictionary:
	if not Terrain.settings(data)["enabled"]: return {"ok":true,"height":0.0,"reason":""}
	if heights.is_empty(): heights=Terrain.lookup(data)
	if waters.is_empty(): waters=Terrain.lookup(data,true)
	var low: float=INF; var high: float=-INF; var first:=Vector2i((rect.position/2).floor()); var last:=Vector2i((rect.end/2).ceil()); var area: Rect2i=Terrain.bounds(data)
	for x in range(first.x,last.x):
		for z in range(first.y,last.y):
			var cell:=Vector2i(x,z); var faces: Array[PackedVector3Array]=Terrain.triangles(data,cell,heights)
			if not area.has_point(cell): faces=[PackedVector3Array([Vector3(x*2,0,z*2),Vector3(x*2,0,z*2+2),Vector3(x*2+2,0,z*2)]),PackedVector3Array([Vector3(x*2+2,0,z*2),Vector3(x*2,0,z*2+2),Vector3(x*2+2,0,z*2+2)])]
			for face in faces:
				var polygon: PackedVector3Array=clip(face,Vector2.LEFT,-rect.position.x); polygon=clip(polygon,Vector2.RIGHT,rect.end.x); polygon=clip(polygon,Vector2.UP,-rect.position.y); polygon=clip(polygon,Vector2.DOWN,rect.end.y)
				for point in polygon:
					low=minf(low,point.y); high=maxf(high,point.y)
					if waters.has(Terrain.key(cell)) and float(waters[Terrain.key(cell)]["level"])-point.y>.05: return {"ok":false,"height":high,"reason":"Drain water beneath the building footprint before development."}
					if high-low>.35: return {"ok":false,"height":high,"reason":"Smooth or flatten the building footprint before development."}
	return {"ok":true,"height":high if is_finite(high) else 0.0,"reason":""}
static func signature(data: Dictionary,rect: Rect2,heights: Dictionary) -> int:
	if not Terrain.settings(data)["enabled"]: return 0
	var first:=Vector2i((rect.position/2).floor()); var last:=Vector2i((rect.end/2).ceil()); var samples: Array=[]
	for x in range(first.x,last.x+1):
		for z in range(first.y,last.y+1): samples.append(heights.get(Terrain.key(Vector2i(x,z)),{}).get("height",0))
	return hash([Terrain.bounds(data),rect,samples])
