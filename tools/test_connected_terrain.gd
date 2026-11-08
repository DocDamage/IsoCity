extends SceneTree

const Families=preload("res://scripts/builder/terrain_family_plan.gd")
const Patterns=preload("res://scripts/builder/tile_patterns.gd")
const Fit=preload("res://scripts/builder/grid_fit.gd")
const Terrain=preload("res://scripts/builder/terrain_plan.gd")
const Templates=preload("res://scripts/builder/templates.gd")
const Doc=preload("res://scripts/builder/document.gd")
const Protection=preload("res://scripts/builder/cooperative_plan.gd")
const Export=preload("res://scripts/builder/portable_export.gd")

var studio: Control
var checks: int=0
var failures: int=0
var output: String

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool,description: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL: "+description)

func settle() -> void:
	for frame in 8: await process_frame

func pixels(cell: Vector2i) -> Vector2:
	return Fit.pixels(Vector2(cell)+Vector2.ONE*.5)

func screen(cell: Vector2i) -> Vector2:
	return studio.viewport.get_canvas_transform()*pixels(cell)

func brush(style: int,operation: int,asset: String="") -> void:
	studio._command("ground_families",null)
	var tools: RefCounted=studio.ground_brush
	tools.family_choice.select(style)
	tools.family_choice.item_selected.emit(style)
	if not asset.is_empty(): studio.select_asset(asset)
	tools.operation.select(operation)
	tools.replace_only.button_pressed=false
	studio.brush_input.set_value_no_signal(1)
	studio.repeat_input.button_pressed=true

func paint(first: Vector2i,last: Vector2i) -> void:
	var event:=InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=true
	event.position=screen(first)
	studio._canvas_input(event)
	event=event.duplicate()
	event.pressed=false
	event.position=screen(last)
	studio._canvas_input(event)
	studio.current().finish_checkpoint()

func native_ground() -> void:
	var world: Node=studio.worlds["2d"]
	var doc: RefCounted=studio.current()
	var original: Dictionary=doc.data.duplicate(true)
	brush(1,2)
	check(studio.ground_brush.panel.is_visible_in_tree() and studio.ground_brush.family()=="shore","Normal Ground controls start the reviewed shoreline brush.")
	paint(Vector2i(-5,-4),Vector2i(-1,0))
	check(doc.data["tiles"].size()==25 and world.family_variants.size()==25 and doc.undo_history.size()==1,
		"The rectangular pond is one authored stroke and uses one tile per cell. "+str(doc.data["tiles"].size()))
	if world.family_variants.size()!=25: return
	var middle:=Vector2i(-3,-2)
	check(world.family_variants[middle]["mask"]==0 and world.family_variants[Vector2i(-5,-4)]["mask"]==9,
		"Closed pond has a dry outer corner and a continuous interior.")
	var source: TileSetAtlasSource=world.ground.tile_set.get_source(world.ground.get_cell_source_id(middle))
	check(source.get_tile_animation_frames_count(Vector2i.ZERO)==4 and source.texture_region_size==Vector2i(32,16) and not source.use_texture_padding,
		"Each shoreline variant keeps the native cell size and four water frames.")
	var pond: Dictionary=doc.data.duplicate(true)
	studio._command("undo",null)
	check(doc.data==original and world.family_variants.is_empty(),"Undo removes the entire automatic pond.")
	studio._command("redo",null)
	check(doc.data==pond and world.family_variants.size()==25,"Redo restores the pond family and native cell layout.")
	brush(0,0,"2d:Grass")
	var untouched: int=world.ground.get_cell_source_id(Vector2i(-5,-4))
	paint(middle,middle)
	check(world.family_variants[Vector2i(-4,-3)]["inlets"]==2 and world.family_variants[Vector2i(-3,-3)]["mask"]==4,
		"A dry island forms a diagonal inlet and matching cardinal banks.")
	check(world.last_apply_tile_updates<=9 and world.ground.get_cell_source_id(Vector2i(-5,-4))==untouched,
		"One island cell only invalidates its immediate neighbors.")
	var island: Dictionary=doc.data.duplicate(true)
	paint(middle,middle)
	check(doc.data==island and world.ground.get_used_cells().size()==25,"Repeating a manual paint never stacks ground.")
	brush(2,1)
	paint(Vector2i(-6,5),Vector2i(0,5))
	paint(Vector2i(-3,3),Vector2i(-3,5))
	var junction:=Vector2i(-3,5)
	check(Families.piece(world.family_variants.get(junction,{"family":"path","mask":0}))=="tee","Three path arms choose the T piece.")
	paint(junction,Vector2i(-3,7))
	check(world.family_variants.get(junction,{}).get("mask",0)==15 and Families.piece(world.family_variants[junction])=="cross",
		"Fourth arm chooses the path cross piece.")
	var path_scene: Dictionary=doc.data.duplicate(true)
	brush(0,0,"2d:Stone_Path")
	studio.direction="SW"
	var arm:=Vector2i(-3,4)
	paint(arm,arm)
	var tile: Dictionary=Families.by_cell(doc.data["tiles"])[arm]
	check(not tile.has("family") and tile["direction"]=="SW" and world.family_warnings.has(junction),
		"Manual rotation survives and the adjacent unsupported join is marked.")
	studio._command("undo",null)
	check(doc.data==path_scene and world.family_variants[junction]["mask"]==15,"Undo restores automatic topology exactly.")
	brush(2,3)
	var previous_updates: int=world.last_apply_tile_updates
	var previous_history: int=doc.undo_history.size()
	paint(junction,junction)
	check(doc.data==path_scene and studio.ground_brush.changed_count==0 and world.last_apply_tile_updates==previous_updates
		and doc.undo_history.size()==previous_history,
		"Connected flood repaint leaves authored surfaces, rendering and Undo unchanged.")
	check(Doc.valid(doc.data,"2d",studio.library),"The ordinary document validator accepts authored family records.")
	await capture("shore_and_paths","ground_families")

