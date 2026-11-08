extends SceneTree
const Delta=preload("res://scripts/builder/document_delta.gd")
const Document=preload("res://scripts/builder/document.gd")
const Floors=preload("res://scripts/builder/floor_plan.gd")
var checks: int=0
var failures: int=0
var library: RefCounted
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func room(mode: String,index: int) -> Dictionary:
	var value: Dictionary=preload("res://scripts/builder/interiors.gd").make(mode,"Floor "+str(index)); value["objects"]=[]; value["tiles"]=[]; value["roads"]=[]
	value["extension"]={"sentinel":"floor_sentinel_"+str(index),"nested":{"retain":[1,2,3]}}
	value["objects"].append({"uid":"door","asset":"2d:Door_White","direction":library.directions("2d:Door_White")[0],"position":[0,0,0],"scale":1.0,"open":false})
	for number in 300: value["objects"].append({"uid":"sofa_"+str(number),"asset":"2d:Sofa_Teal","direction":library.directions("2d:Sofa_Teal")[0],"position":[number%20,(number/20)*2,0],"scale":1.0,"extension":{"unchanged":"sentinel_"+str(number)}})
	return value
func dense(mode: String) -> Dictionary:
	var root: Dictionary=room(mode,0); root["floors"]=[]; root["floor_links"]=[]; root["floor_entrances"]=[]
	for index in range(1,8):
		var content: Dictionary=room(mode,index)
		if index==7:
			content["terrain"]={"enabled":true,"bounds":[0,0,128,128]}; content["terrain_vertices"]=[]; content["water_cells"]=[]
			for x in 129:
				for z in 129: content["terrain_vertices"].append({"cell":[x,z],"height":0.0})
		root["floors"].append({"uid":"floor_"+str(index),"name":"Floor "+str(index),"height":index*3,"room":content,"extension":{"retain":index}})
		root["floor_links"].append({"uid":"stairs_"+str(index),"kind":"stairs","lower":"ground" if index==1 else "floor_"+str(index-1),"upper":"floor_"+str(index),"start":[0,0],"end":[5,0],"width":1.2})
	root["floor_entrances"].append({"uid":"top","floor":"floor_7","position":[12,21,12],"extension":{"retain":true}})
	return root
