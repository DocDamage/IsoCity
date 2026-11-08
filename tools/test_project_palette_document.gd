extends SceneTree
const Plan=preload("res://scripts/builder/asset_collections.gd")
const Project=preload("res://scripts/builder/project_palette_document.gd")
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func run() -> void:
	var doc:=Project.new();check(doc.data.is_empty() and doc.undo_history.is_empty(),"Old projects start without an invented palette or history")
	var proposed: Dictionary=Plan.project_empty();proposed["collection"]["name"]="Workshop recommendation";proposed["collection"]["entries"]=[{"kind":"asset","id":"3d:Uninstalled_Pack/Workbench","name":"Remembered workbench"}]
	var before: Dictionary=doc.data.duplicate(true);var review: Dictionary=doc.propose(proposed);check(review["ok"] and review["changed"] and doc.data==before and doc.undo_history.is_empty(),"Project proposal is read-only and may retain uninstalled recommendations")
	check(doc.apply(review)["ok"] and doc.data==proposed and doc.undo_history.size()==1,"Applying the reviewed project metadata creates one separate history step")
	check(not doc.apply(doc.propose(proposed))["changed"] and doc.undo_history.size()==1,"An unchanged recommendation creates no history")
	check(doc.history()["ok"] and doc.data==before,"Project palette Undo restores exact absence for a legacy project")
	check(doc.history(true)["ok"] and doc.data==proposed,"Project palette Redo restores exact names and missing identities")
	var selected: Dictionary=proposed.duplicate(true);selected["restricted"]=true;review=doc.propose(selected);var tampered: Dictionary=review.duplicate(true);tampered["data"]["collection"]["entries"]=[]
	check(not doc.apply(tampered)["ok"] and doc.data==proposed and doc.undo_history.size()==1,"Changed reviewed membership cannot be applied as the original proposal")
	var concurrent: Dictionary=proposed.duplicate(true);concurrent["collection"]["name"]="Concurrent palette change";check(doc.apply(doc.propose(concurrent))["ok"],"A separate current project metadata change can commit")
	check(not doc.apply(review)["ok"] and doc.data==concurrent and doc.undo_history.size()==2,"Stale project review preserves concurrent metadata and history")
	check(doc.apply(doc.propose(selected))["ok"] and doc.data["restricted"],"Restriction requires an explicit metadata change; it never follows personal filter selection")
	check(doc.history()["ok"] and doc.data==concurrent,"Undo reverses the exact explicit restriction/name change")
	check(doc.history(true)["ok"] and doc.data==selected,"Redo restores the exact reviewed restriction choice")
	var invalid: Dictionary=selected.duplicate(true);invalid["version"]=true;var count: int=doc.undo_history.size();check(not doc.restore(invalid)["ok"] and doc.data==selected and doc.undo_history.size()==count,"Malformed metadata restoration preserves the live project and its history")
	check(doc.restore(selected)["ok"] and doc.undo_history.is_empty() and doc.redo_history.is_empty(),"A reopened or accepted remote palette starts with no obsolete local branch")
	var reopened:=Project.new();check(reopened.restore(JSON.parse_string(JSON.stringify(doc.data)))["ok"] and reopened.data==doc.data,"Project metadata round-trip preserves unknown references without catalog requirements")
	check(not reopened.propose(JSON.parse_string(JSON.stringify(doc.data)))["changed"],"JSON number normalization cannot turn unchanged project metadata into a new edit")
	check(reopened.restore({})["ok"] and reopened.data.is_empty(),"Opening a project without recommendations does not leak the previous palette")
	for index in Project.HISTORY_LIMIT+5:
		var item: Dictionary=selected.duplicate(true);item["collection"]["name"]="Palette edit "+str(index);doc.apply(doc.propose(item))
	check(doc.undo_history.size()==Project.HISTORY_LIMIT,"Project metadata history has a bounded step count")
	var last: Dictionary=doc.data.duplicate(true)
	for index in Project.HISTORY_LIMIT:check(doc.history()["ok"],"Every retained project palette history step can be undone")
	check(not doc.history()["ok"],"Discarded old palette history is not invented as another undo")
	for index in Project.HISTORY_LIMIT:check(doc.history(true)["ok"],"Every retained palette history step can be redone")
	check(doc.data==last,"Complete retained history round trip restores exact project metadata")
	var new_change: Dictionary=last.duplicate(true);new_change["collection"]["name"]="Before external change";doc.apply(doc.propose(new_change));doc.data["collection"]["name"]="External metadata update";before=doc.data.duplicate(true)
	check(not doc.history()["ok"] and doc.data==before,"A conflicting external update cannot be overwritten by local palette Undo")
	var large: Dictionary=Plan.project_empty()
	for index in 4096:large["collection"]["entries"].append({"kind":"asset","id":"2d:Retained_reference_"+str(index),"name":"Reference "+str(index)+" "+"x".repeat(90)})
	var bounded:=Project.new();check(Plan.project_valid(large) and bounded.apply(bounded.propose(large))["ok"],"Large valid project recommendations remain supported")
	for index in 16:
		large["collection"]["entries"][-1]["name"]="Changed large snapshot "+str(index);check(bounded.apply(bounded.propose(large))["ok"],"Large reviewed reference changes can commit within their format bound")
	var bytes: int=0
	for entry in bounded.undo_history:bytes+=entry["bytes"]
	check(bytes<=Project.HISTORY_BYTES and bounded.undo_history.size()<17,"Large project palette history is bounded by retained delta bytes as well as count")
	print("PROJECT PALETTE DOCUMENT: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