func sculpted() -> void:
	var doc: RefCounted=studio.current()
	var world: Node=studio.worlds["2d"]
	doc.data["terrain"]={"enabled":true,"bounds":[-12,-10,28,24]}
	doc.data["terrain_vertices"]=[]
	doc.data["water_cells"]=[]
	for x in range(5,10):
		for y in range(-4,1): doc.data["terrain_vertices"].append({"cell":[x,y],"height":4.0})
	for x in range(-9,-5):
		for y in range(-7,-3): doc.data["water_cells"].append({"cell":[x,y],"level":2.0 if x==-6 else 1.0})
	studio.changed()
	var tools: RefCounted=studio.terrain_tools
	studio._command("terrain",null)
	tools.connected_shores.button_pressed=true
	tools.connected_cliffs.button_pressed=true
	tools.apply_settings()
	var authored: Dictionary=doc.data.duplicate(true)
	check(Terrain.settings(doc.data)["connected_shores"] and Terrain.settings(doc.data)["connected_cliffs"],
		"Terrain applies the optional bank and cliff rules through its settings.")
	var rock: Dictionary=world.terrain.rock_faces.duplicate(true)
	var directions: int=0
	for variant in rock.values(): directions|=variant["mask"]
	check(directions==15 and rock.size()>12,"A raised plateau forms a rock loop with all four downward directions.")
	check(world.terrain.family_warnings.has(Vector2i(-7,-5)) and world.terrain.family_warnings.has(Vector2i(-6,-5)),
		"Unequal water levels mark both sides of the unsupported join.")
	var water_faces: int=0
	var rock_faces: int=0
	for strip in world.terrain.strips.values():
		for face in strip.faces:
			if face["kind"]=="water" and face.get("textures",[]).size()==4: water_faces+=1
			if face["kind"]=="land" and rock.has(face["cell"]) and face.has("textures"): rock_faces+=1
	check(water_faces>12 and rock_faces>12,"Both cliff and animated shore art reach the actual terrain surface.")
	tools.operation.select(2)
	tools.radius.value=1.2
	tools.amount.value=1.0
	tools.target.value=1.0
	tools.begin(Vector2(16,-6))
	tools.finish()
	check(doc.data!=authored and world.terrain.rock_faces!=rock,"Sculpting a changed height recalculates the rock boundary.")
	studio._command("undo",null)
	check(doc.data==authored and world.terrain.rock_faces==rock,"Undo restores the exact height samples and cliff loop.")
	await capture("sculpted_banks_and_cliffs","terrain")

