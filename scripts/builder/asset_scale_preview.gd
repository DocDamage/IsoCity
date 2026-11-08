extends RefCounted

# These private worlds use the placement factory. They never join the city,
# its instance map, history, catalog, or exported scene.
const Factory=preload("res://scripts/builder/asset_instance.gd")
const Bounds=preload("res://scripts/model_bounds.gd")
const Grid=preload("res://scripts/builder/grid_fit.gd")
const Repair=preload("res://scripts/builder/repair_assets.gd")
const PERSON_2D="2d:Office_Worker"
const CAR_2D="2d:Hatchback_Yellow"
const CAR_3D="3d:Supplemental_SWAT/Vehicle_Unmarked_Sedan"
var browser_ref: WeakRef
var browser: RefCounted:
	get:return browser_ref.get_ref()
var studio: Control
var toggle: CheckButton
var panel: VBoxContainer
var container: SubViewportContainer
var viewport: SubViewport
var view: OptionButton
var span: OptionButton
var size_input: SpinBox
var person: CheckButton
var car: CheckButton
var grid: CheckButton
var note: Label
var turn_row: HBoxContainer
var world: Node
var sample: Node
var camera: Node
var references: Array[Node]=[]
var reference_ids: Array[String]=[]
var lines: Node
var outline: Node
var record: Dictionary={}
var mode: String="2d"
var visual_2d:=Rect2()
var framing_2d:=Rect2()
var visual_3d:=AABB()
var ground_2d:=PackedVector2Array()
var ground_3d:=AABB()
var missing: PackedStringArray=[]
var yaw: float=45
var updating: bool=false
var context_label: String=""
var projection_size:=Vector2i.ZERO
var projection_scale:=Vector2.ONE

func _init(owner: RefCounted,box: VBoxContainer) -> void:
	browser_ref=weakref(owner);studio=browser.studio
	toggle=CheckButton.new();toggle.text="Compare placement size";box.add_child(toggle)
	toggle.tooltip_text="Person, car and calibrated grid references in the current world's actual placement representation. Preview only."
	panel=VBoxContainer.new();panel.hide();box.add_child(panel)
	var controls:=HFlowContainer.new();panel.add_child(controls)
	view=OptionButton.new();view.add_item("Fit asset");view.add_item("Same scale");controls.add_child(view)
	view.tooltip_text="Fit asset changes zoom for this asset. Same scale keeps the chosen field of view across assets; large objects may extend outside it."
	span=OptionButton.new()
	for value in [4,16,64,256]:span.add_item(str(value)+" units high");span.set_item_metadata(span.item_count-1,value)
	span.select(1);controls.add_child(span)
	var scale_label:=Label.new();scale_label.text="Scale · preview only";controls.add_child(scale_label)
	size_input=SpinBox.new();size_input.min_value=.001;size_input.max_value=1000;size_input.step=.001;size_input.value=1;size_input.suffix="×";controls.add_child(size_input)
	size_input.tooltip_text="Starts with the selected object's saved scale, the current placement scale, or the asset's default. Changing it here never changes placement."
	var options:=HFlowContainer.new();panel.add_child(options)
	person=check(options,"Person");car=check(options,"Car");grid=check(options,"Grid")
	container=SubViewportContainer.new();container.custom_minimum_size=Vector2(320,220);container.stretch=true;container.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;panel.add_child(container)
	viewport=SubViewport.new();viewport.size=Vector2i(640,360);viewport.world_2d=World2D.new();viewport.own_world_3d=true;viewport.gui_disable_input=true;viewport.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE;container.add_child(viewport)
	turn_row=HBoxContainer.new();panel.add_child(turn_row)
	for amount in [-45,45]:
		var button:=Button.new();button.text="View left" if amount<0 else "View right";turn_row.add_child(button)
		button.tooltip_text="Orbit the comparison camera; preserve the object's placed orientation."
		button.pressed.connect(func():yaw=wrapf(yaw+amount,0,360);arrange())
	note=Label.new();note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;panel.add_child(note)
	container.resized.connect(arrange)
	toggle.toggled.connect(func(_value: bool):refresh())
	view.item_selected.connect(func(_index: int):arrange())
	span.item_selected.connect(func(_index: int):arrange())
	size_input.value_changed.connect(func(_value: float):if not updating:rebuild())
	for option in [person,car,grid]:option.toggled.connect(func(_value: bool):arrange())

