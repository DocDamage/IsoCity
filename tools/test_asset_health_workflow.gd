extends SceneTree
const OUT="res://output/verification/asset_expansion/U17"
const SHIP="3d:Supplemental_Spaceships_II/belly_bay_bomber"
const CHAIR="3d:HanX_School/Student_Chair"
const Preview=preload("res://scripts/builder/model_preview.gd")
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func settle() -> void:
	for frame in 8:await process_frame
func key(code: Key) -> void:
	for pressed in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.pressed=pressed;Input.parse_input_event(event);await process_frame
func run() -> void:
	var store=preload("res://scripts/builder/project_store.gd");store.storage_root=OUT+"/workflow_history";store.legacy_autosave=OUT+"/workflow_legacy.json"
	var studio: Control=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio)
	while not studio.enhancements_ready:await process_frame
	var ui: RefCounted=studio.consumer_shell;var health: RefCounted=studio.asset_browser.health_tools
	check(ui!=null,"Both browsing interfaces expose library health")
	if not ui:studio.free();quit(1);return
	ui.dismiss_welcome();var original: String=studio.library.assets[SHIP]["data"]["preview_path"];var target: String=OUT+"/workflow_preview.png"
	health.repair.allowed_roots.append(OUT+"/");health.repair.backup_root=OUT+"/workflow_backups"
	for mode in ["2d","3d"]:
		studio.switch_mode(mode);studio.current().data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
		for index in 2:studio.current().add([SHIP,CHAIR][index],[index*200,0,0] if mode=="2d" else [index*6,0,0],"0")
		studio.changed();await settle();var doc: RefCounted=studio.current();var authored: Dictionary=doc.data.duplicate(true);var history: int=doc.undo_history.size();var dirty: bool=studio.dirty;var placement: Array=[studio.asset_id,studio.direction,studio.scale_input.value]
		var flat:=Image.create_empty(192,192,false,Image.FORMAT_RGBA8);flat.fill(Color(.2,.4,.6));flat.save_png(target)
		studio.library.assets[SHIP]["data"]["preview_path"]=target;studio.library.icons.erase(SHIP)
		for active in [false,true]:
			ui.set_active(active,false);health.open();health.scan();health.audit.ids=[SHIP,CHAIR]
			while health.audit.active:await process_frame
			health.refresh_list(true)
			check(studio.modal_visible() and health.audit.report()["assets_scanned"]==2,"Health window is modal and reports actual audited coverage: "+mode+" "+str(active))
			check(health.entries.size()==1 and health.entries[0]["code"]=="preview_placeholder" and health.shown_ids==[SHIP],"Defect list identifies the exact thumbnail target and affected identity")
			health.issues_list.grab_focus();await key(KEY_R);await settle()
			check(doc.data==authored and doc.undo_history.size()==history and studio.dirty==dirty and [studio.asset_id,studio.direction,studio.scale_input.value]==placement,"Inspection/filter input does not rotate, place or change city/history/dirty state")
			health.save_report(OUT+"/health_report_"+mode+"_"+str(active)+".json")
			check(health.message.text.contains("saved"),"A health snapshot saves independently of city content")
			var protected: String=OUT+"/unrelated_source.json";FileAccess.open(protected,FileAccess.WRITE).store_string('{"objects":[]}');var protected_sha: String=FileAccess.get_sha256(protected);health.save_report(protected)
			check(FileAccess.get_sha256(protected)==protected_sha and health.message.text.contains("preserved"),"Saving a report cannot overwrite unrelated source/project JSON")
			health.inspect_selected();check(studio.asset_browser.dialog.visible and not health.dialog.visible and doc.data==authored,"Inspect opens the actual prepared source without switching worlds or altering authored content");studio.asset_browser.dialog.hide()
		if "--rendered" in OS.get_cmdline_user_args():
			health.open();health.refresh_list(true);var before: String=FileAccess.get_sha256(target);var space_index: int=studio.library.themes.KEYS.find("space")+1;var old_icon: int=studio.asset_browser.theme_choice.get_item_icon(space_index).get_instance_id()
			health.prepare_repair();health.dialog.hide();await settle()
			check(not health.busy and FileAccess.get_sha256(target)==before and root.find_children("PrivateModelThumbnail","",true,false).is_empty(),"Closing health during a render discards its private scene without publishing")
			health.open();health.refresh_list(true)
			await health.prepare_repair()
			check(not health.apply_button.disabled and health.after.texture!=null and FileAccess.get_sha256(target)==before,"Rendering proposes artwork for review before any public thumbnail write: "+mode)
			if not health.apply_button.disabled:
				health.apply_button.pressed.emit();await settle()
				check(Preview.meaningful_image(Preview.read_image(target)) and health.audit.report()["issues"].is_empty(),"Applying an actual rendered repair removes its defect without changing metadata: "+mode)
				check(studio.asset_browser.theme_choice.get_item_icon(space_index).get_instance_id()!=old_icon and Preview.meaningful(studio.library.icon(SHIP)),"Cards and collection preview dependencies refresh immediately")
			health.dialog.hide()
		else:DirAccess.copy_absolute(original,target)
		check(doc.data==authored and doc.undo_history.size()==history and studio.dirty==dirty,"Health/repair never edits city data, history or dirty state: "+mode)
		var path: String=OUT+"/health_"+mode+".isocity.json"
		check(studio.write_project(path) and studio.load_project(path) and studio.current().data["objects"]==JSON.parse_string(JSON.stringify(authored["objects"])) and studio.repair_report.get("issues",[]).is_empty(),"Health state does not enter persisted authored data or require repairs: "+mode)
		studio.library.assets[SHIP]["data"]["preview_path"]=target
		var result: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],studio.current().data,studio.library,OUT+"/health_"+mode+".zip")
		check(result["ok"],"Allowed export retains repaired/supplied and derived native thumbnails: "+mode+" "+result.get("message",""))
		studio.library.assets[SHIP]["data"]["source_export_allowed"]=false
		var blocked: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],studio.current().data,studio.library,OUT+"/blocked_"+mode+".zip")
		check(not blocked["ok"] and blocked["message"].contains("restrict"),"Thumbnail dependency collection preserves existing source-export restrictions: "+mode);studio.library.assets[SHIP]["data"].erase("source_export_allowed")
	studio.library.assets[SHIP]["data"]["preview_path"]=original;studio.free();await process_frame;await process_frame
	print("ASSET HEALTH WORKFLOW: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
