extends RefCounted
const Plan=preload("res://scripts/builder/asset_import_plan.gd")
const Thumbnail=preload("res://scripts/builder/import_thumbnail.gd")
var studio: Control
var panel: ScrollContainer
var steps: Array[VBoxContainer]=[]
var stage: int=0
var title: Label
var notice: Label
var source_label: Label
var file: FileDialog
var name_field: LineEdit
var author: LineEdit
var license: LineEdit
var source_url: LineEdit
var category: OptionButton
var collision: CheckButton
var fields: Dictionary={}
var field_labels: Dictionary={}
var preview: SubViewport
var picture: TextureRect
var thumb: TextureRect
var review: Label
var source: Dictionary={}
var thumbnail: Image
var installed: Dictionary={}
var loading: bool=false
var preview_scale: float=1
var preview_origin:=Vector2.ZERO
var model_yaw: float=45
func _init(host: Control) -> void:
	studio=host; panel=ScrollContainer.new(); panel.name="Import assets"; panel.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; panel.follow_focus=true; studio.workspace_layout.tabs.add_child(panel)
	var box:=VBoxContainer.new(); box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; box.add_theme_constant_override("separation",8); panel.add_child(box)
	title=studio.label(box,"Import a custom asset",17); title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	for index in 4:
		var section:=VBoxContainer.new(); box.add_child(section); steps.append(section)
	button(steps[0],"Choose file...",func():file.popup_centered_ratio(.75))
	source_label=studio.label(steps[0],"PNG / JPEG / WebP sprite or GLB / glTF model",12); source_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	name_field=text(steps[0],"Asset name"); author=text(steps[0],"Author / attribution"); license=text(steps[0],"License or permission"); source_url=text(steps[0],"Source URL (optional)")
	category=OptionButton.new(); steps[0].add_child(category)
	for value in Plan.TYPES: category.add_item(value)
	button(steps[0],"Next: geometry",func():go(1))
	studio.label(steps[1],"Set the origin, contact point and occupied ground area. Sprite anchors use image pixels; model anchors use source coordinates. Footprints use ground units (sprite grid cells in 2D).",12).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	for entry in [["anchor_x","Anchor X",-100000,100000,.1],["anchor_y","Anchor Y",-100000,100000,.1],["anchor_z","Model anchor Z",-100000,100000,.1],["contact_x","Sprite ground contact X",-100000,100000,.1],["contact_y","Sprite ground contact Y",-100000,100000,.1],["width","Footprint width",1,64,1],["depth","Footprint depth",1,64,1],["height","Collision height",.05,256,.05],["scale","Model source scale",.001,1000,.001]]:
		field_labels[entry[0]]=studio.label(steps[1],entry[1],12); var control: SpinBox=studio.spin(steps[1],entry[2],entry[3],entry[4],maxf(entry[2],1)); fields[entry[0]]=control; control.value_changed.connect(func(_value: float): invalidate())
	collision=CheckButton.new(); collision.text="Solid footprint collision"; collision.button_pressed=true; steps[1].add_child(collision); collision.toggled.connect(func(_value: bool):invalidate())
	button(steps[1],"Reset source anchor",auto_anchor)
	button(steps[1],"Next: preview",func():go(2)); button(steps[1],"Back: source",func():go(0))
	preview=SubViewport.new(); preview.size=Vector2i(320,280); preview.transparent_bg=true; preview.own_world_3d=true; preview.world_2d=World2D.new(); preview.gui_disable_input=true; preview.render_target_update_mode=SubViewport.UPDATE_ALWAYS; studio.add_child(preview)
	picture=TextureRect.new(); picture.texture=preview.get_texture(); picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; picture.custom_minimum_size=Vector2(220,280); picture.size_flags_horizontal=Control.SIZE_EXPAND_FILL; steps[2].add_child(picture); picture.gui_input.connect(preview_input)
	studio.label(steps[2],"Blue shows the footprint; the cross marks the placement origin. Click a sprite to set its pivot, or edit exact coordinates in the previous step.",12).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	button(steps[2],"Turn model left",func():model_yaw-=45; update_preview()); button(steps[2],"Turn model right",func():model_yaw+=45; update_preview())
	button(steps[2],"Review thumbnail",func():go(3)); button(steps[2],"Back: geometry",func():go(1))
	thumb=TextureRect.new(); thumb.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; thumb.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; thumb.custom_minimum_size=Vector2(192,192); steps[3].add_child(thumb)
	review=studio.label(steps[3],"",12); review.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	button(steps[3],"Import asset",install); button(steps[3],"Back: preview",func():go(2))
	button(box,"Start again",reset)
	notice=studio.label(box,"Choose a local source to begin.",12); notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	file=FileDialog.new(); file.access=FileDialog.ACCESS_FILESYSTEM; file.file_mode=FileDialog.FILE_MODE_OPEN_FILE; file.title="Import sprite or model"; file.filters=PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Sprite images","*.glb,*.gltf ; glTF models"]); studio.add_child(file); file.file_selected.connect(load_source)
	for control in [name_field,author,license,source_url]: control.text_changed.connect(func(_value: String):invalidate())
	category.item_selected.connect(func(_value: int):invalidate()); show_step()
