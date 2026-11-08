extends Node

const Plan=preload("res://scripts/builder/delivery_plan.gd")
const Instance=preload("res://scripts/builder/asset_instance.gd")
const TINT=Color("f3ce75")
var driver: Node
var panel: PanelContainer
var caption: Label
var action: Button
var cancel: Button
var marker: Node
var marker_key: Array=[]
var cargo: Node
var cargo_id: String=""
var elapsed: float=0.0
var text_scale: float=1
var large_targets: bool=false
var high_contrast: bool=false
var bottom_inset: float=74
var available_width: float=INF
var style_key: Array=[]

func _ready() -> void:
	var layer:=CanvasLayer.new()
	layer.layer=24
	add_child(layer)
	panel=PanelContainer.new()
	layer.add_child(panel)
	var box:=VBoxContainer.new()
	panel.add_child(box)
	caption=Label.new()
	caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	box.add_child(caption)
	var row:=HBoxContainer.new()
	box.add_child(row)
	action=button(row,"Handle delivery cargo",activate)
	cancel=button(row,"Cancel delivery contract",driver.cancel_delivery)
	panel.hide()

func button(parent: Node,title: String,callback: Callable) -> Button:
	var result:=Button.new()
	result.accessibility_name=title
	result.clip_text=true
	result.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	result.pressed.connect(callback)
	parent.add_child(result)
	return result

func activate() -> void:
	if is_instance_valid(driver.construction) and not driver.construction.nearby_task().is_empty(): driver.construction.work()
	else: driver.request_delivery()

func _process(delta: float) -> void:
	if not driver.care_visible():
		panel.hide()
		if is_instance_valid(marker): marker.hide()
		if is_instance_valid(cargo): cargo.hide()
		return
	elapsed+=delta
	if elapsed>=.12:
		elapsed=0
		refresh()
	update_cargo()

func refresh() -> void:
	var runtime=driver.delivery
	var job: Dictionary=runtime.job
	var pose: Dictionary=driver.delivery_pose()
	var pickup: String=runtime.nearest_offer(pose)
	var construction: Node=driver.construction
	var work: bool=is_instance_valid(construction) and not construction.attempt.is_empty() and job.is_empty() and pickup.is_empty()
	panel.visible=work or not job.is_empty() or not pickup.is_empty() or (not pose.is_empty() and not runtime.message.is_empty())
	if not panel.visible:
		if is_instance_valid(marker): marker.hide()
		return
	caption.text="Local deliveries · %d preview credits"%runtime.reward_total
	var target: Dictionary={}
	var ready: bool=false
	var task: Dictionary={}
	if not job.is_empty():
		if job.has("construction_attempt"): caption.text="Construction haul"
		var loading: bool=job["phase"]=="loading" or job.get("resume")=="loading" and job["phase"] in ["routing","blocked"]
		target=runtime.sites[job["pickup"] if loading else job["destination"]]
		caption.text+="\n%s · %s %d/%d"%[target["name"],Plan.goods()[job["goods"]]["name"],job["loaded"],job["quantity"]]
		if job["deadline"]>0: caption.text+=" · %ds"%ceili(maxf(0,job["deadline"]-job["elapsed"]))
		if not pose.is_empty() and job["phase"]=="carrying" and not runtime.at_site(pose,target):
			var offset: Vector2=target["point"]-pose["point"]
			var bearing: int=posmod(roundi(offset.angle()/(PI/4)),8)
			caption.text+="\n%d m %s"%[roundi(offset.length()),["E","SE","S","SW","W","NW","N","NE"][bearing]]
		if job["phase"]=="unloading": caption.text+="\nUnloading %d/%d"%[job["staged"],job["quantity"]]
		elif job["phase"]=="loading": caption.text+="\nLoading cargo"
		else: caption.text+="\n"+runtime.message
		var same_vehicle: bool=not driver.active.is_empty() and driver.active["item"]["uid"]==job["vehicle"]
		ready=same_vehicle and (job["phase"]=="blocked" or job["phase"]=="carrying" and runtime.at_site(pose,target))
	elif not pickup.is_empty():
		var contract: Dictionary=runtime.offers[pickup]
		if contract.has("construction_attempt"): caption.text="Construction haul · reward after building"
		target=runtime.sites[pickup]
		var destination: Dictionary=runtime.sites.get(contract["destination"],{})
		caption.text+="\n%s → %s\n%d %s"%[target["name"],destination.get("name","Missing site"),contract["quantity"],Plan.goods()[contract["goods"]]["name"].to_lower()]
		if not contract.has("construction_attempt"): caption.text+=" · %d credits"%contract["reward"]
		caption.text+="\n"+(runtime.message if not runtime.message.is_empty() else "Stop on the marked pickup pad.")
		ready=runtime.at_site(pose,target)
	elif work:
		caption.text="Foundation contract"
		if construction.reward_total>0: caption.text+=" · %d preview credits"%construction.reward_total
		task=construction.next_task()
		if not task.is_empty():
			target={"uid":task["id"],"point":task["approach"],"height":task["height"],"safe":true,"radius":.8}
			caption.text+="\n"+task["title"]
			ready=not construction.nearby_task().is_empty()
		elif construction.site_plan.get("ok",false) and not construction.terminal.has(construction.attempt):
			target=construction.site_plan["stations"]["pickup"]
		var hint: String=construction.message
		if hint.is_empty(): hint=construction.site_plan.get("reason","")
		if hint.is_empty(): hint="Drive an enabled delivery vehicle onto the marked supply pad."
		caption.text+="\n"+hint
	else: caption.text+="\n"+runtime.message
	if not target.is_empty(): update_marker(target)
	elif is_instance_valid(marker): marker.hide()
	action.text="Install" if not task.is_empty() else driver.delivery_key+" · Cargo"
	action.accessibility_name=task["title"] if not task.is_empty() else "Handle delivery cargo"
	action.disabled=not ready
	cancel.text="Cancel"
	cancel.tooltip_text=driver.delivery_cancel_key+(" · Cancel construction" if work or job.has("construction_attempt") else " · Cancel delivery")
	cancel.disabled=job.is_empty() and (not work or construction.terminal.has(construction.attempt) or not construction.site_plan.get("ok",false))
	apply_style()
	var size: Vector2=get_viewport().get_visible_rect().size
	var width: float=minf(available_width,maxf(270,size.x*.42))
	panel.custom_minimum_size.x=minf(minf(340*text_scale,width),size.x-24)
	panel.reset_size()
	panel.position=Vector2(maxf(12,size.x-panel.size.x-12),maxf(12,size.y-panel.size.y-bottom_inset))

