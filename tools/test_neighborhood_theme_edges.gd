extends "res://tools/test_neighborhood_palettes.gd"
func run() -> void:
	library=preload("res://scripts/builder/asset_library.gd").new()
	for mode in ["2d","3d"]:
		var source: Dictionary=preload("res://scripts/builder/templates.gd").make(mode,"blank");var config: Dictionary=Plan.defaults();config.merge({"theme":"village","blocks":1,"density":100,"seed":17},true);var result: Dictionary=Plan.generate(source,config,library);check(result["ok"],"Reviewed edge fixture starts from a real permitted district: "+mode)
		if not result["ok"]:continue
		var original: Dictionary=Palettes.definitions().duplicate(true);var retired: Dictionary=original.duplicate(true);retired["palettes"]["village"]["revision"]="ab".repeat(32);retired["palettes"]["village"]["families"]=[];Palettes.cached=retired
		check(Document.valid(result["data"],mode,library),"Existing generated objects and exact historical notes survive retirement of a palette's design list: "+mode);check(not Plan.generate(source,config,library)["ok"],"A retired design list cannot generate new unreviewed substitutes: "+mode);Palettes.cached=original
		var poor: Dictionary=source.duplicate(true);poor["economy"]={"enabled":true,"starting_cash":1};var poor_before: String=JSON.stringify(poor);var costly: Dictionary=Plan.generate(poor,config,library);check(costly["ok"] and not costly["affordable"] and costly["quote"]["reason"].contains("budget") and JSON.stringify(poor)==poor_before,"An unaffordable complete proposal remains reviewable without charging or mutating the original: "+mode)
		var funded: Dictionary=source.duplicate(true);funded["economy"]={"enabled":true,"starting_cash":100000};var bought: Dictionary=Plan.generate(funded,config,library);check(bought["ok"] and bought["affordable"] and bought["data"]["economy_account"]["cash"]==100000-bought["quote"]["net"],"Actual combined buildings, scenery, paving and roads settle at the ordinary quoted price: "+mode)
		var small: Dictionary=source.duplicate(true);small["terrain"]={"enabled":true,"bounds":[-4,-4,8,8]};small["terrain_vertices"]=[];small["water_cells"]=[];var outside: Dictionary=Plan.generate(small,config,library);check(outside["ok"] and outside["data"]["terrain"]==small["terrain"] and preload("res://scripts/builder/city_foundation.gd").bounds(outside["data"]).encloses(outside["bounds"]),"A smaller sculpted region keeps its authored bounds while the existing foundation supports the district: "+mode)
		var policy: Dictionary=preload("res://scripts/builder/asset_collections.gd").project_empty();policy["restricted"]=true;library.set_project_palette(policy);var restricted: Dictionary=Plan.generate(source,config,library);check(not restricted["ok"] and (restricted["reason"].contains("permit") or restricted["reason"].contains("palette")),"A restrictive project cannot silently generate disallowed palette content: "+mode);library.set_project_palette({})
		var hidden: Dictionary=source.duplicate(true);hidden["layers"]={"Buildings":{"locked":true}};check(not Plan.generate(hidden,config,library)["ok"],"Protected building layers prevent a complete district mutation: "+mode)
		var missing=preload("res://scripts/builder/asset_library.gd").new();config["theme"]="industrial"
		for id in Palettes.palettes()["industrial"][mode]:missing.assets[id]=missing.assets[id].duplicate(true);missing.assets[id]["unavailable"]=true
		var absent: Dictionary=Plan.generate(source,config,missing);check(not absent["ok"] and absent["reason"].contains("No installed"),"Absent industrial sources produce a useful reason with no unrelated filler: "+mode)
		var appearances: Dictionary={};config["theme"]="village";var palette: Dictionary=Palettes.palettes()["village"]
		for seed_value in range(1,257):
			var appearance: Dictionary=Palettes.appearance_choice(palette,seed_value);var key: String=JSON.stringify(appearance)
			if appearances.has(key):continue
			config["seed"]=seed_value;var variant: Dictionary=Plan.generate(source,config,library);check(variant["ok"] and variant["data"]["objects"].all(func(item: Dictionary):return Palettes.matches_appearance(item["asset"],appearance,library)),"A newly reached palette/lighting appearance generates as a coherent full district: "+mode+key);appearances[key]=true
			if appearances.size()==palette["appearances"].size():break
		check(appearances.size()==18,"Every supplied Village appearance is reachable without mixing palettes within a district: "+mode)
	print("NEIGHBORHOOD THEME EDGES: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
