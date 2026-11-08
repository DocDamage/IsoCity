extends SceneTree
const Economy=preload("res://scripts/builder/economy_plan.gd")
const Shell=preload("res://scripts/builder/interior_kit_plan.gd")
var host: Control
var guest: Control
var checks: int=0
var failures: int=0
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
func review(studio: Control,uid: String) -> RefCounted:
	studio.selected_uid=uid;studio.selected_uids.assign([uid]);studio.refresh_controls();var tools: RefCounted=studio.companion_tools;tools.start()
	check(await wait_until(func():return tools.proposal.has("ok") and (not tools.proposal["ok"] or tools.proposal.get("geometry_checked",false))),"Shared companion review finishes");return tools
func run() -> void:
	host=load("res://scenes/builder.tscn").instantiate();guest=load("res://scenes/builder.tscn").instantiate()
	for studio in [host,guest]:studio.storage_enabled=false;root.add_child(studio)
	check(await wait_until(func():return host.enhancements_ready and guest.enhancements_ready and host.consumer_shell!=null and guest.consumer_shell!=null),"Both actual editors finish deferred initialization");await settle()
	for studio in [host,guest]:
		studio.consumer_shell.dismiss_welcome()
		for mode in ["2d","3d"]:
			var city: RefCounted=studio.documents[mode];city.data=preload("res://scripts/builder/templates.gd").make(mode,"blank");var item: Dictionary=city.add("3d:HanX_School/School_Building",[0,0,0],"0");item["uid"]="companion_owner_"+mode;item["interior"]=Shell.shell(mode,studio.library)
			item["interior"]["objects"].append({"uid":"shared_source_"+mode,"asset":"3d:HanX_School/Student_Desk","direction":"0","scale":1,"position":[0,0,0] if mode=="2d" else [0,.12,0],"name":"Preserved shared desk"})
			city.data["economy"]={"enabled":true,"starting_cash":100000};city.data["economy_account"]=Economy.fresh_account(city.data,studio.library)
		studio.changed()
	var a: RefCounted=host.cooperative_tools;var b: RefCounted=guest.cooperative_tools;var ah: RefCounted=host.asset_browser.recents;var bh: RefCounted=guest.asset_browser.recents
	a.name_field.text="Companion host";a.password.text="companion-pass";a.port.value=0;a.host_game();b.name_field.text="Companion guest";b.password.text="companion-pass";b.address.text="127.0.0.1";b.port.value=a.session.server.get_local_port();b.join_game()
	check(await wait_until(func():return a.participating and b.participating and synced()),"Actual host and guest connect before companion edits")
	for mode in ["2d","3d"]:
		host.switch_mode(mode);guest.switch_mode(mode);await settle();ah.history.histories={};bh.history.histories={};var owner: String="companion_owner_"+mode;var source: String="shared_source_"+mode
		host.interior_tools.start(owner);guest.interior_tools.start(owner);await settle();var before: Dictionary=a.session.data.duplicate(true);var tools: RefCounted=await review(guest,source)
		check(synced() and a.session.data==before and ah.history.histories.is_empty() and bh.history.histories.is_empty(),"Shared companion inspection edits no layout, money or personal history")
		check(not tools.dialog.get_ok_button().disabled and tools.proposal["created"].size()==1,"One missing chair is reviewable in the shared room")
		var cost: int=tools.proposal["quote"]["net"];var cash: int=a.session.data[mode]["economy_account"]["cash"];tools.apply()
		check(bh.history.histories.is_empty() and not bh.pending.is_empty(),"Companion recent receipt waits for host acceptance")
		check(await wait_until(func():return synced() and bh.pending.is_empty() and bh.history.ids("").has("3d:HanX_School/Student_Chair")),"Host accepts the ordinary whole companion transaction")
		var accepted: Dictionary=a.session.data.duplicate(true);check(host.interior_tools.editing() and guest.interior_tools.editing() and host.current().data==guest.current().data,"Both editors retain their owned floor and identical accepted pieces")
		check(a.session.data[mode]["economy_account"]["cash"]==cash-cost and ah.history.histories.is_empty(),"Host charges once and remote edits never become personal recents")
		guest._command("undo",null);check(await wait_until(func():return synced() and a.session.data==before),"Shared companion Undo restores the exact source and treasury");guest._command("redo",null);check(await wait_until(func():return synced() and a.session.data==accepted),"Shared companion Redo preserves identities without another charge")
		guest._command("undo",null);check(await wait_until(func():return synced() and a.session.data==before),"Remove the accepted chair before reviewing protection")
		host.interior_tools.leave();await settle();a.select_owner("host");a.area_name.text="Protected companion owner";a.add_bounds(Rect2(-20,-20,40,40));check(await wait_until(synced),"Host exterior protection reaches the entire owned room")
		tools=await review(guest,source);before=a.session.data.duplicate(true);var history: int=guest.current().undo_history.size();var recent: Dictionary=bh.history.state()
		check(tools.proposal.get("ok",false) and tools.dialog.get_ok_button().disabled and not tools.message.text.is_empty(),"Protected companions remain inspectable with an explicit blocked Apply")
		tools.apply();await settle();check(synced() and a.session.data==before and guest.current().undo_history.size()==history and bh.history.state()==recent and bh.pending.is_empty(),"Protected Apply creates no optimistic partial edit, money change or receipt");tools.dialog.hide()
		guest.interior_tools.leave();host.interior_tools.leave();await settle()
	b.leave();a.leave();host.free();guest.free();await process_frame;await process_frame;print("COMPANION COOPERATIVE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
