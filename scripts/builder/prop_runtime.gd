extends Node
const Plan=preload("res://scripts/builder/prop_plan.gd")
const UtilityProfiles=preload("res://scripts/builder/utility_profiles.gd")
const MAX_EFFECTS: int=24
var exploration: Node
var active: Dictionary={}
var states: Dictionary={}
var inventory: Dictionary={}
var effects=preload("res://scripts/builder/prop_effects.gd").new()
var elapsed: float=0
var notice: String=""
var notice_time: float=0
var saved: Dictionary={}
var swing=preload("res://scripts/builder/prop_swing.gd").new()
var reservations: RefCounted
var reservation_key: String=""
var reservation_token: int=0
var active_transform: Variant

func key_for(candidate: Dictionary) -> String: return candidate["scope"]+candidate["item"]["uid"]
func state_for(candidate: Dictionary) -> Dictionary:
	var key: String=key_for(candidate); var stamp: int=hash(candidate["profile"])
	if not states.has(key) or states[key].get("stamp")!=stamp:
		var on: bool=candidate["profile"].get("initial_on",false)
		states[key]={"stamp":stamp,"on":on,"remaining":candidate["profile"]["duration"] if on and candidate["profile"]["kind"]=="appliance" else 0.0,"cycles":0,"touched":false}
	return states[key]

func prompt(candidate: Dictionary={}) -> String:
	if not active.is_empty():
		var kind: String=active["profile"]["kind"]
		var text: String="E · Stand up" if kind=="seat" else ("E · Stop swinging" if kind=="swing" else "E · Cancel · "+active["profile"]["label"])
		var fallback: String=str(exploration.player.get_meta("animation_fallback","")) if exploration.dimension=="2d" and exploration.player.authored_animation else ""
		return text+(" · "+fallback if not fallback.is_empty() else "")+(" · "+notice if notice_time>0 else "")
	if candidate.is_empty(): return notice if notice_time>0 else ""
	var state: Dictionary=state_for(candidate); var profile: Dictionary=candidate["profile"]
	var text: String="E · "+profile["label"]
	if profile["kind"]=="switch": text+=" · "+("ON" if power_state(candidate) else "OFF")
	elif profile["kind"]=="appliance" and state["cycles"]>0: text+=" · completed: "+str(state["cycles"])
	var reason: String=power_reason(target(candidate) if profile["kind"]=="switch" else candidate)
	if not reason.is_empty(): text+=" · "+reason
	return text+(" · "+notice if notice_time>0 else "")

func target(candidate: Dictionary) -> Dictionary:
	var uid: String=candidate["profile"].get("target","")
	if uid.is_empty(): return candidate
	var item: Dictionary=Plan.target_record(candidate["item"],candidate["data"],exploration.library)
	if item.is_empty():return {}
	var node: Node=candidate["instances"].get(item["uid"])
	if not is_instance_valid(node) or not node.is_visible_in_tree():return {}
	var result: Dictionary=candidate.duplicate(false);result["node"]=node;result["item"]=item;result["profile"]=Plan.profile(item);return result
func power_state(candidate: Dictionary) -> bool:
	var controlled: Dictionary=target(candidate)
	return not controlled.is_empty() and state_for(controlled)["on"] and power_reason(controlled).is_empty()

func power_reason(candidate: Dictionary) -> String:
	if candidate.is_empty() or not exploration or not is_instance_valid(exploration.power): return ""
	var item: Dictionary=candidate["item"]
	if exploration.interior:
		if UtilityProfiles.fixture_load(item)>0: return exploration.power.requirement(exploration.interior_uid,"building")
	elif candidate["scope"]=="city:":
		return exploration.power.requirement(item["uid"],"fixture")
	return ""

