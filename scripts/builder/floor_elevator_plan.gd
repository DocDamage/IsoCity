extends RefCounted

static func stops(root: Dictionary,link: Dictionary) -> Array:
	var definitions: Array=preload("res://scripts/builder/floor_plan.gd").definitions(root); var low: float=0; var high: float=0
	for floor in definitions:
		if floor["uid"]==link["lower"]: low=float(floor["height"])
		if floor["uid"]==link["upper"]: high=float(floor["height"])
	return definitions.filter(func(floor: Dictionary)->bool:return floor["height"]>=low and floor["height"]<=high)

static func trip(from: float,to: float,speed: float=1.5,acceleration: float=1.8) -> Dictionary:
	var distance: float=absf(to-from); var ramp: float=minf(speed/acceleration,sqrt(distance/acceleration))
	var cruise: float=(distance-acceleration*ramp*ramp)/maxf(0.00001,acceleration*ramp)
	return {"from":from,"to":to,"ramp":ramp,"cruise":maxf(0,cruise),"acceleration":acceleration,"duration":2*ramp+maxf(0,cruise)}

static func sample(travel: Dictionary,time: float) -> float:
	if travel["duration"]<=0.00001 or time>=travel["duration"]: return travel["to"]
	var t: float=maxf(0,time); var ramp: float=travel["ramp"]; var acceleration: float=travel["acceleration"]; var distance: float
	if t<ramp: distance=0.5*acceleration*t*t
	elif t<ramp+travel["cruise"]: distance=0.5*acceleration*ramp*ramp+acceleration*ramp*(t-ramp)
	else: distance=absf(travel["to"]-travel["from"])-0.5*acceleration*pow(travel["duration"]-t,2)
	return travel["from"]+signf(travel["to"]-travel["from"])*distance
