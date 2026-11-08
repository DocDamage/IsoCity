extends RefCounted
const Plan=preload("res://scripts/builder/asset_collections.gd")
const PAGE=80
var studio: Control
var local=preload("res://scripts/builder/asset_collection_store.gd").new()
var index=preload("res://scripts/builder/asset_collection_index.gd").new()
var controls: Array[OptionButton]=[]
var override_filter: Variant=null
var sync_key: String=""
var dialog: AcceptDialog
var scope_choice: OptionButton
var collection_choice: OptionButton
var restriction: CheckBox
var clear_project_button: Button
var name_input: LineEdit
var explanation: Label
var members: Tree
var member_page: int=0
var member_note: Label
var query: LineEdit
var results: Tree
var result_note: Label
var message: Label
var save_button: Button
var use_button: Button
var delete_button: Button
var to_project: Button
var to_personal: Button
var undo_button: Button
var redo_button: Button
var edit_buttons: Array[Button]=[]
var file_dialog: FileDialog
var file_action: String=""
var review_dialog: ConfirmationDialog
var review_text: Label
var review_kind: String=""
var review_plan: Dictionary={}
var draft: Dictionary={}
var draft_source_hash: String=""
var loading: bool=false
func _init(host: Control,parent: Node) -> void:
	studio=host;local.storage_enabled=studio.storage_enabled
	if studio.storage_enabled:local.restore(studio.favorites,studio.library)
	add_controls(parent);make_dialog()
func selection() -> String:return str(override_filter) if override_filter!=null else local.state["selected"]
func valid_selection(uid: String) -> bool:return uid in ["","project"] or not Plan.collection(local.state,uid).is_empty()
func selected_collection() -> Dictionary:
	var uid: String=selection()
	if uid=="project":return studio.project_palette_document.data.get("collection",{})
	return Plan.collection(local.state,uid)
func sync() -> void:
	var key: String=str([selection(),local.revision,studio.project_palette_document.revision,studio.library.get_instance_id()])
	if key!=sync_key:
		sync_key=key;var value: Dictionary=selected_collection()
		if value.is_empty():index.clear()
		else:index.choose(value,studio.library)
	index.refresh(studio.library)
func active() -> bool:sync();return index.active()
func filter(found: Array[Dictionary]) -> Array[Dictionary]:sync();return index.filter(found,studio.library)
func note() -> String:
	sync()
	if selection().is_empty():return ""
	if not index.active():return "This project has no recommendation yet. Showing the matching library."
	var missing: int=index.resolved["missing"].size()
	return ("Project recommendation" if selection()=="project" else "Personal · "+index.source["name"])+" · %d saved references%s. Other filters still apply."%[index.resolved["ids"].size()," · %d unavailable"%missing if missing else ""]
func select_filter(uid: String,refresh_library: bool=true) -> void:
	if not valid_selection(uid):uid=""
	local.storage_enabled=studio.storage_enabled;var saved: Dictionary=local.select(uid);override_filter=null;sync_key="";refresh()
	if not saved.get("persisted",true):studio.status.text=saved["reason"]
	if refresh_library:studio.page=0;studio.refresh_library()
func temporary_filter(uid: String) -> void:override_filter=uid if valid_selection(uid) else "";sync_key="";refresh()
func add_controls(parent: Node) -> void:
	var row:=HFlowContainer.new();row.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(row)
	var choice:=OptionButton.new();choice.fit_to_longest_item=false;choice.clip_text=true;choice.custom_minimum_size=Vector2(190,40);choice.accessibility_name="Named collection or project recommendation filter";row.add_child(choice);controls.append(choice)
	choice.item_selected.connect(func(at: int):select_filter(str(choice.get_item_metadata(at))))
	var manage:=Button.new();manage.text="Manage collections…";manage.tooltip_text="Create personal reference lists or review a shared project recommendation.";row.add_child(manage);manage.pressed.connect(show_manager);refresh()
func refresh() -> void:
	for choice in controls:
		choice.clear();choice.add_item("Any named collection");choice.set_item_metadata(0,"");choice.add_item("Project recommendation");choice.set_item_metadata(1,"project")
		for value in local.state["collections"]:choice.add_item("Personal · "+value["name"]);choice.set_item_metadata(choice.item_count-1,value["uid"])
		for at in choice.item_count:
			if choice.get_item_metadata(at)==selection():choice.select(at)
		choice.tooltip_text=note() if not selection().is_empty() else "Advisory browsing filter. Exact asset members and saved family snapshots; other filters still apply."
	if is_instance_valid(dialog) and dialog.visible and not loading and is_instance_valid(message):
		var current: Dictionary=studio.project_palette_document.data if scope_choice.selected==1 else Plan.collection(local.state,current_personal_uid())
		if Plan.fingerprint(current)!=draft_source_hash:message.text="The current list changed. Reload the current list before saving this draft."
