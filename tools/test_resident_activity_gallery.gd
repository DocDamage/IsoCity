extends "res://tools/test_resident_activity_routines.gd"

func while_visited(doc: RefCounted,_building: Dictionary,mode: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args():return
	var coordinator: RefCounted=citizens.activities;var ready: bool=false
	for frame in 1800:
		await tick()
		if coordinator.scheduler.jobs.size()==2 and coordinator.scheduler.jobs.values().all(func(job: Dictionary):return job["state"]=="service") and not business.service.visits.is_empty():ready=true;break
	check(ready,"Both ordinary residents are using their actual furnished stations before visual review: "+mode)
	if not ready:return
	var source: Dictionary=doc.data.duplicate(true);var history_count: int=doc.undo_history.size();var world: Node=studio.worlds[mode];var camera: Node=world.camera
	var was_simple: bool=studio.consumer_shell.active;var size: Vector2i=root.size;var walking: bool=world.walking if mode=="3d" else false
	var center:=Vector3.ZERO
	for job in coordinator.scheduler.jobs.values():center+=job["position"]*.5
	var camera_position: Variant=camera.position;var old_zoom: Vector2=camera.zoom if mode=="2d" else Vector2.ONE
	var old_target: Vector3=world.target if mode=="3d" else Vector3.ZERO;var old_distance: float=world.distance if mode=="3d" else 0.0
	studio.set_process(false)
	for simple in [true,false]:
		studio.consumer_shell.set_active(simple,false)
		for dimensions in [Vector2i(1480,900),Vector2i(960,640)]:
			root.size=dimensions;studio.accessibility_settings.restore({"text_scale":1.5,"high_contrast":true,"large_targets":true} if dimensions.x==960 else {})
			if mode=="2d":camera.position=Vector2(center.x,center.y);camera.zoom=Vector2(3,3) if dimensions.x==1480 else Vector2(2,2)
			else:world.walking=false;world.target=Vector3(center.x,.8,center.z);world.distance=9;world.update_camera()
			await settle();RenderingServer.force_draw(false);RenderingServer.force_draw(false)
			var path: String="res://output/verification/asset_expansion/I14/room_%s_%s_%s_%d.png"%[destination_spec()["name"].replace("é","e"),mode,"simple" if simple else "precision",dimensions.x]
			check(root.get_texture().get_image().save_png(path)==OK,"Captured the actual furnished activity room: "+path)
	studio.accessibility_settings.restore({});root.size=size;studio.consumer_shell.set_active(was_simple,false)
	if mode=="2d":camera.position=camera_position;camera.zoom=old_zoom
	else:world.walking=walking;world.target=old_target;world.distance=old_distance;world.update_camera()
	studio.set_process(true);await settle()
	if doc.data!=source or coordinator.view.attached.size()!=2:
		FileAccess.open("res://output/verification/asset_expansion/I14/gallery_failure_"+mode+".json",FileAccess.WRITE).store_string(JSON.stringify({"change":preload("res://scripts/builder/document_delta.gd").between(source,doc.data),"source":source,"current":doc.data,"configuration":citizens.plan.get("settings",{}),"attached":coordinator.view.attached.keys(),"closed":coordinator.closed},"\t"))
	check(doc.data==source and doc.undo_history.size()==history_count and coordinator.view.attached.size()==2,"Temporary visual review preserves source, history and the two live resident bodies: "+mode)
