extends RefCounted
const Plan=preload("res://scripts/builder/asset_recents.gd")
const Floors=preload("res://scripts/builder/floor_plan.gd")
var studio: Control
var history=Plan.new()
var only: bool=false
var settings_path: String="user://studio_recent_assets.json"
var controls: Array[Button]=[]
var pending: Array[Dictionary]=[]
var drawer_state: Dictionary={}
var restore_epoch: int=0
func _init(host: Control,parent: Node) -> void:
	studio=host
	if studio.storage_enabled:restore()
	add_control(parent)
func restore() -> void:
	history.restore({},studio.library.tasks.tasks)
	if FileAccess.file_exists(settings_path):
		var file:=FileAccess.open(settings_path,FileAccess.READ)
		if file and file.get_length()<=262144:history.restore(studio.Store.read_json(settings_path,{}),studio.library.tasks.tasks)
func task() -> String:return studio.asset_browser.task_collections.task if studio.asset_browser and studio.asset_browser.task_collections else ""
func add_control(parent: Node) -> void:
	var button:=Button.new();button.text="Recent";button.toggle_mode=true;button.custom_minimum_size=Vector2(90,40);button.accessibility_name="Recently placed assets for this task";parent.add_child(button);controls.append(button);button.toggled.connect(set_only);refresh()
func set_only(value: bool) -> void:
	only=value;studio.page=0;studio.refresh_library()
func active() -> bool:return only and not history.available(task(),studio.library).is_empty()
func filter(found: Array[Dictionary]) -> Array[Dictionary]:
	if not active():return found
	var result: Array[Dictionary]=[];var lookup: Dictionary={}
	for asset in found:lookup[asset["id"]]=asset
	for id in history.available(task(),studio.library):
		if lookup.has(id):result.append(lookup[id])
	return result
func note() -> String:
	if not only:return ""
	var available: Array=history.available(task(),studio.library);var missing: int=history.ids(task()).size()-available.size()
	if available.is_empty():return "No available recents for this task; showing the matching library."
	return "Recent placements · exact variations"+(" · %d unavailable"%missing if missing else "")
func refresh() -> void:
	var label: String=studio.library.tasks.tasks[task()]["name"] if studio.library.tasks.tasks.has(task()) else "all activities"
	for button in controls:
		button.set_pressed_no_signal(only);button.tooltip_text="Recently placed for "+label+". Shows exact placed variations, newest first. Other filters still apply. "+note()
func persist() -> void:
	if studio.storage_enabled and not studio.Store.write_json(settings_path,history.state()):studio.status.text="Recent placements are available in this session; preferences could not be saved."
func document_for(receipt: Dictionary,data: Dictionary) -> Dictionary:
	var source: Dictionary=data.get(receipt["mode"],{})
	if not receipt["owner"].is_empty():
		var owned: Dictionary={}
		for item in source.get("objects",[]):
			if item["uid"]==receipt["owner"]:owned=item.get("interior",{});break
		source=Floors.room(owned,receipt["floor"])
	return source
func contains(receipt: Dictionary,data: Dictionary) -> bool:
	var source: Dictionary=document_for(receipt,data)
	if receipt.has("cell"):
		return source.get("tiles",[]).any(func(tile: Dictionary):return tile["cell"]==receipt["cell"] and tile["asset"]==receipt["asset"])
	return source.get("objects",[]).any(func(item: Dictionary):return item["uid"]==receipt["uid"] and item["asset"]==receipt["asset"])
func placed(id: String,uid: String="",cell: Variant=null) -> void:
	if not studio.library.assets.has(id):return
	var inside: bool=studio.interior_tools.editing()
	var receipt: Dictionary={"mode":studio.mode,"owner":studio.interior_tools.uid if inside else "","floor":studio.current().floor_uid if inside else "ground","task":task(),"asset":id,"uid":uid}
	if cell!=null:receipt["cell"]=cell.duplicate()
	var current: Dictionary={studio.mode:studio.interior_tools.root_document(studio.mode).data}
	if not contains(receipt,current):return
	var session: Node=studio.cooperative_tools.session
	if session.connected:
		pending.append(receipt)
		while pending.size()>128:pending.pop_front()
	else:commit([receipt])
func commit(receipts: Array) -> void:
	var changed: bool=false
	for receipt in receipts:changed=history.remember(receipt["asset"],receipt["task"],studio.library.tasks.tasks) or changed
	if changed:persist();refresh()
func tick() -> void:
	if pending.is_empty():return
	var coop: RefCounted=studio.cooperative_tools
	if not coop.session.connected:pending.clear();return
	if coop.dirty or not coop.session.pending.is_empty():return
	var accepted: Array=pending.filter(func(receipt: Dictionary):return contains(receipt,coop.session.data));pending.clear();commit(accepted)
func drawer_signature() -> String:
	var state: Dictionary=studio.asset_browser.semantic_search.snapshot();state.erase("page")
	state["recent"]=only;state["project"]=studio.project_id
	state["collection"]=studio.asset_browser.collections.selection() if studio.asset_browser.collections else ""
	state["scope"]=[studio.interior_tools.uid,studio.current().floor_uid] if studio.interior_tools.editing() else [studio.current().data.get("template","city")]
	return JSON.stringify(state)
func capture_drawer() -> void:
	var ui: RefCounted=studio.consumer_shell
	if not ui or ui.drawer_kind!="build":return
	restore_epoch+=1;drawer_state={"signature":drawer_signature(),"page":studio.page,"scroll":ui.card_scroll.scroll_vertical}
func restore_drawer() -> void:
	if drawer_state.is_empty() or drawer_state["signature"]!=drawer_signature():return
	restore_epoch+=1;var request: int=restore_epoch;var signature: String=drawer_state["signature"];var scroll: int=drawer_state["scroll"]
	# Container ranges settle after cards are rebuilt. Cancel stale restoration
	# when another query, task, page or scope is selected in the meantime.
	for frame in 3:await studio.get_tree().process_frame
	var ui: RefCounted=studio.consumer_shell
	if request==restore_epoch and ui and ui.drawer_kind=="build" and signature==drawer_signature() and studio.page==drawer_state["page"]:ui.card_scroll.scroll_vertical=scroll
