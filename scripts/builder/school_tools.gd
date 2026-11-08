extends RefCounted

const Plan=preload("res://scripts/builder/school_plan.gd")
var studio: Control
var panel: ScrollContainer
var status: Label
var enabled: CheckButton
var closed: CheckButton
var capacity: SpinBox
var bells: Dictionary={}
var yard: OptionButton
var route: OptionButton
var home_stop: OptionButton
var school_stop: OptionButton
var school: String=""
var selection_stamp: int=0
var elapsed: float=0

func _init(host: Control) -> void:
	studio=host
	panel=ScrollContainer.new()
	panel.name="Schools"
	panel.follow_focus=true
	panel.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	studio.workspace_layout.tabs.add_child(panel)
	var box:=VBoxContainer.new()
	box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	panel.add_child(box)
	studio.label(box,"School life",17)
	status=studio.label(box,"Select a HanX School Building.",12)
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	enabled=CheckButton.new()
	enabled.text="Run school days here"
	box.add_child(enabled)
	closed=CheckButton.new()
	closed.text="Closed for holiday"
	box.add_child(closed)
	capacity=field(box,"Enrollment limit",1,Plan.MAX_ENROLLMENT,1)
	var labels: Array=["Arrival from (hour)","First lesson","Break begins","Class resumes","Dismissal"]
	for index in Plan.BELLS.size():
		bells[Plan.BELLS[index]]=field(box,labels[index],0,23.75,.01)
	studio.label(box,"Break playground",12)
	yard=OptionButton.new()
	yard.fit_to_longest_item=false
	yard.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(yard)
	route=option(box,"School bus route")
	home_stop=option(box,"Neighborhood boarding stop")
	school_stop=option(box,"School boarding stop")
	route.item_selected.connect(func(_index: int): refresh_stops(""))
	var apply:=Button.new()
	apply.text="Apply school settings"
	box.add_child(apply)
	apply.pressed.connect(save)
	var help: Label=studio.label(box,"Use decimal hours. 8.25 means 08:15. Enable residents and assign homes first. Pupils use reachable classroom desks and share them with the player. Choose nearby school grounds for break, or use the school entrance. For rides, enable Transit and mark an operating route to use the school bus. "+str(Plan.definitions().get("placeholder_note","")),12)
	help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART

func option(parent: Node,title: String) -> OptionButton:
	studio.label(parent,title,12)
	var menu:=OptionButton.new()
	menu.fit_to_longest_item=false
	menu.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	menu.accessibility_name=title
	parent.add_child(menu)
	return menu

func chosen(menu: OptionButton) -> String:
	return str(menu.get_item_metadata(menu.selected)) if menu.selected>=0 else ""

func add_choice(menu: OptionButton,label: String,id: String,selected: String) -> void:
	menu.add_item(label)
	menu.set_item_metadata(menu.item_count-1,id)
	if id==selected: menu.select(menu.item_count-1)

func refresh_stops(home: String,school_site: String="") -> void:
	var doc: RefCounted=studio.current()
	var line_id: String=chosen(route)
	var lines: Array=doc.data.get("transit_lines",[]).filter(func(line: Dictionary)->bool:return line["uid"]==line_id)
	for pair in [[home_stop,home],[school_stop,school_site]]:
		var menu: OptionButton=pair[0]
		var previous: String=pair[1]
		menu.clear()
		add_choice(menu,"Choose a stop","",previous)
		menu.select(0)
		menu.disabled=line_id.is_empty()
		if not lines.is_empty():
			for uid in lines[0]["stops"]:
				var stop: Dictionary=doc.object(uid)
				var label: String=stop.get("name",studio.library.assets.get(stop.get("asset",""),{}).get("name","Unavailable stop"))
				add_choice(menu,label,uid,previous)
		if not previous.is_empty() and chosen(menu).is_empty():
			add_choice(menu,"Unavailable stop",previous,previous)

func field(parent: Node,title: String,low: float,high: float,step: float) -> SpinBox:
	studio.label(parent,title,12)
	var spin:=SpinBox.new()
	spin.min_value=low
	spin.max_value=high
	spin.step=step
	spin.get_line_edit().accessibility_name=title
	parent.add_child(spin)
	return spin

func show() -> void:
	studio.workspace_presets.set_focus(false)
	if studio.walking: studio.set_walking(false)
	studio.workspace_layout.inspector_toggle.button_pressed=true
	studio.workspace_layout.tabs.current_tab=panel.get_index()
	refresh(true)

