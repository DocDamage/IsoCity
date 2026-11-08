extends RefCounted

const PATH: String="res://resources/catalog/props.json"
const KINDS: Array[String]=["seat","swing","slide","switch","appliance"]
const POINTS: Array[String]=["point","approach","end","exit","facing","customer"]
static var catalog: Dictionary={}

static func definitions() -> Dictionary:
	if catalog.is_empty(): catalog=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return catalog

static func valid(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.has("kind") and value["kind"] not in ["auto","none"]+KINDS: return false
	for key in ["enabled","initial_on"]:
		if value.has(key) and not value[key] is bool: return false
	for key in ["label","target"]:
		if value.has(key) and (not value[key] is String or value[key].length()>160): return false
	for key in ["duration","reach"]:
		if not value.has(key): continue
		var n: Variant=value[key]
		if not (n is float or n is int) or not is_finite(float(n)) or n<(.5 if key=="duration" else .5) or n>(60 if key=="duration" else 6): return false
	for key in POINTS:
		if not value.has(key): continue
		if not value[key] is Array or value[key].size()!=3: return false
		for n in value[key]:
			if not (n is float or n is int) or not is_finite(float(n)) or absf(float(n))>64: return false
	return true

static func profile(item: Dictionary) -> Dictionary:
	var raw: Variant=item.get("prop",{})
	if item.has("missing_asset") or not valid(raw) or not raw.get("enabled",true): return {}
	var authored: Dictionary=definitions()["assets"].get(item["asset"],{})
	var kind: String=raw.get("kind",authored.get("kind","none"))
	if kind=="auto": kind=authored.get("kind","none")
	if kind=="none": return {}
	var result: Dictionary=definitions()["kinds"][kind].duplicate(true)
	if authored.get("kind")==kind: result.merge(authored,true)
	for key in ["label","target","initial_on","duration","reach"]+POINTS:
		if raw.has(key): result[key]=raw[key]
	result["custom_points"]=[]
	result["explicit_points"]=[]
	for key in POINTS:
		if authored.get("kind")==kind and authored.has(key): result["explicit_points"].append(key)
	for key in POINTS:
		if raw.has(key): result["custom_points"].append(key)
	# Legacy end remains the slide landing; exit/facing are optional additions.
	if not result.has("exit"): result["exit"]=result["end"] if kind=="slide" else result["approach"]
	if not result.has("facing"): result["facing"]=result["end"] if kind=="slide" else (result["approach"] if kind in ["seat","swing"] else result["point"])
	if not result.has("customer"): result["customer"]=result["approach"]
	result["kind"]=kind
	if kind=="switch" and result.get("target","")==item.get("uid",""): result["target"]=""
	return result

static func power_device(item: Dictionary) -> bool:
	var value: Dictionary=profile(item)
	return value.get("kind","")=="appliance" or (value.get("kind","")=="switch" and str(value.get("target","")).is_empty())

static func target_record(item: Dictionary,data: Dictionary,library: RefCounted) -> Dictionary:
	var uid: String=profile(item).get("target","")
	if uid.is_empty():return item
	for target in data.get("objects",[]):
		if target["uid"]!=uid:continue
		if not library.assets.has(target["asset"]) or target.has("missing_asset") or not target.get("visible",true):return {}
		if not preload("res://scripts/builder/layers.gd").shown(data,preload("res://scripts/builder/layers.gd").layer(target,library)) or not power_device(target):return {}
		return target
	return {}

static func source(profile: Dictionary,item: Dictionary,library: RefCounted,key: String) -> Vector3:
	# Missing optional per-view points inherit the corresponding per-view legacy
	# anchor, rather than an unrotated base point from another source view.
	if key in ["exit","facing","customer"] and key not in profile.get("custom_points",[]) and not profile.get("explicit_points",[]).has(key) and not profile.get("views",{}).get(item["direction"],{}).has(key):
		var fallback: String="approach"
		if key=="exit" and profile["kind"]=="slide": fallback="end"
		if key=="facing" and profile["kind"] not in ["seat","swing","slide"]: fallback="point"
		if key=="facing" and profile["kind"]=="slide": fallback="end"
		return source(profile,item,library,fallback)
	var view_point: bool=key not in profile.get("custom_points",[]) and profile.get("views",{}).get(item["direction"],{}).has(key)
	var value: Array=profile["views"][item["direction"]][key] if view_point else profile[key]
	var point:=Vector3(value[0],value[1],value[2])
	if library.assets[item["asset"]]["mode"]=="2d" and not profile.get("absolute_sprite_anchor",false):
		if not view_point:
			var turn: float=deg_to_rad(float({"SE":-90,"SW":0,"NW":90,"NE":180}.get(item["direction"],0)))
			var rotated:=Vector2(point.x,point.z).rotated(turn); point.x=rotated.x; point.z=rotated.y
		var views: Dictionary=library.assets[item["asset"]]["data"]["directions"]
		var view: Dictionary=views.get(item["direction"],views.get("SE",views.values()[0])); var foot: Array=view.get("footprint",[1,1])
		point.x+=float(foot[0])*.5; point.z+=float(foot[1])*.5
	return point

static func anchor(node: Node,item: Dictionary,library: RefCounted,mode: String,profile: Dictionary,key: String="point") -> Variant:
	return preload("res://scripts/builder/entrance_anchors.gd").source_position(node,item,mode,library,source(profile,item,library,key))

static func edit_point(profile: Dictionary,item: Dictionary,library: RefCounted,key: String) -> Vector3:
	var point: Vector3=source(profile,item,library,key)
	if library.assets[item["asset"]]["mode"]=="2d" and not profile.get("absolute_sprite_anchor",false):
		var views: Dictionary=library.assets[item["asset"]]["data"]["directions"]; var view: Dictionary=views.get(item["direction"],views.get("SE",views.values()[0])); var foot: Array=view.get("footprint",[1,1])
		point.x-=float(foot[0])*.5; point.z-=float(foot[1])*.5
		var turn: float=deg_to_rad(float({"SE":-90,"SW":0,"NW":90,"NE":180}.get(item["direction"],0))); var rotated:=Vector2(point.x,point.z).rotated(-turn); point.x=rotated.x; point.z=rotated.y
	return point

static func global_point(candidate: Dictionary,exploration: Node,key: String="point",offset: Vector3=Vector3.ZERO) -> Variant:
	var node: Node=candidate["node"]; var item: Dictionary=candidate["item"]
	if exploration.library.assets[item["asset"]]["mode"]=="2d":
		var turn: float=deg_to_rad(float({"SE":-90,"SW":0,"NW":90,"NE":180}.get(item["direction"],0)))
		var rotated:=Vector2(offset.x,offset.z).rotated(turn); offset.x=rotated.x; offset.z=rotated.y
	var local: Vector3=source(candidate["profile"],item,exploration.library,key)+offset
	# A sprite card's visible seat follows the camera-facing artwork. Ground
	# approaches retain physical footprint coordinates, while use poses follow
	# the exact pixel on the rendered card, including authored free rotations.
	if exploration.dimension=="3d" and node.has_method("mixed_bounds") and not node.ground_tile and key=="point":
		var pixel: Vector2=preload("res://scripts/builder/grid_fit.gd").pixels(Vector2(local.x,local.z))+Vector2(0,-local.y*8)
		var relative: Vector2=(pixel-node.card_rect.get_center())/node.PIXELS_PER_UNIT
		if node.material.billboard_mode==BaseMaterial3D.BILLBOARD_DISABLED: return node.mesh.global_transform*Vector3(relative.x,-relative.y,0)
		var camera: Camera3D=node.get_viewport().get_camera_3d(); var right: Vector3=camera.global_basis.x.normalized() if camera else Vector3.RIGHT; var scale: Vector3=node.mesh.global_basis.get_scale()
		return node.mesh.global_position+right*relative.x*scale.x-Vector3.UP*relative.y*scale.y
	var value: Variant=preload("res://scripts/builder/entrance_anchors.gd").source_position(node,item,exploration.dimension,exploration.library,local)
	var result: Variant=node.get_parent().to_global(value)
	if exploration.dimension=="2d" and "terrain_visual_offset" in node:
		var sprite: Sprite2D=node.get_node_or_null("Sprite2D")
		if sprite: result+=sprite.global_transform.basis_xform(node.terrain_visual_offset)
	return result

static func scope(exploration: Node) -> String:
	if exploration.interior: return "room:"+exploration.interior_uid+":"+exploration.active_floor()+":"
	if not exploration.editor_scope.is_empty(): return exploration.editor_scope
	var world: Node=exploration.get_parent(); var data: Dictionary=world.live_data if "live_data" in world else world.data_state
	return "room:standalone:ground:" if data.get("interior_room",false) else "city:"

static func ground_point(candidate: Dictionary,exploration: Node,key: String="end") -> Variant:
	var node: Node=candidate["node"]; var item: Dictionary=candidate["item"]; var point: Vector3=source(candidate["profile"],item,exploration.library,key)
	if exploration.dimension=="2d": point.y=0
	var local: Variant=preload("res://scripts/builder/entrance_anchors.gd").source_position(node,item,exploration.dimension,exploration.library,point)
	var result: Variant=node.get_parent().to_global(local)
	if exploration.dimension=="2d": result+=node.get_parent().global_transform.basis_xform(Vector2(0,float(item["position"][2])*8))
	return result

static func context(exploration: Node) -> Dictionary:
	if exploration.interior:
		var room: Node=exploration.room_world()
		return {"data":room.data_state,"instances":room.instances,"world":room,"scope":scope(exploration)}
	var world: Node=exploration.get_parent()
	var data: Dictionary=world.live_data if "live_data" in world else world.data_state
	return {"data":data,"instances":exploration.instances,"world":world,"scope":scope(exploration)}

static func nearby(exploration: Node) -> Dictionary:
	if not exploration.enabled or not is_instance_valid(exploration.player) or exploration.entering: return {}
	if exploration.interior and exploration.interior.floor_stack:
		var stack: Node=exploration.interior.floor_stack
		if "travel" in stack and not stack.travel.is_empty(): return {}
	var active: Dictionary=context(exploration); var best: float=INF; var result: Dictionary={}
	for item in active["data"].get("objects",[]):
		var node: Node=active["instances"].get(item["uid"])
		if not is_instance_valid(node) or not node.is_visible_in_tree() or not item.get("visible",true): continue
		if exploration.cooking and exploration.cooking.manages(item): continue
		if exploration.laundry and exploration.laundry.manages(item): continue
		if exploration.fitness and exploration.fitness.manages(item): continue
		if exploration.arcade and exploration.arcade.manages(item): continue
		if exploration.camping and exploration.camping.manages(item,active["scope"]): continue
		var value: Dictionary=profile(item)
		if value.is_empty(): continue
		var point: Variant=node.get_parent().to_global(anchor(node,item,exploration.library,exploration.dimension,value,"approach"))
		var difference: Variant=point-exploration.player.global_position
		var distance: float=difference.length()
		var metric: float=Vector2(difference.x/16,difference.y/8).length() if exploration.dimension=="2d" else Vector2(difference.x,difference.z).length()
		if exploration.dimension=="3d" and absf(difference.y)>1.2: continue
		if exploration.dimension=="2d" and absf(float(item["position"][2])+float(node.get_meta("terrain_height",0))-float(exploration.player.get_meta("terrain_height",0)))>1.2: continue
		if metric>value["reach"] or distance>=best: continue
		if not reachable(exploration,node,point): continue
		best=distance; result={"item":item,"node":node,"profile":value,"distance":distance,"scope":active["scope"],"world":active["world"],"data":active["data"],"instances":active["instances"]}
	return result

static func reachable(exploration: Node,node: Node,point: Variant,actor: Node=null) -> bool:
	var player: Node=actor if actor else exploration.player; var excluded: Array[RID]=[player.get_rid()]
	for body in [node]+node.find_children("*","CollisionObject2D" if exploration.dimension=="2d" else "CollisionObject3D",true,false):
		if body is CollisionObject2D or body is CollisionObject3D: excluded.append(body.get_rid())
	if exploration.dimension=="2d":
		var query:=PhysicsRayQueryParameters2D.create(player.global_position,point,player.collision_mask,excluded)
		return player.get_world_2d().direct_space_state.intersect_ray(query).is_empty()
	var query:=PhysicsRayQueryParameters3D.create(player.global_position+Vector3.UP*.9,point+Vector3.UP*.9,player.collision_mask,excluded)
	return player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

static func standing_clear(exploration: Node,point: Variant,mask: int=-1) -> bool:
	var player: Node=exploration.player; var original: int=player.collision_mask
	if mask>=0: player.collision_mask=mask
	var clear: bool
	if exploration.dimension=="2d": clear=player.clear_at(point)
	else:
		var pose: Transform3D=player.global_transform; pose.origin=point; clear=player.clear_at(pose)
	player.collision_mask=original
	return clear and (not player.terrain_position_safe.is_valid() or player.terrain_position_safe.call(point))
