extends SceneTree
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for i in 5: await process_frame
func capture(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/"+name+".png")
func run() -> void:
	var studio: Control=load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled=false
	root.add_child(studio)
	await settle()
	var browser: RefCounted=studio.asset_browser
	studio.asset_type.select(1)
	studio.populate_categories()
	for i in studio.category.item_count:
		if studio.category.get_item_text(i)=="Buildings": studio.category.select(i)
	studio.pack_filter="Pixel Isometric"
	studio.search.text="coffee"
	studio.favorites.assign(["2d:Coffee_Shop"])
	studio.favorites_only.button_pressed=true
	studio.refresh_library()
	check(browser.chips.get_child_count()==5,"All active filters have removable chips")
	check(studio.cards.get_child_count()==1 and studio.cards.get_child(0).asset_id=="2d:Coffee_Shop","Combined type/category/pack/favorites/query filters find the right asset")
	await capture("editor_asset_filter_chips")
	for key in ["type","category","pack","favorites","query"]:
		browser.chips.get_node(key).pressed.emit()
		check(not browser.chips.has_node(key),"Removing a chip clears only that filter: "+key)
		if key=="type": check(studio.category.get_item_text(studio.category.selected)=="Buildings" and studio.pack_filter=="Pixel Isometric" and studio.favorites_only.button_pressed,"Removing type preserves category, pack and favorites")
	check(not browser.chips.visible and studio.cards.get_child_count()>1,"Removing all chips restores broad browsing")
	var panel_width: float=studio.mode_library.size.x
	for pair in [[0,96],[1,128],[2,192]]:
		browser.sizes.select(pair[0])
		browser.sizes.item_selected.emit(pair[0])
		await settle()
		var card: Button=studio.cards.get_child(0)
		check(card.custom_minimum_size.x==pair[1] and card.get_child(0).size.x==pair[1]-20,"Thumbnail choice resizes card and image: "+str(pair[1]))
		check(absf(studio.mode_library.size.x-panel_width)<2,"Changing thumbnail size does not resize the library panel")
		card.pressed.emit()
		check(studio.asset_id==card.asset_id and card.preview_texture!=null,"Resized cards retain asset selection and preview data")
	await capture("editor_asset_large_cards")
	studio.pack_filter="HanX_Park"
	studio.refresh_library()
	for card in studio.cards.get_children(): check(studio.library.pack_name(studio.library.assets[card.asset_id])=="HanX_Park","Pack filter excludes other packs")
	studio.capture_workspace()
	studio.switch_mode("3d")
	await settle()
	check(studio.pack_filter.is_empty() and studio.thumbnail_size==128,"Other world has independent browser defaults")
	studio.switch_mode("2d")
	await settle()
	check(studio.pack_filter=="HanX_Park" and studio.thumbnail_size==192,"Browser preferences restore per world")
	var path: String="user://asset_browser_test.isocity.json"
	check(studio.write_project(path),"Browser preferences save in a project")
	browser.restore({})
	check(studio.load_project(path),"Project with browser preferences reopens")
	check(studio.pack_filter=="HanX_Park" and studio.thumbnail_size==192 and not studio.repair_tools.dialog.visible,"JSON round trip restores large thumbnails and pack without a spurious repair")
	var source: Dictionary=studio.current().data.duplicate(true)
	var current_asset: String=studio.asset_id
	browser.show_asset("2d:Coffee_Shop")
	check(studio.modal_visible() and browser.picture.visible and browser.views.item_count==2,"Expanded sprite preview blocks world input and exposes source directions")
	check(browser.details.text.contains("Pack:") and browser.details.text.contains("px per frame") and browser.details.text.contains("footprint"),"Sprite preview explains dimensions, pack and footprint")
	var first_texture: Texture2D=browser.atlas.atlas
	browser.views.select(1)
	browser.views.item_selected.emit(1)
	check(browser.atlas.atlas!=first_texture,"Preview direction switches real source artwork")
	await settle()
	check(browser.dialog.position.y>=0 and browser.dialog.position.y+browser.dialog.size.y<=root.size.y,"First preview opens within the window after metadata layout settles")
	await capture("editor_asset_sprite_preview")
	browser.dialog.hide()
	check(studio.current().data==source and studio.asset_id==current_asset,"Inspecting and closing leaves placement and document unchanged")
	browser.show_asset("2d:Added_animated_boat_9ee9b341")
	check(browser.frames==51 and browser.play.visible,"Expanded imported animation uses all frames")
	browser.tick(0.2)
	check(int(browser.frame.value)>0 and browser.atlas.region.position.x>0,"Animation playback advances actual atlas frames")
	browser.play.button_pressed=false
	var paused: float=browser.frame.value
	browser.tick(1)
	check(browser.frame.value==paused,"Animation can pause")
	browser.frame.value=12
	check(int(browser.atlas.region.position.x)==12*int(browser.frame_size.x),"Animation frames can be scrubbed")
	await capture("editor_asset_animation_preview")
	browser.dialog.hide()
	browser.show_asset("3d:HanX_Park/Bench_Park")
	check(browser.pivot.get_child_count()==1 and browser.model_container.visible and not browser.picture.visible,"Expanded model preview instantiates an isolated real model")
	check(browser.details.text.contains("Dimensions:") and browser.details.text.contains("HanX_Park"),"Model preview reports measured dimensions and pack")
	var rotation_before: float=browser.pivot.rotation_degrees.y
	browser.orbit_row.get_child(1).pressed.emit()
	check(is_equal_approx(browser.pivot.rotation_degrees.y,rotation_before+45),"Model preview can turn around the asset")
	await capture("editor_asset_model_preview")
	browser.dialog.hide()
	check(browser.model_world==null and browser.picture.texture==null,"Closing the preview releases its model and texture")
	root.size=Vector2i(960,640)
	await settle()
	check(studio.mode_library.get_global_rect().end.y<=root.size.y and studio.canvas.size.y>120,"Library filters and cards remain inside the minimum editor window")
	await capture("editor_asset_browser_small")
	browser.show_asset("2d:Office_Worker")
	await settle()
	check(browser.dialog.position.x>=0 and browser.dialog.position.y>=0 and browser.dialog.position.x+browser.dialog.size.x<=root.size.x and browser.dialog.position.y+browser.dialog.size.y<=root.size.y,"Expanded preview stays within a small window")
	await capture("editor_asset_preview_small")
	browser.dialog.hide()
	studio.free()
	print("ASSET BROWSER: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
