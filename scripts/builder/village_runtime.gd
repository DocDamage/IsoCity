extends Node

const Plan = preload("res://scripts/builder/village_plan.gd")
const Ledger = preload("res://scripts/builder/village_ledger.gd")
const Props = Plan.Utility.Props
const Garden = preload("res://scripts/builder/garden_plan.gd")
const Cooking = preload("res://scripts/builder/cooking_plan.gd")
const Delivery = preload("res://scripts/builder/delivery_plan.gd")
const View = preload("res://scripts/builder/village_view.gd")
const TICK = .25

var exploration: Node
var ui_parent: Node
var authored_root: Callable
var interact_label: Callable
var source: Dictionary = {}
var book := Ledger.new()
var view: RefCounted
var accumulator: float = 0
var signature: int = -1
var heights: Dictionary = {}
var notice: String = ""
var selected: String = ""

func root_data() -> Dictionary:
	return authored_root.call() if authored_root.is_valid() else source

func configure(data: Dictionary) -> void:
	source = data
	var root: Dictionary = root_data()
	if not Plan.enabled(root):
		if signature != -1: reset()
		return
	var next: int = hash([root.get("objects",[]),root.get("layers",{}),root.get("terrain",{}),root.get("terrain_vertices",[]),
		root.get("water_cells",[]),Plan.Economy.settings(root)["enabled"]])
	if next == signature: return
	signature = next
	heights = Plan.Terrain.lookup(root) if exploration.dimension == "3d" else {}
	book.configure(Plan.compile(root,exploration.library),Plan.Economy.settings(root)["enabled"])
	if has_menu() and not book.sites.has(selected): close()

func pause() -> void:
	close()
	if view: view.clear()

func reset() -> void:
	pause()
	var delivery: RefCounted = exploration.driving.delivery
	if delivery.job.has("village_route"): delivery.cancel("Village production restarted.")
	book.reset()
	accumulator = 0
	signature = -1
	notice = ""

func has_menu() -> bool:
	return view != null and view.overlay.visible

func close() -> bool:
	if not has_menu(): return false
	view.close()
	selected = ""
	return true

func exterior() -> bool:
	return exploration.enabled and not exploration.entering and not exploration.interior and exploration.editor_scope.is_empty() and not exploration.photo.active

func position(point: Vector2) -> Variant:
	var world: Node = exploration.get_parent()
	if exploration.dimension == "2d": return world.to_global(point*Vector2(16,8))
	var data: Dictionary = root_data()
	var height: float = Plan.Terrain.sample(data,point,heights)["height"] if Plan.Terrain.settings(data)["enabled"] else 0.0
	return world.to_global(Vector3(point.x,height+.05,point.y))

func nearby() -> Dictionary:
	if not exterior() or not is_instance_valid(exploration.player) or not exploration.driving.active.is_empty(): return {}
	var player: Node = exploration.player
	var best: Dictionary = {}
	for uid in book.sites:
		var site: Dictionary = book.sites[uid]
		var node: Node = exploration.instances.get(uid)
		if not is_instance_valid(node) or not node.is_visible_in_tree(): continue
		for point in site["points"]:
			var goal: Variant = position(point)
			var gap: Variant = goal-player.global_position
			var range: float = Vector2(gap.x/16,gap.y/8).length() if exploration.dimension == "2d" else gap.length()
			if range > 2.05 or gap.length() >= best.get("distance",INF): continue
			if range < .015 or Props.reachable(exploration,node,goal):
				best = {"uid":uid,"distance":gap.length()}
	return best

func prompt(uid: String) -> String:
	var site: Dictionary = book.sites.get(uid,{})
	if site.is_empty(): return ""
	var key: String = interact_label.call() if interact_label.is_valid() else "E"
	return key+" · "+site["name"]+" supplies · "+book.states.get(uid,"Ready to preview.")

func open(uid: String) -> void:
	if not book.sites.has(uid): return
	if view == null: view = View.new(self)
	selected = uid
	notice = ""
	view.open()

func stock_text(uid: String) -> String:
	var labels: PackedStringArray = []
	for good in Plan.goods():
		var count: int = book.stock(uid,good)
		if count > 0: labels.append("%s %d" % [Plan.title(good),count])
	return " · ".join(labels) if not labels.is_empty() else "Storage empty"

func status(uid: String) -> String:
	var site: Dictionary = book.sites.get(uid,{})
	if site.is_empty(): return ""
	if not site["reason"].is_empty(): return site["reason"]
	var labels: PackedStringArray = [book.states.get(uid,"Waiting for Walk preview.")]
	var job: Dictionary = book.outbound(uid)
	var route: Dictionary = site["link"]
	if not job.is_empty():
		labels.append("On the delivery truck." if job["transport"] == "truck" else "Porter transfer · %d%%" %
			int(100*job["distance"]/maxf(.001,job["length"])))
	elif not site["profile"]["ships"].is_empty():
		if not route["reason"].is_empty(): labels.append(route["reason"])
		elif route["transport"] == "truck":
			labels.append("Load at the village pickup pad." if truck_offer(uid).has("destination") else "Enable both local delivery pads.")
		elif book.space(route["target"],book.account["stock"]) < Plan.QUANTITY: labels.append("Destination storage is full.")
		else: labels.append("Shipping to "+book.sites[route["target"]]["name"]+".")
	return "\n".join(labels)

