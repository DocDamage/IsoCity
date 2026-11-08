extends Node

const RenderingBudget = preload("res://scripts/builder/rendering_budget.gd")
const SOURCE_PREFIX = "variant:"

@export_enum("2d", "3d") var dimension: String = "2d"
@export var studio_data: Dictionary = {}
# Exported scenes created before I15 use studio_data directly. Base64 prevents
# metadata res:// strings from being mistaken for PackedScene dependencies.
@export_storage var studio_source_base64: String = ""
@export var project_palette: Dictionary = {}
var exploration: Node
var utilities: Node
var power: Node
var walk_prompt: Label
var walking: bool = true
var yaw: float = 45
var pitch: float = 40
var zoom: float = 35
var target := Vector3.ZERO
var dragging: bool = false
var camera: Node
var player: Node
var citizens: Node
var traffic: Node
var businesses: Node
var services: Node
var economy: Node
var scenario: Node
var zoning: Node
var transit: Node
var terrain: Node
var terrain_presentation: Node
var terrain_traversal: Node
var live_data: Dictionary={}
var city_instances: Dictionary={}
var projection_pool: Node
var presentation: Node
var ambience: Node
var ambience_context: RefCounted
var ambience_hint: Label
var weather: Node
var photo_tools: RefCounted
var photo_storage_enabled: bool=true

func set_room_door(host_uid: String,floor_uid: String,uid: String,opened: bool) -> void:
	for host in live_data.get("objects",[]):
		if host["uid"]!=host_uid: continue
		for item in preload("res://scripts/builder/floor_plan.gd").room(host.get("interior",{}),floor_uid).get("objects",[]):
			if item["uid"]!=uid: continue
			item["open"]=opened; exploration.apply_room(floor_uid); return

