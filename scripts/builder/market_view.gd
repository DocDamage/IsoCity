extends Node

const Plan=preload("res://scripts/builder/market_plan.gd")
const Instance=preload("res://scripts/builder/asset_instance.gd")
const Geometry=preload("res://scripts/builder/walk_geometry.gd")
const TINT=Color("eacf77")
var library: RefCounted
var mode: String="2d"
var root: Node
var displays: Dictionary={}

func position(point: Vector2,height: float) -> Variant:
	var values: Array=Plan.Traffic.world(point,mode,height)
	if mode=="2d": return Vector2(values[0],values[1]-height*8)
	return Vector3(values[0],height,values[2])

func sync(vendors: Dictionary,night: bool) -> void:
	for id in displays.keys():
		if not vendors.has(id) or displays[id]["record"]!=vendors[id]["record"] or displays[id]["product"]!=vendors[id]["goods"]:
			displays[id]["root"].free()
			displays.erase(id)
	if vendors.is_empty():
		if is_instance_valid(root): root.free()
		root=null
		return
	if not is_instance_valid(root):
		root=Node2D.new() if mode=="2d" else Node3D.new()
		root.name="MarketStalls"
		if root is Node2D: root.y_sort_enabled=true
		get_parent().add_child(root)
	for id in vendors:
		if not displays.has(id): build(id,vendors[id],night)

func build(id: String,vendor: Dictionary,night: bool) -> void:
	var group: Node=Node2D.new() if mode=="2d" else Node3D.new()
	root.add_child(group)
	if group is Node2D: group.y_sort_enabled=true
	var record: Dictionary=vendor["record"]
	var stall: Node=Instance.make(library,record["asset"],mode)
	group.add_child(stall)
	var scale_value: float=record["scale"]
	stall.scale=Vector2.ONE*scale_value if mode=="2d" else Vector3.ONE*scale_value
	stall.position=position(vendor["center"],vendor.get("height",0))
	Instance.pose(stall,record,night)
	if mode=="2d": Geometry.prepare_2d(stall,record["asset"],library)
	else: Geometry.prepare(stall,record["asset"],library)
	var product: Node=Instance.make(library,vendor["goods"],mode)
	if "collidable" in product: product.collidable=false
	group.add_child(product)
	Instance.orient(product,library.directions(vendor["goods"])[0],night)
	var direction: Vector2=vendor["center"].direction_to(vendor["point"])
	var side:=Vector2(direction.y,-direction.x)
	var goods_at: Vector2=vendor["center"].lerp(vendor["point"],.78)+side*.85
	product.position=position(goods_at,vendor.get("height",0)+.2)
	product.scale=Vector2.ONE*.58 if mode=="2d" else Vector3.ONE*.7
	if product is Node2D: product.z_index=4
	for body in [product]+product.find_children("*","CollisionObject2D" if mode=="2d" else "CollisionObject3D",true,false):
		if body is CollisionObject2D or body is CollisionObject3D:
			body.collision_layer=0
			body.collision_mask=0
	var markers: Node=Node2D.new() if mode=="2d" else Node3D.new()
	group.add_child(markers)
	marker(markers,vendor["point"],vendor.get("height",0),true)
	for point in vendor["queue"]: marker(markers,point,vendor.get("height",0),false)
	displays[id]={"root":group,"stall":stall,"record":record.duplicate(true),"goods":product,"product":vendor["goods"],"markers":markers}

func marker(parent: Node,point: Vector2,height: float,checkout: bool) -> void:
	var radius: float=.38 if checkout else .24
	var color: Color=TINT if checkout else Color("67acb8")
	if mode=="2d":
		var shape:=Polygon2D.new()
		var points:=PackedVector2Array()
		for index in 12: points.append(position(point+Vector2.from_angle(index*TAU/12)*radius,height))
		shape.polygon=points
		shape.color=color
		shape.z_index=10
		parent.add_child(shape)
	else:
		var cylinder:=CylinderMesh.new()
		cylinder.height=.02
		cylinder.top_radius=radius
		cylinder.bottom_radius=radius
		cylinder.radial_segments=12
		var material:=StandardMaterial3D.new()
		material.albedo_color=color
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		var body:=MeshInstance3D.new()
		body.mesh=cylinder
		body.material_override=material
		body.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.position=position(point,height+.14)
		parent.add_child(body)

func stock(runtime: RefCounted) -> void:
	for id in displays:
		var visible: bool=runtime.count(id)!=0
		if displays[id]["goods"].visible!=visible: displays[id]["goods"].visible=visible

func marker_visibility(value: bool) -> void:
	for display in displays.values(): display["markers"].visible=value

func _notification(what: int) -> void:
	if what==NOTIFICATION_PREDELETE and is_instance_valid(root) and not root.is_queued_for_deletion(): root.queue_free()
