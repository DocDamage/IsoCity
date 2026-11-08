extends SceneTree
const Plan=preload("res://scripts/builder/ambience_plan.gd")
const Bank=preload("res://scripts/builder/ambience_bank.gd")
var checks: int=0
var failures: int=0
var library: RefCounted
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func source(uid: String,kind: String,position: Vector3) -> Dictionary:
	var value: Dictionary=Plan.definitions()["kinds"][kind].duplicate(true); value["uid"]=uid; value["kind"]=kind; value["position"]=position; return value
func records(mode: String) -> void:
	var data: Dictionary=preload("res://scripts/builder/templates.gd").make(mode,"blank")
	var assets: Array=["2d:Fountain","2d:Tree_Oak","2d:Coffee_Shop"] if mode=="2d" else ["3d:HanX_Park/Fountain_Tiered","3d:HanX_Park/Tree_Oak","3d:HanX_City/Cafe_Small"]
	for index in assets.size(): data["objects"].append({"uid":str(index),"asset":assets[index],"direction":library.directions(assets[index])[0],"position":[index*10,0,0],"scale":1.0})
	var before: Dictionary=data.duplicate(true); var day: Array[Dictionary]=Plan.emitters(data,library,12,3,"upper:")
	check(day.size()==3 and day.map(func(item: Dictionary)->String:return item["kind"])==["fountain","birds","shop"],"Explicit asset/business profiles identify all localized exterior categories: "+mode)
	check(data==before and day.all(func(item: Dictionary)->bool:return item["uid"].begins_with("upper:") and item["position"].y>=3),"Emitter discovery preserves city data and floor identity: "+mode)
	var mixed: Dictionary=before.duplicate(true); var foreign: String="3d:HanX_City/Cafe_Small" if mode=="2d" else "2d:Coffee_Shop"
	mixed["objects"].append({"uid":"foreign_shop","asset":foreign,"direction":library.directions(foreign)[0],"position":[40,0,0],"scale":1.7,"angle":37})
	check(Plan.emitters(mixed,library).size()==4,"Data-only discovery supports shops from either source dimension: "+mode)
	for index in [2,3]:
		var item: Dictionary=mixed["objects"][index]; var node: Node=preload("res://scripts/builder/asset_instance.gd").make(library,item["asset"],mode); root.add_child(node); preload("res://scripts/builder/asset_instance.gd").pose(node,item)
		node.position=Vector2(item["position"][0],item["position"][1]) if mode=="2d" else Vector3(item["position"][0],item["position"][1],item["position"][2]); node.scale=Vector2.ONE*item["scale"] if mode=="2d" else Vector3.ONE*item["scale"]
		var anchor: Variant=preload("res://scripts/builder/entrance_anchors.gd").position_for(node,item,mode,library,false); var expected: Vector2=Plan.Traffic.metric([anchor.x,anchor.y,0],mode) if mode=="2d" else Vector2(anchor.x,anchor.z)
		var found: Dictionary=Plan.emitters(mixed,library,12,0,"",{item["uid"]:node}).filter(func(value: Dictionary)->bool:return value["uid"]==item["uid"])[0]
		check(Vector2(found["position"].x,found["position"].z).distance_to(expected)<.001,"Native and mixed shop audio follows its real transformed doorway: "+mode+"/"+item["asset"])
		node.free()
	check(Plan.emitters(data,library,2).size()==2,"Closed businesses do not emit shop ambience: "+mode)
	data["night"]=true; var night: Array[Dictionary]=Plan.emitters(data,library)
	check(is_equal_approx(night[1]["gain"],day[1]["gain"]*.12),"Night reduces bird activity without suppressing other categories: "+mode)
	data["objects"][0]["audio"]={"kind":"none"}; check(Plan.emitters(data,library).size()==2,"Objects can explicitly opt out of an automatic profile: "+mode)
	data["objects"][0]["audio"]={"kind":"interior","volume":.5,"range":12}; var custom: Array[Dictionary]=Plan.emitters(data,library)
	check(custom[0]["kind"]=="interior" and custom[0]["range"]==12 and is_equal_approx(custom[0]["gain"],Plan.definitions()["kinds"]["interior"]["gain"]*.5),"Per-object overrides choose sound type, level and distance: "+mode)
	data["objects"][0]["visible"]=false; check(Plan.emitters(data,library).size()==2,"Hidden source objects are silent: "+mode)
	Plan.Layers.set_state(data,Plan.Layers.layer(data["objects"][1],library),"visible",false); check(Plan.emitters(data,library).all(func(item: Dictionary)->bool:return item["kind"]!="birds"),"Hidden source layers are silent: "+mode)
	var room: Dictionary=preload("res://scripts/builder/interiors.gd").make(mode,"Room"); var bed: Dictionary=Plan.interior(room,6,"host:top:")
	check(bed["uid"]=="host:top:room_tone" and bed["kind"]=="interior" and bed["position"].y>=6 and bed["position"].y<7,"Interior beds belong to their actual floor context: "+mode)
	var lower: Dictionary=Plan.interior(room,0,"host:ground:")
	check(lower["uid"]!=bed["uid"] and is_equal_approx(bed["position"].y-lower["position"].y,6),"Repeated local room content retains separate vertical source positions: "+mode)
	room["terrain"]={"enabled":true,"bounds":[-8,-8,16,16]}; room["terrain_vertices"]=[]; room["water_cells"]=[]
	for x in range(-8,9):
		for z in range(-8,9): room["terrain_vertices"].append({"cell":[x,z],"height":3.0})
	var raised: Dictionary=Plan.interior(room,6,"host:top:")
	check(is_equal_approx(raised["position"].y,bed["position"].y+3),"Interior room tone follows its raised terrain landing: "+mode)
	for vertex in room["terrain_vertices"]: vertex["height"]=-4.0
	var lowered: Dictionary=Plan.interior(room,6,"host:top:")
	check(is_equal_approx(lowered["position"].y,bed["position"].y-4),"Interior room tone follows depressions while retaining the owning floor: "+mode)
