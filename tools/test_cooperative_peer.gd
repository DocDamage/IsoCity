extends SceneTree
var studio: Control
var directory: String
var role: String
var port: int
var sequence: int=0
var last_write: int=0
var deadline: int=0
func argument(key: String,fallback: String="") -> String:
	var args:=OS.get_cmdline_user_args(); var index: int=args.find(key); return args[index+1] if index>=0 and index+1<args.size() else fallback
func _initialize() -> void: call_deferred("run")
func save_state() -> void:
	var ui: RefCounted=studio.cooperative_tools; var members: Dictionary={}
	for id in ui.session.roster: members[ui.session.roster[id]["name"]]=id
	var value: Dictionary={"sequence":sequence,"connected":ui.session.connected,"role":ui.session.role,"id":ui.session.local_id,"revision":ui.session.revision,"pending":not ui.session.pending.is_empty(),"dirty":ui.dirty,"participating":ui.participating,"data":ui.snapshot(),"members":members,"failed_edit":ui.failed_edit,"draft":ui.draft,"cursor_count":ui.cursor_root.get_child_count() if is_instance_valid(ui.cursor_root) else 0,"notice":ui.session.notice}
	var path: String=directory+"/"+role+".json"; var file:=FileAccess.open(path+".partial",FileAccess.WRITE); file.store_string(JSON.stringify(value)); file.close(); DirAccess.rename_absolute(path+".partial",path)
func command(value: Dictionary) -> bool:
	if int(value.get("sequence",0))<=sequence: return false
	var ui: RefCounted=studio.cooperative_tools
	match value.get("action",""):
		"place":
			studio.switch_mode(value.get("mode","2d")); var doc: RefCounted=studio.current(); doc.checkpoint(); var item: Dictionary=doc.add("2d:Sedan_Blue",value.get("position",[0,0,0]),"SE",1); item["uid"]=value["uid"]; doc.finish_checkpoint(); studio.changed()
		"protect":
			studio.switch_mode("2d"); var owner: String="host"
			for id in ui.session.roster:
				if ui.session.roster[id]["name"]==value.get("owner"): owner=id
			ui.select_owner(owner); ui.area_name.text="Alice district"; ui.add_bounds(Rect2(-8,-8,16,16))
		"cursor":
			studio.switch_mode(value.get("mode","2d")); studio.control_settings.cursor_active=true; studio.control_settings.cursor_position=studio.canvas.size*.5
		"undo": studio._command("undo",null)
		"redo": studio._command("redo",null)
		"leave": ui.leave()
		"join": ui.join_game()
		"quit": sequence=int(value["sequence"]); save_state(); print("Cooperative peer "+role+" stopping."); quit(); return true
	sequence=int(value["sequence"]); return false
func run() -> void:
	directory=argument("--directory"); role=argument("--role"); port=int(argument("--port")); deadline=Time.get_ticks_msec()+90000
	studio=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio)
	for frame in 6: await physics_frame
	for mode in ["2d","3d"]: studio.documents[mode].data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
	studio.changed(); var ui: RefCounted=studio.cooperative_tools; ui.name_field.text=role.capitalize(); ui.password.text="process-fixture-password"; ui.port.value=port
	if role=="host": ui.host_game()
	else: ui.address.text="127.0.0.1"; ui.join_game()
	while Time.get_ticks_msec()<deadline:
		var path: String=directory+"/"+role+"-command-"+str(sequence+1)+".json"
		if FileAccess.file_exists(path):
			var parser:=JSON.new()
			if parser.parse(FileAccess.get_file_as_string(path))==OK and parser.data is Dictionary:
				if command(parser.data): return
		if Time.get_ticks_msec()-last_write>=50: last_write=Time.get_ticks_msec(); save_state()
		await process_frame
	print("FAIL: Cooperative peer command timeout: "+role); quit(1)
