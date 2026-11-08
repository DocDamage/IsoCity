extends Node

const Plan=preload("res://scripts/builder/business_plan.gd")
const Visits=preload("res://scripts/builder/business_visits.gd")
const Markets=preload("res://scripts/builder/market_runtime.gd")
const DISH_APPROACH = "Approach the serving counter inside this café."
var service=Visits.new()
var market:=Markets.new()
var market_view: Node
var source: Dictionary={}
var standard_businesses: Dictionary={}
var preview_day: int=0
var exploration: Node
var citizens: Node
var instances: Dictionary={}
var dimension: String="2d"
var hour: float=7
var day_length: float=180
var active: bool=true
var signature: int=0
var current_uid: String=""
var message: String=""
var shortcut_label: String="G"
var secondary_label: String="Shift+G"
var cancel_label: String="Alt+G"
var ui_scale: float=1
var large_targets: bool=false
var high_contrast: bool=false
var panel: PanelContainer
var scroll: ScrollContainer
var box: VBoxContainer
var title: Label
var caption: Label
var progress: ProgressBar
var buttons: VBoxContainer
var cancel_button: Button
var items: Label
var shown_actions: String=""
var style_signature: int=-1
var focus_layout_signature: int=0
var panel_area := Rect2() # Optional host HUD area; standalone exports use the viewport.
var cooking_dirty: bool = false
var dish_approach_hint: String = ""

func _ready() -> void:
	service.market_check=func(uid: String,visitor: String)->String:return market.before_purchase(uid,visitor,service)
	service.market_complete=market.settle
	var layer:=CanvasLayer.new(); layer.layer=20; add_child(layer)
	panel=PanelContainer.new(); layer.add_child(panel); panel.hide()
	scroll=ScrollContainer.new(); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; scroll.follow_focus=true; panel.add_child(scroll)
	box=VBoxContainer.new(); box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; box.add_theme_constant_override("separation",6); scroll.add_child(box)
	title=label("",17); caption=label("",13)
	progress=ProgressBar.new(); progress.show_percentage=false; progress.custom_minimum_size.y=12; box.add_child(progress)
	buttons=VBoxContainer.new(); box.add_child(buttons)
	cancel_button=Button.new(); cancel_button.text="Cancel activity"; cancel_button.pressed.connect(func(): service.cancel("player"); message="Activity cancelled.")
	box.add_child(cancel_button)
	items=label("",12)

func label(text: String,size: int) -> Label:
	var control:=Label.new(); control.text=text; control.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; control.add_theme_font_size_override("font_size",size); box.add_child(control); return control

func configure(data: Dictionary,library: RefCounted,nodes: Dictionary,walk: Node,clock: Node,visible_only: bool=true) -> void:
	exploration=walk; citizens=clock; instances=nodes; dimension=data["mode"]; source=data
	if is_instance_valid(walk.fitness): walk.fitness.clock=self
	if is_instance_valid(walk.camping): walk.camping.clock=self
	service.supply_requirement=power_reason
	if is_instance_valid(walk.cooking):
		if not walk.cooking.menu_changed.is_connected(refresh_cooking_menu):
			walk.cooking.menu_changed.connect(refresh_cooking_menu)
		service.dish_check=dish_reason
		service.dish_complete=walk.cooking.serve_visit
	if is_instance_valid(walk.driving) and not walk.driving.delivery.cargo_delivered.is_connected(receive_market_delivery):
		walk.driving.delivery.cargo_delivered.connect(receive_market_delivery)
	var config: Dictionary=preload("res://scripts/builder/citizen_plan.gd").settings(data)
	if signature==0: hour=config["start_hour"]
	day_length=config["day_length"]
	var stamp: int=hash([data["objects"],data.get("layers",{}),data.get("roads",[]),data.get("terrain",{}),data.get("terrain_vertices",[]),data.get("water_cells",[]),visible_only])
	if stamp==signature: return
	signature=stamp
	standard_businesses=Plan.build(data,library,visible_only)
	market.configure(data,library)
	if not market.sites.is_empty() and not is_instance_valid(market_view):
		market_view=load("res://scripts/builder/market_view.gd").new()
		market_view.library=library
		market_view.mode=dimension
		walk.get_parent().add_child(market_view)
	sync_businesses()

