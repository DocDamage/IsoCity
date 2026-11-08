extends RefCounted

const Plan=preload("res://scripts/builder/market_plan.gd")
var studio: Control
var panel: ScrollContainer
var hint: Label
var status: Label
var fields: Dictionary={}
var stalls: Array[Dictionary]=[]
var apply_button: Button
var preview_hour: SpinBox
var stamp: int=0
var elapsed: float=0

func _init(host: Control) -> void:
	studio=host
	panel=ScrollContainer.new()
	panel.name="Market Days"
	panel.follow_focus=true
	panel.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	studio.workspace_layout.tabs.add_child(panel)
	var box:=VBoxContainer.new()
	box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	panel.add_child(box)
	studio.label(box,"Market days",17)
	hint=studio.label(box,"Select a supermarket, HanX grocery or market cart.",12)
	hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	status=studio.label(box,"",12)
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	fields["enabled"]=toggle(box,"Run a market here")
	fields["close_in_rain"]=toggle(box,"Close when it rains")
	fields["stock_policy"]=choice(box,"Stock policy",[["Daily stock","daily"],["Creative stock","creative"],["Delivery-supplied produce","delivery"]])
	fields["goods_style"]=choice(box,"Vendor display artwork",[["Supermarket kit","supermarket"],["HanX goods (portable)","hanx"]])
	for spec in [["open_hour","Opening hour",0,23.5,.5],["close_hour","Closing hour",0,24,.5],["repeat_days","Repeat every (days)",1,7,1],
		["capacity","Visitor limit",1,Plan.MAX_VISITORS,1],["queue","Queue spaces per stall",0,4,1],
		["offset_x","Market offset east (m)",-48,48,.25],["offset_z","Market offset south (m)",-48,48,.25],["spacing","Stall spacing (m)",4,12,.25]]:
		fields[spec[0]]=number(box,spec[1],spec[2],spec[3],spec[4])
	fields["facing"]=choice(box,"Queue direction",[["South",0],["East",90],["North",180],["West",270]])
	var choices: Array=[["Unused",""]]
	for id in Plan.definitions()["vendors"]: choices.append([Plan.definitions()["vendors"][id]["name"],id])
	for index in 3:
		var prefix: String="Stall %d"%(index+1)
		stalls.append({"kind":choice(box,prefix,choices),"stock":number(box,prefix+" starting stock",0,99,1),"price":number(box,prefix+" price",0,999,1)})
	fields["stock_policy"].item_selected.connect(func(_index: int): update_stock_labels())
	apply_button=Button.new()
	apply_button.text="Apply market settings"
	apply_button.clip_text=true
	apply_button.pressed.connect(apply_settings)
	box.add_child(apply_button)
	preview_hour=number(box,"Preview hour (temporary)",0,23.5,.5)
	var preview:=Button.new()
	preview.text="Jump to preview hour"
	preview.clip_text=true
	preview.pressed.connect(func():
		studio.business_tools.managers[studio.mode].hour=preview_hour.value
		studio.citizen_tools.managers[studio.mode].hour=preview_hour.value)
	box.add_child(preview)
	var help: Label=studio.label(box,"Give the stalls, queues, and exits clear space away from roads. In Walk, approach the marked checkout and use the business action. Delivery-supplied fruit and vegetable stalls start empty and receive produce delivered to this host. Closing cancels unfinished sales.",12)
	help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART

func toggle(parent: Node,title: String) -> CheckButton:
	var result:=CheckButton.new()
	result.text=title
	result.clip_text=true
	parent.add_child(result)
	return result

func number(parent: Node,title: String,low: float,high: float,step: float) -> SpinBox:
	studio.label(parent,title,12)
	var result: SpinBox=studio.spin(parent,low,high,step,low)
	result.get_line_edit().accessibility_name=title
	return result

func choice(parent: Node,title: String,options: Array) -> OptionButton:
	studio.label(parent,title,12)
	var result:=OptionButton.new()
	result.fit_to_longest_item=false
	result.clip_text=true
	result.accessibility_name=title
	for option in options:
		result.add_item(option[0])
		result.set_item_metadata(result.item_count-1,option[1])
	parent.add_child(result)
	return result