func check(parent: Node,text: String) -> CheckButton:
	var result:=CheckButton.new();result.text=text;result.button_pressed=true;parent.add_child(result);return result

func clear() -> void:
	if is_instance_valid(world):world.free()
	world=null;sample=null;camera=null;lines=null;outline=null;references.clear();reference_ids.clear();missing.clear()
	projection_size=Vector2i.ZERO

func refresh(reset_scale: bool=false) -> void:
	panel.visible=toggle.button_pressed and not browser.selected_id.is_empty()
	browser.details.visible=not panel.visible
	browser.picture.visible=not panel.visible and not browser.selected_id.is_empty() and studio.library.assets[browser.selected_id]["mode"]=="2d"
	browser.model_container.visible=not panel.visible and not browser.selected_id.is_empty() and studio.library.assets[browser.selected_id]["mode"]=="3d"
	browser.orbit_row.visible=browser.model_container.visible
	if not panel.visible:clear();return
	if reset_scale or record.get("asset","")!=browser.selected_id:
		record=initial_record();updating=true;size_input.set_value_no_signal(record["scale"]);updating=false
	rebuild()

func initial_record() -> Dictionary:
	var id: String=browser.selected_id
	var result: Dictionary={"asset":id,"uid":"__scale_preview__","position":[0,0,0],"direction":str(studio.library.directions(id)[0]),"scale":studio.library.assets[id]["data"].get("default_scale",1.0)}
	var items: Array=studio.selection_items()
	context_label="Asset default"
	if items.size()==1 and items[0]["asset"]==id:
		for key in ["direction","scale","angle","tilt"]:
			if items[0].has(key):result[key]=items[0][key].duplicate() if items[0][key] is Array else items[0][key]
		context_label="Selected object transform"
	elif studio.asset_id==id:
		result.merge(studio.placement_record(),true);result["scale"]=studio.scale_input.value;context_label="Current placement transform"
	return result

func rebuild() -> void:
	clear()
	if not panel.visible or browser.selected_id.is_empty():return
	mode=studio.mode;record["scale"]=size_input.value
	if studio.library.assets[browser.selected_id]["mode"]=="2d" and browser.views.item_count>0:record["direction"]=browser.views.get_item_text(browser.views.selected)
	if not Repair.available(record["asset"],studio.library,{}):note.text="Scale comparison unavailable: prepared scene or required artwork is missing.";return
	world=Node2D.new() if mode=="2d" else Node3D.new();world.name="PrivatePlacementComparison";viewport.add_child(world)
	if mode=="3d":
		var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("182838");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.8;world.add_child(environment)
		var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-30,0);world.add_child(light)
		var fill:=DirectionalLight3D.new();fill.rotation_degrees=Vector3(-25,150,0);fill.light_energy=.5;world.add_child(fill)
	sample=Factory.make(studio.library,record["asset"],mode);sample.name="PreviewAsset";world.add_child(sample)
	Factory.pose(sample,record,false)
	sample.position=Vector2.ZERO if mode=="2d" else Vector3.ZERO
	sample.scale=(Vector2.ONE if mode=="2d" else Vector3.ONE)*float(record["scale"])
	freeze(sample)
	if mode=="2d":
		visual_2d=screen_bounds(sample);ground_2d=sample.transform*Factory.footprint(sample)
		framing_2d=projected_geometry(sample) if record["asset"].begins_with("3d:") else visual_2d
		if record["asset"].begins_with("3d:"):projection_size=sample.viewport.size;projection_scale=sample.sprite.scale
		camera=Camera2D.new();world.add_child(camera)
	else:
		visual_3d=render_bounds(sample)
		ground_3d=sample.transform*Bounds.contact_bounds(sample) if not sample.has_method("mixed_bounds") else sample.transform*sample.mixed_bounds()
		camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_HEIGHT;camera.current=true;camera.near=.001;world.add_child(camera)
	make_references();arrange()

