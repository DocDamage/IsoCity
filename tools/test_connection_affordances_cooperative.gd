extends "res://tools/test_connection_affordances.gd"

var host: Control
var guest: Control

func ready() -> bool:
	var a: RefCounted=host.cooperative_tools
	var b: RefCounted=guest.cooperative_tools
	return a.participating and b.participating and b.session.pending.is_empty() and a.session.data==b.session.data and a.snapshot()==b.snapshot()

func wait_for(condition: Callable) -> bool:
	for frame in 1200:
		if condition.call(): return true
		await process_frame
	return false

func protected_city(mode: String,kind: String) -> void:
	host.switch_mode(mode)
	guest.switch_mode(mode)
	var source: Dictionary
	var target: Dictionary
	if kind=="structure":
		source=Templates.make(mode,"blank")
		target=object(Wall if mode=="2d" else Scaffold,"guarded",Vector2.ZERO,mode)
		target["direction"]="SE" if mode=="2d" else "0"
		source["objects"]=[target]
	else:
		source=authored(mode) if kind=="water" else authored_power(mode)
		source["utility_edges"].pop_front()
		var target_id: String="tank" if kind=="water" else "relay"
		for item in source["objects"]:
			if item["uid"]==target_id: target=item; break
	var bounds: Rect2=Protection.object_rect(target,mode,host.library).grow(.5)
	source["protected_areas"]=[{"uid":"guard","name":"Guarded endpoint","owner":"host",
		"rect":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y]}]
	host.current().data=source
	host.changed()
	await settle()
	var a: RefCounted=host.cooperative_tools
	var b: RefCounted=guest.cooperative_tools
	a.name_field.text="Connection host"
	a.password.text="preview-pass"
	a.port.value=0
	a.host_game()
	check(a.session.server!=null,"Host starts an authored city "+mode+" "+kind)
	if a.session.server==null: return
	b.name_field.text="Connection guest"
	b.password.text="preview-pass"
	b.address.text="127.0.0.1"
	b.port.value=a.session.server.get_local_port()
	b.join_game()
	var converged: bool=await wait_for(ready)
	check(converged,"Guest receives the protected endpoint "+mode+" "+kind)
	if not converged: b.leave(); a.leave(); return
	var baseline: Dictionary=a.session.data.duplicate(true)
	if kind=="structure":
		guest._command("connectors",null)
		var sockets: RefCounted=guest.connector_tools
		sockets.enabled.button_pressed=true
		sockets.markers_visible.button_pressed=false
		select_module(guest.current().object(target["uid"]))
		var frame: Dictionary=Connector.frames(target,mode)[1]
		await show_at(sockets.project(frame["point"]))
		var draft: Dictionary=guest.placement(guest.canvas_pointer()).get("socket",{})
		check(draft.get("blocked",false) and draft["reason"].contains("Guarded endpoint") and guest.overlay.socket_markers.is_empty(),
			"The hidden structural overlay retains the protected reason "+mode)
		shortcut(KEY_PAGEDOWN,true)
		shortcut(KEY_F7)
		check(sockets.selected.is_empty() and guest.status.text.contains("Guarded endpoint"),"Real keyboard placement cannot target the guarded structure "+mode)
		sockets.enabled.button_pressed=false
		sockets.markers_visible.button_pressed=true
	else:
		guest._command(kind,null)
		var tools: RefCounted=guest.utility_tools if kind=="water" else guest.power_tools
		var first: Dictionary=reference("well","outlet") if kind=="water" else reference("generator","output")
		var second: Dictionary=reference(target["uid"],"west")
		choose(tools.first,first)
		choose(tools.second,second)
		tools.markers_visible.button_pressed=false
		guest.update_overlay(false)
		check(tools.join_button.disabled and tools.status.text.contains("Guarded endpoint") and guest.overlay.socket_markers.is_empty(),
			"Textual utility review still rejects the guarded port with markers hidden "+mode+" "+kind)
		shortcut(KEY_PAGEDOWN,true)
		check(tools.choice(tools.second)!=second or tools.join_button.disabled,"Keyboard traversal cannot make the protected utility port eligible "+mode+" "+kind)
		choose(tools.second,second)
		tools.join_button.pressed.emit()
		tools.markers_visible.button_pressed=true
	await settle()
	check(a.session.data==baseline and b.session.pending.is_empty() and b.snapshot()==baseline,
		"The hidden-preview attempt creates no accepted or pending link "+mode+" "+kind)
	b.leave()
	a.leave()
	await settle()

func run() -> void:
	host=load("res://scenes/builder.tscn").instantiate()
	guest=load("res://scenes/builder.tscn").instantiate()
	for editor in [host,guest]:
		editor.storage_enabled=false
		root.add_child(editor)
	await settle()
	for editor in [host,guest]:
		if editor.consumer_shell: editor.consumer_shell.dismiss_welcome()
	studio=guest
	for mode in ["2d","3d"]:
		for kind in ["structure","water","power"]: await protected_city(mode,kind)
	guest.free()
	host.free()
	await settle()
	print("CONNECTION AFFORDANCES COOPERATIVE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
