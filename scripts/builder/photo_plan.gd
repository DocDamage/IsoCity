extends RefCounted
const MAX_BOOKMARKS: int=32
const MAX_PATHS: int=8
const MAX_SAMPLES: int=1800
const MAX_SECONDS: float=180
static func defaults() -> Dictionary:
	return {"dof_enabled":false,"focus_distance":10.0,"focus_range":4.0,"blur":.15,"focus_band":.55,"band_width":.3,"hide_avatar":false,"move_speed":8.0,"bookmarks":[],"paths":[]}
static func number(value: Variant,low: float,high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value>=low and value<=high
static func vector(value: Variant,size: int,limit: float) -> bool:
	if not value is Array or value.size()!=size: return false
	for n in value:
		if not number(n,-limit,limit): return false
	return true
static func settings(data: Dictionary) -> Dictionary:
	var result: Dictionary=defaults(); var raw: Variant=data.get("photo",{})
	if raw is Dictionary:
		for key in result:
			if raw.has(key) and not key in ["bookmarks","paths"] and valid({key:raw[key]},data.get("mode","2d")): result[key]=raw[key]
		for key in ["bookmarks","paths"]:
			if raw.has(key) and valid({key:raw[key]},data.get("mode","2d")): result[key]=raw[key]
	return result
static func view_valid(value: Variant,mode: String) -> bool:
	if not value is Dictionary or not vector(value.get("position"),2 if mode=="2d" else 3,100000): return false
	if mode=="2d":
		if not vector(value.get("zoom"),2,16): return false
		if value.has("frame_height") and not number(value["frame_height"],1,16384): return false
		for n in value["zoom"]:
			if n<.1: return false
		if not number(value.get("rotation",0),-TAU*2,TAU*2): return false
	else:
		if not vector(value.get("rotation"),3,TAU*2) or not number(value.get("projection"),0,1) or floorf(float(value["projection"]))!=float(value["projection"]): return false
		if not number(value.get("fov"),10,140) or not number(value.get("size"),1,500): return false
	for key in ["dof_enabled","focus_distance","focus_range","blur","focus_band","band_width","hide_avatar","move_speed"]:
		if value.has(key) and not valid({key:value[key]},mode): return false
	return true
static func entry_valid(entry: Variant,mode: String,path: bool=false) -> bool:
	if not entry is Dictionary or not preload("res://scripts/builder/floor_plan.gd").identity(entry.get("uid")): return false
	if not entry.get("name") is String or entry["name"].is_empty() or entry["name"].length()>120: return false
	if not path: return view_valid(entry.get("view"),mode)
	var samples: Variant=entry.get("samples")
	if not samples is Array or samples.size()<2 or samples.size()>MAX_SAMPLES: return false
	var previous: float=-1
	for sample in samples:
		if not sample is Dictionary or not number(sample.get("time"),0,MAX_SECONDS) or float(sample["time"])<=previous or not view_valid(sample.get("view"),mode): return false
		if previous<0 and not is_zero_approx(float(sample["time"])): return false
		previous=sample["time"]
	return true
static func valid(raw: Variant,mode: String) -> bool:
	if not raw is Dictionary: return false
	for key in ["dof_enabled","hide_avatar"]:
		if raw.has(key) and not raw[key] is bool: return false
	for spec in [["focus_distance",.1,500],["focus_range",.1,100],["blur",0,1],["focus_band",0,1],["band_width",.05,1],["move_speed",.5,40]]:
		if raw.has(spec[0]) and not number(raw[spec[0]],spec[1],spec[2]): return false
	for key in ["bookmarks","paths"]:
		if not raw.has(key): continue
		if not raw[key] is Array or raw[key].size()>(MAX_BOOKMARKS if key=="bookmarks" else MAX_PATHS): return false
		var seen: Dictionary={}
		for entry in raw[key]:
			if not entry_valid(entry,mode,key=="paths") or seen.has(entry["uid"]): return false
			seen[entry["uid"]]=true
	return true
static func blend(a: Dictionary,b: Dictionary,weight: float,mode: String) -> Dictionary:
	var result: Dictionary=a.duplicate(true); var t: float=clampf(weight,0,1)
	for key in ["focus_distance","focus_range","blur","focus_band","band_width"]: result[key]=lerpf(a.get(key,defaults()[key]),b.get(key,defaults()[key]),t)
	for index in result["position"].size(): result["position"][index]=lerpf(a["position"][index],b["position"][index],t)
	if mode=="2d":
		for index in 2: result["zoom"][index]=lerpf(a["zoom"][index],b["zoom"][index],t)
		if a.has("frame_height") and b.has("frame_height"): result["frame_height"]=lerpf(a["frame_height"],b["frame_height"],t)
		result["rotation"]=lerp_angle(a.get("rotation",0),b.get("rotation",0),t)
	else:
		var qa: Quaternion=Basis.from_euler(Vector3(a["rotation"][0],a["rotation"][1],a["rotation"][2])).get_rotation_quaternion(); var qb: Quaternion=Basis.from_euler(Vector3(b["rotation"][0],b["rotation"][1],b["rotation"][2])).get_rotation_quaternion(); var angles: Vector3=qa.slerp(qb,t).get_euler()
		result["rotation"]=[angles.x,angles.y,angles.z]; result["fov"]=lerpf(a["fov"],b["fov"],t); result["size"]=lerpf(a["size"],b["size"],t)
	if t>=1: result["projection"]=b.get("projection",0); result["dof_enabled"]=b.get("dof_enabled",false); result["hide_avatar"]=b.get("hide_avatar",false)
	return result
static func sample(samples: Array,time: float,mode: String) -> Dictionary:
	if samples.is_empty(): return {}
	if time<=0: return samples[0]["view"].duplicate(true)
	for index in range(1,samples.size()):
		if time<=float(samples[index]["time"]):
			var before: Dictionary=samples[index-1]; var after: Dictionary=samples[index]
			return blend(before["view"],after["view"],(time-float(before["time"]))/maxf(.00001,float(after["time"])-float(before["time"])),mode)
	return samples[-1]["view"].duplicate(true)
static func needs_forward(data: Dictionary) -> bool:
	if data.get("mode")=="3d" and settings(data)["dof_enabled"]: return true
	for key in ["bookmarks","paths"]:
		for entry in settings(data)[key]:
			if key=="bookmarks" and entry["view"].get("dof_enabled",false) and data.get("mode")=="3d": return true
			if key=="paths":
				for sample in entry["samples"]:
					if sample["view"].get("dof_enabled",false) and data.get("mode")=="3d": return true
	for item in data.get("objects",[]):
		if item.get("interior") is Dictionary and needs_forward(item["interior"]): return true
	for floor in data.get("floors",[]):
		if floor.get("room") is Dictionary and needs_forward(floor["room"]): return true
	return false
