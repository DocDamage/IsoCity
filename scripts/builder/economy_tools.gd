extends RefCounted
const Plan=preload("res://scripts/builder/economy_plan.gd")
var studio: Control
var panel: ScrollContainer
var enabled: CheckButton
var budget: SpinBox
var period: SpinBox
var refund: SpinBox
var paused: CheckButton
var treasury: Label
var forecast: Label
var asset_price: Label
var notice: Label
var ledger: ItemList
var badge: Label
var elapsed: Dictionary={"2d":0.0,"3d":0.0}
var pauses: Dictionary={"2d":false,"3d":false}
var refresh_time: float=0
var dirty: bool=true

func _init(host: Control) -> void:
	studio=host; panel=ScrollContainer.new(); panel.name="Economy"; panel.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; panel.follow_focus=true
	studio.workspace_layout.tabs.add_child(panel)
	var box:=VBoxContainer.new(); box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; box.add_theme_constant_override("separation",8); panel.add_child(box)
	studio.label(box,"Optional city economy",17)
	treasury=studio.label(box,"Creative mode · unlimited construction",15); treasury.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	forecast=studio.label(box,"",12); forecast.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	enabled=CheckButton.new(); enabled.text="Enable economy mode"; box.add_child(enabled)
	budget=field(box,"Starting budget (credits)",0,1000000000,1)
	period=field(box,"Accounting period (seconds)",10,3600,1)
	refund=field(box,"Demolition refund (% of price paid)",0,100,1)
	button(box,"Apply economy settings",apply_settings)
	paused=CheckButton.new(); paused.text="Pause accounting preview"; box.add_child(paused); paused.toggled.connect(func(value: bool): pauses[studio.mode]=value)
	button(box,"Settle one accounting period",settle)
	button(box,"Start new budget for this city",restart)
	notice=studio.label(box,"",12); notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	asset_price=studio.label(box,"",12); asset_price.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	button(box,"Quote a proposed edit",func(): studio._command("construction_costs", null))
	studio.label(box,"Recent treasury entries",14)
	ledger=ItemList.new(); ledger.custom_minimum_size=Vector2(180,190); box.add_child(ledger)
	var help: Label=studio.label(box,"Creative mode stays unlimited. Economy prices each placed object, painted tile and road section; moving, resizing and recoloring are free. Prices use catalog roles, not visitor-role overrides. Exterior homes, workplaces and shops provide fixed income per period; all owned objects and roads contribute upkeep even when hidden. Room contents incur costs but do not earn extra building income. Automatically supplied starter rooms are free. New buildings copied with furnished rooms pay for those contents. Demolition refunds only the recorded price paid, so starting-city assets have no refund. Operating deficits become debt and prevent new construction; demolition remains available. Settings, treasury and purchases save with the city and support Undo. Preview time resets on load. Start new budget explicitly replaces the treasury and makes existing content the free starting city; Undo restores the previous account.",12)
	help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	badge=studio.label(studio.mode_badge.get_parent(),"",13); badge.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; badge.hide()
	studio.mode_badge.get_parent().move_child(badge,studio.mode_badge.get_index()+1)
func field(parent: Node,title: String,low: float,high: float,step: float) -> SpinBox:
	studio.label(parent,title,12); return studio.spin(parent,low,high,step,low)
func button(parent: Node,title: String,callback: Callable) -> void:
	var control:=Button.new(); control.text=title; control.clip_text=true; parent.add_child(control); control.pressed.connect(callback)
func root_document() -> RefCounted:
	return studio.interior_tools.root_document(studio.mode)
func refresh_fields() -> void:
	if not studio.documents.has(studio.mode): return
	var config: Dictionary=Plan.settings(root_document().data)
	enabled.set_pressed_no_signal(config["enabled"]); budget.set_value_no_signal(config["starting_cash"]); period.set_value_no_signal(config["period_seconds"]); refund.set_value_no_signal(config["refund_percent"])
	paused.set_pressed_no_signal(pauses[studio.mode])
func show() -> void:
	studio.workspace_presets.set_focus(false)
	if studio.walking: studio.set_walking(false)
	studio.workspace_layout.inspector_toggle.button_pressed=true; studio.workspace_layout.tabs.current_tab=panel.get_index(); refresh_fields(); refresh()
func prepare() -> bool:
	if not studio.shared_authority(): studio.status.text="The host manages the shared treasury."; return false
	if studio.interior_tools.editing(): studio.status.text="Configure the treasury from the exterior city editor."; return false
	studio.finish_edit(studio.canvas_pointer()); root_document().finish_checkpoint(); return true
func commit(before: Dictionary) -> void:
	root_document().record_completed_change(before,true); studio.changed(); dirty=true; refresh_fields(); refresh()
func apply_settings() -> void:
	if not prepare(): return
	var doc: RefCounted=root_document(); var before: Dictionary=doc.data.duplicate(true)
	var config: Dictionary={"enabled":enabled.button_pressed,"starting_cash":int(budget.value),"period_seconds":int(period.value),"refund_percent":int(refund.value)}
	if config==Plan.settings(doc.data): studio.status.text="Economy settings are unchanged."; return
	var value: Dictionary=doc.data.get("economy",{}).duplicate(true); value.merge(config,true); doc.data["economy"]=value
	if config["enabled"] and not Plan.valid_account(doc.data.get("economy_account")): doc.data["economy_account"]=Plan.fresh_account(doc.data,studio.library)
	commit(before); studio.status.text="Economy settings applied. Existing treasury funds are retained."
