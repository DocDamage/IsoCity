extends RefCounted
static var views: Dictionary={}

# A view may select one authored strip inside a shared atlas. Legacy files remain full strips.
static func path(view: Dictionary) -> String:
	var relative: String=view.get("file","")
	if relative.begins_with("res://"): return relative
	if relative.begins_with("../../"): return "res://assets/"+relative.trim_prefix("../../")
	return "res://assets/pixel_isometric/"+relative
static func region(view: Dictionary,texture: Texture2D) -> Rect2:
	var raw: Array=view.get("region",[])
	return Rect2(raw[0],raw[1],raw[2],raw[3]) if raw.size()==4 else Rect2(Vector2.ZERO,texture.get_size())
static func texture(view: Dictionary) -> Texture2D:
	var location: String=path(view)
	if not ResourceLoader.exists(location): return null
	var source: Texture2D=load(location)
	if not source or not view.has("region"): return source
	var area: Rect2=region(view,source); var key: String=location+str(area)
	if views.has(key):
		var cached: Object=views[key].get_ref()
		if cached: return cached as Texture2D
	var result:=AtlasTexture.new(); result.atlas=source; result.region=area; result.filter_clip=true
	if views.size()>=256: views.erase(views.keys()[0])
	views[key]=weakref(result); return result
