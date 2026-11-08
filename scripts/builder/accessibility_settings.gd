extends RefCounted

const PATH = "user://studio_accessibility.json"
const SCALES = [1.0,1.15,1.3,1.5]
const FONT_KEYS = ["font_size","normal_font_size","bold_font_size","italics_font_size","bold_italics_font_size","mono_font_size"]
var studio: Control
var settings_path: String = PATH
var text_scale: float = 1.0
var high_contrast: bool = false
var large_targets: bool = false
var shape_markers: bool = true
var dialog: AcceptDialog
var scale_choice: OptionButton
var contrast_toggle: CheckButton
var targets_toggle: CheckButton
var markers_toggle: CheckButton
var notice: Label
var root_scroll: ScrollContainer
var margin: Control
var original_theme: Theme
var changing: bool = false
var text_nodes: Array[WeakRef] = []

func _init(host: Control) -> void:
	studio=host
	original_theme=studio.theme.duplicate(true)
	build_dialog()
	var entry: Button=studio.control_settings.dialog.add_button("Accessibility…",false,"accessibility")
	entry.tooltip_text="Text size, contrast, click targets and selection markers"
	studio.control_settings.dialog.custom_action.connect(func(action: String):
		if action=="accessibility": studio.control_settings.dialog.hide(); show())
	if studio.storage_enabled: restore(studio.Store.read_json(settings_path,{}),false)
	studio.get_tree().node_added.connect(on_node_added)
	studio.tree_exiting.connect(shutdown)

func on_node_added(node: Node) -> void:
	if not node is Control or not studio.is_ancestor_of(node): return
	var parent: Node=node.get_parent()
	while parent and parent!=studio:
		if parent is SubViewport: return
		parent=parent.get_parent()
	call_deferred("apply_new_control",node.get_instance_id())

func apply_new_control(id: int) -> void:
	var node: Object=instance_from_id(id)
	if is_instance_valid(node) and node is Control: apply_control(node)

func shutdown() -> void:
	if studio.get_tree().node_added.is_connected(on_node_added): studio.get_tree().node_added.disconnect(on_node_added)

func settings() -> Dictionary:
	return {"text_scale":text_scale,"high_contrast":high_contrast,"large_targets":large_targets,"shape_markers":shape_markers}

func restore(value: Variant,refresh: bool = true) -> void:
	var data: Dictionary=value if value is Dictionary else {}
	text_scale=1.0
	var scale: Variant=data.get("text_scale",1.0)
	if (scale is int or scale is float) and is_finite(float(scale)) and float(scale) in SCALES: text_scale=float(scale)
	high_contrast=data.get("high_contrast",false) if data.get("high_contrast",false) is bool else false
	large_targets=data.get("large_targets",false) if data.get("large_targets",false) is bool else false
	shape_markers=data.get("shape_markers",true) if data.get("shape_markers",true) is bool else true
	if refresh: apply()

func persist() -> void:
	if studio.storage_enabled and not studio.Store.write_json(settings_path,settings()):
		notice.text="Applied for this session. Preferences could not be saved to disk."
	else: notice.text="Preferences apply to both worlds and are separate from saved cities."

func change() -> void:
	if changing: return
	text_scale=SCALES[scale_choice.selected]
	high_contrast=contrast_toggle.button_pressed
	large_targets=targets_toggle.button_pressed
	shape_markers=markers_toggle.button_pressed
	apply(); persist()

func build_dialog() -> void:
	dialog=AcceptDialog.new(); dialog.title="Accessibility"; dialog.size=Vector2i(650,490)
	dialog.get_ok_button().text="Close"
	studio.add_child(dialog)
	var scroll:=ScrollContainer.new()
	scroll.custom_minimum_size=Vector2(560,350)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus=true
	dialog.add_child(scroll)
	var box:=VBoxContainer.new(); box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; box.add_theme_constant_override("separation",12); scroll.add_child(box)
	var title:=Label.new(); title.text="Make Studio easier to see and use"; box.add_child(title)
	var label:=Label.new(); label.text="Text size"; box.add_child(label)
	scale_choice=OptionButton.new()
	for percent in [100,115,130,150]: scale_choice.add_item(str(percent)+"%")
	box.add_child(scale_choice)
	contrast_toggle=CheckButton.new(); contrast_toggle.text="Stronger contrast"; box.add_child(contrast_toggle)
	targets_toggle=CheckButton.new(); targets_toggle.text="Larger click targets (at least 44 pixels)"; box.add_child(targets_toggle)
	markers_toggle=CheckButton.new(); markers_toggle.text="Shapes and numbers for selection"; box.add_child(markers_toggle)
	var help:=Label.new(); help.text="Larger settings can add scrolling to the editor and dialogs. Selection brackets, numbered badges and warning symbols remain readable without color. Asset artwork and exported scenes keep their original appearance."
	help.custom_minimum_size.x=540; help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; box.add_child(help)
	notice=Label.new(); notice.custom_minimum_size.x=540; notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; box.add_child(notice)
	var reset:=Button.new(); reset.text="Restore accessibility defaults"; box.add_child(reset)
	reset.pressed.connect(func(): restore({}); persist())
	scale_choice.item_selected.connect(func(_index: int): change())
	for toggle in [contrast_toggle,targets_toggle,markers_toggle]: toggle.toggled.connect(func(_on: bool): change())