func sync_businesses() -> void:
	cooking_dirty=false
	var entries: Dictionary=standard_businesses.duplicate()
	if is_instance_valid(exploration) and is_instance_valid(exploration.cooking) and exploration.cooking.Plan.enabled(source):
		for uid in entries:
			if entries[uid]["config"]["kind"]!="cafe": continue
			var actions: Array=exploration.cooking.menu(uid)
			if not actions.is_empty():
				entries[uid]=entries[uid].duplicate(true)
				entries[uid]["config"]["cooking_actions"]=actions
	entries.merge(market.businesses())
	service.configure(entries)

func refresh_cooking_menu() -> void:
	cooking_dirty=true

func dish_reason(uid: String,visitor: String,result_id: String,queued: int) -> String:
	if not is_instance_valid(exploration) or not is_instance_valid(exploration.cooking): return "The kitchen is unavailable."
	if visitor=="player" and not exploration.cooking.near_counter(uid,result_id): return DISH_APPROACH
	return "All prepared plates are reserved." if exploration.cooking.supply(uid,result_id)<=queued else ""

func market_destination(uid: String) -> Dictionary:
	return market.targets.get(uid,{})

func market_target(resident: Dictionary,actor: Node,eligible: bool) -> String:
	if market.active.is_empty() or not outdoor_market(): return ""
	return market.shopper_target(resident["id"],actor_metric(actor),eligible,service)

func outdoor_market() -> bool:
	return is_instance_valid(exploration) and not exploration.interior and exploration.editor_scope.is_empty() and not (exploration.photo and exploration.photo.active)

func actor_metric(actor: Node) -> Vector2:
	var point: Variant=actor.position
	return market.Plan.Traffic.metric([point.x,point.y,0] if dimension=="2d" else [point.x,point.y,point.z],dimension)

func receive_market_delivery(receipt: Dictionary) -> void:
	var delivery=exploration.driving.delivery
	if delivery.receipts.get(receipt["id"],{})!=receipt: return
	var received: Dictionary=delivery.inventory(receipt["destination"])
	var goods: String=receipt["goods"]
	if int(received.get(goods,0))<receipt["quantity"]: return
	var units: int=market.receive_delivery(receipt,preview_day)
	if units>0: received[goods]=int(received[goods])-units

func available(uid: String) -> bool:
	return service.businesses.has(uid) and Plan.open(service.businesses[uid]["config"],hour) and power_reason(uid).is_empty()

func power_reason(uid: String) -> String:
	if not is_instance_valid(exploration) or not is_instance_valid(exploration.power): return ""
	return exploration.power.requirement(uid,"building")

func player_near(uid: String) -> bool:
	if not is_instance_valid(exploration) or not exploration.enabled or not service.businesses.has(uid): return false
	if market.vendors.has(uid):
		var height: float=exploration.player.position.y if dimension=="3d" else float(exploration.player.get_meta("terrain_height",0))
		return outdoor_market() and exploration.driving.active.is_empty() and absf(height-market.vendors[uid].get("height",0))<=.65 and actor_metric(exploration.player).distance_to(market.vendors[uid]["point"])<=1.35
	if exploration.interior: return exploration.interior_uid==uid
	if not instances.has(uid) or not is_instance_valid(instances[uid]) or not instances[uid].visible: return false
	return exploration.player.position.distance_to(exploration.entrance(instances[uid]))<(50 if dimension=="2d" else 3.5)

func nearby_business() -> String:
	if not is_instance_valid(exploration) or not exploration.enabled: return ""
	if exploration.interior: return exploration.interior_uid if service.businesses.has(exploration.interior_uid) else ""
	var result: String=""; var best: float=50 if dimension=="2d" else 3.5
	for uid in service.businesses:
		if not player_near(uid): continue
		if market.vendors.has(uid): return uid
		var distance: float=exploration.player.position.distance_to(exploration.entrance(instances[uid]))
		if distance<best: best=distance; result=uid
	return result

func request_player(uid: String,action: String) -> Dictionary:
	if cooking_dirty: sync_businesses()
	dish_approach_hint=""
	if not active or not player_near(uid):
		message="Walk to the business entrance or enter its interior first."; return {"ok":false,"reason":message}
	var result: Dictionary=service.request(uid,"player",action,hour)
	message=result["reason"] if not result["ok"] else ""
	if message==DISH_APPROACH: dish_approach_hint=action.trim_prefix("dish/")
	return result

