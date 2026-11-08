extends RefCounted
const Health=preload("res://scripts/builder/asset_health.gd")
const Preview=preload("res://scripts/builder/model_preview.gd")
const Renderer=preload("res://scripts/builder/model_thumbnail.gd")
const View=preload("res://scripts/sprite_view.gd")
var library: RefCounted
var renderer: RefCounted
var proposal: Dictionary={}
var error: String=""
var generation: int=0
var backup_root: String="res://output/asset_preview_repairs"
var allowed_roots: Array[String]=["res://resources/previews_3d/","res://assets/supplemental_models/"]

func _init(host: RefCounted,tree: SceneTree) -> void:
	library=host;renderer=Renderer.new(tree)

func cancel() -> void:
	generation+=1;renderer.cancel();proposal.clear()

func target_allowed(path: String) -> bool:
	if path.get_extension().to_lower()!="png" or not path.begins_with("res://") or path!=path.simplify_path() or ".." in path.trim_prefix("res://").split("/"):return false
	for prefix in allowed_roots:
		if path.begins_with(prefix):return true
	return false

static func same_file(a: String,b: String) -> bool:
	var first: String=ProjectSettings.globalize_path(a).simplify_path();var second: String=ProjectSettings.globalize_path(b).simplify_path()
	return first.to_lower()==second.to_lower() if OS.get_name()=="Windows" else first==second

static func uses_source(asset: Dictionary,target: String) -> bool:
	var data: Variant=asset.get("data",{})
	if not data is Dictionary:return false
	var sources: Variant=data.get("source_files",[])
	if sources is Array:
		for source in sources:
			if source is String and same_file(source,target):return true
	if asset.get("mode")!="2d":return false
	var sets: Array=[data.get("directions",{})];var animations: Variant=data.get("animations",{})
	if animations is Dictionary:
		for entry in animations.values():
			if entry is Dictionary:sets.append(entry.get("directions",{}))
	for views in sets:
		if not views is Dictionary:continue
		for view in views.values():
			if view is Dictionary and view.get("file") is String and same_file(View.path(view),target):return true
	return false

func plan(issue: Dictionary) -> Dictionary:
	if issue.get("repair")!="model_preview" or not issue.get("affected_ids") is Array or issue["affected_ids"].is_empty():return {"ok":false,"message":"This issue needs source/metadata review; automatic repair changes only derived model previews."}
	var target: Variant=issue.get("path")
	if not target is String or not target_allowed(target):return {"ok":false,"message":"Automatic repair is limited to prepared catalog thumbnail locations; source art is preserved."}
	var scene: String="";var owners: Array=[];var snapshots: Dictionary={}
	for id in issue["affected_ids"]:
		if not id is String or not library.assets.has(id):return {"ok":false,"message":"An affected asset was removed. Rescan before preparing a repair."}
		var asset: Dictionary=library.assets[id]
		if asset.get("mode")!="3d" or not same_file(Health.preview_path(asset),target):return {"ok":false,"message":"An affected preview reference changed. Rescan before preparing a repair."}
		if not asset.get("path") is String or asset["path"].is_empty():return {"ok":false,"message":"The prepared scene reference is invalid. Repair its metadata before rebuilding a thumbnail."}
		if scene.is_empty():scene=asset["path"]
		if asset.get("path")!=scene:return {"ok":false,"message":"Different prepared model scenes share this preview. Separate their preview paths before rebuilding."}
		owners.append(id)
	# Include every current owner, even if the audit was filtered/interrupted.
	for id in library.assets:
		var asset: Dictionary=library.assets[id]
		if uses_source(asset,target):return {"ok":false,"message":"The thumbnail path is also supplied source art. Automatic replacement is unavailable."}
		if not same_file(Health.preview_path(asset),target):continue
		if asset.get("mode")!="3d" or asset.get("path")!=scene:return {"ok":false,"message":"This target is also used by different source art. Automatic replacement is unavailable."}
		if id not in owners:owners.append(id)
	var audit: RefCounted=Health.new();var visited: Dictionary={};var errors: Array=audit.dependency_errors(scene,visited)
	if not errors.is_empty():return {"ok":false,"message":"Prepared dependencies need attention first: "+errors[0]["detail"]+" "+errors[0]["path"]}
	for path in visited:
		if path==target:return {"ok":false,"message":"The thumbnail path is also prepared source art; it cannot be overwritten."}
		if not Preview.import_current(path):return {"ok":false,"message":"Refresh the prepared source import before rendering: "+path}
		snapshots[path]=FileAccess.get_sha256(path)
		if FileAccess.file_exists(path+".import"):snapshots[path+".import"]=FileAccess.get_sha256(path+".import")
		if path.get_extension().to_lower() in ["glb","gltf"]:
			# The measured import parameters establish which prepared import was
			# reviewed. A raw source hash alone cannot verify changed settings.
			var verified: bool=false
			for id in owners:
				var source: Dictionary=library.styles.evidence.get(id,{}).get("sources",{}).get(path,{})
				if source.get("sha256")==snapshots[path] and source.get("import_parameters")==library.styles.import_parameters(path):verified=true
			if not verified:return {"ok":false,"message":"Refresh prepared imports and their measured source facts before rebuilding this preview: "+path}
	for path in ["res://scripts/builder/model_thumbnail.gd","res://scripts/builder/model_preview.gd","res://scripts/model_bounds.gd"]:snapshots[path]=FileAccess.get_sha256(path)
	owners.sort()
	var settings: Dictionary={"settings":Renderer.SETTINGS,"engine":Engine.get_version_info()["string"],"renderer":RenderingServer.get_current_rendering_method()}
	var key: String=JSON.stringify({"sources":snapshots,"settings":settings},"",true).sha256_text()
	return {"ok":true,"path":target,"scene":scene,"affected_ids":owners,"sources":snapshots,"settings":settings,"key":key,"before_sha256":FileAccess.get_sha256(target) if FileAccess.file_exists(target) else "missing"}

