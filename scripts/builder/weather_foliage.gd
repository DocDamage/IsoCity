extends RefCounted

const Plan=preload("res://scripts/builder/weather_plan.gd")
const MAX_TEXTURES: int=128
var entries: Dictionary={}
var textures: Dictionary={}
var elapsed: float=0

func texture(original: Texture2D,season: String,kind: String,variation: float) -> Texture2D:
	if not original or original is ViewportTexture or season=="original" or (season=="summer" and kind!="blossom"): return original
	var key: String=str(original.get_instance_id())+":"+season+":"+kind+":"+str(roundi(variation*4))
	if textures.has(key): return textures[key]
	var image: Image=original.get_image()
	if not image or image.is_empty(): return original
	if image.is_compressed() and image.decompress()!=OK: return original
	image=image.duplicate(); image.convert(Image.FORMAT_RGBA8)
	var changed: bool=false
	for y in image.get_height():
		for x in image.get_width():
			var before: Color=image.get_pixel(x,y); var after: Color=Plan.seasonal_color(before,season,kind,variation)
			if after!=before: image.set_pixel(x,y,after); changed=true
	if not changed: return original
	var result:=ImageTexture.create_from_image(image)
	# Piece picking must continue to identify the authored source texture,
	# rather than saving edits against this transient seasonal image.
	result.set_meta("paint_base",original.get_meta("paint_base",original))
	if textures.size()>=MAX_TEXTURES: textures.erase(textures.keys()[0])
	textures[key]=result; return result

func visuals(node: Node,result: Array) -> void:
	# A sprite rendered in 3D owns a hidden source sprite. Alter the visible
	# card only; changing both would double its wind motion and texture work.
	if (node is Sprite2D and not node.texture is ViewportTexture) or node is MeshInstance3D: result.append(node)
	for child in node.get_children():
		if child.name=="SourceSprite": continue
		visuals(child,result)

func current(slot: Dictionary) -> Resource:
	var node: Node=slot["node"].get_ref()
	if not is_instance_valid(node): return null
	if slot["type"]=="sprite": return node.texture
	if slot["type"]=="override": return node.material_override
	return node.get_surface_override_material(slot["surface"]) if node.mesh and slot["surface"]<node.mesh.get_surface_count() else null

func assign(slot: Dictionary,value: Resource) -> void:
	var node: Node=slot["node"].get_ref()
	if not is_instance_valid(node): return
	if slot["type"]=="sprite": node.texture=value
	elif slot["type"]=="override": node.material_override=value
	elif node.mesh and slot["surface"]<node.mesh.get_surface_count(): node.set_surface_override_material(slot["surface"],value)

func slot_for(node: Node,type: String,surface: int=-1) -> Dictionary:
	var slot: Dictionary={"node":weakref(node),"type":type,"surface":surface,"applied":null,"original":null,"base":null,"stamp":""}
	slot["original"]=current(slot); slot["base"]=node.get_active_material(surface) if type=="surface" else slot["original"]
	return slot

func entry_for(node: Node,asset: String) -> Dictionary:
	var nodes: Array=[]; visuals(node,nodes); var slots: Array=[]; var wind: Array=[]; var meshes: Dictionary={}
	var projected: bool=node.has_method("ground_polygon")
	if projected: wind.append({"node":weakref(node.sprite),"angle":0.0,"base":node.sprite.rotation,"animate":true})
	for visual in nodes:
		wind.append({"node":weakref(visual),"angle":0.0,"base":visual.rotation if visual is Node2D else visual.rotation.z,"animate":not projected})
		if visual is Sprite2D: slots.append(slot_for(visual,"sprite"))
		elif visual.mesh:
			meshes[visual.get_instance_id()]=[visual.mesh.get_instance_id(),visual.material_override!=null]
			if visual.material_override: slots.append(slot_for(visual,"override"))
			else:
				for index in visual.mesh.get_surface_count(): slots.append(slot_for(visual,"surface",index))
	return {"node":weakref(node),"asset":asset,"slots":slots,"wind":wind,"meshes":meshes}

func matches(entry: Dictionary) -> bool:
	for value in entry["wind"]:
		var node: Node=value["node"].get_ref()
		if not is_instance_valid(node): return false
		if node is MeshInstance3D:
			if not node.mesh or entry["meshes"].get(node.get_instance_id(),[])!=[node.mesh.get_instance_id(),node.material_override!=null]: return false
	return true

