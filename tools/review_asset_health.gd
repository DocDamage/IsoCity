extends SceneTree
const OUT="res://output/verification/asset_expansion/U17"
const SHIP="3d:Supplemental_Spaceships_II/belly_bay_bomber"
const CHAIR="3d:HanX_School/Student_Chair"
var studio: Control
var count: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func settle() -> void:
	for frame in 12:await process_frame
	await RenderingServer.frame_post_draw
func check(value: bool,message: String) -> void:
	if not value:failures+=1;printerr("FAIL: "+message)
func capture(name: String) -> void:
	await settle();count+=1
	if root.get_texture().get_image().save_png(OUT+"/"+name+".png")!=OK:failures+=1;printerr("FAIL: capture "+name)
func key(code: Key) -> void:
	for pressed in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.pressed=pressed;Input.parse_input_event(event);await process_frame
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio)
	while not studio.enhancements_ready:await process_frame
	var ui: RefCounted=studio.consumer_shell;var health: RefCounted=studio.asset_browser.health_tools;ui.dismiss_welcome()
	var original: String=studio.library.assets[SHIP]["data"]["preview_path"];var target: String=OUT+"/review_preview.png"
	var flat:=Image.create_empty(192,192,false,Image.FORMAT_RGBA8);flat.fill(Color(.2,.4,.6));flat.save_png(target);studio.library.assets[SHIP]["data"]["preview_path"]=target
	health.repair.allowed_roots.append(OUT+"/");health.repair.backup_root=OUT+"/review_backups"
	var reference: String=""
	for id in studio.library.assets:
		if studio.library.assets[id]["data"].get("content_kind")=="atlas":reference=id;break
	for dimensions in [Vector2i(1480,900),Vector2i(960,640)]:
		root.size=dimensions
		for simple in [true,false]:
			ui.set_active(simple,false)
			if simple:
				ui.open_drawer("build");ui.refine.show();ui.layout();await settle()
				for child in ui.refine_controls.get_children():
					if child is Button and child.text=="Library health…":child.grab_focus();ui.refine.ensure_control_visible(child)
				await capture("health_entry_simple_"+str(dimensions.x))
			health.open();health.scan();health.audit.ids=[SHIP,CHAIR,reference]
			while health.audit.active:await process_frame
			health.refresh_list(true);health.scroll.scroll_vertical=0;await capture("health_"+("simple_" if simple else "precision_")+str(dimensions.x))
			check(root.get_visible_rect().encloses(Rect2(Vector2(health.dialog.position),Vector2(health.dialog.size))),"Health window fits the current viewport")
			await health.prepare_repair();health.scroll.ensure_control_visible(health.pictures);await capture("health_repair_"+("simple_" if simple else "precision_")+str(dimensions.x))
			check(health.after.texture!=null and not health.apply_button.disabled,"Before/after artwork and an explicit Apply action are available")
			health.dialog.hide()
	root.size=Vector2i(960,640);studio.switch_mode("3d");ui.set_active(true,false);studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true})
	health.open();health.scan();health.audit.ids=[SHIP,CHAIR,reference]
	while health.audit.active:await process_frame
	health.refresh_list(true);health.scroll.scroll_vertical=0;await capture("health_accessible_top_960")
	await settle();health.render_button.grab_focus();health.scroll.ensure_control_visible(health.render_button);await key(KEY_ENTER)
	while health.busy:await process_frame
	health.scroll.ensure_control_visible(health.apply_button);await capture("health_accessible_repair_960")
	check(health.after.texture!=null and root.get_visible_rect().encloses(health.apply_button.get_global_rect()),"Keyboard preparation and enlarged Apply remain reachable by scrolling")
	var authored: Dictionary=studio.current().data.duplicate(true);health.apply_button.grab_focus();await key(KEY_ENTER);await settle();health.scroll.scroll_vertical=0;await capture("health_accessible_applied_960")
	check(studio.current().data==authored,"Keyboard repair affects no authored city fields")
	studio.library.assets[SHIP]["data"]["preview_path"]=original;studio.free();await process_frame;await process_frame
	print("Rendered library health: %d captures, %d failures"%[count,failures]);quit(1 if failures else 0)
