extends RefCounted
const Health=preload("res://scripts/builder/asset_health.gd")
const Repair=preload("res://scripts/builder/asset_preview_repair.gd")
const Preview=preload("res://scripts/builder/model_preview.gd")
var studio: Control
var audit: RefCounted
var repair: RefCounted
var dialog: AcceptDialog
var save_dialog: FileDialog
var scroll: ScrollContainer
var summary: Label
var message: Label
var severity: OptionButton
var issues_list: ItemList
var affected: ItemList
var affected_label: Label
var details: RichTextLabel
var pictures: HBoxContainer
var before: TextureRect
var after: TextureRect
var render_button: Button
var apply_button: Button
var inspect_button: Button
var stop_button: Button
var entries: Array=[]
var selected: Dictionary={}
var selected_key: String=""
var shown_ids: Array=[]
var repair_allowed: bool=false
var busy: bool=false
var operation: int=0
var elapsed: float=0

func _init(host: Control,filters: Node) -> void:
	studio=host;audit=Health.new();repair=Repair.new(studio.library,studio.get_tree())
	var open_button:=Button.new();open_button.text="Library health…";filters.add_child(open_button);open_button.pressed.connect(open)
	make_dialog();studio.tree_exiting.connect(shutdown)

func button(parent: Node,title: String,action: Callable) -> Button:
	var result:=Button.new();result.text=title;parent.add_child(result);result.pressed.connect(action);return result

func label(parent: Node,text: String) -> Label:
	var result:=Label.new();result.text=text;result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;parent.add_child(result);return result

func make_dialog() -> void:
	dialog=AcceptDialog.new();dialog.title="Library health";dialog.add_theme_color_override("title_color",Color.WHITE);dialog.min_size=Vector2i(360,280);dialog.exclusive=true;studio.add_child(dialog)
	scroll=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.follow_focus=true;scroll.custom_minimum_size=Vector2(340,220);dialog.add_child(scroll)
	var box:=VBoxContainer.new();box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;box.add_theme_constant_override("separation",10);scroll.add_child(box)
	label(box,"Check previews, prepared sources and frame metadata. Review notes do not mean broken art or missing gameplay behavior.")
	summary=label(box,"Not scanned.")
	var actions:=HFlowContainer.new();box.add_child(actions)
	button(actions,"Scan library",scan);stop_button=button(actions,"Stop scan",stop_scan);button(actions,"Save report…",save_report_dialog)
	severity=OptionButton.new()
	for text in ["Defects & review","Defects only","Review notes"]:severity.add_item(text)
	actions.add_child(severity);severity.item_selected.connect(func(_index: int):clear_proposal();refresh_list(true))
	issues_list=ItemList.new();issues_list.custom_minimum_size.y=170;issues_list.allow_reselect=true;box.add_child(issues_list);issues_list.item_selected.connect(select_issue)
	details=RichTextLabel.new();details.fit_content=true;details.scroll_active=false;details.selection_enabled=true;details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;details.custom_minimum_size.y=50;box.add_child(details)
	affected_label=label(box,"Affected IDs")
	affected=ItemList.new();affected.custom_minimum_size.y=95;affected.allow_reselect=true;box.add_child(affected);affected.item_selected.connect(func(_index: int):show_asset_details())
	inspect_button=button(box,"Inspect selected asset",inspect_selected)
	pictures=HBoxContainer.new();box.add_child(pictures)
	for caption in ["Before","Proposed repair"]:
		var column:=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;pictures.add_child(column);label(column,caption)
		var image:=TextureRect.new();image.custom_minimum_size=Vector2(128,128);image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;column.add_child(image)
		if before==null:before=image
		else:after=image
	var repair_actions:=HFlowContainer.new();box.add_child(repair_actions)
	render_button=button(repair_actions,"Preview thumbnail repair",prepare_repair);apply_button=button(repair_actions,"Apply reviewed repair",apply_repair);button(repair_actions,"Discard repair preview",clear_proposal)
	message=label(box,"")
	dialog.visibility_changed.connect(func():if not dialog.visible:shutdown())
	save_dialog=FileDialog.new();save_dialog.title="Save library-health snapshot";save_dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE;save_dialog.access=FileDialog.ACCESS_FILESYSTEM;save_dialog.filters=PackedStringArray(["*.json ; Library health report"]);studio.add_child(save_dialog);save_dialog.file_selected.connect(save_report)
	update_enabled()

func add_simple(parent: Node) -> void:
	var entry: Button=button(parent,"Library health…",open);entry.custom_minimum_size=Vector2(180,40)

