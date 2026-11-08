extends RefCounted
const Plan=preload("res://scripts/builder/business_plan.gd")
const Runtime=preload("res://scripts/builder/business_runtime.gd")
const CatalogDefaults=preload("res://scripts/builder/catalog_defaults.gd")
var studio: Control
var panel: ScrollContainer
var context: Label
var status: Label
var kind: OptionButton
var opening: SpinBox
var closing: SpinBox
var capacity: SpinBox
var duration: SpinBox
var hour: SpinBox
var list: ItemList
var managers: Dictionary={}
var dirty: bool=true
var selection_signature: int=-1
var elapsed: float=0

func _init(host: Control) -> void:
	studio=host
	panel=ScrollContainer.new(); panel.name="Businesses"; panel.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; panel.follow_focus=true; studio.workspace_layout.tabs.add_child(panel)
	var box:=VBoxContainer.new(); box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; box.add_theme_constant_override("separation",8); panel.add_child(box)
	studio.label(box,"Businesses and activities",17)
	status=studio.label(box,"",12); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	context=studio.label(box,"Select editable objects to configure businesses.",12); context.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	kind=OptionButton.new(); kind.fit_to_longest_item=false; kind.clip_text=true
	for title in ["Catalog defaults","Café","Shop","Service counter","No business","Mixed selection"]: kind.add_item(title)
	kind.set_item_disabled(5,true); box.add_child(kind)
	opening=field(box,"Opening hour",0,23.9,.5)
	closing=field(box,"Closing hour",0,24,.5)
	capacity=field(box,"Simultaneous visitors",1,32,1)
	duration=field(box,"Activity duration multiplier",.25,10,.25)
	button(box,"Apply to selected businesses",apply_settings)
	var help: Label=studio.label(box,"Catalog cafés and shops already offer activities. Assign a type to other objects to attract resident shoppers unless a citizen role overrides it. Equal opening and closing hours mean all day. Applying replaces all displayed settings on the selected editable objects; Catalog defaults removes overrides. Walk to an entrance or enter its interior, then use the activity buttons or the business shortcut. Results and visitors are temporary session state; no money is spent.",12); help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	hour=field(box,"Preview hour (temporary)",0,23.9,.5)
	button(box,"Jump to preview hour",func():
		managers[studio.mode].hour=hour.value; studio.citizen_tools.managers[studio.mode].hour=hour.value)
	list=ItemList.new(); list.custom_minimum_size=Vector2(180,180); box.add_child(list)

func field(parent: Node,title: String,low: float,high: float,step: float) -> SpinBox:
	studio.label(parent,title,12); return studio.spin(parent,low,high,step,low)
func button(parent: Node,title: String,callback: Callable) -> void:
	var control:=Button.new(); control.text=title; control.clip_text=true; parent.add_child(control); control.pressed.connect(callback)

func start() -> void:
	for mode in ["2d","3d"]:
		var manager:=Runtime.new(); manager.name="Businesses"; studio.worlds[mode].add_child(manager); managers[mode]=manager
		studio.citizen_tools.managers[mode].businesses=manager
		studio.worlds[mode].exploration.driving.business_clock=manager
		studio.worlds[mode].exploration.fitness.clock=manager
		studio.worlds[mode].exploration.camping.clock=manager

func show() -> void:
	studio.workspace_presets.set_focus(false)
	if studio.walking: studio.set_walking(false)
	studio.workspace_layout.inspector_toggle.button_pressed=true; studio.workspace_layout.tabs.current_tab=panel.get_index(); refresh_selection()

func refresh_selection() -> void:
	var items: Array=studio.selection_items()
	var stamp: int=hash([studio.mode,items.map(func(item: Dictionary):return [item["uid"],item["asset"],item.get("business",{}),item.get(CatalogDefaults.FIELD,0)])])
	if stamp==selection_signature: return
	selection_signature=stamp
	if items.is_empty(): context.text="Select editable objects to configure businesses."; return
	var profiles: Array=items.map(func(item: Dictionary):return Plan.profile(item))
	var overrides: Array=items.map(func(item: Dictionary):return item.get("business",{}).get("kind",""))
	var choices: Array=["","cafe","shop","service","none"]
	kind.select(choices.find(overrides[0]) if overrides.all(func(value: String):return value==overrides[0]) else 5)
	var fields: Array=[opening,closing,capacity,duration]
	var keys: Array=["open_hour","close_hour","capacity","duration_scale"]
	var names: Array=["Opening hour","Closing hour","Simultaneous visitors","Activity duration multiplier"]
	for index in 4:
		fields[index].set_value_no_signal(profiles[0][keys[index]])
		# Labels remain adjacent to fields even after accessibility styling.
		var label: Label=fields[index].get_parent().get_child(fields[index].get_index()-1)
		label.text=names[index]+(" · Mixed" if not profiles.all(func(p: Dictionary):return p[keys[index]]==profiles[0][keys[index]]) else "")
	context.text="%d editable objects · Applying replaces all displayed business settings." % items.size()
	if items.any(func(item: Dictionary) -> bool: return CatalogDefaults.reviewed(item["asset"]) and not CatalogDefaults.enabled(item)):
		context.text += " Older reviewed buildings keep their previous behavior. Apply Catalog defaults to enable the reviewed activities, or choose No business to keep them decorative."

