extends RefCounted

const Document = preload("res://scripts/builder/document.gd")

static func make(mode: String, kind: String) -> Dictionary:
	var doc := Document.new()
	doc.data["mode"] = mode
	doc.data["template"] = kind
	doc.data["template_revision"] = 2
	doc.data["spawn"] = [0, 60, 0] if mode == "2d" else [0, 0.2, 9]
	doc.data["title"] = {"blank": "Blank canvas", "room": "A room of your own", "city": "Your first city block"}[kind]
	if mode == "2d":
		if kind == "room":
			ground(doc, "Floor_Wood_Oak", -6, 6, -6, 6)
			for i in range(-6, 6):
				put(doc, "Wall_White", i, -6, "Right")
				put(doc, "Wall_White", -6, i, "Left")
			put(doc, "Sofa_Teal", -4, -3)
			put(doc, "Coffee_Table_Wood", -1, -1)
			put(doc, "Bookshelf_Tall", -5, 1)
			put(doc, "Plant_Monstera", 3, -4)
			put(doc, "Floor_Lamp", -4, -1)
			put(doc, "Dining_Table_Round", 2, 2)
			put(doc, "Dining_Chair_White", 4, 3)
			put(doc, "Armchair_Mustard", 2, -2)
		elif kind == "city":
			ground(doc, "Grass", -14, 14, -12, 12)
			ground(doc, "Sidewalk", -14, 14, -2, 3)
			ground(doc, "Asphalt", -14, 14, -1, 2)
			ground(doc, "Road_Center_Dash_X", -14, 14, 0, 1)
			put(doc, "Coffee_Shop", -10, -7)
			put(doc, "Apartment_Building", -3, -8)
			put(doc, "Bakery", 5, -7)
			put(doc, "Street_Light", -6, -2)
			put(doc, "Street_Light", 4, -2)
			put(doc, "Sedan_Red", -5, 1, "SE")
			put(doc, "Taxi", 3, -1, "NW")
			put(doc, "Tree_Oak", -9, 6)
			put(doc, "Park_Bench", -4, 6)
			put(doc, "Fountain", 2, 6)
			put(doc, "Tree_Cherry_Blossom", 8, 6)
	else:
		if kind == "city":
			put3(doc, "HanX_City/Apartment_4F_A", -13, -9)
			put3(doc, "HanX_City/Cafe_Small", 0, -9)
			put3(doc, "HanX_City/Corner_Shop_Building", 11, -9)
			for i in range(-24, 25, 8):
				put3(doc, "HanX_Traffic/Road_Straight", i, 3, "90")
				doc.data["objects"][-1]["position"][1] = 0.02
			put3(doc, "HanX_Traffic/Car_Sedan", -6, 4.5, "90")
			doc.data["objects"][-1]["position"][1] = 0.02
			put3(doc, "HanX_Traffic/Car_Taxi", 8, 1.5, "270")
			doc.data["objects"][-1]["position"][1] = 0.02
			put3(doc, "HanX_Park/Tree_Oak", -13, 15)
			put3(doc, "HanX_Park/Bench_Park", -5, 13)
			put3(doc, "HanX_Park/Fountain_Tiered", 5, 15)
			put3(doc, "HanX_Park/Tree_Cherry_Blossom", 16, 15)
		elif kind == "room":
			doc.data["spawn"] = [0, 0.2, 2.5]
			for x in range(-3, 4, 2):
				for z in range(-3, 4, 2):
					put3(doc, "HanX_Shop/Floor_Tile_Store", x, z)
					doc.data["objects"][-1]["position"][1] = 0.04
			put3(doc, "HanX_Shop/Cafe_Table_Set", -1, 0.5)
			put3(doc, "HanX_Shop/Cafe_Table_Set", 1.5, 0.5)
			put3(doc, "HanX_Shop/Cafe_Counter", 0.7, -2.6)
			put3(doc, "HanX_Shop/Pastry_Display", 2.7, -2.6)
			put3(doc, "HanX_Shop/Planter_Box", -2.8, -2.8)
			put3(doc, "HanX_Shop/Shelf_Wall", -3, 0, "90")
			for x in range(-3, 4, 2):
				put3(doc, "HanX_Shop/Wall_Store_Segment", x, -4)
			for z in range(-3, 4, 2):
				put3(doc, "HanX_Shop/Wall_Store_Segment", -4, z, "90")
	return doc.data

static func upgrade_road_layout(data: Dictionary) -> bool:
	if data.get("template") != "city" or int(data.get("template_revision", 1)) >= 2:
		return false
	for item in data["objects"]:
		var position: Vector3 = Vector3(item["position"][0], item["position"][1], item["position"][2])
		# Match only untouched starter placements; preserve moved/rotated user objects.
		if data["mode"] == "2d" and item["direction"] == "SE":
			if item["asset"] == "2d:Sedan_Red" and position.is_equal_approx(Vector3(-80, -40, 0)):
				item["position"] = [-96.0, -32.0, 0.0]
			elif item["asset"] == "2d:Taxi" and position.is_equal_approx(Vector3(48, 24, 0)):
				item["position"] = [64.0, 16.0, 0.0]
				item["direction"] = "NW"
		elif data["mode"] == "3d" and item["direction"] == "0":
			if item["asset"] == "3d:HanX_Traffic/Road_Straight" and is_zero_approx(position.y) and is_equal_approx(position.z, 3.0) and position.x in [-24.0, -16.0, -8.0, 0.0, 8.0, 16.0, 24.0]:
				item["direction"] = "90"
				item["position"][1] = 0.02
			elif item["asset"] == "3d:HanX_Traffic/Car_Sedan" and position.is_equal_approx(Vector3(-6, 0, 3)):
				item["position"] = [-6.0, 0.02, 4.5]
				item["direction"] = "90"
			elif item["asset"] == "3d:HanX_Traffic/Car_Taxi" and position.is_equal_approx(Vector3(8, 0, 3)):
				item["position"] = [8.0, 0.02, 1.5]
				item["direction"] = "270"
	data["template_revision"] = 2
	return true

static func ground(doc: RefCounted, asset: String, x0: int, x1: int, y0: int, y1: int) -> void:
	for x in range(x0, x1):
		for y in range(y0, y1):
			var cell: Array = [x, y]
			var found: bool = false
			for tile in doc.data["tiles"]:
				if tile["cell"] == cell:
					tile["asset"] = "2d:" + asset
					tile["direction"] = "SE"
					found = true
					break
			if not found:
				doc.data["tiles"].append({"cell": cell, "asset": "2d:" + asset, "direction": "SE"})

static func put(doc: RefCounted, id: String, x: int, y: int, direction: String = "SE") -> void:
	var directions: Dictionary = Catalog.get_item(id).get("directions", {})
	if not directions.has(direction) and not directions.is_empty():
		direction = str(directions.keys()[0])
	doc.add("2d:" + id, [16 * (x - y), 8 * (x + y), 0], direction)

static func put3(doc: RefCounted, id: String, x: float, z: float, direction: String = "0") -> void:
	doc.add("3d:" + id, [x, 0, z], direction)
