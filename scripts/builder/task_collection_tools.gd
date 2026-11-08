extends RefCounted
var studio: Control
var task: String=""
var style: String=""
var part: String=""
var settings_path: String="user://studio_task_collections.json"
var controls: Array[Dictionary]=[]
var cached: Dictionary={}
var stamp: String=""

func _init(host: Control,parent: Node) -> void:
	studio=host
	if studio.storage_enabled:restore(studio.Store.read_json(settings_path,{}))
	add_controls(parent)

func restore(value: Variant) -> void:
	var state: Dictionary=value if value is Dictionary else {}
	task=state.get("task","") if state.get("task","") is String and studio.library.tasks.tasks.has(state.get("task","")) else ""
	style=state.get("style","") if not task.is_empty() and state.get("style","") is String and (state.get("style","").is_empty() or studio.library.tasks.tasks[task]["sets"].has(state["style"])) else studio.library.tasks.default_set(task)
	part=state.get("part","") if state.get("part","") in ["","essential","extra"] else ""
	stamp=""

func state() -> Dictionary:return {"task":task,"style":style,"part":part}
func inside() -> bool:
	if not studio.documents.has(studio.mode):return false
	return (studio.interior_tools and studio.interior_tools.editing()) or studio.current().data.get("interior_room",false) or studio.current().data.get("template")=="room"
func selection() -> Dictionary:
	if not task.is_empty():
		if not studio.library.tasks.tasks.has(task):task="";style="";part="";stamp=""
		elif not style.is_empty() and not studio.library.tasks.tasks[task]["sets"].has(style):style=studio.library.tasks.default_set(task);stamp=""
	var current: String=str([task,style,part,inside(),studio.library.tasks.revision])
	if current!=stamp:stamp=current;cached=studio.library.tasks.members(task,style,part,inside())
	return cached
func matches(asset: Dictionary) -> bool:return task.is_empty() or selection()["ids"].has(asset["id"])

func add_controls(parent: Node) -> void:
	var panel:=VBoxContainer.new();parent.add_child(panel)
	var flow:=HFlowContainer.new();panel.add_child(flow)
	var choice:=OptionButton.new();choice.fit_to_longest_item=false;choice.clip_text=true;choice.custom_minimum_size=Vector2(210,40);flow.add_child(choice)
	choice.add_item("Task · Browse all assets");choice.set_item_metadata(0,"")
	for key in studio.library.tasks.tasks:
		choice.add_item(studio.library.tasks.tasks[key]["name"]);choice.set_item_metadata(choice.item_count-1,key)
	choice.tooltip_text="Browse complementary furnishings. Choose and place each item normally."
	choice.item_selected.connect(func(index: int):choose(str(choice.get_item_metadata(index))))
	var sets:=OptionButton.new();sets.fit_to_longest_item=false;sets.clip_text=true;sets.custom_minimum_size=Vector2(170,40);flow.add_child(sets)
	sets.item_selected.connect(func(index: int):style=str(sets.get_item_metadata(index));commit())
	var parts:=OptionButton.new();parts.fit_to_longest_item=false;parts.clip_text=true;parts.custom_minimum_size=Vector2(145,40);flow.add_child(parts)
	for label in ["All parts","Essentials","Extras"]:parts.add_item(label)
	parts.item_selected.connect(func(index: int):part=["","essential","extra"][index];commit())
	var note:=Label.new();note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;note.add_theme_font_size_override("font_size",12);panel.add_child(note)
	controls.append({"panel":panel,"flow":flow,"task":choice,"sets":sets,"parts":parts,"note":note});refresh()

func choose(key: String) -> void:
	# Selecting a task starts a useful compatible set even if unrelated filters
	# previously hid every furnishing. It never edits a document or places art.
	studio.asset_browser.clear_all_filters()
	task=key if studio.library.tasks.tasks.has(key) else "";style=studio.library.tasks.default_set(task);part="";commit()

func clear() -> void:task="";style="";part="";stamp="";refresh();persist()
func persist() -> void:
	if studio.storage_enabled and not studio.Store.write_json(settings_path,state()):studio.status.text="Collection applied for this session; preferences could not be saved."
func commit() -> void:
	stamp="";persist();refresh();studio.page=0;studio.refresh_library()

func refresh() -> void:
	var selected: Dictionary=selection()
	for control in controls:
		var choice: OptionButton=control["task"]
		for index in choice.item_count:
			if choice.get_item_metadata(index)==task:choice.select(index)
		var sets: OptionButton=control["sets"];sets.clear();sets.visible=not task.is_empty();control["parts"].visible=not task.is_empty();control["note"].visible=not task.is_empty()
		if task.is_empty():continue
		for key in studio.library.tasks.tasks[task]["sets"]:
			sets.add_item(studio.library.tasks.tasks[task]["sets"][key]["name"]);sets.set_item_metadata(sets.item_count-1,key)
		sets.add_item("All sets · mixed styles");sets.set_item_metadata(sets.item_count-1,"")
		for index in sets.item_count:
			if sets.get_item_metadata(index)==style:sets.select(index)
		control["parts"].select(["","essential","extra"].find(part))
		var message: String=""
		if not selected["missing"].is_empty():message+="%d items unavailable; their packs may be missing. Choose another set or browse all assets. "%selected["missing"].size()
		if not selected["outdoor"].is_empty():message+="%d outdoor items hidden in this room. Return to the city to browse them. "%selected["outdoor"].size()
		if studio.cards and studio.cards.get_child_count()==0:message+="No visible items. Clear other filters or choose another set. "
		message+=studio.library.tasks.tasks[task]["note"]+" Place items individually. Room layouts: Entrance."
		control["note"].text=message;control["note"].tooltip_text=message