func show() -> void:
	studio.control_settings.finish_drag()
	apply()
	notice.text="Preferences apply to both worlds and are separate from saved cities."
	dialog.popup_centered(Vector2i(mini(760,studio.get_viewport_rect().size.x-40),mini(540,studio.get_viewport_rect().size.y-60)))
	scale_choice.grab_focus()

func apply() -> void:
	changing=true
	scale_choice.select(maxi(0,SCALES.find(text_scale)))
	contrast_toggle.set_pressed_no_signal(high_contrast)
	targets_toggle.set_pressed_no_signal(large_targets)
	markers_toggle.set_pressed_no_signal(shape_markers)
	var theme: Theme=original_theme.duplicate(true)
	theme.default_font_size=roundi(original_theme.default_font_size*text_scale)
	if high_contrast: contrast_theme(theme)
	if large_targets:
		for type in ["Tree","PopupMenu"]: theme.set_constant("v_separation",type,32)
		for type in ["Button","OptionButton","CheckBox","CheckButton","LineEdit","SpinBox","TabBar","ItemList","PopupMenu","HSlider","VSlider","HScrollBar","VScrollBar"]:
			theme.set_constant("minimum_grab_thickness",type,24)
		for state in ["normal","hover","pressed","focus","disabled"]:
			var style: StyleBox=theme.get_stylebox(state,"Button")
			if style:
				style=style.duplicate(); style.content_margin_top=maxf(style.content_margin_top,12); style.content_margin_bottom=maxf(style.content_margin_bottom,12)
				theme.set_stylebox(state,"Button",style)
	studio.theme=theme
	configure_scrolling()
	text_nodes.clear()
	apply_tree(studio)
	studio.overlay.accessible_markers=shape_markers
	studio.overlay.high_contrast=high_contrast
	studio.overlay.text_scale=text_scale
	studio.overlay.queue_redraw()
	studio.control_settings.marker.queue_redraw()
	changing=false
	studio.workspace_layout.call_deferred("refresh")
	call_deferred("fit_dialogs")

func configure_scrolling() -> void:
	if not root_scroll:
		margin=studio.workspace_presets.header.get_parent().get_parent()
		var index: int=margin.get_index()
		root_scroll=ScrollContainer.new(); root_scroll.name="AccessibleEditorScroll"
		root_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root_scroll.follow_focus=true
		studio.add_child(root_scroll); studio.move_child(root_scroll,index)
		margin.reparent(root_scroll)
		margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		margin.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		margin.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var expanded: bool=text_scale>1.0 or large_targets
	root_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO if expanded else ScrollContainer.SCROLL_MODE_DISABLED
	root_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO if expanded else ScrollContainer.SCROLL_MODE_DISABLED
	studio.canvas.custom_minimum_size=Vector2(300,280) if expanded else Vector2.ZERO
	if not expanded: root_scroll.scroll_horizontal=0; root_scroll.scroll_vertical=0

func contrast_theme(theme: Theme) -> void:
	for key in ["icon_normal_color","icon_hover_color","icon_pressed_color","icon_focus_color"]: theme.set_color(key,"Button",Color.WHITE)
	theme.set_color("icon_disabled_color","Button",Color("9aabbc"))
	for type in ["Button","OptionButton","CheckBox","CheckButton","Label","RichTextLabel","LineEdit","TextEdit","SpinBox","ItemList","TabBar","TabContainer","PopupMenu","Tree","TooltipLabel","Window"]:
		for name in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_selected_color","default_color","title_color","font_hovered_color","font_unselected_color"]: theme.set_color(name,type,Color.WHITE)
		theme.set_color("font_disabled_color",type,Color("c4c4c4"))
		theme.set_color("font_uneditable_color",type,Color("c4c4c4"))
		theme.set_color("font_placeholder_color",type,Color("c4c4c4"))
		theme.set_color("selection_color",type,Color("275a91"))
		theme.set_color("caret_color",type,Color.WHITE)
	for type in ["Button","OptionButton","CheckBox","CheckButton","LineEdit","TextEdit","ItemList","Tree","TabContainer","TabBar","PopupMenu","PanelContainer","AcceptDialog"]:
		for state in ["normal","read_only","hover","pressed","disabled","panel","tab_selected","tab_unselected","selected","focus","hover_focus"]:
			var style:=StyleBoxFlat.new()
			style.bg_color=Color("090d12") if not state in ["pressed","selected","tab_selected"] else Color("183e64")
			style.border_color=Color.WHITE if state in ["focus","hover_focus","pressed","selected","tab_selected"] else Color("9aabbc")
			style.set_border_width_all(3 if state in ["focus","hover_focus"] else 1)
			if state in ["focus","hover_focus"]: style.bg_color.a=0
			style.set_corner_radius_all(4)
			style.content_margin_left=10; style.content_margin_right=10; style.content_margin_top=8; style.content_margin_bottom=8
			theme.set_stylebox(state,type,style)

