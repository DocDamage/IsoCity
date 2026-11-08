extends RefCounted
const Plan=preload("res://scripts/builder/resident_activity_plan.gd")
static func initial(leg: Dictionary,source_height: float,target_height: float,point: Vector3) -> Dictionary:
	return {"link":leg["link"],"source":leg["floor"],"target":leg["next_floor"],"source_height":source_height,"target_height":target_height,"point":point,"progress":0.0}
static func advance(state: Dictionary,leg: Dictionary,mode: String,delta: float,speed: float) -> void:
	if state.get("blocked",false):return
	var length: float=sqrt(Plan.metric(leg["to"]-leg["from"],mode).length_squared()+leg["rise"]*leg["rise"])
	state["progress"]=minf(1,state["progress"]+delta*1.8*speed/maxf(.01,length))
	state["point"]=leg["from"].lerp(leg["to"],state["progress"])
	if mode=="3d":
		var from: Vector2=Plan.metric(leg.get("flight_from",leg["from"]),mode);var to: Vector2=Plan.metric(leg.get("flight_to",leg["to"]),mode);var line: Vector2=to-from
		var progress: float=(Plan.metric(state["point"],mode)-from).dot(line)/maxf(.001,line.length_squared())
		var ascending: bool=state["target_height"]>state["source_height"];var count: int=ceili(leg["rise"]/.24)
		# Match the native .28 m capsule and authored .24 m maximum treads.
		# Its uphill edge must clear the next tread before materialization.
		var support: float=clampf((progress if ascending else 1-progress)+.28/maxf(.001,line.length()),0,1)
		var height: float=ceilf(support*count)/count*leg["rise"]
		state["point"].y=height+(0 if ascending else -leg["rise"])+.03
