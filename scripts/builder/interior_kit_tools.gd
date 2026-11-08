extends RefCounted
const Plan=preload("res://scripts/builder/interior_kit_plan.gd")
const Kits=preload("res://scripts/builder/interior_kits.gd")
const Floors=preload("res://scripts/builder/floor_plan.gd")
const Economy=preload("res://scripts/builder/economy_plan.gd")
var studio: Control
var dialog: ConfirmationDialog
var kit: OptionButton
var action: OptionButton
var offset_x: SpinBox
var offset_z: SpinBox
var floor_name: LineEdit
var floor_height: SpinBox
var floor_fields: HFlowContainer
var summary: Label
var contents: Label
var message: Label
var container: SubViewportContainer
var preview=preload("res://scripts/builder/interior_kit_preview.gd").new()
var proposal: Dictionary={}
var owner_uid: String=""
var floor_uid: String="ground"
var dimension: String=""
var opened_inside: bool=false
var standalone: bool=false
var epoch: int=0
var refreshing: bool=false

func _init(host: Control) -> void:
	studio=host
	dialog=ConfirmationDialog.new();dialog.title="Choose an interior layout";dialog.min_size=Vector2i(560,420);dialog.dialog_hide_on_ok=false;dialog.get_ok_button().text="Apply reviewed layout";studio.add_child(dialog)
	dialog.confirmed.connect(apply);dialog.visibility_changed.connect(func():
		if not dialog.visible:epoch+=1;preview.clear();proposal={})
	studio.tree_exiting.connect(shutdown)
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size=Vector2(520,320);scroll.follow_focus=true;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;dialog.add_child(scroll)
	var column:=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.add_theme_constant_override("separation",10);scroll.add_child(column)
	var choices:=HFlowContainer.new();column.add_child(choices)
	kit=OptionButton.new();kit.custom_minimum_size.x=190;kit.fit_to_longest_item=false;kit.clip_text=true;kit.accessibility_name="Interior kit";choices.add_child(kit)
	for key in ["classroom","shop","cafe","apartment","garage","station","empty"]:
		if not Kits.definitions()["kits"].has(key):continue
		var record: Variant=Kits.definitions()["kits"][key];var name: Variant=record.get("name") if record is Dictionary else null
		kit.add_item(name if name is String and not name.is_empty() and name.length()<=160 else "Unavailable "+key);kit.set_item_metadata(kit.item_count-1,key)
	action=OptionButton.new();action.custom_minimum_size.x=240;action.fit_to_longest_item=false;action.clip_text=true;action.accessibility_name="Apply layout action";choices.add_child(action)
	kit.item_selected.connect(func(_index: int):refresh());action.item_selected.connect(func(_index: int):refresh())
	var offsets:=HFlowContainer.new();column.add_child(offsets)
	offset_x=number(offsets,"Layout X",-64,64,.25);offset_z=number(offsets,"Layout Z",-64,64,.25)
	floor_fields=HFlowContainer.new();column.add_child(floor_fields)
	floor_name=LineEdit.new();floor_name.placeholder_text="New floor name";floor_name.max_length=80;floor_name.accessibility_name="New kit floor name";floor_name.custom_minimum_size.x=180;floor_fields.add_child(floor_name)
	floor_height=number(floor_fields,"Height (m)",-24,32,.1);floor_name.text_changed.connect(func(_text: String):refresh())
	summary=studio.label(column,"",13);summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	container=SubViewportContainer.new();container.custom_minimum_size=Vector2(480,240);container.stretch=true;column.add_child(container);container.resized.connect(preview.frame)
	contents=studio.label(column,"",13);contents.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	message=studio.label(column,"",13);message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var update:=Button.new();update.text="Refresh preview";column.add_child(update);update.pressed.connect(refresh)

func shutdown() -> void:epoch+=1;preview.clear()
func number(parent: Node,title: String,low: float,high: float,step: float) -> SpinBox:
	var row:=HBoxContainer.new();parent.add_child(row);studio.label(row,title,13)
	var field:=SpinBox.new();field.min_value=low;field.max_value=high;field.step=step;field.custom_minimum_size.x=110;field.accessibility_name=title;row.add_child(field);field.value_changed.connect(func(_value: float):refresh());return field
func selected(control: OptionButton) -> String:return str(control.get_item_metadata(control.selected)) if control.selected>=0 else ""
func gesture_active() -> bool:return studio.stroke or studio.road_drawing or studio.ground_brush.drawing
func select(control: OptionButton,key: String) -> void:
	for index in control.item_count:
		if control.get_item_metadata(index)==key:control.select(index);return