func label(parent: Node,text: String,size: int=13) -> Label:
	var value:=Label.new();value.text=text;value.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;value.add_theme_font_size_override("font_size",size);parent.add_child(value);return value
func button(parent: Node,text: String,action: Callable,editing: bool=false) -> Button:
	var value:=Button.new();value.text=text;parent.add_child(value);value.pressed.connect(action)
	if editing:edit_buttons.append(value)
	return value
func make_dialog() -> void:
	dialog=AcceptDialog.new();dialog.title="Named collections and project recommendation";dialog.min_size=Vector2i(580,440);dialog.get_ok_button().text="Done";studio.add_child(dialog)
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size=Vector2(540,380);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.follow_focus=true;dialog.add_child(scroll)
	var column:=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.add_theme_constant_override("separation",8);scroll.add_child(column)
	scope_choice=OptionButton.new();scope_choice.add_item("Personal collections · this computer");scope_choice.add_item("Project recommendation · saved and shared");column.add_child(scope_choice);scope_choice.item_selected.connect(func(_at: int):load_draft())
	collection_choice=OptionButton.new();collection_choice.fit_to_longest_item=false;collection_choice.clip_text=true;column.add_child(collection_choice);collection_choice.item_selected.connect(func(_at: int):load_draft())
	name_input=LineEdit.new();name_input.max_length=80;name_input.accessibility_name="Collection name";column.add_child(name_input)
	restriction=CheckBox.new();restriction.text="Restrict new authored content to this project palette";restriction.tooltip_text="Explicitly applies to new objects, ground tiles, citizen appearance, room furnishings, building proposals and zoning. Existing content stays editable; history restoration remains available. Personal collection filters stay advisory.";restriction.accessibility_name=restriction.text;column.add_child(restriction)
	explanation=label(column,"")
	members=Tree.new();members.hide_root=true;members.columns=3;members.set_column_titles_visible(true);members.set_column_title(0,"Saved reference");members.set_column_title(1,"Selection");members.set_column_title(2,"Status");members.set_column_expand(1,false);members.set_column_expand(2,false);members.set_column_custom_minimum_width(1,150);members.set_column_custom_minimum_width(2,120);members.custom_minimum_size.y=180;members.accessibility_name="Saved collection references including missing members";column.add_child(members)
	var pages:=HBoxContainer.new();column.add_child(pages);button(pages,"Previous references",func():member_page=maxi(0,member_page-1);refresh_members());member_note=label(pages,"");member_note.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button(pages,"Next references",func():member_page+=1;refresh_members())
	var removals:=HFlowContainer.new();column.add_child(removals);button(removals,"Remove selected reference",func():remove_selected(false),true);button(removals,"Remove whole saved entry",func():remove_selected(true),true)
	query=LineEdit.new();query.placeholder_text="Find an asset to add or replace";query.accessibility_name=query.placeholder_text;column.add_child(query);query.text_changed.connect(func(_text: String):refresh_results())
	results=Tree.new();results.hide_root=true;results.columns=2;results.set_column_titles_visible(true);results.set_column_title(0,"Available asset");results.set_column_title(1,"Source pack");results.custom_minimum_size.y=150;results.accessibility_name="Available assets for collection references";column.add_child(results)
	result_note=label(column,"")
	var additions:=HFlowContainer.new();column.add_child(additions);button(additions,"Add exact asset",add_asset,true);button(additions,"Add whole family snapshot",add_family,true);button(additions,"Replace selected reference",replace_selected,true)
	var actions:=HFlowContainer.new();column.add_child(actions);save_button=button(actions,"Save personal collection",save_draft);use_button=button(actions,"Use saved list in browser",use_in_browser);delete_button=button(actions,"Delete personal collection",delete_collection)
	var sharing:=HFlowContainer.new();column.add_child(sharing);to_project=button(sharing,"Review as project recommendation…",copy_to_project);to_personal=button(sharing,"Copy recommendation to personal",copy_to_local)
	clear_project_button=button(sharing,"Review removing project palette…",review_clear_project)
	var files:=HFlowContainer.new();column.add_child(files);button(files,"Import collection file…",func():show_file("import"));button(files,"Export saved collection…",func():show_file("export"));button(files,"Copy current favorites",copy_favorites)
	var history_row:=HFlowContainer.new();column.add_child(history_row);undo_button=button(history_row,"Undo personal edit",func():history(false));redo_button=button(history_row,"Redo personal edit",func():history(true));button(history_row,"Reload current list",load_draft);button(history_row,"Refresh saved references",func():index.refresh(studio.library,true);refresh_members();refresh_results())
	message=label(column,"")
	review_dialog=ConfirmationDialog.new();review_dialog.title="Review reference changes";review_dialog.dialog_hide_on_ok=false;review_dialog.min_size=Vector2i(480,280);dialog.add_child(review_dialog);var review_scroll:=ScrollContainer.new();review_scroll.custom_minimum_size=Vector2(440,220);review_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;review_dialog.add_child(review_scroll);review_text=label(review_scroll,"");review_text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;review_dialog.confirmed.connect(apply_review)
	file_dialog=FileDialog.new();file_dialog.access=FileDialog.ACCESS_FILESYSTEM;file_dialog.filters=PackedStringArray(["*.json ; IsoCity collection reference files"]);file_dialog.file_selected.connect(file_selected);dialog.add_child(file_dialog)
