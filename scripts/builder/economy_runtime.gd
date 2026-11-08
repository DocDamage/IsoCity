extends Node
const Plan=preload("res://scripts/builder/economy_plan.gd")
var data: Dictionary={}
var library: RefCounted
var active: bool=true
var paused: bool=false
var elapsed: float=0
var panel: PanelContainer
var summary: Label
var pause_button: Button
var message: String=""
var rates: Dictionary={}
var ui_elapsed: float=0
func _ready() -> void:
	var layer:=CanvasLayer.new(); layer.layer=19; add_child(layer)
	panel=PanelContainer.new(); panel.position=Vector2(20,80); panel.custom_minimum_size=Vector2(270,0); layer.add_child(panel)
	var box:=VBoxContainer.new(); panel.add_child(box)
	summary=Label.new(); summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; summary.custom_minimum_size.x=270; box.add_child(summary)
	pause_button=Button.new(); pause_button.text="Pause accounting"; pause_button.custom_minimum_size.y=36; box.add_child(pause_button)
	pause_button.pressed.connect(func(): paused=not paused; update_ui())
	panel.hide()
func configure(source: Dictionary,assets: RefCounted,shared_city: bool=false) -> void:
	data=source if shared_city else source.duplicate(true); library=assets; elapsed=0; paused=false; message=""
	if Plan.settings(data)["enabled"] and not Plan.valid_account(data.get("economy_account")): data["economy_account"]=Plan.fresh_account(data,library)
	rates=Plan.forecast(data,library) if Plan.settings(data)["enabled"] else {}
	ui_elapsed=0; update_ui()
func step(delta: float) -> void:
	if not active or paused or library==null or not Plan.settings(data)["enabled"] or not is_finite(delta) or delta<=0: return
	elapsed+=minf(delta,.25)
	if elapsed>=Plan.settings(data)["period_seconds"]:
		elapsed=0
		var result: Dictionary=Plan.settle(data,library)
		if result["ok"]: data["economy_account"]=result["account"]
		else: message=result["reason"]; paused=true
	ui_elapsed+=minf(delta,.25)
	if ui_elapsed>=.25: ui_elapsed=0; update_ui()
func update_ui() -> void:
	if not is_instance_valid(panel): return
	panel.visible=library!=null and Plan.settings(data)["enabled"]
	if not panel.visible: return
	var account: Dictionary=data["economy_account"]
	summary.text="Economy · %d credits · period %d\nIncome +%d · upkeep −%d per %ds\nNext settlement %.0fs%s" % [account["cash"],account["period"],rates["income"],rates["upkeep"],Plan.settings(data)["period_seconds"],maxf(0,Plan.settings(data)["period_seconds"]-elapsed)," · paused" if paused else ""]
	if not message.is_empty(): summary.text+="\n"+message
	pause_button.text="Resume accounting" if paused else "Pause accounting"
func _process(delta: float) -> void: step(delta)
