extends SceneTree

const Plan = preload("res://scripts/builder/blueprint_plan.gd")
const Doc = preload("res://scripts/builder/document.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:
		failures+=1
		print("FAIL: "+message)

func normalized(data: Dictionary) -> Variant:
	return JSON.parse_string(JSON.stringify(data))

func run() -> void:
	var scene: Node=load("res://city.tscn").instantiate()
	root.add_child(scene)
	for frame in 8: await physics_frame
	var library: RefCounted=scene.exploration.library
	var source: Dictionary=scene.studio_data
	var mode: String=source["mode"]
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://expected_assembly.json"))
	check(Doc.valid(source,mode,library),"Relocated package uses an independently valid city source.")
	check(scene.find_children("BlueprintProposals","",true,false).is_empty(),"Game scene excludes editor ghosts.")
	check(scene.city_instances.size()==source["objects"].size(),"Game scene contains exactly the built objects.")
	var result: Dictionary=source
	if not source.get("blueprints",[]).is_empty():
		var plans: Array=source["blueprints"]
		check(library.assets.has("3d:HanX_School/Teacher_Desk"),"The pending-only furnished asset loads from the portable library.")
		check(plans.size()==1 and plans[0]["kind"]=="assembly","Deferred assembly survived independent export.")
		check(Plan.rectangles(plans[0],mode,library).size()==10,"All object and road footprints resolve with the relocated dependencies.")
		var preview: Dictionary=Plan.construct(source,[plans[0]["uid"]],library)
		check(preview["ok"] and source["blueprints"].size()==1,"Independent package can review the authored proposal without mutation.")
		if preview["ok"]:
			result=preview["data"]
			result["economy_account"]=preview["quote"]["account"]
	check(normalized(result)==expected,"The relocated candidate matches the exact committed source and account.")
	check(result["roads"].size()==6,"All road profiles and cells remain in the independent source.")
	var building: Dictionary={}
	for object in result["objects"]:
		if object["asset"]=="3d:HanX_School/School_Building" and object["uid"].begins_with("assembly_"):
			building=object
			break
	check(not building.is_empty(),"The copied classroom retains its distinct building identity.")
	if not building.is_empty():
		var room: Dictionary=building["interior"]
		var upper: Dictionary=room["floors"][0]
		check(room["floor_links"][0]["upper"]==upper["uid"],"The copied stair still links to its remapped floor.")
		var props: Array=upper["room"]["objects"]
		check(props[1]["prop"]["target"]==props[2]["uid"],"The copied switch still targets its own appliance.")
		if source.get("blueprints",[]).is_empty():
			var world: Node=scene
			var visit: Node=scene.exploration
			world.player.set_physics_process(false)
			world.player.teleport_to(visit.entrance(scene.city_instances[building["uid"]]))
			var event:=InputEventKey.new()
			event.keycode=KEY_E
			event.pressed=true
			scene._unhandled_input(event)
			for frame in 8: await physics_frame
			check(visit.interior!=null and visit.interior_uid==building["uid"],"Actual Interact opens the copied classroom in the relocated project.")
			if visit.interior: visit.leave_interior()
	scene.free()
	await process_frame
	print("PORTABLE FUNCTIONAL ASSEMBLY: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
