extends SceneTree
const OUT="res://output/verification/asset_expansion/U08"
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
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio)
	while not studio.enhancements_ready:await process_frame
	var browser: RefCounted=studio.asset_browser;var preview: RefCounted=browser.scale_preview
	studio.consumer_shell.dismiss_welcome()
	for dimensions in [Vector2i(1480,900),Vector2i(960,640)]:
		root.size=dimensions
		for mode in ["2d","3d"]:
			studio.switch_mode(mode)
			for pair in [["satellite","3d:Supplemental_Satellites/03_cubesat_3u"],["ship","3d:Supplemental_Spaceships_II/hammerhead_cruiser"],["tree","3d:HanX_Park/Tree_Pine"],["sprite","2d:Coffee_Shop"]]:
				browser.show_asset(pair[1]);preview.toggle.button_pressed=true;await settle()
				preview.view.select(1);preview.arrange();browser.preview_scroll.ensure_control_visible(preview.container);await capture("same_scale_"+pair[0]+"_"+mode+"_"+str(dimensions.x))
				if pair[0]=="satellite":
					preview.view.select(0);preview.arrange();await capture("fit_satellite_"+mode+"_"+str(dimensions.x))
				check(root.get_visible_rect().encloses(browser.dialog.get_visible_rect()),"Scale preview dialog stays in the window")
				browser.dialog.hide()
	root.size=Vector2i(960,640);studio.switch_mode("3d");studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true})
	browser.show_asset("2d:Coffee_Shop");preview.toggle.button_pressed=true;preview.view.select(0);preview.arrange();await settle();browser.preview_scroll.ensure_control_visible(preview.view);preview.view.grab_focus();await capture("accessible_scale_controls_960")
	var before: Dictionary=studio.current().data.duplicate(true)
	for key in [KEY_SPACE,KEY_DOWN,KEY_ENTER]:
		for pressed in [true,false]:
			var event:=InputEventKey.new();event.keycode=key;event.pressed=pressed;Input.parse_input_event(event);await process_frame
	check(preview.view.selected==1,"Keyboard selects Same scale without moving the editor")
	browser.preview_scroll.ensure_control_visible(preview.container);await capture("accessible_scale_view_960");browser.preview_scroll.ensure_control_visible(preview.note);await capture("accessible_scale_units_960")
	check(studio.current().data==before,"Comparison controls leave authored city unchanged")
	browser.dialog.hide();studio.free();await process_frame;await process_frame
	print("Rendered scale review: %d captures, %d failures"%[count,failures]);quit(1 if failures else 0)
