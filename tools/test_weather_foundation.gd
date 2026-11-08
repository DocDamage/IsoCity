extends SceneTree
const Plan=preload("res://scripts/builder/weather_plan.gd")
const Doc=preload("res://scripts/builder/document.gd")
var checks: int=0
var failures: int=0
var library: RefCounted
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func schema() -> void:
	check(Plan.valid_settings({}) and not Plan.settings({})["enabled"],"Legacy cities retain their original clear appearance and activities")
	for field in Plan.defaults(): check(Plan.valid_settings({field:Plan.defaults()[field]}),"Default weather field validates: "+field)
	for raw in [null,[],"rain",{"enabled":1},{"condition":"storm"},{"season":"fall"},{"intensity":-1},{"intensity":1.1},{"wind":NAN},{"wind":INF},{"wind_direction":361},{"seed":.5},{"seed":-1},{"season_seconds":29},{"foliage":0},{"affect_activity":"yes"},{"cycle_seasons":1}]: check(not Plan.valid_settings(raw),"Malformed weather settings rejected: "+str(raw))
	var data: Dictionary={"weather":{"enabled":true,"condition":"rain","season":"autumn","intensity":.8,"wind":.6,"wind_direction":90,"cycle_seasons":true,"season_seconds":30}}
	var before: Dictionary=data.duplicate(true); var state: Dictionary=Plan.state(data)
	check(state["rain"]==.8 and state["snow"]==0 and state["effective_season"]=="autumn","Rain and selected season resolve independently")
	check(state["wind_vector"].is_equal_approx(Vector2(0,.6)),"Authored world wind direction is retained")
	for elapsed in [0,29.9,30,60,90,120]:
		check(Plan.state(data,elapsed)["effective_season"]==Plan.SEASONS[posmod(2+floori(elapsed/30),4)],"Season cycle crosses boundaries and wraps: "+str(elapsed))
	check(Plan.state(data,-1)["effective_season"]=="autumn" and Plan.state(data,NAN)["effective_season"]=="autumn","Invalid elapsed times cannot corrupt season state")
	check(data==before,"State resolution does not change authored settings")
	var resident: Dictionary={"home":"home","work":"work","shop":"shop","park":"park","offset":0}
	check(Plan.target(resident,18,state)=="park" and state["walking_speed"]==1,"Weather activity effects are opt-in")
	data["weather"]["affect_activity"]=true; state=Plan.state(data)
	check(Plan.target(resident,18,state)=="home" and state["walking_speed"]<1,"Optional heavy weather sends park visitors home and slows walking")
	check(Plan.target(resident,10,state)=="work" and Plan.target(resident,19,state)=="shop","Weather preserves work and shop routines")
	data["weather"]["enabled"]=false; state=Plan.state(data)
	check(Plan.target(resident,18,state)=="park" and state["walking_speed"]==1 and state["wind_vector"]==Vector2.ZERO,"Disabling weather restores all activity and wind defaults")
	for mode in ["2d","3d"]:
		var city: Dictionary=preload("res://scripts/builder/templates.gd").make(mode,"blank"); city["weather"]={"enabled":true,"condition":"snow","season":"winter","seed":719}
		check(Doc.valid(city,mode,library),"City schema accepts saved weather: "+mode)
		var doc=Doc.new(); doc.data=city; var original: Dictionary=city.duplicate(true); city["weather"]["intensity"]=.9
		check(doc.record_completed_change(original) and doc.undo() and doc.data==original and doc.redo() and doc.data["weather"]["intensity"]==.9,"Weather settings share normal Undo / Redo history: "+mode)
		var saved: Dictionary=JSON.parse_string(JSON.stringify(doc.data)); check(Doc.valid(saved,mode,library) and saved["weather"]["seed"]==719,"Weather roundtrips through saved JSON: "+mode)
		saved["weather"]={"enabled":true,"condition":"rain","season":"wrong","intensity":-2,"wind":.8,"future_setting":"retained"}
		check(not Doc.valid(saved,mode,library),"Invalid saved weather fails normal validation: "+mode)
		var repair=preload("res://scripts/builder/project_repair.gd").new(library)
		var fixed: Dictionary=repair.world(saved,mode,"weather-test",0)
		check(Doc.valid(fixed,mode,library) and fixed["weather"]["enabled"] and fixed["weather"]["condition"]=="rain" and fixed["weather"]["wind"]==.8 and fixed["weather"]["future_setting"]=="retained" and fixed["weather"]["season"]=="summer","Repair retains valid and future settings: "+mode)
		check(not repair.issues.is_empty() and repair.issues[0].get("original",{})==saved["weather"],"Repair archives original weather values: "+mode)