func modal() -> bool:return dialog.visible or review_dialog.visible or file_dialog.visible
func gesture_active() -> bool:return studio.companion_tools!=null and studio.companion_tools.gesture_active()
func project_authority() -> bool:return studio.cooperative_tools==null or studio.cooperative_tools.session.role in ["offline","host"]
func show_manager() -> void:
	if gesture_active():studio.status.text="Finish the current canvas edit before opening collections.";return
	fill_collections(selection() if selection()!="project" else "");scope_choice.select(1 if selection()=="project" else 0);message.text="";load_draft();refresh_results()
	if message.text.is_empty():message.text=local.notice
	dialog.popup_centered_clamped(Vector2i(900,780),.9)
func fill_collections(uid: String="") -> void:
	collection_choice.clear();collection_choice.add_item("New personal collection…");collection_choice.set_item_metadata(0,"")
	for item in local.state["collections"]:collection_choice.add_item(item["name"]);collection_choice.set_item_metadata(collection_choice.item_count-1,item["uid"])
	for at in collection_choice.item_count:
		if collection_choice.get_item_metadata(at)==uid:collection_choice.select(at)
func current_personal_uid() -> String:return str(collection_choice.get_item_metadata(collection_choice.selected)) if collection_choice.selected>=0 else ""
func load_draft() -> void:
	if loading:return
	loading=true;var project: bool=scope_choice.selected==1;collection_choice.visible=not project
	var existing: Dictionary=studio.project_palette_document.data.get("collection",{}) if project else Plan.collection(local.state,current_personal_uid())
	draft_source_hash=Plan.fingerprint(studio.project_palette_document.data if project else existing)
	if existing.is_empty():
		var created: Dictionary={"ok":true,"data":Plan.project_empty()["collection"]} if project else Plan.create(Plan.unique_name("New collection",local.state["collections"]))
		draft=created.get("data",{})
		if not created["ok"]:message.text=created["reason"]
	else:draft=existing.duplicate(true)
	name_input.text=draft.get("name","");restriction.set_pressed_no_signal(studio.project_palette_document.data.get("restricted",false));member_page=0;refresh_members();refresh_permissions();loading=false
func refresh_permissions() -> void:
	var project: bool=scope_choice.selected==1;var permitted: bool=not project or project_authority()
	name_input.editable=permitted;restriction.visible=project;restriction.disabled=not permitted
	clear_project_button.visible=project;clear_project_button.disabled=not project_authority() or studio.project_palette_document.data.is_empty()
	for value in edit_buttons:value.disabled=not permitted
	save_button.disabled=not permitted or draft.is_empty();save_button.text="Review project recommendation…" if project else "Save personal collection";use_button.text="Use project recommendation in browser" if project else "Use saved list in browser"
	delete_button.visible=not project;delete_button.disabled=current_personal_uid().is_empty();to_project.visible=not project;to_project.disabled=not project_authority() or current_personal_uid().is_empty();to_personal.visible=project
	var shared: bool=project and studio.cooperative_tools!=null and studio.cooperative_tools.session.connected
	undo_button.text="Undo last shared edit" if shared else ("Undo palette edit" if project else "Undo personal edit");redo_button.text=undo_button.text.replace("Undo","Redo")
	undo_button.disabled=(not project_authority()) if shared else (studio.project_palette_document.undo_history.is_empty() if project else local.undo_history.is_empty());redo_button.disabled=(not project_authority()) if shared else (studio.project_palette_document.redo_history.is_empty() if project else local.redo_history.is_empty())
	explanation.text=("Project recommendations travel with this project and are shared. " if project else "Personal lists stay on this computer and never enter project or co-op data. ")+"An asset means exactly that member. A family snapshot keeps its saved members when the library changes."
	if project and not permitted:explanation.text+=" The host edits this shared recommendation; you can copy it to a personal list."
