extends "res://tools/test_resident_activity_routines.gd"
var layout_facts: Array=[]
func press_key(viewport: Viewport,code: Key) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=true;viewport.push_input(event);await process_frame;event=event.duplicate();event.pressed=false;viewport.push_input(event);await settle()
func while_visited(doc: RefCounted,_building: Dictionary,mode: String) -> void:
	var coordinator: RefCounted=citizens.activities;var ready: bool=false
	for frame in 1800:
		await tick()
		if coordinator.scheduler.jobs.size()==2 and coordinator.scheduler.jobs.values().all(func(job: Dictionary):return job["state"]=="service") and not business.service.visits.is_empty():ready=true;break
	check(ready,"Both original residents are seated for runtime HUD verification: "+mode)
	if not ready:return
	var source: Dictionary=doc.data.duplicate(true);var history: int=doc.undo_history.size();var world: Node=studio.worlds[mode];var visit: Node=world.exploration;var actor_ids: Array=citizens.residents.map(func(resident: Dictionary):return resident["actor"].get_instance_id());var job: Dictionary=coordinator.scheduler.jobs.values()[0];var approach: Vector3=job["station"]["approach"]
	var old_position: Variant=world.player.position
	world.player.teleport_to(Vector2(approach.x,approach.y) if mode=="2d" else world.player.get_parent().to_local(visit.room_world().objects.to_global(approach)));await settle()
	var candidate: Dictionary=preload("res://scripts/builder/prop_plan.gd").nearby(visit)
	check(not candidate.is_empty() and candidate["item"]["uid"]==job["station"]["uid"],"Actual player approach selects the occupied resident chair: "+mode)
	studio.control_settings.execute("interact");await settle()
	check(visit.props.active.is_empty() and visit.props.notice.contains("already in use") and coordinator.scheduler.reservations.current(job["station_key"]).get("token",0)==job["station_token"],"Player interaction explains occupied station without stealing resident ownership: "+mode)
	world.player.teleport_to(old_position)
	studio.set_process(false)
	var original_size: Vector2i=root.size;var simple_before: bool=studio.consumer_shell.active
	for simple in [true,false]:
		studio.consumer_shell.set_active(simple,false)
		for dimensions in [Vector2i(1480,900),Vector2i(960,640)]:
			root.size=dimensions
			for scale_value in [1.0,1.5]:
				studio.accessibility_settings.restore({"text_scale":scale_value,"large_targets":scale_value>1.0,"high_contrast":scale_value>1.0});await settle();studio.interior_tools.refresh();studio.consumer_shell.tick(0);await settle();studio.business_tools.tick(0);business.update_ui();await settle()
				var label: String=destination_spec()["name"].replace("é","e")+"_"+mode+"_"+("simple" if simple else "precision")+"_"+str(dimensions.x)+"_"+str(int(scale_value*100));var viewport:=Rect2(Vector2.ZERO,Vector2(root.size));var panel_rect: Rect2=business.panel.get_global_rect()
				if not simple:panel_rect.position+=studio.canvas.get_global_rect().position
				var canvas: Rect2=studio.canvas.get_global_rect().intersection(viewport)
				check(business.panel.visible and viewport.encloses(panel_rect),"Actual runtime business HUD stays inside the window: "+label+" "+str(panel_rect))
				check(canvas.size.x>=240 and canvas.size.y>=200,"Actual occupied-room canvas remains usable: "+label+" "+str(canvas))
				if simple:
					check(not panel_rect.intersects(studio.consumer_shell.room_navigation.get_global_rect()) and not panel_rect.intersects(studio.consumer_shell.hint_panel.get_global_rect()),"Runtime activities do not cover room navigation or walking hints: "+label)
					check(not studio.consumer_shell.status_panel.visible or not panel_rect.intersects(studio.consumer_shell.status_panel.get_global_rect()),"Runtime activities leave economy and shared status readable: "+label)
				var button: Button=business.buttons.get_child(0);button.grab_focus();await settle();await press_key(business.get_viewport(),KEY_SPACE);business.update_ui();await settle()
				check(business.service.result("player").get("state","")=="queued" and button.disabled,"Actual keyboard activation joins the capacity-one queue behind the resident: "+label)
				business.cancel_button.grab_focus();await settle();var focused: Rect2=business.cancel_button.get_global_rect();var scroll_rect: Rect2=business.scroll.get_global_rect()
				check(business.cancel_button.has_focus() and scroll_rect.encloses(focused) and (scale_value==1.0 or focused.size.y>=44),"Focus reveals the complete cancel button with enlarged target: "+label)
				await press_key(business.get_viewport(),KEY_SPACE);business.update_ui();await settle()
				check(business.service.result("player").get("state","")=="cancelled" and coordinator.scheduler.jobs.size()==2 and coordinator.scheduler.reservations.current(job["station_key"]).get("token",0)==job["station_token"],"Keyboard Cancel releases only the player's request: "+label)
				var after: Rect2=business.cancel_button.get_global_rect()
				var screen_button: Rect2=after
				if not simple:screen_button.position+=studio.canvas.get_global_rect().position
				check(business.scroll.get_global_rect().encloses(after) and viewport.encloses(screen_button),"Content changes keep the focused cancel action fully visible: "+label+" "+str(screen_button))
				check(simple or not panel_rect.intersects(studio.consumer_shell.expert_return.get_global_rect()),"Precision activity actions leave the return-to-Simple button clear: "+label)
				layout_facts.append({"name":label,"canvas":str(canvas),"panel":str(panel_rect),"scroll":str(scroll_rect),"focused":str(focused)})
				if "--capture" in OS.get_cmdline_user_args():
					RenderingServer.force_draw(false);RenderingServer.force_draw(false);check(root.get_texture().get_image().save_png("res://output/verification/asset_expansion/I14/runtime_"+label+".png")==OK,"Captured actual occupied-room HUD: "+label)
	studio.accessibility_settings.restore({});root.size=original_size;studio.consumer_shell.set_active(simple_before,false);studio.set_process(true);await settle()
	check(doc.data==source and doc.undo_history.size()==history and citizens.residents.map(func(resident: Dictionary):return resident["actor"].get_instance_id())==actor_ids and coordinator.view.attached.size()==2,"All runtime UI operations preserve source, history, treasury and original residents: "+mode)
	FileAccess.open("res://output/verification/asset_expansion/I14/runtime_layout_"+destination_spec()["name"].replace("é","e")+"_facts.json",FileAccess.WRITE).store_string(JSON.stringify(layout_facts,"\t"))
