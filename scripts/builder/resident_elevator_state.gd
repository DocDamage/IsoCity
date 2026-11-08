extends RefCounted

const Motion=preload("res://scripts/builder/floor_elevator_plan.gd")
const PHASES=["calling","boarding","waiting","closing","moving","arriving","opening","idle","blocked","alighting"]

static func initial(link: Dictionary,leg: Dictionary,mode: String,source_height: float,target_height: float,car: Dictionary,position: Vector3) -> Dictionary:
	var offset:=Vector3(0,.03,0)
	if mode=="2d":
		var pixel: Vector2=preload("res://scripts/builder/grid_fit.gd").pixels(Vector2(link["start"][0],link["start"][1]));offset=Vector3(pixel.x,pixel.y,0)
	var center: Vector3=offset if mode=="2d" else Vector3(link["start"][0],offset.y,link["start"][1])
	var height: float=car.get("height",source_height);var calling: bool=absf(height-source_height)>.01
	return {"version":1,"phase":"calling" if calling else "boarding","call_phase":"closing","mode":mode,"link":link["uid"],"source":leg["floor"],"target":leg["next_floor"],"last_stop":car.get("last_stop",leg["floor"]),"height":height,"elapsed":0.0,"motion":{},"source_height":source_height,"target_height":target_height,"offset":offset,"point":position,"cabin_point":center,"notice":"","queue":[]}

static func valid(value: Dictionary) -> bool:
	if value.get("version",0)!=1 or value.get("phase","") not in PHASES:return false
	for key in ["source","target","last_stop","link"]:
		if not value.get(key) is String or value[key].is_empty():return false
	for key in ["height","elapsed","source_height","target_height"]:
		if not (value.get(key) is float or value.get(key) is int) or not is_finite(float(value[key])):return false
	if value["elapsed"]<0 or not value.get("offset") is Vector3 or not value["offset"].is_finite():return false
	if not value.get("motion",{}) is Dictionary or not value.get("queue",[]) is Array:return false
	if not value.get("presentation",{}) is Dictionary:return false
	if value["phase"] in ["calling","boarding","alighting"] and (not value.get("point") is Vector3 or not value["point"].is_finite()):return false
	if value["phase"] in ["calling","boarding"] and (value.get("mode","") not in ["2d","3d"] or not value.get("cabin_point") is Vector3 or not value["cabin_point"].is_finite()):return false
	if value["phase"]=="calling" and value.get("call_phase","") not in ["waiting","closing","moving","arriving","opening","idle","blocked"]:return false
	if value.get("phase")=="moving" or (value["phase"]=="calling" and value["call_phase"]=="moving"):
		if not value.get("motion") is Dictionary:return false
		for key in ["from","to","ramp","cruise","acceleration","duration"]:
			if not (value["motion"].get(key) is float or value["motion"].get(key) is int) or not is_finite(float(value["motion"][key])):return false
	return true

static func capture_presentation(body: Node) -> Dictionary:
	var pose: Dictionary
	if body is CharacterBody2D:
		pose={"mode":"2d","action":body.action,"direction":body.direction,"frame":body.get_node("Sprite2D").frame,"timer":body._anim_timer,"frame_index":body._anim_frame_idx,"blink":body._blink_timer}
	else:pose={"mode":"3d","body":body.body.transform,"limbs":body.limbs.map(func(limb: Node3D):return limb.transform),"phase":body.phase}
	pose["appearance"]=body.get_meta("citizen_appearance","");return pose

static func capture(lift: Node) -> Dictionary:
	var offset: Vector3=Vector3(lift.view.captured.x,lift.view.captured.y,0) if lift.npc is CharacterBody2D else lift.view.offset
	return {"version":1,"phase":lift.phase,"link":lift.link["uid"],"source":lift.npc_source,"target":lift.target,"last_stop":lift.last_stop,"height":lift.height,"elapsed":lift.elapsed,"motion":lift.motion.duplicate(true),"source_height":lift.stop_height(lift.npc_source),"target_height":lift.stop_height(lift.target),"offset":offset,"notice":lift.notice,"queue":lift.queue.duplicate(),"presentation":capture_presentation(lift.npc)}

