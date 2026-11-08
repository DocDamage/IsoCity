extends SceneTree
const OUT="res://output/verification/asset_expansion/U08"
const Preview=preload("res://scripts/builder/asset_scale_preview.gd")
const Templates=preload("res://scripts/builder/templates.gd")
const SATELLITE="3d:Supplemental_Satellites/03_cubesat_3u"
const SHIP="3d:Supplemental_Spaceships_II/hammerhead_cruiser"
const TREE="3d:HanX_Park/Tree_Pine"
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;print("FAIL: "+message)
func settle() -> void:
	for frame in 8:await process_frame
	await physics_frame
func close_vec(a: Vector3,b: Vector3) -> bool:return a.is_equal_approx(b)
func fit(preview: RefCounted) -> void:
	if preview.mode=="3d":
		for point in preview.view_points():
			var pixel: Vector2=preview.camera.unproject_position(point)
			check(Rect2(Vector2.ZERO,Vector2(preview.viewport.size)).grow(1).has_point(pixel),"Fit asset camera contains actual prepared bounds, including oblique billboard cards")
func run() -> void:
	var store=preload("res://scripts/builder/project_store.gd");store.storage_root=OUT+"/history";store.legacy_autosave=OUT+"/legacy.json"
	var studio: Control=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio)
	while not studio.enhancements_ready:await process_frame
	var browser: RefCounted=studio.asset_browser;var preview: RefCounted=browser.scale_preview
	if studio.consumer_shell:studio.consumer_shell.dismiss_welcome()
	var inventory: int=studio.library.assets.size()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode);var doc: RefCounted=studio.current();doc.data=Templates.make(mode,"blank");studio.changed();await settle()
		var same: float=-1
		for id in [SATELLITE,SHIP,TREE,"2d:Coffee_Shop","2d:Office_Worker","2d:Hatchback_Yellow"]:
			var before: Dictionary=doc.data.duplicate(true);var undo: int=doc.undo_history.size()
			browser.show_asset(id);preview.toggle.button_pressed=true;await settle()
			check(is_instance_valid(preview.sample) and preview.mode==mode,"Comparison builds the same representation as placement: "+mode+"/"+id)
			check(preview.references.size()==2 and preview.viewport.gui_disable_input,"Actual person/car references and isolated input exist: "+mode+"/"+id)
			check(preview.record["scale"]==studio.library.assets[id]["data"].get("default_scale",1),"Default placement scale is used: "+id)
			preview.view.select(0);preview.arrange();fit(preview)
			if mode=="2d" and id.begins_with("3d:"):
				await settle()
				check(Preview.screen_bounds(preview.sample).is_equal_approx(preview.visual_2d),"Private projection supersampling preserves the placed canvas rectangle")
				if id==SATELLITE:check(preview.sample.viewport.size.x>preview.projection_size.x and preview.sample.viewport.size.x<=2048,"Tiny model close-up has useful private render resolution without changing placement")
			check(preview.note.text.contains("grid cell") and preview.note.text.contains("still pose"),"Comparison states units and pose honestly")
			if id.begins_with("2d:"):
				check(preview.note.text.contains("Calibrated ground footprint") and preview.note.text.contains("Artwork height is not physical height"),"Sprite physical sizing comes from calibrated ground, not image height")
				if mode=="3d":
					check(preview.note.text.contains("Flat sprite card"),"Mixed-mode sprite retains its actual flat projection")
					var foot: Array=studio.library.assets[id]["data"]["directions"][preview.record["direction"]]["footprint"]
					check(is_equal_approx(preview.ground_3d.size.x,float(foot[0])*float(preview.record["scale"])) and is_equal_approx(preview.ground_3d.size.z,float(foot[1])*float(preview.record["scale"])),"Sprite ground dimensions agree with calibrated metadata independently of picture size")
			preview.view.select(1);preview.span.select(1);preview.arrange()
			var scale: float=preview.camera.zoom.y if mode=="2d" else preview.camera.size
			if same<0:same=scale
			check(is_equal_approx(same,scale),"Fixed-scale camera is unchanged across tiny satellites, broad ships, tall trees and sprites: "+mode)
			preview.person.button_pressed=false;check(not preview.references[0].visible,"Person reference toggle affects only the private scene");preview.person.button_pressed=true
			check(doc.data==before and doc.undo_history.size()==undo and studio.library.assets.size()==inventory,"References and camera changes never author city content, history or catalog entries")
			var weak: WeakRef=weakref(preview.sample);browser.dialog.hide();await settle()
			check(weak.get_ref()==null and preview.world==null,"Closing releases the private scene and all references")
		# Preview a placed object's actual arbitrary transform, then edit only the
		# comparison scale. No transform is applied back to the selected object.
		var item: Dictionary=doc.add(SATELLITE,[0,0,0],"35",2.75);item["tilt"]=[12,-8]
		studio.changed();await settle();studio.selected_uids.assign([item["uid"]]);studio.selected_uid=item["uid"];studio.refresh_controls()
		var before: Dictionary=doc.data.duplicate(true);var history: int=doc.undo_history.size()
		browser.show_asset(SATELLITE);preview.toggle.button_pressed=true;await settle()
		check(preview.context_label=="Selected object transform" and is_equal_approx(preview.size_input.value,2.75) and preview.record["tilt"]==[12,-8],"Selected arbitrary scale/orientation are represented: "+mode)
		var actual: Node=studio.worlds[mode].instances[item["uid"]]
		if mode=="2d":check(Preview.screen_bounds(actual).is_equal_approx(preview.visual_2d) and actual.ground_polygon()==preview.sample.ground_polygon(),"Projected model size and footprint exactly match the placed instance")
		else:
			var bounds: AABB=Preview.render_bounds(actual)
			check(close_vec(bounds.position,preview.visual_3d.position) and close_vec(bounds.size,preview.visual_3d.size),"Prepared geometry with nested import transforms matches the placed instance")
		var reference_sizes: Array=preview.references.map(func(node: Node):return node.scale)
		preview.size_input.value=.01;await settle();preview.view.select(0);preview.arrange();fit(preview)
		check(doc.data==before and doc.undo_history.size()==history and is_equal_approx(doc.object(item["uid"])["scale"],2.75),"Tiny comparison-only scaling preserves placed transforms and Undo history")
		preview.size_input.value=75;await settle();preview.view.select(1);preview.arrange()
		check(reference_sizes==preview.references.map(func(node: Node):return node.scale),"Changing comparison asset scale never rescales the person or car")
		check(is_equal_approx(preview.camera.zoom.y,float(preview.viewport.size.y)/256) if mode=="2d" else is_equal_approx(preview.camera.size,16),"Very large comparison-only scale does not silently change fixed zoom")
		check(preview.references.all(func(node: Node):return preview.world.is_ancestor_of(node) and not studio.worlds[mode].is_ancestor_of(node) and not node.has_meta("builder_uid")),"References remain outside the city's instance and ownership tree")
		var result: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],studio.current().data,studio.library,OUT+"/scale_"+mode+".zip")
		check(result["ok"] and preview.panel.visible and is_instance_valid(preview.world),"Export while comparison is open excludes private objects: "+mode+" "+result.get("message",""))
		var expected: Dictionary={"asset":SATELLITE,"uid":item["uid"],"scale":2.75,"direction":"35","tilt":[12,-8]}
		if mode=="2d":
			var rect: Rect2=Preview.screen_bounds(actual);expected["min"]=[rect.position.x,rect.position.y];expected["size"]=[rect.size.x,rect.size.y]
		else:
			var box: AABB=Preview.render_bounds(actual);expected["min"]=[box.position.x,box.position.y,box.position.z];expected["size"]=[box.size.x,box.size.y,box.size.z]
		FileAccess.open(OUT+"/expected_"+mode+".json",FileAccess.WRITE).store_string(JSON.stringify(expected))
		browser.dialog.hide();await settle()
		var path: String=OUT+"/scale_"+mode+".isocity.json"
		check(studio.write_project(path) and studio.load_project(path) and studio.current().data["objects"]==JSON.parse_string(JSON.stringify(before["objects"])),"Save/reopen retains only exact authored content: "+mode)
	# Missing reference art degrades independently of the inspected asset.
	studio.switch_mode("3d");var car: Dictionary=studio.library.assets[Preview.CAR_3D];studio.library.assets.erase(Preview.CAR_3D)
	browser.show_asset(SATELLITE);preview.toggle.button_pressed=true;await settle()
	check(preview.sample!=null and preview.note.text.contains("Car reference unavailable") and preview.references.size()==1,"Missing car reference leaves inspected art, person and grid usable")
	studio.library.assets[Preview.CAR_3D]=car;browser.dialog.hide();await settle()
	browser.show_asset(SATELLITE);await settle();var path: String=studio.library.assets[SATELLITE]["path"]
	studio.library.assets[SATELLITE]["path"]="res://missing_u08_prepared_scene.tscn";preview.rebuild()
	check(preview.sample==null and preview.note.text.contains("comparison unavailable"),"Missing prepared source produces an explanation without an engine loader error")
	studio.library.assets[SATELLITE]["path"]=path;preview.rebuild();check(preview.sample!=null,"Restoring the prepared source recovers comparison in the same session");browser.dialog.hide();await settle()
	await pivots(studio)
	studio.free();await process_frame;await process_frame
	print("ASSET SCALE PREVIEW: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

func pivots(studio: Control) -> void:
	var source:=Node3D.new();source.name="OffsetPivot";source.position=Vector3(17,8,-20);source.scale=Vector3(4,2,1)
	var mesh:=MeshInstance3D.new();mesh.mesh=BoxMesh.new();mesh.mesh.size=Vector3(2,4,6);mesh.position=Vector3(12,1,-9);mesh.scale=Vector3(.5,2,1.5);source.add_child(mesh);mesh.owner=source
	var packed:=PackedScene.new();check(packed.pack(source)==OK and ResourceSaver.save(packed,OUT+"/offset_pivot.tscn")==OK,"Offset-pivot fixture is an actual prepared scene");source.free()
	var id: String="3d:U08/OffsetPivot"
	studio.library.assets[id]={"id":id,"mode":"3d","name":"Offset-pivot fixture","category":"Verification","path":OUT+"/offset_pivot.tscn","data":{},"behavior":{"collision":"none"}}
	var browser: RefCounted=studio.asset_browser;var preview: RefCounted=browser.scale_preview
	for mode in ["2d","3d"]:
		studio.switch_mode(mode);var doc: RefCounted=studio.current();doc.data=Templates.make(mode,"blank")
		var item: Dictionary=doc.add(id,[0,0,0],"17",1.3);item["tilt"]=[8,13]
		studio.changed();await settle();studio.selected_uids.assign([item["uid"]]);studio.selected_uid=item["uid"];studio.refresh_controls()
		browser.show_asset(id);preview.toggle.button_pressed=true;await settle();preview.view.select(0);preview.arrange();fit(preview)
		var actual: Node=studio.worlds[mode].instances[item["uid"]]
		if mode=="3d":
			var expected: AABB=Preview.render_bounds(actual)
			check(close_vec(expected.position,preview.visual_3d.position) and close_vec(expected.size,preview.visual_3d.size) and preview.sample.position==Vector3.ZERO,"Imported pivots and nested nonuniform transforms match actual 3D placement without recentering the asset")
		else:check(Preview.screen_bounds(actual).is_equal_approx(preview.visual_2d) and preview.sample.position==Vector2.ZERO,"Offset imported pivot uses the same 2D projection/origin as placement")
		var old: WeakRef=weakref(preview.world);browser.show_asset(SATELLITE);await settle();check(old.get_ref()==null,"Rapid selection frees the previous private imported scene")
		browser.dialog.hide();doc.data=Templates.make(mode,"blank");studio.changed();await settle()
	studio.library.assets.erase(id)