func button(parent: Node,label: String,callback: Callable) -> void:
	var control:=Button.new(); control.text=label; control.tooltip_text=label; control.clip_text=true; parent.add_child(control); control.pressed.connect(callback)
func text(parent: Node,label: String) -> LineEdit:
	studio.label(parent,label,12); var value:=LineEdit.new(); parent.add_child(value); return value
func show() -> void:
	if studio.walking: studio.set_walking(false)
	studio.workspace_presets.set_focus(false)
	if studio.get_viewport_rect().size.x<1200: studio.workspace_layout.library_toggle.button_pressed=false
	studio.workspace_layout.inspector_toggle.button_pressed=true; studio.workspace_layout.tabs.current_tab=panel.get_index()
func show_step() -> void:
	for index in steps.size(): steps[index].visible=index==stage
	title.text="Import asset · %d / 4 · %s" % [stage+1,["Source","Geometry","Preview","Review"][stage]]
	preview.render_target_update_mode=SubViewport.UPDATE_ALWAYS if stage==2 else SubViewport.UPDATE_DISABLED
func load_source(path: String) -> void:
	var loaded: Dictionary=Plan.inspect(path)
	if not loaded["ok"]: notice.text=loaded["reason"]; return
	Plan.release(source); source=loaded; installed={}; thumbnail=null; loading=true
	name_field.text=source["config"]["name"]; source_label.text=path.get_file()+" · "+("sprite" if source["mode"]=="2d" else "model")
	for key in ["anchor_x","anchor_y","anchor_z"]: fields[key].step=.000001 if source["mode"]=="3d" else .1
	apply_geometry(source["config"]);
	for key in fields:
		var visible_field: bool=not (key in ["anchor_z","scale"] and source["mode"]=="2d") and not (key in ["contact_x","contact_y"] and source["mode"]=="3d")
		fields[key].visible=visible_field; field_labels[key].visible=visible_field
	loading=false; stage=0; show_step(); notice.text="Source loaded. Name the asset, then set its anchors and footprint."
func apply_geometry(config: Dictionary) -> void:
	for pair in [["anchor_x",config["anchor"][0]],["anchor_y",config["anchor"][1]],["anchor_z",config["anchor"][2]],["contact_x",config["contact"][0]],["contact_y",config["contact"][1]],["width",config["footprint"][0]],["depth",config["footprint"][1]],["height",config["height"]],["scale",config["model_scale"]]]: fields[pair[0]].set_value_no_signal(pair[1])
	collision.set_pressed_no_signal(config["collision"])
func config() -> Dictionary:
	return {"name":name_field.text,"author":author.text,"license":license.text,"source_url":source_url.text,"category":Plan.TYPES[category.selected],"anchor":[fields["anchor_x"].value,fields["anchor_y"].value,fields["anchor_z"].value],"contact":[fields["contact_x"].value,fields["contact_y"].value],"footprint":[int(fields["width"].value),int(fields["depth"].value)],"height":fields["height"].value,"model_scale":fields["scale"].value,"collision":collision.button_pressed}
func invalidate() -> void:
	if loading: return
	thumbnail=null; installed={}
	if stage==2: update_preview()
func auto_anchor() -> void:
	if source.is_empty(): return
	loading=true; var value: Dictionary=config(); value["anchor"]=source["config"]["anchor"].duplicate(); value["contact"]=source["config"]["contact"].duplicate(); apply_geometry(value); loading=false; invalidate()
func go(index: int) -> void:
	if index>0 and source.is_empty(): notice.text="Choose a source file first."; return
	if index>0 and not Plan.valid(config()): notice.text="Enter a name and valid anchor, footprint, scale and height values."; return
	stage=index
	if index==2: update_preview()
	if index==3:
		thumbnail=Thumbnail.make(source,config()); thumb.texture=ImageTexture.create_from_image(thumbnail)
		review.text="%s\n%s · %d × %d footprint\nAuthor: %s\nLicense: %s\nA separate prepared asset and thumbnail will be saved in this project's custom library. Your source file is unchanged." % [name_field.text,source["mode"],fields["width"].value,fields["depth"].value,author.text,license.text]
	show_step(); notice.text=""
func preview_input(event: InputEvent) -> void:
	if source.get("mode")!="2d" or not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT: return
	var factor: float=minf(picture.size.x/320.0,picture.size.y/280.0); var offset: Vector2=(picture.size-Vector2(320,280)*factor)*.5; var point: Vector2=((event.position-offset)/factor-preview_origin)/preview_scale
	if point.x<0 or point.y<0 or point.x>source["image"].get_width() or point.y>source["image"].get_height(): return
	fields["anchor_x"].set_value_no_signal(point.x); fields["anchor_y"].set_value_no_signal(point.y); invalidate(); notice.text="Sprite pivot updated. Ground contact remains independently editable."
