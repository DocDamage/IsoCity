extends RefCounted

const Doc = preload("res://scripts/builder/document.gd")
const Assets = preload("res://scripts/builder/repair_assets.gd")
const Layers = preload("res://scripts/builder/layers.gd")
const MAX_COORDINATE: float = 1000000.0
var library: RefCounted
var issues: Array = []
var availability: Dictionary = {}

func _init(asset_library: RefCounted) -> void:
	library = asset_library

func note(path: String, message: String, original: Variant = null) -> void:
	var entry: Dictionary = {"path":path,"message":message}
	if original != null: entry["original"] = original.duplicate(true) if original is Dictionary or original is Array else original
	issues.append(entry)

# Keep complete JSON prefixes if a write was truncated. Strings/escapes are
# tracked so braces and commas inside asset names never become boundaries.
func parse_text(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) == OK: return {"value":parser.data,"salvaged":false}
	var recovered: Variant = preload("res://scripts/builder/json_recovery.gd").new().recover(text)
	if recovered is Dictionary and recovered.get("documents") is Dictionary:
		return {"value":recovered,"salvaged":true,"original_text":text}
	var stack: Array[String] = []
	var candidates: Array = []
	var quoted: bool = false
	var escaped: bool = false
	for i in text.length():
		var c: String = text.substr(i,1)
		if quoted:
			if escaped: escaped = false
			elif c == "\\": escaped = true
			elif c == '"': quoted = false
			continue
		if c == '"': quoted = true
		elif c in ["{","["]: stack.append("}" if c == "{" else "]")
		elif c in ["}","]"]:
			if stack.is_empty() or stack.back() != c: break
			stack.pop_back()
			candidates.append([i+1,stack.duplicate()])
		elif c == ",": candidates.append([i,stack.duplicate()])
		if candidates.size() > 128: candidates.pop_front()
	if not quoted: candidates.append([text.length(),stack.duplicate()])
	for index in range(candidates.size()-1,-1,-1):
		var candidate: Array = candidates[index]
		var prefix: String = text.substr(0,candidate[0]).strip_edges().trim_suffix(",")
		for close_index in range(candidate[1].size()-1,-1,-1): prefix += candidate[1][close_index]
		if parser.parse(prefix) == OK and parser.data is Dictionary and parser.data.get("documents") is Dictionary:
			return {"value":parser.data,"salvaged":true,"original_text":text}
	return {"error":"JSON could not be recovered: " + parser.get_error_message()}

func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok":false,"error":"Project file was not found."}
	var parsed: Dictionary = parse_text(FileAccess.get_file_as_string(path))
	if parsed.has("error"): return {"ok":false,"error":parsed["error"]}
	if parsed.get("salvaged",false): note("file","Recovered recognizable JSON records around damaged tokens or a truncated tail.",parsed["original_text"])
	return session(parsed["value"],path)

func session(raw: Variant, source: String = "") -> Dictionary:
	if not raw is Dictionary or not raw.get("documents") is Dictionary: return {"ok":false,"error":"No recognizable Studio documents were found."}
	if raw.has("version") and raw["version"] != 1: return {"ok":false,"error":"This project version is not supported."}
	var useful: bool = false
	for mode in ["2d","3d"]:
		var world: Variant = raw["documents"].get(mode)
		useful = useful or (world is Dictionary and (world.get("objects") is Array or world.get("tiles") is Array))
	if not useful: return {"ok":false,"error":"No recoverable world collections were found. Current work was preserved."}
	var result: Dictionary = raw.duplicate(true)

	if not result.has("version"): result["version"] = 1; note("version","Recovered the Studio format version.")
	for mode in ["2d","3d"]:
		result["documents"][mode] = world(raw["documents"].get(mode),mode,"documents/"+mode,0)
		if not Doc.valid(result["documents"][mode],mode,library): return {"ok":false,"error":"The repaired document could not be validated. Current work was preserved."}
	if not result.get("active_mode","2d") in ["2d","3d"]: note("active_mode","Reset the invalid active world.",result["active_mode"]); result["active_mode"] = "2d"
	for key in ["project_path","project_origin_path","project_title","saved_digest"]:
		if result.has(key) and not result[key] is String: note(key,"Removed an invalid project metadata field.",result[key]); result.erase(key)
	if result.has("workspace"): result["workspace"] = workspace(result["workspace"])
	if result.has("project_palette") and not preload("res://scripts/builder/asset_collections.gd").project_valid(result["project_palette"]):
		note("project_palette","Archived unreadable project recommendation metadata; personal collections and world content were preserved.",result["project_palette"]);result.erase("project_palette")
	var old_report: Dictionary = result.get("repair_report",{}) if result.get("repair_report") is Dictionary else {}
	if not old_report.is_empty() and not old_report.get("issues") is Array: note("repair_report","Archived an unreadable earlier repair report.",old_report); old_report = {}
	var report: Dictionary = {"source":source,"time":Time.get_datetime_string_from_system(true).replace("T"," ")+" UTC","issues":issues.duplicate(true)}
	if not issues.is_empty():
		if not old_report.is_empty(): report["previous"] = old_report
		result["repair_report"] = report
	elif not old_report.is_empty(): report = old_report
	return {"ok":true,"content":result,"changed":not issues.is_empty(),"report":report}

