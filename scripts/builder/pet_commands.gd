extends RefCounted

const BUTTONS = [
	["follow","Follow me"],["stay","Stay here"],["come","Come here"],
	["rest","Rest at home"],["home","Return home"],["practice","Practice at dog station"]
]

var runtime: Node
var overlay := Control.new()
var panel := PanelContainer.new()
var scroll := ScrollContainer.new()
var title := Label.new()
var status := Label.new()
var buttons: Dictionary = {}
var dismiss: Button

func _init(owner: Node) -> void:
	runtime = owner
	var layer := CanvasLayer.new()
	layer.name = "PetCommands"
	layer.layer = 40
	var host: Node = owner.ui_parent if is_instance_valid(owner.ui_parent) else owner
	host.add_child(layer)
	layer.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(.025,.043,.076,.63)
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
	body.add_theme_constant_override("separation",7)
	scroll.add_child(body)
	for label in [title,status]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size",22 if label == title else 14)
		body.add_child(label)
	for entry in BUTTONS:
		var command: String = entry[0]
		buttons[command] = button(body,entry[1],func(): runtime.command(command))
	dismiss = button(body,"Back to walking",runtime.close)
	overlay.resized.connect(layout)
	overlay.hide()

func button(parent: Control, text: String, action: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.accessibility_name = text
	node.clip_text = true
	node.custom_minimum_size.y = 44
	node.add_theme_font_size_override("font_size",15)
	node.pressed.connect(action)
	parent.add_child(node)
	return node

func layout() -> void:
	var area: Vector2 = overlay.get_viewport_rect().size
	var size := Vector2(minf(438,area.x-26),minf(495,area.y-26))
	panel.position = (area-size)*.5
	panel.size = size

func open(at_station: bool) -> void:
	if runtime.ui_parent is Control: overlay.theme = runtime.ui_parent.theme
	title.text = runtime.title()
	status.text = runtime.status
	buttons["practice"].visible = at_station
	overlay.show()
	layout()
	scroll.scroll_vertical = 0
	var order: Array = buttons.values().filter(func(node: Button)->bool: return node.visible)
	order.append(dismiss)
	for index in order.size():
		order[index].focus_next = order[(index+1)%order.size()].get_path()
		order[index].focus_previous = order[posmod(index-1,order.size())].get_path()
	var primary: Button = buttons["practice"] if at_station else buttons["follow"]
	primary.grab_focus()

func hide_panel() -> void:
	var focused: Control = overlay.get_viewport().gui_get_focus_owner()
	if is_instance_valid(focused) and overlay.is_ancestor_of(focused): focused.release_focus()
	overlay.hide()
