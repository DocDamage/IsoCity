extends SceneTree
const Plan=preload("res://scripts/builder/floor_plan.gd")
const Doc=preload("res://scripts/builder/document.gd")
const Economy=preload("res://scripts/builder/economy_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func same_serialized(a: Variant,b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return absf(float(a)-float(b))<1e-9
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for index in a.size():
			if not same_serialized(a[index],b[index]): return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not same_serialized(a[key],b[key]): return false
		return true
	return a==b
func blank(mode: String) -> Dictionary:
	return {"title":"Owned room","mode":mode,"objects":[],"tiles":[],"night":false,"interior_room":true,"exit":[0,0,0]}
func floor_value(mode: String, uid: String="upper", height: float=3) -> Dictionary:
	return {"uid":uid,"name":"Upper floor","height":height,"room":blank(mode),"extension":{"retain":true}}
func link(kind: String="stairs") -> Dictionary:
	return {"uid":"connection","kind":kind,"lower":"ground","upper":"upper","start":[0,0],"end":[0,5] if kind=="stairs" else [0,0],"width":1.2,"extension":"retain"}
func run() -> void:
	var library=preload("res://scripts/builder/asset_library.gd").new()
	for mode in ["2d","3d"]:
		var base: Dictionary=blank(mode); var source: Dictionary=base.duplicate(true)
		check(Plan.valid(base) and Doc.valid(base,mode,library),"Legacy single room validates: "+mode)
		var added: Dictionary=Plan.put_floor(base,floor_value(mode))
		check(added["ok"] and base==source,"Adding a floor leaves the source room intact: "+mode)
		var data: Dictionary=added["data"]
		check(Plan.room(data,"upper")==floor_value(mode)["room"] and Plan.room(data,"unknown").is_empty(),"Floor lookup uses stable IDs: "+mode)
		check(Doc.valid(data,mode,library),"Additional rooms pass recursive document validation: "+mode)
		for value in [null,{},true,"upper",[{}]]:
			var bad: Dictionary=data.duplicate(true); bad["floors"]=value
			check(not Plan.valid(bad),"Reject malformed floor collection: "+mode+str(value))
		for value in [null,true,"3",INF,NAN,0,1,-1,-25,33]:
			var bad: Dictionary=floor_value(mode); bad["height"]=value
			check(not Plan.put_floor(base,bad)["ok"],"Reject invalid floor elevation: "+mode+str(value))
		for value in [null,true,"","ground","a/b","has space","x".repeat(65)]:
			var bad: Dictionary=floor_value(mode); bad["uid"]=value
			check(not Plan.put_floor(base,bad)["ok"],"Reject invalid floor identity: "+mode+str(value))
		for value in [null,true,"","   ","x".repeat(81)]:
			var bad: Dictionary=floor_value(mode); bad["name"]=value
			check(not Plan.put_floor(base,bad)["ok"],"Reject unreadable floor name: "+mode+str(value))
		check(not Plan.put_floor(data,floor_value(mode,"crowded",4))["ok"],"Floor separation prevents overlapping storeys: "+mode)
		var basement: Dictionary=Plan.put_floor(data,floor_value(mode,"basement",-3))["data"]
		check(Plan.definitions(basement).map(func(value: Dictionary):return value["uid"])==["basement","ground","upper"],"Floor presentation sorts basement, ground, and upper levels: "+mode)
		data=Plan.put_record(data,"floor_links",link())["data"]
		check(Plan.valid(data) and data["floor_links"][0]["extension"]=="retain","Supported stairs retain extension metadata: "+mode)
		for patch in [{"upper":"missing"},{"lower":"upper"},{"width":true},{"width":0.7},{"width":4.1},{"start":[0,INF]},{"end":[0,1]},{"end":[0,33]},{"kind":"ladder"}]:
			var bad: Dictionary=link(); bad.merge(patch,true)
			check(not Plan.put_record(data,"floor_links",bad)["ok"],"Reject unsafe or dangling connection: "+mode+str(patch))
		var tower: Dictionary=Plan.put_floor(data,floor_value(mode,"roof",9))["data"]
		var skipped: Dictionary=link(); skipped["upper"]="roof"; skipped["end"]=[0,15]
		check(not Plan.put_record(tower,"floor_links",skipped)["ok"],"Stairs cannot skip intermediate levels: "+mode)
		var lift: Dictionary=link("elevator"); lift["uid"]="lift"; lift["upper"]="roof"
		check(Plan.put_record(tower,"floor_links",lift)["ok"],"Elevators can connect distant storeys: "+mode)
		lift["end"]=[1,0]
		check(not Plan.put_record(tower,"floor_links",lift)["ok"],"Elevator landings share one vertical shaft: "+mode)
		var entry: Dictionary={"uid":"balcony","floor":"upper","position":[2,3,4],"view":"NE","extension":"retain"}
		data=Plan.put_record(data,"floor_entrances",entry)["data"]
		check(Doc.valid(data,mode,library),"Floor-specific exterior entrances validate: "+mode)
		for patch in [{"floor":"missing"},{"position":[0,0]},{"position":[0,true,0]},{"position":[0,INF,0]},{"view":"wrong"}]:
			var bad: Dictionary=entry.duplicate(true); bad.merge(patch,true)
			check(not Plan.put_record(data,"floor_entrances",bad)["ok"],"Reject invalid exterior entrance: "+mode+str(patch))
		var removed: Dictionary=Plan.remove_floor(data,"upper")
		check(removed["ok"] and removed["data"]["floor_links"].is_empty() and removed["data"]["floor_entrances"].is_empty(),"Deleting a floor removes its links and entrances atomically: "+mode)
		check(not Plan.remove_floor(data,"ground")["ok"] and not Plan.remove_floor(data,"missing")["ok"],"The original ground room cannot be deleted: "+mode)
		var doc=Doc.new(); doc.data=data.duplicate(true); doc.checkpoint(); doc.data=removed["data"]; doc.finish_checkpoint(); doc.undo()
		check(doc.data==data,"Undo restores the complete removed floor and references: "+mode)
		doc.redo(); check(doc.data==removed["data"],"Redo repeats the atomic removal: "+mode)
		var normalized: Dictionary=Doc.normalize(JSON.parse_string(JSON.stringify(data)))
		check(Doc.valid(normalized,mode,library) and Plan.valid(normalized),"Floors survive JSON and normalization: "+mode)
		var invalid_room: Dictionary=data.duplicate(true); invalid_room["floors"][0]["room"]["objects"]="broken"
		check(not Doc.valid(invalid_room,mode,library),"Nested rooms receive full schema validation: "+mode)
		var nested: Dictionary=data.duplicate(true); nested["floors"][0]["room"]["floors"]=[]
		check(not Doc.valid(nested,mode,library),"Additional rooms cannot hold another floor tree: "+mode)
		var repair=preload("res://scripts/builder/project_repair.gd").new(library)
		check(repair.world(data,mode,"room",1)==data and repair.issues.is_empty(),"Valid floors pass recovery unchanged: "+mode)
		var broken: Dictionary=data.duplicate(true)
		broken["floors"].append(floor_value(mode,"crowded",4)); broken["floors"].append(null)
		broken["floor_links"].append({"uid":"dangling","kind":"stairs","upper":"missing"})
		broken["floor_entrances"].append({"uid":"dangling","floor":"missing"})
		var broken_source: Dictionary=broken.duplicate(true); var repaired: Dictionary=repair.world(broken,mode,"room",1)
		check(Doc.valid(repaired,mode,library) and repaired==data and broken==broken_source,"Recovery retains valid floors, links, entrances and all extensions without changing source: "+mode)
		check(repair.issues.size()==4 and repair.issues.filter(func(issue: Dictionary):return issue.has("original")).size()==3,"Damaged records have archived source evidence and null records have a precise location: "+mode)
		var with_asset: Dictionary=data.duplicate(true)
		with_asset["floors"][0]["room"]["objects"].append({"uid":"furniture","asset":"2d:House_Blue","direction":"SE","position":[0,0,0],"scale":1.0})
		var inventory: Dictionary=Economy.inventory(with_asset,library)
		check(inventory.has(JSON.stringify(["floor","upper","room","object","furniture"])) and inventory.values()[0]["income"]==0,"Upper floor contents incur construction cost without exterior income: "+mode)
		var exporter=preload("res://scripts/builder/portable_export.gd").new(); exporter.library=library
		exporter.paths.compile('["\'](res://[^"\'\\r\\n]+)["\']')
		exporter.collect_document(with_asset)
		check(exporter.assets.has("2d:House_Blue") and exporter.errors.is_empty(),"Portable dependency collection includes assets used only upstairs: "+mode)
		var city: Dictionary=blank(mode); city.erase("interior_room"); city["floors"]=[]
		check(not Doc.valid(city,mode,library),"City roots cannot accidentally become multi-floor interiors: "+mode)
		var repeated: Dictionary=data.duplicate(true); repeated["floors"].append(repeated["floors"][0].duplicate(true))
		check(not Plan.valid(repeated),"Duplicate floor IDs cannot alias rooms: "+mode)
		for field in ["floor_links","floor_entrances"]:
			var duplicate: Dictionary=data.duplicate(true); duplicate[field].append(duplicate[field][0].duplicate(true))
			check(not Plan.valid(duplicate),"Duplicate connection and entrance IDs are rejected: "+mode+field)
			var malformed: Dictionary=data.duplicate(true); malformed[field]={}
			check(not Plan.valid(malformed),"Connections and entrances require collections: "+mode+field)
		var full: Dictionary=base.duplicate(true)
		for index in 7: full=Plan.put_floor(full,floor_value(mode,"f"+str(index),3.0*(index+1)))["data"]
		check(Plan.valid(full) and Plan.definitions(full).size()==8 and not Plan.put_floor(full,floor_value(mode,"too_many",24))["ok"],"Eight total floors bound room/rendering complexity: "+mode)
		for field in ["floor_links","floor_entrances"]:
			var bounded: Dictionary=data.duplicate(true); bounded[field]=[]
			for index in (Plan.MAX_LINKS if field=="floor_links" else Plan.MAX_ENTRANCES):
				var record: Dictionary=link() if field=="floor_links" else entry.duplicate(true); record["uid"]="r"+str(index)
				bounded=Plan.put_record(bounded,field,record)["data"]
			var overflow: Dictionary=link() if field=="floor_links" else entry.duplicate(true); overflow["uid"]="overflow"
			check(Plan.valid(bounded) and not Plan.put_record(bounded,field,overflow)["ok"],"Connection/entrance count has a strict bound: "+mode+field)
		var deep: Dictionary=data.duplicate(true)
		check(not Doc.valid(deep,mode,library,4),"Additional floors obey the existing recursive room depth limit: "+mode)
		var depth_repair=preload("res://scripts/builder/project_repair.gd").new(library)
		var shallow: Dictionary=depth_repair.world(deep,mode,"room",4)
		check(Doc.valid(shallow,mode,library,4) and shallow["floors"].is_empty() and shallow["floor_links"].is_empty(),"Recovery bounds nesting and removes newly dangling references: "+mode)
		var damaged_room: Dictionary=data.duplicate(true); damaged_room["floors"][0]["room"]["objects"]="broken"
		var restored: Dictionary=depth_repair.world(damaged_room,mode,"room",1)
		check(Doc.valid(restored,mode,library) and restored["floors"][0]["extension"]=={"retain":true},"A damaged room collection is repaired without losing the floor descriptor: "+mode)
		var before: Dictionary=data.duplicate(true); before["economy"]={"enabled":true,"starting_cash":5000}
		before["economy_account"]=Economy.fresh_account(before,library)
		var after: Dictionary=with_asset.duplicate(true); after["economy"]=before["economy"].duplicate(true); after["economy_account"]=before["economy_account"].duplicate(true)
		var quoted: Dictionary=Economy.quote(before,after,library)
		check(quoted["ok"] and quoted["construction"]==Economy.profile("2d:House_Blue",library)["construction"],"Actual construction quote charges for an asset placed upstairs: "+mode)
		after["economy_account"]=quoted["account"]
		var demolition: Dictionary=Plan.remove_floor(after,"upper")["data"]
		var refund: Dictionary=Economy.quote(after,demolition,library)
		check(refund["ok"] and refund["refund"]>0 and refund["construction"]==0,"Removing a floor refunds its paid contents through normal treasury rules: "+mode)
		var outer: Dictionary=blank(mode); outer.erase("interior_room")
		outer["objects"]=[{"uid":"building","asset":"2d:House_Blue","direction":"SE","position":[0,0,0],"scale":1.0,"interior":with_asset.duplicate(true)}]
		check(Doc.valid(outer,mode,library),"A building can own separate furnished floor rooms: "+mode)
		var docs: Dictionary={"2d":blank("2d"),"3d":blank("3d")}; docs[mode]=outer
		var saved: Dictionary={"version":1,"active_mode":mode,"documents":docs}
		var path: String="user://floor_plan_roundtrip_"+mode+".isocity.json"
		check(preload("res://scripts/builder/project_store.gd").write_json(path,saved),"Owned multi-floor building is written through the project store: "+mode)
		var loader=preload("res://scripts/builder/project_repair.gd").new(library)
		var reopened: Dictionary=loader.read(path)
		check(reopened["ok"] and loader.issues.is_empty() and same_serialized(reopened["content"]["documents"][mode]["objects"][0]["interior"],with_asset),"Project loader reopens every floor, connection, entrance, and upstairs asset without repair: "+mode)
		var damaged_city: Dictionary=outer.duplicate(true)
		damaged_city["objects"][0]["interior"]["floors"][0]["room"]["objects"][0]["asset"]="missing:upstairs"
		var fixed_city: Dictionary=loader.world(damaged_city,mode,"city",0)
		var placeholder: Dictionary=fixed_city["objects"][0]["interior"]["floors"][0]["room"]["objects"][0]
		check(Doc.valid(fixed_city,mode,library) and placeholder["missing_asset"]["id"]=="missing:upstairs" and placeholder["uid"]=="furniture","Missing assets upstairs become editable placeholders within the original owned room: "+mode)
	print("FLOOR PLAN: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
