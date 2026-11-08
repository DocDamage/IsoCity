extends Node
const Wire=preload("res://scripts/builder/cooperative_wire.gd")
const Merge=preload("res://scripts/builder/cooperative_merge.gd")
const Plan=preload("res://scripts/builder/cooperative_plan.gd")
const Delta=preload("res://scripts/builder/document_delta.gd")
const Doc=preload("res://scripts/builder/document.gd")
const Economy=preload("res://scripts/builder/economy_plan.gd")
const Zone=preload("res://scripts/builder/zone_plan.gd")
const PROTOCOL=1
const MAX_PEERS=8
var role: String="offline"
var connected: bool=false
var library: RefCounted
var data: Dictionary={}
var revision: int=0
var local_id: String=""
var display_name: String="Builder"
var secret: String=""
var server: TCPServer
var peers: Dictionary={}
var upstream: RefCounted
var roster: Dictionary={}
var history: Array[Dictionary]=[]
var history_sequence: int=0
var history_flags: Dictionary={}
var pending: Dictionary={}
var rejected_delta: Dictionary={}
var rejected_view: Dictionary={}
var rejected_request: String=""
var notice: String="Offline"
var event_serial: int=0
var presence_serial: int=0
var sequence: int=0
var presence_elapsed: float=0
var started: int=0
var local_cursor: Dictionary={}
var host_verified: bool=false
var resume_tokens: Dictionary={}
var resume_token: String=""
var resume_endpoint: String=""
var current_endpoint: String=""
func proof(nonce: String,label: String) -> String:
	var context:=HMACContext.new(); context.start(HashingContext.HASH_SHA256,secret.to_utf8_buffer()); context.update(("IsoCity/"+label+"/"+nonce).to_utf8_buffer()); return context.finish().hex_encode()
func normalize_world(value: Dictionary) -> Dictionary:
	var result: Dictionary=value.duplicate(true)
	for key in ["roads","blueprints","zones","transit_lines","protected_areas","terrain_vertices","water_cells","connections"]:
		if not result.has(key): result[key]=[]
	for item in result["objects"]:
		if item.has("interior"): item["interior"]=normalize_world(item["interior"])
	for floor in result.get("floors",[]): floor["room"]=normalize_world(floor["room"])
	return result
func normalize(value: Dictionary) -> Dictionary:
	var result: Dictionary={"2d":normalize_world(value["2d"]),"3d":normalize_world(value["3d"])}
	if value.has("project_palette") and not value["project_palette"].is_empty():result["project_palette"]=value["project_palette"].duplicate(true)
	return JSON.parse_string(JSON.stringify(result))
func valid_data(value: Variant) -> bool:
	if not value is Dictionary: return false
	for mode in ["2d","3d"]:
		if not Doc.valid(value.get(mode),mode,library): return false
		for id in preload("res://scripts/builder/fleet_plan.gd").required(value[mode]):
			var asset: Dictionary=library.assets.get(id,{})
			if asset.is_empty() or asset.get("unavailable",false) or not ResourceLoader.exists(asset["path"],"PackedScene"):
				return false
	return not value.has("project_palette") or preload("res://scripts/builder/asset_collections.gd").project_valid(value["project_palette"])
func fail(reason: String) -> void: notice=reason; event_serial+=1
func host(source: Dictionary,assets: RefCounted,port: int,password: String,builder: String,bind_address: String="*") -> Error:
	close(); library=assets
	if password.is_empty() or password.length()>128 or builder.strip_edges().is_empty() or not valid_data(source): fail("Choose a password and a valid city before hosting."); return ERR_INVALID_PARAMETER
	server=TCPServer.new(); var error: Error=server.listen(port,bind_address)
	if error!=OK: server=null; fail("Could not listen on that address/port: "+error_string(error)); return error
	role="host"; connected=true; local_id="host"; secret=password; display_name=builder.strip_edges().substr(0,32); data=normalize(source); revision=0; history.clear(); history_sequence=0; history_flags={}; rejected_delta={}
	roster={"host":{"name":display_name,"cursor":{}}}; notice="Hosting · port "+str(server.get_local_port()); event_serial+=1; presence_serial+=1; return OK
