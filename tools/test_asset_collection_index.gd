extends SceneTree
const OUT="res://output/verification/asset_expansion/U15/"
const Plan=preload("res://scripts/builder/asset_collections.gd")
const Index=preload("res://scripts/builder/asset_collection_index.gd")
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT);FileAccess.open(OUT+".gdignore",FileAccess.WRITE).close()
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new();var index:=Index.new();var found: Array[Dictionary]=[];found.assign(library.assets.values());var before: Array[Dictionary]=found.duplicate()
	check(not index.active() and index.filter(found,library)==before,"No named collection leaves ordinary library filtering unchanged")
	var full: Dictionary=Plan.migrate_favorites(Plan.empty(),library.assets.keys(),library)["data"]["collections"][0];var start: int=Time.get_ticks_msec();check(index.choose(full,library)["ok"] and index.builds==1,"A selected full-catalog collection compiles availability once");var compile_ms: int=Time.get_ticks_msec()-start
	var filtered: Array[Dictionary]=index.filter(found,library);var initial: Array=filtered.map(func(item: Dictionary):return item["id"]);var builds: int=index.builds
	index.choose(full,library);check(index.builds==builds,"Unchanged selection metadata does not rebuild source availability")
	start=Time.get_ticks_msec()
	for query in 100:index.filter(found,library)
	var repeated_ms: int=Time.get_ticks_msec()-start
	check(index.builds==builds and index.filter(found,library).map(func(item: Dictionary):return item["id"])==initial,"Repeated searches reuse compiled identities without rescanning prepared sources")
	check(found==before,"Named filtering preserves input order, descriptors and source results")
	var empty: Dictionary={"uid":"empty_collection","name":"Empty collection","entries":[]};index.choose(empty,library);check(index.active() and index.filter(found,library).is_empty(),"An explicitly selected empty collection remains distinguishable from Browse all")
	var one: Dictionary=Plan.asset_entry("3d:HanX_School/Student_Chair",library)["entry"];var chosen: Dictionary={"uid":"one","name":"One chair","entries":[one]};index.choose(chosen,library);chosen["entries"]=[];check(index.filter(found,library).map(func(item: Dictionary):return item["id"])==[one["id"]],"The compiled selection owns its snapshot instead of sharing mutable editor input")
	var descriptor: Dictionary=library.assets[one["id"]].duplicate(true);library.assets[one["id"]]["path"]=OUT+"missing_prepared_scene.tscn";index.refresh(library,true);check(index.filter(found,library).is_empty() and index.resolved["missing"].size()==1,"Explicit refresh discovers unavailable prepared sources without losing their identifiable reference")
	library.assets[one["id"]]=descriptor.duplicate(true);index.refresh(library,true);check(index.filter(found,library).size()==1,"Explicit source restoration refresh restores the exact selected member")
	var copied: String=OUT+"cached_chair_fixture.tscn";var content: String=FileAccess.get_file_as_string(descriptor["path"]);FileAccess.open(copied,FileAccess.WRITE).store_string(content);library.assets[one["id"]]["path"]=copied;var cached: Resource=load(copied)
	check(cached!=null and ResourceLoader.exists(copied),"Private prepared source is actually loaded into Godot's resource cache")
	if ProjectSettings.globalize_path(copied).begins_with(ProjectSettings.globalize_path(OUT)):check(DirAccess.remove_absolute(ProjectSettings.globalize_path(copied))==OK,"Only the explicit private fixture copy is removed")
	index.refresh(library,true);check(ResourceLoader.exists(copied) and index.filter(found,library).is_empty(),"A cached scene does not hide its genuinely removed prepared source")
	FileAccess.open(copied,FileAccess.WRITE).store_string(content);index.refresh(library,true);check(index.filter(found,library).size()==1,"Restoring the exact private prepared source restores availability even with a warm resource cache");library.assets[one["id"]]=descriptor.duplicate(true)
	var custom: Dictionary=descriptor.duplicate(true);custom["id"]="3d:Custom/Collection_Index_Only";custom["name"]="Private index fixture";library.assets[custom["id"]]=custom
	var private_collection: Dictionary={"uid":"private","name":"Private references","entries":[Plan.asset_entry(custom["id"],library)["entry"]]};index.choose(private_collection,library);var private_found: Array[Dictionary]=[custom]
	check(index.filter(private_found,library).size()==1,"Private descriptor identities remain local usable references")
	library.assets.erase(custom["id"]);library.rebuild_indexes();index.refresh(library);check(index.filter(private_found,library).is_empty() and index.resolved["ids"].has(custom["id"]),"Actual library rebuild invalidates availability while retaining a removed private ID")
	library.assets[custom["id"]]=custom;library.rebuild_indexes();check(index.filter(private_found,library).size()==1,"Restoring and rebuilding actual catalog indexes refreshes the compiled collection")
	index.clear();check(not index.active() and index.filter(found,library)==before,"Clear returns to the original library without altering collection records")
	FileAccess.open(OUT+"index_performance.json",FileAccess.WRITE).store_string(JSON.stringify({"catalog_entries":library.assets.size()-1,"available_snapshot_entries":initial.size(),"compile_ms":compile_ms,"cached_full_catalog_filters":100,"cached_filter_total_ms":repeated_ms,"cached_filter_average_ms":float(repeated_ms)/100.0},"\t"))
	print("ASSET COLLECTION INDEX: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