func _ready() -> void:
	if studio_source_base64.begins_with(SOURCE_PREFIX):
		var authored: Variant = Marshalls.base64_to_variant(studio_source_base64.trim_prefix(SOURCE_PREFIX))
		if authored is Dictionary: studio_data = authored
	elif not studio_source_base64.is_empty():
		var parser := JSON.new()
		if parser.parse(Marshalls.base64_to_raw(studio_source_base64).get_string_from_utf8()) == OK and parser.data is Dictionary:
			studio_data = parser.data
	live_data=studio_data.duplicate(true) if preload("res://scripts/builder/zone_plan.gd").settings(studio_data)["enabled"] else studio_data
	camera = get_node("Camera2D" if dimension == "2d" else "Camera3D")
	player = get_node("Player")
	if dimension == "2d": projection_pool = RenderingBudget.projection_pool(self)
	presentation = preload("res://scripts/builder/asset_presentation.gd").new()
	add_child(presentation)
	if dimension=="3d" and not live_data.is_empty():
		terrain=preload("res://scripts/builder/terrain_surface_3d.gd").new(); terrain.name="Terrain"; add_child(terrain); terrain.configure(live_data)
		var sculpted: bool=preload("res://scripts/builder/terrain_plan.gd").settings(live_data)["enabled"]
		if has_node("Foundation"): get_node("Foundation").visible=not sculpted; get_node("Foundation").collision_layer=0 if sculpted else 2
	elif not live_data.is_empty():
		terrain=preload("res://scripts/builder/terrain_surface_2d.gd").new(); terrain.name="Terrain"; terrain.z_index=-5; add_child(terrain)
		var records: Dictionary={}
		var sculpted: bool=preload("res://scripts/builder/terrain_plan.gd").settings(live_data)["enabled"]
		if sculpted:
			for record in preload("res://scripts/builder/roads.gd").tiles(live_data): records[Vector2i(record["cell"][0],record["cell"][1])]=record
		terrain.configure(live_data,preload("res://scripts/builder/terrain_tiles_2d.gd").descriptions(get_node("Ground"),records) if sculpted else {})
		if sculpted:
			var outside:=TileMapLayer.new(); outside.name="TerrainOutside"; add_child(outside); preload("res://scripts/builder/terrain_tiles_2d.gd").update_outside(outside,get_node("Ground"),preload("res://scripts/builder/terrain_plan.gd").bounds(live_data)); outside.visible=preload("res://scripts/builder/layers.gd").shown(live_data,"Ground")
		get_node("Ground").visible=not sculpted
	var layer := CanvasLayer.new(); layer.layer=10
	add_child(layer)
	var label := Label.new()
	label.position = Vector2(20, 16)
	label.text = "WASD / arrows: move     Tab: walk / free camera     Mouse wheel: zoom     Right-drag: orbit (3D)     Space: jump (3D)     X: recover position"
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(label)
	walk_prompt = Label.new()
	walk_prompt.position = Vector2(20, 48)
	walk_prompt.add_theme_color_override("font_shadow_color", Color.BLACK)
	layer.add_child(walk_prompt)
	if not live_data.is_empty():
		exploration = preload("res://scripts/builder/exploration.gd").new()
		exploration.dimension = dimension
		exploration.library = preload("res://scripts/builder/asset_library.gd").new()
		exploration.library.set_project_palette(project_palette)
		preload("res://scripts/builder/repair_assets.gd").register_used(live_data,exploration.library)
		exploration.player = player
		add_child(exploration)
		var instances: Dictionary = city_instances
		for node in get_node("Objects").get_children():
			if node.has_meta("builder_uid"): instances[node.get_meta("builder_uid")] = node
		for item in live_data["objects"]:
			# Inherited IsoObject grid/elevation setters can run after the saved
			# Node2D position while a PackedScene is instantiated. Restore the
			# authoritative free placement once every child has entered the tree.
			if instances.has(item["uid"]):
				var node: Node = instances[item["uid"]]
				preload("res://scripts/builder/asset_instance.gd").pose(node, item, live_data.get("night", false))
				if dimension == "2d":
					node.position = Vector2(item["position"][0], item["position"][1] - item["position"][2] * 8)
					node.scale = Vector2.ONE * float(item["scale"])
				else:
					node.position = Vector3(item["position"][0],item["position"][1],item["position"][2])
					node.scale = Vector3.ONE * float(item["scale"])
			if dimension == "2d" and instances.has(item["uid"]): preload("res://scripts/builder/walk_geometry.gd").prepare_2d(instances[item["uid"]], item["asset"], exploration.library)
			if instances.has(item["uid"]): preload("res://scripts/builder/part_colors.gd").apply(instances[item["uid"]], item)
			if instances.has(item["uid"]): RenderingBudget.prepare_projection(instances[item["uid"]],exploration.library.assets[item["asset"]],projection_pool)
			if dimension == "3d" and instances.has(item["uid"]): preload("res://scripts/builder/walk_geometry.gd").prepare(instances[item["uid"]], item["asset"], exploration.library)
			if instances.has(item["uid"]):
				var node: Node=instances[item["uid"]]
				node.visible=preload("res://scripts/builder/layers.gd").shown(live_data,preload("res://scripts/builder/layers.gd").layer(item,exploration.library)) and item.get("visible",true)
				preload("res://scripts/builder/layers.gd").collision_visibility(node,node.visible)
		exploration.update(live_data, instances)
		presentation.configure(live_data,instances,exploration.library)
		var utility_plan=preload("res://scripts/builder/utility_plan.gd")
		if utility_plan.authored(live_data,"water"):
			utilities=network("water")
			exploration.garden.water_network=utilities
		if utility_plan.authored(live_data,"power"):
			power=network("power")
			exploration.power=power
		citizens=preload("res://scripts/builder/citizen_runtime.gd").new()
		add_child(citizens)
		citizens.configure(live_data,exploration.library,instances,get_node("Objects"),false)
		traffic=preload("res://scripts/builder/traffic_runtime.gd").new()
		add_child(traffic)
		traffic.driving=exploration.driving; exploration.driving.traffic=traffic
		citizens.street_traffic=traffic
		traffic.configure(live_data,exploration.library,instances,get_node("Objects"),false)
		businesses=preload("res://scripts/builder/business_runtime.gd").new()
		add_child(businesses)
		businesses.configure(live_data,exploration.library,instances,exploration,citizens,false)
		citizens.businesses=businesses
		exploration.driving.business_clock=businesses
		services=preload("res://scripts/builder/service_runtime.gd").new()
		add_child(services)
		traffic.services=services
		services.configure(live_data,exploration.library,instances,get_node("Objects"),traffic,false,exploration)
		exploration.emergency.services = services
		transit=preload("res://scripts/builder/transit_runtime.gd").new(); transit.show_hud=true; add_child(transit)
		transit.configure(live_data,exploration.library,instances,get_node("Objects"),traffic,services,false); traffic.transit=transit; citizens.transit=transit
		economy=preload("res://scripts/builder/economy_runtime.gd").new()
		add_child(economy); economy.configure(live_data,exploration.library,preload("res://scripts/builder/zone_plan.gd").settings(live_data)["enabled"])
		scenario=preload("res://scripts/builder/scenario_runtime.gd").new()
		scenario.construction=exploration.driving.construction
		scenario.emergency=exploration.emergency
		add_child(scenario); scenario.show_hud=true; scenario.configure(live_data,exploration.library,instances,false)
		zoning=preload("res://scripts/builder/zone_runtime.gd").new()
		add_child(zoning); zoning.show_hud=true; zoning.configure(live_data,exploration.library,get_node("Objects")); zoning.advance_requested.connect(grow_lot)
		if dimension=="2d":
			terrain_presentation=preload("res://scripts/builder/terrain_presentation_2d.gd").new(); add_child(terrain_presentation); terrain_presentation.configure(live_data,get_node("Objects"),instances,exploration); terrain_presentation.bind_actor(player)
		terrain_traversal=preload("res://scripts/builder/terrain_traversal.gd").new(); add_child(terrain_traversal); terrain_traversal.configure(live_data,get_node("Objects"),player,exploration)
		exploration.interior_requested.connect(func(_uid: String):
			if preload("res://scripts/builder/zone_plan.gd").settings(live_data)["enabled"]: call_deferred("refresh_live_forecast")
		)
		exploration.interior_door_changed.connect(func(host_uid: String, uid: String, opened: bool):
			set_room_door(host_uid,"ground",uid,opened)
		)
		exploration.interior_floor_door_changed.connect(set_room_door)
		exploration.door_changed.connect(func(uid: String, opened: bool):
			for item in live_data["objects"]:
				if item["uid"] == uid: item["open"] = opened
			exploration.update(live_data, instances)
		)
		var spawn: Array = live_data.get("spawn", [0,60,0] if dimension == "2d" else [0,.2,9])
		player.teleport_to(Vector2(spawn[0],spawn[1]) if dimension == "2d" else Vector3(spawn[0],spawn[1],spawn[2]))
	_set_mode()
	ambience=preload("res://scripts/builder/ambience_runtime.gd").new(); add_child(ambience); ambience_context=preload("res://scripts/builder/ambience_context.gd").new()
	weather=preload("res://scripts/builder/weather_runtime.gd").new(); add_child(weather)
	if exploration: exploration.garden.weather_runtime=weather
	if exploration:
		exploration.camping.audio_allowed=func()->bool:
			return not ambience.muted and preload("res://scripts/builder/ambience_plan.gd").settings(live_data)["enabled"]
	ambience_hint=Label.new(); ambience_hint.position=Vector2(20,76); ambience_hint.add_theme_color_override("font_shadow_color",Color.BLACK); layer.add_child(ambience_hint)
	if exploration:
		photo_tools=preload("res://scripts/builder/photo_play_tools.gd").new(self); label.text+="     P: photo mode"

