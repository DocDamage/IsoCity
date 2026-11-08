extends RefCounted
const Plan=preload("res://scripts/builder/companion_plan.gd")
const Economy=preload("res://scripts/builder/economy_plan.gd")
const Rotation=preload("res://scripts/builder/rotation.gd")
var studio: Control
var panel: PanelContainer
var title: Label
var note: Label
var together: Button
var dialog: ConfirmationDialog
var summary: Label
var message: Label
var container: SubViewportContainer
var through: CheckBox
var preview=preload("res://scripts/builder/companion_preview.gd").new()
var proposal: Dictionary={}
var review: Dictionary={}
var floating: Dictionary={}
var last_placed: Dictionary={}
var offered: Dictionary={}
var signature: String=""
var dismissed: String=""
var elapsed: float=0
var epoch: int=0
func _init(host: Control) -> void:
	studio=host
	panel=PanelContainer.new();panel.name="CompanionSuggestions";panel.mouse_filter=Control.MOUSE_FILTER_STOP;panel.hide();studio.canvas.add_child(panel)
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",6);panel.add_child(box)
	var header:=HBoxContainer.new();box.add_child(header);title=studio.label(header,"",13);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var dismiss:=Button.new();dismiss.text="×";dismiss.tooltip_text="Dismiss companion suggestions for this selection";dismiss.accessibility_name="Dismiss companion suggestions";header.add_child(dismiss);dismiss.pressed.connect(func():dismissed=context_key(offered);panel.hide())
	note=studio.label(box,"",12);note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;note.max_lines_visible=3;note.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	together=Button.new();together.text="Place together…";together.tooltip_text="Review the complete editable set and its price before applying it.";box.add_child(together);together.pressed.connect(start)
	dialog=ConfirmationDialog.new();dialog.title="Review companion set";dialog.min_size=Vector2i(560,420);dialog.dialog_hide_on_ok=false;dialog.get_ok_button().text="Apply reviewed set";studio.add_child(dialog);dialog.confirmed.connect(apply)
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size=Vector2(520,320);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.follow_focus=true;dialog.add_child(scroll)
	var column:=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.add_theme_constant_override("separation",10);scroll.add_child(column)
	summary=studio.label(column,"",13);summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	container=SubViewportContainer.new();container.custom_minimum_size=Vector2(480,240);container.stretch=true;column.add_child(container);container.resized.connect(preview.frame)
	through=CheckBox.new();through.text="See through canopy in this preview";column.add_child(through);through.toggled.connect(preview.see_through)
	message=studio.label(column,"",13);message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var refresh:=Button.new();refresh.text="Refresh exact review";column.add_child(refresh);refresh.pressed.connect(refresh_review)
	dialog.visibility_changed.connect(func():
		if not dialog.visible:epoch+=1;preview.clear();proposal={};review={})
	studio.tree_exiting.connect(func():epoch+=1;preview.clear())
func scope() -> Dictionary:return {"world":studio.mode,"owner":studio.interior_tools.uid if studio.interior_tools.editing() else "","floor":studio.current().floor_uid if studio.interior_tools.editing() else "ground"}
func root_document() -> RefCounted:return studio.interior_tools.root_document(studio.mode)
func gesture_active() -> bool:
	return studio.stroke or studio.road_drawing or studio.ground_brush.drawing or studio.transform_handles.dragging or studio.zone_tools.drawing or studio.cooperative_tools.drawing or studio.terrain_tools.drawing or studio.blueprint_tools.dragging or studio.control_settings.dragging
func shared_pending() -> bool:return studio.cooperative_tools.session.connected and (studio.cooperative_tools.dirty or not studio.cooperative_tools.session.pending.is_empty())
func ready_record() -> Dictionary:
	var result: Dictionary=studio.placement_record().duplicate(true);result["scale"]=studio.scale_input.value;result["position"]=[0,0,0];return result
