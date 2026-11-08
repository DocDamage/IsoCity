extends RefCounted
const Layers=preload("res://scripts/builder/layers.gd")
const CELL_SIZE: float=2
const MAX_AXIS: int=128
const MIN_CELL: int=-256
const MAX_CELL: int=256
const MIN_HEIGHT: float=-24
const MAX_HEIGHT: float=24
const MAX_VERTICES: int=16641
const MAX_WATER: int=16384
const WADING_DEPTH: float=.45
const WALKABLE_NORMAL: float=.694658 # cos(46 degrees)
const OPERATIONS: Array[String]=["raise","lower","flatten","smooth","water","drain","basin","reset"]
static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
static func integer(value: Variant) -> bool: return number(value) and floorf(float(value))==float(value)
static func color_valid(value: Variant) -> bool:
	if not value is String: return false
	var text: String=value.trim_prefix("#").to_lower()
	if not text.length() in [6,8]: return false
	for character in text:
		if not character in "0123456789abcdef": return false
	return true
static func settings(data: Dictionary) -> Dictionary:
	var raw: Dictionary=data.get("terrain",{}) if data.get("terrain",{}) is Dictionary else {}
	var bounds: Array=[-40,-40,80,80]
	if raw.get("bounds") is Array and raw["bounds"].size()==4:
		for index in 4:
			if number(raw["bounds"][index]): bounds[index]=floori(clampf(float(raw["bounds"][index]),MIN_CELL,MAX_CELL))
		bounds[2]=clampi(bounds[2],4,MAX_AXIS); bounds[3]=clampi(bounds[3],4,MAX_AXIS)
		bounds[0]=clampi(bounds[0],MIN_CELL,MAX_CELL-bounds[2]); bounds[1]=clampi(bounds[1],MIN_CELL,MAX_CELL-bounds[3])
	var result: Dictionary={"enabled":raw.get("enabled",false) if raw.get("enabled",false) is bool else false,"bounds":bounds,"land_color":raw.get("land_color","64805c") if color_valid(raw.get("land_color","64805c")) else "64805c","water_color":raw.get("water_color","398da8") if color_valid(raw.get("water_color","398da8")) else "398da8"}
	for field in ["protect_objects","protect_roads","protect_actors"]: result[field]=raw.get(field,true) if raw.get(field,true) is bool else true
	for field in ["connected_shores","connected_cliffs"]: result[field]=raw.get(field,false)==true
	return result
static func valid_settings(value: Variant) -> bool:
	if not value is Dictionary: return false
	for field in ["enabled","protect_objects","protect_roads","protect_actors","connected_shores","connected_cliffs"]:
		if value.has(field) and not value[field] is bool: return false
	for field in ["land_color","water_color"]:
		if value.has(field) and not color_valid(value[field]): return false
	if value.has("bounds"):
		if not value["bounds"] is Array or value["bounds"].size()!=4: return false
		var fixed: Array=settings({"terrain":value})["bounds"]
		for index in 4:
			if not integer(value["bounds"][index]) or float(value["bounds"][index])!=float(fixed[index]): return false
	return true
static func bounds(data: Dictionary) -> Rect2i:
	var raw: Array=settings(data)["bounds"]; return Rect2i(raw[0],raw[1],raw[2],raw[3])
static func vertex_inside(cell: Vector2i,area: Rect2i) -> bool:
	return cell.x>=area.position.x and cell.y>=area.position.y and cell.x<=area.end.x and cell.y<=area.end.y
static func key(cell: Vector2i) -> String: return str(cell.x)+":"+str(cell.y)
static func lookup(data: Dictionary,water: bool=false) -> Dictionary:
	var result: Dictionary={}
	for record in data.get("water_cells" if water else "terrain_vertices",[]): result[key(Vector2i(record["cell"][0],record["cell"][1]))]=record
	return result