func update_preview() -> void:
	for node in preview.get_children(): node.free()
	if source.is_empty() or not Plan.valid(config()): return
	var value: Dictionary=config()
	if source["mode"]=="2d":
		var root:=Node2D.new(); preview.add_child(root); var image: Image=source["image"]; var anchor:=Vector2(value["anchor"][0],value["anchor"][1]); var framing:=Rect2(Vector2.ZERO,Vector2(image.get_size()))
		for point in [Vector2.ZERO,Vector2(value["footprint"][0],0),Vector2(value["footprint"][0],value["footprint"][1]),Vector2(0,value["footprint"][1])]: framing=framing.expand(anchor+Vector2((point.x-point.y)*16,(point.x+point.y)*8))
		preview_scale=minf(280.0/framing.size.x,240.0/framing.size.y); preview_origin=Vector2(160,140)-framing.get_center()*preview_scale
		var sprite:=Sprite2D.new(); sprite.texture=ImageTexture.create_from_image(image); sprite.centered=false; sprite.position=preview_origin; sprite.scale=Vector2.ONE*preview_scale; sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST; root.add_child(sprite)
		var origin: Vector2=preview_origin+anchor*preview_scale; var polygon:=PackedVector2Array()
		for point in [Vector2.ZERO,Vector2(value["footprint"][0],0),Vector2(value["footprint"][0],value["footprint"][1]),Vector2(0,value["footprint"][1])]: polygon.append(origin+Vector2((point.x-point.y)*16,(point.x+point.y)*8)*preview_scale)
		var footprint:=Polygon2D.new(); footprint.polygon=polygon; footprint.color=Color(.1,.65,1,.3); root.add_child(footprint)
		for direction in [Vector2.RIGHT,Vector2.DOWN]:
			var line:=Line2D.new(); line.add_point(origin-direction*7); line.add_point(origin+direction*7); line.width=2; line.default_color=Color.YELLOW; root.add_child(line)
	else:
		var model: Node3D=Plan.model_scene(source,value); preview.add_child(model)
		var bounds: AABB=Plan.Bounds.get_bounds(model).merge(AABB(Vector3(-value["footprint"][0]*.5,0,-value["footprint"][1]*.5),Vector3(value["footprint"][0],.05,value["footprint"][1]))); var camera:=Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=maxf(2,bounds.size.length()*1.25); preview.add_child(camera); camera.position=bounds.get_center()+Vector3(sin(deg_to_rad(model_yaw)),.8,cos(deg_to_rad(model_yaw)))*maxf(5,bounds.size.length()*2); camera.look_at(bounds.get_center()); camera.current=true
		var light:=DirectionalLight3D.new(); light.rotation_degrees=Vector3(-45,-30,0); preview.add_child(light)
		var environment:=WorldEnvironment.new(); environment.environment=Environment.new(); environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color=Color.WHITE; environment.environment.ambient_light_energy=.65; preview.add_child(environment)
		var mesh:=MeshInstance3D.new(); var box:=BoxMesh.new(); box.size=Vector3(value["footprint"][0],.035,value["footprint"][1]); mesh.mesh=box; var material:=StandardMaterial3D.new(); material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; material.albedo_color=Color(.1,.65,1,.4); mesh.material_override=material; mesh.position.y=.02; preview.add_child(mesh)
		for direction in [Vector3.RIGHT,Vector3.FORWARD]:
			var cross_mesh:=MeshInstance3D.new(); var shape:=BoxMesh.new(); shape.size=Vector3(.7,.05,.04) if direction==Vector3.RIGHT else Vector3(.04,.05,.7); cross_mesh.mesh=shape; var yellow:=StandardMaterial3D.new(); yellow.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; yellow.albedo_color=Color.YELLOW; cross_mesh.material_override=yellow; cross_mesh.position.y=.08; preview.add_child(cross_mesh)
func tick(_delta: float) -> void:
	preview.render_target_update_mode=SubViewport.UPDATE_ALWAYS if stage==2 and panel.is_visible_in_tree() else SubViewport.UPDATE_DISABLED
func install() -> void:
	var result: Dictionary=Plan.install(source,config(),thumbnail)
	if not result["ok"]: notice.text=result["reason"]; return
	installed=result["asset"]; studio.library.assets[installed["id"]]=installed.duplicate(true); studio.library.rebuild_indexes(); studio.library.invalidate_icons(installed["id"]); studio.asset_type.select(0); studio.pack_filter="Custom imports"; studio.favorites_only.set_pressed_no_signal(false); studio.populate_categories(); studio.search.text=""; studio.category.select(0); studio.refresh_library(); studio.select_asset(installed["id"])
	notice.text="Imported "+installed["name"]+". It is selected for placement; the library is filtered to Custom imports."
func reset() -> void:
	for node in preview.get_children(): node.free()
	Plan.release(source); thumbnail=null; installed={}; stage=0; source_label.text="PNG / JPEG / WebP sprite or GLB / glTF model"; notice.text="Choose a local source to begin."; show_step()

func _notification(what: int) -> void:
	if what==NOTIFICATION_PREDELETE: Plan.release(source)
