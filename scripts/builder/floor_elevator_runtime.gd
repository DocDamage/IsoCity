extends Node

const Plan=preload("res://scripts/builder/floor_elevator_plan.gd")
const LinkReservations=preload("res://scripts/builder/floor_link_reservations.gd")
const PassengerState=preload("res://scripts/builder/resident_elevator_state.gd")
var stack: Node
var actor: Node
var view: Node
var link: Dictionary
var stops: Array=[]
var height: float=0
var last_stop: String="ground"
var target: String=""
var phase: String="idle"
var elapsed: float=0
var motion: Dictionary={}
var rider: bool=false
var saved_physics: bool=false
var frozen: bool=false
var saved_offset:=Vector2.ZERO
var queue: Array[String]=[]
var notice: String=""
var menu: PanelContainer
var choices: VBoxContainer
var status: Label
var reservations: RefCounted
var reservation_key: String=""
var reservation_token: int=0
var npc: Node
var npc_token: int=0
var npc_complete: bool=false
var npc_source: String=""
var restoration_pending: int=0
var call_owner_token: int=0

func configure(owner_stack: Node,record: Dictionary,presentation: Node) -> void:
	stack=owner_stack; actor=stack.actor; link=record; view=presentation; stops=Plan.stops(stack.room,record)
	last_stop=stops[0]["uid"]; height=float(stops[0]["height"])
	view.configure(self); view.set_height(height); view.open_at(last_stop,1)
	var layer:=CanvasLayer.new(); layer.layer=210; add_child(layer)
	menu=PanelContainer.new(); menu.visible=false; menu.position=Vector2(28,100); menu.custom_minimum_size=Vector2(260,0); layer.add_child(menu)
	var column:=VBoxContainer.new(); menu.add_child(column)
	var title:=Label.new(); title.text="Elevator · choose floor"; column.add_child(title)
	var scroll:=ScrollContainer.new(); scroll.custom_minimum_size=Vector2(260,110); scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; scroll.follow_focus=true; column.add_child(scroll)
	choices=VBoxContainer.new(); choices.size_flags_horizontal=Control.SIZE_EXPAND_FILL; choices.add_theme_constant_override("separation",8); scroll.add_child(choices)
	for floor in stops:
		var button:=Button.new(); button.text="%s · %+.1f m"%[floor["name"],floor["height"]]; button.tooltip_text=button.text; button.clip_text=true; button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; button.custom_minimum_size.y=44; button.set_meta("floor_uid",floor["uid"]); choices.add_child(button)
		button.pressed.connect(choose.bind(floor["uid"]))
	var cancel:=Button.new(); cancel.text="Cancel"; cancel.custom_minimum_size.y=44; choices.add_child(cancel); cancel.pressed.connect(cancel_menu)
	status=Label.new(); status.position=Vector2(28,70); status.add_theme_color_override("font_shadow_color",Color.BLACK); status.add_theme_constant_override("shadow_offset_x",1); status.add_theme_constant_override("shadow_offset_y",1); layer.add_child(status)

func stop_height(uid: String) -> float:
	for floor in stops:
		if floor["uid"]==uid: return float(floor["height"])
	return height

func stop_name(uid: String) -> String:
	for floor in stops:
		if floor["uid"]==uid: return floor["name"]
	return uid

func reserve_player() -> bool:
	if reservation_token:return true
	reservations=LinkReservations.ledger(stack);reservation_key=LinkReservations.key(stack,link["uid"])
	reservation_token=reservations.acquire(reservation_key,self)
	if reservation_token==0:notice="The elevator is reserved by another activity. Wait outside the cabin.";return false
	return true

func release_reservation() -> void:
	if reservations and reservation_token:reservations.release(reservation_key,reservation_token)
	reservations=null;reservation_key="";reservation_token=0

func sync_occupancy() -> void:
	# Cancelling a menu or opening the doors does not empty the cabin. Hold its
	# capacity until the player physically leaves, including after a blocked trip.
	if (rider and npc_token==0) or menu.visible or view.fully_inside():reserve_player()
	else:release_reservation()

func occupant() -> Node:
	return npc if npc_token!=0 and is_instance_valid(npc) else actor if npc_token==0 and is_instance_valid(actor) else null

