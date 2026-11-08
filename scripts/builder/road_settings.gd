extends RefCounted

const STYLES: Array[String] = ["asphalt", "brick", "gravel"]
const CYCLE_ACCESS: Array[String] = ["none", "shared", "cycle"]
const TILES: Dictionary = {"asphalt": "Asphalt", "brick": "Brick_Pavers", "gravel": "Gravel"}
const COLORS: Dictionary = {"asphalt": Color("343e46"), "brick": Color("997565"), "gravel": Color("8b887b")}

static func profile(entry: Dictionary) -> Dictionary:
	var result: Dictionary = {"width": int(entry.get("width", 6)), "sidewalks": entry.get("sidewalks", true), "style": entry.get("style", "asphalt")}
	if entry.has("cycle_access"): result["cycle_access"] = entry["cycle_access"]
	return result

static func valid(entry: Dictionary) -> bool:
	var width_value: Variant = entry.get("width", 6)
	return (width_value is int or width_value is float) and (float(width_value) == 2 or float(width_value) == 6) and entry.get("sidewalks", true) is bool and entry.get("style", "asphalt") in STYLES and entry.get("cycle_access", "none") in CYCLE_ACCESS

static func half_width(entry: Dictionary) -> float:
	return float(entry.get("width", 6)) * 0.5

static func outer_half(entry: Dictionary) -> float:
	return half_width(entry) + (1.0 if entry.get("sidewalks", true) else 0.0)

var studio: Control
var panel: VBoxContainer
var width: OptionButton
var sidewalks: CheckBox
var style: OptionButton
var cycling: OptionButton

func _init(owner_control: Control, tabs: TabContainer) -> void:
	studio = owner_control
	panel = VBoxContainer.new()
	panel.name = "Roads"
	tabs.add_child(panel)
	studio.label(panel, "Road drawing settings", 14)
	width = OptionButton.new()
	width.add_item("Narrow · 1 tile / 2 units")
	width.add_item("Standard · 3 tiles / 6 units")
	width.select(1)
	panel.add_child(width)
	sidewalks = CheckBox.new()
	sidewalks.text = "Include sidewalks"
	sidewalks.button_pressed = true
	panel.add_child(sidewalks)
	style = OptionButton.new()
	for title in ["Asphalt", "Brick paving", "Gravel"]: style.add_item(title)
	panel.add_child(style)
	cycling = OptionButton.new()
	cycling.accessibility_name = "Cycle access for the road brush"
	for title in ["Keep cycle access", "Motor road", "Share with cycles", "Cycle path"]: cycling.add_item(title)
	cycling.select(0)
	panel.add_child(cycling)
	for entry in [["Draw / resurface roads", "road"], ["Toggle crossings", "crossing"], ["Remove roads", "road_erase"]]:
		studio.button(panel, entry[0], "tool", "Drag to edit road sections with the selected settings", entry[1])
	studio.label(panel, "Draw over existing sections to change their width, surface and sidewalks. Compatible roads connect automatically, with width and material transitions. Narrow roads have smaller lane offsets. Removing roads reveals the previous ground. Each drag is one undo step.", 12).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func settings() -> Dictionary:
	var result: Dictionary = {"width": 2 if width.selected == 0 else 6, "sidewalks": sidewalks.button_pressed, "style": STYLES[style.selected]}
	if cycling.selected > 0: result["cycle_access"] = CYCLE_ACCESS[cycling.selected-1]
	return result

func restore(value: Dictionary) -> void:
	width.select(0 if value.get("width", 6) == 2 else 1)
	sidewalks.set_pressed_no_signal(bool(value.get("sidewalks", true)))
	style.select(maxi(0, STYLES.find(value.get("style", "asphalt"))))
	cycling.select(CYCLE_ACCESS.find(value.get("cycle_access", ""))+1)
