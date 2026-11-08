extends SceneTree
const Session=preload("res://scripts/builder/cooperative_session.gd")
const Merge=preload("res://scripts/builder/cooperative_merge.gd")
const Delta=preload("res://scripts/builder/document_delta.gd")
const Plan=preload("res://scripts/builder/cooperative_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func wait_until(test: Callable) -> bool:
	for frame in 500:
		if test.call(): return true
		await process_frame
	return false
func item(uid: String,asset: String,x: float=0) -> Dictionary:
	return {"uid":uid,"asset":asset,"position":[x,0,0],"direction":"SE","scale":1.0}
func run() -> void:
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new(); var source: Dictionary={"2d":preload("res://scripts/builder/templates.gd").make("2d","blank"),"3d":preload("res://scripts/builder/templates.gd").make("3d","blank")}
	var host:=Session.new(); var a:=Session.new(); var b:=Session.new(); root.add_child(host); root.add_child(a); root.add_child(b)
	check(host.host(source,library,0,"fixture-pass","Host","127.0.0.1")==OK,"Start a real TCP host on a free loopback port")
	var port: int=host.server.get_local_port(); check(port>0,"Host reports the actual listening port")
	check(a.join("127.0.0.1",port,"fixture-pass","Alice",library)==OK and b.join("127.0.0.1",port,"fixture-pass","Bob",library)==OK,"Start two real TCP collaborators")
	check(await wait_until(func():return a.connected and b.connected),"Authenticated peers receive and validate the shared city")
	if not a.connected or not b.connected: print(a.notice," / ",b.notice); host.close(); a.close(); b.close(); host.free(); a.free(); b.free(); quit(1); return
	var first: Dictionary=a.data.duplicate(true); var second: Dictionary=b.data.duplicate(true); first["2d"]["objects"].append(item("alice","2d:Sedan_Blue",100)); second["2d"]["objects"].append(item("bob","2d:Sedan_Blue",300))
	a.submit(Delta.between(a.data,first)); b.submit(Delta.between(b.data,second)); check(await wait_until(func():return host.data["2d"]["objects"].size()==2 and a.pending.is_empty() and b.pending.is_empty()),"Concurrent disjoint construction merges without replacing either builder's object")
	check(await wait_until(func():return a.data==host.data and b.data==host.data),"All peers converge to the same accepted city")
	a.local_cursor={"mode":"2d","scope":"city","point":[123,45,0],"visible":true}; check(await wait_until(func():
		var point: Array=b.roster.get(a.local_id,{}).get("cursor",{}).get("point",[]); return point.size()==3 and Vector3(point[0],point[1],point[2]).is_equal_approx(Vector3(123,45,0))),"Cursor movement is relayed to the other collaborator")
	var road_a: Dictionary=a.data.duplicate(true); var road_b: Dictionary=b.data.duplicate(true); preload("res://scripts/builder/roads.gd").paint(road_a["3d"],Vector2i(0,0),Vector2i(1,0)); preload("res://scripts/builder/roads.gd").paint(road_b["3d"],Vector2i(8,0),Vector2i(9,0))
	a.submit(Delta.between(a.data,road_a)); b.submit(Delta.between(b.data,road_b)); check(await wait_until(func():return host.data["3d"]["roads"].size()==4 and a.pending.is_empty() and b.pending.is_empty()),"JSON transport preserves canonical cell identities for concurrent roads")
	var before: Dictionary=host.data.duplicate(true); var protected: Dictionary=before.duplicate(true); protected["2d"]["protected_areas"]=[{"uid":"zone","name":"Alice's work","owner":a.local_id,"rect":[-20,-20,40,40]}]; host.submit(Delta.between(before,protected)); await wait_until(func():return a.revision==host.revision and b.revision==host.revision)
	var blocked: Dictionary=b.data.duplicate(true); blocked["2d"]["objects"].append(item("intruder","2d:Sedan_Blue")); var revision: int=host.revision; b.submit(Delta.between(b.data,blocked)); check(await wait_until(func():return b.pending.is_empty()),"Protected-area rejection returns a definite response")
	check(host.revision==revision and not b.rejected_delta.is_empty() and b.notice.contains("Protected area"),"Host rejects unauthorized construction and retains a recoverable edit intent")
	var allowed: Dictionary=a.data.duplicate(true); allowed["2d"]["objects"].append(item("owned","2d:Sedan_Blue")); a.submit(Delta.between(a.data,allowed)); check(await wait_until(func():return a.pending.is_empty() and host.data["2d"]["objects"].size()==3),"Assigned collaborator can construct in the protected area")
	a.request_undo(); check(await wait_until(func():return a.pending.is_empty() and host.data["2d"]["objects"].size()==2),"Shared Undo reverts the caller's accepted construction")
	a.request_undo(true); check(await wait_until(func():return a.pending.is_empty() and host.data["2d"]["objects"].size()==3),"Shared Redo restores the caller's construction")
	var old: Dictionary=host.data.duplicate(true); var one: Dictionary=old.duplicate(true); var two: Dictionary=old.duplicate(true); one["2d"]["objects"][0]["position"]=[400,0,0]; two["2d"]["objects"][0]["position"]=[500,0,0]
	check(Merge.apply(one,Delta.between(old,two))["ok"]==false,"Overlapping field edits report conflicts instead of overwriting newer work")
	for bad in [null,[],{}, {"fields":[],"collections":{}},{"fields":{},"collections":{"objects":null}}]: check(not Merge.apply(old,bad)["ok"],"Malformed network changes are refused")
	var economy=preload("res://scripts/builder/economy_plan.gd"); var car_cost: int=economy.profile("2d:Sedan_Blue",library)["construction"]; var funded: Dictionary=host.data.duplicate(true); funded["2d"]["economy"]={"enabled":true,"starting_cash":car_cost*10,"period_seconds":60,"refund_percent":25}; funded["2d"]["economy_account"]=economy.fresh_account(funded["2d"],library); host.submit(Delta.between(host.data,funded)); await wait_until(func():return a.data==host.data and b.data==host.data)
	var paid_a: Dictionary=a.data.duplicate(true); var paid_b: Dictionary=b.data.duplicate(true); paid_a["2d"]["objects"].append(item("paid_a","2d:Sedan_Blue",500)); paid_b["2d"]["objects"].append(item("paid_b","2d:Sedan_Blue",700)); a.submit(Delta.between(a.data,paid_a)); b.submit(Delta.between(b.data,paid_b))
	check(await wait_until(func():return host.data["2d"]["objects"].size()==5 and a.pending.is_empty() and b.pending.is_empty()),"Concurrent clients share one authoritative construction budget")
	check(host.data["2d"]["economy_account"]["cash"]==car_cost*8,"Each concurrent purchase is charged exactly once")
	var host_purchase: Dictionary=host.data.duplicate(true); host_purchase["2d"]["objects"].append(item("host_paid","2d:Sedan_Blue",900)); host.submit(Delta.between(host.data,host_purchase)); check(host.data["2d"]["economy_account"]["cash"]==car_cost*7,"A rebased host placement is charged even without a local account delta")
	var period_before: int=host.data["2d"]["economy_account"]["period"]; host.settle_economy("2d"); check(host.data["2d"]["economy_account"]["period"]==period_before+1,"Shared operating periods settle on the authoritative host")
	check(not a.settle_economy("2d"),"Clients cannot duplicate operating-period settlement")
	var empty_budget: Dictionary=host.data.duplicate(true); empty_budget["2d"]["economy"]["starting_cash"]=0; empty_budget["2d"]["economy_account"]=economy.fresh_account(empty_budget["2d"],library); host.submit(Delta.between(host.data,empty_budget)); await wait_until(func():return a.data==host.data and b.data==host.data)
	var unaffordable: Dictionary=a.data.duplicate(true); unaffordable["2d"]["objects"].append(item("too_costly","2d:Sedan_Blue",1100)); revision=host.revision; a.submit(Delta.between(a.data,unaffordable)); await wait_until(func():return a.pending.is_empty()); check(host.revision==revision and a.notice.contains("budget"),"Insufficient shared funds reject the entire construction atomically")
	var building_asset: String=""
	for id in library.assets:
		if id.begins_with("2d:") and library.assets[id]["behavior"].get("building",false): building_asset=id; break
	var starter: Dictionary=host.data.duplicate(true); starter["2d"]["economy"]["enabled"]=false; var building: Dictionary=item("room_host",building_asset,1500); building["direction"]=str(library.directions(building_asset)[0]); starter["2d"]["objects"].append(building); host.submit(Delta.between(host.data,starter))
	starter=host.data.duplicate(true); starter["2d"]["economy"]={"enabled":true,"starting_cash":100000,"period_seconds":60,"refund_percent":25}; starter["2d"]["economy_account"]=economy.fresh_account(starter["2d"],library); host.submit(Delta.between(host.data,starter)); await wait_until(func():return a.data==host.data)
	var room_city: Dictionary=a.data.duplicate(true)
	for entry in room_city["2d"]["objects"]:
		if entry["uid"]=="room_host": entry["interior"]=preload("res://scripts/builder/interiors.gd").make_for(entry,"2d",library)
	a.submit(Delta.between(a.data,room_city)); check(await wait_until(func():return a.pending.is_empty() and host.data["2d"]["objects"].back().has("interior")),"Client can initialize a persistent owned room in shared economy mode")
	check(host.data["2d"]["economy_account"]["cash"]==100000 and host.data["2d"]["economy_account"]["construction_total"]==0,"The ordinary starter-room allowance remains complimentary in co-op")
	var spoof:=Session.new(); root.add_child(spoof); spoof.library=library; spoof.role="joining"; spoof.receive_client({"kind":"snapshot","data":host.data,"id":"peer_spoof","revision":host.revision,"roster":{},"history":{}}); check(spoof.role=="offline" and spoof.data.is_empty(),"An unauthenticated host cannot bypass the password challenge with a city snapshot"); spoof.free()
	var roster_before: Dictionary=a.roster.duplicate(true); a.receive_client({"kind":"presence","roster":{"bad":null}}); check(a.roster==roster_before,"Malformed cursor rosters are ignored without replacing valid presence")
	var forged: Dictionary=b.data.duplicate(true); forged["2d"]["objects"].append(item("forged_host","2d:Sedan_Blue",0)); revision=host.revision; b.upstream.send({"kind":"edit","actor":"host","request":"forged","delta":Delta.between(b.data,forged)})
	for frame in 30: await process_frame
	check(host.revision==revision,"A forged actor field cannot bypass host-side area ownership")
	var wrong:=Session.new(); root.add_child(wrong); wrong.join("127.0.0.1",port,"wrong-pass","Wrong",library); check(await wait_until(func():return wrong.role=="offline"),"Incorrect session password is rejected before city replacement"); check(not wrong.connected and wrong.data.is_empty(),"Failed authentication leaves the peer's city state untouched")
	var departed: String=b.local_id; b.close(); check(await wait_until(func():return not host.roster.has(departed)),"Disconnect removes the peer and cursor from the host roster")
	b.join("127.0.0.1",port,"fixture-pass","Bob",library); check(await wait_until(func():return b.connected),"A disconnected collaborator can reconnect using its private session token")
	check(b.local_id==departed,"Reconnection preserves the collaborator's protected-area identity and history")
	host.close(); a.close(); b.close(); wrong.close(); host.free(); a.free(); b.free(); wrong.free(); await process_frame
	print("Cooperative foundation: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