func world(raw: Variant, mode: String, path: String, depth: int) -> Dictionary:
	if not raw is Dictionary:
		note(path,"Created an empty world for the missing/unreadable document.",raw)
		raw = {}
	var result: Dictionary = raw.duplicate(true)
	if result.has("protected_areas") and ((depth>0 and result["protected_areas"]!=[]) or not preload("res://scripts/builder/cooperative_plan.gd").valid_areas(result["protected_areas"])):
		var original_areas: Variant=result["protected_areas"]; var valid_areas: Array=[]; var area_ids: Dictionary={}
		if depth==0 and original_areas is Array:
			for area in original_areas:
				if valid_areas.size()<128 and preload("res://scripts/builder/cooperative_plan.gd").valid_areas([area]) and not area_ids.has(area["uid"]): valid_areas.append(area); area_ids[area["uid"]]=true
		result["protected_areas"]=valid_areas; note(path+"/protected_areas","Retained valid exterior protected areas; removed damaged or unsupported room areas.",original_areas)
	if result.has("blueprints"):
		repair_proposals(result,mode,path,depth)
	if result.has("photo") and not preload("res://scripts/builder/photo_plan.gd").valid(result["photo"],mode):
		var original_photo: Variant=result["photo"]; var repaired_photo: Dictionary={}; var photo_plan=preload("res://scripts/builder/photo_plan.gd")
		if original_photo is Dictionary:
			repaired_photo=original_photo.duplicate(true)
			for key in original_photo:
				if key in ["bookmarks","paths"]:
					var entries: Array=[]; var ids: Dictionary={}
					if original_photo[key] is Array:
						for entry in original_photo[key]:
							if not photo_plan.entry_valid(entry,mode,key=="paths") or ids.has(entry["uid"]): continue
							if entries.size()>=(photo_plan.MAX_BOOKMARKS if key=="bookmarks" else photo_plan.MAX_PATHS): break
							entries.append(entry); ids[entry["uid"]]=true
					repaired_photo[key]=entries
				elif not photo_plan.valid({key:original_photo[key]},mode): repaired_photo.erase(key)
		result["photo"]=repaired_photo; note(path+"/photo","Retained valid camera settings, bookmarks and paths; removed unreadable entries.",original_photo)

	if result.has("weather") and not preload("res://scripts/builder/weather_plan.gd").valid_settings(result["weather"]):
		var original_weather: Variant=result["weather"]; var fixed_weather: Dictionary=preload("res://scripts/builder/weather_plan.gd").defaults()
		if original_weather is Dictionary:
			fixed_weather=original_weather.duplicate(true)
			for key in original_weather:
				if not preload("res://scripts/builder/weather_plan.gd").valid_settings({key:original_weather[key]}): fixed_weather[key]=preload("res://scripts/builder/weather_plan.gd").defaults()[key]
		result["weather"]=fixed_weather; note(path+"/weather","Reset invalid weather settings and retained valid controls.",original_weather)
	if result.has("garden") and not preload("res://scripts/builder/garden_plan.gd").valid_settings(result["garden"]):
		var original_garden: Variant = result["garden"]
		var fixed_garden: Dictionary = original_garden.duplicate(true) if original_garden is Dictionary else {}
		fixed_garden["enabled"] = false
		result["garden"] = fixed_garden
		note(path+"/garden", "Disabled unreadable garden preview settings.", original_garden)
	if result.has("cooking") and not preload("res://scripts/builder/cooking_plan.gd").valid_settings(result["cooking"]):
		var original_cooking: Variant = result["cooking"]
		var fixed_cooking: Dictionary = original_cooking.duplicate(true) if original_cooking is Dictionary else {}
		fixed_cooking["enabled"] = false
		result["cooking"] = fixed_cooking
		note(path+"/cooking","Disabled unreadable cooking preview settings.",original_cooking)
	if result.has("laundry") and not preload("res://scripts/builder/laundry_plan.gd").valid_settings(result["laundry"]):
		var original_laundry: Variant = result["laundry"]
		var fixed_laundry: Dictionary = original_laundry.duplicate(true) if original_laundry is Dictionary else {}
		fixed_laundry["enabled"] = false
		result["laundry"] = fixed_laundry
		note(path+"/laundry","Disabled unreadable laundry preview settings.",original_laundry)
	if result.has("fitness") and not preload("res://scripts/builder/fitness_plan.gd").valid_settings(result["fitness"]):
		var original_fitness: Variant = result["fitness"]
		var fixed_fitness: Dictionary = original_fitness.duplicate(true) if original_fitness is Dictionary else {}
		fixed_fitness["enabled"] = false
		result["fitness"] = fixed_fitness
		note(path+"/fitness","Disabled unreadable sports preview settings.",original_fitness)
	if result.has("arcade") and not preload("res://scripts/builder/arcade_plan.gd").valid_settings(result["arcade"]):
		var original_arcade: Variant = result["arcade"]
		var fixed_arcade: Dictionary = original_arcade.duplicate(true) if original_arcade is Dictionary else {}
		fixed_arcade["enabled"] = false
		result["arcade"] = fixed_arcade
		note(path+"/arcade","Disabled unreadable arcade preview settings.",original_arcade)
	if result.has("camping") and not preload("res://scripts/builder/camping_plan.gd").valid_settings(result["camping"]):
		var original_camp: Variant = result["camping"]
		var fixed_camp: Dictionary = original_camp.duplicate(true) if original_camp is Dictionary else {}
		fixed_camp["enabled"] = false
		result["camping"] = fixed_camp
		note(path+"/camping","Disabled unreadable camping preview settings.",original_camp)
	var pets = preload("res://scripts/builder/pet_plan.gd")
	if result.has("pet") and not pets.valid(result["pet"]):
		var original_pet: Variant = result["pet"]
		var fixed_pet: Dictionary = original_pet.duplicate(true) if original_pet is Dictionary else {}
		for key in pets.DEFAULTS:
			if fixed_pet.has(key) and not pets.valid({key:fixed_pet[key]}): fixed_pet.erase(key)
		fixed_pet["enabled"] = false
		result["pet"] = fixed_pet
		note(path+"/pet","Disabled unreadable companion settings.",original_pet)
	var village_plan = preload("res://scripts/builder/village_plan.gd")
	if result.has("village") and not village_plan.valid_settings(result["village"]):
		var original: Variant = result["village"]
		var fixed: Dictionary = original.duplicate(true) if original is Dictionary else {}
		fixed["enabled"] = false
		result["village"] = fixed
		note(path+"/village","Disabled unreadable village settings.",original)
	var harbors = preload("res://scripts/builder/harbor_plan.gd")
	if result.has("harbor") and not harbors.valid(result["harbor"]):
		var original: Variant = result["harbor"]
		result["harbor"] = harbors.settings({})
		note(path + "/harbor", "Disabled unreadable harbor settings.", original)
	if result.has("space_outpost"):
		var outpost = preload("res://scripts/builder/space_outpost_plan.gd")
		if depth > 0 or raw.get("interior_room", false) or not outpost.valid(result["space_outpost"]):
			note(path + "/space_outpost", "Removed unreadable exterior outpost settings.", result["space_outpost"])
			result.erase("space_outpost")
		else:
			result["space_outpost"] = outpost.settings(result)
	var cycles = preload("res://scripts/builder/cycling_plan.gd")
	if result.has("cycling") and not cycles.valid(result["cycling"]):
		var original_cycle: Variant = result["cycling"]
		var fixed_cycle: Dictionary = original_cycle.duplicate(true) if original_cycle is Dictionary else {}
		fixed_cycle["enabled"] = false
		result["cycling"] = fixed_cycle
		note(path+"/cycling","Disabled unreadable cycling settings.",original_cycle)
	if result.has("ambience") and not preload("res://scripts/builder/ambience_plan.gd").valid_settings(result["ambience"]):
		var original_audio: Variant=result["ambience"]; var fixed_audio: Dictionary=preload("res://scripts/builder/ambience_plan.gd").defaults()
		if original_audio is Dictionary:
			fixed_audio=original_audio.duplicate(true)
			for key in original_audio:
				if not preload("res://scripts/builder/ambience_plan.gd").valid_settings({key:original_audio[key]}): fixed_audio[key]=preload("res://scripts/builder/ambience_plan.gd").defaults()[key]
		result["ambience"]=fixed_audio; note(path+"/ambience","Reset invalid ambience settings and retained valid controls.",original_audio)
	if result.has("neighborhood_generator") and not preload("res://scripts/builder/neighborhood_plan.gd").valid_settings(result["neighborhood_generator"]):
		note(path+"/neighborhood_generator","Reset unreadable neighborhood generator settings; generated city content was retained.",result["neighborhood_generator"]); result.erase("neighborhood_generator")
	if result.has("terrain"):
		var original: Variant=result["terrain"]; var plan=preload("res://scripts/builder/terrain_plan.gd")
		if not original is Dictionary:
			note(path+"/terrain","Disabled unreadable terrain settings.",original); result["terrain"]={"enabled":false}
		else:
			var fixed: Dictionary=plan.settings({"terrain":original})
			for key in fixed:
				if original.has(key) and not plan.valid_settings({key:original[key]}): note(path+"/terrain/"+key,"Reset or clamped unreadable terrain settings.",original[key]); result["terrain"][key]=fixed[key]
	for field in ["terrain_vertices","water_cells"]:
		if result.has(field): result[field]=terrain_records(result[field],result,path+"/"+field,field=="water_cells")
	if result.has("transit"):
		var original: Variant=result["transit"]; var plan=preload("res://scripts/builder/transit_plan.gd")
		if not original is Dictionary:
			note(path+"/transit","Disabled unreadable public transit settings.",original); result["transit"]={"enabled":false}
		else:
			var fixed: Dictionary=plan.settings({"transit":original})
			for key in fixed:
				if original.has(key) and not plan.valid_settings({key:original[key]}): note(path+"/transit/"+key,"Reset or clamped an invalid transit setting.",original[key]); result["transit"][key]=fixed[key]
	if result.has("transit_lines"): result["transit_lines"]=transit_lines(result["transit_lines"],path+"/transit_lines")
	if result.has("zoning"):
		var original: Variant=result["zoning"]; var plan=preload("res://scripts/builder/zone_plan.gd")
		if not original is Dictionary:
			note(path+"/zoning","Disabled unreadable development settings.",original); result["zoning"]={"enabled":false}
		else:
			var fixed: Dictionary=plan.settings({"zoning":original})
			for key in fixed:
				if original.has(key) and not plan.valid_settings({key:original[key]}): note(path+"/zoning/"+key,"Reset or clamped an invalid development setting.",original[key]); result["zoning"][key]=fixed[key]
	if result.has("zones"): result["zones"]=zones(result["zones"],mode,path+"/zones")
	if result.has("scenario"):
		var scenario: Variant=result["scenario"]
		var exterior_only: bool = scenario is Dictionary and (scenario.get("id") == "construction" or preload("res://scripts/builder/emergency_training_plan.gd").recognized(scenario.get("id")))
		if not preload("res://scripts/builder/scenario_plan.gd").valid(scenario) or exterior_only and (depth > 0 or raw.get("interior_room", false)):
			note(path+"/scenario","Removed an invalid challenge definition and preserved the city and treasury.",scenario); result.erase("scenario")
	if result.has("economy"):
		var original: Variant=result["economy"]
		var plan=preload("res://scripts/builder/economy_plan.gd")
		if not original is Dictionary:
			note(path+"/economy","Disabled unreadable economy settings.",original); result["economy"]={"enabled":false}
		else:
			var fixed: Dictionary=plan.settings({"economy":original})
			for key in fixed:
				if original.has(key) and not plan.valid_settings({key:original[key]}):
					note(path+"/economy/"+key,"Reset or clamped invalid economy settings.",original[key]); result["economy"][key]=fixed[key]
	if result.has("economy_account") and not preload("res://scripts/builder/economy_plan.gd").valid_account(result["economy_account"]):
		var original: Variant=result["economy_account"]
		result["economy_account"]=preload("res://scripts/builder/economy_plan.gd").repair_account(original)
		note(path+"/economy_account","Recovered valid treasury records; invalid cash becomes zero rather than a new starting grant.",original)
	if result.has("services"):
		var original: Variant=result["services"]
		var plan=preload("res://scripts/builder/service_plan.gd")
		if not original is Dictionary:
			note(path+"/services","Reset unreadable city service settings.",original); result["services"]={}
		else:
			var fixed: Dictionary=plan.settings({"services":original})
			for key in fixed:
				if original.has(key) and not plan.valid_settings({key:original[key]}):
					note(path+"/services/"+key,"Reset or clamped invalid city service settings.",original[key]); result["services"][key]=fixed[key]
	if result.has("fleet") and not preload("res://scripts/builder/fleet_plan.gd").valid(result["fleet"]):
		result["fleet"]=repair_fleet(result["fleet"],path+"/fleet")
	if result.has("traffic"):
		var original: Variant=result["traffic"]
		var plan=preload("res://scripts/builder/traffic_plan.gd")
		if not original is Dictionary:
			note(path+"/traffic","Reset unreadable traffic settings.",original); result["traffic"]={}
		else:
			var fixed: Dictionary=plan.settings({"traffic":original})
			for key in fixed:
				if original.has(key) and not plan.valid_settings({key:original[key]}):
					note(path+"/traffic/"+key,"Reset or clamped invalid traffic settings.",original[key]); result["traffic"][key]=fixed[key]
	if result.has("citizens"):
		var original: Variant=result["citizens"]
		var plan=preload("res://scripts/builder/citizen_plan.gd")
		if not original is Dictionary:
			note(path+"/citizens","Reset unreadable citizen settings.",original); result["citizens"]={}
		else:
			var fixed: Dictionary=plan.settings({"citizens":original})
			for key in fixed:
				if original.has(key) and not plan.valid_settings({key:original[key]}):
					note(path+"/citizens/"+key,"Reset or clamped invalid citizen settings.",original[key]); result["citizens"][key]=fixed[key]
			if original.has("appearance"):
				var selected: Variant=original["appearance"]
				var available: bool=selected is String and selected.is_empty()
				if selected is String and mode=="2d" and library.assets.has(selected) and library.assets[selected]["data"].get("kind","")=="char": available=Assets.available(selected,library,availability)
				if not available: result["citizens"].erase("appearance"); note(path+"/citizens/appearance","Restored the default citizen appearance because the selected character is invalid or unavailable.",selected)
	if result.get("mode") != mode: note(path+"/mode","Restored the world dimension.",result.get("mode")); result["mode"] = mode
	if not result.get("title") is String: note(path+"/title","Restored a document title.",result.get("title")); result["title"] = "Recovered " + mode + " world"
	if not result.get("night",false) is bool: note(path+"/night","Reset invalid lighting.",result["night"]); result["night"] = false
	result["night"] = result.get("night",false)
	var objects: Array = []
	var school_count: int=0
	var vehicle_bay_count: int=0
	var delivery_count: int=0
	var market_count: int=0
	var markets=preload("res://scripts/builder/market_plan.gd")
	var deliveries=preload("res://scripts/builder/delivery_plan.gd")
	var seen: Dictionary = {}
	if not raw.get("objects") is Array: note(path+"/objects","Replaced an unreadable object collection; its original value is archived.",raw.get("objects"))
	for index in (raw.get("objects",[]) if raw.get("objects") is Array else []).size():
		var item: Variant = raw["objects"][index]
		var location: String = path+"/objects/"+str(index)
		if not item is Dictionary: note(location,"Quarantined an unreadable object record.",item); continue
		if not ["uid","asset","position","name"].any(func(key:String)->bool:return item.has(key)): note(location,"Quarantined an object fragment without recognizable identity or placement.",item); continue
		var repaired: Dictionary = object(item,mode,location,depth)
		if repaired.has("market"):
			if depth>0 or raw.get("interior_room",false) or not markets.valid(repaired):
				note(location+"/market","Archived invalid market settings and kept the placement.",repaired["market"])
				repaired.erase("market")
			elif markets.enabled(repaired):
				market_count+=1
				if market_count>markets.MAX_MARKETS:
					note(location+"/market","Disabled the market above the city limit.",repaired["market"])
					repaired["market"]["enabled"]=false
		for field in deliveries.FIELDS:
			if repaired.has(field) and (raw.get("interior_room",false) or depth>0 or not deliveries.valid(repaired,field)):
				note(location+"/"+field,"Archived invalid delivery settings and kept the placement.",repaired[field])
				repaired.erase(field)
		if deliveries.enabled(repaired,"delivery_site"):
			delivery_count+=1
			if delivery_count>deliveries.MAX_SITES:
				note(location+"/delivery_site","Disabled the delivery site above the city limit.",repaired["delivery_site"])
				repaired["delivery_site"]["enabled"]=false
		var care=preload("res://scripts/builder/vehicle_service_plan.gd")
		for key in ["vehicle_care","vehicle_bay"]:
			if not repaired.has(key): continue
			if raw.get("interior_room",false) or depth>0 or not (care.valid_bay(repaired) if key=="vehicle_bay" else care.valid_vehicle(repaired)):
				note(location+"/"+key,"Archived invalid vehicle-care settings and retained the object.",repaired[key])
				repaired.erase(key)
		if not care.bay(repaired).is_empty():
			vehicle_bay_count+=1
			if vehicle_bay_count>care.MAX_BAYS:
				note(location+"/vehicle_bay","Disabled the bay above the city limit and kept its configuration.",repaired["vehicle_bay"])
				repaired["vehicle_bay"]["enabled"]=false
		var schools=preload("res://scripts/builder/school_plan.gd")
		if schools.enabled(repaired):
			school_count+=1
			if school_count>schools.MAX_SCHOOLS:
				note(location+"/school","Disabled the school above the city limit and kept its schedule.",repaired["school"])
				repaired["school"]["enabled"]=false
		if seen.has(repaired["uid"]): note(location+"/uid","Assigned a new ID to a duplicate object.",repaired["uid"]); repaired["uid"] = "repair_"+location.sha256_text().substr(0,20)
		seen[repaired["uid"]] = true
		objects.append(repaired)
	result["objects"] = objects
	result["tiles"] = []
	if not raw.get("tiles") is Array: note(path+"/tiles","Replaced an unreadable tile collection; its original value is archived.",raw.get("tiles"))
	for index in (raw.get("tiles",[]) if raw.get("tiles") is Array else []).size():
		var tile: Variant = raw["tiles"][index]
		var location: String = path+"/tiles/"+str(index)
		if not tile is Dictionary or not Doc.numbers(tile.get("cell"),2): note(location,"Quarantined a tile without usable coordinates.",tile); continue
		if absf(tile["cell"][0]) > 100000 or absf(tile["cell"][1]) > 100000: note(location,"Quarantined a tile outside the supported ground range.",tile); continue
		var copy: Dictionary = tile.duplicate(true)
		if floorf(copy["cell"][0]) != copy["cell"][0] or floorf(copy["cell"][1]) != copy["cell"][1]: note(location+"/cell","Rounded the damaged tile coordinates.",copy["cell"]); copy["cell"] = [roundi(copy["cell"][0]),roundi(copy["cell"][1])]
		var asset: String = str(copy.get("asset",""))
		var native: bool = Assets.available(asset,library,availability) and library.assets[asset]["mode"] == "2d" and library.assets[asset]["category"] in ["Floors","City Ground"] and not library.assets[asset].get("hidden",false)
		if native:
			copy["colors"] = colors(copy.get("colors",[]),location+"/colors") if copy.has("colors") else []
			if copy["colors"].is_empty(): copy.erase("colors")
			if not preload("res://scripts/builder/terrain_family_plan.gd").valid_tile(copy,mode):
				note(location+"/family","Kept the manual tile and archived an unsupported terrain family.",copy["family"])
				copy.erase("family")
			if not copy.get("direction","SE") is String or not library.valid_direction(asset,copy.get("direction","SE")): note(location+"/direction","Reset invalid tile rotation.",copy.get("direction")); copy["direction"] = "SE"
			result["tiles"].append(copy)
		else:
			var point := Vector2((copy["cell"][0]-copy["cell"][1])*16,(copy["cell"][0]+copy["cell"][1])*8)
			Assets.register(library)
			var record: Dictionary = {"uid":"repair_tile_"+location.sha256_text().substr(0,20),"asset":Assets.TILE_2D,"position":[point.x,point.y,0],"direction":"SE","scale":1.0,"missing_asset":{"id":asset,"kind":"tile","record":tile.duplicate(true)},"name":"Missing ground: "+asset}
			if copy.get("direction","SE") is String and library.valid_direction(Assets.TILE_2D,copy.get("direction","SE")): record["direction"] = copy.get("direction","SE")
			result["objects"].append(record)
			note(location,"Substituted a visible, editable ground placeholder.",tile)
	for key in ["spawn","exit"]:
		if result.has(key) and (not Doc.numbers(result[key],3) or result[key].any(func(n:float)->bool:return absf(n)>MAX_COORDINATE)): note(path+"/"+key,"Reset damaged coordinates.",result[key]); result.erase(key)
	if result.has("interior_room") and not result["interior_room"] is bool: note(path+"/interior_room","Reset invalid room metadata.",result["interior_room"]); result["interior_room"] = true
	repair_floors(result,mode,path,depth)
	if result.has("modular_rooms"):
		var authored: Variant = result["modular_rooms"]
		var usable: Array = preload("res://scripts/builder/modular_building_plan.gd").retained(authored,mode)
		if usable != authored:
			note(path+"/modular_rooms","Archived unreadable room outlines. The placed modules were kept.",authored)
			result["modular_rooms"] = usable
	if result.has("roads"): result["roads"] = roads(result["roads"],path+"/roads")
	for key in ["layers","group_names"]:
		if result.has(key) and not result[key] is Dictionary: note(path+"/"+key,"Removed invalid document settings.",result[key]); result.erase(key)
	for key in result.get("layers",{}).keys():
		var layer: Variant = result["layers"][key]
		if not key is String or not key in Layers.NAMES or not layer is Dictionary: note(path+"/layers/"+str(key),"Removed an invalid layer definition.",layer); result["layers"].erase(key); continue
		for field in ["visible","locked"]:
			if layer.has(field) and not layer[field] is bool: note(path+"/layers/"+str(key),"Reset invalid layer flags.",layer[field]); layer.erase(field)
	for key in result.get("group_names",{}).keys():
		if not result["group_names"][key] is String: note(path+"/group_names/"+str(key),"Removed an invalid group name.",result["group_names"][key]); result["group_names"].erase(key)
	if result.has("connections"):
		var raw_connections: Variant = result["connections"]
		var retained: Array = preload("res://scripts/builder/connector_plan.gd").retained(result, raw_connections)
		if retained != raw_connections:
			note(path+"/connections", "Archived disconnected or unreadable socket links.", raw_connections)
			result["connections"] = retained
	var utility=preload("res://scripts/builder/utility_plan.gd")
	if depth>0 or result.get("interior_room",false):
		for field in utility.FIELDS:
			if not result.has(field): continue
			note(path+"/"+field,"Archived utility records from an interior.",result[field])
			result.erase(field)
	elif utility.FIELDS.any(func(field: String)->bool:return result.has(field)):
		if not utility.valid_settings(result.get("utilities",{})):
			note(path+"/utilities","Disabled unreadable utility settings.",result["utilities"])
			result.erase("utilities")
		var records: Dictionary=utility.retained(result,library)
		for field in records:
			if result.has(field) and result[field]!=records[field]:
				note(path+"/"+field,"Archived disconnected or unreadable utility records.",result[field])
				result[field]=records[field]
	return result

