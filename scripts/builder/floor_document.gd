extends "res://scripts/builder/document.gd"

# The editor presents one room, while one canonical document owns all floors
# and their chronological delta history. No per-floor redo branches can diverge.
const Floors=preload("res://scripts/builder/floor_plan.gd")
var canonical: RefCounted
var floor_uid: String="ground"
var pending_floor: String="ground"

func configure(root: Dictionary) -> void:
	canonical=preload("res://scripts/builder/document.gd").new()
	canonical.data=root
	undo_history=canonical.undo_history
	redo_history=canonical.redo_history
	bind("ground")

func bind(uid: String) -> void:
	floor_uid=uid if not Floors.room(canonical.data,uid).is_empty() else "ground"
	data=Floors.room(canonical.data,floor_uid)

func flush_room() -> void:
	if floor_uid=="ground":
		# Replacing the ground room template keeps the other owned floors.
		if not is_same(data,canonical.data):
			for field in Floors.FIELDS:
				if canonical.data.has(field) and not data.has(field): data[field]=canonical.data[field]
		canonical.data=data
	else:
		for floor in canonical.data.get("floors",[]):
			if floor["uid"]==floor_uid: floor["room"]=data; return
		bind("ground")

func switch_floor(uid: String) -> bool:
	if Floors.room(canonical.data,uid).is_empty(): return false
	finish_checkpoint()
	bind(uid)
	return true

func checkpoint() -> void:
	finish_checkpoint()
	pending_floor=floor_uid
	canonical.checkpoint()

func finish_checkpoint(discard_empty: bool=false) -> void:
	if not canonical: return
	flush_room()
	var pending: bool=not canonical.undo_history.is_empty() and canonical.undo_history.back().has("pending")
	var old_redo: Array=canonical.pending_redo.duplicate(true) if pending else []
	var pending_count: int=canonical.undo_history.size()
	canonical.finish_checkpoint(discard_empty)
	bind(floor_uid)
	if pending and canonical.undo_history.size()==pending_count:
		var change: Dictionary=canonical.undo_history.back()
		if change["fields"].is_empty() and change["collections"].is_empty():
			canonical.undo_history.pop_back(); canonical.redo_history.assign(old_redo)
		else: change["floor_uid"]=pending_floor

func undo() -> bool:
	finish_checkpoint()
	var selected: String=canonical.undo_history.back().get("floor_uid",floor_uid) if not canonical.undo_history.is_empty() else floor_uid
	var changed: bool=canonical.undo()
	bind(selected)
	return changed

func redo() -> bool:
	finish_checkpoint()
	var selected: String=canonical.redo_history.back().get("floor_uid",floor_uid) if not canonical.redo_history.is_empty() else floor_uid
	var changed: bool=canonical.redo()
	bind(selected)
	return changed

func record_completed_change(before: Dictionary,financial_transaction: bool=false) -> bool:
	flush_room()
	var root_before: Dictionary=before
	if floor_uid!="ground":
		root_before=canonical.data.duplicate(true)
		for floor in root_before.get("floors",[]):
			if floor["uid"]==floor_uid: floor["room"]=before.duplicate(true)
	var changed: bool=canonical.record_completed_change(root_before,financial_transaction)
	if changed: canonical.undo_history.back()["floor_uid"]=floor_uid
	bind(floor_uid)
	return changed

func reconcile_economy(library: RefCounted) -> bool:
	flush_room()
	var accepted: bool=canonical.reconcile_economy(library)
	economy_error=canonical.economy_error
	bind(floor_uid)
	return accepted

func replace_plan(root: Dictionary, selected: String) -> void:
	finish_checkpoint()
	canonical.checkpoint()
	canonical.data=root
	bind(selected)
	canonical.finish_checkpoint()
	if not canonical.undo_history.is_empty(): canonical.undo_history.back()["floor_uid"]=selected

func restore_owned(root: Dictionary) -> void:
	# An exterior budget rejection may replace the entire owned root dictionary.
	canonical.data=root
	bind(floor_uid)