static func valid_records(value: Variant,data: Dictionary,water: bool=false) -> bool:
	if not value is Array or value.size()>(MAX_WATER if water else MAX_VERTICES): return false
	var seen: Dictionary={}; var area: Rect2i=bounds(data); var field: String="level" if water else "height"
	for record in value:
		if not record is Dictionary or not record.get("cell") is Array or record["cell"].size()!=2: return false
		if not integer(record["cell"][0]) or not integer(record["cell"][1]): return false
		if absf(float(record["cell"][0]))>MAX_CELL or absf(float(record["cell"][1]))>MAX_CELL: return false
		var cell:=Vector2i(record["cell"][0],record["cell"][1]); var identity: String=key(cell)
		if seen.has(identity) or not (area.has_point(cell) if water else vertex_inside(cell,area)): return false
		if not number(record.get(field)) or record[field]<MIN_HEIGHT or record[field]>MAX_HEIGHT: return false
		seen[identity]=true
	return true
static func vertex(heights: Dictionary,cell: Vector2i) -> Vector3:
	return Vector3(cell.x*CELL_SIZE,heights.get(key(cell),{}).get("height",0),cell.y*CELL_SIZE)
static func triangles(data: Dictionary,cell: Vector2i,heights: Dictionary={}) -> Array[PackedVector3Array]:
	var result: Array[PackedVector3Array]=[]
	if not bounds(data).has_point(cell): return result
	if heights.is_empty(): heights=lookup(data)
	var a: Vector3=vertex(heights,cell); var b: Vector3=vertex(heights,cell+Vector2i.RIGHT); var c: Vector3=vertex(heights,cell+Vector2i.DOWN); var d: Vector3=vertex(heights,cell+Vector2i.ONE)
	result.append(PackedVector3Array([a,c,b])); result.append(PackedVector3Array([b,c,d])); return result
static func sample(data: Dictionary,point: Vector2,heights: Dictionary={}) -> Dictionary:
	if not point.is_finite(): return {"height":0.0,"normal":Vector3.UP,"inside":false}
	var area: Rect2i=bounds(data); var local: Vector2=point/CELL_SIZE
	if local.x<area.position.x or local.y<area.position.y or local.x>area.end.x or local.y>area.end.y: return {"height":0.0,"normal":Vector3.UP,"inside":false}
	var cell:=Vector2i(clampi(floori(local.x),area.position.x,area.end.x-1),clampi(floori(local.y),area.position.y,area.end.y-1)); local-=Vector2(cell)
	var faces: Array[PackedVector3Array]=triangles(data,cell,heights); var face: PackedVector3Array=faces[0 if local.x+local.y<=1 else 1]
	var normal: Vector3=(face[1]-face[0]).cross(face[2]-face[0]).normalized()
	var height: float=face[0].y-(normal.x*(point.x-face[0].x)+normal.z*(point.y-face[0].z))/normal.y
	return {"height":height,"normal":normal,"inside":true}
static func water_level(data: Dictionary,point: Vector2,heights: Dictionary={},waters: Dictionary={}) -> Variant:
	if not settings(data)["enabled"] or not point.is_finite(): return null
	var cell:=Vector2i((point/CELL_SIZE).floor())
	if not bounds(data).has_point(cell): return null
	if waters.is_empty(): waters=lookup(data,true)
	if not waters.has(key(cell)): return null
	var level: float=waters[key(cell)]["level"]
	return level if sample(data,point,heights)["height"]<level-.001 else null
static func clip_water(face: PackedVector3Array,level: float) -> PackedVector3Array:
	var result:=PackedVector3Array()
	if not Array(face).any(func(point: Vector3):return point.y<level-.001): return result
	var previous: Vector3=face[-1]; var was_inside: bool=previous.y<=level
	for current in face:
		var inside: bool=current.y<=level
		if inside!=was_inside:
			var at: Vector3=previous.lerp(current,(level-previous.y)/(current.y-previous.y)); result.append(Vector3(at.x,level,at.z))
		if inside: result.append(Vector3(current.x,level,current.z))
		previous=current; was_inside=inside
	var unique:=PackedVector3Array()
	for point in result:
		if unique.is_empty() or point.distance_squared_to(unique[-1])>.00000001: unique.append(point)
	if unique.size()>1 and unique[0].distance_squared_to(unique[-1])<.00000001: unique.resize(unique.size()-1)
	var area: float=0
	for index in unique.size(): area+=Vector2(unique[index].x,unique[index].z).cross(Vector2(unique[(index+1)%unique.size()].x,unique[(index+1)%unique.size()].z))
	return unique if unique.size()>=3 and absf(area)>.000001 else PackedVector3Array()