static func restore_presentation(body: Node,state: Dictionary) -> void:
	var pose: Dictionary=state.get("presentation",{})
	if pose.get("appearance","")!=body.get_meta("citizen_appearance",""):return
	if body is CharacterBody2D and pose.get("mode","")=="2d":
		body.action=pose["action"];body.direction=pose["direction"];body._anim_timer=pose["timer"];body._anim_frame_idx=pose["frame_index"];body._blink_timer=pose["blink"];var sprite: Sprite2D=body.get_node("Sprite2D");sprite.frame=clampi(pose["frame"],0,sprite.hframes*sprite.vframes-1)
	elif body is CharacterBody3D and pose.get("mode","")=="3d":
		body.body.transform=pose["body"];body.phase=pose["phase"]
		for index in mini(body.limbs.size(),pose["limbs"].size()):body.limbs[index].transform=pose["limbs"][index]

static func advance(value: Dictionary,delta: float,speed_scale: float=1) -> Dictionary:
	var state: Dictionary=value.duplicate(true)
	# Blocked/waiting physical trips need a clear controller/landing check on
	# materialization. Never declare an unseen obstruction cleared by a timer.
	match state["phase"]:
		"calling":
			match state["call_phase"]:
				"closing":
					state["elapsed"]+=delta
					if state["elapsed"]>=.25:state["motion"]=Motion.trip(state["height"],state["source_height"]);state["call_phase"]="moving";state["elapsed"]=0.0
				"moving":
					state["elapsed"]+=delta;state["height"]=Motion.sample(state["motion"],state["elapsed"])
					if state["elapsed"]>=state["motion"]["duration"]:state["call_phase"]="arriving"
				"arriving":state["call_phase"]="opening";state["last_stop"]=state["source"];state["elapsed"]=0.0
				"opening":
					state["elapsed"]+=delta
					if state["elapsed"]>=.25:state["phase"]="boarding";state["elapsed"]=0.0
				"idle":state["phase"]="boarding";state["elapsed"]=0.0
		"boarding":
			state["point"]=state["point"].move_toward(state["cabin_point"],delta*(48 if state["mode"]=="2d" else 1.8)*speed_scale)
			if state["point"].distance_to(state["cabin_point"])<.005:state["phase"]="closing";state["elapsed"]=0.0;state["last_stop"]=state["source"]
		"closing":
			state["elapsed"]+=delta
			if state["elapsed"]>=.25:state["motion"]=Motion.trip(state["height"],state["target_height"]);state["phase"]="moving";state["elapsed"]=0.0
		"moving":
			state["elapsed"]+=delta;state["height"]=Motion.sample(state["motion"],state["elapsed"])
			if state["elapsed"]>=state["motion"]["duration"]:state["phase"]="arriving"
		"arriving":state["last_stop"]=state["target"];state["phase"]="opening";state["elapsed"]=0.0
		"opening":
			state["elapsed"]+=delta
			if state["elapsed"]>=.25:state["phase"]="idle"
	return state

static func point(state: Dictionary,link: Dictionary,mode: String) -> Vector3:
	if state["phase"] in ["calling","boarding","alighting"]:return state["point"]
	if mode=="2d":return state["offset"]
	return Vector3(link["start"][0]+state["offset"].x,state["height"]-state["source_height"]+state["offset"].y,link["start"][1]+state["offset"].z)

static func landing_start(state: Dictionary,link: Dictionary,mode: String) -> Vector3:
	if mode=="2d":return state["offset"]
	return Vector3(link["start"][0]+state["offset"].x,state["offset"].y,link["start"][1]+state["offset"].z)
