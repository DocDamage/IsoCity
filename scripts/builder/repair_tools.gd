extends RefCounted

const Assets = preload("res://scripts/builder/repair_assets.gd")
const Repair = preload("res://scripts/builder/project_repair.gd")
const Store = preload("res://scripts/builder/project_store.gd")
var studio: Control
var bar: HBoxContainer
var caption: Label
var dialog: AcceptDialog
var text: RichTextLabel
var missing: ItemList
var query: LineEdit
var replacements: ItemList
var replace_button: Button
var report_file: FileDialog
var groups: Dictionary = {}

func _init(owner_control: Control, center: Node) -> void:
	studio = owner_control
	bar = HBoxContainer.new()
	center.add_child(bar)
	center.move_child(bar,1)
	caption = studio.label(bar,"",12)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.clip_text = true
	var button := Button.new()
	button.text = "Repair report…"
	button.pressed.connect(show)
	bar.add_child(button)
	bar.visible = false
	dialog = AcceptDialog.new()
	dialog.title = "Project repair report"
	studio.add_child(dialog)
	var box := VBoxContainer.new()
	dialog.add_child(box)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)
	text = RichTextLabel.new()
	text.name = "Report"
	text.custom_minimum_size = Vector2(760,360)
	text.bbcode_enabled = false
	tabs.add_child(text)
	var panel := VBoxContainer.new()
	panel.name = "Missing assets"
	tabs.add_child(panel)
	studio.label(panel,"Select a missing source, then search for a replacement. Positions and owned rooms stay with their objects.",12).clip_text = true
	missing = ItemList.new()
	missing.custom_minimum_size = Vector2(760,120)
	missing.item_selected.connect(func(_index:int): update_button())
	panel.add_child(missing)
	query = LineEdit.new()
	query.placeholder_text = "Find a replacement asset…"
	query.text_changed.connect(func(_value:String): search_replacements())
	panel.add_child(query)
	replacements = ItemList.new()
	replacements.custom_minimum_size = Vector2(760,120)
	replacements.item_selected.connect(func(_index:int): update_button())
	panel.add_child(replacements)
	var actions := HBoxContainer.new()
	panel.add_child(actions)
	replace_button = Button.new()
	replace_button.text = "Replace this missing source"
	replace_button.pressed.connect(replace_selected)
	actions.add_child(replace_button)
	var retry := Button.new()
	retry.text = "Retry original assets"
	retry.pressed.connect(retry_originals)
	actions.add_child(retry)
	var save_button := Button.new()
	save_button.text = "Save report as JSON…"
	save_button.pressed.connect(func(): report_file.current_file = "project_repair_report.json"; report_file.popup_centered(Vector2i(820,560)))
	box.add_child(save_button)
	report_file = FileDialog.new()
	report_file.access = FileDialog.ACCESS_FILESYSTEM
	report_file.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	report_file.filters = PackedStringArray(["*.json ; Repair report"])
	report_file.file_selected.connect(func(path:String): studio.status.text = "Repair report saved." if Store.write_json(path,studio.repair_report) else "Could not save the repair report.")
	studio.add_child(report_file)

func documents() -> Array:
	return [studio.current()] if studio.interior_tools.editing() else [studio.documents["2d"],studio.documents["3d"]]

func collect(data: Dictionary, result: Dictionary) -> void:
	for item in data["objects"]:
		if item.get("missing_asset") is Dictionary:
			var id: String = str(item["missing_asset"].get("id","Unknown original asset"))
			result[id] = result.get(id,0) + 1
		if item.get("interior") is Dictionary: collect(item["interior"],result)

func refresh() -> void:
	groups = {}
	for doc in documents(): collect(doc.data,groups)
	bar.visible = not studio.repair_report.is_empty() or not groups.is_empty()
	var count: int = 0
	for value in groups.values(): count += value
	caption.text = "Repair history · %d missing asset placeholders" % count + (" in this room" if studio.interior_tools.editing() else " across this project")

func show() -> void:
	refresh()
	var report: Dictionary = studio.repair_report
	var lines: Array[String] = ["Source: " + str(report.get("source","Recovered project")),"Original backup: " + str(report.get("source_backup","The original source file remains unchanged.")),"Time: " + str(report.get("time","")),"", "Repairs and archived records:"]
	for issue in report.get("issues",[]):
		if issue is Dictionary: lines.append(str(issue.get("path","")) + " · " + str(issue.get("message","")))
	lines.append("")
	lines.append("Original values and quarantined records are retained in the JSON report. Repaired projects open as unsaved copies.")
	text.text = "\n".join(lines)
	missing.clear()
	for id in groups:
		missing.add_item(id + " · %d objects/cells" % groups[id])
		missing.set_item_metadata(missing.item_count-1,id)
	search_replacements()
	dialog.popup_centered(Vector2i(studio.get_viewport().get_visible_rect().size-Vector2(64,64)).min(Vector2i(1000,650)))

func search_replacements() -> void:
	replacements.clear()
	var matches: Array = studio.library.find("all","All assets",query.text,[],false)
	for asset in matches.slice(0,80):
		replacements.add_item(asset["name"] + " · " + asset["mode"].to_upper() + " · " + asset["category"])
		replacements.set_item_metadata(replacements.item_count-1,asset["id"])
	update_button()

