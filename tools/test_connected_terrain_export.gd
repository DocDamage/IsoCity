extends SceneTree

const Families=preload("res://scripts/builder/terrain_family_plan.gd")
var checks: int=0
var failures: int=0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL: "+message)

func run() -> void:
	var city: Node=load("res://city.tscn").instantiate()
	root.add_child(city)
	var data: Dictionary=city.studio_data
	var tiles: Dictionary=Families.by_cell(data["tiles"])
	var ground: TileMapLayer=city.get_node("Ground")
	var path: Dictionary=Families.ground_variant(tiles[Vector2i(-3,5)],Vector2i(-3,5),tiles,{})
	check(data["terrain"]["connected_shores"] and data["terrain"]["connected_cliffs"] and path["mask"]==15,
		"Portable source retains authored paths, shores, and cliff settings.")
	var source: TileSetAtlasSource=ground.tile_set.get_source(ground.get_cell_source_id(Vector2i(-4,-3)))
	check(source.get_tile_animation_frames_count(Vector2i.ZERO)==4 and source.texture_region_size==Vector2i(32,16),
		"The fresh project retains the generated shoreline with all native animation frames.")
	var terrain: Node=city.get_node("Terrain")
	var cliff_mask: int=0
	for cliff in terrain.rock_faces.values(): cliff_mask|=cliff["mask"]
	check(cliff_mask==15 and terrain.family_warnings.has(Vector2i(-6,-5)),
		"The independent renderer reconstructs the rock loop and level-mismatch finding.")
	var water: int=0
	for strip in terrain.strips.values():
		for face in strip.faces:
			if face["kind"]=="water" and face.get("textures",[]).size()==4: water+=1
	check(water>12,"Portable sculpted water uses all four authored shore frames.")
	city.free()
	await process_frame
	print("PORTABLE CONNECTED TERRAIN: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