func open() -> void:
	var bounds: Vector2=studio.get_viewport_rect().size
	dialog.popup_centered(Vector2i(mini(860,int(bounds.x)-36),mini(720,int(bounds.y)-48)))
	if audit.status=="not_scanned":scan()
	else:refresh_list()

func modal_visible() -> bool:return dialog.visible or save_dialog.visible

func shutdown() -> void:
	operation+=1;audit.cancel();repair.cancel();busy=false
	if is_instance_valid(before):before.texture=null
	if is_instance_valid(after):after.texture=null

func clear_proposal() -> void:
	operation+=1;repair.cancel();busy=false
	if is_instance_valid(after):after.texture=null
	update_enabled()

func scan() -> void:
	clear_proposal();audit.begin(studio.library);selected_key="";selected={};message.text="Scanning without changing source files or city content. You can stop and keep a partial report.";refresh_list(true)

func stop_scan() -> void:
	audit.cancel();message.text="Scan stopped. This is a partial snapshot; unscanned assets have not been checked.";refresh_list()

func tick(delta: float) -> void:
	if not dialog.visible or not audit.active:return
	audit.step(4,4000)
	elapsed+=delta
	if elapsed>=.3 or not audit.active:
		elapsed=0;refresh_list()

func key(issue: Dictionary) -> String:return str(issue.get("code",""))+"|"+str(issue.get("severity",""))+"|"+str(issue.get("path",""))

func refresh_list(force: bool=false) -> void:
	var report: Dictionary=audit.report();var defects: int=0;var reviews: int=0
	for issue in report["issues"]:
		if issue["severity"]=="defect":defects+=1
		else:reviews+=1
	var state: String={"not_scanned":"Not scanned","scanning":"Scanning","complete":"Complete","cancelled":"Partial · stopped","stale":"Stale · rescan needed"}.get(report["status"],"Not scanned")
	summary.text="%s · %d / %d assets checked · %d defect %s · %d review %s"%[state,report["assets_scanned"],report["assets_total"],defects,"group" if defects==1 else "groups",reviews,"group" if reviews==1 else "groups"]
	summary.tooltip_text=summary.text+". "+report["note"]
	entries=[];issues_list.clear();var target: int=-1
	for issue in report["issues"]:
		if severity.selected==1 and issue["severity"]!="defect" or severity.selected==2 and issue["severity"]!="review":continue
		if key(issue)==selected_key:target=entries.size()
		var count: int=issue["affected_ids"].size()
		entries.append(issue);issues_list.add_item(("Defect" if issue["severity"]=="defect" else "Review")+" · "+issue["title"]+" · %d "%count+("ID" if count==1 else "IDs"));issues_list.set_item_tooltip(issues_list.item_count-1,issue["path"])
	if entries.is_empty():
		selected={};selected_key="";shown_ids=[];affected.clear();affected_label.text="Affected IDs · 0";inspect_button.disabled=true;details.text="No recorded issues in this filter."+(" Scan still in progress." if audit.active else " This snapshot is partial." if audit.status in ["cancelled","stale"] else " Review notes remain separate from definite defects.");pictures.hide();clear_proposal()
	else:
		if target<0:target=0
		issues_list.select(target)
		if force or key(entries[target])!=selected_key:select_issue(target)
		else:selected=entries[target];fill_ids(selected["affected_ids"]);show_asset_details()
	update_enabled()

func fill_ids(ids: Array) -> void:
	if shown_ids==ids:return
	shown_ids=ids.duplicate();affected.clear()
	for id in ids:
		var name: String=str(studio.library.assets.get(id,{}).get("name","Unavailable asset"));affected.add_item(name+" · "+str(id));affected.set_item_tooltip(affected.item_count-1,str(id))
	if affected.item_count>0:affected.select(0)
	affected_label.text="Affected IDs · %d"%ids.size()

func select_issue(index: int) -> void:
	if index<0 or index>=entries.size():return
	clear_proposal();selected=entries[index];selected_key=key(selected);fill_ids(selected["affected_ids"])
	pictures.visible=selected.get("repair")=="model_preview"
	before.texture=Preview.texture_file(selected["path"]) if pictures.visible else null
	var plan: Dictionary=repair.plan(selected);repair_allowed=plan["ok"]
	render_button.tooltip_text="Render a candidate; no thumbnail is replaced until Apply." if repair_allowed else plan["message"]
	message.text="Finish or stop the scan before preparing a repair." if audit.active and repair_allowed else "Review notes do not cause automatic source or metadata changes." if selected["severity"]=="review" else plan.get("message","")
	show_asset_details();update_enabled()

