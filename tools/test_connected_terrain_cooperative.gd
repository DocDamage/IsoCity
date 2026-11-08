extends "res://tools/test_connected_terrain.gd"

const Economy=preload("res://scripts/builder/economy_plan.gd")
var host: Control
var guest: Control

func synchronized() -> bool:
	var a: RefCounted=host.cooperative_tools
	var b: RefCounted=guest.cooperative_tools
	return a.participating and b.participating and not a.dirty and not b.dirty and b.session.pending.is_empty() and a.snapshot()==b.snapshot()

func wait_for(condition: Callable) -> bool:
	for frame in 1000:
		if condition.call(): return true
		await process_frame
	return false

func run() -> void:
	host=load("res://scenes/builder.tscn").instantiate()
	guest=load("res://scenes/builder.tscn").instantiate()
	for editor in [host,guest]:
		editor.storage_enabled=false
		root.add_child(editor)
	await settle()
	for editor in [host,guest]:
		if editor.consumer_shell: editor.consumer_shell.dismiss_welcome()
		editor.switch_mode("2d")
		editor.economy_tools.pauses["2d"]=true
	studio=guest
	var data: Dictionary=Templates.make("2d","blank")
	data["tiles"]=[{"cell":[0,0],"asset":"2d:Stone_Path","family":"path","direction":"SE"}]
	data["protected_areas"]=[{"uid":"plot","name":"Protected path","owner":"host","rect":[.5,.5,1,1]}]
	data["economy"]={"enabled":true,"starting_cash":1000000,"period_seconds":60}
	data["economy_account"]=Economy.fresh_account(data,host.library)
	host.current().data=data
	host.changed()
	var a: RefCounted=host.cooperative_tools
	var b: RefCounted=guest.cooperative_tools
	a.name_field.text="Terrain host"
	a.password.text="terrain-pass"
	a.port.value=0
	a.host_game()
	check(a.session.server!=null,"Host starts from the prepared path city.")
	if a.session.server==null: quit(1); return
	b.name_field.text="Terrain guest"
	b.password.text="terrain-pass"
	b.address.text="127.0.0.1"
	b.port.value=a.session.server.get_local_port()
	b.join_game()
	var ready: bool=await wait_for(synchronized)
	check(ready,"Both peers display the exact same path and protected region.")
	if not ready: b.leave(); a.leave(); quit(1); return
	var baseline: Dictionary=a.session.data.duplicate(true)
	brush(2,0)
	paint(Vector2i.RIGHT,Vector2i.RIGHT)
	await settle()
	check(a.session.data==baseline and b.snapshot()==baseline and guest.status.text.contains("Protected"),
		"Guest cannot change the protected cell's neighbor through connected painting.")
	a.selected="plot"
	a.remove_area()
	check(await wait_for(func():return synchronized() and host.current().data["protected_areas"].is_empty()),"Host releases the protected path.")
	var before: Dictionary=a.session.data.duplicate(true)
	var candidate: Dictionary=before["2d"].duplicate(true)
	candidate["tiles"].append({"cell":[1,0],"asset":"2d:Stone_Path","family":"path","direction":"SE"})
	var quote: Dictionary=Economy.quote(before["2d"],candidate,host.library)
	brush(2,0)
	paint(Vector2i.RIGHT,Vector2i.RIGHT)
	check(await wait_for(func():return synchronized() and host.current().data["tiles"].size()==2),"One legal stroke converges on both peers.")
	var a_world: Node=host.worlds["2d"]
	var b_world: Node=guest.worlds["2d"]
	check(a_world.family_variants==b_world.family_variants and a_world.family_variants.get(Vector2i.ZERO,{}).get("mask")==2,
		"Both peer renderers derive the same eastern arm without editing the original tile.")
	check(a.session.data["2d"]["economy_account"]==JSON.parse_string(JSON.stringify(quote["account"])),
		"Only the authored paint settles through the existing economy quote.")
	guest._command("undo",null)
	check(await wait_for(func():return synchronized() and a.session.data==before),"Shared Undo restores the exact tile and treasury records.")
	b.leave()
	a.leave()
	guest.free()
	host.free()
	await settle()
	print("CONNECTED TERRAIN COOPERATIVE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