func refresh_live_forecast() -> void:
	if economy:
		economy.rates=preload("res://scripts/builder/economy_plan.gd").forecast(live_data,exploration.library); economy.update_ui()

func development_people() -> Array[Vector2]:
	var result: Array[Vector2]=[]
	if not zoning or live_data.get("zones",[]).is_empty(): return result
	var actors: Array=[]
	if walking: actors.append(player)
	for resident in citizens.residents:
		if is_instance_valid(resident["actor"]) and resident["actor"].visible: actors.append(resident["actor"])
	for crew in services.crews.values():
		if is_instance_valid(crew["worker"]) and crew["worker"].visible: actors.append(crew["worker"])
	if transit: actors.append_array(transit.pedestrian_actors())
	for actor in actors:
		var point: Vector2=preload("res://scripts/builder/traffic_plan.gd").metric([actor.position.x,actor.position.y,0] if dimension=="2d" else [actor.position.x,actor.position.y,actor.position.z],dimension)
		var terrain_plan=preload("res://scripts/builder/terrain_plan.gd"); var level: float=terrain_plan.sample(live_data,point,terrain_traversal.heights)["height"] if terrain_plan.settings(live_data)["enabled"] else 0.0
		if dimension=="3d" and absf(actor.position.y-level)>.5: continue
		result.append(point)
	result.append_array(preload("res://scripts/builder/zone_plan.gd").vehicle_points(traffic.vehicles))
	if transit: result.append_array(preload("res://scripts/builder/zone_plan.gd").vehicle_points(transit.vehicle_states()))
	result.append_array(preload("res://scripts/builder/zone_plan.gd").vehicle_points(services.crews.values().map(func(crew: Dictionary):return crew["vehicle"])))
	return result

