extends RefCounted

const Plan=preload("res://scripts/builder/vehicle_service_plan.gd")
var studio: Control
var page: ScrollContainer
var status: Label
var vehicle_box: VBoxContainer
var bay_box: VBoxContainer
var vehicle_fields: Dictionary={}
var bay_fields: Dictionary={}
var apply_button: Button
var stamp: int=0
var elapsed: float=0

func _init(host: Control) -> void:
	studio=host
	page=ScrollContainer.new()
	page.name="Vehicle Care"
	page.follow_focus=true
	page.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	studio.workspace_layout.tabs.add_child(page)
	var box:=VBoxContainer.new()
	box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	page.add_child(box)
	studio.label(box,"Fuel, charging and vehicle care",17)
	status=studio.label(box,"Select an editable road vehicle or service asset.",12)
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	vehicle_box=VBoxContainer.new()
	box.add_child(vehicle_box)
	vehicle_fields["enabled"]=toggle(vehicle_box,"Enable vehicle care")
	vehicle_fields["energy"]=choice(vehicle_box,"Energy type",["Fuel","Charge"],["fuel","charge"])
	vehicle_fields["class"]=choice(vehicle_box,"Vehicle class",["Car","Van","Heavy"],Plan.CLASSES)
	for spec in [["capacity","Energy capacity",1,250,1],["initial","Starting energy",0,250,1],["condition","Starting condition (%)",0,100,1],["cleanliness","Starting cleanliness (%)",0,100,1],["use_per_metre","Energy used per metre",.05,5,.01]]:
		vehicle_fields[spec[0]]=number_field(vehicle_box,spec)
	bay_box=VBoxContainer.new()
	box.add_child(bay_box)
	bay_fields["enabled"]=toggle(bay_box,"Enable the service bay")
	for spec in [["offset_x","Bay offset across source (m)",-32,32,.1],["offset_z","Bay offset along source (m)",-32,32,.1],["yaw","Approach yaw relative to asset",0,360,1],["width","Usable bay width (m)",2,12,.1],["length","Usable bay length (m)",3,24,.1],["approach","Waiting approach length (m)",2,80,.5],["queue","Waiting vehicles allowed",0,8,1],["price","Service price (credits)",0,100000,1],["seconds","Service duration (seconds)",.5,90,.1]]:
		bay_fields[spec[0]]=number_field(bay_box,spec)
	apply_button=Button.new()
	apply_button.text="Apply vehicle care"
	apply_button.clip_text=true
	box.add_child(apply_button)
	apply_button.pressed.connect(apply_settings)
	var help: Label=studio.label(box,"In Walk, enter a vehicle and drive along the marked approach. Brake and request service. When called, park the entire vehicle in the bay. Wash and repair happen on the outside apron. The vehicle-care wallet and results reset together on returning to Build or reopening.",12)
	help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART

func toggle(parent: Node,title: String) -> CheckButton:
	var button:=CheckButton.new()
	button.text=title
	button.clip_text=true
	parent.add_child(button)
	return button

func choice(parent: Node,title: String,labels: Array,values: Array) -> OptionButton:
	studio.label(parent,title,12)
	var menu:=OptionButton.new()
	menu.fit_to_longest_item=false
	menu.accessibility_name=title
	for index in labels.size():
		menu.add_item(labels[index])
		menu.set_item_metadata(index,values[index])
	parent.add_child(menu)
	return menu

func number_field(parent: Node,spec: Array) -> SpinBox:
	studio.label(parent,spec[1],12)
	var field:=SpinBox.new()
	field.min_value=spec[2]
	field.max_value=spec[3]
	field.step=spec[4]
	field.get_line_edit().accessibility_name=spec[1]
	parent.add_child(field)
	return field

func selected() -> Dictionary:
	if studio.interior_tools.editing(): return {}
	var items: Array=studio.selection_items()
	return items[0] if items.size()==1 and (Plan.site_asset(items[0]) or Plan.vehicle_asset(items[0])) else {}

func show() -> void:
	if studio.walking: studio.set_walking(false)
	studio.workspace_presets.set_focus(false)
	studio.workspace_layout.inspector_toggle.button_pressed=true
	studio.workspace_layout.tabs.current_tab=page.get_index()
	stamp=0
	refresh()

