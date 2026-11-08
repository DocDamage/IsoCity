extends RefCounted

var runtime: Node
var panel := PanelContainer.new()
var scroll := ScrollContainer.new()
var body := VBoxContainer.new()
var heading: Label
var summary: Label
var close_button: Button
var rows: Dictionary = {}
var stamp: int = -1

func _init(host: Node) -> void:
	runtime = host
	var layer := CanvasLayer.new()
	layer.layer = 21
	host.add_child(layer)
	layer.add_child(panel)
	panel.add_child(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.resized.connect(func(): queue_focus_reveal(panel.get_viewport().gui_get_focus_owner()))
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	scroll.add_child(body)
	heading = label("Laundry counter")
	close_button = button("Close laundry counter", host.close_counter)
	summary = label("")
	for customer in host.Plan.customers():
		var name_text: String = host.Plan.customers()[customer]["name"]
		var status: Label = label("")
		var primary: Button = button("", func(): primary_action(customer))
		var cancel: Button = button("Cancel " + name_text + "’s load", func(): cancel_action(customer))
		rows[customer] = {"status": status, "primary": primary, "cancel": cancel, "order": ""}
	panel.hide()

func label(text: String) -> Label:
	var control := Label.new()
	control.text = text
	control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(control)
	return control

func button(text: String, pressed: Callable) -> Button:
	var control := Button.new()
	control.text = text
	control.clip_text = true
	control.pressed.connect(pressed)
	control.focus_entered.connect(func(): queue_focus_reveal(control))
	body.add_child(control)
	return control

func primary_action(customer: String) -> void:
	var id: String = rows[customer]["order"]
	var primary: Button = rows[customer]["primary"]
	var had_focus: bool = primary.has_focus()
	if id.is_empty(): runtime.receive(customer)
	else: runtime.return_load(id, customer)
	refresh()
	if had_focus and primary.disabled: rows[customer]["cancel"].grab_focus()

func cancel_action(customer: String) -> void:
	var id: String = rows[customer]["order"]
	var had_focus: bool = rows[customer]["cancel"].has_focus()
	if not id.is_empty(): runtime.return_load(id, customer, true)
	refresh()
	if had_focus and rows[customer]["order"].is_empty(): rows[customer]["primary"].grab_focus()

func hide() -> void:
	panel.hide()

func refresh(opening: bool = false) -> void:
	var site: Dictionary = runtime.counter_site()
	if site.is_empty():
		runtime.close_counter()
		return
	var orders: Dictionary = {}
	for order in site["orders"].values(): orders[order["customer"]] = order
	for customer in rows:
		var row: Dictionary = rows[customer]
		var order: Dictionary = orders.get(customer, {})
		var person: Dictionary = runtime.Plan.customers()[customer]
		var primary: Button = row["primary"]
		var cancel: Button = row["cancel"]
		var status: Label = row["status"]
		row["order"] = order.get("id", "")
		status.visible = not order.is_empty()
		cancel.visible = status.visible
		if order.is_empty():
			primary.text = "Receive %s · %d items" % [person["name"], person["items"].size()]
			primary.disabled = false
		else:
			var stage: String = order["stage"]
			var details: String = order["wait"]
			if not order["station"].is_empty(): details = "%.0f s remaining" % ceilf(order["remaining"])
			if stage == "fold" and details.is_empty(): details = "Use the folding table."
			if stage == "return": details = "Claim ticket ready."
			status.text = "#%d · %s · %s%s" % [order["number"], person["name"], stage.capitalize(),
				(" · " + details) if not details.is_empty() else ""]
			primary.text = "Return #%d to %s" % [order["number"], person["name"]]
			primary.disabled = stage != "return"
		primary.accessibility_name = primary.text
		cancel.accessibility_name = cancel.text
	summary.text = "Detergent available · %d" % [int(site["account"]["stock"]["detergent"]) - runtime.reserved_detergent(site)]
	if runtime.notice_seconds > 0:
		summary.text += "\n" + runtime.notice
	elif not site["last_receipt"].is_empty():
		var receipt: Dictionary = site["last_receipt"]
		summary.text += "\n%s · %s · %s" % [receipt["id"].replace("laundry/", "Receipt #"),
			runtime.Plan.customers()[receipt["customer"]]["name"], receipt["state"].capitalize()]
	layout()
	panel.show()
	if opening: close_button.grab_focus()
	if opening: scroll.scroll_vertical = 0
	else: queue_focus_reveal(panel.get_viewport().gui_get_focus_owner())

func queue_focus_reveal(focused: Control) -> void:
	if not is_instance_valid(focused) or not body.is_ancestor_of(focused): return
	await panel.get_tree().process_frame
	if not panel.is_visible_in_tree() or not is_instance_valid(focused) or not focused.has_focus(): return
	var frame: Rect2 = scroll.get_global_rect()
	var target: Rect2 = focused.get_global_rect()
	if target.position.y < frame.position.y:
		scroll.scroll_vertical += floori(target.position.y - frame.position.y)
	elif target.end.y > frame.end.y:
		scroll.scroll_vertical += ceili(target.end.y - frame.end.y)

func layout() -> void:
	var area: Rect2 = runtime.panel_area
	if not area.has_area(): area = Rect2(Vector2(12, 92), (panel.get_viewport_rect().size - Vector2(24, 106)).max(Vector2.ONE))
	var width: float = minf(340 * runtime.ui_scale, area.size.x)
	panel.position = Vector2(area.end.x - width, area.position.y)
	panel.size = Vector2(width, minf(430 * runtime.ui_scale, area.size.y))
	var style_stamp: int = hash([runtime.ui_scale, runtime.large_targets, runtime.high_contrast])
	if style_stamp == stamp: return
	stamp = style_stamp
	for control in body.get_children():
		control.add_theme_font_size_override("font_size", roundi((18 if control == heading else 14) * runtime.ui_scale))
		if control is Button: control.custom_minimum_size.y = 44 if runtime.large_targets else 32
	var style := StyleBoxFlat.new()
	style.bg_color = Color.BLACK if runtime.high_contrast else Color("152531")
	style.border_color = Color.WHITE if runtime.high_contrast else Color("527180")
	style.set_border_width_all(2 if runtime.high_contrast else 1)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