func apply_style() -> void:
	var next: Array=[text_scale,large_targets,high_contrast]
	if next==style_key: return
	style_key=next
	caption.add_theme_font_size_override("font_size",roundi(13*text_scale))
	for control in [action,cancel]:
		control.add_theme_font_size_override("font_size",roundi(13*text_scale))
		control.custom_minimum_size.y=44 if large_targets else 34
	var style:=StyleBoxFlat.new()
	style.bg_color=Color.BLACK if high_contrast else Color("2d2317")
	style.border_color=Color.WHITE if high_contrast else TINT
	style.set_border_width_all(2 if high_contrast else 1)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel",style)

func at(point: Vector2,height: float) -> Variant:
	if driver.exploration.dimension=="2d": return Plan.Drive.world(point,"2d")-Vector2(0,height*8)
	return Plan.Drive.world(point,"3d",height)

func update_marker(site: Dictionary) -> void:
	var radius: float=site.get("radius",Plan.PAD_RADIUS)
	var key: Array=[site["uid"],site["point"],site["height"],site["safe"],radius]
	if is_instance_valid(marker):
		if key==marker_key:
			marker.show()
			return
		marker.free()
	marker_key=key
	var tint: Color=TINT if site["safe"] else Color.SALMON
	var height: float=site["height"]+.18
	var point: Vector2=site["point"]
	if driver.exploration.dimension=="2d":
		var line:=Line2D.new()
		line.width=3
		line.z_index=60
		line.closed=true
		line.default_color=tint
		for index in 24: line.add_point(at(point+Vector2.from_angle(index*TAU/24)*radius,height))
		marker=line
	else:
		var mesh:=ImmediateMesh.new()
		var material:=StandardMaterial3D.new()
		material.albedo_color=tint
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode=BaseMaterial3D.CULL_DISABLED
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES,material)
		for index in 24:
			var from: Vector2=Vector2.from_angle(index*TAU/24)
			var to: Vector2=Vector2.from_angle((index+1)*TAU/24)
			var outer: float=radius+.06
			var inner: float=radius-.06
			for offset in [from*inner,from*outer,to*outer,from*inner,to*outer,to*inner]:
				mesh.surface_add_vertex(at(point+offset,height))
		mesh.surface_end()
		var instance:=MeshInstance3D.new()
		instance.mesh=mesh
		marker=instance
	add_child(marker)

func update_cargo() -> void:
	var runtime=driver.delivery
	var job: Dictionary=runtime.job
	var pose: Dictionary=driver.delivery_pose()
	if job.is_empty() or pose.is_empty() or driver.active["item"]["uid"]!=job["vehicle"] or job["phase"] in ["routing","blocked"] and job["loaded"]==0:
		if is_instance_valid(cargo): cargo.hide()
		return
	var mode: String=driver.exploration.dimension
	var library: RefCounted=driver.exploration.library
	var asset: String=Plan.goods()[job["goods"]][mode]
	if not library.assets.has(asset): return
	if not is_instance_valid(cargo) or asset!=cargo_id:
		if is_instance_valid(cargo): cargo.free()
		cargo=Instance.make(library,asset,mode,false)
		if not is_instance_valid(cargo): return
		cargo_id=asset
		add_child(cargo)
		Instance.orient(cargo,library.directions(asset)[0],false)
		if mode=="2d":
			cargo.z_index=112
			cargo.scale=Vector2.ONE*.5
		else: cargo.scale=Vector3.ONE*.65
	var vehicle_point: Vector2=pose["point"]
	var height: float=pose["height"]+1.5
	var moving: bool=job["phase"] in ["loading","unloading"]
	if moving:
		var site: Dictionary=runtime.sites[job["pickup"] if job["phase"]=="loading" else job["destination"]]
		var heading: Vector2=Plan.Drive.heading(driver.active["yaw"])
		var staging: Vector2=site["point"]-heading*(pose["extent"].y+1.2)
		var t: float=clampf(job["clock"]/Plan.UNIT_SECONDS,0,1)
		if job["phase"]=="unloading": t=1-t
		vehicle_point=staging.lerp(vehicle_point,t)
		height=lerpf(site["height"]+.18,height,t)+sin(t*PI)*.35
	cargo.position=at(vehicle_point,height)
	cargo.show()