func join(address: String,port: int,password: String,builder: String,assets: RefCounted) -> Error:
	close(); library=assets
	if password.is_empty() or password.length()>128 or builder.strip_edges().is_empty(): fail("Enter your name and the host's session password."); return ERR_INVALID_PARAMETER
	var socket:=StreamPeerTCP.new(); var error: Error=socket.connect_to_host(address,port)
	if error!=OK: fail("Could not connect: "+error_string(error)); return error
	current_endpoint=address+":"+str(port); upstream=Wire.new(socket); host_verified=false; role="joining"; display_name=builder.strip_edges().substr(0,32); secret=password; started=Time.get_ticks_msec(); notice="Connecting…"; event_serial+=1; return OK
func close(reason: String="Offline") -> void:
	if server: server.stop(); server=null
	for peer in peers.values(): peer["wire"].close()
	peers.clear(); resume_tokens.clear()
	if upstream: upstream.close(); upstream=null
	if not pending.is_empty(): rejected_delta=pending.get("delta",{}).duplicate(true); rejected_view=pending.get("view",{}).duplicate(true); rejected_request=pending.get("request","")
	pending.clear(); roster.clear(); history_flags.clear(); role="offline"; connected=false; secret=""; local_id=""; notice=reason; event_serial+=1; presence_serial+=1
func _exit_tree() -> void: close()
func _process(delta: float) -> void: step(delta)
func step(delta: float) -> void:
	if role=="host":
		while server.is_connection_available():
			var socket: StreamPeerTCP=server.take_connection()
			if peers.size()>=MAX_PEERS-1: socket.disconnect_from_host(); continue
			var id: String="peer_"+Crypto.new().generate_random_bytes(8).hex_encode(); var nonce: String=Crypto.new().generate_random_bytes(24).hex_encode(); var wire: RefCounted=Wire.new(socket); wire.max_frame=1024*1024
			peers[id]={"wire":wire,"connected":false,"name":"","nonce":nonce,"created":Time.get_ticks_msec(),"assets":{}}
			wire.send({"kind":"challenge","protocol":PROTOCOL,"nonce":nonce,"proof":proof(nonce,"host")})
		for id in peers.keys():
			if not peers.has(id): continue
			var peer: Dictionary=peers[id]; var wire: RefCounted=peer["wire"]; wire.step()
			var messages: Array=wire.messages.duplicate(); wire.messages.clear()
			for message in messages:
				if peers.has(id): receive_host(id,message)
			if wire.failed or (not peer["connected"] and Time.get_ticks_msec()-peer["created"]>10000): remove_peer(id)
		presence_elapsed+=delta
		if presence_elapsed>=.1:
			presence_elapsed=0; roster["host"]["cursor"]=local_cursor.duplicate(true); broadcast({"kind":"presence","roster":roster}); presence_serial+=1
	elif role in ["joining","client"] and upstream:
		upstream.step(); var messages: Array=upstream.messages.duplicate(); upstream.messages.clear()
		for message in messages:
			if upstream: receive_client(message)
		if upstream and (upstream.failed or (role=="joining" and Time.get_ticks_msec()-started>10000)): close("Connection lost. The last accepted shared city is kept; pending edits are available as a draft.")
		presence_elapsed+=delta
		if connected and upstream and presence_elapsed>=.1: presence_elapsed=0; upstream.send({"kind":"cursor","cursor":local_cursor})
func remove_peer(id: String) -> void:
	if not peers.has(id): return
	peers[id]["wire"].close(); peers.erase(id); roster.erase(id); presence_serial+=1
func broadcast(message: Dictionary) -> void:
	for peer in peers.values():
		if peer["connected"]: peer["wire"].send(message)
func send_state(id: String) -> void:
	peers[id]["wire"].send({"kind":"snapshot","data":data,"revision":revision,"id":id,"roster":roster,"history":history_flags,"resume_token":peers[id].get("token","")})
