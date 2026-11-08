extends RefCounted

const Layers = preload("res://scripts/builder/layers.gd")
var studio: Control
var breadcrumb: Label
var affected: Label
var field_notes: Dictionary = {}
var base_tooltips: Dictionary = {}
var view_note: Label
var mixed: Dictionary = {}
var revisions: Dictionary = {}
var focus_revisions: Dictionary = {}
var typed: Dictionary = {}
var context_key: String = ""
var mixed_labels: Dictionary = {}

func _init(host: Control, center: Node) -> void:
	studio = host
	breadcrumb = studio.label(center,"",12)
	breadcrumb.name = "SelectionContext"
	breadcrumb.clip_text = true
	breadcrumb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	center.move_child(breadcrumb,1)
	affected = studio.label(studio.height_input.get_parent(),"",12)
	affected.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	studio.height_input.get_parent().move_child(affected,studio.height_input.get_index()-1)
	for key in ["height","scale","angle","pitch","roll"]:
		var input: SpinBox = field(key)
		var row: Node = input.get_parent()
		var note: Label = studio.label(row,"",11)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if row is HBoxContainer:
			row.remove_child(note)
			var wrapper := VBoxContainer.new()
			var parent: Node = row.get_parent()
			var index: int = row.get_index()
			parent.add_child(wrapper)
			parent.move_child(wrapper,index)
			row.reparent(wrapper)
			wrapper.add_child(note)
			if key in ["pitch","roll"]:
				var advanced_index: int = studio.workspace_layout.advanced_controls.find(row)
				if advanced_index>=0: studio.workspace_layout.advanced_controls[advanced_index] = wrapper
				wrapper.visible = row.visible
				row.show()
		else: row.move_child(note,input.get_index()+1)
		field_notes[key] = note
		base_tooltips[key] = input.tooltip_text
		var mixed_label := Label.new()
		mixed_label.text = "Mixed"
		mixed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		input.get_line_edit().add_child(mixed_label)
		mixed_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mixed_label.offset_left = 6
		mixed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mixed_label.hide()
		mixed_labels[key] = mixed_label
		input.get_line_edit().focus_entered.connect(func():
			focus_revisions[key] = revisions.get(key,0)
			typed[key] = false
			render_mixed(key)
			if mixed.get(key,false): input.get_line_edit().select_all()
		)
		input.value_changed.connect(func(_value: float): revisions[key] = revisions.get(key,0)+1)
		input.get_line_edit().text_changed.connect(func(_text: String): typed[key] = true)
		input.get_line_edit().text_submitted.connect(func(_text: String): commit_unchanged(key,true))
		input.get_line_edit().focus_exited.connect(func(): commit_unchanged(key); call_deferred("render_mixed",key))
	view_note = studio.label(studio.view_choice.get_parent(),"",11)
	view_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	studio.view_choice.get_parent().move_child(view_note,studio.view_choice.get_index()+1)

func commit_unchanged(key: String, submitted: bool = false) -> void:
	# SpinBox emits no value_changed when the entered value equals the active
	# object's value. Absolute fields must still update the other mixed objects.
	if key not in ["height","pitch","roll"] or not mixed.get(key,false): return
	if not submitted and not typed.get(key,false): return
	if revisions.get(key,0) != focus_revisions.get(key,-1): return
	var input: SpinBox = field(key)
	var text: String = input.get_line_edit().text.trim_suffix(input.suffix).strip_edges()
	if not text.is_valid_float() or not is_equal_approx(float(text),input.value): return
	revisions[key] = revisions.get(key,0)+1
	studio._command(key,input.value)

func field(key: String) -> SpinBox:
	return {"height":studio.height_input,"scale":studio.scale_input,"angle":studio.angle_input,"pitch":studio.pitch_input,"roll":studio.roll_input}[key]

func eligible(items: Array, key: String) -> Array:
	if key not in ["pitch","roll"] or studio.mode == "3d": return items
	return items.filter(func(item: Dictionary) -> bool: return item["asset"].begins_with("3d:"))

func value(item: Dictionary, key: String) -> float:
	match key:
		"height": return float(item["position"][2 if studio.mode == "2d" else 1])
		"scale": return float(item["scale"])
		"angle": return studio.rotation_controls.displayed(item)
		"pitch": return float(item.get("tilt",[0,0])[0])
		"roll": return float(item.get("tilt",[0,0])[1])
	return 0

func render_mixed(key: String) -> void:
	var input: SpinBox = field(key)
	var show: bool = mixed.get(key,false) and not input.get_line_edit().has_focus()
	mixed_labels[key].visible = show
	for color in ["font_color","font_selected_color","selection_color"]:
		if show: input.get_line_edit().add_theme_color_override(color,Color.TRANSPARENT)
		else: input.get_line_edit().remove_theme_color_override(color)