func refresh_members() -> void:
	members.clear();var root: TreeItem=members.create_item();var resolved: Dictionary=Plan.resolve(draft,studio.library);var rows: Array=resolved.get("rows",[]);member_page=clampi(member_page,0,maxi(0,ceili(rows.size()/float(PAGE))-1))
	for row in rows.slice(member_page*PAGE,(member_page+1)*PAGE):
		var item: TreeItem=members.create_item(root);item.set_text(0,row["name"]);item.set_text(1,"Family snapshot" if not row["family"].is_empty() else "Exact asset");item.set_text(2,"Available" if row["available"] else "Missing");item.set_tooltip_text(2,"Installed prepared source" if row["available"] else "Unavailable pack or prepared source: "+row["id"]);item.set_metadata(0,row);item.set_tooltip_text(0,("Family snapshot · "+row["family"]+"\n" if not row["family"].is_empty() else "Exact asset\n")+row["id"])
		if row["available"]:item.set_icon(0,studio.library.icon(row["id"]));item.set_icon_max_width(0,32)
	member_note.text="%d references · %d unavailable\nPage %d of %d"%[rows.size(),resolved.get("missing",[]).size(),member_page+1,maxi(1,ceili(rows.size()/float(PAGE)))];member_note.tooltip_text="Unavailable references remain saved and can be replaced."
func current_asset() -> String:
	if not studio.asset_id.is_empty():return studio.asset_id
	var chosen: Array=studio.selection_items()
	if chosen.size()==1:return chosen[0]["asset"]
	return studio.asset_browser.selected_id if studio.asset_browser else ""
func refresh_results() -> void:
	results.clear();var root: TreeItem=results.create_item();var found: Array[Dictionary]=[];var exact: String=query.text.strip_edges()
	if studio.library.assets.has(exact):found.append(studio.library.assets[exact])
	else:found=studio.library.find("all","All assets",query.text,[],false)
	var preferred: String=current_asset();var shown: Array[Dictionary]=[]
	if query.text.is_empty() and studio.library.assets.has(preferred):shown.append(studio.library.assets[preferred])
	for asset in found:
		if shown.size()>=PAGE:break
		if asset["id"]!=preferred or not query.text.is_empty():shown.append(asset)
	for asset in shown:
		if not Plan.available(asset["id"],studio.library):continue
		var item: TreeItem=results.create_item(root);item.set_text(0,asset["name"]);item.set_text(1,studio.library.pack_name(asset));item.set_metadata(0,asset["id"]);item.set_tooltip_text(0,asset["name"]+"\n"+asset["id"]);item.set_icon(0,studio.library.icon(asset["id"]));item.set_icon_max_width(0,32)
		if asset["id"]==preferred:item.select(0)
	result_note.text="Showing up to %d of %d matches. Search words narrow the list; nothing is placed here."%[PAGE,found.size()]
func picked_asset() -> String:
	var item: TreeItem=results.get_selected();return str(item.get_metadata(0)) if item else ""
func picked_member() -> Dictionary:
	var item: TreeItem=members.get_selected();return item.get_metadata(0) if item else {}
func update_draft(result: Dictionary) -> void:
	if not result.get("ok",false):message.text=result.get("reason","Choose a saved reference first.");return
	draft=result["data"];refresh_members();message.text="Draft updated. Save or review to keep these references."
func add_asset() -> void:
	var checked: Dictionary=Plan.asset_entry(picked_asset(),studio.library)
	if not checked["ok"]:message.text=checked["reason"];return
	update_draft(Plan.put(draft,checked["entry"]))
func add_family() -> void:
	var checked: Dictionary=Plan.family_entry(picked_asset(),studio.library)
	if not checked["ok"]:message.text=checked["reason"];return
	update_draft(Plan.put(draft,checked["entry"]))
