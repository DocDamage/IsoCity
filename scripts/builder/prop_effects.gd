extends RefCounted
var entries: Dictionary={}
var glow: Texture2D

func radial_texture() -> Texture2D:
	if glow: return glow
	var gradient:=Gradient.new(); gradient.set_color(0,Color.WHITE); gradient.set_color(1,Color(1,1,1,0))
	var texture:=GradientTexture2D.new(); texture.gradient=gradient; texture.width=128; texture.height=128; texture.fill=GradientTexture2D.FILL_RADIAL; texture.fill_from=Vector2(.5,.5); texture.fill_to=Vector2(.5,1)
	glow=texture; return glow

func apply(key: String,candidate: Dictionary,exploration: Node,on: bool,text: String) -> void:
	var node: Node=candidate["node"]; var mode: String=exploration.dimension; var profile: Dictionary=candidate["profile"]
	if entries.has(key) and entries[key]["node"].get_ref()!=node: release(key)
	if not entries.has(key):
		var effect: Node=Node2D.new() if mode=="2d" else Node3D.new(); effect.name="PropFeedback"; node.add_child(effect)
		var label: Node=Label.new() if mode=="2d" else Label3D.new(); effect.add_child(label)
		if mode=="2d": label.z_index=110; label.position=Vector2(-16,-18); label.add_theme_color_override("font_shadow_color",Color.BLACK); label.add_theme_constant_override("shadow_offset_x",1)
		else: label.billboard=BaseMaterial3D.BILLBOARD_ENABLED; label.font_size=26; label.position.y=.3
		var light: Node=PointLight2D.new() if mode=="2d" else OmniLight3D.new(); effect.add_child(light)
		if mode=="2d": light.texture=radial_texture(); light.texture_scale=.8; light.energy=.8
		else: light.omni_range=3.5; light.light_energy=1.5; light.shadow_enabled=false
		var color: Color=Color("ffd390") if profile["effect"]=="light" else Color("81cddc")
		if mode=="2d": light.color=color
		else: light.light_color=color
		var source: Node=node.source if node.has_method("mixed_bounds") else node
		entries[key]={"node":weakref(node),"effect":effect,"label":label,"light":light,"source":weakref(source),"playing":source.get("playing") if "playing" in source else null,"night":source.get("night_mode") if "night_mode" in source else null,"on":null,"kind":profile["kind"]}
	var entry: Dictionary=entries[key]; entry["effect"].global_position=preload("res://scripts/builder/prop_plan.gd").global_point(candidate,exploration)
	var linked: bool=profile["kind"]=="switch" and not str(profile.get("target","")).is_empty()
	entry["label"].text=text; entry["label"].visible=not text.is_empty(); entry["light"].visible=on and not linked
	var source: Node=entry["source"].get_ref()
	if is_instance_valid(source):
		if profile["kind"]=="appliance" and "playing" in source:
			source.playing=on
			if not on and source.has_node("Sprite2D"): source.get_node("Sprite2D").frame=0
		if profile["kind"]=="switch" and "night_mode" in source: source.night_mode=candidate["data"].get("night",false) if linked else on
		if entry["on"]!=on and node.has_method("mixed_bounds"): node.last_frame=""; node.update_visual()
	entry["on"]=on
	if entry["night"]!=null: entry["night"]=candidate["data"].get("night",false)

func release(key: String) -> void:
	if not entries.has(key): return
	var entry: Dictionary=entries[key]; var source: Node=entry["source"].get_ref()
	if is_instance_valid(source):
		if entry["playing"]!=null: source.playing=entry["playing"]
		if entry["night"]!=null: source.night_mode=entry["night"]
	if is_instance_valid(entry["effect"]): entry["effect"].free()
	var node: Node=entry["node"].get_ref()
	if is_instance_valid(node) and node.is_inside_tree() and node.has_method("mixed_bounds"): node.last_frame=""; node.update_visual()
	entries.erase(key)
func reset() -> void:
	for key in entries.keys(): release(key)
	glow=null
