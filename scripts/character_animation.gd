@tool
extends RefCounted

var actor: Node2D
var clips: Dictionary
var current: Dictionary={}
var current_view: Dictionary={}
var base_scale: float=1
var actions: Dictionary = {}
var fallback_reason: String = ""

func _init(owner: Node2D,definitions: Dictionary,scale_value: float=1,semantic_actions: Dictionary={}) -> void:
	actor=owner; clips=definitions; base_scale=maxf(.001,scale_value); actions=semantic_actions

func available_direction(views: Dictionary, requested: String) -> String:
	if views.has(requested): return requested
	var aliases: Dictionary = {"N":"NW", "E":"NE", "S":"SE", "W":"SW"}
	if views.has(aliases.get(requested, "")): return aliases[requested]
	if views.has("SE"): return "SE"
	var keys: Array = views.keys(); keys.sort()
	return str(keys[0]) if not keys.is_empty() else ""
static func resolve_pose(clips: Dictionary,actions: Dictionary,requested: String) -> Dictionary:
	var fallback_reason: String = ""
	var config: Dictionary = actions.get(requested, {})
	var key: String = config.get("clip", requested if requested in ["idle", "walk"] else "")
	if requested == "run" and config.is_empty() and clips.has("walk"):
		key = "walk"; fallback_reason = "No supplied run clip; using walk."
	elif config.has("fallback"): fallback_reason = "No supplied " + requested + " clip; using " + config["fallback"] + "."
	if not clips.has(key):
		key = actions.get("idle", {}).get("clip", "idle")
		fallback_reason = "No supported " + requested + " pose; showing idle."
	return {"clip":key,"config":config,"reason":fallback_reason,"available":clips.has(key) and not clips[key].is_empty()}

func apply_view() -> void:
	var sprite: Sprite2D=actor.get_node_or_null("Sprite2D")
	if not sprite or clips.is_empty(): return
	var resolved: Dictionary=resolve_pose(clips,actions,actor.action)
	var key: String=resolved["clip"];var config: Dictionary=resolved["config"];fallback_reason=resolved["reason"]
	current = clips.get(key, {}).duplicate(); current_view = {}
	if current.is_empty():
		fallback_reason = "No supported idle clip; keeping the base pose."
		actor.set_meta("animation_fallback", fallback_reason)
		return
	if config.has("loop"): current["loop"] = config["loop"]
	actor.set_meta("animation_fallback", fallback_reason)
	var views: Dictionary=current.get("directions",{})
	if views.is_empty(): return
	var direction: String=available_direction(views, actor.direction)
	if direction != actor.direction:
		fallback_reason += (" " if not fallback_reason.is_empty() else "") + "No supplied " + actor.direction + " view; showing " + direction + "."
		actor.set_meta("animation_fallback", fallback_reason)
	current_view=views[direction]; var texture: Texture2D=preload("res://scripts/sprite_view.gd").texture(current_view)
	if not texture:
		fallback_reason = "The requested source frames are unavailable; showing idle."
		current = clips.get(actions.get("idle", {}).get("clip", "idle"), {}).duplicate()
		var idle_views: Dictionary = current.get("directions", {})
		var idle_direction: String = available_direction(idle_views, actor.direction)
		current_view = idle_views.get(idle_direction, {})
		texture = preload("res://scripts/sprite_view.gd").texture(current_view) if not current_view.is_empty() else null
		actor._anim_timer = 0; actor._anim_frame_idx = 0
		actor.set_meta("animation_fallback", fallback_reason)
		if not texture:
			current_view = {}; sprite.frame = 0
			return
	sprite.texture=texture; sprite.hframes=maxi(1,int(current_view.get("frames",1))); sprite.vframes=1
	var pivot: Array=current_view.get("actor_origin",current_view.get("origin",[0,0])); actor.origin_offset=Vector2(pivot[0],pivot[1])
	sprite.offset=-actor.origin_offset+actor.terrain_visual_offset+actor.interaction_visual_offset
	sprite.scale=Vector2.ONE*float(current.get("scale",base_scale))/base_scale
	sprite.frame=mini(actor._anim_frame_idx,sprite.hframes-1)
func tick(delta: float) -> void:
	var sprite: Sprite2D=actor.get_node_or_null("Sprite2D")
	if not sprite or current_view.is_empty() or not is_finite(delta) or delta <= 0: return
	var rate: float = float(current.get("fps",8))
	if not is_finite(rate): rate = 8
	actor._anim_timer+=minf(delta, .25)*clampf(rate, .1, 120)
	if actor._anim_timer>=1:
		var count: int=maxi(1,int(current_view.get("frames",1))); var next: int=actor._anim_frame_idx+int(actor._anim_timer)
		actor._anim_frame_idx=posmod(next,count) if current.get("loop",true) else mini(next,count-1)
		actor._anim_timer=fmod(actor._anim_timer,1); sprite.frame=actor._anim_frame_idx