func fill(fields: Dictionary,values: Dictionary) -> void:
	for key in fields:
		var control: Control=fields[key]
		if control is CheckButton: control.set_pressed_no_signal(values[key])
		elif control is OptionButton:
			for index in control.item_count:
				if control.get_item_metadata(index)==values[key]: control.select(index)
		else: control.set_value_no_signal(values[key])

func refresh() -> void:
	var item: Dictionary=selected()
	var next: int=hash([studio.mode,item,studio.interior_tools.editing()])
	if next==stamp: return
	stamp=next
	vehicle_box.visible=Plan.vehicle_asset(item)
	bay_box.visible=Plan.site_asset(item)
	apply_button.disabled=item.is_empty()
	status.text="Select one editable road vehicle or a reviewed service asset."
	if vehicle_box.visible:
		status.text="Configure energy and condition for this vehicle."
		fill(vehicle_fields,Plan.vehicle_settings(item))
	elif bay_box.visible:
		var source: Dictionary=Plan.definitions()["sites"][item["asset"]]
		status.text=Plan.TITLES[source["kind"]]+" · accepts "+", ".join(source["classes"])
		fill(bay_fields,Plan.bay_settings(item))

func applied_values(fields: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for key in fields:
		var control: Control=fields[key]
		if control is CheckButton: result[key]=control.button_pressed
		elif control is OptionButton: result[key]=control.get_item_metadata(control.selected)
		else: result[key]=int(control.value) if key in ["queue","price"] else control.value
	return result

func apply_settings() -> void:
	var item: Dictionary=selected()
	if item.is_empty(): return
	studio.finish_edit(studio.canvas_pointer())
	var doc: RefCounted=studio.current()
	doc.finish_checkpoint()
	item=doc.object(item["uid"])
	if item.is_empty(): return
	var site: bool=Plan.site_asset(item)
	var key: String="vehicle_bay" if site else "vehicle_care"
	var config: Dictionary=applied_values(bay_fields if site else vehicle_fields)
	var next: Dictionary=item.duplicate()
	next[key]=config
	if not (Plan.valid_bay(next) if site else Plan.valid_vehicle(next)):
		studio.status.text="Starting energy must fit the selected capacity."
		return
	if config==(Plan.bay_settings(item) if site else Plan.vehicle_settings(item)): return
	if site and config["enabled"] and not item.get(key,{}).get("enabled",false):
		var count: int=doc.data["objects"].filter(func(record: Dictionary)->bool:return not Plan.bay(record).is_empty()).size()
		if count>=Plan.MAX_BAYS:
			studio.status.text="The city has reached its vehicle service bay limit."
			return
	var before: Dictionary=doc.data.duplicate(true)
	item[key]=config
	doc.record_completed_change(before)
	studio.changed()
	studio.status.text="Vehicle care settings saved."

func tick(delta: float) -> void:
	var driver: Node=studio.worlds[studio.mode].exploration.driving
	driver.care_key=studio.control_settings.label_for("vehicle_service")
	driver.care_cancel_key=studio.control_settings.label_for("vehicle_service_cancel")
	if is_instance_valid(driver.care_view):
		driver.care_view.ui_scale=studio.accessibility_settings.text_scale
		driver.care_view.large_targets=studio.accessibility_settings.large_targets
		driver.care_view.high_contrast=studio.accessibility_settings.high_contrast
		driver.care_view.bottom_inset=74
		driver.care_view.available_width=INF
		if studio.consumer_shell and studio.canvas.size.x>0 and studio.canvas.size.y>0:
			var visible: Vector2=driver.get_viewport().get_visible_rect().size
			var canvas: Rect2=studio.canvas.get_global_rect()
			if studio.consumer_shell.active:
				var room_below: float=canvas.end.y-studio.consumer_shell.hint_panel.get_global_rect().position.y+8
				driver.care_view.bottom_inset=maxf(74,room_below*visible.y/canvas.size.y)
			elif studio.consumer_shell.expert_return.visible:
				var room_left: float=studio.consumer_shell.expert_return.get_global_rect().position.x-canvas.position.x
				driver.care_view.available_width=maxf(220,room_left*visible.x/canvas.size.x-20)
	if not page.is_visible_in_tree(): return
	elapsed+=delta
	if elapsed<.25: return
	elapsed=0
	refresh()
