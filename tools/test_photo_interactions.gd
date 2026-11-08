extends SceneTree
const Prop=preload("res://scripts/builder/prop_plan.gd")
var checks: int=0
var failures: int=0
var studio: Control
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle(frames: int=6) -> void:
	for frame in frames: await physics_frame
	await process_frame
func approach(world: Node,item: Dictionary) -> void:
	var context: Dictionary=Prop.context(world.exploration); context["node"]=world.instances[item["uid"]]; context["item"]=item; context["profile"]=Prop.profile(item)
	world.player.teleport_to(world.player.get_parent().to_local(Prop.ground_point(context,world.exploration,"approach")))
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode); var doc: RefCounted=studio.current(); var world: Node=studio.worlds[mode]; var exploration: Node=world.exploration; var photo: Node=exploration.photo; var props: Node=exploration.props
		var asset: String="2d:Washing_Machine" if mode=="2d" else "3d:HanX_Shop/Vending_Machine"; var machine: Dictionary={"uid":"photo_machine","asset":asset,"position":preload("res://scripts/builder/traffic_plan.gd").world(Vector2(30,20),mode),"direction":studio.library.directions(asset)[0],"scale":1.0,"prop":{"duration":.5}}
		doc.data["objects"].append(machine); studio.changed(); await settle(); var before: Dictionary=doc.data.duplicate(true); var history: int=doc.undo_history.size(); studio.set_walking(true)
		var bench: Dictionary=doc.data["objects"].filter(func(item: Dictionary)->bool:return Prop.profile(item).get("kind","")=="seat")[0]; approach(world,bench); await settle(); exploration.interact()
		check(not props.active.is_empty() and not world.player.is_physics_processing(),"Normal seat interaction is active before photo mode: "+mode)
		photo.start(); photo.configure({"hide_avatar":true}); photo.navigate(.1,Vector3.RIGHT); await settle(); exploration.interact()
		check(photo.active and not props.active.is_empty() and not world.player.visible,"Photo camera preserves seated pose and blocks accidental interaction release: "+mode); photo.stop()
		check(not world.player.is_physics_processing() and world.player.visible and not props.active.is_empty(),"Returning from photo mode preserves seated controller ownership: "+mode); exploration.interact(); check(world.player.is_physics_processing() and props.active.is_empty(),"Normal Interact restores walking after seated photo: "+mode)
		approach(world,machine); await settle(); exploration.interact(); check(not props.active.is_empty() and props.active["profile"]["kind"]=="appliance","Timed appliance starts through normal interaction: "+mode); photo.start(); await settle(50)
		check(photo.active and props.active.is_empty() and not props.inventory.is_empty(),"Timed activity can finish while photo camera remains active: "+mode); photo.stop()
		check(world.player.is_physics_processing() and exploration.walk_allowed(),"Photo return restores movement when the original timed interaction has completed: "+mode)
		studio.set_walking(false); var car: Dictionary=doc.data["objects"].filter(func(item: Dictionary)->bool:return not preload("res://scripts/builder/driving_plan.gd").profile(item).is_empty())[0]; studio.selected_uids.assign([car["uid"]]); studio.selected_uid=car["uid"]; studio.driving_tools.stamp=0; studio.driving_tools.refresh(); studio.driving_tools.preview_selected(); await settle()
		var driving: Node=exploration.driving; check(not driving.active.is_empty(),"Actual selected-vehicle control enters a vehicle before photography: "+mode)
		if not driving.active.is_empty():
			var point: Vector2=driving.active["point"]; driving.speed=4; photo.start(); await settle(12); check(driving.active["point"]==point and driving.speed==0,"Photo mode stops and retains the occupied vehicle: "+mode); photo.stop()
			check(not driving.active.is_empty() and not world.player.is_physics_processing() and not world.player.visible,"Photo return preserves driving ownership and hidden avatar: "+mode); exploration.interact(); check(driving.active.is_empty() and world.player.is_physics_processing() and world.player.visible,"Vehicle exit remains usable after photography: "+mode)
		photo.start_recording()
		for index in 181: photo.advance(1)
		check(not photo.recording and photo.pending_take and photo.record_elapsed==180 and photo.recorded.size()<=1800 and photo.recorded[-1]["time"]==180,"Recording duration limit ends in a bounded recoverable take: "+mode)
		studio.set_walking(false); check(doc.data==before and doc.undo_history.size()==history,"Photo interactions and recording limits preserve authored city content/history: "+mode)
		var path: String="res://output/photo_reload_"+mode+".isocity.json"; check(studio.write_project(path),"Ordinary project save works after photo interactions: "+mode); check(studio.load_project(path) and not world.exploration.photo.pending_take and world.exploration.photo.recorded.is_empty(),"Loading a project clears unsaved camera takes from the previous session: "+mode)
		check(studio.documents[mode].data["objects"].size()==before["objects"].size() and studio.documents[mode].object("photo_machine")["prop"]["duration"]==.5,"Reload retains the authored objects and interaction settings: "+mode)
	studio.free(); await process_frame; print("PHOTO INTERACTIONS: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
