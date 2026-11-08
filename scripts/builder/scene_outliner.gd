extends RefCounted

const Layers = preload("res://scripts/builder/layers.gd")
var studio: Control
var panel: VBoxContainer
var search: LineEdit
var tree: Tree
var refreshing: bool = false
var previous: int = 0

func _init(owner_control: Control, tabs: TabContainer) -> void:
	studio = owner_control
	panel = VBoxContainer.new()
	panel.name = "Scene"
	tabs.add_child(panel)
	search = LineEdit.new()
	search.placeholder_text = "Find object, layer or group"
	search.clear_button_enabled = true
	panel.add_child(search)
	search.text_changed.connect(func(_text: String): refresh(true))
	tree = Tree.new()
	tree.columns = 3
	tree.hide_root = true
	tree.column_titles_visible = true
	tree.set_column_title(0, "Objects / groups")
	tree.set_column_title(1, "Show")
	tree.set_column_title(2, "Lock")
	for column in [1, 2]:
		tree.set_column_expand(column, false)
		tree.set_column_custom_minimum_width(column, 44)
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(tree)
	tree.item_selected.connect(select_item)
	tree.item_edited.connect(edit_item)
	var hint := Label.new()
	hint.text = "Double-click a name to rename.\nHidden and locked objects stay protected."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(hint)

func refresh(force: bool = false) -> void:
	if studio.documents.is_empty(): return
	var rows: Array = []
	for item in studio.current().data["objects"]:
		rows.append([item["uid"], item["asset"], item.get("name", ""), item.get("group", ""), item.get("visible", true), item.get("locked", false), Layers.layer(item, studio.library)])
	var signature: int = hash([rows, studio.current().data.get("group_names", {}), studio.current().data.get("layers", {}), studio.selected_uids, studio.mode, search.text])
	if not force and signature == previous: return
	previous = signature
	refreshing = true
	tree.clear()
	var root: TreeItem = tree.create_item()
	var groups: Dictionary = {}
	var query: String = search.text.to_lower().strip_edges()
	for row in rows:
		var group: String = row[3]
		var group_name: String = studio.current().data.get("group_names", {}).get(group, "Group " + group)
		var name: String = row[2] if not str(row[2]).is_empty() else studio.library.assets.get(row[1], {}).get("name", row[1])
		if not query.is_empty() and not query in (name + " " + row[6] + " " + group_name).to_lower(): continue
		var parent: TreeItem = root
		if not group.is_empty():
			if not groups.has(group):
				var group_item: TreeItem = tree.create_item(root)
				group_item.set_text(0, group_name)
				group_item.set_metadata(0, {"group": group})
				group_item.set_editable(0, true)
				for column in [1, 2]:
					group_item.set_cell_mode(column, TreeItem.CELL_MODE_CHECK)
					group_item.set_editable(column, true)
					var values: Array = rows.filter(func(member: Array) -> bool: return member[3] == group)
					var first: bool = values[0][4 if column == 1 else 5]
					group_item.set_checked(column, first)
					group_item.set_indeterminate(column, values.any(func(member: Array) -> bool: return member[4 if column == 1 else 5] != first))
				groups[group] = group_item
			parent = groups[group]
		var entry: TreeItem = tree.create_item(parent)
		entry.set_text(0, name)
		entry.set_tooltip_text(0, "%s · %s\n%s" % [name, row[6], row[0]])
		entry.set_metadata(0, {"uid": row[0]})
		entry.set_editable(0, true)
		for column in [1, 2]:
			entry.set_cell_mode(column, TreeItem.CELL_MODE_CHECK)
			entry.set_editable(column, true)
			entry.set_checked(column, row[4] if column == 1 else row[5])
		if studio.selected_uids.has(row[0]): entry.select(0)
	refreshing = false

func select_item() -> void:
	if refreshing: return
	var selected: TreeItem = tree.get_selected()
	if not selected: return
	var info: Dictionary = selected.get_metadata(0)
	studio.selected_uids.clear()
	studio.selected_uid = ""
	for item in studio.current().data["objects"]:
		if (item["uid"] == info.get("uid") or (info.has("group") and item.get("group") == info["group"])) and Layers.editable(studio.current().data, item, studio.library): studio.selected_uids.append(item["uid"])
	if not studio.selected_uids.is_empty(): studio.selected_uid = studio.selected_uids[0]
	studio.set_tool("select")
	studio.call_deferred("refresh_controls")

func edit_item() -> void:
	if refreshing: return
	var edited: TreeItem = tree.get_edited()
	if not edited: return
	var column: int = tree.get_edited_column()
	var info: Dictionary = edited.get_metadata(0)
	call_deferred("apply_edit", info, column, edited.get_text(0) if column == 0 else edited.is_checked(column))

func apply_edit(info: Dictionary, column: int, value: Variant) -> void:
	if info.has("group"):
		studio.current().checkpoint()
		if column == 0:
			if not studio.current().data.has("group_names"): studio.current().data["group_names"] = {}
			studio.current().data["group_names"][info["group"]] = str(value).strip_edges().left(160)
		else:
			for item in studio.current().data["objects"]:
				if item.get("group") == info["group"]: item["visible" if column == 1 else "locked"] = bool(value)
	else:
		var item: Dictionary = studio.current().object(info.get("uid", ""))
		if item.is_empty(): return
		studio.current().checkpoint()
		if column == 0: item["name"] = str(value).strip_edges().left(160)
		else: item["visible" if column == 1 else "locked"] = bool(value)
	studio.changed()