func palette() -> void:
	for id in Plan.catalog.get("foliage",{}): check(library.assets.has(id),"Explicit foliage profile exists in indexed library: "+id)
	var bark:=Color(.4,.25,.12); var leaf:=Color(.2,.65,.15)
	for season in Plan.SEASONS:
		check(Plan.seasonal_color(bark,season,"deciduous")==bark,"Season preserves brown trunk pixels: "+season)
		check(is_equal_approx(Plan.seasonal_color(Color(.2,.65,.15,.4),season,"deciduous").a,.4),"Season preserves foliage alpha: "+season)
	check(Plan.seasonal_color(leaf,"summer","deciduous")==leaf,"Summer retains authored foliage")
	check(Plan.seasonal_color(leaf,"autumn","deciduous")!=leaf and Plan.seasonal_color(leaf,"autumn","evergreen")==leaf,"Autumn changes deciduous leaves and preserves evergreens")
	check(Plan.seasonal_color(leaf,"winter","evergreen")!=leaf,"Winter adds a frosted foliage appearance")
	var blossom:=Color(.9,.35,.7)
	check(Plan.seasonal_color(blossom,"spring","blossom")==blossom and Plan.seasonal_color(blossom,"summer","blossom").g>blossom.g,"Cherry blossoms bloom in spring and leaf out during summer")
	check(Plan.seasonal_color(blossom,"autumn","blossom")!=blossom and Plan.seasonal_color(blossom,"winter","blossom")!=blossom,"Cherry foliage also responds to autumn and winter")
	check(Plan.foliage("2d:Tree_Oak")=="deciduous" and Plan.foliage("2d:Coffee_Shop")=="","Foliage classification is explicit rather than inferred from names")