static func water_polygons(data: Dictionary,cell: Vector2i,heights: Dictionary={},waters: Dictionary={}) -> Array[PackedVector3Array]:
	var result: Array[PackedVector3Array]=[]
	if not settings(data)["enabled"] or not bounds(data).has_point(cell): return result
	if waters.is_empty(): waters=lookup(data,true)
	if not waters.has(key(cell)): return result
	for face in triangles(data,cell,heights):
		var polygon: PackedVector3Array=clip_water(face,waters[key(cell)]["level"])
		if not polygon.is_empty(): result.append(polygon)
	return result
static func failure(reason: String) -> Dictionary: return {"ok":false,"reason":reason,"changed":0}
static func project_2d(point: Vector3) -> Vector2:
	return Vector2((point.x-point.z)*8,(point.x+point.z)*4-point.y*8)
static func raycast(data: Dictionary,origin: Vector3,direction: Vector3,max_distance: float=1000,include_water: bool=false) -> Dictionary:
	if not origin.is_finite() or not direction.is_finite() or direction.length_squared()<.00000001 or not is_finite(max_distance) or max_distance<=0 or max_distance>10000: return failure("The terrain ray is invalid.")
	direction=(direction/maxf(absf(direction.x),maxf(absf(direction.y),absf(direction.z)))).normalized()
	var area: Rect2i=bounds(data); var low:=Vector3(area.position.x*CELL_SIZE,MIN_HEIGHT,area.position.y*CELL_SIZE); var high:=Vector3(area.end.x*CELL_SIZE,MAX_HEIGHT,area.end.y*CELL_SIZE); var start: float=0; var finish: float=max_distance
	for axis in 3:
		if absf(direction[axis])<.00000001:
			if origin[axis]<low[axis] or origin[axis]>high[axis]: return failure("The ray misses the terrain boundary.")
		else:
			var a: float=(low[axis]-origin[axis])/direction[axis]; var b: float=(high[axis]-origin[axis])/direction[axis]
			start=maxf(start,minf(a,b)); finish=minf(finish,maxf(a,b))
	if start>finish: return failure("The ray misses the terrain boundary.")
	var entry: Vector3=origin+direction*start; var cell:=Vector2i(clampi(floori(entry.x/CELL_SIZE),area.position.x,area.end.x-1),clampi(floori(entry.z/CELL_SIZE),area.position.y,area.end.y-1))
	var step:=Vector2i(int(signf(direction.x)),int(signf(direction.z))); var next_x: float=INF; var next_y: float=INF; var delta_x: float=INF; var delta_y: float=INF
	if step.x!=0: next_x=((cell.x+(1 if step.x>0 else 0))*CELL_SIZE-origin.x)/direction.x; delta_x=CELL_SIZE/absf(direction.x)
	if step.y!=0: next_y=((cell.y+(1 if step.y>0 else 0))*CELL_SIZE-origin.z)/direction.z; delta_y=CELL_SIZE/absf(direction.z)
	var heights: Dictionary=lookup(data); var waters: Dictionary=lookup(data,true) if include_water else {}; var best: Dictionary={}
	for visit in MAX_AXIS*2+4:
		var nearest: float=INF; var end: float=minf(finish,minf(next_x,next_y)); var faces: Array[PackedVector3Array]=triangles(data,cell,heights)
		for index in faces.size():
			var face: PackedVector3Array=faces[index]; var normal: Vector3=(face[1]-face[0]).cross(face[2]-face[0]).normalized(); var denominator: float=normal.dot(direction)
			if denominator>=-.00000001: continue
			var time: float=normal.dot(face[0]-origin)/denominator
			if time<start-.00001 or time>end+.00001 or time>=nearest: continue
			var point: Vector3=origin+direction*time; var local:=Vector2(point.x,point.z)/CELL_SIZE-Vector2(cell)
			if local.x<-.00001 or local.y<-.00001 or local.x>1.00001 or local.y>1.00001: continue
			if index==0 and local.x+local.y>1.00001 or index==1 and local.x+local.y<.99999: continue
			nearest=time; best={"ok":true,"point":point,"normal":normal,"kind":"land","cell":cell,"distance":time}
		if include_water and direction.y<-.00000001 and waters.has(key(cell)):
			var time: float=(float(waters[key(cell)]["level"])-origin.y)/direction.y
			if time>=start-.00001 and time<=end+.00001 and time<=nearest:
				var point: Vector3=origin+direction*time
				if sample(data,Vector2(point.x,point.z),heights)["height"]<point.y-.001: best={"ok":true,"point":point,"normal":Vector3.UP,"kind":"water","cell":cell,"distance":time}
		if not best.is_empty(): return best
		if end>=finish-.000001: break
		var cross_x: bool=next_x<=next_y+.000001; var cross_y: bool=next_y<=next_x+.000001
		start=end
		if cross_x: cell.x+=step.x; next_x+=delta_x
		if cross_y: cell.y+=step.y; next_y+=delta_y
		if not area.has_point(cell): break
	return failure("No front-facing terrain surface lies along the ray.")
