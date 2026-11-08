extends SceneTree

const Plan = preload("res://scripts/builder/modular_building_plan.gd")
const Doc = preload("res://scripts/builder/document.gd")
const Connector = preload("res://scripts/builder/connector_plan.gd")
const Copy = preload("res://scripts/builder/owned_room_copy.gd")
const Protection = preload("res://scripts/builder/cooperative_plan.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const KIT = "hanx_training"

var library: RefCounted
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + message)

func cast(world: Node3D, start: Vector3, end: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(start, end, 1)
	query.hit_back_faces = true
	return world.get_world_3d().direct_space_state.intersect_ray(query)

func run() -> void:
	library = preload("res://scripts/builder/asset_library.gd").new()
	var kit: Dictionary = Plan.kits()[KIT]
	var blank: Dictionary = Templates.make("3d", "blank")
	var request: Dictionary = {"uid": Plan.new_identity(), "kit": KIT,
		"outline": [[-4,-4], [4,-4], [4,4], [-4,4]], "openings": {"x/0/4": "door", "x/0/-4": "window"}}
	var l_shape: Array = [[0,0], [12,0], [12,4], [4,4], [4,12], [0,12]]
	var concave: Dictionary = Plan.layout(kit, l_shape, {})
	check(concave.get("ok", false) and concave["parts"].has("floor/1/11") and not concave["parts"].has("floor/7/7"),
		"A concave outline fills its own footprint and leaves its exterior recess open.")
	var backwards: Array = l_shape.duplicate()
	backwards.reverse()
	check(Plan.layout(kit, backwards, {}).get("parts") == concave.get("parts"), "Reverse winding places the same complete kit.")
	check(not Plan.layout(kit, [[0,0], [8,0], [12,8], [0,8]], {})["ok"], "Diagonal edges are rejected.")
	check(not Plan.layout(kit, [[0,0], [6,0], [6,8], [0,8]], {})["ok"], "An incomplete module span is rejected.")
	check(not Plan.layout(kit, [[0,0], [8,0], [8,8], [4,8], [4,-4], [0,-4]], {})["ok"], "A crossing outline is rejected.")
	check(not Plan.layout(kit, request["outline"], {"x/-4/4":"door"})["ok"], "An opening cannot replace a corner.")
	check(not Plan.propose(Templates.make("2d","blank"),request,library)["ok"], "Pixel world reports the unsupported reverse-face kit.")
	check(not Plan.propose(blank,request,library,2.6)["ok"], "A short floor gap rejects the taller structure.")
	var hole := PackedVector2Array([Vector2(-1,3), Vector2(1,3), Vector2(1,5), Vector2(-1,5)])
	check(not Plan.propose(blank,request,library,INF,[hole])["ok"], "A cutout cannot interrupt the doorway or wall.")
	var roof: Dictionary = blank.duplicate(true)
	roof["objects"] = [{"uid":"roof","asset":kit["parts"]["floor"],"direction":"0","position":[0,1.6,0],"scale":1.0}]
	var obstructed: Dictionary = Plan.propose(roof,request,library)
	check(not obstructed["ok"] and "overhead" in obstructed["reason"], "Low meshes inside the outline prevent an unsafe review.")
	var proposal: Dictionary = Plan.propose(blank,request,library)
	check(proposal["ok"], "A valid outline compiles without changing the source. " + proposal.get("reason",""))
	if not proposal["ok"]:
		quit(1)
		return
	var placed: Dictionary = proposal["data"]
	var record: Dictionary = proposal["room"]
	check(blank["objects"].is_empty() and placed["objects"].size() == 24 and record["owned"].size() == 24,
		"Four corners, four wall bays and 16 fitted floor modules have one owned assembly.")
	check(placed["connections"].size() == 8 and Connector.retained(placed,placed["connections"]) == placed["connections"],
		"Real calibrated structural sockets link every side and corner.")
	check(Doc.valid(placed,"3d",library), "An authored modular room validates as ordinary project data.")
	var loaded: Dictionary = JSON.parse_string(JSON.stringify(placed))
	var reviewed: Dictionary = Plan.propose(loaded,request,library)
	check(reviewed.get("created",-1) == 0 and reviewed.get("removed",-1) == 0 and reviewed.get("preserved_edits",-1) == 0,
		"Save JSON normalization preserves procedural identity and does not recreate modules.")
	var disconnected: Dictionary = loaded.duplicate(true)
	disconnected["connections"].pop_back()
	check(Plan.propose(disconnected,request,library)["data"]["connections"].size() == 7,
		"Review does not recreate a joint manually disconnected between retained parts.")
	var cloned: Dictionary = Copy.room(loaded)
	var clone: Dictionary = cloned["modular_rooms"][0]
	check(clone["uid"] != record["uid"] and clone["owned"]["x/0/4"]["uid"] != record["owned"]["x/0/4"]["uid"] and clone["joints"].size() == 8,
		"Duplicating an owned room remaps module and joint identities.")
	check(Connector.retained(cloned,cloned["connections"]) == cloned["connections"] and Plan.propose(cloned,clone,library).get("created",-1) == 0,
		"The duplicate preserves connection geometry and can be edited independently.")
	var doc: RefCounted = Doc.new()
	doc.data = loaded.duplicate(true)
	var floor_uid: String = record["owned"]["floor/-3/-3"]["uid"]
	var missing_floor: Dictionary = doc.object(floor_uid)
	doc.data["objects"].erase(missing_floor)
	var wall_uid: String = record["owned"]["z/4/0"]["uid"]
	doc.object(wall_uid)["name"] = "My hand-edited wall"
	var edit: Dictionary = request.duplicate(true)
	edit["outline"] = [[-4,-4], [8,-4], [8,4], [-4,4]]
	var resized: Dictionary = Plan.propose(doc.data,edit,library)
	check(resized["ok"] and resized.get("preserved_edits",-1) == 2, "Resize preserves removed and edited parts. " + resized.get("reason",""))
	if resized["ok"]:
		var old: Dictionary = doc.data.duplicate(true)
		doc.checkpoint()
		doc.data = resized["data"]
		doc.finish_checkpoint()
		check(doc.object(wall_uid).get("name") == "My hand-edited wall" and doc.object(floor_uid).is_empty(),
			"Preserved edits remain visible and deleted floor modules are not regenerated.")
		check(doc.undo() and doc.data == old and doc.redo() and doc.data == resized["data"], "Resize is one exact Undo and Redo step.")
		var detached: Dictionary = Plan.detached(doc.data,request["uid"])
		check(detached["modular_rooms"].is_empty() and detached["objects"] == doc.data["objects"] and detached["connections"] == doc.data["connections"],
			"Detaching keeps all ordinary modules and their established joints.")
		check(not Protection.touched(doc.data,detached,library).is_empty(), "Detaching an assembly touches its protected footprint.")
	var world: Node3D = load("res://scripts/builder/world_3d.gd").new()
	world.library = library
	root.add_child(world)
	world.apply(placed)
	for frame in 4: await physics_frame
	check(cast(world, Vector3(0,1.1,3),Vector3(0,1.1,5)).is_empty(), "The doorway is physically open at torso height.")
	check(not cast(world, Vector3(1,1.1,3),Vector3(1,1.1,5)).is_empty(), "The same module has a solid doorway jamb.")
	check(cast(world, Vector3(0,1.4,-3),Vector3(0,1.4,-5)).is_empty(), "The window has an actual opening.")
	check(not cast(world, Vector3(0,.45,-3),Vector3(0,.45,-5)).is_empty(), "The window sill remains solid.")
	check(not cast(world, Vector3(1,.5,1),Vector3(1,-.2,1)).is_empty(), "The fitted floor includes collision.")
	world.free()
	await process_frame
	print("MODULAR BUILDING PLAN: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
