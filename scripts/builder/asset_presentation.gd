extends Node

const Budget = preload("res://scripts/builder/rendering_budget.gd")
const Bounds = preload("res://scripts/model_bounds.gd")
const PIXEL_PHOTO_LIMIT = 4
const MODEL_PHOTO_LIMIT = 6
const HIDE_PIXELS = 2.0
const SHOW_PIXELS = 3.0
const MIN_DETAIL_PIXELS = 64.0
const RETAIN_DETAIL_PIXELS = 32.0
const DETAIL_MARGIN = 24.0

var tracked: Dictionary = {}
var dimension: String = ""
var elapsed: float = 0

func _ready() -> void:
	add_to_group("iso_render_presenters")
	set_process(false)

func configure(data: Dictionary, instances: Dictionary, library: RefCounted) -> void:
	if DisplayServer.get_name() == "headless": return
	dimension = data["mode"]
	var next: Dictionary = {}
	for item in data["objects"]:
		var uid: String = item["uid"]
		var instance: Node = instances.get(uid)
		if not is_instance_valid(instance): continue
		var asset: Dictionary = library.assets.get(item["asset"],{})
		var profile: Dictionary = Budget.profile(asset)
		var approved: bool = Budget.share_projection(asset)
		if dimension == "2d" and (not approved or not instance.has_method("set_photo_projection")): continue
		if dimension == "3d" and (not approved and profile.is_empty()): continue
		var entry: Dictionary = tracked.get(uid,{})
		if entry.get("node") != instance:
			if not entry.is_empty(): restore(entry)
			entry = candidate(instance,profile,approved)
		if entry.is_empty(): continue
		entry["painted"] = not item.get("colors",[]).is_empty()
		next[uid] = entry
	for uid in tracked:
		if not next.has(uid): restore(tracked[uid])
	tracked = next
	set_process(not tracked.is_empty())
	elapsed = .10

func candidate(node: Node, profile: Dictionary, approved: bool) -> Dictionary:
	if dimension == "2d":
		return {"node":node,"profile":profile}
	var visual: Node3D = node.get_node_or_null("Model")
	if not is_instance_valid(visual) or not visual.visible or not Budget.static_visual(visual,true): return {}
	return {"node":node,"visual":visual,"profile":profile,"bounds":Bounds.get_bounds(node),
		"can_cull":approved,"culled":false,"detail":null}

func refresh_for_viewport(view: Viewport) -> void:
	if get_viewport() == view: refresh()

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < .10: return
	elapsed = 0
	refresh()

func refresh() -> void:
	if tracked.is_empty(): return
	var view: Viewport = get_viewport()
	var camera: Node = view.get_camera_2d() if dimension == "2d" else view.get_camera_3d()
	var photo: bool = is_instance_valid(camera) and camera.get_meta("iso_photo_detail",false)
	var screen: Rect2 = view.get_visible_rect()
	var ranked: Array[Dictionary] = []
	var sizes: Dictionary = {}
	for uid in tracked:
		var entry: Dictionary = tracked[uid]
		var node: Variant = entry["node"]
		if not is_instance_valid(node) or not node.is_visible_in_tree() or not is_instance_valid(camera):
			restore(entry)
			continue
		var footprint: Rect2 = projected(entry,camera)
		sizes[uid] = maxf(footprint.size.x,footprint.size.y)
		if photo and not entry["painted"] and (dimension == "2d" or not entry["profile"].is_empty()):
			var retained: bool = entry.get("photo_selected",false)
			var minimum: float = RETAIN_DETAIL_PIXELS if retained else MIN_DETAIL_PIXELS
			if sizes[uid] >= minimum and footprint.intersects(screen.grow(DETAIL_MARGIN*(2 if retained else 1))):
				ranked.append({"uid":uid,"size":sizes[uid],"retained":retained})
	ranked.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
		if a["retained"] != b["retained"]: return a["retained"]
		return a["uid"] < b["uid"] if a["size"] == b["size"] else a["size"] > b["size"])
	var chosen: Dictionary = {}
	var maximum: int = PIXEL_PHOTO_LIMIT if dimension == "2d" else MODEL_PHOTO_LIMIT
	for row in ranked.slice(0,maximum): chosen[row["uid"]] = true
	for uid in sizes:
		var entry: Dictionary = tracked[uid]
		entry["photo_selected"] = chosen.has(uid)
		if dimension == "2d":
			entry["node"].set_photo_projection(entry["photo_selected"],entry["profile"])
			continue
		var cutoff: float = SHOW_PIXELS if entry["culled"] else HIDE_PIXELS
		var hide: bool = not photo and entry["can_cull"] and not entry["painted"] and sizes[uid] > 0 and sizes[uid] < cutoff
		show_model(entry,chosen.has(uid),hide)

func projected(entry: Dictionary, camera: Node) -> Rect2:
	var node: Variant = entry["node"]
	if dimension == "2d":
		var local: Transform2D = node.get_global_transform_with_canvas()
		var center: Vector2 = local*node.sprite.position
		var size: Vector2 = Vector2(node.projection.get("size",Vector2i.ZERO))*node.sprite.scale*local.get_scale().abs()
		return Rect2(center-size*.5,size)
	var bounds: AABB = entry["bounds"]
	var transform: Transform3D = node.global_transform
	var center: Vector3 = transform*bounds.get_center()
	if camera.is_position_behind(center): return Rect2()
	var scale: Vector3 = transform.basis.get_scale().abs()
	var radius: float = .5*bounds.size.length()*maxf(scale.x,maxf(scale.y,scale.z))
	var at: Vector2 = camera.unproject_position(center)
	var edge: Vector2 = camera.unproject_position(center+camera.global_basis.x*radius)
	var half: Vector2 = Vector2.ONE*at.distance_to(edge)
	return Rect2(at-half,half*2)

func show_model(entry: Dictionary, full: bool, hide: bool) -> void:
	var node: Node3D = entry["node"]
	var detail: Node3D = entry["detail"]
	if full and not is_instance_valid(detail):
		detail = Budget.make_detail(entry["profile"])
		if detail:
			detail.name = "PresentationDetail"
			add_child(detail)
			entry["detail"] = detail
	if is_instance_valid(detail):
		if full: detail.global_transform = node.global_transform
		else:
			detail.free()
			entry["detail"] = null
	entry["culled"] = hide
	entry["visual"].visible = not hide and not is_instance_valid(entry["detail"])

func restore(entry: Dictionary) -> void:
	entry["photo_selected"] = false
	var node: Variant = entry["node"]
	if dimension == "2d":
		if is_instance_valid(node): node.set_photo_projection(false,{})
		return
	if is_instance_valid(entry["detail"]): entry["detail"].free()
	entry["detail"] = null
	entry["culled"] = false
	if is_instance_valid(entry["visual"]): entry["visual"].visible = true