func receive_host(id: String,message: Dictionary) -> void:
	var peer: Dictionary=peers[id]; var kind: Variant=message.get("kind")
	if not peer["connected"]:
		if kind!="hello" or message.get("protocol")!=PROTOCOL or message.get("proof")!=proof(peer["nonce"],"join") or not message.get("name") is String or message["name"].strip_edges().is_empty() or message["name"].length()>32 or not valid_inventory(message.get("assets")):
			peer["wire"].send({"kind":"error","reason":"Session password, protocol, name or asset inventory was not accepted."}); peer["wire"].step(); remove_peer(id); return
		var token: String=message.get("resume_token","") if message.get("resume_token","") is String else ""
		if resume_tokens.has(token):
			var identity: String=resume_tokens[token]
			if peers.has(identity): peer["wire"].send({"kind":"error","reason":"That collaborator is still connected."}); peer["wire"].step(); remove_peer(id); return
			peers.erase(id); peers[identity]=peer; id=identity
		else:
			token=Crypto.new().generate_random_bytes(32).hex_encode(); resume_tokens[token]=id
		peer["token"]=token
		peer["assets"]=inventory(message["assets"]); peer["name"]=message["name"].replace("\n"," ").replace("\r"," "); peer["connected"]=true; peer["wire"].max_frame=Wire.MAX_FRAME
		var missing: String=missing_assets(data,peer["assets"])
		if not missing.is_empty(): peer["wire"].send({"kind":"error","reason":"Install the city's assets before joining: "+missing}); peer["wire"].step(); remove_peer(id); return
		roster[id]={"name":peer["name"],"cursor":{}}; send_state(id); presence_serial+=1; return
	if kind=="edit" and message.get("request") is String and message["request"].length()<=64: commit(id,message.get("delta"),message["request"])
	elif kind in ["undo","redo"] and message.get("request") is String and message["request"].length()<=64: undo_redo(id,kind=="redo",message["request"])
	elif kind=="resync": send_state(id)
	elif kind=="assets" and valid_inventory(message.get("assets")): peer["assets"]=inventory(message["assets"])
	elif kind=="cursor" and valid_cursor(message.get("cursor")): roster[id]["cursor"]=message["cursor"].duplicate(true)
func receive_client(message: Dictionary) -> void:
	var kind: Variant=message.get("kind")
	if kind=="error": close(str(message.get("reason","Host declined the connection."))); return
	if not connected:
		if kind=="challenge":
			if message.get("protocol")!=PROTOCOL or not message.get("nonce") is String or message["nonce"].length()>128 or message.get("proof")!=proof(message["nonce"],"host"): close("Host authentication failed. Check the session password."); return
			host_verified=true; upstream.send({"kind":"hello","protocol":PROTOCOL,"proof":proof(message["nonce"],"join"),"name":display_name,"assets":library.assets.keys(),"resume_token":resume_token if current_endpoint==resume_endpoint else ""}); return
		if kind!="snapshot": return
		if not host_verified: close("Host authentication is required before joining a city."); return
	if kind=="snapshot":
		if not valid_data(message.get("data")) or not message.get("id") is String or not integer(message.get("revision")) or not valid_roster(message.get("roster",{})) or not valid_hints(message.get("history",{})): close("Shared city validation failed. Local work was preserved; check required assets."); return
		resume_token=str(message.get("resume_token","")); resume_endpoint=current_endpoint
		data=message["data"].duplicate(true); revision=int(message["revision"]); local_id=message["id"]; roster=message.get("roster",{}); history_flags=message.get("history",{}); role="client"; connected=true; notice="Connected as "+display_name; event_serial+=1; presence_serial+=1
	elif kind=="change":
		if not valid_hints(message.get("history",{})): close("Invalid shared history metadata."); return
		if not integer(message.get("revision")) or int(message["revision"])!=revision+1: upstream.send({"kind":"resync"}); return
		var result: Dictionary=Merge.apply(data,message.get("delta"))
		if not result["ok"] or not valid_data(result["data"]): close("Invalid shared update. The last accepted city was preserved."); return
		data=result["data"]; revision=int(message["revision"]); history_flags=message.get("history",{})
		if message.get("actor")==local_id and message.get("request")==pending.get("request"): pending.clear(); notice="Shared edit committed."
		event_serial+=1
	elif kind in ["ack","reject"]:
		if message.get("request")==pending.get("request"):
			if kind=="reject": rejected_delta=pending.get("delta",{}).duplicate(true); rejected_view=pending.get("view",{}).duplicate(true); rejected_request=pending.get("request",""); notice=str(message.get("reason","Shared edit rejected."))
			else: notice="No shared change."
			pending.clear(); event_serial+=1
	elif kind=="presence" and valid_roster(message.get("roster")): roster=message["roster"].duplicate(true); presence_serial+=1
