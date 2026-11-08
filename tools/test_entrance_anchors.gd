extends SceneTree

const Anchors = preload("res://scripts/builder/entrance_anchors.gd")
const Factory = preload("res://scripts/builder/asset_instance.gd")
const Geometry = preload("res://scripts/builder/walk_geometry.gd")
const Document = preload("res://scripts/builder/document.gd")
var checks: int = 0
var failures: int = 0
var library: RefCounted

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	library = preload("res://scripts/builder/asset_library.gd").new()
	var candidates: int = 0
	for id in library.assets:
		var asset: Dictionary = library.assets[id]
		if not asset["behavior"].get("building", false): continue
		candidates += 1
		var sprite: bool = asset["mode"] == "2d"
		check(Anchors.valid(asset["behavior"].get("entrance_anchor"), sprite), "Every eligible building has valid authored points: " + id)
		var directions: Array = asset["data"]["directions"].keys() if sprite else ["0", "90", "180", "270", "315"]
		for mode in ["2d", "3d"]:
			var node: Node = Factory.make(library, id, mode)
			root.add_child(node)
			if mode == "2d": node.transform = Transform2D.IDENTITY
			if mode == "3d": Geometry.prepare(node, id, library)
			for direction in directions:
				var item: Dictionary = {"uid":"probe", "asset":id, "position":[0,0,0], "direction":direction, "scale":1.0}
				if sprite: check(asset["behavior"]["entrance_anchor"]["views"].has(direction), "Every supplied view has its own anchor: " + id + "/" + direction)
				Factory.pose(node, item)
				var profile: Dictionary = Anchors.profile(item, library)
				var base: Variant = Anchors.position_for(node, item, mode, library)
				var threshold: Variant = Anchors.position_for(node, item, mode, library, false)
				check(base.distance_to(threshold) > 0.1, "Doorway and clear approach are distinct: " + id + "/" + mode + "/" + direction)
				for size in [0.5, 1.75]:
					if mode == "2d":
						node.position = Vector2(123, -45)
						node.rotation = 0.37
						node.scale = Vector2.ONE * size
					else:
						# Preserve source view/model yaw and compose a rigid outer transform.
						node.transform = Transform3D(Basis.from_euler(Vector3(.11,.37,-.08)).scaled(Vector3.ONE * size), Vector3(12,3,-7)) * Transform3D(node.basis.orthonormalized(), Vector3.ZERO)
					var actual: Variant = Anchors.position_for(node, item, mode, library)
					if mode == "2d":
						check(actual.distance_to(node.transform * base) < 0.001, "Approach follows 2D rotation/scale exactly: " + id + "/" + direction)
					else:
						var raw: Array = profile["arrival"]
						var local: Vector3
						if sprite:
							var foot: Array = asset["data"]["directions"][direction]["footprint"]
							local = Vector3(raw[0]-foot[0]*.5, .02, raw[1]-foot[1]*.5)
						else: local = Vector3(raw[0],raw[1],raw[2])
						check(actual.distance_to(node.transform * local) < .001, "Approach follows all 3D axes/scale exactly: " + id + "/" + direction)
					# Restore the untransformed wrapper/source before the next case.
					if mode == "2d": node.transform = Transform2D.IDENTITY
					else: node.transform = Transform3D.IDENTITY; Factory.pose(node, item)
			# Use the engine's actual obstacle geometry to verify source approaches.
			var first: String = directions[0]
			var item: Dictionary = {"uid":"probe", "asset":id, "direction":first}
			Factory.pose(node, item)
			await physics_frame
			var point: Variant = Anchors.position_for(node, item, mode, library)
			if mode == "3d":
				var query := PhysicsShapeQueryParameters3D.new()
				var capsule := CapsuleShape3D.new()
				capsule.radius = .28
				capsule.height = 1.8
				query.shape = capsule
				query.transform.origin = point + Vector3.UP * .9
				query.collision_mask = 1
				check(node.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(), "Authored approach clears the actual 3D obstacle: " + id)
			else:
				var query := PhysicsShapeQueryParameters2D.new()
				query.shape = CircleShape2D.new()
				query.shape.radius = 4
				query.transform.origin = point
				query.collision_mask = 1
				check(node.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(), "Authored approach clears the actual 2D obstacle: " + id)
			node.free()
	var supplemental: int=0
	for entry in Catalog.get_registry()["items"].values():
		if entry.has("source_pack") and entry.get("behavior",{}).get("building",false): supplemental+=1
	for entry in Catalog.get_registry().get("models",{}).values():
		if entry.get("behavior",{}).get("building",false): supplemental+=1
	check(candidates == 102+supplemental, "The anchor audit includes every original and supplemental building")
	check(not library.assets["3d:HanX_School/School_Bus"]["behavior"]["building"] and not library.assets["2d:Basket"]["behavior"]["building"], "Vehicles and imported prop sheets no longer receive building entrances")
	await test_editor()
	print("ENTRANCE ANCHORS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func test_editor() -> void:
	var studio: Control = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	for i in 5: await process_frame
	for mode in ["2d", "3d"]:
		studio.switch_mode(mode)
		var item: Dictionary = studio.current().data["objects"].filter(func(record: Dictionary) -> bool: return library.assets[record["asset"]]["behavior"].get("building",false))[0]
		studio.selected_uid = item["uid"]
		studio.selected_uids.assign([item["uid"]])
		studio.refresh_controls()
		var tool: RefCounted = studio.entrance_tools
		tool.fields["arrival"][0].value += 1
		check(item.has("entrance_anchor"), "Inspector edits author a per-object entrance: " + mode)
		check(Document.valid(studio.current().data, mode, library), "Entrance overrides remain valid project data: " + mode)
		check(studio.current().undo() and not studio.current().object(item["uid"]).has("entrance_anchor"), "Entrance edits undo: " + mode)
		check(studio.current().redo(), "Entrance edits redo: " + mode)
		studio.changed()
		item = studio.current().object(item["uid"])
		item["position"][0] += 0.27
		item["position"][1] += 0.4
		item["position"][2] += 2.25
		item["scale"] = 1.3
		if mode == "2d": item["angle"] = 23.0
		else: item["direction"] = "73"; item["tilt"] = [9.0,4.0]
		studio.changed()
		var content: Dictionary = JSON.parse_string(JSON.stringify(studio.current().data))
		var restored: Dictionary = content["objects"].filter(func(record:Dictionary)->bool:return record["uid"]==item["uid"])[0]
		var saved_profile: Dictionary = Anchors.profile(restored,library)
		var original_profile: Dictionary = Anchors.profile(item,library)
		var same: bool = true
		for key in ["point","arrival"]:
			for index in original_profile[key].size(): same = same and is_equal_approx(saved_profile[key][index],original_profile[key][index])
		check(Document.valid(content,mode,library) and same, "Entrance overrides round-trip through JSON: " + mode)
		var node: Node = studio.worlds[mode].instances[item["uid"]]
		var expected: Variant = Anchors.position_for(node,item,mode,library)
		check(studio.worlds[mode].exploration.entrance(node).distance_to(expected)<.001, "Marker and interaction use the authored override: " + mode)
		var path: String = "user://entrance_export_" + mode + "_test.tscn"
		check(preload("res://scripts/builder/exporter.gd").save_scene(studio.worlds[mode],studio.current().data,library,path)==OK, "Entrance overrides export: " + mode)
		var exported: Node = load(path).instantiate()
		root.add_child(exported)
		var runtime_node: Node = exported.exploration.instances[item["uid"]]
		check(runtime_node.transform.is_equal_approx(node.transform), "Exports retain free position, height, rotation and scale at ready: " + mode)
		var spawn: Array = studio.current().data.get("spawn", [0,60,0] if mode == "2d" else [0,.2,9])
		check(exported.player.position.distance_to(Vector2(spawn[0],spawn[1]) if mode == "2d" else Vector3(spawn[0],spawn[1],spawn[2])) < .001, "Exported player retains the authored spawn after ready: " + mode)
		var actual: Variant = exported.exploration.entrance(runtime_node)
		check(actual.distance_to(expected)<.001, "Exported interactions retain authored entrance overrides: %s %s / %s" % [mode,str(expected),str(actual)])
		exported.free()
		DirAccess.remove_absolute(path)
		tool.preview.button_pressed = true
		check(studio.worlds[mode].exploration.markers.visible, "Build can preview entrance approaches: " + mode)
		if "--capture" in OS.get_cmdline_user_args() and mode == "3d":
			tool.note.get_parent().get_parent().current_tab = tool.note.get_parent().get_index()
			for i in 10: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://output/editor_entrance_anchors.png")
		tool.walk_here()
		check(studio.walking and studio.worlds[mode].player.position.distance_to(expected)<.001, "Walk from entrance uses the same transformed approach: " + mode)
		studio.set_walking(false)
		tool.reset_anchor()
		check(not item.has("entrance_anchor"), "Catalog entrance can be restored: " + mode)
	studio.free()