func repair_proposals(data: Dictionary,mode: String,path: String,depth: int) -> void:
	var blueprint=preload("res://scripts/builder/blueprint_plan.gd")
	var raw: Variant=data["blueprints"]
	var retained: Array=[]
	var identities: Dictionary={}
	var road_count: int=0
	if raw is Array:
		for index in raw.size():
			var proposal: Variant=raw[index]
			if not proposal is Dictionary: continue
			if proposal.get("kind")=="assembly":
				var scope: Dictionary={"mode":mode,"title":"Assembly","objects":proposal.get("objects"),"tiles":[]}
				if blueprint.Assembly.bounded_scope(scope,[0]) and assembly_missing_sources(scope):
					var repaired: Dictionary=world(scope,mode,path+"/blueprints/"+str(index),depth)
					proposal=proposal.duplicate(true)
					proposal["objects"]=repaired["objects"]
			if retained.size()>=blueprint.LIMIT or not blueprint.valid([proposal],mode,library) or identities.has(proposal["uid"]): continue
			var sections: int=0
			if proposal["kind"]=="road": sections=blueprint.Assembly.road_length(proposal)
			elif proposal["kind"]=="assembly":
				for road in proposal["roads"]: sections+=blueprint.Assembly.road_length(road)
			if road_count+sections>4096: continue
			road_count+=sections
			identities[proposal["uid"]]=true
			retained.append(proposal)
	if retained!=raw:
		data["blueprints"]=retained
		note(path+"/blueprints","Recovered available proposals and retained original records for unavailable or unreadable content.",raw)