func primary_action(index: int=0) -> void:
	var uid: String=nearby_business()
	if uid.is_empty(): message="Walk to a business entrance to use its activities."; return
	var actions: Array=Plan.activities(service.businesses[uid]["config"])
	if index<actions.size(): request_player(uid,actions[index]["id"])
	else: message="This business offers one activity."

func cancel_activity() -> void:
	if is_instance_valid(exploration) and exploration.cooking.cancel_player(): return
	service.cancel("player"); message="Activity cancelled."

func resident_arrival(uid: String,visitor: String,actor: Node) -> Dictionary:
	if active and market.targets.has(uid) and is_instance_valid(actor):
		var height: float=actor.position.y if dimension=="3d" else float(actor.get_meta("terrain_height",0))
		return market.arrive(uid,visitor,actor_metric(actor),height,hour,service)
	if not active or not service.businesses.has(uid) or not instances.has(uid) or not is_instance_valid(instances[uid]) or not is_instance_valid(actor): return {}
	var entrance: Variant=exploration.entrance(instances[uid])
	var position: Variant=actor.position
	var near: bool
	if dimension=="2d": near=Vector2((position.x-entrance.x)/16,(position.y-entrance.y)/8).length()<6
	else: near=Vector2(position.x-entrance.x,position.z-entrance.z).length()<6 and absf(position.y-entrance.y)<.5
	if not near: return {}
	var result: Dictionary=service.result(visitor)
	if not result.is_empty() and result["business"]==uid: return result
	var actions: Array=Plan.activities(service.businesses[uid]["config"])
	if actions.is_empty(): return {}
	var request: Dictionary=service.request(uid,visitor,actions[0]["id"],hour)
	return request.get("visit",{})

func step(delta: float,advance_clock: bool=true) -> void:
	if not active or not is_finite(delta) or delta<0: return
	if cooking_dirty: sync_businesses()
	if advance_clock:
		if is_instance_valid(citizens) and not citizens.plan.is_empty() and citizens.plan["settings"]["enabled"]:
			hour=citizens.hour
			preview_day=maxi(preview_day,citizens.preview_day)
			citizens.preview_day=preview_day
		else:
			var next: float=hour+maxf(0,delta)*24/day_length
			preview_day+=floori(next/24)
			hour=fposmod(next,24)
	var market_paused: bool=not outdoor_market()
	if not market_paused and (not market.sites.is_empty() or not market.active.is_empty()):
		var rain: bool=Markets.Plan.Weather.state(source)["rain"]>0
		if market.reconcile(hour,preview_day,rain,service):
			sync_businesses()
			if is_instance_valid(market_view): market_view.sync(market.vendors,source.get("night",false))
			if is_instance_valid(citizens): citizens.set_market_obstacles(market.walk_obstacles())
	var player: Dictionary=service.result("player")
	if not player.is_empty() and player["state"] in ["queued","active"] and not player_near(player["business"]):
		if not market_paused or not market.vendors.has(player["business"]): service.cancel("player","You left the business")
	elif player.has("result_id") and player["state"] in ["queued","active"] and not exploration.cooking.near_counter(player["business"],player["result_id"]):
		if not exploration.photo.active: service.cancel("player","You left the serving counter")
	if is_instance_valid(citizens):
		var present: Dictionary={}
		for resident in citizens.residents: present[resident["id"]]=true
		for visitor in service.visits.keys():
			if visitor!="player" and not present.has(visitor): service.forget(visitor)
		for visitor in market.assignments.keys():
			if not present.has(visitor): market.depart(visitor,service)
	service.step(delta,hour,market_paused,is_instance_valid(exploration) and exploration.photo.active)
	if is_instance_valid(market_view):
		market_view.marker_visibility(not market_paused)
		if not market_paused: market_view.stock(market)