func replace_selected() -> void:
	var selected: Dictionary=picked_member();var checked: Dictionary=Plan.asset_entry(picked_asset(),studio.library)
	if selected.is_empty() or not checked["ok"]:message.text="Choose a saved reference and an available replacement.";return
	update_draft(Plan.replace_member(draft,selected["entry"],selected["member"],Plan.member(picked_asset(),studio.library)) if selected["member"]>=0 else Plan.put(draft,checked["entry"],selected["entry"]))
func remove_selected(whole: bool) -> void:
	var selected: Dictionary=picked_member()
	if selected.is_empty():message.text="Choose a saved reference first.";return
	update_draft(Plan.remove(draft,selected["entry"],-1 if whole else selected["member"]))
func report(result: Dictionary) -> void:message.text=result.get("reason","") if not result.get("ok",false) or not result.get("persisted",true) else "Saved collection references.";refresh();sync_key="";studio.refresh_library();refresh_permissions()
func save_draft() -> void:
	var project: bool=scope_choice.selected==1
	if project and not project_authority():message.text="The host edits the shared project recommendation.";return
	var current: Dictionary=studio.project_palette_document.data if project else Plan.collection(local.state,current_personal_uid())
	if Plan.fingerprint(current)!=draft_source_hash:message.text="The saved collection changed. Reopen it before replacing its references.";return
	var checked: Dictionary=Plan.rename(draft,name_input.text,[] if project else local.state["collections"])
	if not checked["ok"]:message.text=checked["reason"];return
	if project:review_project(checked["data"],restriction.button_pressed);return
	local.storage_enabled=studio.storage_enabled;var result: Dictionary=local.put(checked["data"])
	if result["ok"]:fill_collections(checked["data"]["uid"]);load_draft()
	report(result)
func use_in_browser() -> void:
	var uid: String="project" if scope_choice.selected==1 else current_personal_uid()
	if uid.is_empty():message.text="Save this personal collection before using it in the browser.";return
	studio.asset_browser.clear_all_filters(true);select_filter(uid);dialog.hide()
func delete_collection() -> void:
	local.storage_enabled=studio.storage_enabled;var result: Dictionary=local.remove(current_personal_uid())
	if result["ok"]:fill_collections();load_draft()
	report(result)
func copy_to_project() -> void:
	if not project_authority():message.text="The host edits the shared project recommendation.";return
	var value: Dictionary=Plan.collection(local.state,current_personal_uid()).duplicate(true)
	if value.is_empty():message.text="Save a personal collection before recommending it.";return
	value["uid"]="project_palette";review_project(value)
func copy_to_local() -> void:
	var value: Dictionary=draft.duplicate(true);value["uid"]=Plan.fresh_uid();value["name"]=Plan.unique_name((value["name"]+" copy").left(80),local.state["collections"]);local.storage_enabled=studio.storage_enabled;var result: Dictionary=local.put(value)
	if result["ok"]:scope_choice.select(0);fill_collections(value["uid"]);load_draft()
	report(result)
func copy_favorites() -> void:
	var copied: Dictionary=Plan.migrate_favorites(Plan.empty(),studio.favorites,studio.library)
	if not copied["ok"] or copied["data"]["collections"].is_empty():message.text=copied.get("reason","No current favorites to copy.");return
	var value: Dictionary=copied["data"]["collections"][0];value["name"]=Plan.unique_name(value["name"],local.state["collections"]);local.storage_enabled=studio.storage_enabled;var result: Dictionary=local.put(value)
	if result["ok"]:scope_choice.select(0);fill_collections(value["uid"]);load_draft()
	report(result)
func history(redo: bool) -> void:
	if scope_choice.selected==1:
		if not project_authority():return
		if gesture_active() or shared_pending():message.text="Finish the current edit and wait for shared acceptance before changing project palette history.";return
		studio.finish_palette_boundary()
		if studio.cooperative_tools.session.connected:studio.cooperative_tools.history(redo);return
		var result: Dictionary=studio.project_palette_document.history(redo)
		if result["ok"]:studio.changed();load_draft()
		report(result)
	else:
		local.storage_enabled=studio.storage_enabled;var result: Dictionary=local.history(redo)
		if result["ok"]:fill_collections(selection());load_draft()
		report(result)
