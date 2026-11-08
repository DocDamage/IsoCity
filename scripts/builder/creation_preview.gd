extends RefCounted
const Share=preload("res://scripts/builder/creation_share.gd")
const Bounds=preload("res://scripts/model_bounds.gd")
const Traffic=preload("res://scripts/builder/traffic_plan.gd")

static func fallback(data: Dictionary,library: RefCounted) -> Image:
	var image:=Image.create(800,500,false,Image.FORMAT_RGBA8); image.fill(Color("152c3a"))
	var ids: Array=preload("res://scripts/builder/cooperative_plan.gd").used_assets(data).keys(); ids.sort()
	for i in mini(ids.size(),12):
		var texture: Texture2D=library.icon(ids[i])
		if not texture: continue
		var icon: Image=texture.get_image()
		if icon==null or icon.is_empty(): continue
		icon.convert(Image.FORMAT_RGBA8); var ratio: float=minf(164.0/icon.get_width(),120.0/icon.get_height()); icon.resize(maxi(1,roundi(icon.get_width()*ratio)),maxi(1,roundi(icon.get_height()*ratio)),Image.INTERPOLATE_NEAREST)
		image.blend_rect(icon,Rect2i(Vector2i.ZERO,icon.get_size()),Vector2i(20+(i%4)*195+(164-icon.get_width())/2,35+(i/4)*150+(120-icon.get_height())/2))
	return image
static func generate(host: Node,source: Dictionary,library: RefCounted) -> Image:
	var data: Dictionary=Share.source_document(source).duplicate(true)
	if DisplayServer.get_name()=="headless": return fallback(data,library)
	var view:=SubViewport.new(); view.size=Vector2i(800,500); view.own_world_3d=true; view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; host.get_tree().root.add_child(view)
	var world: Node=load("res://scripts/builder/world_"+data["mode"]+".gd").new(); world.library=library; view.add_child(world); world.apply(data)
	world.grid.hide(); world.selection.hide(); world.player.hide()
	for frame in 8: await host.get_tree().process_frame
	var points: Array[Vector3]=[]
	if data["mode"]=="2d":
		for instance in world.instances.values():
			for sprite in instance.find_children("*","Sprite2D",true,false):
				if sprite.get_viewport()!=view or not sprite.texture: continue
				var rect: Rect2=sprite.get_rect()
				for corner in [rect.position,rect.end,Vector2(rect.end.x,rect.position.y),Vector2(rect.position.x,rect.end.y)]:
					var p: Vector2=sprite.global_transform*corner; points.append(Vector3(p.x,p.y,0))
	else:
		for instance in world.instances.values():
			var box: AABB=instance.transform*Bounds.get_bounds(instance)
			for i in 8: points.append(box.get_endpoint(i))
	for key in ["roads","tiles","terrain_vertices","water_cells"]:
		for item in data.get(key,[]):
			if not item is Dictionary or not item.get("cell") is Array: continue
			var scale: float=8 if key=="roads" else 2; var cell:=Vector2(item["cell"][0],item["cell"][1])*scale
			for p in [cell-Vector2.ONE*scale,cell+Vector2.ONE*scale]:
				var values: Array=Traffic.world(p,data["mode"]); points.append(Vector3(values[0],values[1],values[2]))
	if points.is_empty(): points.assign([Vector3(-8,-8,-8),Vector3(8,8,8)])
	var low: Vector3=points[0]; var high: Vector3=points[0]
	for p in points: low=low.min(p); high=high.max(p)
	if data["mode"]=="2d":
		world.camera.position=Vector2((low.x+high.x)*.5,(low.y+high.y)*.5); world.camera.zoom=Vector2.ONE*minf(720/maxf(44,high.x-low.x),420/maxf(44,high.y-low.y)); world.camera.reset_smoothing()
	else:
		world.target=(low+high)*.5; world.distance=maxf(8,(high-low).length()*1.25); world.update_camera()
		var right: Vector3=world.camera.global_basis.x; var up: Vector3=world.camera.global_basis.y; var width: float=0; var height: float=0
		for p in points:
			var relative: Vector3=p-world.target; width=maxf(width,absf(relative.dot(right))*2); height=maxf(height,absf(relative.dot(up))*2)
		world.distance=maxf(8,maxf(width/1.6,height)*1.2); world.update_camera(); world.camera.far=maxf(1000,(high-low).length()*5)
	for frame in 4: await host.get_tree().process_frame
	RenderingServer.force_draw(false); RenderingServer.force_draw(false)
	var image: Image=view.get_texture().get_image(); view.free(); return image