func wallet() -> String:
	return "Village preview · %d credits" % book.account.get("cash",0) if book.wallet_enabled else "Creative preview · finite stock"

func garden_enabled() -> bool:
	return Garden.settings(root_data()) and not exploration.garden.account.is_empty()

func garden_import(uid: String) -> Dictionary:
	var kit: Node = exploration.garden
	if not garden_enabled() or kit.account["stock"].get("produce/tomato",0) < 1: return book.failure("Harvest tomatoes in the garden first.")
	var id: String = book.ticket("garden")
	var staged: Dictionary = book.exchange(id,{Plan.key(uid,"tomato"):1},0,{"kind":"garden","site":uid})
	if not staged["ok"]: return book.failure(book.describe_error(staged))
	var debited: Dictionary = Garden.exchange(kit.account,id,{"produce/tomato":-1},0,{"kind":"village","site":uid})
	if not debited["ok"] or debited["replayed"]: return book.failure("The garden stock changed.")
	kit.account = debited["account"]
	book.account = staged["account"]
	return staged["receipt"]

func kitchen_supply(uid: String) -> Dictionary:
	if book.available(uid,"flour") < 1: return book.failure("Wait for an unreserved unit of flour.")
	var id: String = book.ticket("kitchen")
	var staged: Dictionary = book.exchange(id,{Plan.key(uid,"flour"):-1},0,{"kind":"kitchen","site":uid})
	if not staged["ok"]: return book.failure(book.describe_error(staged))
	var accepted: Dictionary = exploration.cooking.receive_village_flour(uid,id)
	if not accepted["ok"]: return accepted
	book.account = staged["account"]
	return staged["receipt"]

func command(action: String) -> void:
	var uid: String = selected
	var site: Dictionary = book.sites.get(uid,{})
	if site.is_empty() or not exterior() or nearby().get("uid","") != uid or not site["reason"].is_empty():
		notice = "Return to a clear facility approach."
		return
	var role: String = site["profile"]["role"]
	var result: Dictionary = book.failure("This facility cannot do that.")
	var success: String = ""
	match action:
		"sell":
			if role == "market":
				result = book.sell(uid,book.order(uid).get("id",""))
				success = book.latest
		"forge":
			if role == "smith":
				result = book.supply(uid,{"iron":2,"fuel":2},6)
				success = "Received two bar iron and two charcoal."
		"tomatoes":
			if role == "bakery" and site["config"]["recipe"] == "tomato_loaf":
				result = garden_import(uid) if garden_enabled() else book.supply(uid,{"tomato":1},3)
				success = "Tomatoes added to bakery stock."
		"kitchen":
			if role == "bakery":
				result = kitchen_supply(uid)
				success = "One flour sent to the ground-floor kitchen."
	notice = success if result["ok"] else result["reason"]
	if view: view.refresh()

func truck_offer(uid: String) -> Dictionary:
	var from: Dictionary = book.sites.get(uid,{})
	if from.is_empty(): return {}
	var link: Dictionary = from["link"]
	if not link["reason"].is_empty() or link["transport"] != "truck": return {}
	var target: Dictionary = book.sites[link["target"]]
	if not Delivery.enabled(from["item"],"delivery_site") or not Delivery.enabled(target["item"],"delivery_site"): return {}
	if Delivery.enabled(from["item"],"delivery_contract"): return {}
	return {"enabled":true,"destination":link["target"],"goods":"village_"+link["good"],"quantity":Plan.QUANTITY,
		"reward":0,"deadline":120,"village_route":book.link_signature(from,target)}

func truck_offers() -> Dictionary:
	var result: Dictionary = {}
	for uid in book.sites:
		var offer: Dictionary = truck_offer(uid)
		if not offer.is_empty(): result[uid] = offer
	return result

func step(delta: float) -> void:
	if not Plan.enabled(root_data()) or not exploration.enabled or exploration.photo.active or not is_finite(delta) or delta <= 0:
		if not exploration.enabled or exploration.photo.active: pause()
		return
	accumulator += minf(delta,.5)
	while accumulator >= TICK:
		accumulator -= TICK
		book.tick(TICK,exploration.garden.season())
	if not exterior():
		close()
		if view: view.clear()
	elif not book.sites.is_empty():
		if view == null: view = View.new(self)
		view.render()
		if has_menu(): view.refresh()

func _physics_process(delta: float) -> void:
	step(delta)