func refresh() -> void:
	refresh_context()
	var items: Array = studio.selection_items()
	affected.text = "%d editable objects selected · adjustments affect the counts below" % items.size() if items.size()>1 else ""
	affected.visible = items.size()>1
	for key in field_notes:
		var input: SpinBox = field(key)
		if items.is_empty():
			mixed[key] = false
			field_notes[key].hide()
			input.tooltip_text = base_tooltips[key]
			clear_mixed_text(input)
			render_mixed(key)
			continue
		var targets: Array = eligible(items,key)
		var different: bool = false
		if not targets.is_empty():
			var first: float = value(targets[0],key)
			input.set_value_no_signal(first)
			for item in targets:
				if not is_equal_approx(value(item,key),first): different = true
			if key in ["height","scale"]: input.editable = true
			if key in ["pitch","roll"]: input.editable = true
		elif not items.is_empty(): input.editable = false
		mixed[key] = different
		if not different: clear_mixed_text(input)
		var note: Label = field_notes[key]
		note.visible = items.size()>1
		var count: int = targets.size()
		var behavior: String = "Set %d objects" % count
		if key == "scale": behavior = "Scale %d objects together; keep size ratios" % count
		elif key == "angle": behavior = "Turn %d objects together; keep relative headings" % count
		elif key in ["pitch","roll"]: behavior = "Set %s on %d of %d objects" % [key,count,items.size()]
		note.text = ("Mixed · " if different else "") + behavior
		input.tooltip_text = behavior + (". Mixed values: typing sets the active value; arrows start from %s." % str(input.value) if different else ".")
		render_mixed(key)
	if items.size()>1:
		studio.selected_name.text = "%d objects selected" % items.size()
		var names: Array[String] = []
		for item in items: names.append(item.get("name",studio.library.assets[item["asset"]]["name"]))
		studio.selected_name.tooltip_text = ", ".join(names)
		refresh_views(items)
	else:
		view_note.hide()
		studio.selected_name.tooltip_text = ""
		if items.size()==1: studio.selected_name.text = items[0].get("name",studio.library.assets[items[0]["asset"]]["name"])
	var layers: Array[String] = []
	for item in items:
		var name: String = Layers.layer(item,studio.library)
		if not layers.has(name): layers.append(name)
	studio.assign_layer.set_item_text(0,"Layer · Mixed" if layers.size()>1 else "Layer · " + layers[0] if layers.size()==1 else "Move selection to layer…")
	studio.assign_layer.tooltip_text = "Assign a layer to %d editable objects" % items.size()

func clear_mixed_text(input: SpinBox) -> void:
	if input.get_line_edit().text == "Mixed": input.get_line_edit().text = input.prefix + str(input.value) + input.suffix

func refresh_views(items: Array) -> void:
	var views: Array[String] = []
	var current: Array[String] = []
	for item in items:
		if not item["asset"].begins_with("2d:") or studio.library.is_ground_tile(item["asset"]): continue
		current.append(item["direction"])
		for view in studio.library.directions(item["asset"]):
			if not views.has(str(view)): views.append(str(view))
	studio.view_choice.clear()
	if views.is_empty(): studio.view_choice.hide(); view_note.hide(); return
	var different: bool = current.any(func(direction: String) -> bool: return direction != current[0])
	if different: studio.view_choice.add_item("Mixed")
	for view in views: studio.view_choice.add_item(view)
	if not different:
		for index in studio.view_choice.item_count:
			if studio.view_choice.get_item_text(index)==current[0]: studio.view_choice.select(index)
	studio.view_choice.show()
	view_note.show()
	view_note.text = "Source view · %d of %d sprites; choose compatible artwork" % [current.size(),items.size()]
	for index in studio.view_choice.item_count:
		var choice: String = studio.view_choice.get_item_text(index)
		if choice == "Mixed": continue
		var count: int = 0
		for item in items:
			if item["asset"].begins_with("2d:") and not studio.library.is_ground_tile(item["asset"]) and studio.library.directions(item["asset"]).has(choice): count+=1
		studio.view_choice.set_item_tooltip(index,"Applies to %d of %d objects" % [count,items.size()])
	studio.view_choice.tooltip_text = "Choose supplied artwork; only compatible sprites change. Models keep their source."

func refresh_context() -> void:
	context_key = location_key()
	var parts: Array[String] = [str(studio.current().data.get("title","Untitled")),"City"]
	if studio.interior_tools.editing():
		var host: Dictionary = studio.interior_tools.outer.object(studio.interior_tools.uid)
		parts = [str(studio.interior_tools.outer.data.get("title","Untitled")),host.get("name",studio.library.assets.get(host.get("asset",""),{}).get("name","Building")),"Interior"]
		if studio.walking and studio.worlds[studio.mode].exploration.preview: parts.insert(parts.size()-1,studio.worlds[studio.mode].exploration.room_world().data_state.get("title","Interior"))
	elif studio.walking and studio.worlds[studio.mode].exploration.interior:
		var exploration: Node = studio.worlds[studio.mode].exploration
		parts.append(str(exploration.room_world().data_state.get("title","Interior")))
		parts.append("Interior")
	var items: Array = studio.selection_items()
	if studio.walking and studio.worlds[studio.mode].exploration.interior: items = []
	if not items.is_empty():
		var layers: Array[String] = []
		var groups: Array[String] = []
		for item in items:
			var layer: String = Layers.layer(item,studio.library)
			if not layers.has(layer): layers.append(layer)
			var group: String = item.get("group","")
			var group_name: String = "No group" if group.is_empty() else studio.current().data.get("group_names",{}).get(group,group)
			if not groups.has(group_name): groups.append(group_name)
		parts.append(layers[0] if layers.size()==1 else "Mixed layers")
		parts.append(groups[0] if groups.size()==1 else "Mixed groups")
		parts.append(items[0].get("name",studio.library.assets[items[0]["asset"]]["name"]) if items.size()==1 else "%d objects" % items.size())
	elif not studio.selected_tile().is_empty():
		parts.append("Ground")
		parts.append(studio.library.assets[studio.selected_tile()["asset"]]["name"])
		parts.append(str(studio.selected_cell))
	else: parts.append("No selection")
	breadcrumb.text = " › ".join(parts)
	breadcrumb.tooltip_text = breadcrumb.text

func location_key() -> String:
	var exploration: Node = studio.worlds[studio.mode].exploration
	return str([studio.mode,studio.walking,studio.interior_tools.uid,exploration.interior_uid if exploration else "",exploration.active_floor() if exploration else "ground",studio.current().data.get("title","")])

func tick_context() -> void:
	if context_key != location_key(): refresh_context()