func interact(candidate: Dictionary={}) -> bool:
	if not active.is_empty(): return finish(false)
	if candidate.is_empty(): return false
	if not is_instance_valid(candidate.get("node")) or not candidate["node"].is_visible_in_tree() or not candidate["item"].get("visible",true): return false
	var context: Dictionary=Plan.context(exploration)
	var fresh: Dictionary={}
	for item in context["data"].get("objects",[]):
		if item["uid"]==candidate["item"]["uid"]: fresh=item; break
	if fresh.is_empty() or not fresh.get("visible",true) or context["instances"].get(fresh["uid"])!=candidate["node"]: return false
	var profile: Dictionary=Plan.profile(fresh)
	if profile.is_empty(): return false
	candidate=context.duplicate(false); candidate["item"]=fresh; candidate["node"]=context["instances"][fresh["uid"]]; candidate["profile"]=profile
	var kind: String=candidate["profile"]["kind"]
	if kind=="switch":
		var controlled: Dictionary=target(candidate)
		if controlled.is_empty(): notice="Switch target is missing or unavailable in this room."; notice_time=5; return false
		var state: Dictionary=state_for(controlled)
		var reason: String=power_reason(controlled)
		if not state["on"] and not reason.is_empty(): notice=reason; notice_time=5; return false
		state["on"]=not state["on"]; state["touched"]=true
		state["remaining"]=controlled["profile"]["duration"] if state["on"] and controlled["profile"]["kind"]=="appliance" else 0.0
		state_for(candidate)["touched"]=true; notice="Power on" if state["on"] else "Power off"; notice_time=3; sync_effects(); return true
	if kind=="appliance":
		var reason: String=power_reason(candidate)
		if not reason.is_empty(): notice=reason; notice_time=5; return false
	var player: Node=exploration.player
	var approach: Variant=Plan.ground_point(candidate,exploration,"approach")
	if not Plan.reachable(exploration,candidate["node"],approach) or not Plan.standing_clear(exploration,approach):
		notice="The operator approach is blocked. Clear a standing space or adjust its anchor."; notice_time=5; return false
	reservations=preload("res://scripts/builder/activity_reservations.gd").for_world(candidate["world"])
	reservation_key=key_for(candidate); reservation_token=reservations.acquire(reservation_key,self)
	if reservation_token==0: notice="This station is already in use."; notice_time=5; reservation_key=""; return false
	active=candidate; elapsed=0
	active_transform=candidate["node"].global_transform
	saved={"physics":player.is_physics_processing(),"layer":player.collision_layer,"mask":player.collision_mask,"position":player.global_position}
	if exploration.dimension=="2d": saved.merge({"action":player.action,"direction":player.direction,"visual":player.interaction_visual_offset})
	else:
		saved["body"]=player.body.transform; saved["limbs"]=player.limbs.map(func(limb: Node3D)->Transform3D:return limb.transform)
	player.set_physics_process(false); player.collision_layer=0; player.collision_mask=0; player.velocity=Vector2.ZERO if exploration.dimension=="2d" else Vector3.ZERO
	player.teleport_to(player.get_parent().to_local(approach))
	if kind=="swing": swing.start(candidate,exploration)
	if kind=="appliance":
		var state: Dictionary=state_for(candidate); state["on"]=true; state["remaining"]=candidate["profile"]["duration"]; state["touched"]=true
	pose(); sync_effects(); return true

func pose(delta: float=0) -> void:
	if active.is_empty() or not is_instance_valid(active["node"]): return
	var player: Node=exploration.player; var kind: String=active["profile"]["kind"]; var point: Variant=Plan.global_point(active,exploration); var approach: Variant=Plan.global_point(active,exploration,"approach")
	if kind=="swing":
		var phase: float=sin(elapsed*2.2)*.5; var length: float=active["profile"]["rope_length"]; point=Plan.global_point(active,exploration,"point",Vector3(0,length*(1-cos(phase)),sin(phase)*length)); swing.step(phase)
	elif kind=="slide":
		var progress: float=clampf(elapsed/float(active["profile"]["duration"]),0,1)
		var end: Variant=Plan.global_point(active,exploration,"end")
		var hips: Variant=Vector2(0,-.85*8) if exploration.dimension=="2d" else Vector3.UP*.85
		point=(approach+hips).lerp(point,smoothstep(0,1,progress/.35)) if progress<.35 else point.lerp(end+hips,clampf((progress-.35)/.65,0,1))
	var seated: bool=kind in ["seat","swing","slide"]
	if exploration.dimension=="2d":
		player.action="sit" if seated else "wave"; player.direction=active["item"]["direction"] if active["item"]["direction"] in ["SE","SW","NW","NE"] else "SE"
		var heading: Vector2=Plan.ground_point(active,exploration,"facing")-Plan.ground_point(active,exploration,"point" if seated else "approach")
		if heading.length_squared()>.0001: player.direction=("NE" if heading.y<0 else "SE") if heading.x>=0 else ("NW" if heading.y<0 else "SW")
		if seated:
			var sprite: Sprite2D=player.get_node("Sprite2D"); var desired: Vector2=point+Vector2(0,.85*8)
			player.interaction_visual_offset=sprite.global_transform.affine_inverse().basis_xform(desired-player.global_position)-player.terrain_visual_offset
		player._update_animation(delta)
	else:
		if seated: player.body.global_position=point-Vector3.UP*.85
		var facing: Vector3=Plan.ground_point(active,exploration,"facing")-(point if seated else player.global_position)
		if Vector2(facing.x,facing.z).length()>.01: player.body.global_rotation.y=atan2(-facing.x,-facing.z)
		for index in player.limbs.size(): player.limbs[index].rotation.x=(.95 if index>=2 else .12) if seated else (.7 if index<2 else 0.0)

