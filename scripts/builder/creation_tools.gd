extends RefCounted
const Share=preload("res://scripts/builder/creation_share.gd")
const Preview=preload("res://scripts/builder/creation_preview.gd")
const Templates=preload("res://scripts/builder/templates.gd")
var studio: Control
var panel: ScrollContainer
var kind: OptionButton
var assembly: OptionButton
var fields: Dictionary={}
var description: TextEdit
var thumbnail: TextureRect
var review: Label
var notice: Label
var import_button: Button
var file: FileDialog
var folder: FileDialog
var prepared: Dictionary={}
var incoming: Dictionary={}
var source: Dictionary={}
var preview: Image
var busy: bool=false
var gallery_folder: String=""
var assembly_stamp: int=0

func _init(host: Control) -> void:
	studio=host; panel=ScrollContainer.new(); panel.name="Sharing"; panel.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; panel.follow_focus=true; studio.workspace_layout.tabs.add_child(panel)
	var box:=VBoxContainer.new(); box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; box.add_theme_constant_override("separation",8); panel.add_child(box)
	studio.label(box,"Creation sharing",17)
	kind=OptionButton.new(); kind.add_item("Current city"); kind.add_item("Saved assembly"); box.add_child(kind); kind.item_selected.connect(func(_index: int):clear_preview(); refresh())
	assembly=OptionButton.new(); assembly.fit_to_longest_item=false; assembly.clip_text=true; box.add_child(assembly); assembly.item_selected.connect(func(_index: int):clear_preview())
	for spec in [["title","Creation title"],["author","Creator name"],["license","Creation license"],["source_url","Creator / source URL"]]:
		studio.label(box,spec[1],12); var entry:=LineEdit.new(); box.add_child(entry); fields[spec[0]]=entry; entry.max_length=100 if spec[0] in ["title","author"] else 500
	studio.label(box,"Description",12); description=TextEdit.new(); description.custom_minimum_size=Vector2(180,100); description.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY; box.add_child(description)
	button(box,"Generate creation preview",generate)
	thumbnail=TextureRect.new(); thumbnail.custom_minimum_size=Vector2(180,112); thumbnail.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; thumbnail.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; box.add_child(thumbnail)
	review=studio.label(box,"Generate a preview to review the exact city or assembly and its asset requirements.",12); review.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	button(box,"Publish to gallery folder",publish_dialog); button(box,"Open gallery in browser",open_gallery)
	button(box,"Review creation download",open_download)
	import_button=button(box,"Import reviewed creation",import_reviewed); import_button.disabled=true
	notice=studio.label(box,"Publish a downloadable layout and preview to a folder. Open its index.html to browse, share the folder, or upload it to a static website host. Downloads list required asset packs and attribution; assets are installed separately. Use portable Godot export for a self-contained playable city.",12); notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	file=FileDialog.new(); file.title="Review IsoCity creation"; file.access=FileDialog.ACCESS_FILESYSTEM; file.file_mode=FileDialog.FILE_MODE_OPEN_FILE; file.filters=PackedStringArray(["*.isocity-share.json ; IsoCity creation"]); file.file_selected.connect(review_download); studio.add_child(file)
	folder=FileDialog.new(); folder.title="Publish creation gallery"; folder.access=FileDialog.ACCESS_FILESYSTEM; folder.file_mode=FileDialog.FILE_MODE_OPEN_DIR; folder.dir_selected.connect(publish_to); studio.add_child(folder)
func button(parent: Node,title: String,callback: Callable) -> Button:
	var control:=Button.new(); control.text=title; control.tooltip_text=title; control.clip_text=true; parent.add_child(control); control.pressed.connect(callback); return control
func show() -> void:
	studio.workspace_presets.set_focus(false)
	if fields["title"].text.is_empty(): fields["title"].text=studio.current().data["title"]
	if studio.get_viewport_rect().size.x<1200: studio.workspace_layout.library_toggle.button_pressed=false
	studio.workspace_layout.inspector_toggle.button_pressed=true; studio.workspace_layout.tabs.current_tab=panel.get_index(); refresh()
func clear_preview() -> void:
	prepared={}; source={}; preview=null; thumbnail.texture=null; incoming={}; import_button.disabled=true; review.text="Generate a fresh preview for the chosen creation."
func refresh() -> void:
	assembly.visible=kind.selected==1
	if assembly_stamp!=hash(studio.assemblies):
		assembly_stamp=hash(studio.assemblies); assembly.clear()
		for index in studio.assemblies.size():
			var entry: Variant=studio.assemblies[index]
			if entry is Dictionary and entry.get("mode") in ["2d","3d"] and entry.get("objects") is Array:
				assembly.add_item(str(entry.get("name","Assembly"))+" · "+entry["mode"]); assembly.set_item_metadata(assembly.item_count-1,index)
func capture_source() -> Dictionary:
	if kind.selected==0:
		studio.finish_edit(studio.canvas_pointer()); studio.interior_tools.flush()
		return {"kind":"city","document":studio.interior_tools.root_document(studio.mode).data.duplicate(true)}
	if assembly.selected<0 or assembly.item_count==0: return {}
	return {"kind":"assembly","assembly":studio.assemblies[assembly.get_item_metadata(assembly.selected)].duplicate(true)}
func metadata() -> Dictionary:
	var result: Dictionary={"kind":"city" if kind.selected==0 else "assembly","description":description.text.strip_edges()}
	for key in fields: result[key]=fields[key].text.strip_edges()
	return result
