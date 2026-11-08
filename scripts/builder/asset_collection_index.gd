extends RefCounted
const Plan=preload("res://scripts/builder/asset_collections.gd")
var source: Dictionary={}
var resolved: Dictionary={}
var library_id: int=0
var library_revision: int=-1
var builds: int=0
func active() -> bool:return not source.is_empty()
func clear() -> void:source={};resolved={};library_id=0;library_revision=-1
func choose(value: Dictionary,library: RefCounted) -> Dictionary:
	if active() and value==source:refresh(library);return {"ok":true}
	if not Plan.collection_valid(value):return Plan.failure("Choose a valid named collection or project recommendation.")
	# Capture the selected membership on its change, not on every search key.
	# The owning store's transient revision tells the UI when to choose again.
	source=value.duplicate(true);library_revision=-1;refresh(library);return {"ok":true}
func refresh(library: RefCounted,force: bool=false) -> void:
	if not active():return
	if not force and library_id==library.get_instance_id() and library_revision==library.families.revision:return
	resolved=Plan.resolve(source,library);library_id=library.get_instance_id();library_revision=library.families.revision;builds+=1
func filter(found: Array[Dictionary],library: RefCounted) -> Array[Dictionary]:
	if not active():return found
	refresh(library);var result: Array[Dictionary]=[]
	for asset in found:
		if resolved["available"].has(asset["id"]):result.append(asset)
	return result