func shared_pending() -> bool:return studio.cooperative_tools!=null and studio.cooperative_tools.session.connected and (studio.cooperative_tools.dirty or not studio.cooperative_tools.session.pending.is_empty())
func review_clear_project() -> void:review_policy({})
func review_project(value: Dictionary,restricted_value: Variant=null) -> void:
	var policy: Dictionary=studio.project_palette_document.data.duplicate(true) if not studio.project_palette_document.data.is_empty() else Plan.project_empty();policy["collection"]=value.duplicate(true)
	if restricted_value!=null:policy["restricted"]=bool(restricted_value)
	review_policy(policy)
func review_policy(policy: Dictionary) -> void:
	if not project_authority() or gesture_active() or shared_pending():message.text="Finish the current edit and wait for shared acceptance before reviewing a project palette.";return
	review_plan=studio.project_palette_document.propose(policy)
	if not review_plan["ok"]:message.text=review_plan["reason"];return
	review_kind="project"
	if policy.is_empty():review_text.text="Remove the project palette and disable its content restriction?\n\nPersonal lists and every existing object stay intact. Both worlds return to unrestricted new construction. This changes saved and shared project metadata."
	else:
		var value: Dictionary=policy["collection"];var resolved: Dictionary=Plan.resolve(value,studio.library)
		review_text.text="Use “%s” for this project?\n\n%d saved references · %d unavailable. Missing references remain identifiable.\n\nContent restriction: %s.\n%s\n\nThis changes saved and shared metadata in both worlds. It does not place, recolor, charge for or remove objects. Other collaborators keep their personal browser selection."%[value["name"],resolved["ids"].size(),resolved["missing"].size(),"ON" if policy["restricted"] else "OFF · advisory", "New authored objects, ground, citizen appearance, furnished rooms, building proposals and zoning must use these exact references. Existing content stays editable and history can restore prior content." if policy["restricted"] else "Browser recommendations remain advisory; unrelated construction is allowed."]
	review_dialog.get_ok_button().text="Apply reviewed project palette";review_dialog.popup_centered_clamped(Vector2i(620,500),.9)
func apply_review() -> void:
	if review_kind=="project":
		if not project_authority() or gesture_active() or shared_pending():review_text.text="Wait for the current edit and shared acceptance, then let the host apply the project palette.";return
		studio.finish_palette_boundary()
		var result: Dictionary=studio.project_palette_document.apply(review_plan)
		if not result["ok"]:review_text.text=result["reason"];return
		studio.changed();review_dialog.hide();scope_choice.select(1);load_draft();report(result)
	elif review_kind=="import":
		local.storage_enabled=studio.storage_enabled;var result: Dictionary=local.apply_import(review_plan)
		if not result["ok"]:review_text.text=result["reason"];return
		review_dialog.hide();fill_collections();scope_choice.select(0);load_draft();report(result)
func show_file(action: String) -> void:
	file_action=action;file_dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE if action=="import" else FileDialog.FILE_MODE_SAVE_FILE;file_dialog.title="Import collection references" if action=="import" else "Export saved reference list"
	if action=="export":file_dialog.current_file=(draft.get("name","Collection")+".json").validate_filename()
	file_dialog.popup_centered_clamped(Vector2i(800,600),.9)
func file_selected(path: String) -> void:
	file_dialog.hide()
	if file_action=="import":
		var file:=FileAccess.open(path,FileAccess.READ)
		if not file or file.get_length()>Plan.MAX_BYTES:message.text="Choose a readable collection file of 4 MB or smaller.";return
		review_plan=Plan.import_plan(local.state,file.get_as_text());review_kind="import"
		if not review_plan["ok"]:message.text=review_plan["reason"];return
		review_text.text="Import %d personal collections?\n\n"%review_plan["changes"].size()
		for change in review_plan["changes"]:review_text.text+=change["from"]+(" → "+change["to"] if change["from"]!=change["to"] else "")+"\n"
		review_text.text+="\nExisting lists are retained. This imports references only, including unavailable members; no source artwork or construction permissions are imported.";review_dialog.get_ok_button().text="Import reviewed collections";review_dialog.popup_centered_clamped(Vector2i(620,420),.9)
	else:
		if scope_choice.selected==1:
			var value: Dictionary=studio.project_palette_document.data.get("collection",{});message.text="Project recommendation exported." if not value.is_empty() and studio.Store.write_json(path,Plan.package([value])) else "The saved project recommendation could not be exported."
		else:report(local.export_file(path,[current_personal_uid()]))
