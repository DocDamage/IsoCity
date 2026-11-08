extends RefCounted

const Plan=preload("res://scripts/builder/delivery_plan.gd")
var studio: Control
var page: ScrollContainer
var hint: Label
var site_box: VBoxContainer
var vehicle_box: VBoxContainer
var site_fields: Dictionary={}
var stock_fields: Dictionary={}
var contract_fields: Dictionary={}
var vehicle_enabled: CheckButton
var capacity: SpinBox
var save_button: Button
var stamp: int=0
var elapsed: float=0

func _init(host: Control) -> void:
	studio=host
	page=ScrollContainer.new()
	page.name="Local Deliveries"
	page.follow_focus=true
	page.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	studio.workspace_layout.tabs.add_child(page)
	var box:=VBoxContainer.new()
	box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	page.add_child(box)
	studio.label(box,"Local delivery jobs",17)
	hint=studio.label(box,"Select a reviewed shop or delivery vehicle.",12)
	hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	vehicle_box=VBoxContainer.new()
	box.add_child(vehicle_box)
	vehicle_enabled=toggle(vehicle_box,"Enable this delivery vehicle")
	capacity=number(vehicle_box,"Cargo capacity",1,16,1)
	site_box=VBoxContainer.new()
	box.add_child(site_box)
	site_fields["enabled"]=toggle(site_box,"Enable a loading site")
	site_fields["offset_x"]=number(site_box,"Pad offset east (m)",-32,32,.25)
	site_fields["offset_z"]=number(site_box,"Pad offset south (m)",-32,32,.25)
	site_fields["capacity"]=number(site_box,"Storage capacity",1,Plan.MAX_STOCK,1)
	for id in Plan.goods(): stock_fields[id]=number(site_box,"Starting "+Plan.goods()[id]["name"].to_lower(),0,Plan.MAX_STOCK,1)
	contract_fields["enabled"]=toggle(site_box,"Offer a pickup contract")
	contract_fields["destination"]=choice(site_box,"Destination")
	contract_fields["goods"]=choice(site_box,"Cargo type")
	for id in Plan.goods(): add_choice(contract_fields["goods"],Plan.goods()[id]["name"],id)
	contract_fields["quantity"]=number(site_box,"Cargo quantity",1,16,1)
	contract_fields["reward"]=number(site_box,"Preview reward (credits)",0,Plan.MAX_REWARD,1)
	contract_fields["deadline"]=number(site_box,"Deadline in seconds (0 for none)",0,1800,1)
	save_button=Button.new()
	save_button.text="Apply delivery settings"
	save_button.clip_text=true
	save_button.pressed.connect(apply_settings)
	box.add_child(save_button)
	var help: Label=studio.label(box,"Enable the destination site first. Both pads need a connected road and space for a stopped vehicle. Shop hours apply. In Walk, use the delivery action to load and unload. Cancelling returns cargo to the pickup stock. The preview resets when you return to Build.",12)
	help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART

func toggle(parent: Node,title: String) -> CheckButton:
	var control:=CheckButton.new()
	control.text=title
	control.clip_text=true
	parent.add_child(control)
	return control

func number(parent: Node,title: String,low: float,high: float,step: float) -> SpinBox:
	studio.label(parent,title,12)
	var field: SpinBox=studio.spin(parent,low,high,step,low)
	field.get_line_edit().accessibility_name=title
	return field

func choice(parent: Node,title: String) -> OptionButton:
	studio.label(parent,title,12)
	var field:=OptionButton.new()
	field.fit_to_longest_item=false
	field.clip_text=true
	field.accessibility_name=title
	parent.add_child(field)
	return field

func add_choice(field: OptionButton,title: String,id: String) -> void:
	field.add_item(title)
	field.set_item_metadata(field.item_count-1,id)

func selected() -> Dictionary:
	if studio.interior_tools.editing(): return {}
	var items: Array=studio.selection_items()
	return items[0] if items.size()==1 else {}

func show() -> void:
	if studio.walking: studio.set_walking(false)
	studio.workspace_presets.set_focus(false)
	studio.workspace_layout.inspector_toggle.button_pressed=true
	studio.workspace_layout.tabs.current_tab=page.get_index()
	stamp=0
	refresh()

func fill(field: Control,value: Variant) -> void:
	if field is CheckButton: field.set_pressed_no_signal(value)
	elif field is OptionButton:
		field.select(0)
		for index in field.item_count:
			if field.get_item_metadata(index)==value:
				field.select(index)
				break
	else: field.set_value_no_signal(value)