static func freeze(node: Node) -> void:
	node.process_mode=Node.PROCESS_MODE_DISABLED
	for child in [node]+node.find_children("*","",true,false):
		if child is CollisionObject2D or child is CollisionObject3D:child.collision_layer=0;child.collision_mask=0

static func screen_bounds(root: Node2D) -> Rect2:
	var result:=Rect2();var found: bool=false
	for node in [root]+root.find_children("*","Sprite2D",true,false):
		if not node is Sprite2D or not node.texture:continue
		var rect: Rect2=node.get_rect()
		var transform: Transform2D=root.transform*root.global_transform.affine_inverse()*node.global_transform
		var box: Rect2=transform*rect
		result=result.merge(box) if found else box;found=true
	return result if found else Rect2(Vector2.ZERO,Vector2.ONE)

# Render bounds deliberately include a flat sprite card's actual mesh; its
# calibrated footprint is measured separately, never inferred from pixel height.
static func render_bounds(root: Node3D) -> AABB:
	var result:=AABB();var found: bool=false
	for node in [root]+root.find_children("*","MeshInstance3D",true,false):
		if not node is MeshInstance3D or not node.mesh:continue
		var transform: Transform3D=root.transform*root.global_transform.affine_inverse()*node.global_transform
		var box: AABB=transform*node.mesh.get_aabb()
		result=result.merge(box) if found else box;found=true
	return result if found else AABB(Vector3.ZERO,Vector3.ONE*.01)

static func projected_geometry(root: Node2D) -> Rect2:
	# The normal placement texture has fixed pixel padding. Fit the actual
	# prepared model rather than that padding, while preserving its canvas size.
	var box: AABB=render_bounds(root.model)
	var result:=Rect2()
	for index in 8:
		var point: Vector3=root.camera.basis.inverse()*box.get_endpoint(index)
		var pixel: Vector2=root.transform*(Vector2(point.x,-point.y)*root.PIXELS_PER_UNIT)
		result=Rect2(pixel,Vector2.ZERO) if index==0 else result.expand(pixel)
	return result

func make_references() -> void:
	if mode=="3d":
		var walker: Node3D=preload("res://scripts/builder/player_3d.gd").new();walker.name="PersonReference";world.add_child(walker);freeze(walker);references.append(walker);reference_ids.append("Runtime 3D walker")
	else:add_reference(PERSON_2D,"PersonReference")
	add_reference(CAR_2D if mode=="2d" else CAR_3D,"CarReference")
	lines=Node2D.new() if mode=="2d" else MeshInstance3D.new();lines.name="GridReference";world.add_child(lines)
	outline=Node2D.new() if mode=="2d" else MeshInstance3D.new();outline.name="CalibratedFootprint";world.add_child(outline)

func add_reference(id: String,label: String) -> void:
	if not Repair.available(id,studio.library,{}):missing.append(label.trim_suffix("Reference")+" reference unavailable in this library.");return
	var node: Node=Factory.make(studio.library,id,mode);node.name=label;world.add_child(node)
	Factory.pose(node,{"asset":id,"direction":"SE" if id.begins_with("2d:") else "0"},false);freeze(node);references.append(node);reference_ids.append(id)
	node.position=Vector2.ZERO if mode=="2d" else Vector3.ZERO
	node.scale=(Vector2.ONE if mode=="2d" else Vector3.ONE)*float(studio.library.assets[id]["data"].get("default_scale",1))

func span_value() -> float:return float(span.get_item_metadata(span.selected))

