extends "res://tools/test_resident_activity_routines.gd"
var service_people: Dictionary={}
var sprite_people: Dictionary={}
var maximum_sprite_error: float=0.0
func prepare_document(doc: RefCounted,mode: String) -> void:
	var room: Dictionary=preload("res://scripts/builder/interiors.gd").make(mode,"Raised classroom");room["objects"]=[];var furnishings: RefCounted=Doc.new();furnishings.data=room
	for x in [-3,3]:furnishings.add("3d:HanX_School/Student_Chair",[(x+2)*16,-40,0] if mode=="2d" else [x,2.12,-3],"0")
	room["terrain"]={"enabled":true,"bounds":[-8,-8,16,16]};room["terrain_vertices"]=[]
	for x in range(-8,9):
		for z in range(-8,9):room["terrain_vertices"].append({"cell":[x,z],"height":2})
	doc.data["objects"].filter(func(item: Dictionary):return item.get("citizen_role","")=="work")[0]["interior"]=room
func while_visited(_doc: RefCounted,_building: Dictionary,mode: String) -> void:
	if mode=="3d":check(citizens.residents.all(func(resident: Dictionary):return resident["actor"].global_position.y>1.9),"Both original native bodies enter the raised room on supported terrain")
func tick() -> void:
	await super.tick()
	var mode: String=citizens.dimension;var visit: Node=studio.worlds[mode].exploration
	if not visit.interior:return
	if mode=="2d":
		for resident in citizens.residents:
			var job: Dictionary=citizens.activities.scheduler.jobs.get(resident["id"],{})
			if job.get("state","")!="service":continue
			var actor: Node=resident["actor"];var room: Node=visit.room_world();var prop: Node=room.instances[job["station"]["uid"]];var prop_sprite: Sprite2D=prop.get_node("Sprite2D");var sprite: Sprite2D=actor.get_node("Sprite2D")
			var observed: Vector2=actor.global_position+sprite.global_transform.basis_xform(actor.interaction_visual_offset+actor.terrain_visual_offset)
			var expected: Vector2=room.objects.to_global(Vector2(job["station"]["point"].x,job["station"]["point"].y))+prop_sprite.global_transform.basis_xform(prop.terrain_visual_offset)+Vector2(0,.85*8)
			maximum_sprite_error=maxf(maximum_sprite_error,observed.distance_to(expected));sprite_people[resident["id"]]=true
		return
	for resident in citizens.residents:
		if citizens.activities.scheduler.jobs.get(resident["id"],{}).get("state","")=="service" and resident["actor"].global_position.y>1.9:service_people[resident["id"]]=true
func after_completed(_doc: RefCounted,mode: String) -> void:
	if mode=="2d":
		check(sprite_people.size()==2 and maximum_sprite_error<.1,"Both original seated sprites align with their actually terrain-raised source chairs: "+str(maximum_sprite_error))
		check(citizens.residents.all(func(resident: Dictionary):return resident["actor"].terrain_visual_offset==Vector2.ZERO),"Detaching removes the old room terrain's influence on exterior residents")
	if mode=="3d":
		check(service_people.size()==2,"Both original native bodies complete their actual activity on raised terrain")
		check(citizens.residents.all(func(resident: Dictionary):return resident["actor"].recovery_count==0),"Raised activity entry, service and exit need no recovery teleports")
