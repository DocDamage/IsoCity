extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio)
	for frame in 8: await process_frame
	while not studio.enhancements_ready: await process_frame
	for mode in ["2d","3d"]:
		studio.switch_mode(mode); var doc: RefCounted=studio.current(); doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
		var packs: Array=["Bonsai trees","Village buildings","Flipped Fleet EU","Camping gear kit"] if mode=="2d" else ["Arcade machines","Deciduous trees","Satellites","Spaceships II","Bonsai trees","Camping gear kit"]
		for index in packs.size():
			for id in studio.library.assets:
				var asset: Dictionary=studio.library.assets[id]
				if asset["data"].get("source_pack")==packs[index]:
					doc.add(id,[(index-1.5)*150,0,0] if mode=="2d" else [(index-2.5)*4,0,0],str(studio.library.directions(id)[0]),asset["data"].get("default_scale",1)); break
		studio.changed(); var world: Node=studio.worlds[mode]
		if mode=="2d": world.camera.position=Vector2(0,-30); world.camera.zoom=Vector2.ONE*1.5
		else: world.target=Vector3(0,2,0); world.distance=26; world.update_camera()
		for frame in 30: await process_frame
		RenderingServer.force_draw(false); RenderingServer.force_draw(false); world.get_viewport().get_texture().get_image().save_png("res://output/supplemental_first_"+mode+".png")
	studio.switch_mode("2d"); studio.current().data=preload("res://scripts/builder/templates.gd").make("2d","blank")
	var index: int=0
	for id in studio.library.assets:
		var info: Dictionary=studio.library.assets[id]["data"]
		if not id.begins_with("2d:Supplemental_") or info.get("kind")!="char": continue
		studio.current().add(id,[(index-4)*65,0,0],"SE",info.get("default_scale",1)); index+=1
	studio.changed(); var actors: Node=studio.worlds["2d"]
	actors.camera.position=Vector2(0,-20); actors.camera.zoom=Vector2.ONE*1.4
	for node in actors.instances.values():
		if node.has_method("_update_frame"): node.action="walk"; node._apply_direction(); node._update_animation(.35); node._update_frame()
	for frame in 12: await process_frame
	RenderingServer.force_draw(false); RenderingServer.force_draw(false); actors.get_viewport().get_texture().get_image().save_png("res://output/supplemental_characters.png")
	studio._command("supplemental_showcase",null)
	actors.camera.position=Vector2(0,-80); actors.camera.zoom=Vector2.ONE*.5
	for frame in 12: await process_frame
	RenderingServer.force_draw(false); RenderingServer.force_draw(false); root.get_texture().get_image().save_png("res://output/supplemental_showcase_ui.png")
	studio.switch_mode("3d"); studio.current().data=preload("res://scripts/builder/templates.gd").make("3d","blank"); index=0
	for id in studio.library.assets:
		var info: Dictionary=studio.library.assets[id]["data"]
		if not id.begins_with("2d:Supplemental_") or info.get("kind")!="char": continue
		studio.current().add(id,[(index%3-1)*3.5,0,(floori(index/3.0)-1)*3.5],"SE",info.get("default_scale",1)); index+=1
	studio.changed(); var mixed: Node=studio.worlds["3d"]; mixed.target=Vector3(0,.5,0); mixed.distance=12; mixed.update_camera()
	for frame in 30: await process_frame
	RenderingServer.force_draw(false); RenderingServer.force_draw(false); mixed.get_viewport().get_texture().get_image().save_png("res://output/supplemental_characters_3d.png")
	studio.free(); await process_frame; await process_frame; print("Supplemental rendered samples complete"); quit()