func assembly_missing_sources(scope: Dictionary) -> bool:
	for key in ["objects","tiles"]:
		if not scope.get(key,[]) is Array: continue
		for item in scope.get(key,[]):
			if not item is Dictionary: continue
			if not Assets.available(str(item.get("asset","")),library,availability): return true
			if item.get("interior") is Dictionary and assembly_missing_sources(item["interior"]): return true
	for floor in scope.get("floors",[]):
		if assembly_missing_sources(floor["room"]): return true
	return false

func repair_floors(data: Dictionary,mode: String,path: String,depth: int) -> void:
	var plan=preload("res://scripts/builder/floor_plan.gd")
	if data.get("interior_room")!=true:
		for field in plan.FIELDS:
			if data.has(field): note(path+"/"+field,"Archived floor metadata outside an owned interior.",data[field]); data.erase(field)
		return
	if data.has("floor_name") and not plan.named(data["floor_name"]): note(path+"/floor_name","Reset an unreadable ground floor name.",data["floor_name"]); data.erase("floor_name")
	var raw: Variant=data.get("floors",[]); var floors: Array=[]; var heights: Dictionary={"ground":0.0}
	if not raw is Array: note(path+"/floors","Archived an unreadable floor collection.",raw); raw=[]
	for index in raw.size():
		var source: Variant=raw[index]; var location: String=path+"/floors/"+str(index)
		if floors.size()>=plan.MAX_FLOORS-1 or depth>=4: note(location,"Archived floors beyond the supported count or nesting depth.",raw.slice(index)); break
		# Check the descriptor without allowing another floor tree inside its room.
		var descriptor: Dictionary=source.duplicate(true) if source is Dictionary else {}
		if descriptor.get("room") is Dictionary:
			for field in plan.FIELDS:
				if descriptor["room"].has(field): note(location+"/room/"+field,"Archived nested floor metadata; floor contents were retained.",descriptor["room"][field]); descriptor["room"].erase(field)
		if not plan.floor_record(descriptor,mode) or heights.has(descriptor.get("uid")): note(location,"Archived an unreadable or duplicate floor descriptor.",source); continue
		var crowded: bool=false
		for height in heights.values(): crowded=crowded or absf(float(height)-float(descriptor["height"]))<plan.MIN_GAP-0.00001
		if crowded: note(location,"Archived a floor too close to another level.",source); continue
		descriptor["room"]=world(descriptor["room"],mode,location+"/room",depth+1)
		heights[descriptor["uid"]]=float(descriptor["height"]); floors.append(descriptor)
	if data.has("floors"): data["floors"]=floors
	for field in ["floor_links","floor_entrances"]:
		if not data.has(field): continue
		var sources: Variant=data[field]; var records: Array=[]; var seen: Dictionary={}
		if not sources is Array: note(path+"/"+field,"Archived an unreadable floor connection/entrance collection.",sources); data[field]=[]; continue
		for index in sources.size():
			var source: Variant=sources[index]; var location: String=path+"/"+field+"/"+str(index)
			if records.size()>=(plan.MAX_LINKS if field=="floor_links" else plan.MAX_ENTRANCES): note(location,"Archived records beyond the supported limit.",sources.slice(index)); break
			if not (plan.link_record(source,heights) if field=="floor_links" else plan.entrance_record(source,heights)): note(location,"Archived an invalid or dangling floor connection/entrance.",source); continue
			if seen.has(source["uid"]): note(location,"Archived a repeated floor connection/entrance ID.",source); continue
			if field=="floor_links" and not plan.compatible_link(source,records,heights): note(location,"Archived an overlapping elevator shaft; valid connections were retained.",source); continue
			seen[source["uid"]]=true; records.append(source.duplicate(true))
		data[field]=records