func restart() -> void:
	if not prepare(): return
	var doc: RefCounted=root_document(); var before: Dictionary=doc.data.duplicate(true)
	doc.data["economy_account"]=Plan.fresh_account(doc.data,studio.library); elapsed[studio.mode]=0
	commit(before); studio.status.text="Started a new budget; existing content is the free starting city. Undo restores the old treasury."
func settle() -> void:
	if not prepare(): return
	settle_period()
func settle_period() -> void:
	if not studio.shared_authority(): return
	if studio.cooperative_tools and studio.cooperative_tools.session.connected:
		studio.cooperative_tools.session.settle_economy(studio.mode); return
	var doc: RefCounted=root_document(); doc.finish_checkpoint()
	var result: Dictionary=Plan.settle(doc.data,studio.library)
	if not result["ok"]: studio.status.text=result["reason"]; return
	var before: Dictionary=doc.data.duplicate(true); doc.data["economy_account"]=result["account"]
	commit(before); studio.status.text="Accounting period: +%d income, −%d operating costs." % [result["income"],result["upkeep"]]
func reconcile() -> bool:
	var doc: RefCounted=root_document()
	var accepted: bool=doc.reconcile_economy(studio.library)
	if not accepted:
		if studio.interior_tools.editing(): studio.interior_tools.restore_owned(doc.object(studio.interior_tools.uid)["interior"])
		studio.stroke=false; studio.road_drawing=false
		studio.ground_brush.drawing=false; studio.ground_brush.surfaces.clear()
		studio.status.text=doc.economy_error
	dirty=true
	refresh_badge()
	return accepted
func refresh() -> void:
	var doc: RefCounted=root_document(); var data: Dictionary=doc.data; var config: Dictionary=Plan.settings(data)
	treasury.text="Creative mode · unlimited construction"
	forecast.text="Enable economy to track construction budgets, operating costs and income."
	ledger.clear()
	if config["enabled"]:
		var account: Dictionary=Plan.account(data,studio.library); var rates: Dictionary=Plan.forecast(data,studio.library)
		treasury.text="Treasury · %d credits · period %d" % [account["cash"],account["period"]]
		forecast.text="Per %ds: income +%d\nUpkeep −%d · net %+d\nNext settlement: %.0fs%s" % [config["period_seconds"],rates["income"],rates["upkeep"],rates["net"],maxf(0,config["period_seconds"]-elapsed[studio.mode])," · paused" if pauses[studio.mode] else ""]
		var rows: Array=account["ledger"].duplicate(); rows.reverse()
		for row in rows:
			ledger.add_item(("Period %d · +%d / −%d" % [row["period"],row["income"],row["upkeep"]] if row["kind"]=="period" else "Build −%d · refund +%d" % [row["construction"],row["refund"]])+" · balance %d" % row["cash"])
	notice.text=doc.economy_error
	var id: String=studio.current().object(studio.selected_uid).get("asset",studio.asset_id)
	asset_price.text="Choose an asset or select an object to inspect its price."
	if studio.library.assets.has(id):
		var price: Dictionary=Plan.profile(id,studio.library)
		asset_price.text=studio.library.assets[id]["name"]+"\nConstruction %d · upkeep %d · exterior income %d per period" % [price["construction"],price["upkeep"],price["income"]]
	dirty=false
func refresh_badge() -> void:
	var doc: RefCounted=root_document(); var config: Dictionary=Plan.settings(doc.data)
	badge.visible=config["enabled"]
	if not config["enabled"]: return
	# Cash is validated on load/transactions; an idle badge need not copy the
	# whole city's purchase book several times per second.
	var account: Dictionary=doc.data.get("economy_account",{})
	if account.is_empty(): account=Plan.fresh_account(doc.data,studio.library)
	badge.text="Economy · %d credits%s" % [account["cash"]," · accounting paused" if pauses[studio.mode] else ""]
	if not doc.economy_error.is_empty(): badge.text+=" · "+doc.economy_error
func tick(delta: float) -> void:
	var doc: RefCounted=root_document(); doc.economy_library=studio.library
	if studio.shared_authority() and Plan.settings(doc.data)["enabled"] and not pauses[studio.mode] and not studio.modal_visible() and not studio.interior_tools.editing() and not studio.stroke and not studio.road_drawing and not studio.ground_brush.drawing and not studio.transform_handles.dragging:
		if is_finite(delta) and delta>0: elapsed[studio.mode]+=minf(delta,.25)
		if elapsed[studio.mode]>=Plan.settings(doc.data)["period_seconds"]: elapsed[studio.mode]=0; settle_period()
	refresh_time+=delta
	if refresh_time>=.4:
		refresh_time=0
		refresh_badge()
		if panel.is_visible_in_tree(): refresh()
func reset() -> void:
	elapsed={"2d":0.0,"3d":0.0}; pauses={"2d":false,"3d":false}; dirty=true; refresh_fields()