func refresh() -> void:
	var item: Dictionary=selected()
	var runtime=studio.worlds[studio.mode].exploration.driving.delivery
	var next: int=hash([studio.mode,item,runtime.sites])
	if next==stamp: return
	stamp=next
	var vehicle: bool=Plan.eligible(item,"delivery_vehicle")
	var site: bool=Plan.eligible(item,"delivery_site")
	vehicle_box.visible=vehicle
	site_box.visible=site
	save_button.disabled=not vehicle and not site
	hint.text="Select one editable delivery vehicle, reviewed shop, supply container, or site office in the exterior city."
	if vehicle:
		var config: Dictionary=Plan.settings(item,"delivery_vehicle")
		capacity.max_value=Plan.definitions()["vehicles"][item["asset"]]
		fill(vehicle_enabled,config["enabled"])
		fill(capacity,config["capacity"])
		hint.text="Choose how many cargo units this vehicle can carry."
	if site:
		var config: Dictionary=Plan.settings(item,"delivery_site")
		var contract: Dictionary=Plan.settings(item,"delivery_contract")
		for key in site_fields: fill(site_fields[key],config[key])
		for key in stock_fields: fill(stock_fields[key],config["stock"].get(key,0))
		var destination: OptionButton=contract_fields["destination"]
		destination.clear()
		add_choice(destination,"Choose an enabled site","")
		var ids: Array=runtime.sites.keys()
		ids.sort()
		for uid in ids:
			if uid!=item["uid"]: add_choice(destination,runtime.sites[uid]["name"]+" · "+uid.right(6),uid)
		if not contract["destination"].is_empty() and not runtime.sites.has(contract["destination"]):
			add_choice(destination,"Unavailable destination",contract["destination"])
		for key in contract_fields: fill(contract_fields[key],contract[key])
		hint.text="Set the loading pad, starting stock, and optional outgoing contract."

func field_values(fields: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for key in fields:
		var control: Control=fields[key]
		if control is CheckButton: result[key]=control.button_pressed
		elif control is OptionButton: result[key]=control.get_item_metadata(control.selected)
		else: result[key]=control.value if key in ["offset_x","offset_z"] else int(control.value)
	return result

func apply_settings() -> void:
	var chosen: Dictionary=selected()
	if chosen.is_empty(): return
	studio.finish_edit(studio.canvas_pointer())
	var doc: RefCounted=studio.current()
	doc.finish_checkpoint()
	var item: Dictionary=doc.object(chosen["uid"])
	if item.is_empty() or not studio.Layers.editable(doc.data,item,studio.library): return
	var next: Dictionary=item.duplicate(true)
	if Plan.eligible(item,"delivery_vehicle"):
		next["delivery_vehicle"]={"enabled":vehicle_enabled.button_pressed,"capacity":int(capacity.value)}
	elif Plan.eligible(item,"delivery_site"):
		next["delivery_site"]=field_values(site_fields)
		next["delivery_site"]["stock"]=field_values(stock_fields)
		next["delivery_contract"]=field_values(contract_fields)
		if Plan.enabled(next,"delivery_site") and not Plan.enabled(item,"delivery_site"):
			var count: int=doc.data["objects"].filter(func(record: Dictionary)->bool:return Plan.enabled(record,"delivery_site")).size()
			if count>=Plan.MAX_SITES:
				studio.status.text="The city has reached its delivery-site limit."
				return
	else: return
	for key in Plan.FIELDS:
		if next.has(key) and not Plan.valid(next,key):
			studio.status.text="Check the storage capacity, vehicle capacity, and destination."
			return
	if next==item: return
	var before: Dictionary=doc.data.duplicate(true)
	item.merge(next,true)
	doc.record_completed_change(before)
	studio.changed()
	studio.status.text="Delivery settings saved."

func tick(delta: float) -> void:
	var driver: Node=studio.worlds[studio.mode].exploration.driving
	driver.delivery_key=studio.control_settings.label_for("delivery_cargo")
	driver.delivery_cancel_key=studio.control_settings.label_for("delivery_cancel")
	if is_instance_valid(driver.delivery_view):
		var view: Node=driver.delivery_view
		view.text_scale=studio.accessibility_settings.text_scale
		view.large_targets=studio.accessibility_settings.large_targets
		view.high_contrast=studio.accessibility_settings.high_contrast
		view.bottom_inset=74
		view.available_width=INF
		if studio.consumer_shell and studio.canvas.size.x>0 and studio.canvas.size.y>0:
			var viewport: Vector2=driver.get_viewport().get_visible_rect().size
			var canvas: Rect2=studio.canvas.get_global_rect()
			if studio.consumer_shell.active:
				var below: float=canvas.end.y-studio.consumer_shell.hint_panel.get_global_rect().position.y+8
				view.bottom_inset=maxf(74,below*viewport.y/canvas.size.y)
			elif studio.consumer_shell.expert_return.visible:
				var back: Rect2=studio.consumer_shell.expert_return.get_global_rect()
				var right: float=canvas.end.x-back.end.x
				if right<300*view.text_scale:
					view.bottom_inset=maxf(74,(canvas.end.y-back.position.y+8)*viewport.y/canvas.size.y)
				else: view.available_width=maxf(220,right*viewport.x/canvas.size.x-20)
	if not page.is_visible_in_tree(): return
	elapsed+=delta
	if elapsed>=.25:
		elapsed=0
		refresh()