func terrain_records(raw: Variant,data: Dictionary,path: String,water: bool) -> Array:
	var plan=preload("res://scripts/builder/terrain_plan.gd"); var result: Array=[]; var seen: Dictionary={}; var area: Rect2i=plan.bounds(data); var field: String="level" if water else "height"
	if plan.valid_records(raw,data,water): return raw.duplicate(true)
	if not raw is Array: note(path,"Removed an unreadable terrain sample collection.",raw); return result
	for index in raw.size():
		var source: Variant=raw[index]; var location: String=path+"/"+str(index)
		if result.size()>=(plan.MAX_WATER if water else plan.MAX_VERTICES): note(location,"Archived terrain samples beyond the supported limit.",raw.slice(index)); break
		if not source is Dictionary or not Doc.numbers(source.get("cell"),2) or not plan.number(source.get(field)): note(location,"Archived a terrain sample without readable coordinates and elevation.",source); continue
		if absf(source["cell"][0])>plan.MAX_CELL or absf(source["cell"][1])>plan.MAX_CELL: note(location,"Archived a terrain sample outside the supported area.",source); continue
		var cell:=Vector2i(roundi(source["cell"][0]),roundi(source["cell"][1])); var identity: String=plan.key(cell)
		if seen.has(identity) or not (area.has_point(cell) if water else plan.vertex_inside(cell,area)): note(location,"Archived a repeated sample or a sample outside the terrain boundary.",source); continue
		var copy: Dictionary=source.duplicate(true); copy["cell"]=[cell.x,cell.y]
		if source[field]<plan.MIN_HEIGHT or source[field]>plan.MAX_HEIGHT: copy[field]=clampf(source[field],plan.MIN_HEIGHT,plan.MAX_HEIGHT)
		if copy!=source: note(location,"Recovered terrain coordinates/elevation while retaining sample metadata.",source)
		seen[identity]=true; result.append(copy)
	return result

func repair_fleet(raw: Variant,path: String) -> Dictionary:
	var fleet=preload("res://scripts/builder/fleet_plan.gd")
	if not raw is Dictionary:
		note(path,"Archived unreadable fleet settings.",raw)
		return {}
	var result: Dictionary={}
	for role in raw:
		if role not in fleet.ROLES:
			note(path+"/"+str(role),"Archived an unknown fleet role.",raw[role])
			continue
		result[role]=[]
		if not raw[role] is Array:
			note(path+"/"+role,"Archived an unreadable fleet choice list.",raw[role])
			continue
		for entry in raw[role]:
			var candidate: Array=result[role]+[entry]
			if fleet.valid({role:candidate}):
				result[role]=candidate
			else:
				note(path+"/"+role,"Archived an invalid or duplicate fleet choice.",entry)
	return result

func transit_lines(raw: Variant,path: String) -> Array:
	var result: Array=[]; var plan=preload("res://scripts/builder/transit_plan.gd"); var seen: Dictionary={}
	if not raw is Array: note(path,"Removed an unreadable bus-line collection.",raw); return result
	for index in raw.size():
		var original: Variant=raw[index]; var location: String=path+"/"+str(index)
		if result.size()>=plan.MAX_LINES: note(location,"Quarantined bus lines beyond the maximum of 16.",raw.slice(index)); break
		if plan.valid_lines([original]) and not seen.has(original["uid"]):
			seen[original["uid"]]=true; result.append(original.duplicate(true)); continue
		if not original is Dictionary or not original.get("stops") is Array: note(location,"Quarantined a line without usable stop references.",original); continue
		var copy: Dictionary=original.duplicate(true)
		if not plan.identifier(copy.get("uid")) or seen.has(copy["uid"]): copy["uid"]="repair_line_"+location.sha256_text().substr(0,20)
		if not copy.get("name","") is String: copy["name"]="Recovered bus line"
		elif copy.get("name","").length()>128: copy["name"]=copy["name"].substr(0,128)
		var stops: Array=[]
		for uid in copy["stops"]:
			if plan.identifier(uid) and not uid in stops and stops.size()<plan.MAX_LINE_STOPS: stops.append(uid)
		copy["stops"]=stops
		if stops.size()<2: note(location,"Quarantined a line with fewer than two distinct stop references.",original); continue
		if copy.has("enabled") and not copy["enabled"] is bool: copy["enabled"]=false
		for field in [["headway",60,10,900],["dwell",6,2,60],["offset",0,0,899.999999],["capacity",16,1,64]]:
			var key: String=field[0]
			if copy.has(key): copy[key]=preload("res://scripts/builder/traffic_plan.gd").number(copy[key],field[1],field[2],field[3])
		if copy.has("capacity"): copy["capacity"]=int(copy["capacity"])
		if copy.has("school_bus") and not copy["school_bus"] is bool:
			note(location+"/school_bus","Restored the standard bus type for this route.",copy["school_bus"])
			copy.erase("school_bus")
		if copy.get("offset",0)>=copy.get("headway",60): copy["offset"]=maxf(0,float(copy.get("headway",60))-.001)
		if copy.has("color") and not plan.color_valid(copy["color"]): copy["color"]=plan.definitions()["line_defaults"]["color"]
		if copy!=original: note(location,"Recovered bus-line settings and distinct stop references.",original)
		seen[copy["uid"]]=true; result.append(copy)
	return result