func submit(delta: Dictionary) -> bool:
	if not connected or not pending.is_empty(): return false
	sequence+=1; var request: String="edit_"+str(sequence); rejected_delta={}; rejected_view={}; rejected_request=""
	if role=="host": return commit("host",delta,request)
	var view: Dictionary=Merge.apply(data,delta,true,true)
	pending={"request":request,"delta":delta.duplicate(true),"view":view.get("data",data).duplicate(true)}; upstream.send({"kind":"edit","request":request,"delta":delta}); notice="Sending shared edit…"; event_serial+=1; return true
func reject(actor: String,request: String,reason: String,delta: Dictionary={}) -> bool:
	if actor=="host": rejected_delta=delta.duplicate(true); fail(reason)
	elif peers.has(actor): peers[actor]["wire"].send({"kind":"reject","request":request,"reason":reason})
	return false
func commit(actor: String,delta: Variant,request: String) -> bool:
	var result: Dictionary=Merge.apply(data,delta,true,actor!="host")
	if not result["ok"]: return reject(actor,request,result["reason"],delta if delta is Dictionary else {})
	var candidate: Dictionary=result["data"]
	if not valid_data(candidate): return reject(actor,request,"The proposed city is invalid or uses unavailable assets.",delta)
	var reason: String=Plan.allowed(data,candidate,actor,library)
	if not reason.is_empty(): return reject(actor,request,reason,delta)
	for mode in ["2d","3d"]:
		var previous_lots: Dictionary=Plan.index(data[mode].get("zones",[]))
		for lot in candidate[mode].get("zones",[]):
			if Zone.stage_rank(lot)<=Zone.stage_rank(previous_lots.get(lot["uid"],{})) or not lot.get("proposal") is Dictionary:continue
			var asset: String=lot["proposal"]["asset"]
			if not preload("res://scripts/builder/zone_candidates.gd").source_ready(library.assets[asset]["path"],true):return reject(actor,request,"Restore the selected building's prepared dependencies on the host before shared construction.",delta)
		var content: Dictionary=preload("res://scripts/builder/asset_palette_policy.gd").check_config(data[mode],candidate[mode],candidate.get("project_palette",{}),library)
		if not content["ok"]:return reject(actor,request,content["reason"],delta)
		var geometry_changed: bool=Economy.inventory(data[mode],library)!=Economy.inventory(candidate[mode],library)
		if actor!="host" or (geometry_changed and Economy.settings(data[mode])==Economy.settings(candidate[mode])):
			var quote: Dictionary=Economy.quote(data[mode],candidate[mode],library,Plan.complimentary_rooms(data[mode],candidate[mode],library))
			if not quote["ok"]: return reject(actor,request,quote["reason"],delta)
			if quote.get("enabled",false): candidate[mode]["economy_account"]=quote["account"]
	for peer in peers.values():
		if not peer["connected"]: continue
		var missing: String=missing_assets(candidate,peer["assets"])
		if not missing.is_empty(): return reject(actor,request,"Install matching assets for "+peer["name"]+" before construction: "+missing,delta)
	candidate=normalize(candidate)
	var actual: Dictionary=Delta.between(data,candidate)
	if actual["fields"].is_empty() and actual["collections"].is_empty():
		if actor!="host": peers[actor]["wire"].send({"kind":"ack","request":request})
		return true
	history.append({"actor":actor,"delta":actual.duplicate(true),"undone":false})
	if history.size()>100: history.pop_front()
	accept(candidate,actual,actor,request); return true
func accept(candidate: Dictionary,delta: Dictionary,actor: String,request: String) -> void:
	data=candidate; revision+=1; history_flags.clear()
	for entry in history:
		if not history_flags.has(entry["actor"]): history_flags[entry["actor"]]={"undo":false,"redo":false}
		history_flags[entry["actor"]]["redo" if entry["undone"] else "undo"]=true
	broadcast({"kind":"change","revision":revision,"delta":delta,"actor":actor,"request":request,"history":history_flags}); notice="Shared edit committed."; event_serial+=1
