extends "res://tools/test_resident_activity_routines.gd"
var facts: Dictionary={}
func facts_path() -> String:return "res://output/verification/asset_expansion/I14/stair_routine_facts.json"
func prepare_document(doc: RefCounted,mode: String) -> void:
	var room: Dictionary=preload("res://scripts/builder/interiors.gd").make(mode,"Stair entrance");room["objects"]=[];var upper: Dictionary=room.duplicate(true);upper["title"]="Upstairs classroom"
	var furnishings: RefCounted=Doc.new();furnishings.data=upper
	for x in [-3,3]:furnishings.add("3d:HanX_School/Student_Chair",[(x+2)*16,-64,0] if mode=="2d" else [x,.12,-6],"0")
	room["floors"]=[{"uid":"upper","name":"Upstairs classroom","height":3,"room":upper}];room["floor_links"]=[{"uid":"stairs","kind":"stairs","lower":"ground","upper":"upper","start":[0,2],"end":[0,-4],"width":1.6}]
	doc.data["objects"].filter(func(item: Dictionary):return item.get("citizen_role","")=="work")[0]["interior"]=room
	facts[mode]={"trips":{},"people":{},"max_owners":0,"player_changed_floor":false,"previous":{},"max_vertical_step":0.0,"service_people":{},"recovery_start":{}}
func tick() -> void:
	await super.tick()
	var mode: String=citizens.dimension;var visit: Node=studio.worlds[mode].exploration
	if not visit.interior or not citizens.activities:return
	var result: Dictionary=facts[mode];var scheduler: RefCounted=citizens.activities.scheduler;var travel: RefCounted=citizens.activities.view.travel
	result["max_owners"]=maxi(result["max_owners"],scheduler.jobs.values().filter(func(job: Dictionary):return job["link_token"]!=0).size());result["player_changed_floor"]=result["player_changed_floor"] or visit.active_floor()!="ground"
	for resident in citizens.residents:
		var identity: String=resident["id"];var body: Node=resident["actor"];var job: Dictionary=scheduler.jobs.get(identity,{})
		if mode=="3d" and job.get("state","")=="service" and body.global_position.y>2.9:result["service_people"][identity]=true
		if not travel.states.has(identity) or travel.states[identity].get("kind","")!="stairs":continue
		var key: String=str(job["link_token"]);result["trips"][key]=true;result["people"][identity]=true
		if mode=="3d":
			if result["previous"].has(key):result["max_vertical_step"]=maxf(result["max_vertical_step"],absf(body.global_position.y-result["previous"][key]))
			result["previous"][key]=body.global_position.y
			if not result["recovery_start"].has(identity):result["recovery_start"][identity]=body.recovery_count
func after_completed(_doc: RefCounted,mode: String) -> void:
	var result: Dictionary=facts[mode]
	check(result["trips"].size()==4 and result["people"].size()==2,"Both original residents walk up and down the live stairs: "+mode+" "+str(result))
	check(result["max_owners"]==1 and not result["player_changed_floor"],"Shared single-flight capacity preserves the player's ground floor: "+mode)
	if mode=="3d":
		check(result["max_vertical_step"]<.4 and result["service_people"].size()==2,"Native capsule treads continuously reach both upstairs activities")
		check(citizens.residents.all(func(resident: Dictionary):return resident["actor"].recovery_count==result["recovery_start"].get(resident["id"],-1)),"Physical stair trips never require recovery teleports")
	FileAccess.open(facts_path(),FileAccess.WRITE).store_string(JSON.stringify(facts,"\t"))