func selected_id() -> String:
	var positions: PackedInt32Array=affected.get_selected_items()
	return str(shown_ids[positions[0]]) if not positions.is_empty() and positions[0]<shown_ids.size() else ""

func can_inspect(id: String) -> bool:
	if not studio.library.assets.has(id):return false
	for issue in audit.issues.values():
		if id in issue["affected_ids"] and issue["severity"]=="defect" and issue["code"] not in ["preview_missing","preview_corrupt","preview_placeholder"]:return false
	return true

func show_asset_details() -> void:
	if selected.is_empty():inspect_button.disabled=true;return
	var id: String=selected_id();var notes: Array=selected.get("details",{}).get(id,[])
	details.text=selected["title"]+"\n"+selected["path"]+"\n"+id+"\n"+"\n".join(notes)
	inspect_button.disabled=not can_inspect(id)

func update_enabled() -> void:
	if is_instance_valid(render_button):render_button.disabled=busy or audit.active or selected.is_empty() or not repair_allowed
	if is_instance_valid(apply_button):apply_button.disabled=busy or audit.active or repair.proposal.is_empty()
	if is_instance_valid(stop_button):stop_button.disabled=not audit.active
	if is_instance_valid(issues_list):issues_list.mouse_filter=Control.MOUSE_FILTER_IGNORE if busy else Control.MOUSE_FILTER_STOP

func prepare_repair() -> void:
	if busy or audit.active or selected.is_empty():return
	busy=true;operation+=1;var request: int=operation;update_enabled();message.text="Rendering a private thumbnail candidate; source and city files remain unchanged."
	var result: Dictionary=await repair.prepare(selected)
	if request!=operation or not dialog.visible:return
	busy=false;message.text=result["message"]
	if result["ok"]:
		fill_ids(result["affected_ids"])
		if not result.get("current",false):after.texture=ImageTexture.create_from_image(result["image"]);scroll.ensure_control_visible(apply_button)
	update_enabled()

func apply_repair() -> void:
	if busy or audit.active:return
	var result: Dictionary=repair.apply();message.text=result["message"]
	if result["ok"]:
		var ids: Array=result["affected_ids"];audit.images.erase(result["path"]);audit.dependencies.clear()
		for issue_key in audit.issues.keys():
			var issue: Dictionary=audit.issues[issue_key]
			for id in ids:issue["affected_ids"].erase(id);issue["details"].erase(id)
			if issue["affected_ids"].is_empty():audit.issues.erase(issue_key)
		for id in ids:audit.inspect(id)
		refresh_theme_icons(ids)
		before.texture=null;after.texture=null;refresh_list(true);studio.refresh_library()
		message.text=result["message"]+(" Recovery copy: "+result["backup"] if not result["backup"].is_empty() else "")
	update_enabled()

func refresh_theme_icons(ids: Array) -> void:
	for index in studio.library.themes.KEYS.size():
		var definition: Dictionary=studio.library.themes.definitions[studio.library.themes.KEYS[index]]
		if definition["preview_id"] not in ids:continue
		var texture: Texture2D=studio.library.icon(definition["preview_id"])
		if not texture:continue
		var image: Image=texture.get_image();var factor: float=minf(1,32.0/maxi(image.get_width(),image.get_height()))
		image.resize(maxi(1,roundi(image.get_width()*factor)),maxi(1,roundi(image.get_height()*factor)),Image.INTERPOLATE_NEAREST)
		var icon: Texture2D=ImageTexture.create_from_image(image);studio.asset_browser.theme_choice.set_item_icon(index+1,icon)
		if studio.consumer_shell:studio.consumer_shell.theme_choice.set_item_icon(index+1,icon)

func inspect_selected() -> void:
	var id: String=selected_id()
	if not can_inspect(id):return
	dialog.hide();studio.asset_browser.show_asset(id)

func save_report_dialog() -> void:
	save_dialog.current_file="library_health.json";save_dialog.popup_centered_ratio(.8)

func save_report(path: String) -> void:
	if path.get_extension().to_lower()!="json":message.text="Choose a JSON report filename; source files are unchanged.";return
	if FileAccess.file_exists(path):
		var previous: Dictionary=Repair.read_cache(path)
		if previous.get("version")!=1 or not previous.get("issues") is Array or not previous.has("assets_total"):message.text="Choose a new report filename or an existing health report; other source/project files are preserved.";return
	message.text="Health snapshot saved." if studio.Store.write_json(path,audit.report()) else "Health snapshot could not be saved; source and city content are unchanged."
