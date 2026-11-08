extends "res://tools/test_resident_activity_routines.gd"

var facts: Dictionary={}
func facts_path() -> String:return "res://output/verification/asset_expansion/I14/elevator_routine_facts.json"
func capture_name(mode: String) -> String:return "elevator_live_"+mode+".png"
func expected_rides() -> int:return 4
func activity_floor() -> String:return "upper"

func prepare_document(doc: RefCounted,mode: String) -> void:
	var room: Dictionary=preload("res://scripts/builder/interiors.gd").make(mode,"Ground entrance");room["objects"]=[];var upper: Dictionary=room.duplicate(true);upper["title"]="Upstairs classroom"
	var furnishings: RefCounted=Doc.new();furnishings.data=upper
	for x in [-3,3]:furnishings.add("3d:HanX_School/Student_Chair",[(x+2)*16,-40,0] if mode=="2d" else [x,.12,-3],"0")
	room["floors"]=[{"uid":"upper","name":"Upstairs classroom","height":3,"room":upper}];room["floor_links"]=[{"uid":"lift","kind":"elevator","lower":"ground","upper":"upper","start":[0,0],"end":[0,0],"width":1.6}]
	doc.data["objects"].filter(func(item: Dictionary):return item.get("citizen_role","")=="work")[0]["interior"]=room
	facts[mode]={"rides":{},"people":{},"phases":{},"upper":false,"max_owners":0,"player_changed_floor":false,"previous":{},"max_vertical_step":0.0,"service_people":{}}

func tick() -> void:
	await super.tick()
	var mode: String=citizens.dimension;var visit: Node=studio.worlds[mode].exploration
	if not visit.interior or not citizens.activities:return
	var lift: Node=visit.interior.floor_stack.lifts["lift"];var result: Dictionary=facts[mode];var jobs: Array=citizens.activities.scheduler.jobs.values()
	result["max_owners"]=maxi(result["max_owners"],jobs.filter(func(job: Dictionary):return job["link_token"]!=0).size());result["upper"]=result["upper"] or jobs.any(func(job: Dictionary):return job["floor"]==activity_floor())
	result["player_changed_floor"]=result["player_changed_floor"] or visit.active_floor()!="ground"
	if lift.npc_token!=0 and is_instance_valid(lift.npc):
		result["rides"][str(lift.npc_token)]=true;result["people"][str(lift.npc.get_instance_id())]=true;result["phases"][lift.phase]=true
		if mode=="3d":
			var key: String=str(lift.npc_token);var y: float=lift.npc.global_position.y
			if result["previous"].has(key) and lift.phase=="moving":result["max_vertical_step"]=maxf(result["max_vertical_step"],absf(y-result["previous"][key]))
			result["previous"][key]=y
		if "--capture" in OS.get_cmdline_user_args() and not result.has("capture") and lift.phase=="moving" and lift.height>1.1 and lift.height<1.7:
			result["capture"]=capture_name(mode);await capture_lift(mode,lift,result["capture"])
	if mode=="3d":
		for resident in citizens.residents:
			if citizens.activities.scheduler.jobs.get(resident["id"],{}).get("state","")=="service" and resident["actor"].global_position.y>2.9:result["service_people"][resident["id"]]=true

func capture_lift(mode: String,lift: Node,name: String) -> void:
	var world: Node=studio.worlds[mode];var camera: Node=world.camera;var processing: bool=world.is_processing();var physics: bool=lift.is_physics_processing();var position: Variant=camera.position
	var studio_processing: bool=studio.is_processing();studio.set_process(false)
	var zoom: Vector2=camera.zoom if mode=="2d" else Vector2.ONE;var walking: bool=world.walking if mode=="3d" else false;var target: Vector3=world.target if mode=="3d" else Vector3.ZERO;var distance: float=world.distance if mode=="3d" else 0.0
	world.set_process(false);lift.set_physics_process(false)
	if mode=="2d":camera.position=lift.view.global_position+Vector2(0,-lift.height*8);camera.zoom=Vector2(5,5)
	else:world.walking=false;world.target=Vector3(lift.link["start"][0],1.1,lift.link["start"][1]);world.distance=7;world.update_camera()
	await settle();RenderingServer.force_draw(false);RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png("res://output/verification/asset_expansion/I14/"+name)==OK,"Captured the actual resident body halfway through controller-driven elevator motion: "+mode)
	if mode=="2d":camera.position=position;camera.zoom=zoom
	else:world.walking=walking;world.target=target;world.distance=distance;world.update_camera()
	lift.set_physics_process(physics);world.set_process(processing);studio.set_process(studio_processing)

func after_completed(_doc: RefCounted,mode: String) -> void:
	var result: Dictionary=facts[mode]
	check(result["rides"].size()==expected_rides() and result["people"].size()==2,"Both ordinary residents complete the required rendered controller trips: "+mode+" "+str(result))
	check(result["max_owners"]==1 and result["upper"],"One passenger at a time reaches the upstairs activity: "+mode)
	check(not result["player_changed_floor"],"All resident trips preserve the player's ground-floor context: "+mode)
	check(["closing","moving","arriving","opening"].all(func(phase: String):return result["phases"].has(phase)),"Resident routines exercise the controller's actual full trip phases: "+mode)
	if mode=="3d":check(result["max_vertical_step"]<.12 and result["service_people"].size()==2,"Both original bodies physically reach upstairs service with continuous elevator motion")
	FileAccess.open(facts_path(),FileAccess.WRITE).store_string(JSON.stringify(facts,"\t"))
