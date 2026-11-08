extends RefCounted

static func bounds(data: Dictionary) -> Rect2:
	var area:=Rect2(-80,-80,160,160)
	for road in data.get("roads",[]):
		var point:=Vector2(road["cell"][0],road["cell"][1])*8
		area=area.merge(Rect2(point-Vector2.ONE*4,Vector2.ONE*8))
	return area

static func configure(body: StaticBody3D,data: Dictionary) -> void:
	var area: Rect2=bounds(data)
	if body.get_meta("city_bounds",Rect2())==area: return
	body.set_meta("city_bounds",area); body.position=Vector3(area.get_center().x,0,area.get_center().y)
	var size:=Vector3(area.size.x,.4,area.size.y)
	for child in body.get_children():
		if child is MeshInstance3D:
			var mesh:=BoxMesh.new(); mesh.size=size; child.mesh=mesh
		elif child is CollisionShape3D:
			var shape:=BoxShape3D.new(); shape.size=size; child.shape=shape