func source_document() -> RefCounted:
	if studio.mode!=dimension or studio.interior_tools.editing()!=opened_inside:return null
	if opened_inside:
		if studio.interior_tools.uid!=owner_uid or studio.current().floor_uid!=floor_uid:return null
		return studio.interior_tools.outer
	if standalone:
		return studio.current() if studio.current().data.get("template")=="room" or studio.current().data.get("interior_room",false) else null
	if studio.entrance_tools.active().get("uid","")!=owner_uid:return null
	return studio.current()

func show() -> void:
	if studio.walking:studio.status.text="Return to editing before choosing an interior layout.";return
	opened_inside=studio.interior_tools.editing();dimension=studio.mode
	standalone=not opened_inside and (studio.current().data.get("template")=="room" or studio.current().data.get("interior_room",false))
	owner_uid=studio.interior_tools.uid if opened_inside else studio.entrance_tools.active().get("uid","");floor_uid=studio.current().floor_uid if opened_inside else "ground"
	if owner_uid.is_empty() and not standalone:studio.status.text="Select a building, or edit its interior, before choosing a layout.";return
	refreshing=true
	var doc: RefCounted=source_document();var host: Dictionary=Plan.owner(doc.data,owner_uid) if doc else {}
	if host.is_empty() and not standalone:refreshing=false;return
	action.clear()
	if host.has("interior") or standalone:
		for spec in [["Add furnishings to this floor","add"],["Replace this floor's entire layout","replace"],["Create a new furnished floor","floor"]]:action.add_item(spec[0]);action.set_item_metadata(action.item_count-1,spec[1])
		if standalone:action.set_item_disabled(2,true);action.get_popup().set_item_tooltip(2,"Additional connected floors belong to owned building interiors.")
	else:action.add_item("Create the first interior");action.set_item_metadata(0,"create")
	var default: String="apartment" if standalone else Kits.default_for(host["asset"]);select(kit,default if not default.is_empty() else "apartment")
	offset_x.set_value_no_signal(0);offset_z.set_value_no_signal(0);floor_name.text="Floor "+str(host.get("interior",{}).get("floors",[]).size()+2)
	var highest: float=0
	for floor in host.get("interior",{}).get("floors",[]):highest=maxf(highest,float(floor["height"]))
	floor_height.set_value_no_signal(minf(32,highest+3));refreshing=false
	dialog.popup_centered_clamped(Vector2i(880,680),.9);refresh()

