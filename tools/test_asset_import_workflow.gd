extends SceneTree
const Plan=preload("res://scripts/builder/asset_import_plan.gd")
const Custom=preload("res://scripts/builder/custom_assets.gd")
const Fit=preload("res://scripts/builder/grid_fit.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 5: await physics_frame
func fixtures() -> Dictionary:
	var folder: String=ProjectSettings.globalize_path("user://import-fixtures"); DirAccess.make_dir_recursive_absolute(folder)
	var image:=Image.create_empty(64,80,false,Image.FORMAT_RGBA8); image.fill(Color.TRANSPARENT); image.fill_rect(Rect2i(8,8,48,64),Color("df743a")); image.fill_rect(Rect2i(16,16,14,20),Color("5dbbe8")); image.save_png(folder+"/fixture.png")
	var model:=Node3D.new(); var mesh:=MeshInstance3D.new(); var shape:=BoxMesh.new(); shape.size=Vector3(2,4,6); mesh.mesh=shape; mesh.position=Vector3(3,1,5); var material:=StandardMaterial3D.new(); material.albedo_color=Color("56ad78"); var texture_image:=Image.create_empty(8,8,false,Image.FORMAT_RGBA8); texture_image.fill(Color("e9e1a7")); texture_image.fill_rect(Rect2i(0,0,4,4),Color("d26338")); material.albedo_texture=ImageTexture.create_from_image(texture_image); mesh.material_override=material; model.add_child(mesh)
	var document:=GLTFDocument.new(); var state:=GLTFState.new(); var error: Error=document.append_from_scene(model,state)
	if error==OK: error=document.write_to_filesystem(state,folder+"/fixture.glb")
	check(error==OK,"Create a real GLB source through Godot's glTF exporter")
	check(document.write_to_filesystem(state,folder+"/external.gltf")==OK,"Create glTF with external buffers and textures"); model.free()
	return {"2d":folder+"/fixture.png","3d":folder+"/fixture.glb"}
func run() -> void:
	Custom.registry_override="res://output/custom_asset_test_registry.json"; Custom.save_registry({})
	var sources: Dictionary=fixtures(); var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle(); studio._command("import_asset",null); var ui: RefCounted=studio.asset_import_tools
	check(ui.panel.is_visible_in_tree() and ui.stage==0,"Command opens the first wizard step")
	ui.go(1); check(ui.stage==0 and not ui.notice.text.is_empty(),"Wizard requires a source before geometry")
	var imported: Dictionary={}
	for mode in ["2d","3d"]:
		ui.load_source(sources[mode]); check(ui.source.get("mode")==mode and ui.stage==0,"Source selection decodes a real image/model: "+mode)
		ui.name_field.text="Imported "+mode; ui.author.text="IsoCity fixture author"; ui.license.text="CC0 fixture"; ui.category.select(2); ui.go(1)
		ui.fields["width"].value=4; ui.fields["depth"].value=8; ui.fields["height"].value=5
		if mode=="2d": ui.fields["anchor_x"].value=24; ui.fields["anchor_y"].value=68; ui.fields["contact_x"].value=32; ui.fields["contact_y"].value=72
		else:
			ui.fields["anchor_x"].value=2.03125; check(is_equal_approx(ui.fields["anchor_x"].value,2.03125),"Model anchor fields preserve precise source coordinates")
			ui.fields["scale"].value=.5; ui.fields["anchor_x"].value=2; ui.fields["anchor_y"].value=-1; ui.fields["anchor_z"].value=4
		ui.go(2); await settle(); check(ui.stage==2 and ui.preview.get_child_count()>0,"Geometry step opens a real source preview: "+mode)
		if mode=="2d":
			var click:=InputEventMouseButton.new(); click.button_index=MOUSE_BUTTON_LEFT; click.pressed=true; var factor: float=minf(ui.picture.size.x/320.0,ui.picture.size.y/280.0); click.position=(ui.picture.size-Vector2(320,280)*factor)*.5+(ui.preview_origin+Vector2(20,60)*ui.preview_scale)*factor; ui.preview_input(click)
			check(is_equal_approx(ui.fields["anchor_x"].value,20) and is_equal_approx(ui.fields["anchor_y"].value,60),"Actual sprite-preview click updates pivot coordinates")
			ui.fields["anchor_x"].value=24; ui.fields["anchor_y"].value=68
		if "--capture" in OS.get_cmdline_user_args():
			RenderingServer.force_draw(false); RenderingServer.force_draw(false); ui.preview.get_texture().get_image().save_png("res://output/asset_import_preview_"+mode+".png")
		ui.go(3); check(ui.thumbnail!=null and ui.thumbnail.get_size()==Vector2i(192,192) and ui.thumbnail.get_used_rect().size!=Vector2i.ZERO,"Review generates a nonempty asset thumbnail: "+mode)
		if "--capture" in OS.get_cmdline_user_args(): ui.thumbnail.save_png("res://output/asset_import_thumbnail_"+mode+".png")
		ui.install(); check(not ui.installed.is_empty() and studio.library.assets.has(ui.installed.get("id")),"Actual Import action registers the prepared asset: "+mode)
		if ui.installed.is_empty(): print(ui.notice.text); continue
		var asset: Dictionary=ui.installed; imported[mode]=asset["id"]
		check(FileAccess.file_exists(asset["path"]) and FileAccess.file_exists(asset["data"]["preview_path"]) and FileAccess.file_exists(asset["path"].get_base_dir()+"/LICENSE.txt"),"Import saves a scene, thumbnail and attribution: "+mode)
		check(asset["behavior"]["building"] and asset["data"]["author"]=="IsoCity fixture author","Explicit category behavior and attribution survive registration: "+mode)
		var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new(); check(library.assets.has(asset["id"]) and library.icon(asset["id"])!=null,"A fresh library reloads the import and thumbnail: "+mode)
		if mode=="2d":
			var sample: Dictionary={"asset":asset["id"],"position":[0,0,0],"direction":"SE","scale":1.0}; check(is_equal_approx(Fit.sprite_box(sample,library).size.y,2.25),"Top snapping reads sprite geometry before scene-tree entry")
		var prepared: Node=load(asset["path"]).instantiate(); root.add_child(prepared); await settle()
		if mode=="2d":
			check(prepared.origin_offset==Vector2(24,68) and prepared.footprint==Vector2i(4,8) and prepared.get_node("Sprite2D").texture.get_size()==Vector2(64,80),"Prepared sprite retains its exact image, pivot and footprint")
		else:
			var bounds: AABB=preload("res://scripts/model_bounds.gd").get_bounds(prepared); check(bounds.position.is_equal_approx(Vector3(0,0,-1)) and bounds.size.is_equal_approx(Vector3(1,2,3)),"Prepared model applies source anchor and scale exactly")
			var contact: AABB=Fit.bounds_for(asset["id"],library); check(contact.position==Vector3(-2,0,-4) and contact.size==Vector3(4,5,8),"Grid snapping uses the authored model footprint")
		prepared.free()
		var same: Dictionary=Plan.install(ui.source,ui.config(),ui.thumbnail); check(same["ok"] and same["existing"] and same["asset"]["id"]==asset["id"],"Identical imports reuse their stable asset identity: "+mode)
	var external: Dictionary=Plan.inspect(sources["3d"].get_base_dir()+"/external.gltf")
	check(external["ok"] and external.get("files",{}).size()>=3,"glTF inspection tracks external buffers and textures")
	if external["ok"]:
		var image: Image=preload("res://scripts/builder/import_thumbnail.gd").make(external,external["config"]); var result: Dictionary=Plan.install(external,external["config"],image)
		check(result["ok"] and not FileAccess.get_file_as_string(result["asset"]["path"]).contains("user://") and not FileAccess.get_file_as_string(result["asset"]["path"]).contains(sources["3d"].get_base_dir()),"Prepared glTF embeds resources instead of referencing the source folder")
		var original_catalog: String=FileAccess.get_file_as_string(Custom.registry_path()); var dependency: String=external["files"].keys()[1]; var changed:=FileAccess.open(dependency,FileAccess.READ_WRITE); changed.seek_end(); changed.store_8(0); changed.close()
		result=Plan.install(external,external["config"],image); check(not result["ok"] and result["reason"].contains("changed") and FileAccess.get_file_as_string(Custom.registry_path())==original_catalog,"Changing an external source prevents stale imports and preserves the catalog")
		Plan.release(external)
	var quiet_config: Dictionary=ui.config(); quiet_config["collision"]=false; quiet_config["name"]="Non-solid model fixture"
	var quiet: Dictionary=Plan.install(ui.source,quiet_config,ui.thumbnail); check(quiet["ok"],"Import can disable solid collision")
	if quiet["ok"]:
		studio.library.assets[quiet["asset"]["id"]]=quiet["asset"]
		for mode in ["2d","3d"]:
			var node: Node=preload("res://scripts/builder/asset_instance.gd").make(studio.library,quiet["asset"]["id"],mode); root.add_child(node); await settle()
			check(node.get_child_count()>0 and (not node.has_node("FootprintCollision") if mode=="3d" else not node.collidable),"Collision-free model remains non-solid in native and mixed views: "+mode); node.free()
	var sprite_source: Dictionary=Plan.inspect(sources["2d"]); var sprite_config: Dictionary=sprite_source["config"].duplicate(true); sprite_config["collision"]=false; sprite_config["name"]="Non-solid sprite fixture"
	var quiet_sprite: Dictionary=Plan.install(sprite_source,sprite_config,preload("res://scripts/builder/import_thumbnail.gd").make(sprite_source,sprite_config)); check(quiet_sprite["ok"],"Import can disable sprite collision")
	if quiet_sprite["ok"]:
		studio.library.assets[quiet_sprite["asset"]["id"]]=quiet_sprite["asset"]
		for mode in ["2d","3d"]:
			var node: Node=preload("res://scripts/builder/asset_instance.gd").make(studio.library,quiet_sprite["asset"]["id"],mode); root.add_child(node); await settle(); check(not node.has_node("StaticBody2D") if mode=="2d" else node.collision_layer==0,"Collision-free sprite remains non-solid in native and mixed views: "+mode); node.free()
	Plan.release(sprite_source)
	var registry: String=Custom.registry_override; var original_catalog: String=FileAccess.get_file_as_string(registry)
	var blocked:=FileAccess.open("res://output/import_catalog_blocker",FileAccess.WRITE); blocked.store_string("not a directory"); blocked.close(); Custom.registry_override="res://output/import_catalog_blocker/catalog.json"
	var retry_config: Dictionary=ui.config(); retry_config["name"]="Catalog retry fixture"; var retry: Dictionary=Plan.install(ui.source,retry_config,ui.thumbnail)
	check(not retry["ok"] and retry["reason"].contains("catalog") and FileAccess.get_file_as_string(registry)==original_catalog,"A failed catalog write leaves the existing catalog untouched")
	Custom.registry_override=registry; retry=Plan.install(ui.source,retry_config,ui.thumbnail); check(retry["ok"],"The unchanged pending import succeeds after a catalog write failure")
	for mode in ["2d","3d"]:
		studio.switch_mode(mode); var doc: RefCounted=studio.current()
		for native in ["2d","3d"]: doc.add(imported[native],[0,0,0] if native=="2d" else ([180,80,0] if mode=="2d" else [8,0,0]),"SE" if native=="2d" else "90",1)
		studio.changed(); await settle(); check(studio.worlds[mode].instances.size()==doc.data["objects"].size(),"Native and mixed imported assets instantiate in the city: "+mode)
		check(preload("res://scripts/builder/document.gd").valid(doc.data,mode,studio.library),"Imported placements use ordinary document validation: "+mode)
		var path: String="res://output/custom_import_"+mode; check(studio.write_project(path+".isocity.json"),"Project saving preserves imported placements: "+mode)
		var repair=preload("res://scripts/builder/project_repair.gd").new(studio.library); var reopened: Dictionary=repair.read(path+".isocity.json"); check(reopened["ok"] and repair.issues.is_empty(),"Imported assets reopen without placeholders or repairs: "+mode)
		studio.show_file_dialog("export"); studio.file_dialog.hide(); studio._file_selected(path+".tscn"); studio._command("export_portable",null); studio.file_dialog.hide(); studio._file_selected(path+".zip"); check(FileAccess.file_exists(path+".zip"),"Portable export includes both imported asset types: "+mode)
	var size_before: Vector2i=root.size; root.size=Vector2i(960,640); studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true}); ui.show(); ui.go(3); await settle()
	var import_button: Button
	for button in ui.panel.find_children("*","Button",true,false):
		if button.text=="Import asset": import_button=button; break
	ui.panel.ensure_control_visible(import_button); import_button.grab_focus(); await settle(); check(import_button.get_global_rect().intersects(ui.panel.get_global_rect()) and ui.panel.get_v_scroll_bar().max_value>ui.panel.size.y,"Large-text wizard scrolls the focused import action into view at 960×640")
	if "--capture" in OS.get_cmdline_user_args():
		RenderingServer.force_draw(false); RenderingServer.force_draw(false); root.get_texture().get_image().save_png("res://output/asset_import_accessible.png")
	root.size=size_before; studio.accessibility_settings.restore({})
	ui.reset(); studio.free(); await process_frame; await process_frame
	Custom.registry_override=""; print("Asset import workflow: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
