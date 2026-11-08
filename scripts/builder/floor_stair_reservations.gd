extends RefCounted
const Shared=preload("res://scripts/builder/floor_link_reservations.gd")
var stack_ref: WeakRef
var leases: Dictionary={}
func _init(stack: Node) -> void:stack_ref=weakref(stack)

func inside(link: Dictionary,point: Vector3,margin: float=.3) -> bool:
	var stack: Node=stack_ref.get_ref();var a:=Vector2(link["start"][0],link["start"][1]);var b:=Vector2(link["end"][0],link["end"][1]);var direction: Vector2=(b-a).normalized();var at:=Vector2(point.x,point.z);var along: float=(at-a).dot(direction)
	if along < -margin or along>a.distance_to(b)+margin or absf((at-a).dot(direction.orthogonal()))>float(link["width"])*.5+margin:return false
	var progress: float=clampf(along/maxf(.001,a.distance_to(b)),0,1);var height: float=lerpf(stack.heights[link["lower"]],stack.heights[link["upper"]],progress)
	return absf(point.y-height)<.65

func release(uid: String) -> void:
	if not leases.has(uid):return
	var lease: Dictionary=leases[uid];lease["pool"].release(lease["key"],lease["token"]);leases.erase(uid)
func clear() -> void:
	for uid in leases.keys():release(uid)
func acquire(link: Dictionary) -> bool:
	if leases.has(link["uid"]):return true
	var stack: Node=stack_ref.get_ref();var pool: RefCounted=Shared.ledger(stack);var key: String=Shared.key(stack,link["uid"]);var token: int=pool.acquire(key,stack.actor)
	if token==0:return false
	leases[link["uid"]]={"pool":pool,"key":key,"token":token};return true
func synchronize() -> void:
	var stack: Node=stack_ref.get_ref()
	if not is_instance_valid(stack) or not is_instance_valid(stack.actor):clear();return
	var point: Vector3=stack.get_parent().to_local(stack.actor.global_position)
	for link in stack.room.get("floor_links",[]):
		if link["kind"]!="stairs":continue
		if inside(link,point):acquire(link)
		else:release(link["uid"])
func filter_motion(from: Vector3,motion: Vector3) -> Vector3:
	var stack: Node=stack_ref.get_ref();var point: Vector3=stack.get_parent().to_local(from);var destination: Vector3=stack.get_parent().to_local(from+motion)
	for link in stack.room.get("floor_links",[]):
		if link["kind"]!="stairs" or not inside(link,destination):continue
		if acquire(link):continue
		# A body restored inside an occupied flight can still retreat to its
		# nearest landing. Denial must never trap it in the shared corridor.
		if inside(link,point):
			var a:=Vector2(link["start"][0],link["start"][1]);var b:=Vector2(link["end"][0],link["end"][1]);var at:=Vector2(point.x,point.z);var next:=Vector2(destination.x,destination.z);var exit: Vector2=a if at.distance_to(a)<at.distance_to(b) else b
			if next.distance_to(exit)<at.distance_to(exit):continue
		stack.actor.set_meta("terrain_blocked","Stairs occupied. Wait for the resident to reach the landing.");return Vector3.ZERO
	return motion