func safe_destination(point: Variant) -> bool:
	return Plan.standing_clear(exploration,point,saved["mask"])

func release_reservation() -> void:
	if reservations and reservation_token: reservations.release(reservation_key,reservation_token)
	reservations=null; reservation_key=""; reservation_token=0

func finish(force: bool=false,relocate: bool=true,completed: bool=false) -> bool:
	if active.is_empty(): return true
	if not exploration or not is_instance_valid(exploration.player): release_reservation(); active={}; saved={}; return true
	var player: Node=exploration.player; var candidate: Dictionary=active; var kind: String=candidate["profile"]["kind"]; var destination: Variant=saved["position"]
	if not force and relocate:
		var candidates: Array=[saved["position"]]
		if is_instance_valid(candidate["node"]): candidates.push_front(Plan.ground_point(candidate,exploration,"exit"))
		for radius in ([16.0,32.0] if exploration.dimension=="2d" else [.75,1.5]):
			for turn in 8:
				var offset: Vector2=Vector2.RIGHT.rotated(turn*TAU/8)*float(radius)
				candidates.append(saved["position"]+(offset if exploration.dimension=="2d" else Vector3(offset.x,0,offset.y)))
		var found: bool=false
		for point in candidates:
			if safe_destination(point): destination=point; found=true; break
		if not found: notice="Standing space is blocked. Clear a space and try again."; notice_time=5; return false
	if kind=="appliance" and not completed:
		var state: Dictionary=states.get(key_for(candidate),{})
		if state.get("stamp")==hash(candidate["profile"]): state["on"]=false; state["remaining"]=0
	if kind=="swing": swing.reset()
	if exploration.dimension=="2d": player.interaction_visual_offset=saved["visual"]; player.action=saved["action"]; player.direction=saved["direction"]
	else:
		player.body.transform=saved["body"]
		for index in mini(player.limbs.size(),saved["limbs"].size()): player.limbs[index].transform=saved["limbs"][index]
	player.collision_layer=saved["layer"]; player.collision_mask=saved["mask"]; player.set_physics_process(saved["physics"])
	if relocate: player.teleport_to(player.get_parent().to_local(destination))
	release_reservation(); active={}; saved={}; elapsed=0; return true

func sync_effects() -> void:
	if not exploration.enabled: effects.reset(); return
	var context: Dictionary=Plan.context(exploration); var candidates: Array=[]; var keep: Dictionary={}
	for item in context["data"].get("objects",[]):
		var node: Node=context["instances"].get(item["uid"]); var profile: Dictionary=Plan.profile(item)
		if exploration.cooking and exploration.cooking.manages(item): continue
		if exploration.laundry and exploration.laundry.manages(item): continue
		if exploration.fitness and exploration.fitness.manages(item): continue
		if exploration.arcade and exploration.arcade.manages(item): continue
		if exploration.camping and exploration.camping.manages(item,context["scope"]): continue
		if not is_instance_valid(node) or not node.is_visible_in_tree() or profile.get("kind","") not in ["switch","appliance"]: continue
		var distance: float=node.global_position.distance_to(exploration.player.global_position)
		if distance>(320 if exploration.dimension=="2d" else 24): continue
		var candidate: Dictionary=context.duplicate(false); candidate["item"]=item; candidate["node"]=node; candidate["profile"]=profile; candidate["distance"]=distance; candidates.append(candidate)
	candidates.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a["distance"]<b["distance"] if a["distance"]!=b["distance"] else a["item"]["uid"]<b["item"]["uid"])
	for candidate in candidates.slice(0,MAX_EFFECTS):
		var state: Dictionary=state_for(candidate); var key: String=key_for(candidate); keep[key]=true
		var reason: String=power_reason(target(candidate) if candidate["profile"]["kind"]=="switch" else candidate)
		var on: bool=state["on"] and reason.is_empty()
		if candidate["profile"]["kind"]=="switch": on=power_state(candidate)
		var text: String=""
		if state["touched"]: text=("ON" if on else "OFF") if candidate["profile"]["kind"]=="switch" else ("Running · %.1fs"%state["remaining"] if on else (candidate["profile"]["result"]+" ×"+str(state["cycles"]) if state["cycles"]>0 else "Ready"))
		if not reason.is_empty(): text="Power interrupted"
		effects.apply(key,candidate,exploration,on,text)
	for key in effects.entries.keys():
		if not keep.has(key): effects.release(key)