func dense_history(mode: String) -> void:
	var data: Dictionary=dense(mode)
	check(Document.valid(data,mode,library) and data["floors"].size()+1==Floors.MAX_FLOORS and data["floors"][-1]["room"]["terrain_vertices"].size()==16641,"The dense history fixture reaches the floor and terrain-vertex limits: "+mode)
	var doc=preload("res://scripts/builder/floor_document.gd").new(); doc.configure(data); doc.switch_floor("floor_7")
	var before: Dictionary=doc.canonical.data.duplicate(true)
	doc.checkpoint(); doc.object("door")["open"]=true; doc.finish_checkpoint()
	var bytes: int=var_to_bytes(doc.undo_history.back()).size()
	check(bytes<2048,"An upstairs door edit stores bounded data despite dense unchanged rooms: "+mode)
	check(not JSON.stringify(doc.undo_history.back()).contains("terrain_vertices") and not JSON.stringify(doc.undo_history.back()).contains("sofa_299"),"A door delta omits unchanged terrain and furniture: "+mode)
	check(doc.undo() and doc.canonical.data==before,"Dense upstairs Undo restores exact content: "+mode)
	check(doc.redo() and doc.object("door")["open"],"Dense upstairs Redo restores the edited door: "+mode)
	var terrain_before: Dictionary=doc.canonical.data.duplicate(true)
	doc.checkpoint(); doc.data["terrain_vertices"][8232]["height"]=.25; doc.finish_checkpoint()
	check(var_to_bytes(doc.undo_history.back()).size()<2048,"A one-vertex terrain edit omits the other 16,640 vertices: "+mode)
	check(doc.undo() and doc.canonical.data==terrain_before,"Nested terrain Undo preserves every floor and extension: "+mode)
	check(doc.redo() and doc.data["terrain_vertices"][8232]["height"]==.25,"Nested terrain Redo restores the one sculpted vertex: "+mode)
	var renamed: Dictionary=doc.canonical.data["floors"][-1].duplicate(true); renamed["name"]="Roof garden"; renamed["height"]=21.5
	doc.replace_plan(Floors.put_floor(doc.canonical.data,renamed)["data"],"floor_7")
	check(var_to_bytes(doc.undo_history.back()).size()<2048,"Renaming or raising a floor does not copy its room: "+mode)
	check(doc.undo() and doc.canonical.data["floors"][-1]["height"]==21,"Floor metadata Undo retains its independent contents: "+mode)
	check(doc.redo() and doc.canonical.data["floors"][-1]["name"]=="Roof garden","Floor metadata Redo retains the room's identity: "+mode)
	var complete: Dictionary=doc.canonical.data.duplicate(true); var deleted_size: int=JSON.stringify(complete["floors"][-1]).length()
	doc.replace_plan(Floors.remove_floor(doc.canonical.data,"floor_7")["data"],"ground")
	check(JSON.stringify(doc.undo_history.back()).length()<deleted_size+4096 and not JSON.stringify(doc.undo_history.back()).contains("floor_sentinel_6"),"Removing a dense floor retains that floor and its references, not unaffected rooms: "+mode)
	check(doc.undo() and doc.canonical.data==complete,"Removal Undo restores all dense contents, links and entrances: "+mode)
	check(doc.redo() and Floors.room(doc.canonical.data,"floor_7").is_empty(),"Removal Redo deletes the same floor: "+mode)
	doc.undo(); var redo: Array=doc.redo_history.duplicate(true); var count: int=doc.undo_history.size(); doc.checkpoint(); doc.finish_checkpoint()
	check(doc.undo_history.size()==count and doc.redo_history==redo,"A no-op nested checkpoint preserves history and its redo branch: "+mode)
	doc.switch_floor("floor_7"); var baseline: Dictionary=doc.canonical.data.duplicate(true); var total: int=0
	for index in 20:
		doc.checkpoint(); doc.object("door")["open"]=not doc.object("door")["open"]; doc.finish_checkpoint(); total+=var_to_bytes(doc.undo_history.back()).size()
	check(total<40960,"Twenty dense-room edits retain less than 40 KB of completed changes: "+mode)
	for index in 20: doc.undo()
	check(doc.canonical.data==baseline,"Repeated nested Undo returns the full dense project exactly: "+mode)
	for index in 20: doc.redo()
	check(doc.canonical.data==baseline,"Repeated nested Redo returns the same even-toggle state: "+mode)
	var city=Document.new(); city.data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
	city.data["objects"]=[{"uid":"building","asset":"2d:House_Blue","direction":library.directions("2d:House_Blue")[0],"position":[0,0,0],"scale":1.0,"interior":doc.canonical.data.duplicate(true)}]
	check(Document.valid(city.data,mode,library),"A dense multi-floor building is valid city content: "+mode)
	var original_city: Dictionary=city.data.duplicate(true)
	city.checkpoint(); city.object("building")["position"][0]=2; city.finish_checkpoint()
	check(var_to_bytes(city.undo_history.back()).size()<2048,"Moving a building omits its unchanged owned rooms: "+mode)
	check(city.undo() and city.data==original_city and city.redo(),"City transform history restores exact dense owned content: "+mode)
	var exterior_before: Dictionary=city.data.duplicate(true)
	city.checkpoint(); Floors.room(city.object("building")["interior"],"floor_7")["objects"][0]["name"]="Entry from city"; city.finish_checkpoint()
	check(var_to_bytes(city.undo_history.back()).size()<4096,"A city-level interior visit stores nested changes instead of the whole building: "+mode)
	check(city.undo() and city.data==exterior_before and city.redo(),"Nested city-level Undo and Redo preserve all other floors: "+mode)
	check(Document.valid(city.data,mode,library),"Nested history retains valid max-floor project data: "+mode)
	print("Nested history ",mode,": door ",bytes," bytes; 20 edits ",total," bytes; city edit ",var_to_bytes(city.undo_history.back()).size()," bytes")