static func pick_2d(data: Dictionary,pixel: Vector2,include_water: bool=false,heights: Dictionary={},waters: Dictionary={}) -> Dictionary:
	if not pixel.is_finite(): return failure("The terrain pointer is invalid.")
	var raw:=Vector2(pixel.x/16+pixel.y/8,pixel.y/8-pixel.x/16); var area: Rect2i=bounds(data)
	if raw.x+MAX_HEIGHT<area.position.x*CELL_SIZE or raw.y+MAX_HEIGHT<area.position.y*CELL_SIZE or raw.x+MIN_HEIGHT>area.end.x*CELL_SIZE or raw.y+MIN_HEIGHT>area.end.y*CELL_SIZE: return failure("The pointer is outside the terrain boundary.")
	var first:=Vector2i(((raw+Vector2.ONE*MIN_HEIGHT)/CELL_SIZE).floor()).max(area.position); var last:=Vector2i(((raw+Vector2.ONE*MAX_HEIGHT)/CELL_SIZE).floor()).min(area.end-Vector2i.ONE)
	if heights.is_empty(): heights=lookup(data)
	if include_water and waters.is_empty(): waters=lookup(data,true)
	var best: Dictionary={}; var depth: float=-INF; var diagonal: float=raw.x-raw.y
	for x in range(first.x,last.x+1):
		for y in range(first.y,last.y+1):
			if diagonal<(x-y-1)*CELL_SIZE-.0001 or diagonal>(x-y+1)*CELL_SIZE+.0001: continue
			var cell:=Vector2i(x,y); var faces: Array=triangles(data,cell,heights); var land_count: int=faces.size()
			if include_water:
				for polygon in water_polygons(data,cell,heights,waters):
					for index in range(1,polygon.size()-1): faces.append(PackedVector3Array([polygon[0],polygon[index],polygon[index+1]]))
			for index in faces.size():
				var face: PackedVector3Array=faces[index]; var a: Vector2=project_2d(face[0]); var b: Vector2=project_2d(face[1])-a; var c: Vector2=project_2d(face[2])-a; var q: Vector2=pixel-a; var denominator: float=b.cross(c)
				if absf(denominator)<.000001: continue
				var u: float=q.cross(c)/denominator; var v: float=b.cross(q)/denominator
				if u<-.00001 or v<-.00001 or u+v>1.00001: continue
				var point: Vector3=face[0]+(face[1]-face[0])*u+(face[2]-face[0])*v
				if point.y>depth+.00001 or is_equal_approx(point.y,depth) and index>=land_count:
					depth=point.y; best={"ok":true,"point":Vector2(point.x,point.z),"height":point.y,"cell":cell,"kind":"land" if index<land_count else "water"}
	return best if not best.is_empty() else failure("No visible terrain surface lies under the pointer.")