func arrange() -> void:
	span.disabled=view.selected==0
	for index in span.item_count:span.set_item_text(index,str(span.get_item_metadata(index))+(" diamond heights" if studio.mode=="2d" else " world units high"))
	turn_row.visible=mode=="3d"
	if not is_instance_valid(sample) or not is_instance_valid(camera):return
	var aspect: float=maxf(.1,float(viewport.size.x)/maxf(1,viewport.size.y))
	var field: float=span_value()
	var center: Vector2=visual_2d.get_center() if mode=="2d" else Vector2(visual_3d.get_center().x,visual_3d.get_center().z)
	if mode=="2d":
		var pixels: float=maxf(.02,maxf(framing_2d.size.y,framing_2d.size.x/aspect)*1.2) if view.selected==0 else field*16
		var ground_y: float=0
		for point in ground_2d:ground_y=maxf(ground_y,point.y)
		camera.position=framing_2d.get_center() if view.selected==0 else Vector2(visual_2d.get_center().x,ground_y-32)
		camera.zoom=Vector2.ONE*float(viewport.size.y)/pixels
		field=pixels/16
		projection_quality()
		for node in references:
			node.position=Vector2(visual_2d.end.x+(24 if node.name=="PersonReference" else 80),ground_y)
	else:
		var direction:=Vector3(sin(deg_to_rad(yaw)),.8,cos(deg_to_rad(yaw))).normalized()
		var target: Vector3=visual_3d.get_center()
		if view.selected==1:target.y=1
		camera.position=target+direction*maxf(10,visual_3d.size.length()*3);camera.look_at(target);camera.far=maxf(100,visual_3d.size.length()*10)
		var projected:=Rect2()
		var points: PackedVector3Array=view_points()
		for index in points.size():
			var point: Vector3=camera.basis.inverse()*points[index]
			projected=Rect2(Vector2(point.x,point.y),Vector2.ZERO) if index==0 else projected.expand(Vector2(point.x,point.y))
		camera.size=maxf(.001,maxf(projected.size.y,projected.size.x/aspect)*1.2) if view.selected==0 else field
		field=camera.size
		var right:=Vector3(cos(deg_to_rad(yaw)),0,-sin(deg_to_rad(yaw)))
		for node in references:node.position=Vector3(center.x,0,center.y)+right*(projected.size.x*.5+(1.2 if node.name=="PersonReference" else 4.5))
	var clipped_references: bool=false
	for node in references:
		var enabled: bool=person.button_pressed if node.name=="PersonReference" else car.button_pressed
		var fits: bool=true
		if enabled and view.selected==0:
			if mode=="2d":
				var area: Vector2=Vector2(viewport.size)/camera.zoom
				fits=Rect2(camera.position-area*.5,area).encloses(screen_bounds(node))
			else:
				var box: AABB=render_bounds(node)
				for index in 8:
					if not Rect2(Vector2.ZERO,Vector2(viewport.size)).has_point(camera.unproject_position(box.get_endpoint(index))):fits=false;break
			if not fits:clipped_references=true
		node.visible=enabled and fits
	lines.visible=grid.button_pressed;outline.visible=grid.button_pressed
	var step: int=maxi(1,ceili(field/24))
	draw_grid(center,step)
	var source_sprite: bool=studio.library.assets[record["asset"]]["mode"]=="2d"
	var dimensions: String=""
	if source_sprite:
		var foot: Vector2
		if mode=="2d":
			var low:=Vector2(INF,INF);var high:=Vector2(-INF,-INF)
			for point in ground_2d:low=low.min(Grid.grid(point));high=high.max(Grid.grid(point))
			foot=high-low
		else:foot=Vector2(ground_3d.size.x,ground_3d.size.z)
		dimensions="Calibrated ground footprint %s × %s %s. Artwork height is not physical height."%[number(foot.x),number(foot.y),"grid cells" if mode=="2d" else "world units"]
		if mode=="3d":dimensions+=" Flat sprite card, as placed."
	else:
		var box: AABB=render_bounds(sample.model) if mode=="2d" else visual_3d
		if mode=="2d":box=AABB(box.position*float(record["scale"]),box.size*float(record["scale"]))
		dimensions="Prepared model %s × %s × %s source units (X / height / Z), at %s×."%[number(box.size.x),number(box.size.y),number(box.size.z),number(record["scale"])]
	note.text=context_label+" · still pose · "+mode.to_upper()+" placement.\n"+dimensions
	if source_sprite:note.text+=" Source angle: "+str(record["direction"])+" (preview)."
	note.text+="\n"+("Same scale: " if view.selected==1 else "Fit asset: zoom varies. ")+ ("%s canvas px high; one grid cell is a 32 × 16 px diamond."%number(field*16) if mode=="2d" else "%s world units high; one grid cell is one world unit."%number(field))
	note.text+=" Grid spacing: %d. Person/car keep their normal placement size. References or large assets may extend outside the view."%step
	if clipped_references:note.text+=" References outside this close-up are hidden; use Same scale for context."
	if not missing.is_empty():note.text+="\n"+" ".join(missing)
	note.tooltip_text=note.text

