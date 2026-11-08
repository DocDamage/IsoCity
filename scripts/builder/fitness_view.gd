extends RefCounted

var runtime: Node
var panel := PanelContainer.new()
var scroll := ScrollContainer.new()
var body := VBoxContainer.new()
var heading := Label.new()
var state := Label.new()
var primary: Button
var aim_row := HBoxContainer.new()
var left: Button
var right: Button
var cancel: Button
var details := Label.new()
var style_key: int = -1

func _init(owner: Node) -> void:
	runtime = owner
	var layer := CanvasLayer.new()
	layer.layer = 22
	runtime.add_child(layer)
	layer.add_child(panel)
	panel.add_child(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.resized.connect(func(): reveal(panel.get_viewport().gui_get_focus_owner()))
	scroll.add_child(body)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",6)
	for label in [heading,state,details]: label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(heading)
	body.add_child(state)
	primary = button(body,"Reserve slot",act)
	body.add_child(aim_row)
	left = button(aim_row,"Aim left",func(): runtime.aim(-.35))
	right = button(aim_row,"Aim right",func(): runtime.aim(.35))
	cancel = button(body,"Close booking",runtime.close_view)
	body.add_child(details)
	panel.hide()

func button(parent: Node, text: String, action: Callable) -> Button:
	var control := Button.new()
	control.text = text
	control.clip_text = true
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.pressed.connect(action)
	control.focus_entered.connect(func(): reveal(control))
	parent.add_child(control)
	return control

func act() -> void:
	if runtime.session.is_empty():
		if runtime.booking.is_empty(): runtime.book()
		else: runtime.start()
	elif runtime.session["kind"] == "penalty":
		runtime.kick()
	else:
		runtime.cancel("Workout stopped.")
	if not runtime.menu.is_empty(): update(runtime.local_station(runtime.menu["uid"]))

func hide() -> void:
	panel.hide()

func update(station: Dictionary, opening: bool = false) -> void:
	if station.is_empty(): return
	var setting: Dictionary = station["setting"]
	var entry: Dictionary = runtime.session
	var playing: bool = not entry.is_empty()
	var booked: bool = not runtime.booking.is_empty()
	var penalty: bool = setting["kind"] == "penalty"
	heading.text = runtime.label_for(station)
	aim_row.visible = playing and penalty
	if playing:
		state.text = "%d goals · %d shots · %d seconds" % [entry["score"],entry["shots"],ceili(entry["remaining"])] \
			if penalty else "%d seconds left" % ceili(entry["remaining"])
		primary.text = "Kick" if penalty else "Stop workout"
		cancel.text = "Cancel session"
		details.text = "Aim with movement keys or the buttons. %s kicks." % runtime.interact_label if penalty else entry["note"]
	elif booked:
		state.text = "One spot reserved · check in within %d seconds" % ceili(runtime.booking["remaining"])
		primary.text = "Check in"
		cancel.text = "Release booking"
		details.text = ""
	else:
		var open: bool = runtime.Plan.scheduled(setting,runtime.hour())
		state.text = "%s · %s · 1 player" % [runtime.Visits.time_text(runtime.hour()),"Open" if open else "Closed"]
		primary.text = "Reserve slot"
		cancel.text = "Close booking"
		var start: float = setting["open_hour"]
		var end: float = setting["close_hour"]
		details.text = "Open all day" if is_equal_approx(start,end) else "%s to %s" % [runtime.Visits.time_text(start),runtime.Visits.time_text(end)]
		if penalty: details.text += "\nGoal · score three in five shots."
	primary.disabled = not playing and not runtime.Plan.scheduled(setting,runtime.hour())
	primary.accessibility_name = primary.text
	cancel.accessibility_name = cancel.text
	if runtime.notice_time > 0 and not runtime.notice.is_empty():
		details.text += ("\n" if not details.text.is_empty() else "") + runtime.notice
	layout()
	panel.show()
	if opening:
		scroll.scroll_vertical = 0
		if primary.disabled: cancel.grab_focus()
		else: primary.grab_focus()

func layout() -> void:
	var area: Rect2 = runtime.panel_area
	if not area.has_area(): area = Rect2(Vector2(12,92),(panel.get_viewport_rect().size-Vector2(24,106)).max(Vector2.ONE))
	var viewport: Vector2 = panel.get_viewport_rect().size
	var width: float = minf(318*runtime.ui_scale,area.size.x)
	if viewport.x < 1150: width = minf(width,maxf(230,viewport.x*.38))
	var left_side: bool = false
	if runtime.session.get("kind") == "penalty":
		var player: Node = runtime.exploration.player
		var goal: Variant = runtime.court.frame["origin"]
		if player is Node2D:
			left_side = (player.get_canvas_transform()*goal).x > area.get_center().x
		else:
			var camera: Camera3D = player.get_viewport().get_camera_3d()
			left_side = is_instance_valid(camera) and camera.unproject_position(goal).x > area.get_center().x
	panel.position = Vector2(area.position.x if left_side else area.end.x-width,area.position.y)
	panel.size = Vector2(width,minf(264*runtime.ui_scale,area.size.y))
	var stamp: int = hash([runtime.ui_scale,runtime.high_contrast,runtime.large_targets])
	if stamp == style_key: return
	style_key = stamp
	for label in [heading,state,details]:
		label.add_theme_font_size_override("font_size",roundi((18 if label == heading else 14)*runtime.ui_scale))
	for control in [primary,cancel,left,right]:
		control.custom_minimum_size.y = 44 if runtime.large_targets else 32
		control.add_theme_font_size_override("font_size",roundi(14*runtime.ui_scale))
	var style := StyleBoxFlat.new()
	style.bg_color = Color.BLACK if runtime.high_contrast else Color("172937")
	style.border_color = Color.WHITE if runtime.high_contrast else Color("527180")
	style.set_border_width_all(2 if runtime.high_contrast else 1)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel",style)

func reveal(control: Control) -> void:
	if not is_instance_valid(control) or not body.is_ancestor_of(control): return
	await panel.get_tree().process_frame
	if not panel.is_visible_in_tree() or not is_instance_valid(control) or not control.has_focus(): return
	var frame: Rect2 = scroll.get_global_rect()
	var target: Rect2 = control.get_global_rect()
	if target.position.y < frame.position.y:
		scroll.scroll_vertical += floori(target.position.y-frame.position.y)
	elif target.end.y > frame.end.y:
		scroll.scroll_vertical += ceili(target.end.y-frame.end.y)