func context() -> Dictionary:
	if studio.walking:return {}
	var selected: Array=studio.selection_items()
	if not selected.is_empty():return {"scope":scope(),"uid":selected[0]["uid"],"source":selected[0].duplicate(true)} if selected.size()==1 and not Plan.for_asset(selected[0]["asset"]).is_empty() else {}
	if last_placed.get("scope")==scope():
		var item: Dictionary=studio.current().object(last_placed.get("uid",""))
		if not item.is_empty() and not Plan.for_asset(item["asset"]).is_empty():return {"scope":scope(),"uid":item["uid"],"source":item.duplicate(true)}
	if not studio.asset_id.is_empty() and studio.tool=="place":return {"scope":scope(),"uid":"","source":ready_record()} if not Plan.for_asset(studio.asset_id).is_empty() else {}
	return {}
func context_key(value: Dictionary) -> String:return JSON.stringify([value.get("scope",{}),value.get("uid",""),value.get("source",{}).get("asset","")]) if not value.is_empty() else ""
func chosen() -> void:last_placed={};dismissed="";signature=""
func placed(uid: String) -> void:last_placed={"scope":scope(),"uid":uid};dismissed="";signature=""
func cancel_floating() -> void:
	floating={}
	if dialog.visible:dialog.hide()
func over_ui(point: Vector2) -> bool:return panel.is_visible_in_tree() and panel.get_global_rect().has_point(point)
func tick(delta: float) -> void:
	elapsed+=delta
	if elapsed<.15:return
	elapsed=0
	if not floating.is_empty() and floating["scope"]!=scope():studio.clear_assembly()
	var value: Dictionary=context();var ui: RefCounted=studio.consumer_shell
	var visible: bool=not value.is_empty() and floating.is_empty() and not studio.modal_visible() and (not ui or not ui.active or (ui.drawer_kind.is_empty() and ui.sheet_kind.is_empty() and not ui.details_open))
	panel.visible=visible and context_key(value)!=dismissed
	if not panel.visible:return
	var next: String=JSON.stringify([value,FileAccess.get_sha256(Plan.PATH),studio.library.assets.size()])
	if next!=signature:
		signature=next;offered=value;var key: String=Plan.for_asset(value["source"]["asset"]);var recipe: Dictionary=Plan.definitions()["relationships"].get(key,{})
		if recipe.is_empty():panel.hide();return
		title.text=recipe["label"];note.text=("Add to the placed source. " if not value["uid"].is_empty() else "Preview a new set. ")+recipe["source_set"]+" · "+recipe["note"];note.tooltip_text=note.text
		for spec in recipe["companions"]:
			if not studio.library.assets.has(spec["asset"]) or not FileAccess.file_exists(studio.library.assets[spec["asset"]]["path"]):note.text="A companion source is unavailable. Restore its pack before applying this set."
	together.disabled=gesture_active() or shared_pending();layout()
func layout() -> void:
	# A narrow precision canvas can be shorter than the full explanatory tray.
	# Keep the actions visible and expose the same explanation on focus/hover.
	note.visible=studio.canvas.size.y>=250
	together.tooltip_text=note.tooltip_text+"\nReview the complete editable set and its price before applying it."
	var width: float=minf(340,maxf(180,studio.canvas.size.x-24));panel.custom_minimum_size.x=width;panel.size=Vector2(width,0)
	var y: float=10;var x: float=maxf(8,studio.canvas.size.x-width-12);var ui: RefCounted=studio.consumer_shell
	if ui and ui.active:
		y=112
		if ui.context.visible:y=maxf(y,ui.context.position.y+ui.context.size.y+10)
		var limit: float=ui.dock.position.y-panel.size.y-14
		if y>limit and ui.context.visible and ui.context.position.x>=width+24:
			x=12;y=112
		else:y=minf(y,maxf(112,limit))
	else:y=minf(y,maxf(0,studio.canvas.size.y-panel.size.y-4))
	panel.position=Vector2(x,y)