func request_undo(redo: bool=false) -> bool:
	if not connected or not pending.is_empty(): return false
	sequence+=1; var request: String="history_"+str(sequence)
	if role=="host": return undo_redo("host",redo,request)
	pending={"request":request}; upstream.send({"kind":"redo" if redo else "undo","request":request}); event_serial+=1; return true
func undo_redo(actor: String,redo: bool,request: String) -> bool:
	var order: Array=range(history.size()-1,-1,-1)
	# Redo reverses the actual Undo order for this author. Taking the newest
	# original edit first can restore a move while its purchased object is absent.
	if redo:order.sort_custom(func(a: int,b: int):return int(history[a].get("undo_order",0))>int(history[b].get("undo_order",0)))
	for i in order:
		var entry: Dictionary=history[i]
		if entry["actor"]!=actor or entry["undone"]!=redo: continue
		var result: Dictionary=Merge.apply(data,entry["delta"],redo)
		if not result["ok"]: return reject(actor,request,"Shared Undo/Redo conflicts with later changes, including treasury changes. "+result["reason"])
		var reason: String=Plan.allowed(data,result["data"],actor,library)
		if not reason.is_empty(): return reject(actor,request,reason)
		if not valid_data(result["data"]): return reject(actor,request,"That history step no longer produces a valid city.")
		entry["undone"]=not redo;history_sequence+=1;entry["undo_order"]=history_sequence if not redo else 0
		var actual: Dictionary=Delta.between(data,result["data"]); accept(result["data"],actual,actor,request); return true
	return reject(actor,request,"No matching shared history step is available.")
func overlay() -> Dictionary:
	if pending.has("delta"):
		var result: Dictionary=Merge.apply(data,pending["delta"],true,true)
		if result["ok"]: return result["data"]
	return data
func settle_economy(mode: String) -> bool:
	if role!="host" or not connected or not mode in ["2d","3d"]: return false
	var result: Dictionary=Economy.settle(data[mode],library)
	if not result["ok"]: fail(result["reason"]); return false
	var candidate: Dictionary=data.duplicate(true); candidate[mode]["economy_account"]=result["account"]; sequence+=1; return commit("host",Delta.between(data,candidate),"period_"+str(sequence))
func refresh_assets() -> void:
	if role=="client" and connected: upstream.send({"kind":"assets","assets":library.assets.keys()})
func integer(value: Variant) -> bool: return (value is int or value is float) and is_finite(float(value)) and value>=0 and float(value)==floorf(value)
func valid_inventory(value: Variant) -> bool:
	if not value is Array or value.size()>20000: return false
	for id in value:
		if not id is String or id.length()>512: return false
	return true
func inventory(ids: Array) -> Dictionary:
	var result: Dictionary={}
	for id in ids: result[id]=true
	return result
func missing_assets(source: Dictionary,available: Dictionary) -> String:
	for mode in ["2d","3d"]:
		for id in Plan.required_assets(source[mode],library):
			if not available.has(id): return str(library.assets.get(id,{}).get("name",id))+" · "+id
	return ""
func valid_cursor(value: Variant) -> bool:
	if not value is Dictionary or value.size()>4 or not value.get("mode") in ["2d","3d"] or not value.get("scope") is String or value["scope"].length()>256 or not value.get("point") is Array or value["point"].size()!=3: return false
	for number in value["point"]:
		if not (number is int or number is float) or not is_finite(float(number)) or absf(number)>1000000: return false
	return value.get("visible",true) is bool

func valid_roster(value: Variant) -> bool:
	if not value is Dictionary or value.size()>MAX_PEERS: return false
	for id in value:
		var member: Variant=value[id]
		if not id is String or id.is_empty() or id.length()>128 or not member is Dictionary or not member.get("name") is String or member["name"].length()>32 or not member.get("cursor") is Dictionary: return false
		if not member["cursor"].is_empty() and not valid_cursor(member["cursor"]): return false
	return true
func valid_hints(value: Variant) -> bool:
	if not value is Dictionary or value.size()>100: return false
	for id in value:
		if not id is String or not value[id] is Dictionary or not value[id].get("undo") is bool or not value[id].get("redo") is bool: return false
	return true
