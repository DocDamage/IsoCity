extends RefCounted
const Bounds=preload("res://scripts/model_bounds.gd")
const Preview=preload("res://scripts/builder/model_preview.gd")
const SETTINGS={"version":1,"size":192,"margin":16,"view":[1,.85,1]}
var tree: SceneTree
var viewport: SubViewport
var token: int=0
var error: String=""

func _init(host: SceneTree) -> void:tree=host

func cancel() -> void:
	token+=1
	if is_instance_valid(viewport):viewport.free()
	viewport=null

func _notification(what: int) -> void:
	if what==NOTIFICATION_PREDELETE:
		if is_instance_valid(viewport):viewport.free()
		viewport=null

func render(path: String) -> Image:
	cancel();var request: int=token;error=""
	if DisplayServer.get_name()=="headless":error="A display renderer is required to rebuild a model preview.";return null
	if not FileAccess.file_exists(path):error="Prepared scene is missing.";return null
	var logging: bool=Engine.print_error_messages;Engine.print_error_messages=false
	var packed: PackedScene=ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	Engine.print_error_messages=logging
	if not packed or not packed.can_instantiate():error="Prepared scene cannot be loaded.";return null
	var sample: Node=packed.instantiate()
	if not sample is Node3D:sample.free();error="Prepared scene is not a 3D model.";return null
	var local:=SubViewport.new();viewport=local;local.name="PrivateModelThumbnail";local.size=Vector2i(192,192);local.transparent_bg=true;local.own_world_3d=true;local.render_target_update_mode=SubViewport.UPDATE_ONCE;tree.root.add_child(local)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;local.add_child(camera)
	var environment_node:=WorldEnvironment.new();var environment:=Environment.new();environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color.WHITE;environment.ambient_light_energy=.8;environment_node.environment=environment;local.add_child(environment_node)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-40,-30,0);local.add_child(light);local.add_child(sample)
	var bounds: AABB=Bounds.get_bounds(sample)
	if sample is MeshInstance3D and sample.mesh:
		bounds=bounds.merge(sample.mesh.get_aabb()) if bounds.size.length()>.00001 else sample.mesh.get_aabb()
	if (sample as Node3D).transform!=Transform3D.IDENTITY:bounds=(sample as Node3D).transform*bounds
	if not bounds.position.is_finite() or not bounds.size.is_finite() or not is_finite(bounds.size.length()) or bounds.size.length()<.00001:cancel();error="Prepared geometry has no finite visible bounds.";return null
	var center: Vector3=bounds.get_center();var radius: float=maxf(bounds.size.length()*.5,.001)
	camera.position=center+Vector3(1,.85,1).normalized()*radius*3;camera.look_at(center)
	var extent:=Vector2.ZERO
	for corner in 8:
		var point: Vector3=camera.to_local(bounds.get_endpoint(corner));extent=extent.max(Vector2(absf(point.x),absf(point.y)))
	camera.size=maxf(maxf(extent.x,extent.y)*2*192.0/160,.001);camera.near=maxf(radius*.001,.00001);camera.far=maxf(radius*8,1)
	for frame in 2:
		if request!=token or not is_instance_valid(local):return null
		local.render_target_update_mode=SubViewport.UPDATE_ONCE
		await tree.process_frame;await RenderingServer.frame_post_draw
	if request!=token or not is_instance_valid(local):return null
	var image: Image=local.get_texture().get_image();cancel()
	if not Preview.meaningful_image(image):error="The rendered model preview is empty or uniform.";return null
	return image

static func write_validated(image: Image,destination: String) -> Error:
	if not Preview.meaningful_image(image):return ERR_INVALID_DATA
	var absolute: String=ProjectSettings.globalize_path(destination);var temporary: String=absolute+".isocity-health-%d-%d.partial.png"%[OS.get_process_id(),Time.get_ticks_usec()]
	if DirAccess.dir_exists_absolute(absolute) or FileAccess.file_exists(absolute.get_base_dir()):return ERR_CANT_CREATE
	var result: Error=DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if result!=OK:return result
	result=image.save_png(temporary)
	if result==OK:
		var validated: Image=Preview.read_image(temporary)
		if not validated or validated.get_size()!=image.get_size() or not Preview.meaningful_image(validated):result=ERR_FILE_CORRUPT
	if result==OK:result=DirAccess.rename_absolute(temporary,absolute)
	if result!=OK:DirAccess.remove_absolute(temporary)
	return result