func stage(draft: Dictionary,key: String) -> bool:
	var virtual: Dictionary=preload("res://scripts/builder/templates.gd").make(studio.mode,"blank");var checked: Dictionary=Plan.propose(virtual,{},key,"",draft,studio.library)
	if not checked["ok"]:studio.status.text=checked["reason"];note.text=checked["reason"];return false
	var saved: Dictionary={"scope":scope(),"recipe":key,"draft":draft.duplicate(true)}
	studio.begin_assembly({"name":Plan.definitions()["relationships"][key]["label"],"mode":studio.mode,"objects":checked["room"]["objects"].duplicate(true),"companion":true})
	if studio.assembly_active.is_empty():return false
	floating=saved;panel.hide();studio.status.text="Move the set, then click to review its clearance and price. R rotates; Escape cancels.";return true
func start() -> void:
	if gesture_active() or shared_pending():studio.status.text="Finish the current edit before reviewing companions.";return
	var value: Dictionary=context()
	if value.is_empty():return
	var key: String=Plan.for_asset(value["source"]["asset"])
	if value["uid"].is_empty():stage(value["source"],key)
	else:review=value.duplicate(true);review["recipe"]=key;open_review()
func anchor_at(at: Vector2) -> Array:
	var values: Array=studio.worlds[studio.mode].point(at,studio.snap_input.button_pressed,studio.height_input.value)
	if studio.mode=="3d" and studio.surface_input.button_pressed:values=studio.worlds[studio.mode].surface_point(at,studio.snap_input.button_pressed,studio.height_input.value)
	return preload("res://scripts/builder/grid_fit.gd").place(values,floating["draft"],studio.mode,studio.library,studio.arrange_tools.target()) if studio.snap_input.button_pressed or studio.arrange_tools.target()!="base" else values
func canvas_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed and studio.tool=="select":last_placed={};dismissed="";signature=""
	if floating.is_empty() or studio.walking:return false
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed and not dialog.visible:
			review_at(event.position)
		return true
	return false
func review_at(at: Vector2) -> void:
	if floating.is_empty() or dialog.visible:return
	var source: Dictionary=floating["draft"].duplicate(true);source["position"]=anchor_at(at);review={"scope":floating["scope"].duplicate(true),"uid":"","source":source,"recipe":floating["recipe"]};studio.stroke=false;open_review()
func rotate(step: int,reset: bool=false) -> bool:
	if floating.is_empty():return false
	var draft: Dictionary=floating["draft"].duplicate(true);var key: String=floating["recipe"];Rotation.set_heading(draft,0 if reset else Rotation.heading(draft,studio.library)+90*step,studio.library);stage(draft,key);return true
func open_review() -> void:
	if review.get("scope")!=scope():studio.status.text="The selected world or floor changed. Choose the set again.";return
	dialog.popup_centered_clamped(Vector2i(880,680),.9);refresh_review()
func permission(data: Dictionary) -> String:
	var coop: RefCounted=studio.cooperative_tools
	if not coop.session.connected:return ""
	var before: Dictionary=coop.snapshot();var after: Dictionary=before.duplicate(true);after[studio.mode]=data
	return preload("res://scripts/builder/cooperative_plan.gd").allowed(before,after,coop.session.local_id,studio.library)
