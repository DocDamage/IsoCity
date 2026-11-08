extends RefCounted

const INK=Color("273e47")
const MUTED=Color("64777c")
const PAPER=Color("f8f5ed")
const ACCENT=Color("287b6d")
static var icons: Dictionary={}

static func surface(color: Color=PAPER,radius: int=18,padding: int=16) -> StyleBoxFlat:
	var box:=StyleBoxFlat.new(); box.bg_color=color; box.set_corner_radius_all(radius)
	box.content_margin_left=padding; box.content_margin_right=padding; box.content_margin_top=padding; box.content_margin_bottom=padding
	box.shadow_color=Color(0.03,.09,.12,.17); box.shadow_size=12; box.shadow_offset=Vector2(0,4)
	return box

static func make() -> Theme:
	var result:=Theme.new(); var font:=SystemFont.new(); font.font_names=PackedStringArray(["Segoe UI Variable","Segoe UI","Arial"]); font.font_weight=500
	result.default_font=font; result.default_font_size=16
	for type in ["Label","Button","OptionButton","CheckBox","CheckButton","LineEdit","SpinBox","ItemList","Tree","TabBar","TabContainer","PopupMenu","RichTextLabel","Window"]:
		for key in ["font_color","font_hover_color","font_focus_color","font_selected_color","font_unselected_color","default_color","title_color"]: result.set_color(key,type,INK)
		result.set_color("font_disabled_color",type,Color("8b9799")); result.set_color("font_placeholder_color",type,MUTED)
	# Embedded windows retain Godot's dark title border in the light shell.
	result.set_color("title_color","Window",Color.WHITE)
	for state in ["normal","hover","pressed","disabled","focus"]:
		var box: StyleBoxFlat=surface(Color("eeeee5") if state=="normal" else Color("e0e9df") if state=="hover" else ACCENT if state=="pressed" else Color("eeeee5"),12,12)
		box.shadow_size=0
		if state=="focus": box.bg_color=Color.TRANSPARENT; box.set_border_width_all(3); box.border_color=Color("c08d3a")
		result.set_stylebox(state,"Button",box)
	result.set_color("font_pressed_color","Button",Color.WHITE)
	for key in ["icon_normal_color","icon_hover_color","icon_focus_color"]: result.set_color(key,"Button",INK)
	result.set_color("icon_pressed_color","Button",Color.WHITE)
	result.set_color("icon_disabled_color","Button",Color("9ba8a5"))
	result.set_constant("h_separation","Button",8)
	for type in ["PanelContainer","PopupPanel","PopupMenu","AcceptDialog"]: result.set_stylebox("panel",type,surface())
	var popup_hover: StyleBoxFlat=surface(Color("dbe9db"),6,6);popup_hover.shadow_size=0;result.set_stylebox("hover","PopupMenu",popup_hover)
	for type in ["LineEdit","TextEdit"]:
		for state in ["normal","read_only","focus"]:
			var box: StyleBoxFlat=surface(Color("e9ede7"),10,12); box.shadow_size=0
			if state=="focus": box.set_border_width_all(2); box.border_color=ACCENT
			result.set_stylebox(state,type,box)
		result.set_color("caret_color",type,INK); result.set_color("selection_color",type,Color("a9d5bf"))
	for type in ["ItemList","Tree","TabContainer"]:
		var frame: StyleBoxFlat=surface(PAPER,10,8); frame.shadow_size=0; result.set_stylebox("panel",type,frame)
		result.set_stylebox("selected",type,surface(Color("cde4d7"),8,6))
	for state in ["tab_selected","tab_unselected","tab_hovered"]:
		var tab: StyleBoxFlat=surface(Color("dbe9db") if state=="tab_selected" else PAPER,8,8); tab.shadow_size=0; result.set_stylebox(state,"TabContainer",tab)
	result.set_color("font_color","TooltipLabel",Color.WHITE); result.set_stylebox("normal","TooltipPanel",surface(INK,10,10))
	return result

static func icon(name: String) -> Texture2D:
	if icons.has(name): return icons[name]
	var shapes: Dictionary={
		"build":'<path d="M4 11 12 4l8 7v10h-6v-7h-4v7H4z"/>',
		"city":'<path d="M3 21V10h6v11m0-15h7v15m0-8h5v8M11 9h2m-2 4h2M5 13h2m-2 4h2m12-1h0"/>',
		"road":'<path d="m5 21 4-18m10 18L15 3M12 5v3m0 3v3m0 3v3"/>',
		"nature":'<path d="m12 3-7 9h4l-5 6h6v4h4v-4h6l-5-6h4z"/>',
		"people":'<circle cx="9" cy="7" r="3"/><path d="M3 21v-4a6 6 0 0 1 12 0v4m2-17a3 3 0 0 1 0 6m1 3a5 5 0 0 1 3 5v3"/>',
		"walk":'<circle cx="13" cy="4" r="2"/><path d="m9 22 2-7 4 3 1 4m-5-7 1-7 3 4h4M5 14l3-4 4-2"/>',
		"camera":'<path d="M3 8h5l2-3h5l2 3h4v12H3z"/><circle cx="12" cy="14" r="4"/>',
		"menu":'<path d="M4 6h16M4 12h16M4 18h16"/>',
		"save":'<path d="M4 3h13l4 4v14H4zM8 3v6h8V3M8 21v-8h9v8"/>',
		"undo":'<path d="m8 4-5 5 5 5M3 9h11a6 6 0 0 1 0 12"/>',
		"redo":'<path d="m16 4 5 5-5 5m5-5H10a6 6 0 0 0 0 12"/>',
		"close":'<path d="m6 6 12 12M6 18 18 6"/>',
		"rotate":'<path d="m17 3 4 5-6 1m5-1a9 9 0 1 0 1 8"/>',
		"move":'<path d="M12 2v20M2 12h20m-13-7 3-3 3 3m-6 14 3 3 3-3M5 9l-3 3 3 3m14-6 3 3-3 3"/>',
		"copy":'<rect x="8" y="8" width="13" height="13" rx="2"/><path d="M16 5V3H3v13h2"/>',
		"trash":'<path d="M3 6h18M9 6V3h6v3M6 6l1 15h10l1-15M10 10v7m4-7v7"/>',
		"sun":'<circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1 1m12 12 1 1M5 19l1-1M18 6l1-1"/>',
		"star":'<path d="m12 3 3 6 7 1-5 5 1 7-6-3-6 3 1-7-5-5 7-1z"/>',
		"settings":'<path d="M4 6h16M4 12h16M4 18h16"/><circle cx="8" cy="6" r="2"/><circle cx="16" cy="12" r="2"/><circle cx="10" cy="18" r="2"/>',
		"share":'<path d="M12 15V3m-4 4 4-4 4 4M5 12H3v9h18v-9h-2"/>',
		"furniture":'<path d="M5 12V5h14v7M3 11h4v5h10v-5h4v9H3zm2 9v2m14-2v2"/>',
		"layers":'<path d="m12 3 10 6-10 6L2 9zm-9 11 9 6 9-6M3 18l9 5 9-5"/>',
		"chevron":'<path d="m8 5 7 7-7 7"/>'}
	var svg: String='<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 24 24"><g fill="none" stroke="white" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">'+str(shapes.get(name,shapes["build"]))+'</g></svg>'
	var picture:=Image.new(); picture.load_svg_from_string(svg)
	icons[name]=ImageTexture.create_from_image(picture); return icons[name]
