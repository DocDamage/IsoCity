extends RefCounted

static func make(mode: String, title: String) -> Dictionary:
	var room: Dictionary = load("res://scripts/builder/templates.gd").make(mode,"room")
	room["title"] = title + " · Interior"
	room["interior_room"] = true
	room["exit"] = [0,60,0] if mode == "2d" else [0,.2,2.5]
	room["spawn"] = room["exit"].duplicate()
	return room

static func ensure(item: Dictionary, mode: String, library: RefCounted) -> Dictionary:
	if not item.has("interior"):
		var checked: Dictionary=creation_check(item,mode,library)
		if not checked["ok"]:return {}
		item["interior"]=checked["room"]
	return item["interior"]

static func creation_check(item: Dictionary,mode: String,library: RefCounted,choice: String="") -> Dictionary:
	if item.has("interior"):return {"ok":true,"room":item["interior"],"reason":""}
	var room: Dictionary=make_for(item,mode,library,choice)
	var checked: Dictionary=preload("res://scripts/builder/asset_palette_policy.gd").check({},room,library)
	checked["room"]=room if checked["ok"] else {}
	return checked

static func make_for(item: Dictionary,mode: String,library: RefCounted,choice: String="") -> Dictionary:
	var room: Dictionary=make(mode,item.get("name",library.assets[item["asset"]]["name"]))
	var key: String=choice if not choice.is_empty() else preload("res://scripts/builder/interior_kits.gd").default_for(item["asset"])
	return preload("res://scripts/builder/interior_kits.gd").furnish(room,key,library) if not key.is_empty() else room

static func render(parent: Node, room: Dictionary, library: RefCounted) -> Node:
	var scene: Node = load("res://scripts/builder/world_" + room["mode"] + ".gd").new()
	scene.library = library
	scene.name = "BuildingInterior"
	parent.add_child(scene)
	scene.apply(room)
	scene.grid.visible = false
	scene.selection.visible = false
	scene.player.set_physics_process(false)
	scene.player.collision_layer = 0
	scene.player.visible = false
	if room["mode"] == "2d":
		scene.camera.enabled = false
		# A canvas supports one modulation source. Reuse the exterior's while
		# its saved color is suspended; subsequent room edits update this source.
		for child in parent.get_children():
			if child is CanvasModulate:
				scene.lighting.free()
				scene.lighting = child
				break
		if not room.get("floors",[]).is_empty():
			var stack=load("res://scripts/builder/floor_stack_2d.gd").new(); stack.name="FloorStack"; scene.add_child(stack); scene.floor_stack=stack
			stack.configure(scene,room,parent.player)
	else:
		scene.camera.current = false
		if not room.get("floors",[]).is_empty():
			var stack=load("res://scripts/builder/floor_stack_3d.gd").new(); stack.name="FloorStack"; scene.add_child(stack); scene.floor_stack=stack
			stack.configure(scene,room,library,parent.player)
	return scene