func mixed() -> void:
	# Dictionary recursion must still preserve field presence and replacement types.
	var transitions: Array=[
		[{}, {"extension":{"value":1}}],
		[{"extension":{"value":1}}, {}],
		[{"extension":{"value":1}}, {"extension":null}],
		[{"extension":null}, {"extension":{"value":1}}],
		[{"extension":{"value":1}}, {"extension":[1,2]}],
		[{"objects":[{"uid":"same","value":1},{"uid":"same","value":2}]},{"objects":[{"uid":"same","value":3}]}],
		[{"objects":[{"uid":"a","value":1},{"uid":"b","value":2},{"uid":"c","value":3}]},{"objects":[{"uid":"c","value":4},{"uid":"new","value":5},{"uid":"a","value":6}]}]
	]
	for pair in transitions:
		var restored: Dictionary=pair[0].duplicate(true); var delta: Dictionary=Delta.between(pair[0],pair[1])
		Delta.apply(restored,delta,true); check(restored==pair[1],"Type replacement, fallback and combined collection changes apply exactly")
		Delta.apply(restored,delta,false); check(restored==pair[0],"Type replacement, fallback and combined collection changes reverse exactly")
	var rng:=RandomNumberGenerator.new(); rng.seed=19311
	var value: Dictionary={"objects":[{"uid":"host","interior":{"objects":[{"uid":"keep","value":0}],"tiles":[],"floors":[{"uid":"f","room":{"objects":[{"uid":"child","value":0}],"tiles":[]}}]}}],"tiles":[],"extension":{"nested":{"keep":[1,2,3]}}}
	for step in 72:
		var before: Dictionary=value.duplicate(true); var interior: Dictionary=value["objects"][0]["interior"]; var objects: Array=interior["objects"]
		match step%8:
			0: objects[rng.randi_range(0,objects.size()-1)]["value"]=step
			1: objects.insert(rng.randi_range(0,objects.size()),{"uid":"added_"+str(step),"value":step})
			2: if objects.size()>1: objects.remove_at(rng.randi_range(0,objects.size()-1))
			3: objects.reverse()
			4: interior["floors"][0]["room"]["objects"][0]["value"]=step
			5: value["extension"]["nested"]["field"]=step
			6: value["extension"]["nested"].erase("field")
			7: interior["tiles"].append({"cell":[step,-step],"asset":"tile"})
		var after: Dictionary=value.duplicate(true); var delta: Dictionary=Delta.between(before,after); var restored: Dictionary=before.duplicate(true)
		Delta.apply(restored,bytes_to_var(var_to_bytes(delta)),true); check(restored==after,"Mixed nested add/remove/order/field forward: "+str(step))
		Delta.apply(restored,delta,false); check(restored==before,"Mixed nested add/remove/order/field reverse: "+str(step))
	var before: Dictionary={"objects":[{"uid":"a","metadata":{"edited":1,"keep":{"external":false}}}],"tiles":[]}; var after: Dictionary=before.duplicate(true); after["objects"][0]["metadata"]["edited"]=2
	var delta: Dictionary=Delta.between(before,after); var target: Dictionary=before.duplicate(true); target["objects"][0]["metadata"]["keep"]["external"]=true
	Delta.apply(target,delta,true); check(target["objects"][0]["metadata"]["edited"]==2 and target["objects"][0]["metadata"]["keep"]["external"],"Applying a nested change preserves unrelated current metadata")
	Delta.apply(target,delta,false); check(target["objects"][0]["metadata"]["edited"]==1 and target["objects"][0]["metadata"]["keep"]["external"],"Reversing a nested change preserves unrelated current metadata")
	var legacy: Dictionary={"fields":{},"collections":{"objects":{"identity":"uid","changes":[{"key":"a","before":{"index":0,"value":{"uid":"a","value":1}},"after":{"index":0,"value":{"uid":"a","value":2}}}]}}}
	var old: Dictionary={"objects":[{"uid":"a","value":1}]}; Delta.apply(old,legacy,true); check(old["objects"][0]["value"]==2,"Previously constructed full-record deltas still apply"); Delta.apply(old,legacy,false); check(old["objects"][0]["value"]==1,"Previously constructed full-record deltas still reverse")
	var long_doc=Document.new(); long_doc.data={"objects":[{"uid":"host","interior":{"objects":[{"uid":"a","value":0}]}}]}
	for index in 320:
		long_doc.checkpoint(); long_doc.data["objects"][0]["interior"]["objects"][0]["value"]=index+1; long_doc.finish_checkpoint()
	check(long_doc.undo_history.size()==Document.HISTORY_LIMIT and var_to_bytes(long_doc.undo_history).size()<512000,"Long nested histories respect the existing retention limit with bounded payloads")
	for index in Document.HISTORY_LIMIT: long_doc.undo()
	check(long_doc.data["objects"][0]["interior"]["objects"][0]["value"]==20,"Pruned nested history reverses to the oldest retained state")
	for index in Document.HISTORY_LIMIT: long_doc.redo()
	check(long_doc.data["objects"][0]["interior"]["objects"][0]["value"]==320,"Every retained nested change can be redone")
func run() -> void:
	library=preload("res://scripts/builder/asset_library.gd").new()
	for mode in ["2d","3d"]: dense_history(mode)
	mixed(); print("FLOOR NESTED HISTORY: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