func visuals(mode: String,asset: String) -> void:
	var data: Dictionary=preload("res://scripts/builder/templates.gd").make(mode,"blank")
	data["weather"]={"enabled":true,"season":"autumn","condition":"rain","intensity":.8,"wind":1.0,"seed":123}
	var item: Dictionary={"uid":"oak","asset":asset,"position":[0,0,0],"scale":1.0,"direction":library.directions(asset)[0]}; data["objects"]=[item]
	var tree: Node=preload("res://scripts/builder/asset_instance.gd").make(library,asset,mode); root.add_child(tree); preload("res://scripts/builder/asset_instance.gd").pose(tree,item)
	var transform: Variant=tree.transform; var nodes: Array=[]; var helper=preload("res://scripts/builder/weather_foliage.gd").new(); helper.visuals(tree,nodes)
	var runtime=preload("res://scripts/builder/weather_runtime.gd").new(); root.add_child(runtime); var before: Dictionary=data.duplicate(true)
	runtime.step(.1,data,{"oak":tree}); var state: Dictionary=runtime.current_state
	check(runtime.screen.visible and runtime.screen.rain==.8 and runtime.screen.snow==0,"Rain renderer follows current condition: "+mode+"/"+asset)
	check(runtime.screen.particles.size()==360 and runtime.foliage.entries.size()==1,"Particle budget and explicit foliage collection are bounded: "+mode+"/"+asset)
	var entry: Dictionary=runtime.foliage.entries["oak"]; var changed: bool=false
	for slot in entry["slots"]:
		if slot["applied"]!=slot["original"]: changed=true
	check(changed,"Autumn changes actual sprite pixels / model palette: "+mode+"/"+asset)
	check(tree.transform==transform and data==before,"Weather preserves authored root transforms, physics and document: "+mode+"/"+asset)
	var same: Array=entry["slots"].map(func(slot: Dictionary)->Resource:return slot["applied"])
	runtime.step(.1,data,{"oak":tree})
	check(same==entry["slots"].map(func(slot: Dictionary)->Resource:return slot["applied"]),"Stable season retains generated textures and material instances: "+mode+"/"+asset)
	check(entry["wind"].any(func(value: Dictionary)->bool:return absf(value["angle"])>0),"Wind moves visual foliage without moving the root: "+mode+"/"+asset)
	data["weather"]["foliage"]=false; runtime.step(.1,data,{"oak":tree})
	check(entry["slots"].all(func(slot: Dictionary)->bool:return slot["applied"]==slot["original"]),"Turning foliage off restores original leaves, including authored blossom pixels: "+mode+"/"+asset)
	data["weather"]["foliage"]=true
	var parts=preload("res://scripts/builder/part_colors.gd")
	if asset.begins_with("2d:"):
		var sprite: Sprite2D=parts.sprite_for(tree); var source: Texture2D=parts.base_texture(sprite); var picture: Image=source.get_image(); var pixel: int=-1
		for y in picture.get_height():
			for x in picture.get_width():
				if picture.get_pixel(x,y).a>.9: pixel=y*picture.get_width()+x; break
			if pixel>=0: break
		check(not source.resource_path.is_empty(),"Seasonal sprites preserve authored source identity for piece picking: "+mode+"/"+asset)
		item["colors"]=[{"kind":"pixels","texture":source.resource_path,"pixels":[pixel],"frame":0,"color":[0.1,0.2,1.0,1.0]}]; parts.apply(tree,item); runtime.step(.1,data,{"oak":tree})
		check(parts.sprite_for(tree).texture.get_image().get_pixel(pixel%picture.get_width(),pixel/picture.get_width()).b>.95,"Real pixel painting remains visible during active weather: "+mode+"/"+asset)
	else:
		var model: Node3D=parts.model_root(tree); var mesh: MeshInstance3D=model.find_children("*","MeshInstance3D",true,false)[0]
		var source_mesh: Mesh=mesh.mesh
		item["colors"]=[{"kind":"faces","mesh":str(model.get_path_to(mesh)),"surface":0,"faces":[0],"color":[0.1,0.2,1.0,1.0]}]; parts.apply(tree,item); runtime.step(.1,data,{"oak":tree})
		check(mesh.mesh!=source_mesh and mesh.mesh.get_surface_count()>=2,"Real face painting can replace topology while weather is active: "+mode+"/"+asset)
		var blue: bool=false
		for index in mesh.mesh.get_surface_count():
			var material: Material=mesh.get_active_material(index)
			if material is BaseMaterial3D and material.albedo_color.b>.95 and material.albedo_color.r<.2: blue=true
		check(blue,"Seasonal recoloring preserves the actual custom-painted model surface: "+mode+"/"+asset)
	entry=runtime.foliage.entries["oak"]
	var visual: Node=entry["wind"][0]["node"].get_ref()
	if visual is Node2D: visual.rotation=.4
	else: visual.rotation.z=.4
	runtime.step(.1,data,{"oak":tree})
	var wind: Dictionary=runtime.foliage.entries["oak"]["wind"][0]
	check(is_equal_approx(wind["base"],.4),"Wind accepts externally updated visual transforms without baking its previous sway: "+mode+"/"+asset)
	data["weather"]["condition"]="snow"; runtime.step(.1,data,{"oak":tree})
	check(runtime.screen.snow==.8 and runtime.screen.rain==0,"Snow replaces rain without stale precipitation: "+mode+"/"+asset)
	runtime.step(.1,data,{"oak":tree},false)
	check(not runtime.screen.visible and runtime.foliage.entries.is_empty() and tree.transform==transform,"Interiors suppress precipitation and restore exterior visuals: "+mode+"/"+asset)
	check(is_equal_approx(visual.rotation if visual is Node2D else visual.rotation.z,.4),"Stopping weather preserves the latest authored visual transform: "+mode+"/"+asset)
	data["weather"]["enabled"]=false; runtime.step(.1,data,{"oak":tree})
	check(not runtime.screen.visible and runtime.foliage.entries.is_empty(),"Disabled weather leaves no active effects: "+mode+"/"+asset)
	data["weather"].merge({"enabled":true,"season":"autumn","cycle_seasons":true,"season_seconds":30},true); runtime.step(90,data,{"oak":tree})
	check(runtime.current_state["effective_season"]=="summer","Season timing retains elapsed seconds across a long frame: "+mode+"/"+asset)
	runtime.free(); tree.free()
