extends SceneTree
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;print("FAIL: "+message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new()
	check(library.themes.definitions.size()==6,"Independent project retains six visual collection definitions")
	var definitions: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/catalog/asset_themes.json"))
	check(not definitions.has("packs") and not definitions.has("assets"),"Export contains collection definitions rather than full source-group assignment rules")
	var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/catalog/asset_theme_metadata.json"))["assets"]
	check(metadata.size()==library.assets.size() and metadata.size()<40,"Theme metadata contains only selected assets and actual runtime dependencies")
	check(library.themes.matches(library.assets["2d:Coffee_Shop"],"pixel_city"),"Pixel-city building retains its theme")
	var shared: bool=false;var model: bool=false
	for asset in library.assets.values():
		if library.themes.matches(asset,"village") and library.themes.matches(asset,"historical"):
			shared=true;check(library.icon(asset["id"])!=null,"Shared tile retains actual artwork")
		if library.themes.matches(asset,"space"):
			model=true;check(asset["mode"]=="3d" and library.icon(asset["id"])!=null,"Space model retains prepared source and thumbnail")
	check(shared and model,"Mixed-world package preserves overlapping terrain and model collections")
	var found: Array=library.find("all","All assets","space",[],false)
	check(found.any(func(asset: Dictionary):return library.themes.matches(asset,"space")),"Independent collection-name search works")
	var choice:=OptionButton.new();root.add_child(choice);library.themes.fill(choice,library)
	check(choice.item_count==8,"Missing representative packs use useful fallback icons without hiding any collection")
	choice.free();print("ASSET THEMES PORTABLE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