func _physics_process(delta: float) -> void:
	if not exploration or not is_instance_valid(exploration.player): return
	notice_time=maxf(0,notice_time-delta)
	if not exploration.enabled:
		if not active.is_empty(): finish(true,false)
		effects.reset(); return
	var context: Dictionary=Plan.context(exploration); var scope: String=context["scope"]
	var known: Dictionary={}
	var unpowered: Dictionary={}
	for item in context["data"].get("objects",[]):
		var profile: Dictionary=Plan.profile(item)
		var node: Node=context["instances"].get(item["uid"])
		if profile.is_empty() or not is_instance_valid(node) or not node.is_visible_in_tree(): continue
		known[scope+item["uid"]]=hash(profile)
		if profile["kind"] in ["switch","appliance"]:
			var candidate: Dictionary={"item":item,"profile":profile,"scope":scope}
			var state: Dictionary=state_for(candidate)
			if state["remaining"]>0 and not power_reason(candidate).is_empty(): unpowered[key_for(candidate)]=true
	for key in states.keys():
		if key.begins_with(scope) and (not known.has(key) or states[key]["stamp"]!=known[key]): states.erase(key)
	if not active.is_empty():
		var invalid: bool=active["scope"]!=scope or not is_instance_valid(active["node"]) or not active["node"].is_visible_in_tree() or known.get(key_for(active))!=hash(active["profile"])
		if not invalid: invalid=not reservations or reservations.current(reservation_key).get("token",0)!=reservation_token
		if not invalid: invalid=active["node"].global_transform!=active_transform or context["instances"].get(active["item"]["uid"])!=active["node"]
		if invalid:
			# Do not leave the actor attached to moved/deleted geometry or retain an
			# old object dictionary after document reconciliation.
			finish(true,false)
			if not Plan.standing_clear(exploration,exploration.player.global_position): exploration.player.recover_to_safe()
			notice="Station changed; interaction cancelled. Use Recover if standing space is blocked."; notice_time=5
		else:
			for item in context["data"].get("objects",[]):
				if item["uid"]==active["item"]["uid"]: active["item"]=item; break
	for key in states:
		var state: Dictionary=states[key]
		if not key.begins_with(scope) or state["remaining"]<=0 or unpowered.has(key): continue
		state["remaining"]=maxf(0,state["remaining"]-delta)
		if state["remaining"]>0: continue
		state["on"]=false; state["cycles"]+=1
		for item in context["data"].get("objects",[]):
			if scope+item["uid"]!=key: continue
			var result: String=Plan.profile(item).get("result","Completed cycle"); inventory[result]=int(inventory.get(result,0))+1; notice=result+" +1"; notice_time=5
			if not active.is_empty() and key_for(active)==key: finish(false,true,true)
	if not active.is_empty():
		elapsed+=delta; pose(delta)
		if active["profile"]["kind"]=="slide" and elapsed>=active["profile"]["duration"]: finish(false,true,true)
	sync_effects()

func _process(_delta: float) -> void:
	# Parent cameras update before this child. Keep billboard-bound poses and
	# swing rigs on the current rendered card without advancing animation twice.
	if not active.is_empty(): pose()

func reset(clear_states: bool=true) -> void:
	if not active.is_empty(): finish(true,false)
	release_reservation()
	swing.reset()
	effects.reset(); notice=""; notice_time=0
	if clear_states: states.clear(); inventory.clear()
func _exit_tree() -> void: reset()
