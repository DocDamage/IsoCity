extends RefCounted
const Collections=preload("res://scripts/builder/asset_collections.gd")

# Project policy is separate from advisory browser selection. Compile only when
# the common metadata changes; never turn a reference into an asset descriptor.
static func compile(policy: Dictionary) -> Dictionary:
	var ids: Dictionary={}
	for entry in policy.get("collection",{}).get("entries",[]):
		if entry["kind"]=="asset":ids[entry["id"]]=true
		else:
			for item in entry["members"]:ids[item["id"]]=true
	return ids
static func restricted(library: RefCounted) -> bool:return library!=null and library.project_palette.get("restricted",false)
static func allowed(id: String,library: RefCounted) -> bool:return not restricted(library) or library.project_palette_ids.has(id)
static func excluded(id: String,library: RefCounted) -> String:
	return "Project content restriction excludes “%s” (%s). Ask the project owner to add it to the palette or disable the restriction."%[library.assets.get(id,{}).get("name",id),id]
static func compare(before: Dictionary,after: Dictionary,ids: Dictionary,library: RefCounted) -> Dictionary:
	var old: Dictionary=Collections.records(before);var next: Dictionary=Collections.records(after);var blocked: Array=[]
	for path in next:
		if next[path]!=old.get(path) and not ids.has(next[path]):blocked.append({"scope":path,"id":next[path]})
	return {"ok":blocked.is_empty(),"blocked":blocked,"reason":"" if blocked.is_empty() else excluded(blocked[0]["id"],library),"code":"" if blocked.is_empty() else "palette.excluded"}
static func check(before: Dictionary,after: Dictionary,library: RefCounted) -> Dictionary:
	return compare(before,after,library.project_palette_ids,library) if restricted(library) else {"ok":true,"blocked":[],"reason":""}
static func check_config(before: Dictionary,after: Dictionary,policy: Dictionary,library: RefCounted) -> Dictionary:
	if policy.is_empty():return {"ok":true,"blocked":[],"reason":""}
	if not Collections.project_valid(policy):return {"ok":false,"reason":"Review the unreadable project palette before construction."}
	return compare(before,after,compile(policy),library) if policy["restricted"] else {"ok":true,"blocked":[],"reason":""}
