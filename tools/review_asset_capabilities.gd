extends SceneTree
const OUT="res://output/verification/asset_expansion/U05"
var studio: Control
var failures: int=0
func _initialize() -> void:call_deferred("run")
func settle() -> void:
	for frame in 12:await process_frame
	await RenderingServer.frame_post_draw
func capture(name: String) -> void:
	await settle()
	if root.get_texture().get_image().save_png(OUT+"/"+name+".png")!=OK:failures+=1;printerr("FAIL: capture "+name)
func check(value: bool,message: String) -> void:
	if not value:failures+=1;printerr("FAIL: "+message)
func reveal_capabilities() -> void:
	var ancestor: Node=studio.capability_note.get_parent()
	while ancestor:
		if ancestor is ScrollContainer:ancestor.ensure_control_visible(studio.capability_note)
		ancestor=ancestor.get_parent()
	await settle()
func pointer(point: Vector2,pressed: bool,move: bool=false,relative: Vector2=Vector2.ZERO) -> void:
	var event: InputEventMouse
	if move:
		var motion:=InputEventMouseMotion.new();motion.relative=relative;motion.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;event=motion
	else:
		var button:=InputEventMouseButton.new();button.button_index=MOUSE_BUTTON_LEFT;button.pressed=pressed;button.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;event=button
	event.position=point;event.global_position=point;Input.parse_input_event(event)
	await process_frame
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio)
	while not studio.enhancements_ready:await process_frame
	var ui: RefCounted=studio.consumer_shell;ui.dismiss_welcome()
	var doc: RefCounted=studio.current();doc.data=preload("res://scripts/builder/templates.gd").make("2d","blank")
	var item: Dictionary=doc.add("3d:HanX_Shop/Shop_Cafe",[0,0,0],"0");studio.changed();await settle()
	for size in [Vector2i(1480,900),Vector2i(960,640)]:
		root.size=size;ui.set_active(true,false);studio.asset_browser.clear_all_filters();ui.open_drawer("build");ui.query.text="cafe";ui.refresh_catalog();await settle()
		if studio.cards.get_child_count()>0:ui.card_scroll.ensure_control_visible(studio.cards.get_child(0).capability_note)
		await capture("simple_capability_cards_"+str(size.x))
		if size.x==1480 and studio.cards.get_child_count()>0:
			var card: Button=studio.cards.get_child(0);ui.card_scroll.ensure_control_visible(card);await settle()
			var point: Vector2=card.capability_note.get_global_rect().get_center()
			var before: Dictionary=doc.data.duplicate(true);var undo: int=doc.undo_history.size()
			await pointer(point,false,true);await pointer(point,true);await pointer(point+Vector2(4,0),true,true,Vector2(4,0));await pointer(point+Vector2(28,0),true,true,Vector2(24,0));await settle()
			var drag: Variant=root.gui_get_drag_data()
			check(root.gui_is_dragging() and drag is Dictionary and drag.get("asset_id")==card.asset_id,"Dragging from capability text starts the normal exact-ID asset drag")
			await pointer(point+Vector2(28,0),false);await settle()
			check(doc.data==before and doc.undo_history.size()==undo,"Cancelling capability-area drag leaves document and history unchanged")
		studio.asset_browser.show_asset(item["asset"]);await capture("capability_details_"+str(size.x));studio.asset_browser.dialog.hide();ui.close_overlays()
		studio.selected_uids.assign([item["uid"]]);studio.selected_uid=item["uid"];studio.refresh_controls();await settle();await capture("simple_capability_selection_"+str(size.x))
		ui.open_details("Selection");await settle();await reveal_capabilities();await capture("simple_capability_availability_"+str(size.x));ui.close_overlays()
		ui.set_active(false,false);studio.refresh_controls();await settle();await reveal_capabilities();await capture("precision_capability_selection_"+str(size.x))
	root.size=Vector2i(960,640);ui.set_active(true,false);studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true});ui.layout();ui.open_drawer("build");ui.query.text="cafe";ui.refresh_catalog();await capture("accessible_capability_cards_960")
	ui.close_overlays();studio.refresh_controls();await capture("accessible_capability_selection_960");ui.open_details("Selection");await settle();await reveal_capabilities();await capture("accessible_capability_availability_960")
	check(root.get_visible_rect().encloses(ui.details.get_global_rect()),"Enlarged capability details remain inside 960×640")
	studio.free();await process_frame;await process_frame
	print("Rendered capability review: 13 captures, %d failures"%failures);quit(1 if failures else 0)