static func read_cache(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):return {}
	var json:=JSON.new()
	return json.data if json.parse(FileAccess.get_file_as_string(path))==OK and json.data is Dictionary else {}

func prepare(issue: Dictionary) -> Dictionary:
	cancel();error="";var request: int=generation;var candidate: Dictionary=plan(issue)
	if not candidate["ok"]:error=candidate["message"];return candidate
	var cache: Dictionary=read_cache(candidate["path"]+".isocity-preview.json")
	if cache.get("version")==1 and cache.get("key")==candidate["key"] and cache.get("sha256")==candidate["before_sha256"] and Preview.meaningful_image(Preview.read_image(candidate["path"])):return {"ok":true,"current":true,"message":"The preview is already current; no files changed.","affected_ids":candidate["affected_ids"]}
	var image: Image=await renderer.render(candidate["scene"])
	if request!=generation:return {"ok":false,"cancelled":true,"message":"Repair preview cancelled; no thumbnail was changed."}
	if not image:error=renderer.error;return {"ok":false,"message":error}
	var current: Dictionary=plan(issue)
	if not current["ok"] or current["key"]!=candidate["key"] or current["before_sha256"]!=candidate["before_sha256"] or current["affected_ids"]!=candidate["affected_ids"]:error="Source, thumbnail or affected IDs changed during rendering. Rescan before applying a repair.";return {"ok":false,"message":error}
	candidate["image"]=image;proposal=candidate
	return {"ok":true,"current":false,"affected_ids":candidate["affected_ids"],"path":candidate["path"],"image":image,"message":"Review the rendered thumbnail and every affected ID before applying. Source files and city objects are unchanged."}

func apply() -> Dictionary:
	if proposal.is_empty():return {"ok":false,"message":"Prepare and review a repair preview first."}
	var issue: Dictionary={"repair":"model_preview","path":proposal["path"],"affected_ids":proposal["affected_ids"]}
	var current: Dictionary=plan(issue)
	if not current["ok"] or current["key"]!=proposal["key"] or current["before_sha256"]!=proposal["before_sha256"] or current["affected_ids"]!=proposal["affected_ids"]:return {"ok":false,"message":"Source, thumbnail or affected IDs changed after review. Prepare a fresh repair preview."}
	var target: String=proposal["path"];var backup: String=""
	if FileAccess.file_exists(target):
		backup=backup_root.path_join(proposal["before_sha256"]+".png")
		if FileAccess.file_exists(backup_root):return {"ok":false,"message":"Cannot create a recoverable thumbnail backup; no files changed."}
		if DirAccess.make_dir_recursive_absolute(backup_root)!=OK:return {"ok":false,"message":"Cannot create a recoverable thumbnail backup; no files changed."}
		if not FileAccess.file_exists(backup) and DirAccess.copy_absolute(target,backup)!=OK:return {"ok":false,"message":"Cannot preserve the previous thumbnail; no files changed."}
		if FileAccess.get_sha256(backup)!=proposal["before_sha256"]:return {"ok":false,"message":"The recovery copy does not match the previous thumbnail; no files changed."}
	var result: Error=Renderer.write_validated(proposal["image"],target)
	if result!=OK:return {"ok":false,"message":"Thumbnail could not be saved; the previous file is retained. "+error_string(result)}
	var cache: Dictionary={"version":1,"key":proposal["key"],"sources":proposal["sources"],"settings":proposal["settings"],"sha256":FileAccess.get_sha256(target)}
	var text: String=JSON.stringify(cache,"\t",true)+"\n";var cache_path: String=target+".isocity-preview.json";var staged: String=cache_path+".partial"
	var stream:=FileAccess.open(staged,FileAccess.WRITE);var cached: bool=false
	if stream:
		stream.store_string(text);stream.close()
		cached=FileAccess.get_file_as_string(staged)==text and DirAccess.rename_absolute(staged,cache_path)==OK
	if not cached:DirAccess.remove_absolute(staged)
	var affected: Array=proposal["affected_ids"].duplicate()
	var texture: Texture2D=ImageTexture.create_from_image(proposal["image"])
	for id in affected:library.icons[id]=texture
	proposal.clear()
	return {"ok":true,"affected_ids":affected,"path":target,"backup":backup,"cached":cached,"message":"Thumbnail saved; source art, IDs, geometry, transforms and city history are unchanged."+(" Its derived cache record could not be saved; the thumbnail remains valid." if not cached else "")}
