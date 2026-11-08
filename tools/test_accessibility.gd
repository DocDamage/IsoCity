extends SceneTree
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for i in 10: await process_frame
	await physics_frame
func capture(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await settle(); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/"+name+".png")
func ratio(a: Color,b: Color) -> float:
	var x: float=a.srgb_to_linear().get_luminance()
	var y: float=b.srgb_to_linear().get_luminance()
	return (maxf(x,y)+.05)/(minf(x,y)+.05)
func run() -> void:
	var studio: Control=load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled=false
	root.add_child(studio); await settle()
	var settings: RefCounted=studio.accessibility_settings
	var original: Dictionary=studio.current().data.duplicate(true)
	var history: int=studio.current().undo_history.size()
	var layout: Dictionary=studio.workspace_layout.settings().duplicate(true)
	var title: Label=studio.selected_name
	var base_font: int=title.get_theme_font_size("font_size")
	var base_size: Vector2=studio.undo_button.custom_minimum_size
	check(settings.settings()=={"text_scale":1.0,"high_contrast":false,"large_targets":false,"shape_markers":true},"Accessibility has explicit safe defaults with noncolor markers enabled")
	for scale in settings.SCALES:
		settings.restore({"text_scale":scale})
		await settle()
		check(title.get_theme_font_size("font_size")==roundi(base_font*scale),"Explicit heading sizes scale: "+str(scale))
		check(studio.undo_button.get_theme_font_size("font_size")==roundi(14*scale),"Inherited button text scales: "+str(scale))
		check(studio.overlay.caption_font_size()==roundi(13*scale),"Canvas captions scale: "+str(scale))
	settings.restore({"text_scale":1.5,"high_contrast":true,"large_targets":true,"shape_markers":true})
	await settle()
	check(studio.undo_button.get_combined_minimum_size().y>=44 and studio.search.get_combined_minimum_size().y>=44,"Buttons and text entry offer larger click targets")
	check(studio.height_input.get_combined_minimum_size().y>=44 and settings.scale_choice.get_combined_minimum_size().y>=44,"Numeric controls and option selectors offer larger targets")
	for i in studio.workspace_layout.tabs.get_tab_count():
		if studio.workspace_layout.tabs.get_tab_title(i)=="Scene": studio.workspace_layout.tabs.current_tab=i
	studio.scene_outliner.refresh(true); await settle()
	var row: TreeItem=studio.scene_outliner.tree.get_root().get_first_child()
	check(studio.scene_outliner.tree.get_item_area_rect(row).size.y>=44,"Outliner object rows offer enlarged click targets")
	check(studio.undo_button.focus_mode==Control.FOCUS_ALL,"Enlarged toolbar controls support keyboard focus")
	studio.undo_button.grab_focus()
	var tab:=InputEventKey.new(); tab.pressed=true; tab.keycode=KEY_TAB
	check(not studio.control_settings.input(tab) and not studio.control_settings.unhandled(tab) and not studio.walking,"Tab navigates focused UI controls without switching to Walk")
	studio.control_settings.execute("cancel")
	check(root.gui_get_focus_owner()==null,"Cancel releases control focus back to the canvas")
	studio.undo_button.grab_focus(); studio.set_walking(true)
	check(root.gui_get_focus_owner()==null,"Entering Walk returns keyboard control to the character")
	studio.set_walking(false)
	check(studio.overlay.accessible_markers and studio.overlay.high_contrast,"Shape markers and high contrast reach the actual canvas overlay")
	var color: Color=studio.undo_button.get_theme_color("font_color")
	var style: StyleBoxFlat=studio.undo_button.get_theme_stylebox("normal")
	check(ratio(color,style.bg_color)>=7,"Strong contrast uses at least 7:1 button text contrast")
	check(ratio(studio.undo_button.get_theme_color("font_disabled_color"),style.bg_color)>=7,"Disabled button labels remain readable")
	check(studio.asset_count.modulate==Color.WHITE,"Dim secondary text becomes full contrast")
	check(studio.mode_library.get_theme_stylebox("panel").bg_color==Color("090d12"),"Locally styled panels adopt the stronger-contrast background")
	var dynamic:=Label.new(); dynamic.text="Dynamic text"; dynamic.add_theme_font_size_override("font_size",12); dynamic.modulate=Color("8daabe"); studio.add_child(dynamic)
	await settle()
	check(dynamic.get_theme_font_size("font_size")==18 and dynamic.modulate==Color.WHITE,"Controls created after applying preferences inherit scaling and contrast")
	dynamic.queue_free()
	var tracked_before: int=settings.text_nodes.size()
	for i in 30:
		var transient:=Label.new(); studio.add_child(transient); transient.free()
	await settle()
	check(settings.text_nodes.size()<=tracked_before,"Freed transient controls do not accumulate in the accessibility cache")
	var asset_label:=Label.new(); asset_label.add_theme_font_size_override("font_size",12); asset_label.modulate=Color("8daabe")
	studio.viewport.add_child(asset_label); await settle()
	check(asset_label.get_theme_font_size("font_size")==12 and asset_label.modulate==Color("8daabe"),"Scene viewport controls keep their original artwork styling")
	asset_label.queue_free()
	studio.refresh_library(); await settle()
	var card: Button=studio.cards.get_child(0)
	var favorite: Button=null
	var preview: Button=null
	for child in card.get_children():
		if child is Button and child.text in ["★","☆"]: favorite=child
		if child is Button and child.text=="⋯": preview=child
	check(favorite.get_combined_minimum_size().y>=44 and preview.get_combined_minimum_size().y>=44,"New asset-card actions receive larger targets")
	check(favorite.position.x+favorite.get_combined_minimum_size().x<=card.custom_minimum_size.x,"Favorite target stays inside its card")
	check(studio.current().data==original and studio.current().undo_history.size()==history,"Accessibility settings leave city content and undo history unchanged")
	check(studio.workspace_layout.settings()==layout,"Accessibility preserves the chosen panel preferences")
	settings.settings_path="res://output/accessibility_preferences_test.json"
	studio.storage_enabled=true; settings.persist(); studio.storage_enabled=false
	var saved: Variant=studio.Store.read_json(settings.settings_path,{})
	settings.restore({}); settings.restore(saved); await settle()
	check(settings.text_scale==1.5 and settings.high_contrast and settings.large_targets,"Written user preferences restore all accessibility options")
	settings.restore({"text_scale":"huge","large_targets":1,"high_contrast":[],"shape_markers":"yes"}); await settle()
	check(settings.text_scale==1.0 and not settings.large_targets and not settings.high_contrast and settings.shape_markers,"Malformed settings fall back to valid defaults")
	check(title.get_theme_font_size("font_size")==base_font and studio.undo_button.custom_minimum_size==base_size,"Default restoration reverses scaling and click-target overrides")
	check(studio.asset_count.modulate==Color("8daabe"),"Default restoration restores the secondary-text style")
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		studio.clear_placement()
		studio.selected_uids.clear()
		for item in studio.current().data["objects"]:
			if studio.Layers.editable(studio.current().data,item,studio.library):
				studio.selected_uids.append(item["uid"])
				if studio.selected_uids.size()==2: break
		studio.selected_uid=studio.selected_uids[0]
		studio.refresh_controls()
		settings.restore({"text_scale":1.3,"high_contrast":true,"large_targets":true,"shape_markers":true}); await settle()
		studio.update_overlay(false)
		check(studio.overlay.boxes.size()==2 and studio.overlay.accessible_markers,"Both selected objects have numbered shape indicators: "+mode)
		check(studio.overlay.caption_style().bg_color==Color.BLACK,"High-contrast captions use an opaque background: "+mode)
		studio.set_walking(true); await settle()
		check(studio.mode_badge.modulate==Color.WHITE,"Mode changes retain readable text contrast: "+mode)
		studio.set_walking(false)
		studio.workspace_presets.set_focus(true); await settle()
		await capture("editor_accessibility_selection_"+mode)
		if mode=="2d":
			studio.clear_placement(); studio.selected_cell=Vector2i.ZERO
			studio.refresh_controls(); studio.update_overlay(false)
			check(studio.overlay.tile_outline.size()==4,"Ground-cell selection has a distinct outlined shape")
			await capture("editor_accessibility_ground_selection")
		studio.workspace_presets.set_focus(false)
	settings.restore({"text_scale":1.5,"high_contrast":true,"large_targets":true,"shape_markers":true})
	root.size=Vector2i(960,640); await settle()
	check(root.min_size==Vector2i(960,640),"Large accessibility settings preserve the supported minimum window size")
	check(settings.root_scroll.size.x<=960 and settings.root_scroll.size.y<=640 and studio.canvas.size.y>=280,"Root scrolling keeps a usable canvas at the minimum window size")
	settings.root_scroll.ensure_control_visible(studio.canvas); await settle()
	check(settings.root_scroll.get_v_scroll_bar().max_value>640,"Oversized editor content is reachable through scrolling")
	await capture("editor_accessibility_small_canvas")
	settings.show(); await settle()
	check(settings.dialog.size.x<=960 and settings.dialog.size.y<=600,"Accessibility settings fit at 150% text and large targets in a small window")
	await capture("editor_accessibility_settings")
	settings.dialog.hide()
	studio.control_settings.show(); await settle()
	check(studio.control_settings.dialog.size.x<=960 and studio.control_settings.dialog.size.y<=600,"Shortcut reference remains bounded with enlarged text")
	check(studio.control_settings.rows.get_item_rect(0).size.y>=44,"Shortcut reference rows offer enlarged click targets")
	await capture("editor_accessibility_controls")
	studio.control_settings.dialog.hide()
	settings.restore({}); await settle()
	check(studio.control_settings.dialog.get_node_or_null("AccessibleDialogScroll")==null,"Restoring defaults removes temporary dialog scroll wrappers")
	settings.show(); await settle()
	check(settings.dialog.size.x<=960 and settings.dialog.size.y<=600,"Default settings remain reachable after returning from enlarged text")
	settings.dialog.hide()
	settings.shape_markers=false; settings.apply()
	check(not studio.overlay.accessible_markers,"Shape markers can be configured independently")
	var event:=InputEventKey.new(); event.pressed=true; event.keycode=KEY_F2
	studio._input(event)
	check(settings.dialog.visible,"Accessibility settings have a direct keyboard entry point")
	settings.dialog.hide()
	studio.queue_free(); await process_frame
	print("ACCESSIBILITY: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