func generate() -> void:
	if busy: return
	refresh(); var candidate: Dictionary=capture_source()
	if candidate.is_empty(): notice.text="Save or choose an assembly first."; return
	var data: Dictionary=Share.source_document(candidate)
	if not studio.Document.valid(data,data.get("mode",""),studio.library): notice.text="The creation uses invalid records or unavailable assets."; return
	busy=true; incoming={}; import_button.disabled=true; notice.text="Rendering the exact creation in an isolated preview…"
	var image: Image=await Preview.generate(studio,candidate,studio.library)
	source=candidate; preview=image; prepared={}; thumbnail.texture=ImageTexture.create_from_image(image); show_requirements(Share.required_assets(data,studio.library),[])
	notice.text="Preview ready. Publishing uses this exact captured layout. Generate again to include later edits."; busy=false
func show_requirements(requirements: Array,missing: Array) -> void:
	var lines: PackedStringArray=[]
	for entry in requirements: lines.append(("Missing · " if entry["id"] in missing else "Ready · ")+entry["name"]+" · "+entry["pack"])
	review.text="%d required assets\n" % requirements.size()+"\n".join(lines)
func publish_dialog() -> void:
	if busy: return
	if source.is_empty() or preview==null: notice.text="Generate the creation preview first."; return
	var result: Dictionary=Share.prepare(source,metadata(),preview,studio.library)
	if not result["ok"]: notice.text=result["reason"]; return
	prepared=result["creation"]; folder.popup_centered_ratio(.7)
func publish_to(path: String) -> void:
	if prepared.is_empty():
		var result: Dictionary=Share.prepare(source,metadata(),preview,studio.library)
		if not result["ok"]: notice.text=result["reason"]; return
		prepared=result["creation"]
	var result: Dictionary=Share.publish(prepared,path,studio.library)
	if not result["ok"]: notice.text=result["reason"]; return
	gallery_folder=path; notice.text="Published downloadable "+prepared["metadata"]["kind"]+". Open index.html or upload the whole gallery folder to your static host."; studio.status.text="Creation published · "+result["path"]
func open_gallery() -> void:
	if gallery_folder.is_empty(): notice.text="Publish to a gallery folder first."; return
	OS.shell_open("file://"+ProjectSettings.globalize_path(gallery_folder.path_join("index.html")))
func open_download() -> void:
	if not busy: file.popup_centered_ratio(.7)
func review_download(path: String) -> void:
	if busy: return
	incoming={}; prepared={}; source={}; preview=null; import_button.disabled=true; var result: Dictionary=Share.read(path,studio.library)
	if not result["ok"]: notice.text=result["reason"]; return
	incoming=result; thumbnail.texture=ImageTexture.create_from_image(result["preview"]); show_requirements(result["creation"]["requirements"],result["missing"])
	var info: Dictionary=result["creation"]["metadata"]
	notice.text=info["title"]+" · "+info["author"]+"\n"+info["description"]+"\nCreation license: "+info["license"]+"\nSource: "+info["source_url"]+"\n\n"+result["creation"]["attribution"]
	import_button.disabled=not result["missing"].is_empty()
	if import_button.disabled: review.text+="\nInstall these assets, then review the download again."
func import_reviewed() -> void:
	if incoming.is_empty() or busy: return
	# Recheck the catalog and source at the moment the user commits the import.
	var checked: Dictionary=Share.inspect(incoming["creation"],studio.library)
	if not checked["ok"] or not checked.get("missing",[]).is_empty(): notice.text="The creation is no longer importable. Review it again."; import_button.disabled=true; return
	var content: Dictionary=checked["source"]
	if content["kind"]=="assembly":
		var entry: Dictionary=content["assembly"].duplicate(true); entry["share_id"]=checked["creation"]["id"]; entry["creation_credits"]=Share.imported_credits(checked["creation"])
		if not studio.assemblies.any(func(item: Dictionary):return item.get("share_id")==entry["share_id"]):
			var all: Array=studio.assemblies.duplicate(true); all.append(entry)
			if studio.storage_enabled and not studio.Store.write_json("user://studio_assemblies.json",all): notice.text="The assembly library could not be saved."; return
			studio.assemblies=all
		notice.text="Imported into My assemblies · "+entry["name"]+". Choose its view to place it."; refresh()
	else:
		if studio.cooperative_tools.session.role!="offline": notice.text="Leave the cooperative session before opening a shared city."; return
		studio.finish_edit(studio.canvas_pointer()); studio.set_walking(false)
		if studio.interior_tools.editing(): studio.interior_tools.leave()
		studio.clear_placement(); var mode: String=checked["mode"]
		for view in ["2d","3d"]:
			var doc: RefCounted=studio.documents[view]; doc.data=content["document"].duplicate(true) if view==mode else Templates.make(view,"blank")
			if view==mode: doc.data["creation_credits"]=Share.imported_credits(checked["creation"])
			studio.cooperative_tools.clear_history(doc); studio.worlds[view].apply(doc.data); studio.worlds[view].reset_camera()
		studio.project_id=studio.Store.new_id(); studio.project_path=""; studio.saved_digest=""; studio.switch_mode(mode); studio.changed(); studio.dirty=true; studio.update_save_badge()
		notice.text="Opened shared city as a new local project · "+checked["creation"]["metadata"]["title"]
	studio.status.text=notice.text; import_button.disabled=true