func capture(name: String,command: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	for simple in [false,true]:
		studio.consumer_shell.set_active(simple,false)
		for size in [Vector2i(1480,900),Vector2i(960,640)]:
			root.size=size
			studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true} if size.x==960 else {})
			if size.x==960: studio.workspace_layout.library_toggle.button_pressed=false
			studio._command(command,null)
			if command=="terrain": studio.terrain_tools.activate()
			await settle()
			var world: Node=studio.worlds["2d"]
			if command=="terrain":
				world.camera.position=Vector2((210 if size.x==960 else 135) if simple else 0,-16)
				world.camera.zoom=Vector2.ONE*(1.0 if size.x==960 else 1.7)
			else:
				world.camera.position=Vector2(70 if simple else -32,12)
				world.camera.zoom=Vector2.ONE*(1.35 if size.x==960 else 2.1)
			await settle()
			var control: Control=studio.ground_brush.family_choice if command=="ground_families" else studio.terrain_tools.connected_shores
			control.grab_focus()
			await settle()
			if command=="terrain":
				studio.control_settings.cursor_active=true
				var at: Vector2=studio.overlay_position([pixels(Vector2i(-7,-5)).x,pixels(Vector2i(-7,-5)).y,1.0],0.0)
				studio.control_settings.cursor_position=at
				await settle()
				check(not studio.overlay.terrain_markers.is_empty() and "different levels" in studio.overlay.caption,
					"Unsupported height transitions have explicit canvas markers and a reason.")
			check(control.has_focus() and Rect2(Vector2.ZERO,Vector2(size)).encloses(control.get_global_rect()),
				"Connected terrain controls remain keyboard-visible in "+str([name,simple,size]))
			RenderingServer.force_draw(false)
			RenderingServer.force_draw(false)
			check(root.get_texture().get_image().save_png(output+"/%s_%s_%d.png"%[name,"simple" if simple else "precision",size.x])==OK,
				"Captured connected terrain artwork and controls.")
			control.release_focus()
			studio.control_settings.cursor_active=false
	root.size=Vector2i(1480,900)
	studio.accessibility_settings.restore({})
	await settle()

func rule_edges() -> void:
	var variant: Dictionary={"family":"path","mask":7,"unsupported":0}
	var pieces: Array=Families.profile("path")["pieces"]
	var original: String=pieces[7]
	pieces[7]=""
	var key: Array=Patterns.family_key(variant)
	var cached: Dictionary=Patterns.family_cache.get(key,{})
	Patterns.family_cache.erase(key)
	check(Patterns.family_pattern(variant).is_empty(),"A missing reviewed piece returns an explicit fallback.")
	pieces[7]=original
	if not cached.is_empty(): Patterns.family_cache[key]=cached
	var surfaces: Dictionary={}
	for x in 129:
		for y in 129: surfaces[Vector2i(x,y)]={"asset":"2d:Water","editable":true}
	var cells=preload("res://scripts/builder/brush_cells.gd")
	check(cells.flood(Vector2i.ZERO,surfaces).size()==cells.LIMIT,"Connected flood retains the 16,384-cell cap.")
	var base: Dictionary=Templates.make("2d","blank")
	base["tiles"]=[{"cell":[0,0],"asset":"2d:Stone_Path","family":"path","direction":"SE"}]
	base["protected_areas"]=[{"uid":"plot","name":"Protected path","owner":"host","rect":[.5,.5,1,1]}]
	var before: Dictionary={"2d":base,"3d":Templates.make("3d","blank")}
	var after: Dictionary=before.duplicate(true)
	after["2d"]["tiles"].append({"cell":[1,0],"asset":"2d:Stone_Path","family":"path","direction":"SE"})
	check(Protection.allowed(before,after,"guest",studio.library).contains("Protected path"),
		"Host rejects an outside edit that would change a protected neighbor's automatic path.")

func run() -> void:
	output=OS.get_environment("ISOCITY_TERRAIN_FAMILY_OUTPUT")
	if output.is_empty(): output="res://output/verification/asset_expansion/I09"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	studio=load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled=false
	root.add_child(studio)
	await settle()
	if studio.consumer_shell: studio.consumer_shell.dismiss_welcome()
	studio.switch_mode("2d")
	var doc: RefCounted=studio.current()
	doc.data=Templates.make("2d","blank")
	studio.changed()
	await settle()
	await native_ground()
	await sculpted()
	rule_edges()
	var path: String=output+"/connected_terrain.isocity.json"
	var saved: Dictionary=studio.current().data.duplicate(true)
	check(studio.write_project(path,false) and studio.load_project(path),"Connected terrain uses the regular save and load flow.")
	check(studio.current().data["tiles"]==saved["tiles"] and Terrain.settings(studio.current().data)==Terrain.settings(saved),
		"Reopening retains editable terrain families and settings.")
	if "--portable" in OS.get_cmdline_user_args():
		var result: Dictionary=Export.new().save(studio.worlds["2d"],saved,studio.library,output+"/connected_terrain.zip")
		check(result.get("ok",false),"Allowed native assets export to an independent project. "+result.get("message",""))
	studio.switch_mode("3d")
	studio._command("ground_families",null)
	check(studio.ground_brush.family_choice.disabled and studio.ground_brush.info.text.contains("Pixel world"),
		"Model world gives the explicit unsupported-family fallback.")
	studio._command("terrain",null)
	check(studio.terrain_tools.connected_cliffs.disabled and studio.terrain_tools.connected_shores.disabled,
		"Native Model terrain controls never guess a sprite cliff equivalent.")
	studio.free()
	await settle()
	print("CONNECTED TERRAIN: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