func run() -> void:
	library=preload("res://scripts/builder/asset_library.gd").new()
	check(Plan.valid_settings({}) and Plan.valid_settings(Plan.defaults()),"Default and partial audio settings are valid")
	for pair in [["enabled",1],["preview_in_build",true],["volume",-1],["volume",INF],["volume",true],["range_scale",0],["range_scale",5],["birds",1.1]]:
		var value: Dictionary={pair[0]:pair[1]}; check(Plan.valid_settings(value)==(pair[0]=="preview_in_build"),"Audio setting validation: "+str(pair))
	for value in [false,[],{"kind":"unknown"},{"range":0},{"range":129},{"volume":3},{"enabled":0},{"volume":NAN}]: check(not Plan.valid_source(value),"Invalid emitter settings are rejected: "+str(value))
	check(Plan.valid_source({"kind":"auto","volume":2,"range":128}) and Plan.valid_source({"kind":"none"}),"Explicit profile limits and source opt-out are accepted")
	for asset in Plan.definitions()["assets"]: check(library.assets.has(asset),"Ambient asset metadata references installed content: "+asset)
	for kind in Plan.KINDS:
		var stream: AudioStreamWAV=Bank.stream(kind)
		check(stream!=null and stream.loop_mode==AudioStreamWAV.LOOP_FORWARD and stream.loop_end==176400 and is_equal_approx(stream.get_length(),8),"Every category has a real eight-second looping waveform: "+kind)
		check(stream.mix_rate==22050 and not stream.stereo and stream.format==AudioStreamWAV.FORMAT_16_BITS and stream.data.size()==352800,"Ambient source PCM format is portable and spatializable: "+kind)
		check(Bank.stream(kind)==stream and Bank.PATHS[kind]==Plan.definitions()["kinds"][kind]["stream"],"Streams are reused and explicit export dependency paths match catalog metadata: "+kind)
		var sum: float=0; var power: float=0; var peak: float=0; var bytes: PackedByteArray=stream.data
		for index in range(0,bytes.size(),2):
			var value: float=bytes.decode_s16(index)/32768.0; sum+=value; power+=value*value; peak=maxf(peak,absf(value))
		check(absf(sum/176400)<.0001 and sqrt(power/176400)>.01 and peak<.7,"Synthesized loops contain audible balanced signal without clipping or DC offset: "+kind)
	check(Bank.stream("unknown")==null,"Unknown sound types cannot load arbitrary paths")
	for mode in ["2d","3d"]: records(mode)
	var config: Dictionary=Plan.defaults(); var value: Dictionary=source("f","fountain",Vector3.ZERO); var previous: float=INF
	for distance in 31:
		var level: float=Plan.gain(value,Vector3(distance,0,0),config); check(level<=previous and level>=0,"Distance attenuation is bounded and monotonic: "+str(distance)); previous=level
	check(Plan.gain(value,Vector3(26,0,0),config)==0 and Plan.gain(value,Vector3.ZERO,config)>0,"Sources are silent at their range boundary and audible nearby")
	config["range_scale"]=4; check(Plan.gain(value,Vector3(40,0,0),config)>0,"Range controls alter actual audibility distance")
	config["range_scale"]=1; config["fountain"]=0; check(Plan.mix([value],Vector3.ZERO,config).is_empty(),"Category level zero mutes only that category")
	config=Plan.defaults(); config["enabled"]=false; check(Plan.mix([value],Vector3.ZERO,config).is_empty(),"Project audio disable selects no active voices")
	config=Plan.defaults(); value["range"]=1; check(Plan.gain(value,Vector3(1,0,0),config)==0,"Short custom ranges retain a correct distance cutoff")
	var dense: Array=[]
	for index in 100: dense.append(source("source_%03d"%index,"fountain",Vector3.ZERO))
	var mixed: Array[Dictionary]=Plan.mix(dense,Vector3.ZERO,config); var total: float=0; var power: float=0
	for emitter in mixed: total+=emitter["level"]; power+=emitter["level"]*emitter["level"]
	check(mixed.size()==Plan.MAX_VOICES and total<=1.250001 and power<=.562501,"Dense cities respect voice, aggregate amplitude and power budgets")
	check(mixed[0]["uid"]=="source_000" and mixed[-1]["uid"]=="source_023","Equal-priority source selection is stable across frames")
	check(Plan.mix(dense,Vector3.INF,config).is_empty(),"Invalid listener coordinates cannot poison the mixer")
	var sixty: float=0; var one_twenty: float=0
	for frame in 60: sixty=Plan.smooth(sixty,1,1.0/60)
	for frame in 120: one_twenty=Plan.smooth(one_twenty,1,1.0/120)
	check(absf(sixty-one_twenty)<1e-9 and sixty>.99 and sixty<1,"Audio fades are smooth and independent of frame rate")
	check(Plan.smooth(.5,1,NAN)==.5 and Plan.smooth(.5,1,-1)==.5,"Invalid elapsed time cannot create audio spikes")
	print("AMBIENCE PLAN: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
