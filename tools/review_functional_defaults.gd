extends SceneTree
# Reproducible counter/entrance review; does not open or save user projects.
const OUTPUT = "res://output/verification/asset_expansion/I01"
const FACILITIES = ["3d:HanX_School/School_Building", "3d:HanX_GasStation/Repair_Garage", "2d:city_Hall", "2d:Public_Library"]
var studio: Control

func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 12: await process_frame
	await RenderingServer.frame_post_draw

func capture(name: String) -> void:
	await settle()
	if studio.consumer_shell.active:
		var panel: Control = studio.business_tools.managers["3d"].panel
		for control in [studio.consumer_shell.header,studio.consumer_shell.header_actions,studio.consumer_shell.hint_panel,studio.consumer_shell.dock]:
			if control.visible and panel.get_rect().intersects(control.get_rect()): printerr("Counter overlaps shell control: ", name); quit(1); return
	var error: Error = root.get_texture().get_image().save_png(OUTPUT + "/" + name + ".png")
	if error != OK: printerr("Capture failed: ", name); quit(1)

func prepare(id: String) -> void:
	studio.set_walking(false)
	studio.current().data = preload("res://scripts/builder/templates.gd").make("3d", "blank")
	var item: Dictionary = studio.current().add(id, [0,0,0], "SE" if id.begins_with("2d:") else "0")
	studio.changed(); await settle()
	studio.set_walking(true)
	var world: Node = studio.worlds["3d"]
	world.player.set_physics_process(false)
	world.player.teleport_to(world.exploration.entrance(world.instances[item["uid"]]))
	var manager: Node = studio.business_tools.managers["3d"]
	manager.set_physics_process(false); manager.hour = 12.5
	manager.update_ui()
	if not manager.available(item["uid"]) or not manager.player_near(item["uid"]): printerr("Counter unavailable: ", id); quit(1)

func run() -> void:
	studio = load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled = false; root.add_child(studio)
	while not studio.enhancements_ready: await process_frame
	if studio.consumer_shell == null: printerr("Run with --consumer-ui"); quit(1); return
	studio.consumer_shell.dismiss_welcome(); studio.consumer_shell.close_overlays()
	studio.switch_mode("3d")
	for size in [Vector2i(1480,900), Vector2i(960,640)]:
		root.size = size
		for simple in [true,false]:
			studio.consumer_shell.set_active(simple,false)
			await prepare(FACILITIES[0])
			await capture("counter_" + ("simple_" if simple else "precision_") + str(size.x))
	root.size = Vector2i(1480,900); studio.consumer_shell.set_active(true,false)
	for index in FACILITIES.size():
		await prepare(FACILITIES[index]); await capture("facility_" + str(index))
		var texture: Texture2D = studio.library.icon(FACILITIES[index])
		if texture: texture.get_image().save_png(OUTPUT + "/facility_icon_" + str(index) + ".png")
	root.size = Vector2i(960,640)
	studio.accessibility_settings.restore({"text_scale":1.5,"high_contrast":true,"large_targets":true})
	await prepare(FACILITIES[0]); await capture("counter_accessible_960")
	var manager: Node = studio.business_tools.managers["3d"]
	if manager.buttons.get_child(0).custom_minimum_size.y < 44: printerr("Counter click target is too small"); quit(1); return
	studio.free(); await process_frame; await process_frame
	print("Captured four reviewed facilities and simple/precision counter UI at desktop and 960x640"); quit()
