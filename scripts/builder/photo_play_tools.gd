extends "res://scripts/builder/photo_tools.gd"
const Location=preload("res://scripts/builder/prop_plan.gd")
class Host extends Control:
	var mode: String
	var worlds: Dictionary={}
	var status: Label
	var overlay: Control
	func label(parent: Node,value: String,size: int=14) -> Label:
		var result:=Label.new(); result.text=value; result.add_theme_font_size_override("font_size",size); parent.add_child(result); return result
var scene: Node
var host_layer: CanvasLayer
var locations: Dictionary={}
var session_locations: Dictionary={}
var storage_path: String=""
var storage_enabled: bool=true
var max_library_bytes: int=32*1024*1024
var store_error: String=""
func _init(play_scene: Node) -> void:
	scene=play_scene; storage_enabled=scene.photo_storage_enabled
	host_layer=CanvasLayer.new(); host_layer.name="PhotoControls"; host_layer.layer=20; scene.add_child(host_layer)
	var host:=Host.new(); host.name="PhotoControlsHost"; host.mode=scene.dimension; host.worlds[scene.dimension]=scene; host.mouse_filter=Control.MOUSE_FILTER_IGNORE; host_layer.add_child(host)
	host.status=Label.new(); host.status.position=Vector2(20,108); host.add_child(host.status); host.status.hide()
	super(host)
	storage_path="user://photos/"+JSON.stringify(scene.studio_data).sha256_text().left(20)+"/camera-library.json"
	reload_store()
	runtime().input_allowed=can_input
func runtime() -> Node: return scene.exploration.photo
func target() -> Dictionary:
	var scope: String=Location.scope(scene.exploration); var context: Dictionary=runtime().context()
	if not session_locations.has(scope):
		var photo: Dictionary=locations.get(scope,context["data"].get("photo",{})).duplicate(true)
		session_locations[scope]={"mode":scene.dimension,"title":context["data"].get("title","Current location"),"photo":photo}
	return {"data":session_locations[scope]}
func reload_store() -> void:
	locations={}; session_locations={}; stamp=0
	if not storage_enabled or not FileAccess.file_exists(storage_path): return
	var source:=FileAccess.open(storage_path,FileAccess.READ)
	if not source or source.get_length()>max_library_bytes: return
	var value: Variant=JSON.parse_string(source.get_as_text()); source.close()
	if not value is Dictionary or value.get("format")!=1 or not value.get("locations") is Dictionary: return
	for key in value["locations"]:
		if not key is String or key.length()>512 or not Plan.valid(value["locations"][key],scene.dimension): continue
		locations[key]=value["locations"][key]
func write_store(next: Dictionary) -> bool:
	store_error=""
	if not storage_enabled: return true
	var contents: String=JSON.stringify({"format":1,"locations":next},"\t")
	if contents.to_utf8_buffer().size()>max_library_bytes:
		store_error="Local camera library full. Remove older takes or bookmarks, then retry."; return false
	var directory: String=ProjectSettings.globalize_path(storage_path).get_base_dir()
	if FileAccess.file_exists(directory): return false
	if DirAccess.make_dir_recursive_absolute(directory)!=OK: return false
	var partial: String=storage_path+".partial"; var output:=FileAccess.open(partial,FileAccess.WRITE)
	if not output: return false
	output.store_string(contents); output.flush(); var result: Error=output.get_error(); output.close()
	if result!=OK: DirAccess.remove_absolute(ProjectSettings.globalize_path(partial)); return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(partial),ProjectSettings.globalize_path(storage_path))==OK
func commit(photo: Dictionary) -> bool:
	if not Plan.valid(photo,scene.dimension): return false
	var scope: String=Location.scope(scene.exploration); var next: Dictionary=locations.duplicate(true); next[scope]=photo.duplicate(true)
	if not write_store(next): runtime().notice=store_error if not store_error.is_empty() else "Could not save the local camera library. Free space or restore access to the game's user-data folder, then retry."; return false
	locations=next; target()["data"]["photo"]=photo; settings_stamp=hash(focus_settings(Plan.settings(target()["data"]))); stamp=0; runtime().notice=""; refresh()
	return true
func start() -> void:
	if not runtime().start(): return
	runtime().configure(focus_settings(Plan.settings(target()["data"]))); settings_stamp=hash(focus_settings(Plan.settings(target()["data"]))); stamp=0; refresh()
func text_focused() -> bool:
	var focus: Control=dialog.gui_get_focus_owner() if dialog.visible else null
	return focus is LineEdit or focus is TextEdit
func can_input() -> bool:
	return not file.visible and not scene.exploration.runtime_modal() and not text_focused()
func window_input(event: InputEvent) -> void:
	if handle_input(event): dialog.set_input_as_handled()
func handle_input(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo and not event.alt_pressed and not event.meta_pressed and not text_focused() and not file.visible and runtime().active:
		var action: String=""
		match event.keycode:
			KEY_EQUAL: action="zoom_in"
			KEY_MINUS: action="zoom_out"
			KEY_BRACKETLEFT: action="tilt_up" if event.ctrl_pressed else "orbit_left"
			KEY_BRACKETRIGHT: action="tilt_down" if event.ctrl_pressed else "orbit_right"
		if not action.is_empty() and runtime().action(action): return true
	if event is InputEventKey and event.pressed and not event.echo and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed and not text_focused() and not file.visible:
		match event.keycode:
			KEY_P: toggle(); return true
			KEY_F4: choose_screenshot(); return true
			KEY_F5: record_toggle(); return true
			KEY_ESCAPE:
				if runtime().active: stop(); return true
			KEY_TAB:
				if runtime().active: stop()
	if runtime().active and (event is InputEventMouseButton or event is InputEventMouseMotion):
		if event is InputEventMouseButton and event.pressed: release_focus()
		return runtime().input(event)
	return false
func choose_screenshot() -> void:
	if not runtime().active: start()
	if storage_enabled:
		var directory: String=ProjectSettings.globalize_path(storage_path).get_base_dir()
		DirAccess.make_dir_recursive_absolute(directory); file.current_dir=directory
	file.current_file="city-photo.png"; file.popup_centered_ratio(.7)
func tick(delta: float) -> void:
	super.tick(delta)