static func brush(data: Dictionary,operation: String,center: Vector2,radius: float,amount: float,target: float=0,protected: Array[Rect2]=[]) -> Dictionary:
	if not valid_settings(data.get("terrain",{})) or not valid_records(data.get("terrain_vertices",[]),data) or not valid_records(data.get("water_cells",[]),data,true): return failure("Repair unreadable terrain before sculpting.")
	if not settings(data)["enabled"]: return failure("Enable terrain editing first.")
	if not Layers.shown(data,"Ground") or Layers.locked(data,"Ground"): return failure("Show and unlock Ground before sculpting.")
	if not operation in OPERATIONS or not center.is_finite() or not is_finite(radius) or radius<1 or radius>24 or not is_finite(amount) or amount<.01 or amount>8 or not is_finite(target) or target<MIN_HEIGHT or target>MAX_HEIGHT: return failure("Terrain brush values are outside their supported ranges.")
	var area: Rect2i=bounds(data); var heights: Dictionary=lookup(data); var waters: Dictionary=lookup(data,true); var next: Dictionary=heights.duplicate(true); var wet: Dictionary=waters.duplicate(true); var changed: int=0
	if center.x+radius<area.position.x*CELL_SIZE or center.y+radius<area.position.y*CELL_SIZE or center.x-radius>area.end.x*CELL_SIZE or center.y-radius>area.end.y*CELL_SIZE: return failure("The brush is outside the terrain boundary.")
	var first:=Vector2i(((center-Vector2.ONE*radius)/CELL_SIZE).floor()).max(area.position); var last:=Vector2i(((center+Vector2.ONE*radius)/CELL_SIZE).ceil()).min(area.end)
	if operation in ["raise","lower","flatten","smooth","basin","reset"]:
		for x in range(first.x,last.x+1):
			for y in range(first.y,last.y+1):
				var cell:=Vector2i(x,y); var distance: float=(Vector2(cell)*CELL_SIZE).distance_to(center)
				if distance>=radius: continue
				if protected.any(func(box: Rect2):return box.abs().grow(CELL_SIZE).has_point(Vector2(cell)*CELL_SIZE)): continue
				var weight: float=1-distance/radius; weight=weight*weight*(3-2*weight)
				var id: String=key(cell); var old: float=heights.get(id,{}).get("height",0); var value: float=old
				match operation:
					"raise": value+=amount*weight
					"lower": value-=amount*weight
					"flatten": value=lerpf(old,target,minf(1,amount)*weight)
					"basin": value=lerpf(old,minf(old,target-amount),weight)
					"reset": value=0
					"smooth":
						var total: float=old; var count: int=1
						for step in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
							if vertex_inside(cell+step,area): total+=heights.get(key(cell+step),{}).get("height",0); count+=1
						value=lerpf(old,total/count,minf(1,amount)*weight)
				value=snappedf(clampf(value,MIN_HEIGHT,MAX_HEIGHT),.001)
				if is_equal_approx(value,old): continue
				changed+=1
				if is_zero_approx(value) and next.get(id,{}).keys().all(func(field: String):return field in ["cell","height"]): next.erase(id)
				else:
					var record: Dictionary=next.get(id,{"cell":[x,y]}).duplicate(true); record["height"]=value; next[id]=record
	if operation in ["water","drain","basin","reset"]:
		for x in range(first.x,mini(last.x,area.end.x-1)+1):
			for y in range(first.y,mini(last.y,area.end.y-1)+1):
				var cell:=Vector2i(x,y)
				var closest: Vector2=center.clamp(Vector2(cell)*CELL_SIZE,Vector2(cell+Vector2i.ONE)*CELL_SIZE)
				if closest.distance_to(center)>radius: continue
				if protected.any(func(box: Rect2):return box.abs().grow(.1).intersects(Rect2(Vector2(cell)*CELL_SIZE,Vector2.ONE*CELL_SIZE))): continue
				var id: String=key(cell)
				if operation in ["drain","reset"]:
					if wet.has(id): wet.erase(id); changed+=1
				elif not wet.has(id) or wet[id]["level"]!=target:
					var record: Dictionary=wet.get(id,{"cell":[x,y]}).duplicate(true); record["level"]=target; wet[id]=record; changed+=1
	var result: Dictionary=data.duplicate(false)
	if changed:
		result["terrain_vertices"]=next.values(); result["water_cells"]=wet.values()
	return {"ok":true,"data":result,"changed":changed,"reason":"Sculpted %d terrain/water samples."%changed}
