extends "res://tools/test_collection_cooperative.gd"
const Economy=preload("res://scripts/builder/economy_plan.gd")
func run() -> void:
	host=load("res://scenes/builder.tscn").instantiate();guest=load("res://scenes/builder.tscn").instantiate()
	for editor in [host,guest]:editor.storage_enabled=false;root.add_child(editor)
	await settle()
	for mode in ["2d","3d"]:
		var doc: RefCounted=host.documents[mode];doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
		var asset: String="2d:Supplemental_Office_desk_kit_office_mug_9546ebf5" if mode=="2d" else "3d:Fire_Station_PSX/bench_vise"
		var prop: Dictionary=doc.add(asset,[0,0,0],str(host.library.directions(asset)[0]));prop["uid"]="tiny_"+mode
		var other: Dictionary=doc.add(asset,[50,0,0] if mode=="2d" else [2,0,0],prop["direction"]);other["uid"]="other_"+mode
		doc.data["economy"]={"enabled":true,"starting_cash":100000};doc.data["economy_account"]=Economy.fresh_account(doc.data,host.library);host.economy_tools.pauses[mode]=true
	host.changed();var a: RefCounted=host.cooperative_tools;var b: RefCounted=guest.cooperative_tools
	a.name_field.text="Prop host";a.password.text="tiny-prop-fixture";a.port.value=0;a.host_game()
	if a.session.server==null:
		check(false,"Fixture must be hostable: "+a.session.notice)
		for mode in ["2d","3d"]:print("Document valid ",mode,": ",preload("res://scripts/builder/document.gd").valid(host.documents[mode].data,mode,host.library))
		host.free();guest.free();await settle();quit(1);return
	b.name_field.text="Prop guest";b.password.text="tiny-prop-fixture";b.address.text="127.0.0.1";b.port.value=a.session.server.get_local_port();b.join_game()
	check(await wait_until(func():return a.participating and b.participating and synced()),"Actual Host/Join converges before prop editing")
	for mode in ["2d","3d"]:
		host.switch_mode(mode);guest.switch_mode(mode);await settle()
		var uid: String="tiny_"+mode;var other: String="other_"+mode;var accepted: Dictionary=a.session.data.duplicate(true);var treasury: Dictionary=accepted[mode]["economy_account"].duplicate(true)
		var host_camera: Dictionary=host.small_prop_tools.camera_state();guest.overlap_picker.choose(uid);guest._command("small_props_isolate",null);await settle()
		check(guest.small_prop_tools.active and not host.small_prop_tools.active and synced() and a.session.data==accepted,"Magnification/isolation are personal and create no shared edit: "+mode)
		check(not guest.worlds[mode].instances[other].visible and host.worlds[mode].instances[other].visible and host.small_prop_tools.camera_state()==host_camera,"Guest view does not hide or move host's view: "+mode)
		var doc: RefCounted=guest.current();doc.checkpoint();doc.object(uid)["position"][0]+=2 if mode=="2d" else .05;doc.finish_checkpoint();guest.changed()
		check(await wait_until(func():return synced() and a.session.data!=accepted),"Normal edit while isolated is accepted by authority: "+mode)
		var moved: Dictionary=a.session.data.duplicate(true)
		check(host.current().object(uid)["position"]==guest.current().object(uid)["position"] and moved[mode]["economy_account"]==treasury,"Exact small movement converges without a construction charge: "+mode)
		check(not guest.worlds[mode].instances[other].visible and host.worlds[mode].instances[other].visible,"Shared refresh retains each editor's personal isolation: "+mode)
		guest._command("undo",null);check(await wait_until(func():return synced() and a.session.data==accepted),"Shared Undo restores source position and treasury: "+mode)
		guest._command("redo",null);check(await wait_until(func():return synced() and a.session.data==moved),"Shared Redo restores exact prop movement: "+mode)
		a.area_name.text="Protected counter";a.area_owner.select(0);a.add_bounds(Rect2(-8,-8,16,16));check(await wait_until(synced),"Host assigns the counter to itself: "+mode)
		accepted=a.session.data.duplicate(true);b.failed_edit=false;doc=guest.current();doc.checkpoint();doc.object(uid)["position"][0]+=1 if mode=="2d" else .01;doc.finish_checkpoint();guest.changed()
		check(await wait_until(func():return b.failed_edit and synced()),"Isolation cannot bypass host protection: "+mode)
		check(a.session.data==accepted and not b.draft.is_empty() and a.session.data[mode]["economy_account"]==treasury,"Rejected prop edit retains recovery draft and accepted treasury: "+mode)
		guest._command("small_props_return",null);await settle();check(not guest.small_prop_tools.active and guest.worlds[mode].instances[other].visible,"Return restores guest view after shared rejection: "+mode)
		a.selected=host.current().data["protected_areas"][0]["uid"];a.remove_area();check(await wait_until(synced),"Host removes fixture protection through ordinary controls: "+mode)
	b.leave();a.leave();host.free();guest.free();await settle();print("SMALL PROP COOPERATIVE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
