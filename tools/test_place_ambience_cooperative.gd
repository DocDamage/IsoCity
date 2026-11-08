extends SceneTree

const Templates = preload("res://scripts/builder/templates.gd")
var host: Control
var guest: Control
var checks: int
var failures: int

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: "+message)
	return ok

func wait_for(condition: Callable) -> bool:
	for frame in 1100:
		if condition.call(): return true
		await process_frame
	return false

func synchronized() -> bool:
	var a: RefCounted = host.cooperative_tools
	var b: RefCounted = guest.cooperative_tools
	return a.participating and b.participating and not a.dirty and not b.dirty and b.session.pending.is_empty() and a.snapshot() == b.snapshot()

func override_at(editor: Control) -> void:
	editor.selected_uid = "sound_anchor"
	editor.selected_uids.assign(["sound_anchor"])
	editor._command("ambience",null)
	var audio: RefCounted = editor.ambience_tools
	for index in audio.source_kind.item_count:
		if audio.source_kind.get_item_metadata(index) == "harbor": audio.source_kind.select(index)
	audio.source_range.value = 18
	audio.source_volume.value = 70
	audio.apply_source.pressed.emit()

func run() -> void:
	host = load("res://scenes/builder.tscn").instantiate()
	guest = load("res://scenes/builder.tscn").instantiate()
	for editor in [host,guest]:
		editor.storage_enabled = false
		root.add_child(editor)
	while not host.enhancements_ready or not guest.enhancements_ready: await process_frame
	for editor in [host,guest]:
		if editor.consumer_shell: editor.consumer_shell.dismiss_welcome()
		editor.switch_mode("3d")
	host.current().data = Templates.make("3d","blank")
	var item: Dictionary = host.current().add("2d:crate",[0,0,0],"SE",1)
	item["uid"] = "sound_anchor"
	host.current().data["protected_areas"] = [{"uid":"wharf","name":"Protected wharf","owner":"host","rect":[-8,-8,16,16]}]
	host.changed()
	var a: RefCounted = host.cooperative_tools
	var b: RefCounted = guest.cooperative_tools
	a.name_field.text = "Audio host"
	a.password.text = "ambience-fixture"
	a.port.value = 0
	a.host_game()
	if not check(a.session.server != null,"A real audio host session opens."): quit(1); return
	b.name_field.text = "Audio guest"
	b.password.text = a.password.text
	b.address.text = "127.0.0.1"
	b.port.value = a.session.server.get_local_port()
	b.join_game()
	if not check(await wait_for(synchronized),"Peers share the same protected shoreline."): quit(1); return
	var protected: Dictionary = a.session.data.duplicate(true)
	override_at(guest)
	check(await wait_for(func()->bool: return synchronized() and not guest.current().object("sound_anchor").has("audio")) and a.session.data == protected,
		"Protected object audio edit is rejected and the exact shared source is restored.")
	a.selected = "wharf"
	a.remove_area()
	check(await wait_for(func()->bool: return synchronized() and host.current().data["protected_areas"].is_empty()),"The host opens the anchor for guest edits.")
	var baseline: Dictionary = a.session.data.duplicate(true)
	override_at(guest)
	if check(await wait_for(func()->bool: return synchronized() and host.current().object("sound_anchor").get("audio",{}).get("kind") == "harbor"),
		"Allowed place audio settings synchronize to the host."):
		var authored: Dictionary = a.session.data.duplicate(true)
		guest.control_settings.execute("ambience_mute")
		check(guest.ambience_tools.muted and not host.ambience_tools.muted and synchronized() and a.session.data == authored,
			"Session mute and audio playback remain peer-local.")
		guest._command("undo",null)
		check(await wait_for(func()->bool: return synchronized() and a.session.data == baseline),"Shared Undo restores the exact original audio settings.")
		guest._command("redo",null)
		check(await wait_for(func()->bool: return synchronized() and a.session.data == authored),"Shared Redo restores the exact place override.")
	b.leave()
	a.leave()
	guest.free()
	host.free()
	OS.delay_msec(120)
	await process_frame
	print("PLACE AMBIENCE COOPERATIVE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
