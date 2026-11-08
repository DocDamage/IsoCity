extends SceneTree
const OUT="res://output/verification/asset_expansion/U15/"
const Plan=preload("res://scripts/builder/asset_collections.gd")
var studio: Control
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func settle() -> void:
	for frame in 20:await process_frame
func key(code: Key) -> void:
	for pressed in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.pressed=pressed;Input.parse_input_event(event);await process_frame
func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw;check(root.get_texture().get_image().save_png(OUT+name+".png")==OK,"Retained actual collection interface: "+name)
func focus(control: Control) -> void:
	control.grab_focus()
	var parent: Node=control.get_parent()
	while parent and not parent is Window:
		if parent is ScrollContainer:parent.ensure_control_visible(control)
		parent=parent.get_parent()
	await settle()
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT);FileAccess.open(OUT+".gdignore",FileAccess.WRITE).close();studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio);await settle();await settle();studio.consumer_shell.dismiss_welcome()
	var tools: RefCounted=studio.asset_browser.collections;var fixture: Dictionary=Plan.create("My workshop references")["data"];fixture["entries"]=[Plan.asset_entry("3d:HanX_School/Student_Chair",studio.library)["entry"],{"kind":"asset","id":"2d:Missing_Collection_Table_Fixture","name":"Remembered work table"}];tools.local.put(fixture);tools.select_filter(fixture["uid"])
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		for simple in [true,false]:
			studio.consumer_shell.set_active(simple,false)
			for setting in [{"size":Vector2i(1480,900),"large":false},{"size":Vector2i(960,640),"large":false},{"size":Vector2i(960,640),"large":true}]:
				root.size=setting["size"];studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true} if setting["large"] else {});await settle();var name: String=mode+"_"+("simple" if simple else "precision")+"_"+str(root.size.x)+("_large" if setting["large"] else "");var digest: String=studio.content_digest();var personal: Dictionary=tools.local.state.duplicate(true)
				tools.show_manager();await settle();check(tools.dialog.visible and Rect2(Vector2.ZERO,Vector2(root.size)).encloses(Rect2(Vector2(tools.dialog.position),Vector2(tools.dialog.size))),"Manager fits supported screen: "+name)
				check(tools.members.get_root().get_child_count()==2 and tools.members.get_root().get_first_child().get_icon(0)!=null,"Saved exact art and identifiable unavailable reference stay visible: "+name);await focus(tools.name_input);await capture("manager_"+name)
				tools.members.get_root().get_first_child().select(0);await focus(tools.members);await key(KEY_DOWN);await settle();check(tools.members.get_selected().get_metadata(0)["id"]=="2d:Missing_Collection_Table_Fixture" and studio.content_digest()==digest and tools.local.state==personal,"Keyboard reaches the identifiable missing reference without changing saved state: "+name);await capture("missing_reference_"+name)
				tools.scope_choice.select(1);tools.scope_choice.item_selected.emit(1);await settle();await focus(tools.restriction);var was: bool=tools.restriction.button_pressed;await key(KEY_SPACE);await settle();check(tools.restriction.button_pressed!=was and studio.content_digest()==digest,"Real Space-key activation changes only the explicit restriction draft: "+name)
				await focus(tools.save_button);await key(KEY_SPACE);await settle();check(tools.review_dialog.visible and tools.review_text.text.contains("Content restriction: ON") and studio.content_digest()==digest,"Real keyboard review remains read-only: "+name)
				check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(Rect2(Vector2(tools.review_dialog.position),Vector2(tools.review_dialog.size))),"Explicit restriction review fits supported screen: "+name);await capture("restriction_review_"+name)
				tools.review_dialog.get_cancel_button().grab_focus();await key(KEY_ESCAPE);await settle();check(not tools.review_dialog.visible and studio.content_digest()==digest and tools.local.state==personal,"Real Escape cancellation preserves common and personal state: "+name);tools.dialog.hide()
		studio.accessibility_settings.restore({})
	studio.free();await process_frame;await process_frame;print("COLLECTION ACCESSIBILITY: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
