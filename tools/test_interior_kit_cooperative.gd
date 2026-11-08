extends SceneTree
const Economy=preload("res://scripts/builder/economy_plan.gd")
var checks: int=0
var failures: int=0
var host: Control
var guest: Control
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func settle() -> void:
	for frame in 8:await physics_frame
func wait_until(test: Callable) -> bool:
	for frame in 900:
		if test.call():return true
		await process_frame
	return false
func synced() -> bool:
	var a: RefCounted=host.cooperative_tools;var b: RefCounted=guest.cooperative_tools
	return not a.dirty and not b.dirty and b.session.pending.is_empty() and a.snapshot()==b.snapshot() and a.snapshot()==a.session.data
func ready(tools: RefCounted) -> void:
	check(await wait_until(func():return tools.proposal.has("ok") and (not tools.proposal["ok"] or tools.proposal.get("geometry_checked",false))),"Shared preview finishes")
func choose(studio: Control,key: String,action: String) -> RefCounted:
	var tools: RefCounted=studio.interior_tools.kit_chooser;tools.show();tools.select(tools.kit,key);tools.select(tools.action,action);tools.refresh();await ready(tools);return tools
func select_owner(studio: Control,uid: String) -> void:
	studio.selected_uid=uid;studio.selected_uids.assign([uid]);studio.refresh_controls()
func run() -> void:
	host=load("res://scenes/builder.tscn").instantiate();guest=load("res://scenes/builder.tscn").instantiate()
	for studio in [host,guest]:studio.storage_enabled=false;root.add_child(studio)
	await settle()
	for studio in [host,guest]:
		studio.consumer_shell.dismiss_welcome()
		for mode in ["2d","3d"]:
			var doc: RefCounted=studio.documents[mode];doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
			var item: Dictionary=doc.add("3d:HanX_School/School_Building",[0,0,0],"0");item["uid"]="kit_shared_"+mode
			doc.data["economy"]={"enabled":true,"starting_cash":100000};doc.data["economy_account"]=Economy.fresh_account(doc.data,studio.library)
		studio.changed()
	var a: RefCounted=host.cooperative_tools;var b: RefCounted=guest.cooperative_tools
	a.name_field.text="Kit host";a.password.text="kit-pass";a.port.value=0;a.host_game()
	b.name_field.text="Kit guest";b.password.text="kit-pass";b.address.text="127.0.0.1";b.port.value=a.session.server.get_local_port();b.join_game()
	check(await wait_until(func():return a.participating and b.participating and synced()),"Actual host/guest controls converge before kit operations")
	for mode in ["2d","3d"]:
		host.switch_mode(mode);guest.switch_mode(mode);await settle();var uid: String="kit_shared_"+mode;select_owner(guest,uid)
		var before: Dictionary=b.snapshot().duplicate(true);var tools: RefCounted=await choose(guest,"classroom","create")
		check(b.snapshot()==before and synced(),"Shared read-only review creates no room or pending transaction: "+mode)
		check(tools.proposal.get("quote",{}).get("construction",-1)==0,"Shared first default receives the same free allowance: "+mode)
		tools.apply();check(await wait_until(func():return host.current().object(uid).has("interior") and synced()),"Guest Apply commits the whole starter through host authority: "+mode)
		check(a.session.data[mode]["economy_account"]["cash"]==100000,"Host does not double charge the complimentary starter: "+mode)
		var created: Dictionary=a.session.data.duplicate(true);guest._command("undo",null)
		check(await wait_until(func():return not host.current().object(uid).has("interior") and synced()),"Shared author Undo removes precisely the created layout: "+mode)
		guest._command("redo",null);check(await wait_until(func():return a.session.data==created and synced()),"Shared Redo restores the same furnishing identities and account: "+mode)
		host.interior_tools.start(uid);guest.interior_tools.start(uid);await settle()
		tools=await choose(guest,"empty","replace");tools.apply();check(await wait_until(synced),"Shared room replacement converges without closing either editor: "+mode)
		check(host.interior_tools.editing() and guest.interior_tools.editing() and host.current().data["objects"]==guest.current().data["objects"] and host.current().data["objects"].size()<created[mode]["objects"][0]["interior"]["objects"].size(),"Both editors retain their room scope and actual replaced contents: "+mode)
		var emptied: Dictionary=a.session.data.duplicate(true);tools=await choose(guest,"shop","add");var net: int=tools.proposal.get("quote",{}).get("net",0);var cash: int=a.session.data[mode]["economy_account"]["cash"]
		check(net>0 and not tools.dialog.get_ok_button().disabled,"Shared additional shop furnishing has a positive affordable quote: "+mode)
		tools.apply();check(await wait_until(synced),"Shared Add converges: "+mode)
		check(a.session.data[mode]["economy_account"]["cash"]==cash-net,"Authoritative host charges Add exactly once: "+mode)
		var added: Dictionary=a.session.data.duplicate(true);guest._command("undo",null);check(await wait_until(func():return a.session.data==emptied and synced()),"Shared Add Undo restores exact room and treasury: "+mode)
		guest._command("redo",null);check(await wait_until(func():return a.session.data==added and synced()),"Shared Add Redo restores identities without another charge: "+mode)
		tools=await choose(guest,"apartment","floor");tools.apply();check(await wait_until(synced),"Shared new-floor application converges: "+mode)
		var floor_uid: String=guest.current().floor_uid
		check(floor_uid!="ground" and a.session.data[mode]["objects"][0]["interior"]["floors"].size()==1,"Host accepts one fresh independently editable apartment floor: "+mode)
		guest.interior_tools.leave();host.interior_tools.leave();await settle();check(await wait_until(synced),"Leaving shared applied rooms flushes identical source data: "+mode)
		# Host-owned protected exteriors include every owned floor.
		a.select_owner("host");a.area_name.text="Protected kit owner";a.add_bounds(Rect2(-20,-20,40,40));check(await wait_until(synced),"Host protection assignment reaches guest: "+mode)
		select_owner(guest,uid);before=b.snapshot().duplicate(true);tools=await choose(guest,"apartment","replace")
		check(tools.proposal.get("ok",false) and not tools.dialog.get_ok_button().disabled,"Protected layouts can be inspected before authoritative submission: "+mode)
		b.failed_edit=false;tools.apply();tools.dialog.hide()
		check(await wait_until(func():return b.failed_edit and synced()),"Host rejects unassigned guest kit edits through the ordinary shared transaction: "+mode)
		check(b.snapshot()==before and not b.draft.is_empty() and guest.status.text.contains("Co-op"),"Rejected protected proposal preserves accepted data, treasury and a recovery draft: "+mode)
	b.leave();a.leave();host.free();guest.free();await process_frame;await process_frame
	print("INTERIOR KIT COOPERATIVE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
