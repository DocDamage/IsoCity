extends RefCounted
const DEFINITIONS="res://resources/catalog/asset_themes.json"
const METADATA="res://resources/catalog/asset_theme_metadata.json"
const KEYS=["hanx_modern","pixel_city","village","industrial","space","historical"]
const LABELS=["HanX modern","Pixel City","Village","Industrial","Space","Historical"]
var definitions: Dictionary={}
var members: Dictionary={}
var index: Dictionary={}
var revision: int=0
var thumbnails: Dictionary={}

static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):return {}
	var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary and value.get("version")==1 else {}

func valid(value: Variant) -> Array[String]:
	var result: Array[String]=[]
	if value is Array:
		for key in KEYS:
			if value.has(key):result.append(key)
	return result

func build(assets: Dictionary) -> void:
	definitions.clear();members.clear();index.clear();thumbnails.clear()
	var source: Variant=read(DEFINITIONS).get("definitions",{})
	for position in KEYS.size():
		var key: String=KEYS[position];var definition: Variant=source.get(key,{}) if source is Dictionary else {}
		definitions[key]={"label":LABELS[position],"description":"Browse this collection.","icon":"build","preview_id":""}
		if definition is Dictionary:
			for field in ["label","description","icon","preview_id"]:
				if definition.get(field) is String and not definition[field].strip_edges().is_empty():definitions[key][field]=definition[field]
		members[key]={}
	members["unclassified"]={}
	var overlay: Variant=read(METADATA).get("assets",{})
	if not overlay is Dictionary:overlay={}
	for id in assets:
		var asset: Dictionary=assets[id];var data: Dictionary=asset["data"]
		var entry: Variant=overlay.get(id,{}) if not id.contains(":Custom/") else {"themes":data.get("themes",[]),"theme_note":"Collection tags supplied with this custom asset."}
		if not entry is Dictionary:entry={}
		var selected: Array[String]=valid(entry.get("themes",[]))
		var note: Variant=entry.get("theme_note","")
		data["themes"]=selected
		data["theme_note"]=note if note is String and not note.is_empty() and not selected.is_empty() else "No reviewed theme yet. Everything includes this asset."
		data["theme_labels"]=[]
		index[id]=selected
		for key in selected:
			members[key][id]=true;data["theme_labels"].append(label(key))
		if selected.is_empty():members["unclassified"][id]=true
	revision+=1

func label(key: String) -> String:
	if key.is_empty():return "Everything"
	if key=="unclassified":return "Unclassified"
	return definitions.get(key,{}).get("label",key)

func tags(asset: Dictionary) -> Array:
	return index.get(asset["id"],valid(asset.get("data",{}).get("themes",[])))

func matches(asset: Dictionary,key: String) -> bool:
	if key.is_empty():return true
	if key=="unclassified":return tags(asset).is_empty()
	return members.get(key,{}).has(asset["id"])

func describe(asset: Dictionary) -> String:
	var labels: Array[String]=[]
	for key in tags(asset):labels.append(label(key))
	return "Themes: "+(", ".join(labels) if not labels.is_empty() else "Unclassified")+"\n"+str(asset.get("data",{}).get("theme_note","No reviewed theme yet. Everything includes this asset."))

func fill(choice: OptionButton,library: RefCounted) -> void:
	choice.clear();choice.fit_to_longest_item=false;choice.clip_text=true
	var fallback_icons: Array[int]=[0]
	choice.add_icon_item(preload("res://scripts/builder/consumer_theme.gd").icon("layers"),"Everything");choice.set_item_metadata(0,"")
	for key in KEYS:
		var definition: Dictionary=definitions[key]
		var texture: Texture2D=library.icon(definition["preview_id"]) if library.assets.has(definition["preview_id"]) else null
		if not texture:
			texture=preload("res://scripts/builder/consumer_theme.gd").icon(definition["icon"]);fallback_icons.append(choice.item_count)
		var key_texture: int=texture.get_instance_id()
		if not thumbnails.has(key_texture):
			var picture: Image=texture.get_image()
			if picture.is_compressed():picture.decompress()
			var factor: float=minf(1.0,32.0/maxi(picture.get_width(),picture.get_height()))
			picture.resize(maxi(1,roundi(picture.get_width()*factor)),maxi(1,roundi(picture.get_height()*factor)),Image.INTERPOLATE_NEAREST)
			thumbnails[key_texture]=ImageTexture.create_from_image(picture)
		texture=thumbnails[key_texture]
		choice.add_icon_item(texture,label(key));choice.set_item_metadata(choice.item_count-1,key)
		choice.get_popup().set_item_tooltip(choice.item_count-1,definition["description"])
	choice.add_icon_item(preload("res://scripts/builder/consumer_theme.gd").icon("menu"),"Unclassified");choice.set_item_metadata(choice.item_count-1,"unclassified")
	fallback_icons.append(choice.item_count-1);choice.set_meta("theme_fallback_icons",fallback_icons)
	choice.get_popup().about_to_popup.connect(func():
		for position in fallback_icons:choice.get_popup().set_item_icon_modulate(position,choice.get_popup().get_theme_color("font_color"))
	)
	choice.item_selected.connect(func(_position: int):style_icon(choice))
	choice.add_theme_constant_override("icon_max_width",32)
	for position in choice.item_count:choice.get_popup().set_item_icon_max_width(position,40)
	choice.tooltip_text="Theme collection · Everything includes every theme. Unclassified keeps assets without reviewed tags available."

static func select(choice: OptionButton,key: String) -> void:
	for position in choice.item_count:
		if choice.get_item_metadata(position)==key:choice.select(position);style_icon(choice);return
	choice.select(0);style_icon(choice)

static func style_icon(choice: OptionButton) -> void:
	var fallback: Array=choice.get_meta("theme_fallback_icons",[])
	for state in ["icon_normal_color","icon_hover_color","icon_focus_color","icon_pressed_color"]:
		if fallback.has(choice.selected):choice.remove_theme_color_override(state)
		else:choice.add_theme_color_override(state,Color.WHITE)
