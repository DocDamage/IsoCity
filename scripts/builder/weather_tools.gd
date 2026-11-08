extends RefCounted
const Plan=preload("res://scripts/builder/weather_plan.gd")
var studio: Control
var page: ScrollContainer
var panel: VBoxContainer
var enabled: CheckButton
var condition: OptionButton
var season: OptionButton
var intensity: SpinBox
var wind: SpinBox
var direction: SpinBox
var seed: SpinBox
var foliage: CheckButton
var affect_activity: CheckButton
var cycle: CheckButton
var duration: SpinBox
var apply_button: Button
var status: Label
var managers: Dictionary={}
var stamp: int=0
var elapsed: float=0

func _init(owner_control: Control) -> void:
	studio=owner_control; page=ScrollContainer.new(); page.name="Weather"; page.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_SHOW_NEVER; studio.workspace_layout.tabs.add_child(page)
	panel=VBoxContainer.new(); panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL; page.add_child(panel)
	var title: Label=studio.label(panel,"Weather and seasons",17); title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	enabled=toggle("Enable weather","Weather is optional and applies to the city exterior.")
	condition=choice("Weather",Plan.CONDITIONS); season=choice("Starting season",Plan.SEASONS)
	intensity=field("Precipitation / gusts (%)",0,100,1); wind=field("Wind strength (%)",0,100,1); direction=field("Wind direction · degrees",0,360,5); seed=field("Weather seed",0,2147483647,1)
	foliage=toggle("Seasonal foliage","Change leaf colors while preserving source assets, custom paint and collisions.")
	affect_activity=toggle("Affect daily activity","Heavy rain, snow and strong wind send park visitors home and reduce citizen walking speed. Work and shop schedules remain available.")
	cycle=toggle("Cycle seasons","Advance spring, summer, autumn and winter while the city exterior is active. Loading restarts at the saved starting season.")
	duration=field("Seconds per season",30,86400,30)
	apply_button=Button.new(); apply_button.text="Apply weather"; panel.add_child(apply_button); apply_button.pressed.connect(apply_settings)
	status=studio.label(panel,"Weather is disabled by default.",12); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var help: Label=studio.label(panel,"Rain and snow follow the visible exterior; entering a room suppresses outdoor effects. Wind drifts precipitation and sways tree artwork without moving collision bodies. Seasons affect catalogued deciduous and evergreen foliage in both views. City controls apply outside the room editor and share normal Undo. Weather and season settings travel with playable and portable exports.",12); help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	studio.workspace_layout.prepare_controls(panel)

func toggle(title: String,help: String) -> CheckButton:
	var result:=CheckButton.new(); result.text=title; result.tooltip_text=help; panel.add_child(result); return result
func choice(title: String,values: Array[String]) -> OptionButton:
	studio.label(panel,title,12); var result:=OptionButton.new()
	for value in values: result.add_item(value.capitalize())
	result.accessibility_name=title; panel.add_child(result); return result
func field(title: String,low: float,high: float,step: float) -> SpinBox:
	studio.label(panel,title,12); var result: SpinBox=studio.spin(panel,low,high,step,low); result.accessibility_name=title; return result
func root_document() -> RefCounted: return studio.interior_tools.root_document(studio.mode)
func start() -> void:
	for mode in ["2d","3d"]:
		var manager=preload("res://scripts/builder/weather_runtime.gd").new(); studio.worlds[mode].add_child(manager); managers[mode]=manager
		studio.worlds[mode].exploration.garden.weather_runtime=manager
	refresh()
func show() -> void:
	studio.set_walking(false); studio.workspace_presets.set_focus(false)
	if studio.get_viewport_rect().size.x<1200: studio.workspace_layout.library_toggle.button_pressed=false
	studio.workspace_layout.inspector_toggle.button_pressed=true; studio.workspace_layout.tabs.current_tab=page.get_index(); stamp=0; refresh()
func refresh() -> void:
	if studio.documents.is_empty(): return
	var config: Dictionary=Plan.settings(root_document().data); var next: int=hash([studio.mode,config,studio.interior_tools.editing()])
	if next!=stamp:
		stamp=next; enabled.set_pressed_no_signal(config["enabled"]); condition.select(Plan.CONDITIONS.find(config["condition"])); season.select(Plan.SEASONS.find(config["season"]))
		intensity.set_value_no_signal(config["intensity"]*100); wind.set_value_no_signal(config["wind"]*100); direction.set_value_no_signal(config["wind_direction"]); seed.set_value_no_signal(config["seed"])
		foliage.set_pressed_no_signal(config["foliage"]); affect_activity.set_pressed_no_signal(config["affect_activity"]); cycle.set_pressed_no_signal(config["cycle_seasons"]); duration.set_value_no_signal(config["season_seconds"])
	apply_button.disabled=studio.interior_tools.editing()
func apply_settings() -> void:
	if studio.interior_tools.editing(): studio.status.text="Return to the city to change its weather."; return
	studio.finish_edit(studio.canvas_pointer()); var doc: RefCounted=root_document(); doc.finish_checkpoint(); var before: Dictionary=doc.data.duplicate(true)
	var value: Dictionary=doc.data.get("weather",{}).duplicate(true)
	value.merge({"enabled":enabled.button_pressed,"condition":Plan.CONDITIONS[condition.selected],"season":Plan.SEASONS[season.selected],"intensity":intensity.value/100,"wind":wind.value/100,"wind_direction":direction.value,"seed":int(seed.value),"foliage":foliage.button_pressed,"affect_activity":affect_activity.button_pressed,"cycle_seasons":cycle.button_pressed,"season_seconds":duration.value},true)
	doc.data["weather"]=value
	if doc.record_completed_change(before): studio.changed(); studio.status.text="Saved city weather and seasons. Undo restores the previous settings."
	stamp=0; refresh()
func tick(delta: float) -> void:
	if managers.is_empty(): return
	refresh()
	for mode in managers:
		var manager: Node=managers[mode]
		if mode!=studio.mode:
			if not manager.foliage.entries.is_empty() or manager.screen.visible: manager.reset()
			continue
		var world: Node=studio.worlds[mode]; var exterior: bool=not studio.interior_tools.editing() and world.exploration.interior==null
		var right: Vector3=Vector3(1,0,-1).normalized() if mode=="2d" else world.camera.global_basis.x
		manager.step(delta,root_document().data,world.instances,exterior,right)
	elapsed+=delta
	if elapsed<.3: return
	elapsed=0; refresh()
	var config: Dictionary=managers[studio.mode].current_state
	if config.is_empty() or not config["enabled"]: status.text="Weather is disabled. Original appearance and daily routines are active."
	elif studio.interior_tools.editing() or studio.worlds[studio.mode].exploration.interior!=null: status.text="Outdoor weather is paused while inside."
	else: status.text="%s · %s · %s"%[config["condition"].capitalize(),config["effective_season"].capitalize(),"daily activity affected" if config["affect_activity"] else "normal daily routines"]
func reset() -> void:
	for manager in managers.values(): manager.reset()
	stamp=0