func refresh(force: bool=false) -> void:
	var item: Dictionary=studio.current().object(studio.selected_uid)
	school=item["uid"] if Plan.eligible(item) and not studio.interior_tools.editing() else ""
	var setting: Dictionary=Plan.settings(item)
	var candidates: Array=studio.current().data["objects"].filter(func(candidate: Dictionary)->bool:return Plan.playground(candidate))
	var authored_lines: Array=studio.current().data.get("transit_lines",[])
	var stamp: int=hash([studio.mode,school,setting,candidates,authored_lines])
	if not force and stamp==selection_stamp: return
	selection_stamp=stamp
	enabled.set_pressed_no_signal(setting["enabled"])
	closed.set_pressed_no_signal(setting["closed"])
	capacity.set_value_no_signal(setting["capacity"])
	for key in bells: bells[key].set_value_no_signal(setting[key])
	yard.clear()
	yard.add_item("School entrance")
	yard.set_item_metadata(0,"")
	for candidate in candidates:
		yard.add_item(candidate.get("name",studio.library.assets.get(candidate["asset"],{}).get("name",candidate["asset"])))
		yard.set_item_metadata(yard.item_count-1,candidate["uid"])
		if candidate["uid"]==setting["playground"]: yard.select(yard.item_count-1)
	if not setting["playground"].is_empty() and yard.selected==0:
		yard.add_item("Unavailable playground")
		yard.set_item_metadata(yard.item_count-1,setting["playground"])
		yard.select(yard.item_count-1)
	route.clear()
	add_choice(route,"Walk to school","",setting["bus_line"])
	route.select(0)
	for line in authored_lines:
		if line.get("school_bus",false): add_choice(route,line.get("name","School bus"),line["uid"],setting["bus_line"])
	if not setting["bus_line"].is_empty() and chosen(route).is_empty():
		add_choice(route,"Unavailable school-bus route",setting["bus_line"],setting["bus_line"])
	refresh_stops(setting["home_stop"],setting["school_stop"])

func save() -> void:
	var doc: RefCounted=studio.current()
	var item: Dictionary=doc.object(school)
	if not Plan.eligible(item) or studio.interior_tools.editing() or not studio.selection_items().has(item):
		studio.status.text="Select an editable HanX School Building in the city."
		return
	studio.finish_edit(studio.canvas_pointer())
	doc.finish_checkpoint()
	var config: Dictionary=Plan.settings(item)
	config.merge({"enabled":enabled.button_pressed,"closed":closed.button_pressed,"capacity":int(capacity.value),"playground":yard.get_item_metadata(yard.selected)},true)
	for key in bells: config[key]=bells[key].value
	config["bus_line"]=chosen(route)
	config["home_stop"]=chosen(home_stop) if not config["bus_line"].is_empty() else ""
	config["school_stop"]=chosen(school_stop) if not config["bus_line"].is_empty() else ""
	if not config["bus_line"].is_empty() and (config["home_stop"].is_empty() or config["school_stop"].is_empty() or config["home_stop"]==config["school_stop"]):
		studio.status.text="Choose two different stops on the assigned school-bus route."
		return
	if not Plan.valid(config):
		studio.status.text="Set the bells in order, at least fifteen minutes apart."
		return
	if config["enabled"] and not Plan.enabled(item):
		var count: int=doc.data["objects"].filter(func(candidate: Dictionary)->bool:return Plan.enabled(candidate)).size()
		if count>=Plan.MAX_SCHOOLS:
			studio.status.text="The city already has sixteen enabled schools."
			return
	if config==Plan.settings(item): return
	var before: Dictionary=doc.data.duplicate(true)
	item["school"]=config
	doc.record_completed_change(before)
	studio.changed()
	studio.status.text="School settings saved."

func tick(delta: float) -> void:
	if not panel.is_visible_in_tree(): return
	elapsed+=delta
	if elapsed<.25: return
	elapsed=0
	refresh()
	if school.is_empty():
		status.text="Select a HanX School Building."
		return
	var manager: Node=studio.citizen_tools.managers.get(studio.mode)
	if not is_instance_valid(manager) or not manager.plan.get("settings",{}).get("enabled",false):
		status.text="Enable residents and assign a home to start school."
		return
	status.text=manager.schools.summary(school,manager.hour,manager.activities)