func selected() -> Dictionary:
	if studio.interior_tools.editing(): return {}
	var items: Array=studio.selection_items()
	return items[0] if items.size()==1 and Plan.eligible(items[0]) else {}

func show() -> void:
	if studio.walking: studio.set_walking(false)
	studio.workspace_presets.set_focus(false)
	studio.workspace_layout.inspector_toggle.button_pressed=true
	studio.workspace_layout.tabs.current_tab=panel.get_index()
	stamp=0
	refresh()

func fill(field: Control,value: Variant) -> void:
	if field is CheckButton: field.set_pressed_no_signal(value)
	elif field is OptionButton:
		for index in field.item_count:
			if field.get_item_metadata(index)==value:
				field.select(index)
				break
	else: field.set_value_no_signal(value)

func update_stock_labels() -> void:
	var delivery: bool=fields["stock_policy"].get_selected_metadata()=="delivery"
	for index in stalls.size():
		var stock: SpinBox=stalls[index]["stock"]
		var label: Label=stock.get_parent().get_child(stock.get_index()-1)
		label.text="Stall %d %s"%[index+1,"stock limit" if delivery else "starting stock"]
		stock.get_line_edit().accessibility_name=label.text

func refresh() -> void:
	var item: Dictionary=selected()
	var next: int=hash([studio.mode,item])
	if next!=stamp:
		stamp=next
		apply_button.disabled=item.is_empty()
		hint.text="Select a supermarket, HanX grocery or market cart." if item.is_empty() else "Set the market schedule, vendor row and queue positions."
		var config: Dictionary=Plan.settings(item)
		for key in fields: fill(fields[key],config[key])
		for index in stalls.size():
			var vendor: Dictionary=config["vendors"][index] if index<config["vendors"].size() else {"kind":"","stock":8,"price":5}
			for key in stalls[index]: fill(stalls[index][key],vendor[key])
		update_stock_labels()
	status.text=""
	if item.is_empty() or studio.business_tools.managers.is_empty(): return
	var manager: Node=studio.business_tools.managers[studio.mode]
	var uid: String=item["uid"]
	var runtime=manager.market
	if runtime.active.has(uid): status.text="Open · %d visitors · %d preview credits earned citywide"%[runtime.people(uid),runtime.revenue]
	elif runtime.sites.has(uid): status.text=runtime.notices.get(uid,runtime.sites[uid]["problem"])
	else: status.text="Market is disabled."

func apply_settings() -> void:
	var item: Dictionary=selected()
	if item.is_empty(): return
	studio.finish_edit(studio.canvas_pointer())
	var doc: RefCounted=studio.current()
	doc.finish_checkpoint()
	item=doc.object(item["uid"])
	if item.is_empty() or not studio.Layers.editable(doc.data,item,studio.library): return
	var config: Dictionary={"vendors":[]}
	for key in fields:
		var field: Control=fields[key]
		if field is CheckButton: config[key]=field.button_pressed
		elif field is OptionButton: config[key]=field.get_selected_metadata()
		else: config[key]=field.value
	for row in stalls:
		var kind: String=row["kind"].get_selected_metadata()
		if not kind.is_empty(): config["vendors"].append({"kind":kind,"stock":int(row["stock"].value),"price":int(row["price"].value)})
	var candidate: Dictionary=item.duplicate()
	candidate["market"]=config
	if not Plan.valid(candidate):
		studio.status.text="Choose a vendor and check the settings. Delivery stock supports fruit and vegetables."
		return
	if config==Plan.settings(item): return
	if config["enabled"] and not Plan.enabled(item) and doc.data["objects"].filter(Plan.enabled).size()>=Plan.MAX_MARKETS:
		studio.status.text="The city has reached its market limit."
		return
	var before: Dictionary=doc.data.duplicate(true)
	item["market"]=config
	doc.record_completed_change(before)
	studio.changed()
	studio.status.text="Market settings saved."

func tick(delta: float) -> void:
	if not panel.is_visible_in_tree(): return
	elapsed+=delta
	if elapsed>=.25:
		elapsed=0
		refresh()
