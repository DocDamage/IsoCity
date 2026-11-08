extends "res://tools/test_functional_assemblies.gd"

var host_editor: Control
var guest_editor: Control

func wait_for(test: Callable) -> bool:
	for frame in 900:
		if test.call(): return true
		await process_frame
	return false

func synced() -> bool:
	var a: RefCounted=host_editor.cooperative_tools
	var b: RefCounted=guest_editor.cooperative_tools
	return a.participating and b.participating and not a.dirty and not b.dirty and b.session.pending.is_empty() and a.session.data==b.session.data and a.snapshot()==b.snapshot()

func run() -> void:
	host_editor=load("res://scenes/builder.tscn").instantiate()
	guest_editor=load("res://scenes/builder.tscn").instantiate()
	for editor in [host_editor,guest_editor]:
		editor.storage_enabled=false
		root.add_child(editor)
	await settle()
	for editor in [host_editor,guest_editor]:
		if editor.consumer_shell: editor.consumer_shell.dismiss_welcome()
	for mode in ["2d","3d"]:
		for editor in [host_editor,guest_editor]:
			editor.switch_mode(mode)
			editor.economy_tools.pauses[mode]=true
		var doc:=Doc.new()
		doc.data=Templates.make(mode,"blank")
		host_editor.documents[mode]=doc
		doc.data["economy"]={"enabled":true,"starting_cash":1000000,"period_seconds":60}
		doc.data["economy_account"]=Economy.fresh_account(doc.data,host_editor.library)
		doc.data["blueprints"]=[{"kind":"assembly","version":1,"uid":"shared_copy","name":"School proposal","objects":[furnished(mode,"3d:HanX_School/School_Building",Traffic.world(Vector2(32,32),mode))],"roads":[],"connections":[]}]
		doc.data["protected_areas"]=[{"uid":"protected_site","name":"School site","owner":"host","rect":[24,24,16,16]}]
		host_editor.changed()
		await settle()
		var a: RefCounted=host_editor.cooperative_tools
		var b: RefCounted=guest_editor.cooperative_tools
		a.name_field.text="Assembly host"
		a.password.text="assembly-pass"
		a.port.value=0
		a.host_game()
		check(a.session.server!=null,"Host starts with a valid furnished proposal: "+mode)
		if a.session.server==null: continue
		b.name_field.text="Assembly guest"
		b.password.text="assembly-pass"
		b.address.text="127.0.0.1"
		b.port.value=a.session.server.get_local_port()
		b.join_game()
		check(await wait_for(synced),"Actual peers converge on the proposed construction: "+mode)
		var ui: RefCounted=guest_editor.blueprint_tools
		guest_editor._command("blueprints",null)
		ui.selected="shared_copy"
		ui.review(["shared_copy"])
		check(ui.reviewed.is_empty() and ui.review_label.text.contains("Protected area"),"Guest review reports the protected site before a commit: "+mode)
		var locked: Dictionary=a.session.data.duplicate(true)
		ui.construct(false)
		await settle()
		check(a.session.data==locked and b.session.pending.is_empty(),"Protected construction produces no accepted or pending edit: "+mode)
		a.selected="protected_site"
		a.remove_area()
		check(await wait_for(func():return synced() and host_editor.current().data.get("protected_areas",[]).is_empty()),"Host unlocks the site through the actual area control: "+mode)
		ui.review(["shared_copy"])
		check(not ui.reviewed.is_empty(),"Unlocked site receives a valid review: "+mode+" "+ui.review_label.text)
		var current: RefCounted=host_editor.current()
		current.checkpoint()
		current.data["blueprints"][0]["name"]="Host revised school"
		host_editor.changed()
		check(await wait_for(func():return synced() and guest_editor.current().data["blueprints"][0]["name"]=="Host revised school"),"Host edit reaches the guest after preview: "+mode)
		var before: Dictionary=a.session.data.duplicate(true)
		ui.construct(false)
		await settle()
		check(a.session.data==before and b.session.pending.is_empty() and not ui.reviewed.is_empty(),"First commit after the conflict reviews the newer proposal without building: "+mode)
		var preview: Dictionary=Plan.construct(guest_editor.current().data,["shared_copy"],guest_editor.library)
		check(preview["ok"],"The refreshed proposal produces a complete quote: "+mode)
		if preview["ok"]:
			ui.construct(false)
			check(await wait_for(func():return synced() and host_editor.current().data["blueprints"].is_empty()),"Reviewed guest construction converges through host authority: "+mode)
			var accepted: Dictionary=a.session.data.duplicate(true)
			check(host_editor.current().data["economy_account"]["cash"]==preview["quote"]["account"]["cash"],"The host charges the accepted assembly exactly once: "+mode)
			guest_editor._command("undo",null)
			check(await wait_for(func():return synced() and a.session.data==before),"Shared Undo restores the exact reviewed proposal and account: "+mode)
			guest_editor._command("redo",null)
			check(await wait_for(func():return synced() and a.session.data==accepted),"Shared Redo restores the same assembly identities and account: "+mode)
		b.leave()
		a.leave()
		await settle()
	guest_editor.free()
	host_editor.free()
	await settle()
	print("FUNCTIONAL ASSEMBLY COOPERATIVE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