func begin_passenger(body: Node,source: String,destination: String,token: int,logical_boarding: bool=false) -> bool:
	if npc_token!=0 or phase!="idle" or menu.visible or rider or last_stop!=source or view.fully_inside():return false
	if call_owner_token!=0 and call_owner_token!=token:return false
	if not is_instance_valid(body) or body==actor or token==0 or not stops.any(func(floor: Dictionary):return floor["uid"]==destination):return false
	if LinkReservations.ledger(stack).current(LinkReservations.key(stack,link["uid"])).get("token",0)!=token:return false
	if logical_boarding:
		if not body is CharacterBody2D or source==stack.current_floor or not passenger_landing_allowed(source):return false
	elif not view.passenger_inside(body,source):return false
	call_owner_token=0;npc=body;npc_token=token;npc_source=source;npc_complete=false;freeze();view.capture_actor()
	if request(destination,true):return true
	end_passenger(token);return false

func passenger_result(token: int) -> Dictionary:
	if token==0 or token!=npc_token:return {"state":"missing"}
	if not is_instance_valid(npc):return {"state":"missing"}
	return {"state":"complete" if npc_complete else "blocked" if phase=="blocked" else "travelling","height":height,"floor":last_stop,"reason":notice}

func snapshot_passenger(token: int) -> Dictionary:
	return PassengerState.capture(self) if token!=0 and token==npc_token and is_instance_valid(npc) else {}

func restore_passenger(body: Node,token: int,state: Dictionary) -> bool:
	if not PassengerState.valid(state) or state["link"]!=link["uid"] or phase!="idle" or npc_token!=0 or rider or menu.visible or view.fully_inside():return false
	if state["phase"] in ["calling","boarding"] or (call_owner_token!=0 and call_owner_token!=token):return false
	if not is_instance_valid(body) or body==actor or token==0 or LinkReservations.ledger(stack).current(LinkReservations.key(stack,link["uid"])).get("token",0)!=token:return false
	if not stops.any(func(stop: Dictionary):return stop["uid"]==state["source"]) or not stops.any(func(stop: Dictionary):return stop["uid"]==state["target"]):return false
	if absf(stop_height(state["source"])-state["source_height"])>.001 or absf(stop_height(state["target"])-state["target_height"])>.001:return false
	if state["height"]<minf(state["source_height"],state["target_height"])-.01 or state["height"]>maxf(state["source_height"],state["target_height"])+.01:return false
	call_owner_token=0;npc=body;npc_token=token;npc_source=state["source"]
	height=state["height"];elapsed=state["elapsed"];motion=state.get("motion",{}).duplicate(true);target=state["target"];last_stop=state["last_stop"];notice=state.get("notice","");queue.assign(state.get("queue",[]))
	phase="idle" if state["phase"]=="alighting" else state["phase"];npc_complete=phase=="idle";rider=not npc_complete
	view.close_all();view.set_height(height);freeze();view.capture_actor()
	if phase=="closing":view.door_progress(last_stop,1-clampf(elapsed/.25,0,1))
	elif phase=="opening":view.open_at(last_stop,clampf(elapsed/.25,0,1))
	elif phase=="idle":view.open_at(last_stop,1)
	elif phase=="arriving":view.prepare_arrival(target,true)
	# Fresh room bodies and suspended exterior collision layers need a physics
	# synchronization before a space query. Restore the visible pose now, but
	# validate it before allowing any motion on the following physics frames.
	restoration_pending=2
	return true

func restore_empty_call(token: int,state: Dictionary) -> bool:
	if not PassengerState.valid(state) or state["phase"] not in ["calling","boarding"] or state["link"]!=link["uid"] or npc_token!=0 or rider or menu.visible or phase!="idle" or view.fully_inside():return false
	if token==0 or (call_owner_token!=0 and call_owner_token!=token) or LinkReservations.ledger(stack).current(LinkReservations.key(stack,link["uid"])).get("token",0)!=token:return false
	if not stops.any(func(stop: Dictionary):return stop["uid"]==state["source"]) or not stops.any(func(stop: Dictionary):return stop["uid"]==state["last_stop"]):return false
	if absf(stop_height(state["source"])-state["source_height"])>.001 or state["height"]<stops[0]["height"]-.01 or state["height"]>stops[-1]["height"]+.01:return false
	call_owner_token=token;height=state["height"];elapsed=state["elapsed"];motion=state.get("motion",{}).duplicate(true);target=state["source"];last_stop=state["last_stop"];notice=state.get("notice","");queue.assign(state.get("queue",[]))
	phase=state["call_phase"] if state["phase"]=="calling" else "idle"
	view.close_all();view.set_height(height)
	if phase=="closing":view.door_progress(last_stop,1-clampf(elapsed/.25,0,1))
	elif phase=="opening":view.open_at(last_stop,clampf(elapsed/.25,0,1))
	elif phase=="idle":view.open_at(last_stop,1)
	elif phase=="arriving":view.prepare_arrival(target,false)
	restoration_pending=2;return true