func update_slot(slot: Dictionary,season: String,kind: String,variation: float) -> bool:
	var node: Node=slot["node"].get_ref()
	if not is_instance_valid(node): return false
	var actual: Resource=current(slot)
	if actual!=slot["applied"]:
		slot["original"]=actual; slot["base"]=node.get_active_material(slot["surface"]) if slot["type"]=="surface" else actual; slot["stamp"]=""
	var base: Resource=slot["base"]
	# Sprite-card animation can update a StandardMaterial in place.
	var source_texture: Texture2D=base.albedo_texture if base is BaseMaterial3D else (base if base is Texture2D else null)
	var stamp: String=season+":"+kind+":"+str(source_texture.get_instance_id() if source_texture else 0)+":"+str(base.albedo_color if base is BaseMaterial3D else "")
	if stamp==slot["stamp"]: return false
	slot["stamp"]=stamp
	var result: Resource=slot["original"]
	if season!="original" and (season!="summer" or kind=="blossom"):
		if base is Texture2D: result=texture(base,season,kind,variation)
		elif base is BaseMaterial3D:
			var modified: Texture2D=texture(source_texture,season,kind,variation)
			var color: Color=Plan.seasonal_color(base.albedo_color,season,kind,variation)
			if modified!=source_texture or color!=base.albedo_color:
				result=base.duplicate(); result.albedo_texture=modified; result.albedo_color=color
	assign(slot,result); slot["applied"]=result
	return actual!=result

func redraw(entry: Dictionary) -> void:
	var node: Node=entry["node"].get_ref()
	if is_instance_valid(node) and node.has_method("ground_polygon") and is_instance_valid(node.viewport): node.viewport.render_target_update_mode=SubViewport.UPDATE_ONCE

func restore_entry(entry: Dictionary) -> void:
	for slot in entry["slots"]:
		if current(slot)==slot["applied"]: assign(slot,slot["original"])
	for value in entry["wind"]:
		if not value["animate"]: continue
		var node: Node=value["node"].get_ref()
		if not is_instance_valid(node): continue
		var angle: float=node.rotation if node is Node2D else node.rotation.z
		if not is_equal_approx(angle,value["base"]+value["angle"]): continue
		if node is Node2D: node.rotation=value["base"]
		elif node is Node3D: node.rotation.z=value["base"]
	redraw(entry)

func sync(data: Dictionary,instances: Dictionary,state: Dictionary,delta: float) -> void:
	if not state.get("enabled",false): reset(); return
	elapsed=fposmod(elapsed+maxf(0,delta),10000)
	var seen: Dictionary={}
	for item in data.get("objects",[]):
		var kind: String=Plan.foliage(item["asset"]); var uid: String=item["uid"]
		if kind.is_empty() or not instances.has(uid) or not is_instance_valid(instances[uid]): continue
		var node: Node=instances[uid]; seen[uid]=true
		if entries.has(uid) and (entries[uid]["node"].get_ref()!=node or entries[uid]["asset"]!=item["asset"] or not matches(entries[uid])): restore_entry(entries[uid]); entries.erase(uid)
		if not entries.has(uid): entries[uid]=entry_for(node,item["asset"])
		var entry: Dictionary=entries[uid]; var variation: float=float(posmod(hash(uid),1000))/1000
		var changed: bool=false
		for slot in entry["slots"]:
			if update_slot(slot,state["effective_season"] if state.get("foliage",true) else "original",kind,variation): changed=true
		if changed: redraw(entry)
		var force: Vector2=state.get("wind_vector",Vector2.ZERO)
		var sway: float=sin(elapsed*2.1+variation*TAU)*force.length()*.022
		for value in entry["wind"]:
			if not value["animate"]: continue
			var visual: Node=value["node"].get_ref()
			if not is_instance_valid(visual): continue
			# Add only the visual delta, so terrain offsets, source rotation,
			# authored transforms and collision bodies remain authoritative.
			var angle: float=visual.rotation if visual is Node2D else visual.rotation.z
			if not is_equal_approx(angle,value["base"]+value["angle"]): value["base"]=angle
			if visual is Node2D: visual.rotation=value["base"]+sway
			elif visual is Node3D: visual.rotation.z=value["base"]+sway
			value["angle"]=sway
	for uid in entries.keys():
		if not seen.has(uid): restore_entry(entries[uid]); entries.erase(uid)

func reset() -> void:
	for entry in entries.values(): restore_entry(entry)
	entries.clear(); textures.clear(); elapsed=0
