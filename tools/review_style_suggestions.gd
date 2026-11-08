extends SceneTree
const OUT="res://output/verification/asset_expansion/U09"
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
	var browser: RefCounted=studio.asset_browser;var controller: RefCounted=browser.compatibility;var ui: RefCounted=studio.consumer_shell;ui.dismiss_welcome()
	for dimensions in [Vector2i(1480,900),Vector2i(960,640)]:
		root.size=dimensions;ui.set_active(true,false);ui.open_drawer("build");browser.clear_all_filters();ui.group="Everything";ui.style_choice.select(1);ui.query.text="cafe";controller.anchor("3d:HanX_Shop/Shop_Cafe");ui.refresh_catalog();await settle()
		if studio.cards.get_child_count()>0:ui.card_scroll.ensure_control_visible(studio.cards.get_child(0).caption)
		await capture("simple_suggested_"+str(dimensions.x))
		check(root.get_visible_rect().encloses(ui.drawer.get_global_rect()) and ui.drawer.get_global_rect().encloses(controller.simple_choice.get_global_rect()),"Style order remains inside the simple drawer")
		controller.simple_choice.grab_focus();await key(KEY_SPACE);await key(KEY_DOWN);await key(KEY_ENTER);await settle()
		check(controller.include_all,"Keyboard selects All styles without hiding matches")
		await capture("simple_all_styles_"+str(dimensions.x))
		controller.set_include_all(false);browser.show_asset("2d:Coffee_Shop");await capture("cross_style_details_"+str(dimensions.x))
		var suggest: Button
		for button in browser.dialog.find_children("*","Button",true,false):
			if button.text=="Suggest this style":suggest=button
		check(suggest!=null,"Asset details expose an explicit style context action")
		if suggest:
			suggest.grab_focus();browser.preview_scroll.ensure_control_visible(suggest);await capture("style_action_"+str(dimensions.x))
			var authored: Dictionary=studio.current().data.duplicate(true);suggest.pressed.emit()
			check(controller.explicit_id=="2d:Coffee_Shop" and studio.current().data==authored and not browser.dialog.visible,"Style action changes only browsing context")
		controller.anchor("3d:HanX_Shop/Shop_Cafe");browser.dialog.hide()
		ui.set_active(false,false);studio.search.text="cafe";browser.filters_manual=true;browser.filters_expanded=true;browser.fit_filters();studio.refresh_library();await settle()
		var ancestor: Node=controller.choice.get_parent()
		while ancestor and not ancestor is ScrollContainer:ancestor=ancestor.get_parent()
		if ancestor:ancestor.ensure_control_visible(controller.choice)
		await capture("precision_suggested_"+str(dimensions.x))
		browser.filters_expanded=false;browser.fit_filters();await capture("precision_results_"+str(dimensions.x))
	root.size=Vector2i(960,640);ui.set_active(true,false);studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true});ui.open_drawer("build");ui.layout();await settle();await capture("accessible_style_order_960")
	check(root.get_visible_rect().encloses(ui.drawer.get_global_rect()) and ui.drawer.get_global_rect().encloses(controller.simple_choice.get_global_rect()),"Enlarged style order stays inside 960×640")
	controller.simple_choice.show_popup();await capture("accessible_style_menu_960");controller.simple_choice.get_popup().hide()
	if studio.cards.get_child_count()>0:
		ui.card_scroll.ensure_control_visible(studio.cards.get_child(0).artwork);await capture("accessible_style_art_960")
	studio.free();await process_frame;await process_frame
	print("Rendered style review: %d captures, %d failures"%[count,failures]);quit(1 if failures else 0)