func call_for_passenger(source: String,token: int) -> bool:
	if phase!="idle" or npc_token!=0 or rider or menu.visible or view.fully_inside() or (call_owner_token!=0 and call_owner_token!=token):return false
	if token==0 or LinkReservations.ledger(stack).current(LinkReservations.key(stack,link["uid"])).get("token",0)!=token:return false
	call_owner_token=token
	return request(source)

func retry_call(source: String,token: int) -> void:
	if token==0 or call_owner_token!=token or npc_token!=0 or phase!="blocked":return
	target=source;motion=Plan.trip(height,stop_height(source));elapsed=0;phase="moving";notice="Retrying the cleared elevator call."

func passenger_landing_allowed(uid: String) -> bool:
	# A sprite-world visit instantiates only the player's current floor. Check
	# another passenger's unseen destination against the same authored plan
	# used for activity admission, without switching the player's render scope.
	var activity_plan: GDScript=load("res://scripts/builder/resident_activity_plan.gd")
	var compiled: Dictionary=activity_plan.compile(stack.room,stack.get_parent().library)
	if not compiled["floors"].has(uid):return false
	var at: Vector2=preload("res://scripts/builder/grid_fit.gd").pixels(Vector2(link["start"][0],link["start"][1])+Vector2(0,float(link["width"])*.5+.95))
	return activity_plan.walk(compiled["floors"][uid],Vector3(at.x,at.y,0),Vector3(at.x,at.y,0),"2d")["ok"]

func retry_passenger(token: int) -> void:
	if token!=npc_token or token==0 or phase!="blocked":return
	motion=Plan.trip(height,stop_height(target));elapsed=0;phase="moving";notice="Retrying the cleared elevator route."

func end_passenger(token: int,keep_call: bool=false) -> void:
	if token==0:return
	if token==call_owner_token and npc_token==0:
		if not keep_call:call_owner_token=0;restoration_pending=0
		return
	if token!=npc_token:return
	release();rider=false;npc=null;npc_token=0;npc_source="";npc_complete=false;restoration_pending=0;call_owner_token=token if keep_call else 0

func freeze() -> void:
	var body: Node=occupant();saved_physics=body.is_physics_processing();body.set_physics_process(false);body.velocity=Vector2.ZERO if body is CharacterBody2D else Vector3.ZERO
	frozen=true
	if body is CharacterBody2D:saved_offset=body.terrain_visual_offset

func release() -> void:
	var body: Node=occupant()
	frozen=false
	if not is_instance_valid(body):return
	body.velocity=Vector2.ZERO if body is CharacterBody2D else Vector3.ZERO
	body.set_physics_process(saved_physics);view.release_actor()

func prompt() -> String:
	if menu.visible: return "Choose an elevator floor · Escape cancels"
	if phase=="blocked": return "E · Return elevator to "+stop_name(last_stop)+" · "+notice
	if phase!="idle": return "Elevator to "+stop_name(target)+" · "+("Clear the doorway" if phase=="waiting" else phase.capitalize())
	if view.fully_inside(): return "E · Choose elevator floor"+(" · "+notice if not notice.is_empty() else "")
	if stack.current_floor==last_stop: return "Elevator ready · walk into the cabin, then E"
	return "E · Call elevator to "+stop_name(stack.current_floor)

func active() -> bool:
	return (rider and npc_token==0) or menu.visible

