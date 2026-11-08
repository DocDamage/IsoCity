extends "res://tools/test_modular_building_workflow.gd"

var host: Control
var guest: Control

func synchronized() -> bool:
	var first: RefCounted = host.cooperative_tools
	var second: RefCounted = guest.cooperative_tools
	return first.participating and second.participating and not first.dirty and not second.dirty \
		and second.session.pending.is_empty() and first.snapshot() == second.snapshot()

func wait_for(condition: Callable) -> bool:
	for frame in 1000:
		if condition.call(): return true
		await process_frame
	return false

func run() -> void:
	host = load("res://scenes/builder.tscn").instantiate()
	guest = load("res://scenes/builder.tscn").instantiate()
	for editor in [host,guest]:
		editor.storage_enabled = false
		root.add_child(editor)
	while not host.enhancements_ready or not guest.enhancements_ready: await process_frame
	for editor in [host,guest]:
		editor.consumer_shell.dismiss_welcome()
		editor.switch_mode("3d")
		editor.economy_tools.pauses["3d"] = true
	studio = guest
	tools = guest.modular_building_tools
	var initial: Dictionary = Templates.make("3d","blank")
	initial["economy"] = {"enabled":true,"starting_cash":50000}
	initial["economy_account"] = Economy.fresh_account(initial,host.library)
	initial["protected_areas"] = [{"uid":"room_plot","name":"Room footprint","owner":"host","rect":[-2,-2,4,4]}]
	host.current().data = initial
	host.changed()
	var first: RefCounted = host.cooperative_tools
	var second: RefCounted = guest.cooperative_tools
	first.name_field.text = "Room host"
	first.password.text = "local-room-fixture"
	first.port.value = 0
	first.host_game()
	check(first.session.server != null,"The host starts with the protected room plot.")
	if first.session.server == null: quit(1); return
	second.name_field.text = "Room guest"
	second.password.text = first.password.text
	second.address.text = "127.0.0.1"
	second.port.value = first.session.server.get_local_port()
	second.join_game()
	var ready: bool = await wait_for(synchronized)
	check(ready,"Two active peers synchronize the Model world.")
	if not ready: second.leave(); first.leave(); quit(1); return
	var guarded: Dictionary = first.session.data.duplicate(true)
	guest._command("modular_rooms",null)
	await settle()
	outline(OUTLINE)
	opening("x/0/4",1)
	tools.review_button.pressed.emit()
	check(tools.reviewed.is_empty() and tools.message.text.contains("Protected area") and first.session.data == guarded,
		"Guest review rejects a room touching host-protected floor modules.")
	first.selected = "room_plot"
	first.remove_area()
	check(await wait_for(func(): return synchronized() and host.current().data["protected_areas"].is_empty()),"The host releases the room plot.")
	var before: Dictionary = first.session.data.duplicate(true)
	guest._command("modular_rooms",null)
	outline(OUTLINE)
	opening("x/0/4",1)
	tools.review_button.pressed.emit()
	check(not tools.reviewed.is_empty(),"The same guest outline is reviewable after authorization. " + tools.message.text)
	if tools.reviewed.is_empty(): second.leave(); first.leave(); quit(1); return
	var quote: Dictionary = tools.reviewed["quote"]
	tools.apply_button.pressed.emit()
	check(await wait_for(func(): return synchronized() and host.current().data.get("modular_rooms",[]).size() == 1),
		"One legal guest construction converges with matching parts and ownership.")
	check(first.session.data["3d"]["economy_account"] == JSON.parse_string(JSON.stringify(quote["account"])),
		"The host settles the same reviewed construction cost exactly once.")
	var built: Dictionary = first.session.data.duplicate(true)
	guest._command("undo",null)
	check(await wait_for(func(): return synchronized() and first.session.data == before),"Shared Undo restores the entire layout and treasury.")
	guest._command("redo",null)
	check(await wait_for(func(): return synchronized() and first.session.data == built),"Shared Redo restores the exact same modules and joint identities.")
	second.leave()
	first.leave()
	guest.free()
	host.free()
	await settle()
	print("MODULAR BUILDING COOPERATIVE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
