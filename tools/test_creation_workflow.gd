extends SceneTree
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 12: await process_frame
func run() -> void:
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	var ui: RefCounted=studio.creation_tools; studio._command("creation_sharing",null); check(ui.panel.is_visible_in_tree(),"Command opens creation sharing controls")
	ui.fields["author"].text="Fixture creator"; ui.fields["license"].text="CC BY 4.0"; ui.description.text="A native and mixed creation"
	for mode in ["2d","3d"]:
		studio.switch_mode(mode); var doc: RefCounted=studio.current(); doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
		var id: String="2d:Sedan_Blue" if mode=="2d" else "3d:HanX_Traffic/Car_Sedan"; var other: String="3d:HanX_Traffic/Car_Sedan" if mode=="2d" else "2d:Sedan_Blue"
		doc.add(id,[0,0,0],str(studio.library.directions(id)[0]),1); doc.add(other,[100,0,0] if mode=="2d" else [4,0,0],str(studio.library.directions(other)[0]),1); studio.changed(); await settle()
		ui.kind.select(0); ui.fields["title"].text="Shared "+mode; await ui.generate(); check(ui.preview!=null and ui.source["document"]["objects"].size()==2,"Preview captures exact native/mixed city source: "+mode)
		if "--capture" in OS.get_cmdline_user_args(): ui.preview.save_png("res://output/creation_preview_"+mode+".png")
		var before: Dictionary=ui.source["document"].duplicate(true); doc.add(id,[300,0,0] if mode=="2d" else [20,0,0],str(studio.library.directions(id)[0]),1); studio.changed()
		check(ui.source["document"]["objects"].size()==2 and doc.data["objects"].size()==3,"Later editing does not silently change the previewed publication snapshot: "+mode)
		var folder: String="res://output/creation_workflow_"+mode+"_"+studio.Store.new_id(); DirAccess.make_dir_recursive_absolute(folder); ui.publish_to(folder)
		check(not ui.prepared.is_empty() and FileAccess.file_exists(folder+"/index.html"),"Actual publish action writes the browsable gallery: "+mode)
		var path: String=folder+"/creations/"+ui.prepared["id"]+".isocity-share.json"; ui.review_download(path)
		check(not ui.import_button.disabled and ui.incoming["missing"].is_empty(),"Actual review shows an available city ready for import: "+mode)
		var asset: Dictionary=studio.library.assets[id]; studio.library.assets.erase(id); ui.review_download(path); var unchanged: Dictionary=studio.current().data.duplicate(true); ui.import_reviewed()
		check(ui.import_button.disabled and studio.current().data==unchanged and ui.review.text.contains("Missing"),"Missing requirements block the actual import action without changing the city: "+mode)
		studio.library.assets[id]=asset; ui.review_download(path)
		var previous_id: String=studio.project_id; ui.import_reviewed(); var imported: Dictionary=studio.current().data.duplicate(true); imported.erase("creation_credits"); check(JSON.parse_string(JSON.stringify(imported))==JSON.parse_string(JSON.stringify(before)) and studio.project_id!=previous_id and studio.project_path.is_empty() and studio.dirty,"City import opens an independent editable local project: "+mode)
		check(studio.current().data["creation_credits"][0]["author"]=="Fixture creator","Imported city retains its original creation attribution: "+mode)
		var saved_path: String=folder+"/reopened.isocity.json"; studio.write_project(saved_path); var repaired: Dictionary=preload("res://scripts/builder/project_repair.gd").new(studio.library).read(saved_path)
		check(repaired["ok"] and repaired["content"]["documents"][mode]["creation_credits"]==studio.current().data["creation_credits"],"Creation attribution survives normal project saving and repair-aware reopening: "+mode)
		studio.assemblies.append({"name":"Assembly "+mode,"mode":mode,"objects":before["objects"].duplicate(true)}); ui.refresh(); ui.kind.select(1); ui.assembly.select(ui.assembly.item_count-1); ui.clear_preview(); await ui.generate()
		check(ui.source["kind"]=="assembly" and ui.preview!=null,"Saved assembly generates its own preview independently of the open city: "+mode)
		if "--capture" in OS.get_cmdline_user_args(): ui.preview.save_png("res://output/creation_assembly_"+mode+".png")
		ui.publish_to(folder); var assembly_id: String=ui.prepared["id"]; check(ui.Share.entries(folder).size()==2,"City and assembly appear as separate downloadable cards: "+mode)
		path=folder+"/creations/"+assembly_id+".isocity-share.json"; ui.review_download(path); var count: int=studio.assemblies.size(); var city_before: Dictionary=studio.current().data.duplicate(true); ui.import_reviewed()
		check(studio.assemblies.size()==count+1 and studio.current().data==city_before,"Assembly import preserves the current city and adds to My assemblies: "+mode)
		ui.review_download(path); ui.import_reviewed(); check(studio.assemblies.size()==count+1,"Repeated import does not duplicate an already imported assembly: "+mode)
		var native_index: int=studio.assemblies.size()-1; studio.show_assemblies()
		for index in studio.assembly_list.item_count:
			if studio.assembly_list.get_item_metadata(index)==native_index: studio.assembly_list.select(index)
		studio.choose_assembly(); check(studio.assembly_active["objects"].size()==2 and studio.assembly_ghosts.size()==2,"Imported assembly uses the existing native/mixed placement workflow: "+mode); studio.clear_placement()
	var size_before: Vector2i=root.size; root.size=Vector2i(960,640); ui.show(); studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true}); await settle(); ui.import_button.grab_focus(); await settle(); ui.panel.ensure_control_visible(ui.import_button); await settle()
	check(ui.import_button.size.y>=44 and ui.import_button.get_global_rect().intersects(ui.panel.get_global_rect()),"Sharing import action remains keyboard-reachable at 150% text and 960×640")
	if "--capture" in OS.get_cmdline_user_args(): RenderingServer.force_draw(false); RenderingServer.force_draw(false); root.get_texture().get_image().save_png("res://output/creation_accessible.png")
	root.size=size_before; studio.free(); await process_frame; await process_frame
	print("Creation workflow: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
