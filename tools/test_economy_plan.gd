extends SceneTree
const Plan=preload("res://scripts/builder/economy_plan.gd")
const Doc=preload("res://scripts/builder/document.gd")
var checks: int=0
var failures: int=0
var library: RefCounted
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func blank(mode: String,cash: int=5000) -> Dictionary:
	var data: Dictionary=preload("res://scripts/builder/templates.gd").make(mode,"blank")
	data["economy"]={"enabled":true,"starting_cash":cash,"refund_percent":25,"period_seconds":60}
	return data
func add(data: Dictionary,uid: String,asset: String) -> Dictionary:
	var item: Dictionary={"uid":uid,"asset":asset,"position":[0,0,0],"direction":library.directions(asset)[0],"scale":1.0}
	data["objects"].append(item); return item
func buy(before: Dictionary,after: Dictionary) -> Dictionary:
	var quote: Dictionary=Plan.quote(before,after,library)
	if quote.get("ok",false) and quote.get("enabled",false): after["economy_account"]=quote["account"]
	return quote
func run() -> void:
	library=preload("res://scripts/builder/asset_library.gd").new()
	check(not Plan.settings({})["enabled"],"Creative mode is the default")
	check(Plan.valid_settings({"extension":"keep"}) and Plan.valid_settings(Plan.SETTINGS),"Settings are optional and retain extensions")
	for value in [null,[],"yes",true,1]: check(not Plan.valid_settings(value),"Reject malformed settings: "+str(value))
	for key in Plan.RANGES:
		for value in [-1,1.5,INF,NAN,"100",true,Plan.RANGES[key][1]+1]:
			check(not Plan.valid_settings({key:value}),"Settings reject non-integer, non-finite and out-of-range values: "+key+" "+str(value))
		check(Plan.valid_settings({key:Plan.RANGES[key][0]}) and Plan.valid_settings({key:Plan.RANGES[key][1]}),"Accept exact setting boundaries: "+key)
	check(not Plan.valid_settings({"enabled":1}) and not Plan.settings({"economy":{"enabled":1}})["enabled"],"Enabled requires an actual boolean")
	check(Plan.settings({"economy":{"starting_cash":-9,"period_seconds":2.8,"refund_percent":105}})=={"enabled":false,"starting_cash":0,"period_seconds":10,"refund_percent":100},"Repair clamps and rounds known settings")
	for asset in library.assets:
		var profile: Dictionary=Plan.profile(asset,library)
		check(["construction","upkeep","income"].all(func(key: String):return Plan.integer(profile[key],0,Plan.LIMIT)),"Every installed asset has bounded integer economy rates: "+asset)
	check(Plan.profile("2d:House_Blue",library)["kind"]=="home" and Plan.profile("2d:Coffee_Shop",library)["kind"]=="shop" and Plan.profile("2d:Hopital",library)["kind"]=="station","Home, shop and civic prices use explicit catalog roles")
	check(Plan.profile("2d:House_Made_Up_Hospital_Shop",library)["kind"]=="object","Names do not infer earning or civic behavior")
	check(Plan.road_profile({"cell":[0,0]})["construction"]==240 and Plan.road_profile({"width":2,"sidewalks":false,"style":"gravel"})["construction"]==60 and Plan.road_profile({"style":"brick","crossing":true})["construction"]==310,"Road prices reflect actual width, surface, sidewalks and crossing")
	for mode in ["2d","3d"]:
		var home: String="2d:House_Blue" if mode=="2d" else "3d:HanX_City/Row_Houses_A"
		var work: String="2d:Office_Tower" if mode=="2d" else "3d:HanX_City/Office_Building_A"
		# Select the catalog's real work asset rather than depend on pack naming.
		if not library.assets.has(work):
			for asset in library.assets:
				if library.assets[asset]["mode"]==mode and Plan.profile(asset,library)["kind"]=="work": work=asset; break
		var data: Dictionary=blank(mode); add(data,"starter",home)
		data["economy_account"]=Plan.fresh_account(data,library)
		check(Plan.valid_account(data["economy_account"]) and data["economy_account"]["cash"]==5000 and data["economy_account"]["holdings"].values()[0]["paid"]==0,"Activation grants the chosen budget and gives existing content no refundable basis: "+mode)
		var removed: Dictionary=data.duplicate(true); removed["objects"].clear()
		var quote: Dictionary=buy(data,removed)
		check(quote["refund"]==0 and removed["economy_account"]["cash"]==5000,"Demolishing a free starting building cannot mint credits: "+mode)
		var next: Dictionary=data.duplicate(true); add(next,"paid",home)
		var untouched: Dictionary=data.duplicate(true)
		quote=buy(data,next)
		check(quote["construction"]==2000 and quote["refund"]==0 and next["economy_account"]["cash"]==3000 and data==untouched,"New construction spends credits without mutating the source: "+mode)
		check(next["economy_account"]["construction_total"]==2000 and next["economy_account"]["ledger"].size()==1,"Construction records its actual paid basis and ledger total: "+mode)
		var moved: Dictionary=next.duplicate(true); moved["objects"][1].merge({"position":[42,17,0],"scale":3.0,"angle":90,"name":"Moved","visible":false,"locked":true,"citizen_role":"shop"},true)
		quote=buy(next,moved)
		check(quote["construction"]==0 and quote["refund"]==0 and moved["economy_account"]==next["economy_account"],"Moving, scaling, rotating, renaming, hiding and role edits do not rebuy an existing object: "+mode)
		check(Plan.forecast(next,library)==Plan.forecast(moved,library),"Hiding assets and changing visitor roles cannot evade upkeep or invent income: "+mode)
		removed=next.duplicate(true); removed["objects"].remove_at(1); quote=buy(next,removed)
		check(quote["refund"]==500 and removed["economy_account"]["cash"]==3500 and removed["economy_account"]["refund_total"]==500,"Demolition refunds the configured percentage of the paid basis: "+mode)
		var replaced: Dictionary=next.duplicate(true); replaced["objects"][1]["asset"]=work; replaced["objects"][1]["direction"]=library.directions(work)[0]
		quote=buy(next,replaced)
		check(quote["construction"]==3500 and quote["refund"]==500 and replaced["economy_account"]["cash"]==0,"Replacement is a real new purchase with the old paid refund: "+mode)
		var denied: Dictionary=replaced.duplicate(true); add(denied,"too_expensive",home); var denied_source: Dictionary=denied.duplicate(true)
		quote=buy(replaced,denied)
		check(not quote["ok"] and "Insufficient" in quote["reason"] and denied==denied_source and replaced["economy_account"]["cash"]==0,"Over-budget quotes reject atomically without changing either document: "+mode)
		var renamed: Dictionary=data.duplicate(true); renamed["economy"]["starting_cash"]=999999
		check(Plan.account(renamed,library)["cash"]==5000,"Changing the starting-budget preference cannot silently replenish an active treasury: "+mode)
		var no_account: Dictionary=blank(mode); add(no_account,"starter",home); next=no_account.duplicate(true); add(next,"new",home)
		check(Plan.quote(no_account,next,library)["account"]["cash"]==3000,"An absent purchase book adopts the before-city, so new construction is still charged: "+mode)
		var off: Dictionary=next.duplicate(true); off["economy"]["enabled"]=false
		var creative: Dictionary=off.duplicate(true); add(creative,"free",home)
		check(Plan.quote(off,creative,library)["ok"] and not Plan.quote(off,creative,library)["enabled"] and not Plan.settle(off,library)["ok"],"Creative mode permits unlimited construction and pauses accounting: "+mode)
		# Nested rooms have separate identities, no duplicated commercial income,
		# and purchases are refunded when the owning building is demolished.
		var nested: Dictionary=blank(mode); var host: Dictionary=add(nested,"host",home); host["interior"]=blank(mode)
		add(host["interior"],"same",home); add(nested,"same",home)
		nested["economy_account"]=Plan.fresh_account(nested,library)
		check(Plan.inventory(nested,library).size()==3 and Plan.forecast(nested,library)["income"]==90,"Nested and exterior IDs cannot collide, and room buildings cannot generate extra tax income: "+mode)
		next=nested.duplicate(true); add(next["objects"][0]["interior"],"paid_furniture",home); quote=buy(nested,next)
		check(quote["construction"]==2000 and next["economy_account"]["cash"]==3000,"Room construction shares the owning city's purchase book: "+mode)
		removed=next.duplicate(true); removed["objects"].remove_at(0); quote=buy(next,removed)
		check(quote["refund"]==500 and removed["economy_account"]["holdings"].size()==1,"Removing a host refunds paid room contents once and retires nested holdings: "+mode)
		var roads: Dictionary=blank(mode); roads["economy_account"]=Plan.fresh_account(roads,library)
		next=roads.duplicate(true); next["roads"]=[{"cell":[0,0]}]; quote=buy(roads,next)
		check(quote["construction"]==240 and Plan.forecast(next,library)["upkeep"]==2,"Road construction and maintenance are part of the budget: "+mode)
		var resurfaced: Dictionary=next.duplicate(true); resurfaced["roads"][0].merge({"width":2,"sidewalks":false},true); quote=buy(next,resurfaced)
		check(quote["construction"]==80 and quote["refund"]==60,"Road resurfacing uses actual old purchase basis rather than creating a free upgrade: "+mode)
		var doc:=Doc.new(); doc.data=data.duplicate(true); doc.checkpoint(); add(doc.data,"undo_purchase",home)
		quote=buy(doc.pending_before,doc.data); doc.finish_checkpoint()
		check(doc.undo() and doc.data==data,"Undo restores the construction and treasury together: "+mode)
		check(doc.redo() and doc.data["economy_account"]["cash"]==3000 and doc.data["economy_account"]["holdings"].size()==2,"Redo restores the exact purchase without charging twice: "+mode)
		var rates: Dictionary=Plan.forecast(doc.data,library); var settled: Dictionary=Plan.settle(doc.data,library)
		check(settled["income"]==90 and settled["upkeep"]==24 and settled["account"]["cash"]==3066 and settled["account"]["period"]==1,"An accounting period settles concrete building income and operating costs: "+mode)
		check(doc.data["economy_account"]["period"]==0 and settled["account"]["income_total"]==90 and settled["account"]["upkeep_total"]==24,"Settlement is a pure proposal with cumulative totals: "+mode)
		check(Doc.valid(doc.data,mode,library) and Doc.valid(JSON.parse_string(JSON.stringify(doc.data)),mode,library),"Settings and purchase history survive normal project validation and JSON round trips: "+mode)
		var missing: Dictionary=doc.data.duplicate(true); missing["objects"][0]["missing_asset"]={"id":"absent"}
		check(Plan.forecast(missing,library)["income"]==rates["income"]-45 and Plan.forecast(missing,library)["upkeep"]==rates["upkeep"]-12,"Missing-asset placeholders cannot earn income or incur fictitious upkeep: "+mode)
	var tiles: Dictionary=blank("2d"); tiles["economy_account"]=Plan.fresh_account(tiles,library)
	var tile_asset: String=""
	for asset in library.assets:
		if library.assets[asset]["mode"]=="2d" and library.is_ground_tile(asset): tile_asset=asset; break
	var tiled: Dictionary=tiles.duplicate(true); tiled["tiles"]=[{"cell":[1,2],"asset":tile_asset,"direction":library.directions(tile_asset)[0]}]
	var quote: Dictionary=buy(tiles,tiled)
	check(quote["construction"]==10 and tiled["economy_account"]["cash"]==4990,"Painted native ground participates in construction spending")
	var paint: Dictionary=tiled.duplicate(true); paint["tiles"][0]["direction"]=library.directions(tile_asset)[0]; paint["tiles"][0]["colors"]=[]
	check(Plan.quote(tiled,paint,library)["construction"]==0,"Tile appearance changes preserve the purchase basis")
	var debts: Dictionary=blank("2d",0); add(debts,"civic","2d:Hopital"); debts["economy_account"]=Plan.fresh_account(debts,library)
	var settled: Dictionary=Plan.settle(debts,library); debts["economy_account"]=settled["account"]
	check(settled["upkeep"]==140 and debts["economy_account"]["cash"]==-140,"Operating costs can create debt instead of silently disappearing")
	var denied: Dictionary=debts.duplicate(true); add(denied,"new","2d:House_Blue")
	check(not Plan.quote(debts,denied,library)["ok"],"Debt prevents new construction")
	var demolished: Dictionary=debts.duplicate(true); demolished["objects"].clear(); quote=buy(debts,demolished)
	check(quote["ok"] and demolished["economy_account"]["cash"]==-140 and Plan.forecast(demolished,library)["upkeep"]==0,"Demolition remains possible during debt and actually stops ongoing costs")
	for index in 80:
		settled=Plan.settle(debts,library); debts["economy_account"]=settled["account"]
	check(debts["economy_account"]["ledger"].size()==64 and debts["economy_account"]["period"]==81 and debts["economy_account"]["upkeep_total"]==11340,"Ledger storage is bounded while lifetime totals retain all periods")
	var overflow: Dictionary=blank("2d"); add(overflow,"home","2d:House_Blue"); overflow["economy_account"]=Plan.fresh_account(overflow,library); overflow["economy_account"]["cash"]=Plan.LIMIT
	check(not Plan.settle(overflow,library)["ok"] and overflow["economy_account"]["period"]==0,"Treasury limits reject overflow without advancing the period")
	var original: Dictionary=overflow.duplicate(true); original["economy"]["extension"]="preserve"; original["economy"]["period_seconds"]=3; original["economy_account"]["cash"]="damaged"
	original["economy_account"]["extension"]="preserve"; original["economy_account"]["holdings"]["bad"]={"token":"a","paid":-1}; original["economy_account"]["ledger"]=[{"kind":"period"}]
	check(not Doc.valid(original,"2d",library),"Document validation rejects damaged treasury data")
	var repair=preload("res://scripts/builder/project_repair.gd").new(library); var repaired: Dictionary=repair.world(original,"2d","world",0)
	check(Doc.valid(repaired,"2d",library) and repaired["economy"]["period_seconds"]==10 and repaired["economy_account"]["cash"]==0,"Project repair fixes settings and never substitutes a fresh grant for damaged cash")
	check(repaired["economy_account"]["holdings"].size()==1 and repaired["economy_account"]["ledger"].is_empty() and repaired["economy_account"]["extension"]=="preserve" and repaired["economy"]["extension"]=="preserve","Repair keeps valid purchases and extensions while dropping invalid rows")
	check(original["economy_account"]["cash"]=="damaged" and not repair.issues.is_empty() and repair.issues.back()["original"]["cash"]=="damaged","Repair archives original financial data and preserves the input source")
	original["economy"]="yes"; original["economy_account"]=[]; repaired=repair.world(original,"2d","world",0)
	check(Doc.valid(repaired,"2d",library) and not Plan.settings(repaired)["enabled"] and repaired["economy_account"]["cash"]==0,"Unreadable economy definitions disable safely without granting cash")
	for field in ["cash","period","income_total","upkeep_total","construction_total","refund_total"]:
		for value in [null,true,"1",1.25,INF,NAN,Plan.LIMIT+1]:
			var broken: Dictionary=Plan.fresh_account(tiles,library); broken[field]=value
			check(not Plan.valid_account(broken),"Account rejects invalid integer amounts: "+field+" "+str(value))
	var fractional: Dictionary=blank("2d"); fractional["economy"]["refund_percent"]=1; fractional["economy_account"]=Plan.fresh_account(fractional,library)
	var built: Dictionary=fractional.duplicate(true); built["roads"]=[{"cell":[0,0],"width":2,"sidewalks":false,"style":"gravel"}]; buy(fractional,built)
	var erased: Dictionary=built.duplicate(true); erased["roads"].clear()
	check(Plan.quote(built,erased,library)["refund"]==0,"Fractional-credit refunds round down deterministically")
	print("ECONOMY PLAN: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
