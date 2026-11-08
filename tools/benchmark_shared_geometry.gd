extends SceneTree

const COUNT = 64
const OUTPUT = "res://output/verification/asset_expansion/I19/instancing.json"

func _initialize() -> void: call_deferred("run")

func measurements() -> Dictionary:
	for frame in 12: await RenderingServer.frame_post_draw
	var calls: Array[int] = []
	var primitives: Array[int] = []
	for frame in 60:
		await RenderingServer.frame_post_draw
		calls.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		primitives.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	calls.sort()
	primitives.sort()
	return {"draw_calls_p50":calls[30],"primitives_p50":primitives[30]}

func position_of(index: int) -> Vector3:
	return Vector3((index%8-3.5)*2,0,(index/8-3.5)*2)

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(12,18,15)
	camera.look_at(Vector3.ZERO)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 27
	camera.current = true
	var cube := BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("b8dcec")
	var instances := Node3D.new()
	scene.add_child(instances)
	for index in COUNT:
		var cube_node := MeshInstance3D.new()
		cube_node.mesh = cube
		cube_node.material_override = material
		cube_node.position = position_of(index)
		instances.add_child(cube_node)
	var identical: Dictionary = await measurements()
	for node in instances.get_children(): node.material_override = material.duplicate()
	var unique: Dictionary = await measurements()
	instances.free()
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = cube
	multi.instance_count = COUNT
	for index in COUNT:
		multi.set_instance_transform(index,Transform3D(Basis.IDENTITY,position_of(index)))
	var batch := MultiMeshInstance3D.new()
	batch.multimesh = multi
	batch.material_override = material
	scene.add_child(batch)
	var batch_data: Dictionary = await measurements()
	var result: Dictionary = {"instances":COUNT,"renderer":RenderingServer.get_current_rendering_method(),
		"adapter":RenderingServer.get_video_adapter_name(),"shared":identical,"unique_material":unique,"multimesh":batch_data}
	var file: FileAccess = FileAccess.open(OUTPUT,FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	print("INSTANCING PROBE: ",JSON.stringify(result))
	var comparable: bool = identical["primitives_p50"] > 0 and identical["primitives_p50"] == unique["primitives_p50"] \
		and identical["primitives_p50"] == batch_data["primitives_p50"]
	scene.free()
	await process_frame
	quit(0 if comparable else 1)