static func number(value: float) -> String:
	return String.num(value,clampi(3-floori(log(absf(value))/log(10.0)),0,12)) if value!=0 else "0"

func projection_quality() -> void:
	if projection_size==Vector2i.ZERO:return
	# Supersample only this private model projection. Keep its camera frustum
	# and canvas rectangle fixed, compensating the texture's extra pixels on
	# Sprite2D. A close-up of a tiny model must not enlarge an eight-pixel render.
	var factor: int=clampi(ceili(camera.zoom.x*absf(sample.scale.x)*projection_scale.x),1,maxi(1,floori(2048.0/maxi(projection_size.x,projection_size.y))))
	var target: Vector2i=projection_size*factor
	if sample.viewport.size==target:return
	sample.viewport.size=target;sample.sprite.scale=projection_scale/float(factor)
	sample.viewport.render_target_update_mode=SubViewport.UPDATE_ONCE

func view_points() -> PackedVector3Array:
	var result:=PackedVector3Array()
	if sample.has_method("mixed_bounds") and sample.material.billboard_mode==BaseMaterial3D.BILLBOARD_FIXED_Y:
		# Fixed-Y billboards turn in the renderer. Fitting the unturned quad's
		# AABB would crop wide cards at oblique camera angles.
		var center: Vector3=sample.transform*sample.mesh.position
		var right:=Vector3(cos(deg_to_rad(yaw)),0,-sin(deg_to_rad(yaw)))
		var half: Vector2=sample.mesh.mesh.size*Vector2(sample.scale.x,sample.scale.y)*.5
		for x in [-1,1]:
			for y in [-1,1]:result.append(center+right*half.x*x+Vector3.UP*half.y*y)
	else:
		for index in 8:result.append(visual_3d.get_endpoint(index))
	return result

func draw_grid(center: Vector2,step: int) -> void:
	var vertices:=PackedVector3Array();var color:=Color(.35,.55,.65,.7)
	var ground_center: Vector2=Grid.grid(Vector2(ground_2d[0])) if mode=="2d" and not ground_2d.is_empty() else center
	if mode=="2d":
		for child in lines.get_children():child.free()
		for child in outline.get_children():child.free()
	var extent: int=32*step
	ground_center=(ground_center/step).floor()*step
	for index in range(-extent,extent+1,step):
		for pair in [[Vector2(index,-extent),Vector2(index,extent)],[Vector2(-extent,index),Vector2(extent,index)]]:
			if mode=="2d":line_2d(lines,[Grid.pixels(ground_center+pair[0]),Grid.pixels(ground_center+pair[1])],color)
			else:vertices.append(Vector3(ground_center.x+pair[0].x,0,ground_center.y+pair[0].y));vertices.append(Vector3(ground_center.x+pair[1].x,0,ground_center.y+pair[1].y))
	if mode=="2d":
		var polygon: PackedVector2Array=ground_2d.duplicate()
		if not polygon.is_empty():polygon.append(polygon[0]);line_2d(outline,polygon,Color("ffd36f"))
	else:
		mesh_lines(lines,vertices,color)
		var a: Vector3=ground_3d.position;var b: Vector3=ground_3d.end
		mesh_lines(outline,PackedVector3Array([Vector3(a.x,.01,a.z),Vector3(b.x,.01,a.z),Vector3(b.x,.01,a.z),Vector3(b.x,.01,b.z),Vector3(b.x,.01,b.z),Vector3(a.x,.01,b.z),Vector3(a.x,.01,b.z),Vector3(a.x,.01,a.z)]),Color("ffd36f"))

func line_2d(parent: Node,points: PackedVector2Array,color: Color) -> void:
	var line:=Line2D.new();line.points=points;line.width=1/maxf(.0001,camera.zoom.x);line.default_color=color;parent.add_child(line);line.z_index=-1 if parent==lines else 1

static func mesh_lines(node: MeshInstance3D,points: PackedVector3Array,color: Color) -> void:
	var mesh:=ImmediateMesh.new();mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for point in points:mesh.surface_add_vertex(point)
	mesh.surface_end();node.mesh=mesh
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=color;material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;node.material_override=material
