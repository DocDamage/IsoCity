extends RefCounted
const Plan=preload("res://scripts/builder/terrain_plan.gd")
const MAX_GRADE_NORMAL: float=.939693 # 20 degrees, for ordinary city roads.
static var cache: Dictionary={}
static func reason(data: Dictionary,center: Vector2,heights: Dictionary,waters: Dictionary) -> String:
	if not Plan.settings(data)["enabled"]: return ""
	var area: Rect2i=Plan.bounds(data); var rect:=Rect2(Vector2(area.position)*Plan.CELL_SIZE,Vector2(area.size)*Plan.CELL_SIZE)
	if not rect.grow(.1).intersects(Rect2(center-Vector2.ONE*4,Vector2.ONE*8)): return ""
	var first:=Vector2i(((center-Vector2.ONE*4)/Plan.CELL_SIZE).floor()); var last:=Vector2i(((center+Vector2.ONE*4)/Plan.CELL_SIZE).ceil())+Vector2i.ONE; var samples: Array=[]
	for x in range(first.x,last.x+1):
		for z in range(first.y,last.y+1):
			var id: String=Plan.key(Vector2i(x,z)); samples.append([heights.get(id,{}).get("height",0),waters.get(id,{}).get("level",null)])
	var stamp: int=hash([area,center,samples])
	if cache.has(stamp): return cache[stamp]
	var result: String=inspect(data,center,heights,waters)
	if cache.size()>=8192: cache.clear()
	cache[stamp]=result; return result
static func inspect(data: Dictionary,center: Vector2,heights: Dictionary,waters: Dictionary) -> String:
	# Check the full section, including lane transitions and sidewalks.
	for x in range(-4,5):
		for z in range(-4,5):
			var point: Vector2=center+Vector2(x,z); var sample: Dictionary=Plan.sample(data,point,heights)
			if sample["normal"].y<MAX_GRADE_NORMAL: return "Road bank is too steep · smooth or flatten the section."
			var water: Dictionary=waters.get(Plan.key(Vector2i((point/Plan.CELL_SIZE).floor())),{})
			if not water.is_empty() and float(water["level"])-sample["height"]>.26: return "Road is flooded · drain water or raise the road bed."
			for step in [Vector2(.05,0),Vector2(0,.05)]:
				if absf(Plan.sample(data,point+step,heights)["height"]-sample["height"])>.37: return "Road crosses an abrupt terrain edge · flatten its boundary."
	return ""
