extends RefCounted

var runtime: Node
var overlay := Control.new()
var panel := PanelContainer.new()
var scroll := ScrollContainer.new()
var body := VBoxContainer.new()
var heading := Label.new()
var status := Label.new()
var feedback := Label.new()
var screen := VBoxContainer.new()
var direction_row := HBoxContainer.new()
var actions := HBoxContainer.new()
var directions: Dictionary = {}
var primary: Button
var exit: Button
var help := Label.new()
var scores := Label.new()
var style_key: int = -1
var focus_key: String = ""

func _init(owner: Node) -> void:
	runtime = owner
	var layer := CanvasLayer.new()
	layer.name = "ArcadeOverlay"
	layer.layer = 40
	var host: Node = owner.ui_parent if is_instance_valid(owner.ui_parent) else owner
	host.add_child(layer)
	layer.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(.025,.043,.076,.87)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(panel)
	panel.add_child(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.resized.connect(func(): reveal(panel.get_viewport().gui_get_focus_owner()))
	scroll.add_child(body)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",7)
	for label in [heading,status,feedback]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(label)
	body.add_child(screen)
	screen.clip_contents = true
	body.add_child(direction_row)
	for spec in [["move_left","Left"],["move_up","Up"],["move_down","Down"],["move_right","Right"]]:
		var action: String = spec[0]
		directions[action] = button(direction_row,spec[1],func(): runtime.command(action))
	body.add_child(actions)
	primary = button(actions,"Start",runtime.primary)
	exit = button(actions,"Exit cabinet",func(): runtime.close("Left the arcade cabinet."))
	for label in [help,scores]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(label)
	overlay.hide()

func button(parent: Node, text: String, action: Callable) -> Button:
	var control := Button.new()
	control.text = text
	control.clip_text = true
	control.accessibility_name = text
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.pressed.connect(action)
	control.focus_entered.connect(func(): reveal(control))
	parent.add_child(control)
	return control

func show_overlay() -> void:
	overlay.show()
	scroll.scroll_vertical = 0
	refresh()
	focus_primary()

func focus_primary() -> void:
	primary.grab_focus()

func hide_overlay() -> void:
	var focused: Control = overlay.get_viewport().gui_get_focus_owner()
	if is_instance_valid(focused) and overlay.is_ancestor_of(focused): focused.release_focus()
	overlay.hide()
	focus_key = ""

func refresh() -> void:
	if not runtime.active(): return
	var entry: Dictionary = runtime.session
	var game: Control = runtime.game
	var id: String = entry["game"]
	var phase: String = entry["phase"]
	heading.text = runtime.Plan.title(id)
	status.text = game.status()
	feedback.text = game.cue_text() if id == "signals" and phase == "playing" else game.feedback
	direction_row.visible = phase == "playing"
	for action in directions:
		directions[action].visible = id == "signals" or action in ["move_left","move_right"]
	primary.text = {"ready":"Start", "playing":"Pause", "paused":"Resume", "result":"Play again"}[phase]
	primary.disabled = not runtime.focus_available
	primary.accessibility_name = primary.text
	if phase == "paused":
		feedback.text = "Paused · choose Resume." if runtime.focus_available else "Paused · return to this window."
	elif phase == "result":
		feedback.text = "%s Final score %d." % [game.feedback,game.score]
	var show_help: bool = phase in ["ready","playing"]
	help.visible = show_help
	if show_help:
		var keys: String = "%s / %s" % [runtime.binding("move_left","Left"),runtime.binding("move_right","Right")]
		if id == "signals":
			keys = "%s / %s / %s" % [keys,runtime.binding("move_up","Up"),runtime.binding("move_down","Down")]
		help.text = runtime.Plan.definitions()["games"][id]["instruction"]+"\n%s or the direction buttons · %s exits" % [
			keys,runtime.binding("cancel","Esc")]
	scores.visible = phase in ["ready","result"]
	if scores.visible:
		var board: Array = runtime.boards.get(id,[])
		var entries: PackedStringArray = []
		for index in board.size(): entries.append("%d. %d" % [index+1,board[index]["score"]])
		scores.text = "Top scores · "+"    ".join(entries) if not entries.is_empty() else "Top scores · No finished runs yet"
	layout()
	focus_order(id,phase)

func focus_order(id: String, phase: String) -> void:
	var key: String = str([id,phase,runtime.focus_available])
	if key == focus_key: return
	focus_key = key
	var order: Array[Control] = []
	if not primary.disabled: order.append(primary)
	if phase == "playing":
		for control in directions.values():
			if control.visible: order.append(control)
	order.append(exit)
	for index in order.size():
		var control: Control = order[index]
		control.focus_next = order[(index+1)%order.size()].get_path()
		control.focus_previous = order[posmod(index-1,order.size())].get_path()

func layout() -> void:
	var extent: Vector2 = overlay.get_viewport_rect().size
	var box := Vector2(minf(680*runtime.ui_scale,extent.x-28),minf(586*runtime.ui_scale,extent.y-24))
	panel.position = (extent-box)*.5
	panel.size = box
	runtime.game.custom_minimum_size.y = clampf(box.y*.38,130,238)
	var stamp: int = hash([runtime.ui_scale,runtime.high_contrast,runtime.large_targets])
	if stamp == style_key: return
	style_key = stamp
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color.BLACK if runtime.high_contrast else Color("172436")
	surface.border_color = Color.WHITE if runtime.high_contrast else Color("759eaa")
	surface.set_border_width_all(2)
	surface.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel",surface)
	for label in [heading,status,feedback,help,scores]:
		label.add_theme_font_size_override("font_size",roundi((23 if label == heading else 15)*runtime.ui_scale))
		label.add_theme_color_override("font_color",Color.WHITE if runtime.high_contrast else Color("ecf7f8"))
	for control in directions.values()+[primary,exit]:
		control.custom_minimum_size.y = 44 if runtime.large_targets else 34
		control.add_theme_font_size_override("font_size",roundi(15*runtime.ui_scale))
	runtime.game.high_contrast = runtime.high_contrast
	runtime.game.queue_redraw()

func reveal(control: Control) -> void:
	if not is_instance_valid(control) or not body.is_ancestor_of(control): return
	await overlay.get_tree().process_frame
	if not overlay.is_visible_in_tree() or not is_instance_valid(control) or not control.has_focus(): return
	var frame: Rect2 = scroll.get_global_rect()
	var target: Rect2 = control.get_global_rect()
	if target.position.y < frame.position.y:
		scroll.scroll_vertical += floori(target.position.y-frame.position.y)
	elif target.end.y > frame.end.y:
		scroll.scroll_vertical += ceili(target.end.y-frame.end.y)