func zones(raw: Variant,mode: String,path: String) -> Array:
	var result: Array=[]; var plan=preload("res://scripts/builder/zone_plan.gd"); var seen: Dictionary={}
	if not raw is Array: note(path,"Removed an unreadable lot collection.",raw); return result
	for index in raw.size():
		var original: Variant=raw[index]; var location: String=path+"/"+str(index)
		if result.size()>=plan.MAX_LOTS: note(location,"Quarantined a lot beyond the development limit.",original); continue
		if not original is Dictionary or not original.get("kind") in plan.definitions() or not Doc.numbers(original.get("rect"),4): note(location,"Quarantined a lot without a known type and usable bounds.",original); continue
		var copy: Dictionary=original.duplicate(true)
		if not copy.get("uid") is String or copy["uid"].is_empty() or copy["uid"].length()>128 or seen.has(copy["uid"]): copy["uid"]="repair_lot_"+location.sha256_text().substr(0,20)
		copy["rect"]=[clampf(copy["rect"][0],-100000,100000),clampf(copy["rect"][1],-100000,100000),clampf(copy["rect"][2],4,64),clampf(copy["rect"][3],4,64)]
		for key in ["visible","locked"]:
			if copy.has(key) and not copy[key] is bool: copy.erase(key)
		if copy.has("name") and not copy["name"] is String: copy.erase("name")
		for key in ["theme","density","max_price"]:
			if copy.has(key) and not plan.Candidates.valid_options({key:copy[key]}):note(location+"/"+key,"Reset an unreadable lot filter; retained the saved construction plan.",copy[key]);copy.erase(key)
		if copy.has("selection") and not plan.Candidates.selection_valid(copy["selection"]):note(location+"/selection","Archived unreadable selection notes; retained usable construction geometry.",copy["selection"]);copy.erase("selection")
		if not plan.valid_stage(copy.get("stage",0)): copy["stage"]=0; copy.erase("proposal")
		if not plan.valid_lots([copy],mode,library): copy["stage"]=0; copy.erase("proposal")
		if not plan.valid_lots(result+[copy],mode,library): copy["stage"]=0; copy.erase("proposal")
		if not plan.valid_lots(result+[copy],mode,library): note(location,"Quarantined an overlapping or unreadable lot.",original); continue
		if copy!=original: note(location,"Repaired lot metadata; unreadable construction plans restart as vacant lots.",original)
		seen[copy["uid"]]=true; result.append(copy)
	return result

