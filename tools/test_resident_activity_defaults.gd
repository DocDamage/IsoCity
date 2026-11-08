extends "res://tools/test_resident_activities.gd"
func run() -> void:
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new()
	for mode in ["2d","3d"]:
		for id in ["3d:HanX_School/School_Building","3d:HanX_Shop/Shop_Cafe"]:
			var host: Dictionary={"uid":"host","asset":id,"direction":"0","scale":1.0,"position":[0,0,0]};var original: Dictionary=host.duplicate(true);var logical: Dictionary=Plan.for_building(host,mode,library)
			check(logical["virtual"] and not logical["floors"].is_empty() and logical["stations"].size()>=2,"Default school/café has logical furnished stations without creating an owned room: "+mode+" "+id)
			check(host==original,"Offscreen default planning does not author a room or allocate saved identities: "+mode)
			var actual: Dictionary=preload("res://scripts/builder/interiors.gd").make_for(host,mode,library);host["interior"]=actual;var owned: Dictionary=Plan.for_building(host,mode,library)
			check(not owned["virtual"] and logical["semantic_revision"]==owned["semantic_revision"],"Logical default uses the exact geometry, anchors, floor surface and station semantics of actual creation: "+mode+" "+id)
			var scheduler: RefCounted=Scheduler.new();scheduler.configure({"host":logical});var entry: Vector3=logical["floors"]["ground"]["exit"];scheduler.request("resident_a","host","ground",entry);scheduler.request("resident_b","host","ground",entry)
			var a: Dictionary=scheduler.result("resident_a");var b: Dictionary=scheduler.result("resident_b")
			check(a["state"]=="entering" and b["state"]=="entering","Two actual default-room stations have complete approach and return routes: "+mode+" "+id+" "+a["reason"]+" "+b["reason"])
			if a["state"]!="entering" or b["state"]!="entering":
				for station in logical["stations"]:print("STATION ",station["name"]," ",station["reason"]," ",station["approach"])
				scheduler.reset();continue
			for tick in 3:scheduler.step(.1)
			a=scheduler.result("resident_a");b=scheduler.result("resident_b");scheduler.configure({"host":owned});var adopted: Dictionary=scheduler.result("resident_a")
			check(adopted["id"]==a["id"] and adopted["position"]==a["position"] and adopted["state"]==a["state"] and scheduler.result("resident_b")["id"]==b["id"],"Materializing a player-visited room preserves both job identities, positions and progress: "+mode)
			check(not adopted["virtual"] and adopted["station"]["uid"]!=a["station"]["uid"] and scheduler.reservations.entries.size()==2,"Reservation tokens migrate to fresh owned station IDs without double-booking: "+mode)
			var unchanged: Dictionary=actual.duplicate(true);actual["title"]="Renamed room";actual["objects"][0]["name"]="Renamed furnishing";var renamed: Dictionary=Plan.for_building(host,mode,library);scheduler.configure({"host":renamed})
			check(scheduler.result("resident_a")["id"]==a["id"] and scheduler.result("resident_a")["state"]!="cancelled","Cosmetic room/name changes retain the same activity: "+mode)
			for tick in 1000:scheduler.step(.1)
			check(scheduler.jobs.values().all(func(job: Dictionary):return job["state"]=="complete") and scheduler.reservations.entries.is_empty(),"Materialized default-room residents complete their activity and return: "+mode)
			scheduler.reset();scheduler.configure({"host":logical});scheduler.request("late_visitor","host","ground",entry)
			for tick in 800:
				scheduler.step(.1)
				if scheduler.result("late_visitor")["state"]=="returning":break
			var leaving: Dictionary=scheduler.result("late_visitor");scheduler.configure({"host":owned});var late: Dictionary=scheduler.result("late_visitor")
			check(leaving["state"]=="returning" and late["id"]==leaving["id"] and late["position"]==leaving["position"],"A first player visit while the resident is already leaving preserves its return progress: "+mode)
			check(late["station_key"].ends_with(late["station"]["uid"]) and late["station"]["uid"]!=leaving["station"]["uid"] and scheduler.reservations.entries.is_empty(),"Late materialization updates source identity without reacquiring an already released station: "+mode)
			scheduler.reset();actual=unchanged;host["interior"]=actual;owned=Plan.for_building(host,mode,library);scheduler.configure({"host":owned});scheduler.request("resident_a","host","ground",entry);a=scheduler.result("resident_a")
			for item in actual["objects"]:
				if item["uid"]==a.get("station",{}).get("uid",""):item["uid"]="replacement_station";break
			scheduler.configure({"host":Plan.for_building(host,mode,library)});check(scheduler.result("resident_a")["state"]=="cancelled","Replacing an authored occupied station cannot silently transfer its job to a copied object: "+mode);scheduler.reset()
	print("RESIDENT ACTIVITY DEFAULTS: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
