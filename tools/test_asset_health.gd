extends SceneTree
const OUT="res://output/verification/asset_expansion/U17/fixtures"
const Health=preload("res://scripts/builder/asset_health.gd")
const Preview=preload("res://scripts/builder/model_preview.gd")
const Repair=preload("res://scripts/builder/asset_preview_repair.gd")
const Renderer=preload("res://scripts/builder/model_thumbnail.gd")
const BOX="[gd_scene load_steps=3 format=3]\n\n[sub_resource type=\"BoxMesh\" id=\"Box\"]\nsize = Vector3(2, 1, 1)\n\n[sub_resource type=\"StandardMaterial3D\" id=\"Paint\"]\nalbedo_color = Color(0.2, 0.5, 0.8, 1)\n\n[node name=\"Fixture\" type=\"Node3D\"]\n\n[node name=\"Box\" type=\"MeshInstance3D\" parent=\".\"]\nmesh = SubResource(\"Box\")\nmaterial_override = SubResource(\"Paint\")\n"
var checks: int=0
var failures: int=0
var fixture_ids: Array=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func write(path: String,text: String) -> void:FileAccess.open(path,FileAccess.WRITE).store_string(text)
func sprite(id: String,image: String) -> Dictionary:
	return {"id":id,"name":"Fixture tile","mode":"2d","category":"Custom","path":OUT+"/sprite.tscn","data":{"directions":{"SE":{"file":image,"frame_width":32,"frame_height":16,"frames":1,"footprint":[1,1],"origin":[16,8]}},"animation_status":"static_sprite","themes":["pixel_city"]},"behavior":{"layer":"Ground","ground":true,"building":false}}
func model(id: String,target: String) -> Dictionary:
	return {"id":id,"name":"Fixture model","mode":"3d","category":"Fixture","path":OUT+"/box.tscn","data":{"preview_path":target,"animation_status":"static_mesh","themes":["space"]},"behavior":{"layer":"Decorations","building":false}}
func register(library: RefCounted,asset: Dictionary) -> void:library.assets[asset["id"]]=asset;fixture_ids.append(asset["id"])
func scan(library: RefCounted) -> Dictionary:
	var audit: RefCounted=Health.new();audit.begin(library);audit.ids=fixture_ids.duplicate();audit.ids.sort()
	while audit.active:audit.step(3,100000)
	return audit.report()
func find_issue(report: Dictionary,code: String,id: String) -> Dictionary:
	for issue in report["issues"]:
		if issue["code"]==code and id in issue["affected_ids"]:return issue
	return {}
