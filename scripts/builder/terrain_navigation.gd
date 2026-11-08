extends RefCounted
const Plan=preload("res://scripts/builder/terrain_plan.gd")
# Whole unsafe cells form conservative navigation obstacles. Merge adjacent
# cells in each row so a large pond does not add thousands of route obstacles.
static func obstacles(data: Dictionary,citizen_coordinates: bool=false) -> Array[Rect2]:
	var result: Array[Rect2]=[]
	if not Plan.settings(data)["enabled"] or not Plan.Layers.shown(data,"Ground"): return result
	var heights: Dictionary=Plan.lookup(data); var waters: Dictionary=Plan.lookup(data,true); var area: Rect2i=Plan.bounds(data)
	for z in range(area.position.y,area.end.y):
		var start: int=area.position.x; var running: bool=false
		for x in range(area.position.x,area.end.x+1):
			var unsafe: bool=false
			if x<area.end.x:
				var cell:=Vector2i(x,z); var a: Vector3=Plan.vertex(heights,cell); var b: Vector3=Plan.vertex(heights,cell+Vector2i.RIGHT); var c: Vector3=Plan.vertex(heights,cell+Vector2i.DOWN); var d: Vector3=Plan.vertex(heights,cell+Vector2i.ONE)
				var first: Vector3=(c-a).cross(b-a).normalized(); var second: Vector3=(c-b).cross(d-b).normalized()
				unsafe=minf(first.y,second.y)<Plan.WALKABLE_NORMAL
				var water: Dictionary=waters.get(Plan.key(cell),{})
				if not water.is_empty(): unsafe=unsafe or float(water["level"])-minf(minf(a.y,b.y),minf(c.y,d.y))>Plan.WADING_DEPTH
			if unsafe and not running: start=x; running=true
			elif not unsafe and running:
				var rect:=Rect2(start*Plan.CELL_SIZE,z*Plan.CELL_SIZE,(x-start)*Plan.CELL_SIZE,Plan.CELL_SIZE)
				if citizen_coordinates:
					var low:=Vector2(INF,INF); var high:=Vector2(-INF,-INF)
					for point in [rect.position,rect.end,Vector2(rect.position.x,rect.end.y),Vector2(rect.end.x,rect.position.y)]:
						var projected:=Vector2((point.x-point.y)*.5,(point.x+point.y)*.5); low=low.min(projected); high=high.max(projected)
					rect=Rect2(low,high-low)
				result.append(rect); running=false
	return result