func update_ui() -> void:
	if not is_instance_valid(panel): return
	var uid: String=nearby_business() if active else ""
	panel.visible=not uid.is_empty()
	if uid.is_empty(): return
	if uid!=current_uid: message=""; current_uid=uid; dish_approach_hint=""
	if not dish_approach_hint.is_empty() and exploration.cooking.near_counter(uid,dish_approach_hint):
		dish_approach_hint=""
		message=""
	var business: Dictionary=service.businesses[uid]; var config: Dictionary=business["config"]
	var is_market: bool=market.vendors.has(uid)
	var visit: Dictionary=service.result("player")
	title.text=business["name"]+" · "+config["kind"].capitalize()
	var open: bool=Plan.open(config,hour)
	caption.text="%s · %s · %s activities" % [Visits.time_text(hour),"Open" if open else "Closed",shortcut_label]
	if is_market:
		var available_stock: int=market.count(uid)
		caption.text+="\n%s · %d preview credits earned"%["Creative stock" if available_stock<0 else "%d left"%available_stock,market.revenue]
	caption.text+="\n"+message if not message.is_empty() else ""
	var busy: bool=false
	progress.visible=not visit.is_empty() and visit["business"]==uid
	if progress.visible:
		caption.text+="\n"+visit["reason"]
		progress.value=100*(1-visit["remaining"]/visit["duration"])
		busy=visit["state"] in ["active","queued"]
	var stamp: String=uid+str(config)
	if stamp!=shown_actions:
		for child in buttons.get_children(): child.free()
		for action in Plan.activities(config):
			var button:=Button.new(); button.text=action["label"]; button.clip_text=true; buttons.add_child(button)
			if action.has("icon"):
				button.icon=exploration.library.icon(action["icon"])
				button.expand_icon=true
				button.add_theme_constant_override("icon_max_width",30)
			button.pressed.connect(func(): request_player(uid,action["id"]))
		shown_actions=stamp
	for button in buttons.get_children(): button.disabled=busy or not open
	var actions: Array=Plan.activities(config)
	for index in buttons.get_child_count():
		buttons.get_child(index).text=([shortcut_label,secondary_label][index]+" · " if index<2 else "")+actions[index]["label"]
	buttons.visible=not is_market or not busy
	cancel_button.visible=not is_market or busy
	items.visible=not is_market or not busy
	cancel_button.text=cancel_label+" · Cancel activity"
	var possessions: PackedStringArray=[]
	for item in service.inventory.get("player",{}): possessions.append(item+" ×"+str(service.inventory["player"][item]))
	items.text="Session items: "+(", ".join(possessions) if not possessions.is_empty() else "none yet")
	var viewport_size: Vector2=get_viewport().get_visible_rect().size
	var area: Rect2 = panel_area if panel_area.has_area() else Rect2(Vector2(10,10),(viewport_size-Vector2(20,20)).max(Vector2.ONE))
	var width: float=minf(330*ui_scale,area.size.x)
	if is_market and viewport_size.x<1100: width=minf(width,maxf(240,viewport_size.x*.39))
	panel.position=area.position; panel.size=Vector2(width,minf(300*ui_scale,area.size.y))
	var style_stamp: int=hash([ui_scale,large_targets,high_contrast,shown_actions])
	if style_stamp!=style_signature:
		style_signature=style_stamp
		for control in [title,caption,items]: control.add_theme_font_size_override("font_size",roundi((17 if control==title else 13)*ui_scale))
		for button in buttons.get_children()+[cancel_button]: button.custom_minimum_size.y=44 if large_targets else 32; button.add_theme_font_size_override("font_size",roundi(14*ui_scale))
		var style:=StyleBoxFlat.new(); style.bg_color=Color.BLACK if high_contrast else Color("152531"); style.border_color=Color.WHITE if high_contrast else Color("527180"); style.set_border_width_all(2 if high_contrast else 1); style.set_content_margin_all(8)
		panel.add_theme_stylebox_override("panel",style)

	call_deferred("reveal_focus")

func reveal_focus() -> void:
	var focused: Control=get_viewport().gui_get_focus_owner()
	if not is_instance_valid(focused) or not box.is_ancestor_of(focused):focus_layout_signature=0;return
	var stamp: int=hash([focused.get_instance_id(),focused.get_rect(),box.size,scroll.size,title.text,caption.text,items.text])
	if stamp!=focus_layout_signature:scroll.ensure_control_visible(focused);focus_layout_signature=stamp

func _physics_process(delta: float) -> void: step(delta)
func _process(_delta: float) -> void: update_ui()
func reset() -> void:
	if is_instance_valid(exploration) and is_instance_valid(exploration.cooking): exploration.cooking.reset()
	market.reset(service)
	market.sites.clear()
	if is_instance_valid(market_view): market_view.sync({},false)
	if is_instance_valid(citizens):
		var empty: Array[Rect2]=[]
		citizens.set_market_obstacles(empty)
	preview_day=0
	standard_businesses.clear()
	service.reset(); signature=0; current_uid=""; message=""; shown_actions=""; dish_approach_hint=""
	if is_instance_valid(panel): panel.hide()