func grow_lot(uid: String) -> void:
	if exploration.interior!=null: return
	var result: Dictionary=preload("res://scripts/builder/zone_plan.gd").advance(live_data,uid,exploration.library,"",development_people())
	if not result["ok"] or not result.has("data"): zoning.states[uid]=result; return
	live_data.clear(); live_data.merge(result["data"],true)
	for item in live_data["objects"]:
		if city_instances.has(item["uid"]): continue
		var node: Node=preload("res://scripts/builder/asset_instance.gd").make(exploration.library,item["asset"],dimension,true,projection_pool)
		get_node("Objects").add_child(node); node.set_meta("builder_uid",item["uid"]); city_instances[item["uid"]]=node
		preload("res://scripts/builder/asset_instance.gd").pose(node,item,live_data.get("night",false))
		if dimension=="2d":
			node.position=Vector2(item["position"][0],item["position"][1]-item["position"][2]*8); node.scale=Vector2.ONE*item["scale"]
			preload("res://scripts/builder/walk_geometry.gd").prepare_2d(node,item["asset"],exploration.library)
		else:
			node.position=Vector3(item["position"][0],item["position"][1],item["position"][2]); node.scale=Vector3.ONE*item["scale"]
			preload("res://scripts/builder/walk_geometry.gd").prepare(node,item["asset"],exploration.library)
		preload("res://scripts/builder/part_colors.gd").apply(node,item)
	exploration.update(live_data,city_instances)
	presentation.configure(live_data,city_instances,exploration.library)
	if utilities: utilities.configure(live_data,exploration.library)
	if power: power.configure(live_data,exploration.library)
	citizens.configure(live_data,exploration.library,city_instances,get_node("Objects"),false)
	traffic.configure(live_data,exploration.library,city_instances,get_node("Objects"),false)
	businesses.configure(live_data,exploration.library,city_instances,exploration,citizens,false)
	services.configure(live_data,exploration.library,city_instances,get_node("Objects"),traffic,false,exploration)
	transit.configure(live_data,exploration.library,city_instances,get_node("Objects"),traffic,services,false)
	economy.rates=preload("res://scripts/builder/economy_plan.gd").forecast(live_data,exploration.library); economy.update_ui()
	scenario.construction=exploration.driving.construction
	scenario.configure(live_data,exploration.library,city_instances,false)
	zoning.configure(live_data,exploration.library,get_node("Objects"))
	if terrain_presentation: terrain_presentation.configure(live_data,get_node("Objects"),city_instances,exploration)
	if terrain_traversal: terrain_traversal.configure(live_data,get_node("Objects"),player,exploration)