func movement(mode: String) -> void:
	var manager=preload("res://scripts/builder/citizen_runtime.gd").new(); manager.dimension=mode; root.add_child(manager); manager.set_physics_process(false)
	manager.container=Node2D.new() if mode=="2d" else Node3D.new(); manager.add_child(manager.container)
	var actor: Node=manager.make_actor("weather_speed"); actor.set_physics_process(false); actor.collision_mask=0
	if mode=="3d": actor.gravity=0
	var results: Array=[]
	for wet in [false,true]:
		actor.teleport_to(Vector2.ZERO if mode=="2d" else Vector3.ZERO); actor.velocity=Vector2.ZERO if mode=="2d" else Vector3.ZERO
		manager.hour=9; manager.terrain_data={"weather":{"enabled":wet,"condition":"rain","intensity":1.0,"affect_activity":true}}
		manager.plan={"settings":{"enabled":true,"day_length":3600},"lookup":{"work":{"role":"work","name":"Work","point":Vector2(100,0)}}}
		manager.residents.assign([{"actor":actor,"id":"weather_speed","home":"home","work":"work","offset":0,"target":"work","path":PackedVector2Array([Vector2.ZERO,Vector2(100,0)]),"index":1,"blocked":false,"retry":0.0,"stalled":0.0,"spacing":Vector2.ZERO,"waiting":"","visits":[]}])
		for frame in 80: manager.step(1.0/60); await physics_frame
		results.append({"distance":manager.point(actor).length(),"speed":Vector2(actor.velocity.x,actor.velocity.z).length() if mode=="3d" else actor.velocity.length()})
	check(is_equal_approx(results[1]["speed"]/results[0]["speed"],.75),"Optional weather affects the actual citizen controller's sustained walking speed: "+mode)
	var ratio: float=results[1]["distance"]/results[0]["distance"]
	check(ratio>.65 and ratio<.85,"Weather reduces real citizen travel distance while retaining physics timing: "+mode)
	manager.residents.clear(); actor.free(); manager.free()
func rendered_projection() -> void:
	var tree: Node=preload("res://scripts/builder/asset_instance.gd").make(library,"3d:HanX_Park/Tree_Oak","2d"); root.add_child(tree)
	await process_frame; RenderingServer.force_draw(false); RenderingServer.force_draw(false)
	var original: Image=tree.viewport.get_texture().get_image(); original.save_png("res://output/weather_projected_original.png")
	var helper=preload("res://scripts/builder/weather_foliage.gd").new()
	var data: Dictionary={"objects":[{"uid":"projected","asset":"3d:HanX_Park/Tree_Oak"}]}
	helper.sync(data,{"projected":tree},Plan.state({"weather":{"enabled":true,"season":"autumn","wind":0}}),0)
	await process_frame; RenderingServer.force_draw(false); RenderingServer.force_draw(false)
	var autumn: Image=tree.viewport.get_texture().get_image(); autumn.save_png("res://output/weather_projected_autumn.png")
	check(autumn.get_data()!=original.get_data(),"Season changes repaint the actual cached model-in-2D viewport")
	helper.reset(); await process_frame; RenderingServer.force_draw(false); RenderingServer.force_draw(false)
	var restored: Image=tree.viewport.get_texture().get_image()
	check(restored.get_data()==original.get_data(),"Removing seasonal effects restores exact projected model pixels")
	tree.free()
func run() -> void:
	library=preload("res://scripts/builder/asset_library.gd").new(); Plan.foliage("2d:Tree_Oak")
	schema(); palette()
	for mode in ["2d","3d"]:
		for asset in ["2d:Tree_Oak","3d:HanX_Park/Tree_Oak","2d:Tree_Cherry_Blossom","3d:HanX_Park/Tree_Cherry_Blossom"]: visuals(mode,asset)
		await movement(mode)
	if "--capture" in OS.get_cmdline_user_args(): await rendered_projection()
	print("WEATHER FOUNDATION: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)

