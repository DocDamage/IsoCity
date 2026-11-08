extends RefCounted

const CONDITIONS: Array[String]=["clear","rain","snow","wind"]
const SEASONS: Array[String]=["spring","summer","autumn","winter"]
const PATH: String="res://resources/catalog/weather.json"
static var catalog: Dictionary={}

static func defaults() -> Dictionary:
	return {"enabled":false,"condition":"clear","season":"summer","intensity":.65,"wind":.35,"wind_direction":225.0,"seed":1,"foliage":true,"affect_activity":false,"cycle_seasons":false,"season_seconds":600.0}

static func valid_settings(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key in ["enabled","foliage","affect_activity","cycle_seasons"]:
		if value.has(key) and not value[key] is bool: return false
	if value.has("condition") and not value["condition"] in CONDITIONS: return false
	if value.has("season") and not value["season"] in SEASONS: return false
	for key in ["intensity","wind","wind_direction","seed","season_seconds"]:
		if not value.has(key): continue
		var n: Variant=value[key]
		if not (n is int or n is float) or not is_finite(float(n)): return false
		if key in ["intensity","wind"] and (n<0 or n>1): return false
		if key=="wind_direction" and (n<0 or n>360): return false
		if key=="seed" and (n!=floor(n) or n<0 or n>2147483647): return false
		if key=="season_seconds" and (n<30 or n>86400): return false
	return true

static func settings(data: Dictionary) -> Dictionary:
	var result: Dictionary=defaults(); var raw: Variant=data.get("weather",{})
	if valid_settings(raw):
		for key in result:
			if raw.has(key): result[key]=raw[key]
	return result

static func state(data: Dictionary,elapsed: float=0) -> Dictionary:
	var value: Dictionary=settings(data); var season_index: int=SEASONS.find(value["season"])
	if value["enabled"] and value["cycle_seasons"] and is_finite(elapsed): season_index=posmod(season_index+floori(maxf(0,elapsed)/float(value["season_seconds"])),4)
	value["effective_season"]=SEASONS[season_index]
	value["rain"]=float(value["intensity"]) if value["enabled"] and value["condition"]=="rain" else 0.0
	value["snow"]=float(value["intensity"]) if value["enabled"] and value["condition"]=="snow" else 0.0
	var strength: float=float(value["wind"]) if value["enabled"] else 0.0
	if value["enabled"] and value["condition"]=="wind": strength=maxf(strength,float(value["intensity"]))
	value["wind_vector"]=Vector2.from_angle(deg_to_rad(float(value["wind_direction"]))) * strength
	var severity: float=maxf(value["rain"],maxf(value["snow"],strength*.6))
	value["avoid_parks"]=value["enabled"] and value["affect_activity"] and severity>=.3
	value["walking_speed"]=1.0-.25*severity if value["enabled"] and value["affect_activity"] else 1.0
	return value

static func foliage(asset: String) -> String:
	if catalog.is_empty(): catalog=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return str(catalog.get("foliage",{}).get(asset,""))

static func leaf(color: Color) -> bool:
	return color.a>.05 and color.g>color.r*1.07 and color.g>color.b*1.03 and color.g>.08

static func seasonal_color(original: Color,season: String,kind: String,variation: float=0) -> Color:
	if season not in SEASONS: return original
	var blossom: bool=kind=="blossom" and original.a>.05 and original.r>original.g*1.12 and original.b>original.g*1.05 and original.r>.3
	if (not leaf(original) and not blossom) or (season=="summer" and not blossom) or kind.is_empty(): return original
	var tint:=Color.WHITE
	match season:
		"spring":
			if blossom: return original
			tint=Color(.68,1.0,.48)
		"summer": tint=Color(.35,.85,.18)
		"autumn":
			if kind not in ["deciduous","blossom"]: return original
			tint=Color(1,.72,.12).lerp(Color(.92,.22,.06),clampf(variation,0,1))
		"winter": tint=Color(.82,.9,.94)
	var light: float=maxf(original.r,maxf(original.g,original.b))
	if season=="winter": light=lerpf(light,1,.35)
	var result: Color=original.lerp(Color(tint.r*light,tint.g*light,tint.b*light,original.a),.85 if season=="winter" else .8)
	result.a=original.a; return result

static func target(resident: Dictionary,hour: float,weather: Dictionary) -> String:
	var daily=preload("res://scripts/builder/citizen_plan.gd")
	if weather.get("avoid_parks",false) and daily.activity(hour,resident.get("offset",0))=="park": return str(resident.get("home",""))
	return daily.destination(resident,hour)
