extends "res://tools/test_modular_sockets.gd"

var host: Control
var guest: Control

func wait_for(test: Callable) -> bool:
	for frame in 900:
		if test.call(): return true
		await process_frame
	return false

func synced() -> bool:
	var a: RefCounted=host.cooperative_tools
	var b: RefCounted=guest.cooperative_tools
	return a.participating and b.participating and not a.dirty and not b.dirty and b.session.pending.is_empty() and a.session.data==b.session.data and a.snapshot()==b.snapshot()

func run() -> void:
	host=load("res://scenes/builder.tscn").instantiate()
	guest=load("res://scenes/builder.tscn").instantiate()
	for editor in [host,guest]:
		editor.storage_enabled=false
		root.add_child(editor)
	await settle()
	for mode in ["2d","3d"]:
		for editor in [host,guest]:
			if editor.consumer_shell: editor.consumer_shell.dismiss_welcome()
			editor.switch_mode(mode)
			editor.economy_tools.pauses[mode]=true
		studio=guest
		var doc:=Doc.new()
		doc.data=Templates.make(mode,"blank")
		host.documents[mode]=doc
		var asset: String=PIPE if mode=="2d" else WALL
		var heading: String="SE" if mode=="2d" else "32"
		var target: Dictionary=record(asset,"existing",[0,0,0],heading)
		var frame: Dictionary=Plan.frames(target,mode)[1]
		doc.data["objects"]=[target]
		doc.data["economy"]={"enabled":true,"starting_cash":1000000,"period_seconds":60}
		doc.data["economy_account"]=Economy.fresh_account(doc.data,host.library)
		var rect: Rect2=Protection.object_rect(target,mode,host.library)
		var margin: float=20 if mode=="2d" else .5
		rect=rect.grow(margin)
		doc.data["protected_areas"]=[{"uid":"locked","name":"Protected joint","owner":"host","rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]}]
		if mode=="2d":
			var part: Dictionary=record(asset,"proposed",[0,0,0],heading)
			var mate: Dictionary=Plan.solve(part,Plan.frames(part,mode)[0],frame,mode,doc.data,{})
			check(mate["ok"],"Shared pipe proposal has a calibrated existing socket.")
			if not mate["ok"]: continue
			for field in ["position","direction","angle"]:
				part[field]=mate["pose"][field]
			doc.data["blueprints"]=[{"uid":"shared_socket","kind":"assembly","version":1,"name":"Pipe replacement","objects":[part],"roads":[],"connections":[{"uid":"pipe_edge","kind":"water","from":{"object_uid":"proposed","socket":mate["source"]["socket"]},"to":{"object_uid":"existing","socket":frame["socket"],"external":true}}]}]
		host.changed()
		await settle()
		var a: RefCounted=host.cooperative_tools
		var b: RefCounted=guest.cooperative_tools
		a.name_field.text="Socket host"
		a.password.text="socket-pass"
		a.port.value=0
		a.host_game()
		check(a.session.server!=null,"Host starts with a city socket: "+mode)
		if a.session.server==null: continue
		b.name_field.text="Socket guest"
		b.password.text="socket-pass"
		b.address.text="127.0.0.1"
		b.port.value=a.session.server.get_local_port()
		b.join_game()
		check(await wait_for(synced),"Peers converge on the same socket and protection: "+mode)
		var protected_state: Dictionary=a.session.data.duplicate(true)
		var ui: RefCounted=guest.connector_tools
		var blueprint: RefCounted=guest.blueprint_tools
		var at: Vector2=ui.project(frame["point"])
		if mode=="2d":
			guest._command("blueprints",null)
			blueprint.selected="shared_socket"
			blueprint.review(["shared_socket"])
			check(blueprint.reviewed.is_empty() and blueprint.review_label.text.contains("Protected area"),"Shared external review blocks the protected city endpoint.")
			blueprint.construct(false)
		else:
			guest._command("connectors",null)
			ui.enabled.button_pressed=true
			set_module(DOOR_WALL,heading,1)
			at=ui.project(frame["point"])
			var pose: Dictionary=guest.placement(at)
			check(pose.get("socket",{}).get("blocked",false) and pose["socket"]["reason"].contains("Protected"),"Guest placement blocks the protected target before paint.")
			place(at)
		await settle()
		check(a.session.data==protected_state and b.session.pending.is_empty(),"Protected attempt leaves no accepted or pending edit: "+mode)
		a.selected="locked"
		a.remove_area()
		check(await wait_for(func():return synced() and host.current().data.get("protected_areas",[]).is_empty()),"Host releases the socket through the normal area controls: "+mode)
		if mode=="2d":
			blueprint.review(["shared_socket"])
			check(not blueprint.reviewed.is_empty(),"The guest reviews the now available outside socket. "+blueprint.review_label.text)
			host.current().checkpoint()
			host.current().data["blueprints"][0]["name"]="Revised pipe replacement"
			host.changed()
			check(await wait_for(func():return synced() and guest.current().data["blueprints"][0]["name"]=="Revised pipe replacement"),"Host revision reaches the guest after review.")
			var revised: Dictionary=a.session.data.duplicate(true)
			blueprint.construct(false)
			await settle()
			check(a.session.data==revised and b.session.pending.is_empty() and not blueprint.reviewed.is_empty(),"Stale commit reviews the revised link without building.")
		var before: Dictionary=a.session.data.duplicate(true)
		var quote: Dictionary={}
		if mode=="2d":
			var candidate: Dictionary=Blueprint.construct(guest.current().data,["shared_socket"],guest.library)
			check(candidate["ok"],"The refreshed proposal has an exact candidate and quote.")
			if candidate["ok"]: quote=candidate["quote"]
			blueprint.construct(false)
		else:
			place(at)
		check(await wait_for(func():return synced() and host.current().data.get("connections",[]).size()==1),"Accepted peer edit converges with the same link and object IDs: "+mode)
		var accepted: Dictionary=a.session.data.duplicate(true)
		if mode=="2d" and not quote.is_empty():
			var account: Dictionary=host.current().data["economy_account"]
			check(JSON.parse_string(JSON.stringify(account))==JSON.parse_string(JSON.stringify(quote["account"])),"Shared assembly charges the exact refreshed quote once. Host %s, quote %s"%[account,quote["account"]])
		guest._command("undo",null)
		check(await wait_for(func():return synced() and a.session.data==before),"Shared Undo restores exact link occupancy and account: "+mode)
		guest._command("redo",null)
		check(await wait_for(func():return synced() and a.session.data==accepted),"Shared Redo restores the exact accepted linked city: "+mode)
		b.leave()
		a.leave()
		await settle()
	guest.free()
	host.free()
	await settle()
	print("MODULAR SOCKETS COOPERATIVE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