func interact() -> void:
	if menu.visible: return
	if npc_token!=0 or call_owner_token!=0:notice="The elevator is reserved for another resident. Wait outside the cabin.";return
	if phase=="blocked":
		target=last_stop; motion=Plan.trip(height,stop_height(last_stop)); elapsed=0; phase="moving"; notice="Returning from an obstruction."; return
	if phase!="idle":
		if phase=="waiting" and rider: phase="idle"; release(); rider=false; notice="Doorway blocked. Clear it before riding."; return
		if not rider and not stack.current_floor in queue and target!=stack.current_floor: queue.append(stack.current_floor)
		return
	if view.fully_inside():
		if not reserve_player():return
		freeze(); menu.visible=true
		menu.size=Vector2(280,minf(40+(stops.size()+1)*52,clampf(get_viewport().get_visible_rect().size.y-120,150,460)))
		for button in choices.get_children():
			if button is Button: button.disabled=button.get_meta("floor_uid","")==last_stop
		for button in choices.get_children():
			if button is Button and not button.disabled: button.grab_focus(); break
	elif stack.current_floor!=last_stop: request(stack.current_floor,false)

func choose(uid: String) -> void:
	if not menu.visible or not stops.any(func(floor: Dictionary)->bool:return floor["uid"]==uid): return
	menu.visible=false
	if uid==last_stop: release(); return
	rider=true; view.capture_actor(); request(uid,true)

func cancel_menu() -> void:
	if not menu.visible: return
	menu.visible=false; release()

func request(uid: String,carrying: bool=false) -> bool:
	if not stops.any(func(floor: Dictionary)->bool:return floor["uid"]==uid): return false
	if carrying and npc_token==0 and not reserve_player():return false
	if phase!="idle":
		if not uid in queue and target!=uid: queue.append(uid)
		return true
	target=uid; rider=carrying; elapsed=0; notice=""
	if not view.doorway_clear(last_stop): phase="waiting"; return true
	start_closing(); return true

func start_closing() -> void:
	view.close_all(); phase="closing"; elapsed=0

func block(message: String) -> void:
	phase="blocked"; notice=message; view.close_all()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(actor): return
	if npc_token!=0 and not is_instance_valid(npc):end_passenger(npc_token)
	sync_occupancy()
	if (npc_token!=0 or call_owner_token!=0) and restoration_pending>0:
		restoration_pending-=1
		if restoration_pending>0:return
		if not view.can_move(height,npc_token!=0):block("The restored elevator cabin is obstructed. Clear its path to resume.");return
	if phase=="idle":
		if npc_token!=0 or call_owner_token!=0:return
		if not queue.is_empty() and not view.fully_inside() and view.doorway_clear(last_stop): request(queue.pop_front())
		return
	if phase=="waiting":
		if view.doorway_clear(last_stop): start_closing()
		return
	if phase=="closing":
		elapsed+=delta; view.door_progress(last_stop,1.0-clampf(elapsed/0.25,0,1))
		if elapsed>=0.25: motion=Plan.trip(height,stop_height(target)); phase="moving"; elapsed=0
		return
	if phase=="moving":
		var next_time: float=elapsed+delta; var next: float=Plan.sample(motion,next_time)
		if motion["duration"]>0.00001 and not view.can_move(next,rider): block("Shaft blocked. Clear objects from the elevator's path."); return
		height=next; elapsed=next_time; view.set_height(height)
		if rider: view.carry_actor()
		if elapsed>=motion["duration"]: phase="arriving"; view.prepare_arrival(target,rider)
		return
	if phase=="arriving":
		var ready: int=view.arrival_step(delta,target,rider)
		if ready<0: block("Landing blocked. Clear water, uneven terrain and objects from the elevator exit.")
		elif ready>0: last_stop=target; phase="opening"; elapsed=0
		return
	if phase=="opening":
		elapsed+=delta; view.open_at(last_stop,clampf(elapsed/0.25,0,1))
		if elapsed>=0.25:
			phase="idle"
			if rider:
				if npc_token!=0:npc_complete=true
				else:release()
				rider=false

func _process(_delta: float) -> void:
	if rider: view.present_actor()
	if status: status.visible=not menu.visible and (active() or (view.near() and phase!="idle")); status.text=prompt()+" · %+.1f m"%height

func _unhandled_key_input(event: InputEvent) -> void:
	if menu.visible and event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE: cancel_menu(); get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what!=NOTIFICATION_PREDELETE:return
	if npc_token!=0:end_passenger(npc_token)
	elif call_owner_token!=0:end_passenger(call_owner_token)
	elif frozen:release()
	release_reservation()