func apply_settings() -> void:
	if studio.interior_tools.editing(): studio.status.text="Configure businesses from the exterior city editor."; return
	if kind.selected>=5: studio.status.text="Choose a business type for the mixed selection."; return
	studio.finish_edit(studio.canvas_pointer())
	var items: Array=studio.selection_items()
	if items.is_empty(): studio.status.text="Select editable business objects first."; return
	var changes: Dictionary={}
	var revisions: Dictionary={}
	for item in items:
		var config: Dictionary=item.get("business",{}).duplicate(true)
		if kind.selected==0:
			for key in Plan.defaults("none"): config.erase(key)
			if CatalogDefaults.reviewed(item["asset"]) and not CatalogDefaults.enabled(item): revisions[item["uid"]]=true
		else: config.merge({"kind":["","cafe","shop","service","none"][kind.selected],"open_hour":opening.value,"close_hour":closing.value,"capacity":int(capacity.value),"duration_scale":duration.value},true)
		if config!=item.get("business",{}) or revisions.has(item["uid"]): changes[item["uid"]]=config
	if changes.is_empty(): studio.status.text="Business settings are unchanged."; return
	studio.current().checkpoint()
	for item in items:
		if not changes.has(item["uid"]): continue
		if revisions.has(item["uid"]): CatalogDefaults.stamp(item)
		if changes[item["uid"]].is_empty(): item.erase("business")
		else: item["business"]=changes[item["uid"]]
	studio.changed(); dirty=true; studio.status.text="Business settings applied to %d objects. Undo restores previous settings." % changes.size()

func tick(delta: float) -> void:
	if managers.is_empty(): return
	for mode in managers:
		var manager: Node=managers[mode]
		manager.panel_area = Rect2()
		if studio.consumer_shell and studio.consumer_shell.active:
			var shell: RefCounted = studio.consumer_shell
			var top: float = maxf(shell.header.position.y + shell.header.size.y, shell.header_actions.position.y + shell.header_actions.size.y) + 12
			if shell.room_navigation.visible: top = maxf(top,shell.room_navigation.position.y+shell.room_navigation.size.y+12)
			if shell.status_panel.visible: top = maxf(top,shell.status_panel.position.y+shell.status_panel.size.y+12)
			var bottom: float = minf(shell.hint_panel.position.y,shell.dock.position.y) - 12
			manager.panel_area = Rect2(22, top, maxf(1,studio.size.x-44), maxf(1,bottom-top))
		else:
			# Enlarged precision workspaces may scroll beyond the physical window.
			# Fit the HUD to the visible canvas so its own focus scroll can reveal actions.
			var canvas_rect: Rect2=studio.canvas.get_global_rect()
			var visible: Rect2=canvas_rect.intersection(studio.get_viewport().get_visible_rect())
			if studio.consumer_shell:
				for control in [studio.consumer_shell.focus_return,studio.consumer_shell.expert_return]:
					if control.is_visible_in_tree():visible.size.y=maxf(1,minf(visible.end.y,control.get_global_rect().position.y-10)-visible.position.y)
			manager.panel_area=Rect2(visible.position-canvas_rect.position+Vector2(10,10),(visible.size-Vector2(20,20)).max(Vector2.ONE))
		manager.active=mode==studio.mode and not studio.modal_visible() and not studio.interior_tools.editing()
		manager.shortcut_label=studio.control_settings.label_for("business")
		manager.secondary_label=studio.control_settings.label_for("business_secondary"); manager.cancel_label=studio.control_settings.label_for("business_cancel")
		manager.ui_scale=studio.accessibility_settings.text_scale; manager.large_targets=studio.accessibility_settings.large_targets; manager.high_contrast=studio.accessibility_settings.high_contrast
		var laundry: Node=studio.worlds[mode].exploration.laundry
		if not manager.active: laundry.close_counter()
		laundry.panel_area=manager.panel_area
		laundry.ui_scale=manager.ui_scale
		laundry.large_targets=manager.large_targets
		laundry.high_contrast=manager.high_contrast
		var fitness: Node=studio.worlds[mode].exploration.fitness
		fitness.panel_area=manager.panel_area
		fitness.ui_scale=manager.ui_scale
		fitness.large_targets=manager.large_targets
		fitness.high_contrast=manager.high_contrast
		fitness.interact_label=studio.control_settings.label_for("interact")
		fitness.hud_enabled=mode==studio.mode and not studio.modal_visible()
	if dirty and not studio.interior_tools.editing() and not studio.stroke and not studio.ground_brush.drawing and not studio.transform_handles.dragging:
		managers[studio.mode].configure(studio.current().data,studio.library,studio.worlds[studio.mode].instances,studio.worlds[studio.mode].exploration,studio.citizen_tools.managers[studio.mode]); dirty=false
	if panel.is_visible_in_tree(): refresh_selection()
	elapsed+=delta
	if elapsed<.4: return
	elapsed=0
	var manager: Node=managers[studio.mode]; var open: int=0
	for uid in manager.service.businesses:
		if manager.available(uid): open+=1
	status.text="%s · %d businesses · %d open · %d completed visits" % [preload("res://scripts/builder/business_visits.gd").time_text(manager.hour),manager.service.businesses.size(),open,manager.service.history.size()]
	list.clear()
	for visit in manager.service.visits.values():
		list.add_item(visit["visitor"]+" · "+visit["reason"]); list.set_item_tooltip(list.item_count-1,visit["label"]+" · "+visit["reason"])

func reset() -> void:
	for manager in managers.values(): manager.reset()
	dirty=true; selection_signature=-1