func object(raw: Dictionary, mode: String, path: String, depth: int) -> Dictionary:
	if raw.has("driving") and not preload("res://scripts/builder/driving_plan.gd").valid(raw["driving"]):
		var original_driving: Variant=raw["driving"]; var fixed_driving: Dictionary={"enabled":false}
		if original_driving is Dictionary:
			fixed_driving=original_driving.duplicate(true)
			for key in original_driving:
				if not preload("res://scripts/builder/driving_plan.gd").valid({key:original_driving[key]}): fixed_driving.erase(key)
			fixed_driving["enabled"]=false
		raw=raw.duplicate(true); raw["driving"]=fixed_driving; note(path+"/driving","Disabled malformed driving controls and retained readable settings.",original_driving)
	if raw.has("garden") and not preload("res://scripts/builder/garden_plan.gd").valid_site(raw["garden"]):
		var original_garden: Variant = raw["garden"]
		var fixed_garden: Dictionary = original_garden.duplicate(true) if original_garden is Dictionary else {}
		for key in ["crop", "irrigation"]:
			if fixed_garden.has(key) and not preload("res://scripts/builder/garden_plan.gd").valid_site({key:fixed_garden[key]}):
				fixed_garden.erase(key)
		fixed_garden["enabled"] = false
		raw = raw.duplicate(true)
		raw["garden"] = fixed_garden
		note(path+"/garden", "Disabled malformed garden settings and preserved the placed object.", original_garden)
	if raw.has("cooking") and not preload("res://scripts/builder/cooking_plan.gd").valid_station(raw["cooking"]):
		var original_cooking: Variant = raw["cooking"]
		var fixed_cooking: Dictionary = original_cooking.duplicate(true) if original_cooking is Dictionary else {}
		for key in ["recipe","power"]:
			if fixed_cooking.has(key) and not preload("res://scripts/builder/cooking_plan.gd").valid_station({key:fixed_cooking[key]}):
				fixed_cooking.erase(key)
		fixed_cooking["enabled"] = false
		raw = raw.duplicate(true)
		raw["cooking"] = fixed_cooking
		note(path+"/cooking","Disabled malformed kitchen settings and preserved the placed object.",original_cooking)
	var laundry_plan = preload("res://scripts/builder/laundry_plan.gd")
	if raw.has("laundry") and not laundry_plan.valid_station(raw["laundry"]):
		var original_laundry: Variant = raw["laundry"]
		var fixed_laundry: Dictionary = original_laundry.duplicate(true) if original_laundry is Dictionary else {}
		for key in ["capacity","power","water"]:
			if fixed_laundry.has(key) and not laundry_plan.valid_station({key:fixed_laundry[key]}): fixed_laundry.erase(key)
		fixed_laundry["enabled"] = false
		raw = raw.duplicate(true)
		raw["laundry"] = fixed_laundry
		note(path+"/laundry","Disabled malformed laundry settings and preserved the placed object.",original_laundry)
	var fitness_plan = preload("res://scripts/builder/fitness_plan.gd")
	if raw.has("fitness") and not fitness_plan.valid_station(raw["fitness"]):
		var original_fitness: Variant = raw["fitness"]
		var fixed_fitness: Dictionary = original_fitness.duplicate(true) if original_fitness is Dictionary else {}
		for key in ["open_hour","close_hour"]:
			if fixed_fitness.has(key) and not fitness_plan.valid_station({key:fixed_fitness[key]}): fixed_fitness.erase(key)
		fixed_fitness["enabled"] = false
		raw = raw.duplicate(true)
		raw["fitness"] = fixed_fitness
		note(path+"/fitness","Disabled malformed sports settings and preserved the placed object.",original_fitness)
	if raw.has("arcade") and not preload("res://scripts/builder/arcade_plan.gd").valid_cabinet(raw["arcade"]):
		var original_arcade: Variant = raw["arcade"]
		var fixed_arcade: Dictionary = original_arcade.duplicate(true) if original_arcade is Dictionary else {}
		fixed_arcade["game"] = "demo"
		raw = raw.duplicate(true)
		raw["arcade"] = fixed_arcade
		note(path+"/arcade","Restored the cabinet demo and preserved the placed object.",original_arcade)
	var camping_plan = preload("res://scripts/builder/camping_plan.gd")
	if raw.has("camping") and not camping_plan.valid_site(raw["camping"]):
		var original_camp: Variant = raw["camping"]
		var fixed_camp: Dictionary = original_camp.duplicate(true) if original_camp is Dictionary else {}
		for key in camping_plan.DEFAULTS:
			if fixed_camp.has(key) and not camping_plan.valid_site({key:fixed_camp[key]}): fixed_camp.erase(key)
		fixed_camp["enabled"] = false
		raw = raw.duplicate(true)
		raw["camping"] = fixed_camp
		note(path+"/camping","Disabled malformed camping settings and kept the shelter.",original_camp)
	var village_plan = preload("res://scripts/builder/village_plan.gd")
	if raw.has("village") and not village_plan.valid_site(raw["village"]):
		var original: Variant = raw["village"]
		var fixed: Dictionary = original.duplicate(true) if original is Dictionary else {}
		for key in village_plan.DEFAULTS:
			if fixed.has(key) and not village_plan.valid_site({key:fixed[key]}): fixed.erase(key)
		fixed["enabled"] = false
		raw["village"] = fixed
		note(path+"/village","Disabled malformed village settings and kept the facility.",original)
	var cycle_plan = preload("res://scripts/builder/cycling_plan.gd")
	if raw.has("cycling") and not cycle_plan.valid_vehicle(raw["cycling"]):
		var original_cycle: Variant = raw["cycling"]
		var fixed_cycle: Dictionary = original_cycle.duplicate(true) if original_cycle is Dictionary else {}
		fixed_cycle["enabled"] = false
		for key in ["npc","rack"]:
			if fixed_cycle.has(key) and not cycle_plan.valid_vehicle({key:fixed_cycle[key]}): fixed_cycle.erase(key)
		raw["cycling"] = fixed_cycle
		note(path+"/cycling","Disabled malformed riding settings and kept the cycle.",original_cycle)
	if raw.has("prop") and not preload("res://scripts/builder/prop_plan.gd").valid(raw["prop"]):
		var original_prop: Variant=raw["prop"]; var fixed_prop: Dictionary={"kind":"none","enabled":false}
		if original_prop is Dictionary:
			fixed_prop=original_prop.duplicate(true)
			for key in original_prop:
				if not preload("res://scripts/builder/prop_plan.gd").valid({key:original_prop[key]}): fixed_prop.erase(key)
			fixed_prop["enabled"]=false
		raw=raw.duplicate(true); raw["prop"]=fixed_prop; note(path+"/prop","Disabled malformed prop interaction controls and retained readable settings.",original_prop)
	if raw.has("audio") and not preload("res://scripts/builder/ambience_plan.gd").valid_source(raw["audio"]):
		var original_audio: Variant=raw["audio"]; var fixed_audio: Dictionary={"kind":"none","enabled":false}
		if original_audio is Dictionary:
			fixed_audio=original_audio.duplicate(true)
			for key in original_audio:
				if not preload("res://scripts/builder/ambience_plan.gd").valid_source({key:original_audio[key]}): fixed_audio[key]={"kind":"none","enabled":false,"volume":1.0,"range":24.0}[key]
		raw=raw.duplicate(true); raw["audio"]=fixed_audio; note(path+"/audio","Repaired source audio controls; object content was retained.",original_audio)
	if raw.has("school"):
		var schools=preload("res://scripts/builder/school_plan.gd")
		if depth>0 or not schools.eligible(raw) or not schools.valid(raw["school"]):
			note(path+"/school","Archived invalid school settings and retained the building.",raw["school"])
			raw=raw.duplicate(true)
			raw.erase("school")
	if raw.has("transit_stop") and not raw["transit_stop"] is bool:
		note(path+"/transit_stop","Disabled an unreadable transit-stop designation.",raw["transit_stop"]); raw=raw.duplicate(true); raw["transit_stop"]=false
	if raw.has("zone_uid") and (not raw["zone_uid"] is String or raw["zone_uid"].length()>128):
		note(path+"/zone_uid","Removed an unreadable lot association; the object was retained.",raw["zone_uid"]); raw=raw.duplicate(true); raw.erase("zone_uid")
	if raw.has("city_service"):
		var original: Variant=raw["city_service"]
		var plan=preload("res://scripts/builder/service_plan.gd")
		if not original is Dictionary:
			note(path+"/city_service","Disabled an unreadable city service station.",original)
			raw=raw.duplicate(true); raw["city_service"]={"kind":"none"}
		else:
			var fixed: Dictionary=plan.profile({"city_service":original})
			for key in fixed:
				if original.has(key) and not plan.valid_profile({key:original[key]}):
					note(path+"/city_service/"+key,"Reset or clamped an invalid station setting.",original[key])
					raw=raw.duplicate(true); raw["city_service"][key]=fixed[key]
	if raw.has("catalog_behavior_revision") and not preload("res://scripts/builder/catalog_defaults.gd").valid_revision(raw["catalog_behavior_revision"]):
		note(path+"/catalog_behavior_revision", "Kept this placement on its legacy catalog behavior after an invalid revision.", raw["catalog_behavior_revision"])
		raw=raw.duplicate(true); raw["catalog_behavior_revision"]=0
	if raw.has("business"):
		var original: Variant=raw["business"]
		var plan=preload("res://scripts/builder/business_plan.gd")
		if not original is Dictionary:
			note(path+"/business","Disabled an unreadable business definition.",original)
			raw=raw.duplicate(true); raw["business"]={"kind":"none"}
		else:
			var fixed: Dictionary=plan.profile({"business":original})
			for key in fixed:
				if original.has(key) and not plan.valid({key:original[key]}):
					note(path+"/business/"+key,"Reset or clamped an invalid business setting.",original[key])
					raw=raw.duplicate(true); raw["business"][key]=fixed[key]
	if raw.has("traffic_control") and not preload("res://scripts/builder/traffic_control_plan.gd").valid(raw["traffic_control"]):
		note(path+"/traffic_control","Archived an invalid traffic control and preserved its sign or signal.",raw["traffic_control"])
		raw=raw.duplicate(true); raw.erase("traffic_control")
	if raw.has("traffic_parking") and not raw["traffic_parking"] is bool:
		note(path+"/traffic_parking","Disabled an unreadable parking designation.",raw["traffic_parking"])
		raw=raw.duplicate(true); raw["traffic_parking"]=false
	if raw.has("citizen_role") and (not raw["citizen_role"] is String or not raw["citizen_role"] in ["home","work","shop","park","none"]):
		note(path+"/citizen_role","Disabled an unreadable citizen destination role.",raw["citizen_role"])
		raw=raw.duplicate(true); raw["citizen_role"]="none"
	if raw.has("neighborhood_palette_selection") and not preload("res://scripts/builder/neighborhood_palettes.gd").valid_selection(raw["neighborhood_palette_selection"]):
		note(path+"/neighborhood_palette_selection","Removed unreadable neighborhood selection notes; generated artwork and geometry were retained.",raw["neighborhood_palette_selection"])
		raw=raw.duplicate(true);raw.erase("neighborhood_palette_selection")
	var item: Dictionary = raw.duplicate(true)
	if not item.get("uid") is String or item["uid"].is_empty(): note(path+"/uid","Assigned a missing object ID.",item.get("uid")); item["uid"] = "repair_"+path.sha256_text().substr(0,20)
	if not Doc.numbers(item.get("position"),3):
		note(path+"/position","Recovered usable position components; unknown components use zero.",item.get("position"))
		var old: Variant = item.get("position")
		item["position"] = [0,0,0]
		if old is Array:
			for index in mini(3,old.size()):
				if Doc.numbers([old[index]],1): item["position"][index] = old[index]
	if item["position"].any(func(n:float)->bool:return absf(n)>MAX_COORDINATE):
		note(path+"/position","Clamped coordinates outside the supported editing range.",item["position"])
		for index in 3: item["position"][index] = clampf(item["position"][index],-MAX_COORDINATE,MAX_COORDINATE)
	if not Doc.numbers([item.get("scale")],1) or item["scale"] < .1 or item["scale"] > 8:
		note(path+"/scale","Reset or clamped invalid scale.",item.get("scale"))
		item["scale"] = clampf(item["scale"],.1,8) if Doc.numbers([item.get("scale")],1) else 1.0
	var id: String = str(item.get("asset",""))
	if id in [Assets.OBJECT_2D,Assets.OBJECT_3D,Assets.TILE_2D]: Assets.register(library)
	if id in [Assets.OBJECT_2D,Assets.OBJECT_3D,Assets.TILE_2D] and (not item.get("missing_asset") is Dictionary or not item["missing_asset"].get("id") is String or not item["missing_asset"].get("record") is Dictionary):
		note(path+"/missing_asset","Archived damaged placeholder metadata; the original source is unknown.",item.get("missing_asset"))
		item["missing_asset"] = {"id":"Unknown original asset","kind":"object","record":raw.duplicate(true)}
	if not Assets.available(id,library,availability):
		Assets.register(library)
		item["missing_asset"] = {"id":id,"kind":"object","record":raw.duplicate(true)}
		item["asset"] = Assets.OBJECT_3D if id.begins_with("3d:") or (not id.begins_with("2d:") and mode == "3d") else Assets.OBJECT_2D
		if library.assets.has(id): library.assets[id]["unavailable"] = true
		id = item["asset"]
		note(path+"/asset","Substituted a visible placeholder for the unavailable asset.",raw.get("asset"))
	if not id in [Assets.OBJECT_2D,Assets.OBJECT_3D,Assets.TILE_2D] and item.has("missing_asset"):
		note(path+"/missing_asset","Archived an obsolete placeholder marker on an available asset.",item["missing_asset"])
		item["recovered_missing_source"] = item["missing_asset"]
		item.erase("missing_asset")
	if item.has("missing_asset"):
		item.erase("school")
		item.erase("vehicle_care")
		item.erase("vehicle_bay")
		item.erase("market")
		for field in preload("res://scripts/builder/delivery_plan.gd").FIELDS: item.erase(field)
	if not item.get("direction") is String or not library.valid_direction(id,item["direction"]): note(path+"/direction","Reset invalid source view/rotation; its original is archived.",item.get("direction")); item["direction"] = library.directions(id)[0]
	for key in ["angle","tilt"]:
		if item.has(key):
			var values: Variant = [item[key]] if key == "angle" else item[key]
			if not Doc.numbers(values,1 if key == "angle" else 2): note(path+"/"+key,"Removed an invalid rotation.",item[key]); item.erase(key)
			elif values.any(func(n:float)->bool:return absf(n)>360000): note(path+"/"+key,"Normalized excessively large rotation.",item[key]); item[key] = fmod(item[key],360) if key == "angle" else [fmod(item[key][0],360),fmod(item[key][1],360)]
	for key in ["name","group"]:
		if item.has(key) and not item[key] is String: note(path+"/"+key,"Removed an invalid text field.",item[key]); item.erase(key)
	for key in ["visible","locked","open"]:
		if item.has(key) and not item[key] is bool: note(path+"/"+key,"Removed an invalid flag.",item[key]); item.erase(key)
	if item.has("layer") and (not item["layer"] is String or not item["layer"] in Layers.NAMES): note(path+"/layer","Removed an invalid layer assignment.",item["layer"]); item.erase("layer")
	if item.has("colors"):
		if item.has("missing_asset"): item.erase("colors")
		else: item["colors"] = colors(item["colors"],path+"/colors")
	if item.has("entrance_anchor") and (item.has("missing_asset") or not preload("res://scripts/builder/entrance_anchors.gd").valid(item["entrance_anchor"],id.begins_with("2d:"))): note(path+"/entrance_anchor","Archived an unusable entrance override.",item["entrance_anchor"]); item.erase("entrance_anchor")
	if item.has("interior"):
		if depth >= 4: note(path+"/interior","Quarantined a room beyond the supported nesting depth.",item["interior"]); item.erase("interior")
		else: item["interior"] = world(item["interior"],mode,path+"/interior",depth+1)
	return item

