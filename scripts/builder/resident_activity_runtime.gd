extends RefCounted

const ActivityPlan=preload("res://scripts/builder/resident_activity_plan.gd")
const Scheduler=preload("res://scripts/builder/resident_activities.gd")
const View=preload("res://scripts/builder/resident_activity_view.gd")
const Reservations=preload("res://scripts/builder/activity_reservations.gd")
const Citizens=preload("res://scripts/builder/citizen_plan.gd")
const Layers=preload("res://scripts/builder/layers.gd")
const Business=preload("res://scripts/builder/business_plan.gd")
var manager_ref: WeakRef
var visit_ref: WeakRef
var scheduler: RefCounted
var view: RefCounted
var items: Dictionary={}
var cache: Dictionary={}
var outside: Dictionary={}
var history: Array=[]
var elapsed: float=0
var notice: String=""
var closed: bool=false

func _init(citizens: Node) -> void:
	manager_ref=weakref(citizens);var root: Node=citizens.get_parent();var visit: Node=root.exploration;visit_ref=weakref(visit)
	scheduler=Scheduler.new(Reservations.for_world(root));view=View.new(visit,scheduler.reservations)
	scheduler.move_actor=view.move;scheduler.service_request=request_service;scheduler.service_result=service_result;scheduler.service_cancel=cancel_service
	scheduler.transition_actor=view.travel.step
	visit.interior_opened.connect(opened);visit.interior_closing.connect(closing)
	poll(true)

func manager() -> Node:return manager_ref.get_ref()
func visit() -> Node:return visit_ref.get_ref()
func inside() -> bool:
	var current: Node=visit();return is_instance_valid(current) and is_instance_valid(current.interior)

func data() -> Dictionary:
	var owner_manager: Node=manager();var root: Node=owner_manager.get_parent()
	if owner_manager.city_data.is_valid():return owner_manager.city_data.call()
	return root.live_data if "live_data" in root else root.data_state if "data_state" in root else owner_manager.terrain_data

func stamp(item: Dictionary) -> String:
	var library: RefCounted=manager().library
	return JSON.stringify([item["asset"],item.get("interior",{}),library.project_palette_revision,preload("res://scripts/builder/interior_kits.gd").catalog_hash]).sha256_text()

func apply_cache() -> void:
	var plans: Dictionary={}
	for uid in cache:plans[uid]=cache[uid]["plan"]
	scheduler.configure(plans)

func poll(force: bool=false) -> void:
	if not force and elapsed<.25:return
	elapsed=0;var source: Dictionary=data();var next: Dictionary={};var changed: bool=false;var library: RefCounted=manager().library
	for item in source.get("objects",[]):
		if not item.has("missing_asset") and library.assets.has(item["asset"]) and item.get("visible",true) and Layers.shown(source,Layers.layer(item,library)):next[item["uid"]]=item
	items=next
	for uid in cache.keys():
		if not items.has(uid):cache.erase(uid);changed=true;continue
		var revision: String=stamp(items[uid])
		if revision!=cache[uid]["stamp"]:cache[uid]={"stamp":revision,"plan":ActivityPlan.for_building(items[uid],manager().dimension,library)};changed=true
	if changed:apply_cache()

func ensure(uid: String) -> Dictionary:
	poll(true)
	if not items.has(uid):return {}
	if not cache.has(uid):
		var plan: Dictionary=ActivityPlan.for_building(items[uid],manager().dimension,manager().library);cache[uid]={"stamp":stamp(items[uid]),"plan":plan};apply_cache()
	return cache[uid]["plan"]

func request_service(job: Dictionary) -> Dictionary:
	var business: Variant=manager().businesses
	if not is_instance_valid(business) or not business.active:return {"ok":false,"reason":"The business is unavailable."}
	return business.service.request(job["building"],job["resident"],job["action"],manager().hour)

func service_result(job: Dictionary) -> Dictionary:
	var business: Variant=manager().businesses
	return business.service.result(job["resident"]) if is_instance_valid(business) else {}

func cancel_service(job: Dictionary) -> void:
	var business: Variant=manager().businesses
	if is_instance_valid(business):business.service.cancel(job["resident"],"Resident itinerary cancelled")

