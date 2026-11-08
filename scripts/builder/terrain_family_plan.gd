extends RefCounted

const CATALOG: String="res://resources/catalog/terrain_families.json"
const CARDINAL: Array[Vector2i]=[Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
static var catalog: Dictionary={}

static func definitions() -> Dictionary:
	if catalog.is_empty():
		var source: Variant=JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
		if source is Dictionary and source.get("version")==1: catalog=source
	return catalog

static func profile(id: String) -> Dictionary:
	return definitions().get("families",{}).get(id,{})

static func valid_tile(tile: Dictionary,mode: String) -> bool:
	if not tile.has("family"): return true
	var id: Variant=tile["family"]
	return mode=="2d" and id is String and id in ["shore","path"] and tile["asset"]==profile(id).get("asset","") and tile.get("colors",[]).is_empty()

static func cell_of(record: Dictionary) -> Vector2i:
	return Vector2i(record["cell"][0],record["cell"][1])

static func by_cell(records: Array) -> Dictionary:
	var result: Dictionary={}
	for record in records: result[cell_of(record)]=record
	return result

static func affected(old: Dictionary,next: Dictionary) -> Dictionary:
	var cells: Dictionary=old.duplicate()
	cells.merge(next)
	var changed: Dictionary={}
	for cell in cells:
		if old.get(cell)!=next.get(cell):
			for x in range(-1,2):
				for y in range(-1,2): changed[cell+Vector2i(x,y)]=true
	return changed

static func water_levels(records: Array) -> Dictionary:
	var result: Dictionary={}
	for record in records: result[cell_of(record)]=float(record["level"])
	return result

static func shoreline(cell: Vector2i,levels: Dictionary) -> Dictionary:
	var level: float=levels.get(cell,0.0)
	var wet: int=0
	var unsupported: int=0
	for i in 4:
		var side: Vector2i=cell+CARDINAL[i]
		if not levels.has(side): continue
		if is_equal_approx(level,levels[side]): wet|=1<<i
		else: unsupported|=1<<i
	var inlets: int=0
	for i in 4:
		var j: int=(i+1)%4
		if not wet&(1<<i) or not wet&(1<<j): continue
		var diagonal: Vector2i=cell+CARDINAL[i]+CARDINAL[j]
		if not levels.has(diagonal): inlets|=1<<i
		elif not is_equal_approx(level,levels[diagonal]): unsupported|=1<<i
	return {"family":"shore","mask":15^wet,"inlets":inlets,"unsupported":unsupported}

static func ground_variant(tile: Dictionary,cell: Vector2i,tiles: Dictionary,levels: Dictionary) -> Dictionary:
	var id: String=tile.get("family","")
	if id=="shore":
		var water: Dictionary={}
		for x in range(-1,2):
			for y in range(-1,2):
				var other: Vector2i=cell+Vector2i(x,y)
				if tiles.get(other,{}).get("asset")=="2d:Water": water[other]=levels.get(other,0.0)
		return shoreline(cell,water)
	if id=="path":
		var mask: int=0
		var unsupported: int=0
		for i in 4:
			var neighbor: Dictionary=tiles.get(cell+CARDINAL[i],{})
			if neighbor.get("family")=="path": mask|=1<<i
			elif neighbor.get("asset")=="2d:Stone_Path": unsupported|=1<<i
		return {"family":"path","mask":mask,"unsupported":unsupported}
	return {}

static func warning(variant: Dictionary) -> String:
	if variant.get("unsupported",0)==0: return ""
	return "Manual path neighbor · transition unavailable" if variant["family"]=="path" else "Water at different levels · transition unavailable"

static func cliff(samples: Array) -> Dictionary:
	var limit: float=profile("cliff").get("minimum_drop",1.2)
	var x: float=(float(samples[1])+float(samples[3])-float(samples[0])-float(samples[2]))*.5
	var y: float=(float(samples[2])+float(samples[3])-float(samples[0])-float(samples[1]))*.5
	var mask: int=0
	if x>=limit: mask|=8
	elif x<=-limit: mask|=2
	if y>=limit: mask|=1
	elif y<=-limit: mask|=4
	return {} if mask==0 else {"family":"cliff","mask":mask,"unsupported":0}

static func piece(variant: Dictionary) -> String:
	var id: String=variant["family"]
	if id=="shore": return "shore" if profile(id).has("bank_width") else ""
	var pieces: Array=profile(id).get("pieces",[])
	var mask: int=variant["mask"]
	return pieces[mask] if mask<pieces.size() else ""