func update_button() -> void:
	replace_button.disabled = missing.get_selected_items().is_empty() or replacements.get_selected_items().is_empty()

func replace_selected() -> void:
	if replace_button.disabled: return
	var source: String = missing.get_item_metadata(missing.get_selected_items()[0])
	var target: String = replacements.get_item_metadata(replacements.get_selected_items()[0])
	apply_changes(source,target,false)

func retry_originals() -> void:
	preload("res://scripts/catalog.gd")._loaded = false
	var refreshed: RefCounted = load("res://scripts/builder/asset_library.gd").new()
	for id in refreshed.assets:
		if not studio.library.assets.has(id) or studio.library.assets[id].get("unavailable",false): studio.library.assets[id] = refreshed.assets[id]; studio.library.invalidate_icons(id)
	apply_changes("","",true)

func plan(data: Dictionary, source: String, target: String, retry: bool, changes: Array) -> void:
	for item in data["objects"]:
		if item.get("missing_asset") is Dictionary:
			var info: Dictionary = item["missing_asset"]
			var id: String = str(info.get("id",""))
			var destination: String = id if retry else target
			if (retry or id == source) and Assets.available(destination,studio.library,{}) and not studio.library.assets[destination].get("hidden",false):
				var restored: Dictionary = info.get("record",{}).duplicate(true)
				restored["asset"] = destination
				restored["uid"] = item["uid"]
				restored.erase("missing_asset")
				for key in ["position","scale","angle","tilt","group","layer","visible","locked","interior"]:
					if item.has(key): restored[key] = item[key]
				if item.has("name") and not item["name"].begins_with("Missing ground:"): restored["name"] = item["name"]
				if not retry: restored.erase("colors"); restored.erase("entrance_anchor")
				if not restored.get("direction") is String or not studio.library.valid_direction(destination,restored["direction"]): restored["direction"] = studio.library.directions(destination)[0]
				if info.get("kind") == "tile" and studio.library.is_ground_tile(destination) and studio.library.valid_direction(destination,item["direction"]): restored["direction"] = item["direction"]
				restored["recovered_missing_source"] = info.duplicate(true)
				restored = Repair.new(studio.library).object(restored,data["mode"],"restored/"+item["uid"],0)
				var tile: Dictionary = native_tile(item,restored,data)
				changes.append([item,tile,data] if not tile.is_empty() else [item,restored])
		if item.get("interior") is Dictionary: plan(item["interior"],source,target,retry,changes)

func native_tile(item: Dictionary, restored: Dictionary, data: Dictionary) -> Dictionary:
	if item["missing_asset"].get("kind") != "tile" or data["mode"] != "2d" or not studio.worlds["2d"].tile_lookup.has(restored["asset"]): return {}
	if item.has("interior") or item.has("group") or item.get("locked",false) or not item.get("visible",true) or item.get("layer","Ground") != "Ground": return {}
	if not is_equal_approx(item["scale"],1) or not is_zero_approx(item["position"][2]) or not is_zero_approx(item.get("angle",0)) or not Vector2(item.get("tilt",[0,0])[0],item.get("tilt",[0,0])[1]).is_zero_approx(): return {}
	if item.has("name") and not item["name"].begins_with("Missing ground:"): return {}
	var grid: Vector2 = preload("res://scripts/builder/grid_fit.gd").grid(Vector2(item["position"][0],item["position"][1]))
	if not grid.is_equal_approx(grid.round()): return {}
	var cell: Array = [roundi(grid.x),roundi(grid.y)]
	if data["tiles"].any(func(tile:Dictionary)->bool:return float(tile["cell"][0])==cell[0] and float(tile["cell"][1])==cell[1]): return {}
	var result: Dictionary = item["missing_asset"]["record"].duplicate(true)
	result["asset"] = restored["asset"]
	result["cell"] = cell
	result["direction"] = restored["direction"]
	result.erase("colors")
	if restored.has("colors"): result["colors"] = restored["colors"]
	result["recovered_missing_source"] = item["missing_asset"].duplicate(true)
	return result

func apply_changes(source: String, target: String, retry: bool) -> void:
	var count: int = 0
	for doc in documents():
		var changes: Array = []
		plan(doc.data,source,target,retry,changes)
		if changes.is_empty(): continue
		doc.checkpoint()
		for pair in changes:
			if pair.size() == 3:
				pair[2]["objects"].erase(pair[0])
				pair[2]["tiles"].append(pair[1])
			else:
				pair[0].clear()
				pair[0].merge(pair[1])
		count += changes.size()
	if count > 0:
		if studio.repair_report.is_empty(): studio.repair_report = {"issues":[]}
		studio.repair_report["issues"].append({"path":"missing assets","message":("Restored %d available original assets." % count) if retry else ("Replaced %d placeholders with %s." % [count,target])})
		studio.refresh_worlds()
		studio.changed()
	studio.status.text = "%d missing assets restored/replaced. Undo restores the placeholders." % count if count > 0 else "No original assets are available yet. Restore their source files or choose a replacement."
	show()
