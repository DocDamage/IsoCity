extends SceneTree
const OUTPUT="res://resources/catalog/asset_style_models.json"
const Bounds=preload("res://scripts/model_bounds.gd")
var failures: PackedStringArray=[]
func _initialize() -> void:call_deferred("run")
func dependencies(path: String,found: Dictionary) -> void:
	if found.has(path):return
	if not FileAccess.file_exists(path):failures.append("Missing prepared dependency: "+path);return
	var file:=FileAccess.open(path,FileAccess.READ)
	found[path]={"sha256":FileAccess.get_sha256(path),"size":file.get_length()}
	if path.get_extension() in ["glb","gltf"]:found[path]["import_parameters"]=preload("res://scripts/builder/asset_styles.gd").import_parameters(path)
	if path.get_extension() in ["tscn","tres"]:
		var pattern:=RegEx.new();pattern.compile('\\[ext_resource[^\\n]*path="([^"]+)"')
		for match_value in pattern.search_all(FileAccess.get_file_as_string(path)):dependencies(match_value.get_string(1),found)
	elif path.get_extension()=="gltf":
		var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary:failures.append("Unreadable glTF: "+path);return
		for entry in data.get("buffers",[])+data.get("images",[]):
			var uri: String=entry.get("uri","")
			if not uri.is_empty() and not uri.begins_with("data:"):dependencies(path.get_base_dir().path_join(uri.uri_decode()),found)
func imported(path: String) -> bool:
	if path.get_extension() not in ["glb","gltf"]:return true
	var settings:=ConfigFile.new()
	if settings.load(path+".import")!=OK:return false
	var compiled: String=settings.get_value("remap","path","")
	var marker: String=compiled.get_basename()+".md5"
	if not FileAccess.file_exists(compiled) or not FileAccess.file_exists(marker):return false
	var pattern:=RegEx.new();pattern.compile('source_md5="([a-f0-9]+)"')
	var result: RegExMatch=pattern.search(FileAccess.get_file_as_string(marker))
	return result!=null and result.get_string(1)==FileAccess.get_md5(path)
func material_tags(root_node: Node) -> Array[String]:
	var tags: Array[String]=[]
	for node in [root_node]+root_node.find_children("*","MeshInstance3D",true,false):
		if not node is MeshInstance3D or not node.mesh:continue
		for index in node.mesh.get_surface_count():
			var material: Material=node.get_active_material(index)
			var selected: Array[String]=[]
			if material is BaseMaterial3D:
				selected.append("unlit" if material.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED else "lit_pbr")
				if material.albedo_texture:selected.append("albedo_texture")
				if material.vertex_color_use_as_albedo:selected.append("vertex_color")
				if not material.albedo_texture and not material.vertex_color_use_as_albedo:selected.append("solid_color")
				if material.metallic>.25:selected.append("metallic")
				if material.roughness>=.75:selected.append("rough_surface")
				elif material.roughness<=.35:selected.append("smooth_surface")
				if material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED:selected.append("transparent")
				if material.albedo_texture and material.texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST:selected.append("nearest_texture")
			elif material is ShaderMaterial:selected.append("custom_shader")
			elif material==null:selected.append("default_material")
			for tag in selected:
				if tag not in tags:tags.append(tag)
	tags.sort();return tags
func run() -> void:
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new()
	var result: Dictionary={};var verified: int=0
	for id in library.assets:
		if not id.begins_with("3d:") or id.contains(":Custom/"):continue
		var asset: Dictionary=library.assets[id];var sources: Dictionary={};var previous_failures: int=failures.size();dependencies(asset["path"],sources)
		var entry: Dictionary={"scene":asset["path"],"sources":sources,"verified":false,"materials":[],"span":[],"note":"Prepared import needs refreshing; material and size hints are unavailable."}
		var ready: bool=failures.size()==previous_failures
		for path in sources:
			if not imported(path):ready=false
		if ready:
			var sample: Node3D=load(asset["path"]).instantiate()
			sample.position=Vector3.ZERO;sample.rotation=Vector3.ZERO;sample.scale=Vector3.ONE
			var box: AABB=Bounds.get_bounds(sample)
			entry.merge({"verified":true,"materials":material_tags(sample),"span":[box.size.x,box.size.z],"height":box.size.y,"note":"Measured prepared geometry and active material properties; source hashes retained."},true)
			sample.free();verified+=1
		result[id]=entry
	if not failures.is_empty():
		for message in failures:printerr("FAIL: "+message)
		quit(1);return
	var text: String=JSON.stringify({"version":1,"assets":result},"\t",true)+"\n"
	if "--check" in OS.get_cmdline_user_args():
		if not FileAccess.file_exists(OUTPUT) or FileAccess.get_file_as_string(OUTPUT)!=text:printerr("FAIL: prepared style evidence is stale");quit(1);return
	elif not FileAccess.file_exists(OUTPUT) or FileAccess.get_file_as_string(OUTPUT)!=text:
		var temporary: String=OUTPUT+".tmp";var file:=FileAccess.open(temporary,FileAccess.WRITE)
		if not file:printerr("FAIL: cannot stage prepared style evidence");quit(1);return
		file.store_string(text);file.close()
		if FileAccess.get_file_as_string(temporary)!=text or not JSON.parse_string(text) is Dictionary or DirAccess.rename_absolute(temporary,OUTPUT)!=OK:printerr("FAIL: cannot publish prepared style evidence");quit(1);return
	print("ASSET STYLE MODELS: %d models; %d measured, %d need imports"%[result.size(),verified,result.size()-verified]);quit()
