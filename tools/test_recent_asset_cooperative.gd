extends SceneTree
const OUT="res://output/verification/asset_expansion/U14/"
var host: Control
var guest: Control
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func settle() -> void:
	for frame in 10:await physics_frame
func wait_until(test: Callable) -> bool:
	for frame in 900:
		if test.call():return true
		await process_frame
	return false
func synced() -> bool:
	var a: RefCounted=host.cooperative_tools;var b: RefCounted=guest.cooperative_tools
	return not a.dirty and not b.dirty and b.session.pending.is_empty() and a.snapshot()==b.snapshot() and a.snapshot()==a.session.data
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT);FileAccess.open(OUT+".gdignore",FileAccess.WRITE).close()
	host=load("res://scenes/builder.tscn").instantiate();guest=load("res://scenes/builder.tscn").instantiate()
	for studio in [host,guest]:studio.storage_enabled=false;root.add_child(studio)
	await settle()
	for studio in [host,guest]:
		studio.consumer_shell.dismiss_welcome()
		for mode in ["2d","3d"]:
			studio.documents[mode].data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
			var item: Dictionary=studio.documents[mode].add("3d:HanX_School/School_Building",[0,0,0],"0");item["uid"]="recent_owner_"+mode;item["interior"]=preload("res://scripts/builder/interior_kit_plan.gd").shell(mode,studio.library)
		studio.changed()
	var a: RefCounted=host.cooperative_tools;var b: RefCounted=guest.cooperative_tools;var ah: RefCounted=host.asset_browser.recents;var bh: RefCounted=guest.asset_browser.recents
	a.name_field.text="Recent host";a.password.text="recent-pass";a.port.value=0;a.host_game()
	b.name_field.text="Recent guest";b.password.text="recent-pass";b.address.text="127.0.0.1";b.port.value=a.session.server.get_local_port();b.join_game()
	check(await wait_until(func():return a.participating and b.participating and synced()),"Real host/guest instances connect before testing local placement receipts")
	for mode in ["2d","3d"]:
		host.switch_mode(mode);guest.switch_mode(mode);await settle();var uid: String="recent_owner_"+mode
		ah.history.histories={};bh.history.histories={};guest.asset_browser.task_collections.choose("classroom");guest.interior_tools.start(uid);await settle()
		var accepted: Dictionary=a.session.data.duplicate(true);guest.select_asset("3d:HanX_School/Student_Chair");guest.clear_placement();await settle()
		check(ah.history.histories.is_empty() and bh.history.histories.is_empty() and synced() and a.session.data==accepted,"Selecting and canceling shared placement records no local or peer history: "+mode)
		guest.drop_asset("3d:HanX_School/Student_Chair",guest.canvas.size*.5)
		check(bh.history.histories.is_empty() and not bh.pending.is_empty(),"Optimistic shared placement waits for host acceptance before becoming recent: "+mode)
		check(await wait_until(func():return synced() and bh.pending.is_empty() and bh.history.ids("classroom").has("3d:HanX_School/Student_Chair")),"Accepted actual room placement records a scoped guest-local receipt: "+mode)
		check(ah.history.histories.is_empty() and not a.session.data[mode].has("histories"),"Remote accepted construction never enters the host's local history or project data: "+mode)
		var before: Dictionary=bh.history.state();a.select_owner("host");a.area_name.text="Recent protected owner";a.add_bounds(Rect2(-20,-20,40,40));check(await wait_until(synced),"Protection reaches the current guest room: "+mode)
		b.failed_edit=false;guest.drop_asset("3d:HanX_School/Teacher_Chair",guest.canvas.size*.7)
		check(await wait_until(func():return synced() and b.failed_edit and bh.pending.is_empty()),"Host rejects optimistic room placement and settles its local receipt: "+mode)
		check(bh.history.state()==before and not b.draft.is_empty(),"Rejected shared construction retains a recovery draft without adding a recent asset: "+mode)
		guest.interior_tools.leave();await settle();host.asset_browser.task_collections.choose("classroom");host.interior_tools.start(uid);await settle();host.drop_asset("3d:HanX_School/Student_Desk",host.canvas.size*.7)
		check(await wait_until(func():return synced() and ah.pending.is_empty() and ah.history.ids("classroom").has("3d:HanX_School/Student_Desk")),"Host's own accepted placement records only its own task history: "+mode)
		check(bh.history.state()==before,"Accepted remote host placement leaves the guest's personal recents untouched: "+mode)
		host.interior_tools.leave();await settle()
	check(host.write_project(OUT+"cooperative.isocity.json") and not JSON.stringify(host.session_data()).contains("histories"),"Ordinary shared save excludes every local history")
	b.leave();a.leave();host.free();guest.free();await process_frame;await process_frame;print("RECENT ASSET COOPERATIVE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