func _set_mode() -> void:
	if exploration: exploration.set_enabled(walking)
	var allowed: bool=walking and (not terrain_traversal or terrain_traversal.ensure_start())
	if dimension == "2d":
		player.is_player_controlled = allowed
	else:
		player.active = allowed
	player.visible = walking
	player.collision_layer = 1 if walking else 0

func network(kind: String) -> Node:
	var runtime=preload("res://scripts/builder/utility_runtime.gd").new()
	runtime.kind=kind
	runtime.name=kind.capitalize()+"Network"
	runtime.show_hud=true
	add_child(runtime)
	runtime.configure(live_data,exploration.library)
	return runtime

func _process(delta: float) -> void:
	if photo_tools: photo_tools.tick(delta)
	if terrain_traversal and walking:
		var allowed: bool=terrain_traversal.walk_allowed() and exploration.walk_allowed()
		if dimension=="2d": player.is_player_controlled=allowed
		else: player.active=allowed
	if transit:
		transit.active=not exploration or exploration.interior==null
		if is_instance_valid(transit.helper.container): transit.helper.container.visible=transit.active
	if zoning:
		zoning.active=exploration.interior==null
		if is_instance_valid(zoning.container): zoning.container.visible=zoning.active
		zoning.people=development_people()
	if traffic:
		traffic.active=not exploration or exploration.interior==null
		if is_instance_valid(traffic.container): traffic.container.visible=traffic.active
		traffic.pedestrians.assign([player])
		for resident in citizens.residents:
			if is_instance_valid(resident["actor"]): traffic.pedestrians.append(resident["actor"])
	if citizens:
		citizens.active=not exploration or exploration.interior==null or citizens.interior_activities_enabled()
		if is_instance_valid(citizens.container): citizens.container.visible=not exploration or exploration.interior==null
	if services:
		services.active=not exploration or exploration.interior==null
		if is_instance_valid(services.helper.container): services.helper.container.visible=services.active
		services.refresh_links()
	if exploration and walk_prompt:
		walk_prompt.text=exploration.prompt() if walking else ""
		if walking and utilities and utilities.graph["enabled"] and not exploration.photo.active:
			var uid: String=exploration.interior_uid if exploration.interior else exploration.nearby.get("item",{}).get("uid","")
			var node: Dictionary=utilities.graph["nodes"].get(uid,{})
			if node.get("role")=="consumer": walk_prompt.text+="\nWater · "+utilities.describe(uid)
		if walking and power and power.graph["enabled"] and not exploration.photo.active:
			var uid: String=exploration.interior_uid if exploration.interior else exploration.nearby.get("item",{}).get("uid","")
			var node: Dictionary=power.graph["nodes"].get(uid,{})
			if node.get("role")=="consumer": walk_prompt.text+="\nPower · "+power.describe(uid)
	var movement := Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if not exploration or (not exploration.photo.active and not exploration.arcade.active()):
		if dimension == "2d":
			if walking:
				camera.position = camera.position.lerp(player.position+Vector2(0,-(float(player.get_meta("terrain_height",0))+float(player.get_meta("floor_travel_height",0)))*8), minf(delta * 10, 1))
			else:
				camera.position += movement * 250 * delta / camera.zoom.x
		else:
			if not walking:
				var direction: Vector3 = camera.basis.x * movement.x + camera.basis.z * movement.y
				direction.y = 0
				target += direction * delta * 20
			var focus: Vector3 = player.position + Vector3.UP if walking else target
			camera.projection = Camera3D.PROJECTION_PERSPECTIVE if walking else Camera3D.PROJECTION_ORTHOGONAL
			camera.size = zoom
			camera.position = focus + Basis.from_euler(Vector3(deg_to_rad(-pitch), deg_to_rad(yaw), 0)) * Vector3(0, 0, 9 if walking else zoom)
			camera.look_at(focus)
	if weather:
		weather.step(delta,live_data,city_instances,not exploration or exploration.interior==null,Vector3(1,0,-1).normalized() if dimension=="2d" else camera.global_basis.x)
	if ambience and exploration:
		var vehicles: Array=[]; vehicles.append_array(traffic.vehicles); vehicles.append_array(services.vehicle_states()); vehicles.append_array(transit.vehicle_states())
		vehicles.append_array(exploration.driving.vehicle_states())
		var context: Dictionary=ambience_context.collect(live_data,self,walking,exploration.library,vehicles,businesses.hour,{},"",0,citizens,businesses)
		ambience.step(delta,context["sources"],context["listener"],context["config"],context["right"])
		ambience_hint.text=("M · Unmute ambience" if ambience.muted else "M · Mute ambience") if preload("res://scripts/builder/ambience_plan.gd").settings(live_data)["enabled"] else "City ambience is disabled."
		ambience_hint.position.y=maxf(76,walk_prompt.position.y+walk_prompt.get_combined_minimum_size().y+4)
		var panel_top: float=ambience_hint.position.y+ambience_hint.get_combined_minimum_size().y+10
		var viewport_size: Vector2=get_viewport().get_visible_rect().size
		businesses.panel_area=Rect2(Vector2(10,panel_top),(viewport_size-Vector2(20,panel_top+10)).max(Vector2.ONE))