func refresh() -> void:
	if refreshing or not dialog.visible:return
	epoch+=1;var request: int=epoch;proposal={};preview.clear();dialog.get_ok_button().disabled=true
	floor_fields.visible=selected(action)=="floor"
	var doc: RefCounted=source_document()
	if not doc:message.text="The selected building, floor or world changed. Close and reopen the chooser.";return
	var key: String=selected(kit);var operation: String=selected(action);var source: Dictionary=doc.data
	proposal=Plan.propose_room(source,key,operation,[offset_x.value,offset_z.value],studio.library) if standalone else Plan.propose(source,owner_uid,floor_uid,key,operation,[offset_x.value,offset_z.value],studio.library,floor_name.text,floor_height.value)
	var raw_definition: Variant=Kits.definitions()["kits"].get(key,{});var definition: Dictionary=raw_definition if raw_definition is Dictionary else {}
	var names: Dictionary={}
	var records: Variant=definition.get("objects",[])
	for record in (records.slice(0,256) if records is Array else []):
		if not record is Dictionary or not record.get("asset") is String:continue
		var name: String=studio.library.assets.get(record["asset"],{}).get("name",record["asset"]);names[name]=int(names.get(name,0))+1
	var lines: Array=[]
	for name in names:lines.append("%d × %s"%[names[name],name])
	contents.text="Contents · "+("Empty shell" if lines.is_empty() else "; ".join(lines))
	var raw_dimensions: Variant=definition.get("dimensions",{});var values: Variant=raw_dimensions.get(dimension) if raw_dimensions is Dictionary else null
	var dimensions: Array=values if values is Array and values.size()==2 else ["?","?"];var host: Dictionary=Plan.owner(source,owner_uid)
	summary.text=(source["title"] if standalone else host.get("name",studio.library.assets[host["asset"]]["name"])+" · "+(floor_name.text if operation=="floor" else preload("res://scripts/builder/floor_entrances.gd").name_for(host.get("interior",{}),floor_uid)))+"\nKit footprint: %s × %s %s. "%[dimensions[0],dimensions[1],"cells" if dimension=="2d" else "m"]
	if key=="apartment" and dimension=="3d":summary.text+="Pixel City sprites appear as flat artwork in this world. "
	if operation=="replace":summary.text+="Replaces all objects and floor tiles on this floor; its exit, settings and other floors remain. "
	elif operation=="floor":summary.text+="The new floor needs stairs, an elevator or an entrance before it can be visited from outside. "
	else:summary.text+="Choose an offset to keep existing furniture and approaches clear. "
	if not proposal["ok"]:
		message.text=proposal["reason"]
		for missing in proposal.get("missing",[]):message.text+="\n"+missing.get("name","")+": "+missing.get("reason","")
		return
	if operation=="replace":
		var previous: Dictionary=source if standalone else Floors.room(host["interior"],floor_uid)
		summary.text+="\nAffected: %d objects and %d floor tiles; %d other floors retained."%[proposal["removed"].size(),previous["tiles"].size(),proposal["root"].get("floors",[]).size()]
	if operation!="add":contents.text+=". Shell: %d structural pieces and %d floor tiles."%[proposal["created"].size()-proposal["contents"].size(),proposal["room"]["tiles"].size()]
	var quote: Dictionary=proposal["quote"]
	if quote.get("enabled",false):summary.text+="\nConstruction %d · refunds %d · net cost %d credits."%[quote.get("construction",0),quote.get("refund",0),quote.get("net",0)]
	elif quote["ok"]:summary.text+="\nCreative mode · unlimited construction."
	else:summary.text+="\n"+quote["reason"]
	summary.text+="\nReviewed building starters are free on first creation. Other layout changes use normal construction prices."
	message.text="Checking the proposed floor, exit, stations and walking approaches…"
	var planned: Dictionary=proposal
	var finished: bool=await preview.build(planned,studio.library,container,DisplayServer.get_name()!="headless")
	if request!=epoch or not dialog.visible:return
	if not finished:message.text="Preview was interrupted. Refresh before applying.";return
	var messages: Array=[]
	for entry in proposal["issues"]:messages.append(entry["message"])
	if not quote["ok"]:messages.append(quote["reason"])
	message.text="\n".join(messages) if not messages.is_empty() else "Preview ready. Apply changes only this reviewed floor layout; Undo restores the previous state."
	dialog.get_ok_button().disabled=not proposal["issues"].is_empty() or not quote["ok"] or not Plan.current(proposal,doc.data) or gesture_active()

func apply() -> void:
	var doc: RefCounted=source_document()
	if not doc or not proposal.get("ok",false) or not proposal.get("geometry_checked",false) or not proposal.get("issues",[{}]).is_empty() or not proposal.get("quote",{}).get("ok",false):message.text="Review an available, clear and affordable layout before applying.";return
	if gesture_active():message.text="Finish the current edit before applying a layout.";return
	if not Plan.current(proposal,doc.data):message.text="The document or a dependency changed. Refresh the exact preview before applying.";dialog.get_ok_button().disabled=true;return
	var prepared: Dictionary=Plan.materialize(proposal);var allowances: Dictionary={} if standalone else preload("res://scripts/builder/cooperative_plan.gd").complimentary_rooms(doc.data,prepared["data"],studio.library);var quote: Dictionary=Economy.quote(doc.data,prepared["data"],studio.library,allowances)
	if not quote["ok"] or [quote.get("construction"),quote.get("refund"),quote.get("net") ]!=[proposal["quote"].get("construction"),proposal["quote"].get("refund"),proposal["quote"].get("net")]:message.text=quote.get("reason","The price changed. Refresh before applying.");dialog.get_ok_button().disabled=true;return
	if opened_inside:
		var floors: RefCounted=studio.interior_tools.floor_tools
		if not floors.prepare():message.text="The room is no longer available.";return
		floors.commit({"ok":true,"changed":true,"data":prepared["root"]},prepared["floor_uid"])
		if not is_same(studio.current().canonical.data,prepared["root"]):message.text=floors.message.text;return
	else:
		doc.checkpoint();doc.data=prepared["data"];doc.economy_complimentary=allowances;studio.changed();doc.finish_checkpoint()
		if (doc.data if standalone else Plan.owner(doc.data,owner_uid).get("interior",{}))!=prepared["root"]:message.text=doc.economy_error;return
	studio.status.text="Applied the reviewed interior layout. Undo restores the previous state.";dialog.hide()
