@tool
extends EditorPlugin

# A normal editor run, not recovery mode. Wait for completed imports and two
# seconds of a stable filesystem before quitting. Fixed frame-count exits can
# abort the initial scan; the installed engine has also failed during immediate
# --import shutdown. Native errors still fail the calling verifier.
var started: int=0
var stable_since: int=0
var changed: bool=false
var filesystem: EditorFileSystem
var finishing: bool=false
func _enter_tree() -> void:
	started=Time.get_ticks_msec();call_deferred("start_watch")
func source_changed() -> void:changed=true
func disconnect_watch() -> void:
	if is_instance_valid(filesystem) and filesystem.filesystem_changed.is_connected(source_changed):filesystem.filesystem_changed.disconnect(source_changed)
func _exit_tree() -> void:disconnect_watch()
func imported(directory: EditorFileSystemDirectory) -> bool:
	if not directory:return false
	for index in directory.get_file_count():
		if directory.get_file(index).get_extension().to_lower() in ["glb","gltf","png","jpg","jpeg","webp","svg","wav","ogg","ttf","otf"] and not directory.get_file_import_is_valid(index):return false
	for index in directory.get_subdir_count():
		if not imported(directory.get_subdir(index)):return false
	return true
func start_watch() -> void:
	if not Engine.is_editor_hint():printerr("FAIL: import wait requires an ordinary editor run");get_tree().quit(1);return
	filesystem=EditorInterface.get_resource_filesystem()
	if not filesystem:printerr("FAIL: editor filesystem unavailable");get_tree().quit(1);return
	filesystem.filesystem_changed.connect(source_changed);set_process(true)
func ready_to_finish() -> bool:
	var directory: EditorFileSystemDirectory=filesystem.get_filesystem()
	return not filesystem.is_scanning() and directory!=null and directory.get_file_count()>0 and imported(directory)
func _process(_delta: float) -> void:
	if not filesystem or finishing:return
	if Time.get_ticks_msec()-started>=120000:
		set_process(false);disconnect_watch();printerr("FAIL: editor imports did not settle within 120 seconds");get_tree().quit(1);return
	if not ready_to_finish() or changed:stable_since=0;changed=false;return
	if stable_since==0:stable_since=Time.get_ticks_msec()
	if Time.get_ticks_msec()-stable_since>=2000:finishing=true;set_process(false);call_deferred("finish_watch")
func finish_watch() -> void:
	# Finish outside the process callback. No suspended coroutine or anonymous
	# filesystem callable survives into editor/GDScript shutdown (#119857).
	if changed or not ready_to_finish():finishing=false;stable_since=0;changed=false;set_process(true);return
	disconnect_watch();print("Editor imports complete; filesystem stable for two seconds.");get_tree().quit()