func colors(raw: Variant, path: String) -> Array:
	if not raw is Array: note(path,"Archived an invalid appearance collection.",raw); return []
	var result: Array = []
	for index in raw.size():
		var edit: Variant = raw[index]
		if not edit is Dictionary: note(path+"/"+str(index),"Archived an invalid appearance edit.",edit); continue
		var copy: Dictionary = edit.duplicate(true)
		if copy.get("pattern") is Dictionary and copy["pattern"].get("texture") is String and not Assets.texture_available(copy["pattern"]["texture"]): note(path+"/"+str(index),"Archived an unavailable pattern while retaining usable color settings.",copy["pattern"]); copy.erase("pattern")
		if copy.has("pattern") and not preload("res://scripts/builder/tile_patterns.gd").valid(copy["pattern"]): note(path+"/"+str(index),"Archived a damaged pattern while retaining usable color settings.",copy["pattern"]); copy.erase("pattern")
		if not preload("res://scripts/builder/part_colors.gd").valid([copy]): note(path+"/"+str(index),"Archived an invalid appearance edit.",edit); continue
		if copy.has("pattern") and not Assets.path_available(copy["pattern"]["texture"],{}): note(path+"/"+str(index),"Removed a missing pattern while retaining its base color.",copy["pattern"]); copy.erase("pattern")
		result.append(copy)
	return result

func roads(raw: Variant, path: String) -> Array:
	if not raw is Array: note(path,"Archived an invalid road collection.",raw); return []
	var result: Array = []
	var seen: Dictionary = {}
	for index in raw.size():
		var road: Variant = raw[index]
		var location: String = path+"/"+str(index)
		if not road is Dictionary or not Doc.numbers(road.get("cell"),2): note(location,"Quarantined a road without usable coordinates.",road); continue
		if absf(road["cell"][0]) > 100000 or absf(road["cell"][1]) > 100000: note(location,"Quarantined an out-of-range road.",road); continue
		var copy: Dictionary = road.duplicate(true)
		copy["cell"] = [roundi(copy["cell"][0]),roundi(copy["cell"][1])]
		if float(copy["cell"][0]) != float(road["cell"][0]) or float(copy["cell"][1]) != float(road["cell"][1]): note(location+"/cell","Rounded damaged road coordinates.",road["cell"])
		if seen.has(str(copy["cell"])) or result.size() >= 4096: note(location,"Quarantined a duplicate or excess road record.",road); continue
		seen[str(copy["cell"])] = true
		if not copy.get("crossing",false) is bool: note(location+"/crossing","Reset an invalid crossing flag.",copy["crossing"]); copy["crossing"] = false
		if copy.has("width") and (not Doc.numbers([copy["width"]],1) or (float(copy["width"]) != 2 and float(copy["width"]) != 6)): note(location+"/width","Reset an invalid road width.",copy["width"]); copy.erase("width")
		if copy.has("style") and not copy["style"] in ["asphalt","brick","gravel"]: note(location+"/style","Reset an invalid road surface.",copy["style"]); copy.erase("style")
		if copy.has("cycle_access") and not copy["cycle_access"] in ["none","shared","cycle"]:
			note(location+"/cycle_access","Reset unreadable cycle access.",copy["cycle_access"])
			copy.erase("cycle_access")
		if copy.has("sidewalks") and not copy["sidewalks"] is bool: note(location+"/sidewalks","Reset an invalid sidewalk flag.",copy["sidewalks"]); copy.erase("sidewalks")
		result.append(copy)
	return result

func workspace(raw: Variant) -> Dictionary:
	if not raw is Dictionary: note("workspace","Reset invalid workspace settings.",raw); return {}
	var result: Dictionary = raw.duplicate(true)
	for mode in result.keys():
		if not result[mode] is Dictionary: note("workspace/"+str(mode),"Reset invalid view settings.",result[mode]); result.erase(mode); continue
		clean_settings(result[mode],"workspace/"+str(mode))
	return result

func clean_settings(settings: Dictionary, path: String) -> void:
	for key in settings.keys():
		var value: Variant = settings[key]
		if key in ["custom","return_workspace"] and not path.ends_with("/presets"): continue
		if key in ["piece_selection","roads","ground_brush","arrange","layout","browser","presets","custom","return_workspace"] and value is Dictionary: clean_settings(value,path+"/"+key); continue
		var valid: bool = true
		if key in ["camera","pivot"]: valid = Doc.numbers(value,3 if key == "pivot" else 3 if path.ends_with("2d") else 6)
		elif key in ["query","category","tool","snap_target","style","pack","tab"]: valid = value is String
		elif key=="preset" and "/presets" in path: valid=value is String and value in ["custom","building","painting","exploring"]
		elif key=="walking" and "/presets" in path: valid=value is bool
		elif key in ["snap","repeat","surface","lanes","favorites","enabled","replace_only","protect_visible","sidewalks","library_open","inspector_open","advanced"]: valid = value is bool
		elif key in ["piece_selection","roads","ground_brush","arrange","layout","browser","presets","custom","return_workspace"]: valid = false
		elif key == "thumbnail_size": valid = (value is int or value is float) and float(value) in [96.0,128.0,192.0]
		elif key in ["library_width","inspector_width"]: valid = Doc.numbers([value],1)
		elif key in ["rotation_mode","expansion","rotation_step","asset_type","page","operation","width","pivot_mode","axis","gap"]: valid = Doc.numbers([value],1)
		if not valid: note(path+"/"+str(key),"Removed an invalid workspace setting.",value); settings.erase(key)
		elif key in ["library_width","inspector_width"] and (value < 220 or value > 600): note(path+"/"+str(key),"Clamped a panel width to its supported range.",value); settings[key] = clampf(value,220,600)
		elif key in ["camera","pivot"] and value is Array and value.any(func(n:float)->bool:return absf(n)>MAX_COORDINATE):
			note(path+"/"+str(key),"Clamped out-of-range workspace coordinates.",value)
			for index in value.size(): value[index] = clampf(value[index],-MAX_COORDINATE,MAX_COORDINATE)
		elif key in ["rotation_mode","expansion","rotation_step","asset_type","page","operation","width","pivot_mode","axis","gap"] and (value is int or value is float) and absf(value)>MAX_COORDINATE: note(path+"/"+str(key),"Clamped an out-of-range workspace value.",value); settings[key] = clampf(value,-MAX_COORDINATE,MAX_COORDINATE)