func apply_tree(node: Node) -> void:
	if node is Control: apply_control(node)
	for child in node.get_children():
		# Scene artwork is outside the editor UI, including model preview viewports.
		if not child is SubViewport: apply_tree(child)

func apply_control(control: Control) -> void:
	if not is_instance_valid(control) or control.is_queued_for_deletion(): return
	if not control.has_meta("a11y_original"):
		var fonts: Dictionary={}
		for key in FONT_KEYS:
			if control.has_theme_font_size_override(key): fonts[key]=control.get_theme_font_size(key)
		var styles: Dictionary={}
		for key in ["panel","normal","read_only","hover","pressed","focus","disabled"]:
			if control.has_theme_stylebox_override(key): styles[key]=control.get_theme_stylebox(key).duplicate(true)
		var original: Dictionary={"fonts":fonts,"styles":styles,"minimum":control.custom_minimum_size,"modulate":control.modulate,"focus":control.focus_mode}
		if control is ItemList:
			original["icons"]=control.fixed_icon_size; original["separation"]=control.get_theme_constant("v_separation")
		control.set_meta("a11y_original",original)
	var original: Dictionary=control.get_meta("a11y_original")
	for key in original["fonts"]: control.add_theme_font_size_override(key,roundi(original["fonts"][key]*text_scale))
	for key in original["styles"]:
		var style: StyleBox=original["styles"][key].duplicate(true)
		if high_contrast and style is StyleBoxFlat:
			style.bg_color=Color("090d12"); style.border_color=Color("9aabbc"); style.set_border_width_all(1)
		control.add_theme_stylebox_override(key,style)
	if control is Label or control is RichTextLabel:
		if not control.has_meta("a11y_text_registered") or changing:
			text_nodes.append(weakref(control)); control.set_meta("a11y_text_registered",true)
		control.modulate=Color.WHITE if high_contrast else original["modulate"]
	if control is BaseButton or control is LineEdit or control is TextEdit or control is SpinBox or control is Slider or control is ScrollBar or control is TabBar:
		var minimum: Vector2=original["minimum"]
		if not control.get_script()==preload("res://scripts/builder/asset_card.gd"): minimum.x*=text_scale
		control.custom_minimum_size=Vector2(maxf(minimum.x,44),maxf(minimum.y,44)) if large_targets else minimum
		if control is BaseButton and large_targets: control.focus_mode=Control.FOCUS_ALL
		else: control.focus_mode=original["focus"]
	if control is ItemList:
		control.add_theme_constant_override("v_separation",32 if large_targets else original["separation"])
		control.fixed_icon_size=Vector2i(28,28) if large_targets else original["icons"]
	if control is Button and control.get_parent() and control.get_parent().get_script()==preload("res://scripts/builder/asset_card.gd"):
		var card: Button=control.get_parent()
		card.reflow(studio.thumbnail_size,text_scale)
	if control is Label and control.get_parent() and control.get_parent().get_script()==preload("res://scripts/builder/asset_card.gd"):
		# Header actions and scaled names have their own space around the artwork.
		var card: Button=control.get_parent()
		card.reflow(studio.thumbnail_size,text_scale)
	control.queue_redraw()

func tick() -> void:
	if high_contrast:
		for i in range(text_nodes.size()-1,-1,-1):
			var node: Node=text_nodes[i].get_ref()
			if is_instance_valid(node): node.modulate=Color.WHITE
			else: text_nodes.remove_at(i)

func fit_dialogs() -> void:
	# Dialog bodies scroll when enlarged; confirmation controls stay outside the scroll area.
	for window in studio.get_children():
		if not window is AcceptDialog or window==dialog: continue
		if not window.has_meta("a11y_window_size"):
			window.set_meta("a11y_window_size",window.size); window.set_meta("a11y_window_minimum",window.min_size)
		var expanded: bool=text_scale>1.0 or large_targets
		var scroll: ScrollContainer=window.get_node_or_null("AccessibleDialogScroll")
		if not expanded and scroll:
			var body: Node=scroll.get_child(0)
			body.reparent(window)
			window.remove_child(scroll); scroll.queue_free()
			window.min_size=window.get_meta("a11y_window_minimum")
			window.size=window.get_meta("a11y_window_size")
			continue
		if expanded and not scroll:
			var body: Control=null
			for child in window.get_children():
				if child is VBoxContainer: body=child; break
			if not body: continue
			scroll=ScrollContainer.new(); scroll.name="AccessibleDialogScroll"; scroll.follow_focus=true
			scroll.custom_minimum_size=Vector2(560,300)
			window.add_child(scroll); body.reparent(scroll); body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		if scroll:
			scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO if expanded else ScrollContainer.SCROLL_MODE_DISABLED
			scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO if expanded else ScrollContainer.SCROLL_MODE_DISABLED
			if expanded:
				window.min_size=Vector2i.ZERO
				window.size=Vector2i(mini(780,studio.get_viewport_rect().size.x-40),mini(560,studio.get_viewport_rect().size.y-60))
