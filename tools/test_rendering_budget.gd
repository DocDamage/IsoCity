extends SceneTree

const Budget = preload("res://scripts/builder/rendering_budget.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const Doc = preload("res://scripts/builder/document.gd")
const Portable = preload("res://scripts/builder/portable_export.gd")
const Traffic = preload("res://scripts/builder/traffic_plan.gd")
const OUTPUT = "res://output/verification/asset_expansion/I19"
const SHIP = "3d:Supplemental_Spaceships_II/hammerhead_cruiser"
const CRATE = "3d:HanX_Construction/Shipping_Container"
const ARCADE = "3d:Supplemental_Arcade/13_arcade_13_racer_blue"
var checks: int
var failures: int
var studio: Control
var output: String = OUTPUT

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: "+message)
	return ok

func frames(count: int = 7) -> void:
	for frame in count: await process_frame

func drawn(count: int = 7) -> void:
	for frame in count: await RenderingServer.frame_post_draw
	await process_frame

func add(uid: String, asset: String, point: Vector2, scale_value: float = 1.0) -> Dictionary:
	var item: Dictionary = studio.current().add(asset,Traffic.world(point,studio.mode),"0",scale_value)
	item["uid"] = uid
	return item

func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	var arguments := OS.get_cmdline_user_args()
	var output_option := arguments.find("--rendering-output")
	if output_option >= 0:
		if output_option + 1 >= arguments.size():
			push_error("--rendering-output needs a verification directory")
			quit(2)
			return
		output = arguments[output_option + 1]
		if not output.begins_with("res://output/verification/") or ".." in output.split("/"):
			push_error("--rendering-output must stay under res://output/verification")
			quit(2)
			return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	studio = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	while not studio.enhancements_ready: await process_frame
	if studio.consumer_shell: studio.consumer_shell.dismiss_welcome()
	for mode in ["2d","3d"]: await exercise(mode)
	await browser()
	policy_edges()
	studio.free()
	await frames()
	print("RENDERING BUDGET: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func exercise(mode: String) -> void:
	studio.switch_mode(mode)
	var doc := Doc.new()
	doc.data = Templates.make(mode,"blank")
	doc.data["title"] = "Rendering budget fixture"
	studio.documents[mode] = doc
	var first: Dictionary = add("hero",SHIP,Vector2.ZERO)
	add("matching",SHIP,Vector2(-8,3))
	add("container",CRATE,Vector2(7,2))
	add("live",ARCADE,Vector2(5,-5))
	studio.changed()
	var world: Node = studio.worlds[mode]
	var instance: Node = world.instances["hero"]
	var asset: Dictionary = studio.library.assets[SHIP]
	var profile: Dictionary = Budget.profile(asset)
	check(profile["low"]["triangles"] < profile["full"]["triangles"] and profile["regular"] == "low"
		and profile["photo"] == "full" and ResourceLoader.exists(profile["full"]["path"]),"Both explicit visual editions resolve "+mode)
	if mode == "2d":
		world.camera.position = Vector2.ZERO
		world.camera.zoom = Vector2.ONE*2.2
	else:
		world.target = Vector3.ZERO
		world.distance = 19
		world.update_camera()
	await drawn()
	var source_record: Dictionary = doc.data.duplicate(true)
	if mode == "2d":
		var match_instance: Node = world.instances["matching"]
		var original: Texture2D = instance.sprite.texture
		check(original is ImageTexture and instance.viewport == null and match_instance.sprite.texture == original
			and match_instance.viewport == null,"Identical Pixel assets share one baked texture and release both targets")
		check(world.instances["live"].viewport is SubViewport,"The interactive arcade keeps a live projection")
		var hit: Dictionary = paint_hit(instance,first)
		check(not hit.is_empty(),"The actual paint tool picks a canonical face through a cached projection")
		var footprint: PackedVector2Array = instance.ground_polygon()
		var mesh_root: Node3D = instance.model
		var meshes: Array = mesh_root.find_children("*","MeshInstance3D",true,false)
		var mesh_path: String = str(mesh_root.get_path_to(meshes[0]))
		first["colors"] = [{"kind":"faces","mesh":mesh_path,"surface":0,"faces":[0],"color":[.92,.02,.08,1.0]}]
		studio.changed()
		await drawn()
		check(instance.viewport is SubViewport and instance.sprite.texture != original and match_instance.sprite.texture == original
			and instance.ground_polygon() == footprint,"Paint isolates the affected model and preserves its collision footprint")
		first.erase("colors")
		first["direction"] = "31.25"
		studio.changed()
		await drawn()
		check(instance.viewport == null and instance.sprite.texture is ImageTexture and instance.sprite.texture != original,
			"A free angle uses a distinct projection key")
		first["direction"] = "0"
		studio.changed()
		await drawn()
		check(instance.sprite.texture == original and instance.ground_polygon() == footprint,"Removing the override restores the exact shared image and footprint")
	else:
		var container: Node3D = world.instances["container"]
		var shape: CollisionShape3D = container.get_node("CollisionShape3D")
		var saved_shape: Shape3D = shape.shape
		world.camera.size = 7000
		world.presentation.refresh()
		check(not container.get_node("Model").visible and not shape.disabled and shape.shape == saved_shape
			and container.collision_layer != 0,"Tiny Model visuals can cull while the actual collider remains enabled")
		world.update_camera()
		world.presentation.refresh()
		check(container.get_node("Model").visible and shape.shape == saved_shape and not shape.disabled,"Zooming in restores the same visual and collider")
	var saved_normal: Texture2D = instance.sprite.texture if mode == "2d" else null
	var photo: Node = world.exploration.photo
	check(photo.start(),"The normal Photo action starts "+mode)
	await drawn()
	if mode == "2d":
		check(instance.photo_quality and instance.photo_profile["full"]["sha256"] == profile["full"]["sha256"]
			and instance.sprite.texture is ImageTexture and instance.sprite.texture.get_width() > saved_normal.get_width(),
			"Photo chooses the reviewed full mesh and a higher-resolution Pixel image")
	else:
		var detail: Node3D = world.presentation.tracked["hero"]["detail"]
		check(is_instance_valid(detail) and not instance.get_node("Model").visible and detail.global_transform.is_equal_approx(instance.global_transform),
			"Photo shows full geometry outside the canonical instance with identical transform")
		check(not instance.is_ancestor_of(detail) and instance.get_node("CollisionShape3D").disabled,
			"Photo detail does not enter placement or collision queries")
	if "--capture" in OS.get_cmdline_user_args():
		check(await photo.screenshot(output+"/photo_"+mode+".png") == OK,"Captured actual Photo detail "+mode)
	photo.stop()
	await drawn()
	if mode == "2d":
		check(not instance.photo_quality and instance.sprite.texture == saved_normal,"Exiting Photo restores the regular Pixel projection")
	else:
		check(instance.get_node("Model").visible and world.presentation.tracked["hero"]["detail"] == null,
			"Exiting Photo restores regular Model geometry and releases the extra branch")
	check(doc.data == source_record,"Projection, visibility and Photo leave authored records exact "+mode)
	var save: String = output+"/rendering_"+mode+".isocity.json"
	check(studio.write_project(save,false),"Normal Save writes the fixture "+mode)
	var reopened: Dictionary = preload("res://scripts/builder/project_repair.gd").new(studio.library).read(save)
	check(reopened["ok"] and reopened["content"]["documents"][mode]["objects"].size() == 4
		and reopened["content"]["documents"][mode]["objects"][0]["asset"] == SHIP,"Saved layout keeps original asset IDs "+mode)
	if "--portable" in OS.get_cmdline_user_args():
		var result: Dictionary = Portable.new().save(world,doc.data,studio.library,output+"/rendering_"+mode+".zip")
		check(result["ok"],"The allowed fixture packages both editions "+mode+" "+result.get("message",""))

func paint_hit(instance: Node, item: Dictionary) -> Dictionary:
	var sprite: Sprite2D = instance.sprite
	var picture: Image = sprite.texture.get_image()
	for y in range(0,picture.get_height(),7):
		for x in range(0,picture.get_width(),7):
			if picture.get_pixel(x,y).a < .9: continue
			var target: Vector2 = studio.viewport.canvas_transform*sprite.to_global(sprite.get_rect().position+Vector2(x,y))
			var hit: Dictionary = studio.color_editor.pick_instance(instance,item,target,true)
			if not hit.is_empty(): return hit
	return {}

func browser() -> void:
	var library: RefCounted = studio.library
	library.invalidate_icons(SHIP)
	var texture: Texture2D = library.icon(SHIP)
	var ids: Array = library.assets.keys().filter(func(id: String)->bool: return id.begins_with("3d:"))
	ids.sort()
	for id in ids.slice(0,320): library.icon(id)
	check(library.icons.size() <= library.ICON_LIMIT and library.icon(SHIP) != null,"Thumbnail cache evicts while the requested ship remains reloadable")
	library.invalidate_icons(SHIP)
	check(library.icon(SHIP) != texture,"Explicit asset refresh invalidates the old thumbnail")
	studio.asset_browser.show_asset(SHIP)
	await frames()
	check(studio.asset_browser.details.text.contains("Approximate mesh cost") and
		studio.asset_browser.details.text.contains("Frame cost depends"),"Asset inspector labels the mesh estimate and its uncertainty")
	if "--capture" not in OS.get_cmdline_user_args(): return
	for simple in [false,true]:
		studio.asset_browser.dialog.hide()
		studio.consumer_shell.set_active(simple,false)
		studio.consumer_shell.dismiss_welcome()
		for size in [Vector2i(1480,900),Vector2i(960,640)]:
			root.size = size
			studio.accessibility_settings.restore({"text_scale":1.5,"high_contrast":true,"large_targets":true} if size.x == 960 else {})
			if not studio.asset_browser.dialog.visible: studio.asset_browser.show_asset(SHIP)
			await drawn()
			var dialog: Window = studio.asset_browser.dialog
			var toggle: Control = studio.asset_browser.scale_preview.toggle
			toggle.grab_focus()
			await drawn()
			check(Rect2i(Vector2i.ZERO,size).encloses(Rect2i(dialog.position,dialog.size)) and toggle.has_focus(),
				"The resized inspector fits and takes keyboard focus "+str([simple,size]))
			var path: String = output+"/cost_%s_%d.png"%["simple" if simple else "precision",size.x]
			check(root.get_texture().get_image().save_png(path) == OK,"Captured the rendering estimate "+path)

func policy_edges() -> void:
	var sample := MeshInstance3D.new()
	sample.mesh = BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sample.material_override = material
	check(not Budget.static_visual(sample,true),"Transparent model geometry is excluded from small-object hiding")
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	sample.add_child(AnimationPlayer.new())
	check(not Budget.static_visual(sample),"Animated scenes retain their own renderer")
	sample.free()
	check(Budget.make_detail({"full":{"path":"res://assets/missing_rendering_fixture.glb"}}) == null,"Missing Photo geometry falls back to the canonical edition")
	var pool: Node = studio.worlds["2d"].projection_pool
	var image := Image.create_empty(8,8,false,Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	for index in pool.MAX_ENTRIES+20:
		pool.store("budget-fixture-"+str(index),texture,1024*1024)
	check(pool.entries.size() <= pool.MAX_ENTRIES and pool.bytes <= pool.MAX_BYTES
		and not pool.entries.has("budget-fixture-0"),"Projected texture cache evicts and stays inside both budgets")
