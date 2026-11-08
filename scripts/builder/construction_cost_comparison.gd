extends RefCounted

const Factory = preload("res://scripts/builder/asset_instance.gd")
const ScalePreview = preload("res://scripts/builder/asset_scale_preview.gd")
const Budget = preload("res://scripts/builder/rendering_budget.gd")
const Cost = preload("res://scripts/builder/construction_cost.gd")
const Paint = preload("res://scripts/builder/part_colors.gd")

var studio: Control
var dialog: AcceptDialog
var note: Label
var replace: Button
var gallery: HBoxContainer
var scroller: ScrollContainer
var source_item: Dictionary
var target_item: Dictionary

func _init(host: Control, apply: Callable) -> void:
	studio = host
	dialog = AcceptDialog.new()
	dialog.title = "Compare asset appearances"
	dialog.ok_button_text = "Close comparison"
	studio.add_child(dialog)
	scroller = ScrollContainer.new()
	scroller.custom_minimum_size = Vector2(320, 280)
	scroller.follow_focus = true
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dialog.add_child(scroller)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(content)
	gallery = HBoxContainer.new()
	gallery.add_theme_constant_override("separation", 12)
	content.add_child(gallery)
	note = studio.label(content, "", 13)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.focus_mode = Control.FOCUS_ALL
	note.accessibility_name = "Comparison and exact economy quote"
	replace = dialog.add_button("Apply reviewed replacement", true, "replace")
	dialog.custom_action.connect(func(action: StringName):
		if action == &"replace": apply.call(source_item, target_item)
	)
	dialog.visibility_changed.connect(func():
		if not dialog.visible: clear()
	)

func clear() -> void:
	for child in gallery.get_children():
		gallery.remove_child(child)
		child.queue_free()
	source_item = {}
	target_item = {}

func open(source: Dictionary, target: Dictionary, profile: Dictionary, scan: RefCounted, text: String, allow: bool) -> void:
	clear()
	source_item = source.duplicate(true)
	target_item = target.duplicate(true)
	var editions: bool = not profile.is_empty()
	var first: String = "Regular · low detail" if editions else "Current appearance"
	var second: String = "Photo · full detail" if editions else "Proposed appearance"
	var left: Dictionary = card(source_item, first, scan)
	var right: Dictionary = card(target_item, second, scan, profile)
	var smaller: bool = right["cost"]["live"] < left["cost"]["live"] or right["cost"]["triangles"] < left["cost"]["triangles"]
	note.text = text + "\n\nViews use the same magnification. Artwork and footprint can differ."
	if not editions and smaller:
		note.text += "\nThe proposed appearance uses less model geometry or fewer private live views."
	if editions and not source_item.get("colors", []).is_empty():
		note.text += "\nThe full-detail sample shows original artwork. Paint edits use the regular model’s surfaces."
	replace.visible = not editions
	replace.disabled = not allow
	dialog.popup_centered_clamped(Vector2i(760, 620), .9)
	var frame: Callable = func(): fit(left, right)
	left["container"].resized.connect(frame)
	right["container"].resized.connect(frame)
	frame.call_deferred()
	studio.accessibility_settings.apply_tree(scroller)
	scroller.scroll_vertical = 0
	# Start on the images; the keyboard can move to either estimate or the quote.
	left["title"].grab_focus()

func card(item: Dictionary, title: String, scan: RefCounted, profile: Dictionary = {}) -> Dictionary:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gallery.add_child(box)
	var title_label: Label = studio.label(box, title + "\n" + studio.library.assets[item["asset"]]["name"], 15)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.focus_mode = Control.FOCUS_ALL
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(140, 190)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(container)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.world_2d = World2D.new()
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	container.add_child(viewport)
	var pixel: bool = studio.mode == "2d"
	var sample: Node
	var camera: Node
	var area := Rect2()
	if pixel:
		sample = Factory.make(studio.library, item["asset"], studio.mode, false)
		if not profile.is_empty(): sample.set_photo_projection(true, profile)
		viewport.add_child(sample)
		Factory.pose(sample, item)
		sample.scale = Vector2.ONE * float(item["scale"])
		if profile.is_empty(): Paint.apply(sample, item)
		area = ScalePreview.projected_geometry(sample) if item["asset"].begins_with("3d:") else ScalePreview.screen_bounds(sample)
		camera = Camera2D.new()
		viewport.add_child(camera)
		camera.position = area.get_center()
	else:
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color("182838")
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color.WHITE
		environment.environment.ambient_light_energy = .7
		viewport.add_child(environment)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-45, -30, 0)
		viewport.add_child(light)
		sample = Factory.make(studio.library, item["asset"], studio.mode, false) if profile.is_empty() else Budget.make_detail(profile)
		viewport.add_child(sample)
		Factory.pose(sample, item)
		sample.scale = Vector3.ONE * float(item["scale"])
		if profile.is_empty(): Paint.apply(sample, item)
		var bounds: AABB = ScalePreview.render_bounds(sample)
		camera = Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		camera.current = true
		viewport.add_child(camera)
		var center: Vector3 = bounds.get_center()
		camera.position = center + Vector3(1, .8, 1).normalized() * maxf(3, bounds.size.length() * 2)
		camera.look_at(center)
		camera.far = maxf(4000, bounds.size.length() * 4)
		for index in 8:
			var point: Vector3 = camera.basis.inverse() * bounds.get_endpoint(index)
			area = Rect2(Vector2(point.x, point.y), Vector2.ZERO) if index == 0 else area.expand(Vector2(point.x, point.y))
	ScalePreview.freeze(sample)
	var cost: Dictionary = scan.estimate({"sample": item}, studio.mode, profile.get("full", {}))
	var stats: Label = studio.label(box, "Approximate render cost\n" + Cost.estimate_text(cost, studio.mode), 12)
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.focus_mode = Control.FOCUS_ALL
	return {"container": container, "camera": camera, "area": area, "cost": cost, "title": title_label}

func fit(left: Dictionary, right: Dictionary) -> void:
	if not dialog.visible or not is_instance_valid(left["camera"]) or not is_instance_valid(right["camera"]): return
	var a: Vector2 = left["container"].size
	var b: Vector2 = right["container"].size
	var area: Vector2 = left["area"].size.max(right["area"].size)
	var width: float = maxf(1, minf(a.x, b.x))
	var height: float = maxf(1, minf(a.y, b.y))
	var zoom: float = minf(width / maxf(.01, area.x), height / maxf(.01, area.y)) * .8
	for side in [left, right]:
		var camera: Node = side["camera"]
		if camera is Camera2D: camera.zoom = Vector2.ONE * zoom
		else: camera.size = height / zoom
