extends SceneTree
const OUT="res://output/verification/asset_expansion/U10/"
var studio: Control
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func settle() -> void:
	for frame in 24:await process_frame
func key(code: Key) -> void:
	for pressed in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.pressed=pressed;Input.parse_input_event(event);await process_frame
func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw;check(root.get_texture().get_image().save_png(OUT+name+".png")==OK,"Retained actual companion layout: "+name)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT);FileAccess.open(OUT+".gdignore",FileAccess.WRITE).close();studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio);await settle();await settle();studio.consumer_shell.dismiss_welcome()
	var tools: RefCounted=studio.companion_tools;var ui: RefCounted=studio.consumer_shell
	for mode in ["2d","3d"]:
		studio.switch_mode(mode);studio.current().data=preload("res://scripts/builder/templates.gd").make(mode,"blank");var source: Dictionary=studio.current().add("3d:HanX_School/Student_Desk",[0,0,0],"0",1);studio.changed();await settle()
		for simple in [true,false]:
			ui.set_active(simple,false)
			for size in [Vector2i(1480,900),Vector2i(960,640),Vector2i(960,640)]:
				var accessible: bool=size==Vector2i(960,640) and studio.accessibility_settings.text_scale==1.5
				# The repeated compact case explicitly exercises enlarged controls.
				var label: String=mode+"_"+("simple" if simple else "precision")+"_"+str(size.x)+("_large" if accessible else "")
				root.size=size;studio.selected_uid=source["uid"];studio.selected_uids.assign([source["uid"]]);studio.refresh_controls();tools.chosen();await settle()
				if accessible and not simple:
					tools.together.grab_focus();studio.accessibility_settings.root_scroll.ensure_control_visible(tools.panel);await settle()
				var before: Dictionary=studio.current().data.duplicate(true);var history: int=studio.current().undo_history.size();var canvas: Rect2=studio.canvas.get_global_rect();var tray: Rect2=tools.panel.get_global_rect()
				check(tools.panel.is_visible_in_tree() and canvas.encloses(tray),"Companion tray fits the supported canvas: "+label+" "+str(canvas)+" "+str(tray))
				check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(tray),"Visible companion controls fit the actual screen after keyboard scrolling: "+label)
				if simple:check(not tray.intersects(ui.context.get_global_rect()) and not tray.intersects(ui.dock.get_global_rect()),"Companion controls clear selected-object context and dock: "+label)
				await capture("tray_"+label);var dismiss: Button
				for button in tools.panel.find_children("*","Button",true,false):
					if button.accessibility_name=="Dismiss companion suggestions":dismiss=button
				dismiss.grab_focus();await key(KEY_SPACE);await settle();check(not tools.panel.visible and studio.current().data==before,"Keyboard dismissal is read-only and stays dismissed: "+label)
				tools.chosen();await settle();tools.together.grab_focus();await key(KEY_SPACE)
				for frame in 900:
					if tools.proposal.get("geometry_checked",false):break
					await process_frame
				check(tools.dialog.visible and tools.proposal.get("geometry_checked",false) and not tools.dialog.get_ok_button().disabled,"Keyboard opens a complete usable priced review: "+label)
				check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(Rect2(Vector2(tools.dialog.position),Vector2(tools.dialog.size))),"Review window fits the supported screen: "+label)
				await capture("review_"+label);tools.dialog.get_cancel_button().grab_focus();await key(KEY_ESCAPE);await settle();check(not tools.dialog.visible and studio.current().data==before and studio.current().undo_history.size()==history,"Keyboard cancellation preserves all content and history: "+label)
				studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true} if size==Vector2i(960,640) and not accessible else {})
			studio.accessibility_settings.restore({})
	studio.free();await process_frame;await process_frame;print("COMPANION ACCESSIBILITY: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