func track_prepare(repair: RefCounted,issue: Dictionary,record: Dictionary) -> void:
	record["result"]=await repair.prepare(issue)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	write(OUT+"/box.tscn",BOX);write(OUT+"/sprite.tscn","[gd_scene format=3]\n[node name=\"SpriteFixture\" type=\"Node2D\"]\n")
	var flat:=Image.create_empty(32,16,false,Image.FORMAT_RGBA8);flat.fill(Color(.2,.4,.6,1));flat.save_png(OUT+"/tile.png");flat.save_png(OUT+"/model_preview.png")
	var good:=Image.create_empty(32,32,false,Image.FORMAT_RGBA8);good.fill(Color.TRANSPARENT);good.fill_rect(Rect2i(8,8,16,16),Color.CORNFLOWER_BLUE)
	check(not Preview.meaningful_image(flat) and Preview.meaningful_image(good),"Model uniform detection accepts silhouettes and rejects flat model placeholders")
	var thin: Image=Preview.read_image("res://resources/previews_3d/Fire_Station_PSX/fire_hook.png")
	check(Preview.meaningful_image(thin),"Actual thin fire-hook artwork survives alpha counting without false repair")
	var noise: Image=flat.duplicate();noise.set_pixel(0,0,Color.RED);check(not Preview.meaningful_image(noise),"A few noisy pixels do not turn a uniform opaque model placeholder into artwork")
	var invisible:=Image.create_empty(32,32,false,Image.FORMAT_RGBA8);invisible.fill(Color(1,0,0,0));check(not Preview.meaningful_image(invisible),"Invisible RGB is not art")
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new();check(library.assets.size()==6555,"Health work preserves the full catalog")
	register(library,sprite("2d:HealthFixture/FlatTile",OUT+"/tile.png"))
	register(library,model("3d:HealthFixture/Box",OUT+"/model_preview.png"));register(library,model("3d:HealthFixture/BoxAlias",OUT+"/model_preview.png"))
	for id in ["2d:HealthFixture/MissingA","2d:HealthFixture/MissingB"]:register(library,sprite(id,OUT+"/absent.png"))
	var invalid: Dictionary=sprite("2d:HealthFixture/InvalidRegion",OUT+"/tile.png");invalid["data"]["directions"]["SE"]["region"]=[false,0,32,16];register(library,invalid)
	var frames: Dictionary=sprite("2d:HealthFixture/InvalidFrames",OUT+"/tile.png");frames["data"]["directions"]["SE"]["frames"]=9;register(library,frames)
	var reference: Dictionary=sprite("2d:HealthFixture/Reference",OUT+"/tile.png");reference["data"]["content_kind"]="atlas";reference["data"]["source_files"]=[OUT+"/unavailable_original.png"];register(library,reference)
	var decorative: Dictionary=sprite("2d:HealthFixture/DecorativeBuilding",OUT+"/tile.png");decorative["behavior"]={"layer":"Buildings","building":true,"door":false};register(library,decorative)
	var malformed: Dictionary=sprite("2d:HealthFixture/BadMetadata",OUT+"/tile.png");malformed["data"]=false;register(library,malformed)
	var before: Dictionary={}
	for id in fixture_ids:before[id]=library.assets[id].duplicate(true)
	var source_hashes: Dictionary={}
	for path in [OUT+"/tile.png",OUT+"/box.tscn",OUT+"/sprite.tscn"]:source_hashes[path]=FileAccess.get_sha256(path)
	var report: Dictionary=scan(library)
	check(report["status"]=="complete" and report["assets_scanned"]==fixture_ids.size(),"Incremental scan reports actual completed coverage")
	check(report["issues"].filter(func(issue: Dictionary):return issue["severity"]=="defect" and "2d:HealthFixture/FlatTile" in issue["affected_ids"]).is_empty(),"Legitimate flat sprite tiles remain valid")
	check(find_issue(report,"preview_placeholder","3d:HealthFixture/Box")["affected_ids"].size()==2,"One shared model-preview issue identifies every exact affected ID")
	check(find_issue(report,"missing_dependency","2d:HealthFixture/MissingA")["affected_ids"].size()==2,"A shared unavailable sprite source groups affected variants")
	check(not find_issue(report,"invalid_region",invalid["id"]).is_empty() and not find_issue(report,"invalid_frames",frames["id"]).is_empty(),"Invalid region types and frame bounds are definite defects")
	check(find_issue(report,"reference_content",reference["id"])["severity"]=="review" and find_issue(report,"optional_source_unavailable",reference["id"])["severity"]=="review","References and unavailable optional originals remain review notes while prepared art exists")
	check(report["issues"].filter(func(issue: Dictionary):return issue["severity"]=="defect" and decorative["id"] in issue["affected_ids"]).is_empty(),"An intentionally decorative building is never automatically broken")
	check(not find_issue(report,"invalid_metadata",malformed["id"]).is_empty(),"Malformed metadata reports a defect without crashing or changing it")
	for id in fixture_ids:check(library.assets[id]==before[id],"Audit never mutates asset metadata: "+id)
	for path in source_hashes:check(FileAccess.get_sha256(path)==source_hashes[path],"Read-only audit preserves source bytes: "+path)
	var audit: RefCounted=Health.new();audit.begin(library);audit.ids=fixture_ids.duplicate();audit.step(0,1000);check(audit.cursor==0 and audit.active,"Zero asset budget performs no work");audit.step(1,100000);audit.cancel();check(audit.status=="cancelled" and audit.cursor==1,"Interrupted audit retains honest partial coverage")
	audit.begin(library);audit.step(0,1000);var old_revision: int=library.families.revision;library.families.revision+=1;audit.step();check(audit.status=="stale" and not audit.active,"Catalog rebuild invalidates a pending scan");library.families.revision=old_revision
	write(OUT+"/cycle_a.tres","[gd_resource type=\"Resource\" format=3]\n[ext_resource type=\"Resource\" path=\""+OUT+"/cycle_b.tres\" id=\"b\"]\n[ext_resource type=\"Texture2D\" path=\""+OUT+"/cycle_missing.png\" id=\"missing\"]\n[resource]\n")
	write(OUT+"/cycle_b.tres","[gd_resource type=\"Resource\" format=3]\n[ext_resource type=\"Resource\" path=\""+OUT+"/cycle_a.tres\" id=\"a\"]\n[resource]\n")
	var cycles: RefCounted=Health.new();var first: Array=cycles.dependency_errors(OUT+"/cycle_a.tres",{});var second: Array=cycles.dependency_errors(OUT+"/cycle_b.tres",{})
	check(first.any(func(issue: Dictionary):return issue["code"]=="dependency_cycle") and second.any(func(issue: Dictionary):return issue["code"]=="missing_dependency"),"Cyclic/shared dependency traversal stays bounded without hiding a missing source on another root")
	await repair_checks(library,report,good,flat)
	print("ASSET HEALTH: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

func repair_checks(library: RefCounted,report: Dictionary,good: Image,flat: Image) -> void:
	var issue: Dictionary=find_issue(report,"preview_placeholder","3d:HealthFixture/Box");var repair: RefCounted=Repair.new(library,self);repair.allowed_roots.append(OUT+"/");repair.backup_root=OUT+"/backups"
	check(repair.plan(issue)["ok"],"Repair preflight handles prepared inline geometry and every shared owner")
	check(not repair.plan({"repair":"model_preview","path":"res://assets/editor/missing_object.png","affected_ids":issue["affected_ids"]})["ok"],"Repair never overwrites unrelated/source locations")
	var source_alias: Dictionary=sprite("2d:HealthFixture/SourceAlias",OUT+"/model_preview.png");library.assets[source_alias["id"]]=source_alias
	check(not repair.plan(issue)["ok"],"A thumbnail also used as sprite source art cannot be overwritten");library.assets.erase(source_alias["id"])
	write(OUT+"/other.tscn",BOX);library.assets["3d:HealthFixture/BoxAlias"]["path"]=OUT+"/other.tscn"
	check(not repair.plan(issue)["ok"],"Different scenes sharing one target require explicit metadata repair");library.assets["3d:HealthFixture/BoxAlias"]["path"]=OUT+"/box.tscn"
	var target: String=OUT+"/model_preview.png";var old_hash: String=FileAccess.get_sha256(target)
	DirAccess.remove_absolute(target+".isocity-preview.json")
	if DisplayServer.get_name()=="headless":
		var missing_gpu: Dictionary=await repair.prepare(issue);check(not missing_gpu["ok"] and FileAccess.get_sha256(target)==old_hash,"Unavailable rendering retains the existing thumbnail")
	good.save_png(target);var plan: Dictionary=repair.plan(issue)
	write(target+".isocity-preview.json",JSON.stringify({"version":1,"key":plan["key"],"sha256":FileAccess.get_sha256(target)}))
	var cached: Dictionary=await repair.prepare(issue);check(cached["ok"] and cached.get("current",false),"Verified current preview is a repeatable no-op even without a GPU")
	write(OUT+"/box.tscn",BOX+"\n; source revision\n");check(repair.plan(issue)["key"]!=plan["key"],"Dependency content changes invalidate the versioned render cache")
	write(OUT+"/box.tscn",BOX);DirAccess.remove_absolute(target+".isocity-preview.json")
	plan=repair.plan(issue);plan["image"]=good;repair.proposal=plan
	write(OUT+"/blocked_parent.txt","not a directory");repair.backup_root=OUT+"/blocked_parent.txt";var before: String=FileAccess.get_sha256(target)
	check(not repair.apply()["ok"] and FileAccess.get_sha256(target)==before,"Failed recovery-copy write preserves a good existing preview")
	repair.backup_root=OUT+"/backups";repair.proposal=repair.plan(issue);repair.proposal["image"]=flat
	check(not repair.apply()["ok"] and FileAccess.get_sha256(target)==before,"Uniform temporary output is refused before replacing a good file")
	repair.proposal=repair.plan(issue);repair.proposal["image"]=good;library.assets["3d:HealthFixture/NewAlias"]=model("3d:HealthFixture/NewAlias",target)
	check(not repair.apply()["ok"] and FileAccess.get_sha256(target)==before,"New affected IDs after review require a fresh proposal");library.assets.erase("3d:HealthFixture/NewAlias")
	repair.proposal=repair.plan(issue);repair.proposal["image"]=good;write(OUT+"/box.tscn",BOX+"\n; changed after review\n")
	check(not repair.apply()["ok"] and FileAccess.get_sha256(target)==before,"Source edits after review do not publish a stale repair");write(OUT+"/box.tscn",BOX)
	repair.cancel();check(repair.proposal.is_empty() and not repair.apply()["ok"],"Cancellation discards all unapplied work")
	if "--rendered" in OS.get_cmdline_user_args():
		flat.save_png(target);var original: String=FileAccess.get_sha256(target);var interrupted: Dictionary={}
		track_prepare(repair,issue,interrupted);repair.cancel()
		for frame in 4:await process_frame
		check(interrupted.get("result",{}).get("cancelled",false) and FileAccess.get_sha256(target)==original and root.find_children("PrivateModelThumbnail","",true,false).is_empty(),"Cancelling a live GPU proposal leaves no public write or private scene")
		var prepared: Dictionary=await repair.prepare(issue)
		check(prepared["ok"] and not prepared.get("current",false) and prepared["affected_ids"].size()==2 and FileAccess.get_sha256(target)==original,"Actual GPU render prepares artwork for review without modifying its target")
		if prepared["ok"] and not prepared.get("current",false):
			check(Preview.meaningful_image(prepared["image"]) and prepared["image"].get_size()==Vector2i(192,192),"GPU proposal contains transparent bounds-fitted model artwork")
			var applied: Dictionary=repair.apply();check(applied["ok"] and applied["cached"] and Preview.meaningful(library.icon(issue["affected_ids"][0])) and Preview.meaningful(library.icon(issue["affected_ids"][1])),"Atomic repair updates every owner immediately without an editor reimport")
			check(FileAccess.get_sha256(applied["backup"])==original,"Previous preview remains recoverable by exact content hash")
			check((await repair.prepare(issue)).get("current",false),"Repeating a verified applied repair is a no-op")
			var after: Dictionary=scan(library);check(find_issue(after,"preview_placeholder","3d:HealthFixture/Box").is_empty(),"A fresh audit confirms the repaired preview defect is gone")
	repair.cancel()
