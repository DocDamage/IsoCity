extends SceneTree

# This file is copied into an extracted ZIP by verify_portable.py. Every res://
# reference below resolves only against that separate project, never the source.
var checks: int = 0
var failures: int = 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; print("FAIL: " + message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var city: Node = load("res://city.tscn").instantiate()
	root.add_child(city)
	for i in 4: await process_frame
	city.player.set_physics_process(false)
	var exploration: Node = city.exploration
	if city.dimension == "3d":
		check(city.get_node("Foundation").collision_layer == 2 and city.get_node("Foundation").visible,"Exterior floor collision and visibility survive export from an active room visit")
		check(city.find_children("*","WorldEnvironment",false,false)[0].environment != null,"Exterior environment survives export from an active room visit")
	else:
		check(city.get_node("Lighting").color == Color.WHITE,"Exterior daylight survives export from a night room visit")
	check(exploration != null and exploration.instances.size() == city.studio_data["objects"].size(),"All exterior objects loaded from relocated project")
	var library: RefCounted = exploration.library
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://city-source.json"))
	for mode in ["2d","3d"]:
		check(preload("res://scripts/builder/document.gd").valid(source["documents"][mode],mode,library),"Editable source validates with packaged asset definitions: " + mode)
	var painted: Dictionary = city.studio_data["objects"].filter(func(item: Dictionary) -> bool: return item["uid"] == "portable_painted")[0]
	var pattern: Dictionary = painted["colors"][0]["pattern"]
	check(load(pattern["texture"]) is Texture2D,"Appearance-only texture imports in relocated project")
	var sprite: Sprite2D = preload("res://scripts/builder/part_colors.gd").sprite_for(exploration.instances["portable_painted"])
	check(sprite.texture is ImageTexture and sprite.texture.has_meta("paint_base"),"Painted sprite appearance is reapplied")
	check(city.studio_data["roads"].size() == 2,"Styled road records retained")
	for asset in library.assets.values():
		var instance: Node = load(asset["path"]).instantiate()
		check(instance != null,"Packaged asset instantiates: " + asset["id"])
		instance.free()
		for view in asset.get("data",{}).get("directions",{}).values():
			var file: String = view.get("file","")
			if file.is_empty(): continue
			var path: String = "res://assets/" + file.trim_prefix("../../") if file.begins_with("../../") else "res://assets/pixel_isometric/" + file
			check(load(path) is Texture2D,"Directional image imports: " + path)
	var saved: Dictionary = city.studio_data["objects"][0]
	var lazy: Dictionary = city.studio_data["objects"][1]
	for item in [saved,lazy]:
		city.player.teleport_to(exploration.entrance(exploration.instances[item["uid"]]))
		exploration.interact()
		check(exploration.interior != null and exploration.interior_uid == item["uid"],"Enter correct saved or unvisited building")
		if not exploration.interior: continue
		check(exploration.interior.instances.size() == item["interior"]["objects"].size(),"All interior furniture loaded independently")
		if item == saved:
			check(exploration.interior.data_state["title"] == "My portable room" and exploration.interior.data_state["night"],"Owned room settings preserved")
			check(exploration.interior.instances.has("portable_mixed"),"Mixed furniture preserved")
			if "--capture" in OS.get_cmdline_user_args():
				for i in 10: await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://portable_room.png")
		city.player.teleport_to(exploration.exit_position)
		exploration.interact()
		check(exploration.interior == null and city.get_node("Objects").visible,"Return to exterior restores city")
	if city.dimension == "2d":
		city.player.set_physics_process(false)
		for direction in ["SE","SW","NW","NE"]:
			city.player.direction = direction
			city.player.action = "walk"
			check(city.player.get_node("Sprite2D").texture != null,"Player can animate in " + direction)
		check(city.get_node("Ground").get_used_cells().size() == preload("res://scripts/builder/roads.gd").tiles(city.studio_data).size(),"Ground cells and styled roads survive fresh import")
	else:
		check(city.get_node_or_null("SmartRoads") != null,"Styled 3D roads retain their generated meshes and collisions")
	city.free()
	print("PORTABLE RUNTIME: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