func _input(event: InputEvent) -> void:
	if not is_instance_valid(exploration): return
	if ambience and event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_M and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		ambience.muted = not ambience.muted
		get_viewport().set_input_as_handled()
		return
	if exploration.village.has_menu():
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			exploration.village.close()
			get_viewport().set_input_as_handled()
		return
	if exploration.pet.has_menu():
		if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
			exploration.pet.close()
			get_viewport().set_input_as_handled()
		return
	if not exploration.arcade.active(): return
	var action: String=exploration.arcade.Plan.default_action(event) if event is InputEventKey else ""
	if exploration.arcade.input(event,action): get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(exploration) and exploration.arcade.active(): return
	if photo_tools and photo_tools.handle_input(event): return
	if exploration and exploration.runtime_modal(): return
	if exploration and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if not exploration.laundry.counter.is_empty(): exploration.laundry.close_counter(); return
		if not exploration.fitness.menu.is_empty(): exploration.fitness.close_view(); return
		if exploration.camping.cancel_player(): return
	if exploration and walking and event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_B and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		if event.shift_pressed: exploration.driving.cancel_vehicle_service()
		else: exploration.driving.request_vehicle_service()
		return
	if exploration and walking and event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_H and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		if event.shift_pressed: exploration.driving.cancel_delivery()
		else: exploration.driving.request_delivery()
		return
	if services and walking and event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_V and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		if event.shift_pressed: services.cycle_request()
		else: services.request_nearby()
		return
	if businesses and walking and event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_G and not event.ctrl_pressed and not event.meta_pressed:
		if not event.alt_pressed and not event.shift_pressed and exploration.cycling.guide(): return
		if event.alt_pressed and not event.shift_pressed: businesses.cancel_activity()
		elif not event.alt_pressed: businesses.primary_action(1 if event.shift_pressed else 0)
		return
	if exploration and walking and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		exploration.interact()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		walking = not walking
		_set_mode()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var factor: float = 1.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1
			if dimension == "2d":
				camera.zoom = (camera.zoom * factor).clamp(Vector2.ONE * 0.4, Vector2.ONE * 6)
			else:
				zoom = clampf(zoom / factor, 5, 100)
	elif event is InputEventMouseMotion and dragging and dimension == "3d":
		yaw -= event.relative.x * 0.4
		pitch = clampf(pitch + event.relative.y * 0.3, 15, 80)