func opened() -> void:
	if closed:return
	poll(true);view.synchronize(scheduler,manager().residents)

func closing() -> void:
	# View detaches first, before the room tree is freed. Active residents stay
	# logically indoors even though their bodies have returned to the city tree.
	for resident in manager().residents:
		if scheduler.jobs.has(resident["id"]) and scheduler.jobs[resident["id"]]["state"] not in ["complete","cancelled"] and is_instance_valid(resident.get("actor")):resident["actor"].visible=scheduler.jobs[resident["id"]]["state"]=="queued"

func prepare_rebuild(appearance: String) -> void:
	# Keep unchanged original bodies aboard their live controller. Reconcile
	# detaches departing identities; appearance replacements detach before free.
	for identity in view.attached.keys():
		var actor: Node=view.attached[identity]["actor"].get_ref()
		if not is_instance_valid(actor) or actor.get_meta("citizen_appearance","")!=appearance:view.detach(identity)

func reconcile() -> void:
	var present: Dictionary={}
	for resident in manager().residents:present[resident["id"]]=true
	for identity in scheduler.jobs.keys():
		if not present.has(identity):view.detach(identity);scheduler.depart(identity);outside.erase(identity)
	poll(true);view.synchronize(scheduler,manager().residents)

func resolve_target(resident: Dictionary,target: String) -> String:
	var slot: String=Citizens.activity(manager().hour,resident.get("offset",0))
	if resident.has("activity_done_target"):
		if resident["activity_done_target"]==target and resident.get("activity_done_slot","")==slot:return resident["home"]
		resident.erase("activity_done_target");resident.erase("activity_done_slot")
	return target if items.has(target) else resident["home"]

func handled(resident: Dictionary,target: String) -> bool:
	var identity: String=resident["id"]
	if not scheduler.jobs.has(identity):return false
	var job: Dictionary=scheduler.jobs[identity]
	if job["state"] not in ["complete","cancelled"] and target!=job["building"]:scheduler.cancel(identity,"The resident's daily destination changed.")
	if job["state"] in ["complete","cancelled"]:finish(resident);return false
	resident["status"]=job["reason"];resident["business_state"]=job["state"];resident["waiting"]=""
	if job["state"]=="queued" or job["blocked_seconds"]>3:resident["waiting"]=job["reason"]
	if is_instance_valid(resident.get("actor")):resident["actor"].visible=view.attached.has(identity) or (job["state"]=="queued" and not inside())
	return true

func arrive(resident: Dictionary,target: String) -> bool:
	var owner_manager: Node=manager()
	if target==resident["home"] or not items.has(target) or owner_manager.plan["lookup"].get(target,{}).get("role","") not in ["work","shop"]:return false
	var item: Dictionary=items[target]
	if not preload("res://scripts/builder/exploration.gd").has_room(item,owner_manager.library):return false
	if resident["retry"]>0:return true
	var plan: Dictionary=ensure(target)
	if plan.is_empty() or not plan["floors"].has("ground") or plan["stations"].is_empty():
		resident["waiting"]=plan.get("notices",[])[0] if not plan.get("notices",[]).is_empty() else "This destination has no usable furnished activity station."
		resident["status"]=resident["waiting"];resident["retry"]=3;resident["actor"].visible=true;return true
	var action: String="";var business: Node=owner_manager.businesses
	if is_instance_valid(business) and business.service.businesses.has(target):
		var actions: Array=Business.activities(business.service.businesses[target]["config"])
		if not actions.is_empty():action=actions[0]["id"]
	return begin_visit(resident,target,plan,action)

func begin_visit(resident: Dictionary,target: String,plan: Dictionary,action: String="",station_assets: Array=[],hold_station: bool=false) -> bool:
	var owner_manager: Node=manager()
	var identity: String=resident["id"]
	outside[identity]={"position":resident["actor"].position,"building":target,"slot":Citizens.activity(owner_manager.hour,resident.get("offset",0))}
	var requested: Dictionary=scheduler.request(identity,target,"ground",plan["floors"]["ground"]["exit"],action,station_assets,hold_station)
	if not requested["ok"]:resident["waiting"]=requested["reason"];resident["status"]=resident["waiting"];resident["retry"]=3;outside.erase(identity);return true
	resident["actor"].visible=false;view.synchronize(scheduler,owner_manager.residents);handled(resident,target);return true

