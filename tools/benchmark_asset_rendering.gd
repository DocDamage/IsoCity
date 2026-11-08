extends SceneTree

const Library = preload("res://scripts/builder/asset_library.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const Document = preload("res://scripts/builder/document.gd")
const Traffic = preload("res://scripts/builder/traffic_plan.gd")
const OUTPUT = "res://output/verification/asset_expansion/I19"
const ASSETS = [
	"3d:Supplemental_Spaceships_II/hammerhead_cruiser",
	"3d:Supplemental_Spaceships_II/nacelle_escort",
	"3d:Supplemental_Spaceships_II/twin_boom_interceptor",
	"3d:Supplemental_Arcade/13_arcade_13_racer_blue",
	"3d:HanX_City/Apartment_4F_A",
	"3d:HanX_Construction/Shipping_Container",
]
const SAMPLES = 100

func _initialize() -> void: call_deferred("run")

func argument(key: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var index: int = args.find(key)
	return args[index+1] if index >= 0 and index+1 < args.size() else fallback

func metrics() -> Dictionary:
	return {
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"texture_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED),
		"buffer_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED),
		"video_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED),
	}

func viewport_metrics(world: Node) -> Dictionary:
	var pixels: int = 0
	var count: int = 0
	for view in world.find_children("*","SubViewport",true,false):
		var viewport: SubViewport = view
		pixels += viewport.size.x*viewport.size.y
		count += 1
	return {"subviewports":count,"color_pixels":pixels,"minimum_rgba8_bytes":pixels*4}

func geometry(world: Node) -> Dictionary:
	var meshes: Dictionary = {}
	var materials: Dictionary = {}
	var textures: Dictionary = {}
	var mesh_nodes: int = 0
	var submitted_triangles: int = 0
	for instance in world.instances.values():
		var nodes: Array = [instance] if instance is MeshInstance3D else []
		nodes.append_array(instance.find_children("*","MeshInstance3D",true,false))
		for node in nodes:
			var mesh: Mesh = node.mesh
			if not mesh: continue
			mesh_nodes += 1
			var key: int = mesh.get_instance_id()
			if not meshes.has(key):
				meshes[key] = 0
				for index in mesh.get_surface_count():
					if mesh is ArrayMesh and mesh.surface_get_primitive_type(index) != Mesh.PRIMITIVE_TRIANGLES: continue
					var arrays: Array = mesh.surface_get_arrays(index)
					if arrays.is_empty(): continue
					var indices: Variant = arrays[Mesh.ARRAY_INDEX]
					var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
					var element_count: int = indices.size() if indices != null and not indices.is_empty() else vertices.size()
					meshes[key] += int(element_count/3)
			submitted_triangles += meshes[key]
			for index in mesh.get_surface_count():
				var material: Material = node.get_active_material(index)
				if not material or materials.has(material.get_instance_id()): continue
				materials[material.get_instance_id()] = true
				for property in material.get_property_list():
					var name: String = property["name"]
					if property["type"] != TYPE_OBJECT or not name.ends_with("_texture"): continue
					var texture: Variant = material.get(name)
					if texture is Texture2D:
						textures[texture.get_instance_id()] = texture.get_width()*texture.get_height()*4
	var source_triangles: int = 0
	for count in meshes.values(): source_triangles += count
	var texture_bytes: int = 0
	for size in textures.values(): texture_bytes += size
	return {"mesh_instances":mesh_nodes,"unique_meshes":meshes.size(),"unique_materials":materials.size(),
		"unique_standard_material_textures":textures.size(),"estimated_rgba8_texture_bytes":texture_bytes,
		"instance_triangles_before_visibility":submitted_triangles,"unique_mesh_triangles":source_triangles}

func window_samples() -> Dictionary:
	for frame in 36: await RenderingServer.frame_post_draw
	var elapsed: Array[float] = []
	var draws: Array[int] = []
	var primitives: Array[int] = []
	var last: int = Time.get_ticks_usec()
	for frame in SAMPLES:
		await RenderingServer.frame_post_draw
		var now: int = Time.get_ticks_usec()
		elapsed.append(float(now-last)/1000.0)
		last = now
		var counters: Dictionary = metrics()
		draws.append(counters["draw_calls"])
		primitives.append(counters["primitives"])
	elapsed.sort()
	draws.sort()
	primitives.sort()
	return {"samples":SAMPLES,"wall_ms_p50":elapsed[SAMPLES/2],"wall_ms_p95":elapsed[int(SAMPLES*.95)],
		"draw_calls_p50":draws[SAMPLES/2],"primitives_p50":primitives[SAMPLES/2],"last_renderer_counters":metrics()}

func visual_case(world: Node, mode: String, wide: bool, label: String) -> Dictionary:
	if mode == "2d":
		world.camera.position = Vector2.ZERO
		world.camera.zoom = Vector2.ONE*(.8 if wide else 1.8)
	else:
		world.target = Vector3.ZERO
		world.distance = 112 if wide else 44
		world.update_camera()
	var result: Dictionary = await window_samples()
	result["case"] = "wide" if wide else "near"
	result["viewports"] = viewport_metrics(world)
	var image: Image = root.get_texture().get_image()
	var path: String = OUTPUT+"/"+label+"_"+result["case"]+".png"
	assert(image.save_png(path) == OK,path)
	return result

func fixture(mode: String, library: RefCounted) -> Dictionary:
	var doc := Document.new()
	doc.data = Templates.make(mode,"blank")
	doc.data["title"] = "Fixed rendering benchmark"
	for z in 8:
		for x in 9:
			var index: int = z*9+x
			var id: String = ASSETS[(x+z*2)%ASSETS.size()]
			assert(library.assets.has(id),id)
			var direction: String = str(library.directions(id)[(z/2)%library.directions(id).size()])
			var point := Vector2((x-4)*8,(z-3.5)*8)
			var item: Dictionary = doc.add(id,Traffic.world(point,mode),direction,.8)
			item["uid"] = "fixture_%02d" % index
	return doc.data

func run() -> void:
	var mode: String = argument("--mode","2d")
	var phase: String = argument("--phase","before")
	if mode not in ["2d","3d"] or phase not in ["before","after"]:
		printerr("Choose --mode 2d or 3d and --phase before or after.")
		quit(1)
		return
	var library := Library.new()
	var world: Node = load("res://scripts/builder/world_"+mode+".gd").new()
	world.library = library
	root.add_child(world)
	var data: Dictionary = fixture(mode,library)
	var start: int = Time.get_ticks_usec()
	world.apply(data)
	var setup_ms: float = float(Time.get_ticks_usec()-start)/1000.0
	var label: String = "%s_%s_%d" % [phase,mode,root.size.x]
	var runs: Array = []
	for wide in [false,true]:
		runs.append(await visual_case(world,mode,wide,label))
	var measured: Dictionary = geometry(world)
	var icon_ids: Array = library.assets.keys().filter(func(id: String)->bool: return id.begins_with("3d:"))
	icon_ids.sort()
	var misses: int = 0
	for id in icon_ids.slice(0,320):
		if library.icon(id) == null: misses += 1
	var result: Dictionary = {"phase":phase,"mode":mode,"screen":[root.size.x,root.size.y],
		"device":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info()["string"],
		"fixture_sha256":JSON.stringify(data).sha256_text(),"assets":ASSETS,"placed":data["objects"].size(),
		"setup_ms":setup_ms,"geometry":measured,"cases":runs,
		"thumbnail_probe":{"requests":320,"missing":misses,"retained_icons":library.icons.size()}}
	var file: FileAccess = FileAccess.open(OUTPUT+"/"+label+".json",FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(result,"\t"))
	print("RENDER BENCHMARK: ",label," ",JSON.stringify(runs)," geometry ",JSON.stringify(measured)," icons ",library.icons.size())
	world.free()
	await process_frame
	quit(0)

