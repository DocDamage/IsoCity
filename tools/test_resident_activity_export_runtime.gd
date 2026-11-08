extends SceneTree
var checks: int=0
var failures: int=0
var scene: Node
var citizens: Node
var business: Node
var mode: String
var kind: String
var trips: Dictionary={}
var people: Dictionary={}
var previous: Dictionary={}
var service_people: Dictionary={}
var max_owners: int=0
var max_vertical_step: float=0
var changed_player_floor: bool=false
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;print("FAIL: "+message)
func same_json(a: Dictionary,b: Dictionary) -> bool:return JSON.parse_string(JSON.stringify(a))==JSON.parse_string(JSON.stringify(b))
func settle() -> void:
	for frame in 10:await process_frame
	await physics_frame
func key(code: Key) -> void:
	root.gui_release_focus();var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=true;Input.parse_input_event(event);await process_frame;event=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=false;Input.parse_input_event(event);await settle()
func tick() -> void:
	await physics_frame;citizens.step(1.0/60);business.step(1.0/60)
	if not scene.exploration.interior or not citizens.activities:return
	var scheduler: RefCounted=citizens.activities.scheduler;var travel: RefCounted=citizens.activities.view.travel
	max_owners=maxi(max_owners,scheduler.jobs.values().filter(func(job: Dictionary):return job["link_token"]!=0).size());changed_player_floor=changed_player_floor or scene.exploration.active_floor()!="ground"
	for resident in citizens.residents:
		var id: String=resident["id"];var job: Dictionary=scheduler.jobs.get(id,{});var body: Node=resident["actor"]
		if mode=="3d" and job.get("state","")=="service" and body.global_position.y>2.9:service_people[id]=true
		if not travel.states.has(id):continue
		var token: String=str(job["link_token"]);trips[token]=true;people[id]=true
		if mode=="3d":
			if previous.has(token):max_vertical_step=maxf(max_vertical_step,absf(body.global_position.y-previous[token]))
			previous[token]=body.global_position.y
func run() -> void:
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://expected_activities.json"));mode=expected["source"]["mode"];kind=expected["kind"]
	check(not ProjectSettings.globalize_path("res://").replace("\\","/").to_lower().begins_with(expected["source_root"].to_lower()+"/"),"Verification runs outside the source checkout with its own resource root")
	scene=load("res://city.tscn").instantiate();root.add_child(scene);await settle();citizens=scene.citizens;business=scene.businesses;citizens.set_physics_process(false);business.set_physics_process(false);scene.player.set_physics_process(false);scene.economy.paused=true
	var source: Dictionary=expected["source"];var library: RefCounted=scene.exploration.library
	check(same_json(scene.studio_data,source) and same_json(scene.live_data,source),"Standalone scene retains all authored values independently of private activity state")
	check(preload("res://scripts/builder/document.gd").valid(scene.studio_data,mode,library),"Standalone document validates against its own included catalog")
	for id in expected["previews"]:
		check(FileAccess.file_exists(expected["previews"][id]) and preload("res://scripts/builder/model_preview.gd").meaningful(library.icon(id)),"Included model preview remains meaningful and compatible: "+id)
	check(citizens.residents.size()==2 and citizens.residents.all(func(resident: Dictionary):return is_instance_valid(resident["actor"])),"Standalone initialization creates the two configured original residents")
	var probe: Node=preload("res://scripts/builder/citizen_runtime.gd").new();scene.add_child(probe);probe.configure(preload("res://scripts/builder/templates.gd").make(mode,"blank"),library,{},scene.get_node("Objects"),false)
	check(not probe.plan["settings"]["enabled"] and not probe.plan["settings"]["interior_activities"] and probe.activities==null and probe.residents.is_empty(),"A fresh exported-runtime city keeps both citizen and interior simulation defaults disabled");probe.free()
	if not expected["enabled"]:
		for frame in 120:await tick()
		check(not scene.studio_data["citizens"].has("interior_activities") and citizens.activities==null and not scene.exploration.interior,"Legacy exports keep the omitted interior option disabled and create no room worlds")
		scene.free();await settle();print("RESIDENT ACTIVITY EXPORT RUNTIME legacy %s: %d checks, %d failures"%[mode,checks,failures]);quit(1 if failures else 0);return
	check(citizens.activities!=null and citizens.interior_activities_enabled(),"The explicit exported option initializes ordinary resident coordination")
	var ids: Array=citizens.residents.map(func(resident: Dictionary):return resident["actor"].get_instance_id());var children: int=scene.get_child_count();var arrived: bool=false
	for frame in 2400:
		await tick()
		if citizens.activities.scheduler.jobs.size()==2:arrived=true;break
	check(arrived and scene.get_child_count()==children and not scene.exploration.interior,"Ordinary standalone city routes begin both logical itineraries without instantiating unvisited rooms")
	if arrived:
		var jobs: Array=citizens.activities.scheduler.jobs.values().map(func(job: Dictionary):return job["id"]);scene.player.teleport_to(scene.exploration.entrance(scene.city_instances["work"]));await key(KEY_E)
		check(scene.walking and scene.exploration.interior!=null and scene.exploration.interior_uid=="work","The actual exported E interaction opens the occupied owned room")
		if scene.exploration.interior:
			check(citizens.activities.scheduler.jobs.values().map(func(job: Dictionary):return job["id"])==jobs and citizens.activities.view.attached.size()==2 and citizens.residents.map(func(resident: Dictionary):return resident["actor"].get_instance_id())==ids,"Player entry binds the original two bodies and jobs in the standalone room")
			scene.player.teleport_to(Vector2(128,0) if mode=="2d" else Vector3(5,.2,4));var completed: bool=false
			for frame in 3600:
				await tick()
				if citizens.activities.history.size()==2:completed=true;break
			check(completed and citizens.activities.history.all(func(value: Dictionary):return value["state"]=="complete"),"Both standalone residents finish station service and return through the actual floor link: "+str(citizens.activities.history))
			check(business.service.history.size()==2 and business.service.inventory.size()==2,"Standalone capacity-one service grants each original resident exactly one item")
			check(trips.size()==4 and people.size()==2 and max_owners==1 and not changed_player_floor,"All four native trips preserve original bodies, single-flight capacity and the player's ground-floor context")
			if mode=="3d":check(service_people.size()==2 and max_vertical_step<(.4 if kind=="stairs" else .15),"Both original native bodies physically reach upstairs service with bounded continuous steps")
			check(citizens.activities.scheduler.reservations.entries.is_empty() and citizens.residents.map(func(resident: Dictionary):return resident["actor"].get_instance_id())==ids,"Completed exported routines retain original bodies and release all station/transport ownership")
			check(same_json(scene.live_data,source) and scene.live_data["economy_account"]["cash"]==100000,"Ordinary standalone activity changes no authored rooms, geometry, source IDs or treasury")
			scene.exploration.leave_interior();await settle()
			for frame in 600:await tick()
			check(citizens.activities.history.size()==2 and business.service.history.size()==2,"Standalone residents do not immediately repeat the completed daily slot")
	scene.free();await settle();print("RESIDENT ACTIVITY EXPORT RUNTIME %s %s: %d checks, %d failures"%[kind,mode,checks,failures]);quit(1 if failures else 0)
