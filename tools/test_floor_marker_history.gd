extends SceneTree
const Document=preload("res://scripts/builder/document.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var library=preload("res://scripts/builder/asset_library.gd").new()
	for mode in ["2d","3d"]:
		var doc=Document.new(); doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
		var room: Dictionary=preload("res://scripts/builder/interiors.gd").make(mode,"Ground")
		room["floors"]=[{"uid":"upper","name":"Original upper","height":3,"room":preload("res://scripts/builder/interiors.gd").make(mode,"Upstairs")}]
		room["floor_entrances"]=[{"uid":"entry","floor":"upper","position":[12,3,12]}]
		doc.data["objects"]=[{"uid":"host","asset":"2d:House_Blue","direction":library.directions("2d:House_Blue")[0],"position":[0,0,0],"scale":1.0,"interior":room}]
		var world: Node=load("res://scripts/builder/world_"+mode+".gd").new(); world.library=library; root.add_child(world); world.apply(doc.data)
		var exploration: Node=world.exploration; var key: String="host:entry"; var marker: Node=exploration.marker_nodes[key]; var building: Node=world.instances["host"]; var origin: Variant=marker.position
		check(Document.valid(doc.data,mode,library),"Valid independently authored marker history fixture: "+mode)
		doc.checkpoint(); doc.object("host")["interior"]["floors"][0]["name"]="Renamed roof"; doc.finish_checkpoint(); world.apply(doc.data)
		check(marker.text.contains("Renamed roof"),"Room-only floor rename refreshes the exterior marker: "+mode)
		check(world.last_apply_updates==0 and world.instances["host"]==building and exploration.marker_nodes[key]==marker,"Marker refresh retains building and marker instances: "+mode)
		doc.undo(); world.apply(doc.data); check(marker.text.contains("Original upper"),"City Undo restores the floor marker title: "+mode)
		doc.redo(); world.apply(doc.data); check(marker.text.contains("Renamed roof"),"City Redo restores the edited title: "+mode)
		doc.checkpoint(); doc.object("host")["interior"]["floor_entrances"][0]["position"]=[19,3,16]; doc.finish_checkpoint(); world.apply(doc.data)
		var moved: Variant=preload("res://scripts/builder/floor_entrances.gd").outside(building,doc.object("host"),doc.object("host")["interior"]["floor_entrances"][0],mode,library)
		moved=moved-Vector2(8,18) if mode=="2d" else moved+Vector3.UP*1.5
		check(marker.position.distance_to(moved)<.001 and marker.position.distance_to(origin)>.1,"Room-only source edit moves the cached exterior marker: "+mode)
		doc.undo(); world.apply(doc.data); check(marker.position.distance_to(origin)<.001,"City Undo restores the source marker position: "+mode)
		doc.redo(); world.apply(doc.data); check(marker.position.distance_to(moved)<.001,"City Redo restores the moved source marker: "+mode)
		doc.checkpoint(); doc.object("host")["interior"]["floor_entrances"].clear(); doc.finish_checkpoint(); world.apply(doc.data)
		check(not exploration.marker_nodes.has(key) and not is_instance_valid(marker),"Room-only deletion removes its exterior marker: "+mode)
		doc.undo(); world.apply(doc.data); check(exploration.marker_nodes.has(key) and exploration.marker_nodes[key].position.distance_to(moved)<.001,"Undo restores a deleted marker at its actual source point: "+mode)
		doc.redo(); world.apply(doc.data); check(not exploration.marker_nodes.has(key),"Redo removes the restored marker: "+mode)
		check(world.last_apply_updates==0 and world.instances["host"]==building,"All room-only history leaves exterior geometry untouched: "+mode)
		world.free()
	print("FLOOR MARKER HISTORY: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
