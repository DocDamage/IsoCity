extends "res://tools/test_construction_costs.gd"

var guest: Control

func synchronized() -> bool:
	var host_tools: RefCounted = studio.cooperative_tools
	var guest_tools: RefCounted = guest.cooperative_tools
	return host_tools.participating and guest_tools.participating and not host_tools.dirty and not guest_tools.dirty and guest_tools.session.pending.is_empty() and host_tools.session.data == guest_tools.session.data

func until(condition: Callable) -> bool:
	for frame in 1100:
		if condition.call(): return true
		await process_frame
	return false

func run() -> void:
	studio = load("res://scenes/builder.tscn").instantiate()
	guest = load("res://scenes/builder.tscn").instantiate()
	for editor in [studio, guest]:
		editor.storage_enabled = false
		root.add_child(editor)
	while not studio.enhancements_ready or not guest.enhancements_ready: await process_frame
	for editor in [studio, guest]:
		editor.consumer_shell.dismiss_welcome()
		editor.switch_mode("2d")
	var doc: RefCounted = fixture("2d")
	doc.checkpoint()
	var crate: Dictionary = doc.add(Tools.MODEL_CRATE, [0, 0, 0], "0")
	var uid: String = crate["uid"]
	studio.changed()
	doc.finish_checkpoint()
	doc.data["protected_areas"] = [{"uid": "protected_crate", "name": "Crate", "owner": "host", "rect": [-8, -8, 16, 16]}]
	studio.changed()
	var a: RefCounted = studio.cooperative_tools
	var b: RefCounted = guest.cooperative_tools
	a.name_field.text = "Cost host"
	a.password.text = "costs-fixture"
	a.port.value = 0
	a.host_game()
	if not check(a.session.server != null, "Host starts a real cooperative session"): quit(1); return
	b.name_field.text = "Cost guest"
	b.password.text = a.password.text
	b.address.text = "127.0.0.1"
	b.port.value = a.session.server.get_local_port()
	b.join_game()
	if not check(await until(synchronized), "Host and guest have the same authoritative treasury and crate"): quit(1); return
	guest.set_tool("select")
	guest.selected_uid = uid
	guest.selected_uids.assign([uid])
	var tools: RefCounted = guest.construction_cost_tools
	var protected: Dictionary = a.session.data.duplicate(true)
	var source: Dictionary = guest.current().object(uid)
	var target: Dictionary = tools.alternative(source)
	var blocked: Dictionary = tools.replacement_draft(source, target)
	check(blocked.has("reason") and "protect" in blocked["reason"].to_lower(), "Replacement review identifies the host-protected area")
	check(synchronized() and protected == a.session.data, "A protected quote leaves the shared city untouched")
	a.selected = "protected_crate"
	a.remove_area()
	if not check(await until(func() -> bool: return synchronized() and studio.current().data["protected_areas"].is_empty() and guest.current().data["protected_areas"].is_empty()), "Host opens the area"): quit(1); return
	var before: Dictionary = a.session.data.duplicate(true)
	guest.selected_uid = uid
	guest.selected_uids.assign([uid])
	source = guest.current().object(uid)
	target = tools.alternative(source)
	var draft: Dictionary = tools.replacement_draft(source, target)
	if check(draft.has("quote") and draft["quote"]["ok"], "Guest sees the exact current replacement quote: " + str(draft.get("reason", draft.get("quote", {}).get("reason", "")))):
		tools.review_comparison()
		check(synchronized() and a.session.data == before, "Guest preview and render comparison remain local")
		tools.comparison.replace.pressed.emit()
		guest.current().finish_checkpoint()
		check(await until(func() -> bool: return synchronized() and studio.current().object(uid)["asset"] == Tools.SPRITE_CRATE), "Guest's reviewed replacement reaches the host")
		var accepted: Dictionary = a.session.data.duplicate(true)
		check(Economy.normalized_account(a.session.data["2d"]["economy_account"]) == draft["quote"]["account"], "Host uses the same transaction and purchase basis exactly once")
		guest._command("undo", null)
		check(await until(func() -> bool: return synchronized() and a.session.data == before), "Shared Undo restores original artwork and treasury")
		guest._command("redo", null)
		check(await until(func() -> bool: return synchronized() and a.session.data == accepted), "Shared Redo restores the reviewed replacement and account")
	b.leave()
	a.leave()
	guest.free()
	studio.free()
	await frames()
	print("CONSTRUCTION COSTS COOPERATIVE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
