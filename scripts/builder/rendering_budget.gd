extends RefCounted

const CATALOG = "res://resources/catalog/rendering_budget.json"
const ProjectionCache = preload("res://scripts/builder/projected_model_cache.gd")
const STATIC_PROJECTIONS = ["3d:HanX_City/Apartment_4F_A","3d:HanX_Construction/Shipping_Container"]
const SPACE_PACKS = ["Spaceships","Spaceships II","Satellites"]

static var profiles: Dictionary = {}

static func projection_pool(parent: Node) -> Node:
	if DisplayServer.get_name() == "headless": return null
	var pool := ProjectionCache.new()
	pool.name = "ModelProjectionCache"
	parent.add_child(pool)
	return pool

static func share_projection(asset: Dictionary) -> bool:
	var id: String = asset.get("id","")
	return id in STATIC_PROJECTIONS or (id.begins_with("3d:Supplemental_") \
		and asset.get("data",{}).get("source_pack","") in SPACE_PACKS \
		and asset.get("behavior",{}).get("collision","") == "none")

static func prepare_projection(instance: Node, asset: Dictionary, pool: Node) -> void:
	if pool and instance.has_method("set_projection_pool") and share_projection(asset):
		instance.set_projection_pool(pool)

static func profile(asset: Dictionary) -> Dictionary:
	if asset.get("data",{}).get("model_file","").is_empty(): return {}
	if profiles.is_empty():
		var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
		if catalog is Dictionary and catalog.get("version") == 1: profiles = catalog["assets"]
	var entry: Dictionary = profiles.get(asset.get("id",""),{})
	if entry.get("low",{}).get("path") != asset["data"]["model_file"]: return {}
	return entry

static func make_detail(entry: Dictionary) -> Node3D:
	var path: String = entry.get("full",{}).get("path","")
	if path.is_empty() or not ResourceLoader.exists(path,"PackedScene"): return null
	var scene := load(path) as PackedScene
	if not scene: return null
	var result := Node3D.new()
	var visual := scene.instantiate() as Node3D
	var offset: Array = entry["photo_offset"]
	visual.position = Vector3(offset[0],offset[1],offset[2])
	visual.scale = Vector3.ONE*float(entry["photo_scale"])
	result.add_child(visual)
	return result

static func static_visual(root: Node3D, opaque_only: bool = false) -> bool:
	for node in [root]+root.find_children("*","",true,false):
		if node.get_script() or node is AnimationPlayer or node is Skeleton3D or node is GPUParticles3D or node is CPUParticles3D:
			return false
		if node is GeometryInstance3D and node.transparency > 0: return false
		if not opaque_only or not node is MeshInstance3D or not node.mesh: continue
		for surface in node.mesh.get_surface_count():
			var material: Material = node.get_active_material(surface)
			if material and (not material is BaseMaterial3D or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED):
				return false
	return true
