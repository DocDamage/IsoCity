extends RefCounted
const Plan=preload("res://scripts/builder/asset_collections.gd")
const Delta=preload("res://scripts/builder/document_delta.gd")
const HISTORY_LIMIT=32
const HISTORY_BYTES=16*1024*1024
# An absent palette stays absent in old projects. Personal collections and
# their browsing selection never enter this shared project metadata document.
var data: Dictionary={}
var undo_history: Array[Dictionary]=[]
var redo_history: Array[Dictionary]=[]
var revision: int=0
func restore(value: Variant) -> Dictionary:
	if not value is Dictionary or (not value.is_empty() and not Plan.project_valid(value)):return Plan.failure("The project palette is invalid. Current metadata and history were preserved.")
	var normalized: Dictionary=value.duplicate(true)
	if not normalized.is_empty():normalized["version"]=1
	var changed: bool=normalized!=data;data=normalized
	if changed:revision+=1
	undo_history.clear();redo_history.clear();return {"ok":true,"changed":changed}
func propose(value: Dictionary) -> Dictionary:
	if not value.is_empty() and not Plan.project_valid(value):return Plan.failure("Choose a valid bounded project recommendation palette.")
	var normalized: Dictionary=value.duplicate(true)
	if not normalized.is_empty():normalized["version"]=1
	return {"ok":true,"changed":normalized!=data,"data":normalized,"source_hash":Plan.fingerprint(data),"review_hash":Plan.fingerprint(normalized)}
func apply(proposal: Dictionary) -> Dictionary:
	if not proposal.get("ok",false) or not proposal.get("data") is Dictionary:return Plan.failure("Review a valid project palette before applying it.")
	var value: Dictionary=proposal["data"]
	if (not value.is_empty() and not Plan.project_valid(value)) or proposal.get("source_hash")!=Plan.fingerprint(data) or proposal.get("review_hash")!=Plan.fingerprint(value):return Plan.failure("The project palette or reviewed proposal changed. Refresh before applying.")
	if value==data:return {"ok":true,"changed":false}
	var delta: Dictionary=Delta.between(data,value);var entry: Dictionary={"delta":delta,"source_hash":Plan.fingerprint(data),"target_hash":Plan.fingerprint(value),"bytes":JSON.stringify(delta).to_utf8_buffer().size()}
	data=value.duplicate(true);revision+=1;undo_history.append(entry);redo_history.clear();trim_history();return {"ok":true,"changed":true}
func trim_history() -> void:
	var total: int=0
	for entry in undo_history:total+=entry["bytes"]
	while undo_history.size()>HISTORY_LIMIT or (total>HISTORY_BYTES and undo_history.size()>1):total-=int(undo_history.pop_front()["bytes"])
func history(redo: bool=false) -> Dictionary:
	var source: Array[Dictionary]=redo_history if redo else undo_history
	if source.is_empty():return Plan.failure("No project palette changes to "+("redo." if redo else "undo."))
	var entry: Dictionary=source.back();var expected: String=entry["source_hash"] if redo else entry["target_hash"]
	if Plan.fingerprint(data)!=expected:return Plan.failure("Project metadata changed outside this history. Refresh before undoing it.")
	var result: Dictionary=data.duplicate(true);Delta.apply(result,entry["delta"],redo)
	var target_hash: String=entry["target_hash"] if redo else entry["source_hash"]
	if Plan.fingerprint(result)!=target_hash or (not result.is_empty() and not Plan.project_valid(result)):return Plan.failure("That history step no longer produces a valid project palette.")
	data=result;revision+=1;source.pop_back();var destination: Array[Dictionary]=undo_history if redo else redo_history;destination.append(entry);return {"ok":true,"changed":true}
