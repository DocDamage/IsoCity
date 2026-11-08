extends RefCounted

const Plan = preload("res://scripts/builder/village_plan.gd")
var runtime: Node
var overlay := Control.new()
var panel := PanelContainer.new()
var scroll := ScrollContainer.new()
var heading := Label.new()
var stock := Label.new()
var status := Label.new()
var wallet := Label.new()
var notice := Label.new()
var buttons: Dictionary = {}
var dismiss: Button
var markers: Dictionary = {}
var cargo: Dictionary = {}

func _init(owner: Node) -> void:
	runtime = owner
	var layer := CanvasLayer.new()
	layer.name = "VillageSupplies"
	layer.layer = 40
	var host: Node = owner.ui_parent if is_instance_valid(owner.ui_parent) else owner
	host.add_child(layer)
	layer.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(.025,.043,.076,.65)
	overlay.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(panel)
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color("172436")
	surface.border_color = Color("759eaa")
	surface.set_border_width_all(2)
	surface.set_corner_radius_all(6)
	surface.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel",surface)
	panel.add_child(scroll)
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",8)
	scroll.add_child(body)
	for label in [heading,status,stock,wallet,notice]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size",22 if label == heading else 14)
		body.add_child(label)
	for entry in [["sell","Sell ready order"],["forge","Order bar iron and charcoal"],["tomatoes","Bring garden tomatoes"],["kitchen","Supply kitchen flour"]]:
		var action: String = entry[0]
		buttons[action] = button(body,entry[1],func(): runtime.command(action))
	dismiss = button(body,"Back to walking",runtime.close)
	overlay.resized.connect(layout)
	overlay.hide()

func button(body: Control, text: String, action: Callable) -> Button:
	var control := Button.new()
	control.text = text
	control.accessibility_name = text
	control.clip_text = true
	control.custom_minimum_size.y = 44
	control.add_theme_font_size_override("font_size",15)
	control.pressed.connect(action)
	body.add_child(control)
	return control

func layout() -> void:
	var area: Vector2 = overlay.get_viewport_rect().size
	var size := Vector2(minf(525,area.x-24),minf(462,area.y-24))
	panel.position = (area-size)*.5
	panel.size = size

func open() -> void:
	if runtime.ui_parent is Control: overlay.theme = runtime.ui_parent.theme
	overlay.show()
	layout()
	scroll.scroll_vertical = 0
	refresh()
	for control in buttons.values():
		if control.visible and not control.disabled:
			control.grab_focus()
			return
	dismiss.grab_focus()

func close() -> void:
	var focused: Control = overlay.get_viewport().gui_get_focus_owner()
	if is_instance_valid(focused) and overlay.is_ancestor_of(focused): focused.release_focus()
	overlay.hide()

func refresh() -> void:
	var uid: String = runtime.selected
	var site: Dictionary = runtime.book.sites.get(uid,{})
	if site.is_empty(): return
	var role: String = site["profile"]["role"]
	heading.text = site["name"]
	status.text = runtime.status(uid)
	stock.text = runtime.stock_text(uid)
	wallet.text = runtime.wallet()
	notice.text = runtime.notice if not runtime.notice.is_empty() else runtime.book.latest
	buttons["sell"].visible = role == "market"
	buttons["sell"].disabled = runtime.book.order(uid).is_empty()
	buttons["forge"].visible = role == "smith"
	buttons["tomatoes"].visible = role == "bakery" and site["config"]["recipe"] == "tomato_loaf"
	buttons["tomatoes"].text = "Bring garden tomatoes" if runtime.garden_enabled() else "Order tomatoes"
	buttons["tomatoes"].accessibility_name = buttons["tomatoes"].text
	buttons["kitchen"].visible = role == "bakery" and runtime.Cooking.enabled(runtime.root_data())
	var sequence: Array = buttons.values().filter(func(control: Button)->bool: return control.visible and not control.disabled)
	sequence.append(dismiss)
	for index in sequence.size():
		sequence[index].focus_next = sequence[(index+1)%sequence.size()].get_path()
		sequence[index].focus_previous = sequence[posmod(index-1,sequence.size())].get_path()

func marker(key: String) -> Node:
	if markers.has(key): return markers[key]
	var label: Node
	if runtime.exploration.dimension == "2d":
		label = Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.z_index = 96
		label.add_theme_font_size_override("font_size",13)
		label.add_theme_color_override("font_outline_color",Color.BLACK)
		label.add_theme_constant_override("outline_size",4)
	else:
		label = Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 30
		label.pixel_size = .011
		label.no_depth_test = true
		label.outline_size = 8
	runtime.exploration.get_parent().add_child(label)
	markers[key] = label
	return label

func crate(key: String, good: String) -> Node:
	if cargo.has(key): return cargo[key]
	var tint := Color(Plan.goods()[good]["color"])
	var model: Node
	if runtime.exploration.dimension == "2d":
		var tile := Node2D.new()
		tile.z_index = 4
		for face in [[[0,-11],[7,-7],[0,-3],[-7,-7]],[[0,-3],[7,-7],[7,-1],[0,3]],[[-7,-7],[0,-3],[0,3],[-7,-1]]]:
			var side := Polygon2D.new()
			var points := PackedVector2Array()
			for vertex in face: points.append(Vector2(vertex[0],vertex[1]))
			side.polygon = points
			side.color = tint.darkened(tile.get_child_count()*.18)
			tile.add_child(side)
		model = tile
	else:
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(.64,.50,.64)
		box.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = tint
		box.material_override = material
		model = box
	runtime.exploration.get_parent().add_child(model)
	cargo[key] = model
	return model

func remove_missing(nodes: Dictionary, keep: Dictionary) -> void:
	for key in nodes.keys():
		if keep.has(key): continue
		if is_instance_valid(nodes[key]): nodes[key].free()
		nodes.erase(key)

func render() -> void:
	var active: Dictionary = {}
	for uid in runtime.book.sites:
		var site: Dictionary = runtime.book.sites[uid]
		if site["points"].is_empty(): continue
		var placed: Node = runtime.exploration.instances.get(uid)
		if not is_instance_valid(placed) or not placed.is_visible_in_tree(): continue
		var node: Node = marker(uid)
		var text: String = site["name"]+" · "+runtime.stock_text(uid)
		if node.text != text: node.text = text
		var point: Variant = runtime.position(site["points"][0])
		node.global_position = point+Vector2(-30,-22) if node is Control else point+Vector3.UP*1.35
		active[uid] = true
	remove_missing(markers,active)
	active = {}
	for id in runtime.book.transfers:
		var job: Dictionary = runtime.book.transfers[id]
		if job["transport"] != "porter": continue
		var point: Vector2 = Plan.Traffic.sample(job["path"],job["distance"])["point"]
		var model: Node = crate(id,job["good"])
		var at: Variant = runtime.position(point)
		model.global_position = at if model is Node2D else at+Vector3.UP*.3
		active[id] = true
	remove_missing(cargo,active)

func clear() -> void:
	remove_missing(markers,{})
	remove_missing(cargo,{})