func restore_outside(resident: Dictionary,job: Dictionary) -> bool:
	var owner_manager: Node=manager();var actor: Variant=resident.get("actor")
	if not is_instance_valid(actor) or not actor.is_inside_tree():return false
	var remembered: Variant=outside.get(resident["id"],{}).get("position",actor.position)
	var origin: Vector2=Vector2(remembered.x/16,remembered.y/8) if owner_manager.dimension=="2d" else Vector2(remembered.x,remembered.z);var candidates: Array[Vector2]=[origin]
	for uid in [job["building"],resident["home"]]:
		if owner_manager.plan["lookup"].has(uid):candidates.append(owner_manager.plan["lookup"][uid]["point"]+resident["spacing"])
	for radius in [.75,1.5,3.0]:
		for turn in 8:candidates.append(origin+Vector2.RIGHT.rotated(turn*TAU/8)*radius)
	for at in candidates:
		var route: Dictionary=owner_manager.route(at,at)
		if route["path"].is_empty() or at.distance_to(route["start"])>.8:continue
		at=route["start"];var next: Variant=Vector2(at.x*16,at.y*8) if owner_manager.dimension=="2d" else Vector3(at.x,owner_manager.terrain_height(owner_manager.terrain_data,at)+.05,at.y)
		if not inside():
			var clear: bool=actor.clear_at(actor.get_parent().to_global(next)) if owner_manager.dimension=="2d" else actor.clear_at(Transform3D(actor.global_basis,actor.get_parent().to_global(next)),true)
			if not clear:continue
		actor.teleport_to(next);return true
	return false

func finish(resident: Dictionary) -> void:
	var identity: String=resident["id"];var job: Dictionary=scheduler.result(identity);var success: bool=job.get("state","")=="complete"
	view.detach(identity)
	var safe: bool=restore_outside(resident,job)
	if success and not job.get("hold_station",false):
		resident["activity_done_target"]=job["building"];resident["activity_done_slot"]=outside.get(identity,{}).get("slot","")
	resident["target"]="";resident["path"]=PackedVector2Array();resident["index"]=0;resident["stalled"]=0.0;resident["retry"]=0.0 if success else 3.0;resident["blocked"]=not safe
	resident["waiting"]="" if safe and success else job.get("reason","Resident activity cancelled.") if safe else "The exterior approach is blocked. Clear space to recover this resident."
	resident["status"]="Activity complete; returning home." if safe and success else resident["waiting"]
	if is_instance_valid(resident.get("actor")):resident["actor"].visible=safe and not inside()
	history.append({"resident":identity,"job":job.get("id",""),"building":job.get("building",""),"state":job.get("state",""),"reason":job.get("reason","")})
	if history.size()>64:history.pop_front()
	scheduler.depart(identity);outside.erase(identity)
	var business: Variant=manager().businesses
	if is_instance_valid(business):business.service.depart(identity)

func step(delta: float,speed_scale: float) -> void:
	if closed:return
	elapsed+=delta;poll()
	if not view.synchronize(scheduler,manager().residents,delta):notice=view.notice;return
	scheduler.step(delta,speed_scale);view.synchronize(scheduler,manager().residents,delta);notice=view.notice
	for resident in manager().residents:
		if scheduler.jobs.has(resident["id"]) and scheduler.jobs[resident["id"]]["state"] in ["complete","cancelled"]:finish(resident)

func close() -> void:
	if closed:return
	closed=true
	for resident in manager().residents:
		if scheduler.jobs.has(resident["id"]):scheduler.cancel(resident["id"],"Resident interior activities stopped.");finish(resident)
	view.close();scheduler.reset();scheduler.service_request=Callable();scheduler.service_result=Callable();scheduler.service_cancel=Callable();scheduler.move_actor=Callable();scheduler.transition_ready=Callable();scheduler.transition_actor=Callable()
	var current: Node=visit()
	if is_instance_valid(current):
		if current.interior_opened.is_connected(opened):current.interior_opened.disconnect(opened)
		if current.interior_closing.is_connected(closing):current.interior_closing.disconnect(closing)
	cache.clear();items.clear();outside.clear()
