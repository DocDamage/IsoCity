@tool
extends Control

const Catalog = preload("res://scripts/catalog.gd")
var model_categories: Dictionary={}

@onready var category_option: OptionButton = $VBox/CategoryOption
@onready var search_input: LineEdit = $VBox/SearchInput
@onready var item_grid: GridContainer = $VBox/Scroll/ItemGrid
@onready var count_label: Label = $VBox/CountLabel

func _ready() -> void:
	_populate_categories()
	_populate_items("Buildings")
	
	category_option.item_selected.connect(func(idx: int):
		var cat: String = category_option.get_item_text(idx)
		_populate_items(cat, search_input.text)
	)
	search_input.text_changed.connect(func(query: String):
		var cat: String = category_option.get_item_text(category_option.selected)
		_populate_items(cat, query)
	)

func _populate_categories() -> void:
	category_option.clear()
	category_option.add_item("All Categories")
	var cats: Array = Catalog.get_categories()
	for cat in cats:
		category_option.add_item(cat)
		
	model_categories.clear()
	for folder in DirAccess.get_directories_at("res://scenes/items_3d"):
		var label: String="3D "+("FireStation" if folder=="Fire_Station_PSX" else folder.trim_prefix("HanX_").replace("_"," "))
		model_categories[label]=folder; category_option.add_item(label)
	
	for idx in range(category_option.item_count):
		if category_option.get_item_text(idx) == "Buildings":
			category_option.select(idx)
			break

func _populate_items(category_filter: String, search_text: String = "") -> void:
	for child in item_grid.get_children():
		child.queue_free()
		
	var items_to_show: Array = []
	var reg: Dictionary = Catalog.get_registry()
	var all_items: Dictionary = reg.get("items", {})
	
	if category_filter.begins_with("3D "):
		# Handle 3D categories
		var sub := category_filter.replace("3D ", "")
		var pack_dir: String=model_categories.get(category_filter,"HanX_" + sub if sub != "FireStation" else "Fire_Station_PSX")
		var tdir := "res://scenes/items_3d/" + pack_dir
		var da := DirAccess.open(tdir)
		if da:
			da.list_dir_begin()
			var fn := da.get_next()
			while fn != "":
				if fn.ends_with(".tscn"):
					items_to_show.append(model_item(pack_dir,fn,category_filter))
				fn = da.get_next()
	elif category_filter == "All Categories":
		for iid in all_items:
			items_to_show.append(all_items[iid])
		for category in model_categories:
			var folder: String = model_categories[category]
			var directory: String = "res://scenes/items_3d/" + folder
			for file in DirAccess.get_files_at(directory):
				if file.ends_with(".tscn"):
					items_to_show.append(model_item(folder,file,category))
	else:
		var cat_items: Array = Catalog.get_items_in_category(category_filter)
		for iid in cat_items:
			if all_items.has(iid):
				items_to_show.append(all_items[iid])
				
	var query: String = search_text.to_lower().strip_edges()
	var displayed_count: int = 0
	for it in items_to_show:
		var iname: String = it.get("name", "")
		var dname: String = it.get("display_name", iname)
		if not query.is_empty():
			if not (query in iname.to_lower().replace("_", " ") or query in dname.to_lower().replace("_", " ")):
				continue
				
		_create_dock_button(it)
		displayed_count += 1
		
	count_label.text = "Items: %d" % displayed_count

func _create_dock_button(item_data: Dictionary) -> void:
	var btn: Button = Button.new()
	var iname: String = item_data.get("name", "")
	var dname: String = item_data.get("display_name", iname).replace("_", " ")
	
	var scene_path: String = item_data.get("scene_path", "")
	if scene_path.is_empty():
		scene_path = Catalog.get_scene_path(iname)
			
	btn.text = dname
	btn.tooltip_text = "%s\nDrag into 2D or 3D scene viewport to place" % dname
	btn.custom_minimum_size = Vector2(130, 32)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.clip_text = true
	
	var icon_tex: Texture2D = _get_icon(item_data)
	if icon_tex:
		btn.icon = icon_tex
		btn.expand_icon = true
		
	# Custom drag script returning native {"type": "files", "files": [scene_path]}
	btn.set_script(preload("res://addons/isocity/dock_drag_button.gd"))
	btn.set("scene_path", scene_path)
	
	item_grid.add_child(btn)

func model_item(folder: String,file: String,category: String) -> Dictionary:
	var id: String="3d:"+folder+"/"+file.get_basename(); var descriptor: Dictionary=Catalog.get_registry().get("models",{}).get(id,{})
	var result: Dictionary={"name":file.get_basename(),"display_name":descriptor.get("name",file.get_basename().replace("_"," ")),"category":category,"scene_path":"res://scenes/items_3d/"+folder+"/"+file,"is_3d":true}
	if descriptor.get("data",{}).has("preview_path"): result["preview_path"]=descriptor["data"]["preview_path"]
	return result

func _get_icon(item_data: Dictionary) -> Texture2D:
	if item_data.has("preview_path"): return load(item_data["preview_path"])
	if item_data.get("is_3d", false):
		return null
	var dirs: Dictionary = item_data.get("directions", {})
	if dirs.is_empty():
		return null
	var pref: String = "SE" if dirs.has("SE") else dirs.keys()[0]
	var file_rel: String = dirs[pref].get("file", "")
	if not file_rel.is_empty():
		var full_res: String = "res://assets/pixel_isometric/" + file_rel
		if ResourceLoader.exists(full_res):
			return load(full_res)
		full_res = "res://assets/" + file_rel.replace("../../", "")
		if ResourceLoader.exists(full_res):
			return load(full_res)
	return null