func refresh_review() -> void:
	if not dialog.visible or review.is_empty():return
	epoch+=1;var request: int=epoch;preview.clear();proposal={};dialog.get_ok_button().disabled=true
	if review["scope"]!=scope():message.text="The world or floor changed. Close this review and choose the source again.";return
	proposal=Plan.propose(root_document().data,review["scope"],review["recipe"],review["uid"],review["source"],studio.library)
	var recipe: Dictionary=Plan.definitions()["relationships"].get(review["recipe"],{})
	summary.text=recipe.get("label","Companion set")+" · "+recipe.get("source_set","")+"\n"+recipe.get("note","")
	through.visible=recipe.get("related_overlap",false);through.set_pressed_no_signal(false);preview.cutaway=false
	if not proposal["ok"]:
		message.text=proposal["reason"]
		for missing in proposal.get("missing",[]):message.text+="\n"+missing["name"]+": "+missing["reason"]
		return
	summary.text+="\nAdds %d editable objects%s."%[proposal["created"].size()," to the existing source" if not review["uid"].is_empty() else ""]
	if not proposal["duplicates"].is_empty():summary.text+=" %d matching pieces already nearby; their saved settings are kept."%proposal["duplicates"].size()
	var quote: Dictionary=proposal["quote"]
	if quote.get("enabled",false):summary.text+="\nConstruction %d · refunds %d · net cost %d credits."%[quote.get("construction",0),quote.get("refund",0),quote.get("net",0)]
	else:summary.text+="\nCreative mode · unlimited construction."
	message.text="Reviewing the actual set, standing points and supporting surfaces…";var planned: Dictionary=proposal
	var finished: bool=await preview.build(planned,studio.library,container,DisplayServer.get_name()!="headless")
	if request!=epoch or not dialog.visible:return
	if not finished:message.text="The preview was interrupted. Refresh before applying.";return
	var messages: Array=[]
	for issue in proposal["issues"]:messages.append(issue["message"])
	var denied: String=permission(proposal["data"])
	if not denied.is_empty():messages.append(denied)
	if not quote["ok"]:messages.append(quote["reason"])
	if not proposal["changed"]:messages.append("Matching companions are already present. No construction is needed.")
	if gesture_active() or shared_pending():messages.append("Finish the current edit or wait for shared acceptance before applying.")
	message.text="\n".join(messages) if not messages.is_empty() else "Preview ready. Apply creates this reviewed set in one undoable step."
	dialog.get_ok_button().disabled=not messages.is_empty() or not Plan.current(proposal,root_document().data,studio.library)
func apply() -> void:
	if not proposal.get("ok",false) or not proposal.get("changed",false) or not proposal.get("geometry_checked",false) or not proposal.get("issues",[{}]).is_empty() or not proposal.get("quote",{}).get("ok",false):message.text="Review an available, clear and affordable set before applying.";return
	if review.get("scope")!=scope() or gesture_active() or shared_pending():message.text="Finish the current edit and review this exact world/floor before applying.";return
	if not Plan.current(proposal,root_document().data,studio.library):message.text="The document or a source dependency changed. Refresh the exact review before applying.";dialog.get_ok_button().disabled=true;return
	var prepared: Dictionary=Plan.materialize(proposal);var denied: String=permission(prepared["data"])
	if not denied.is_empty():message.text=denied;dialog.get_ok_button().disabled=true;return
	var quote: Dictionary=Economy.quote(root_document().data,prepared["data"],studio.library)
	if not quote["ok"] or [quote.get("construction"),quote.get("refund"),quote.get("net") ]!=[proposal["quote"].get("construction"),proposal["quote"].get("refund"),proposal["quote"].get("net")]:message.text=quote.get("reason","The price changed. Refresh this review.");return
	var ids: Array=prepared["ids"].values();var target: Dictionary=prepared["room"];var label: String=Plan.definitions()["relationships"][review["recipe"]]["label"]
	if studio.interior_tools.editing():
		var floors: RefCounted=studio.interior_tools.floor_tools
		if not floors.prepare():message.text="The room is no longer available.";return
		floors.commit({"ok":true,"changed":true,"data":Plan.object(prepared["data"],review["scope"]["owner"])["interior"]},review["scope"]["floor"])
	else:
		var doc: RefCounted=studio.current();doc.checkpoint();doc.data=prepared["data"];studio.changed();doc.finish_checkpoint()
	if studio.current().data["objects"]!=target["objects"]:message.text="The set was not accepted. Review the current document and budget again.";return
	for uid in ids:
		var item: Dictionary=studio.current().object(uid);studio.asset_browser.recents.placed(item["asset"],uid)
	studio.clear_assembly();studio.selected_uids.assign(ids);studio.selected_uid=ids[0] if not ids.is_empty() else "";studio.set_tool("select");studio.refresh_controls();dialog.hide();panel.hide()
	studio.status.text="Submitted "+label+" for shared acceptance." if studio.cooperative_tools.session.connected else "Applied "+label+". Undo restores the previous layout and budget."
