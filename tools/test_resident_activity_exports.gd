extends "res://tools/test_resident_activity_interruptions.gd"
const OUT="res://output/verification/asset_expansion/I14/exports/"
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT));studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio);await settle()
	for mode in ["2d","3d"]:
		for kind in ["stairs","elevator"]:
			var doc: RefCounted=await setup_case(mode,kind);var world: Node=studio.worlds[mode];var old_jobs: Array=citizens.activities.scheduler.jobs.values().map(func(job: Dictionary):return job["id"]);var ready: bool=false
			for frame in 1200:
				await tick()
				ready=citizens.activities.scheduler.jobs.values().any(func(job: Dictionary):return job.has("stair") and job["stair"]["progress"]>.35) if kind=="stairs" else world.exploration.interior.floor_stack.lifts["link"].npc_token!=0 and world.exploration.interior.floor_stack.lifts["link"].phase=="moving"
				if ready:break
			check(ready,"Export begins during an actual occupied native "+kind+" trip: "+mode)
			var original: Dictionary=doc.data.duplicate(true);var history: int=doc.undo_history.size();var ids: Array=citizens.residents.map(func(resident: Dictionary):return resident["actor"].get_instance_id());var name: String=kind+"_"+mode
			var result: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(world,doc.data,studio.library,OUT+name+".zip")
			check(result["ok"],"Allowed occupied-interior portable export succeeds: "+name+" "+result["message"])
			check(world.exploration.interior!=null and doc.data==original and doc.undo_history.size()==history and citizens.residents.map(func(resident: Dictionary):return resident["actor"].get_instance_id())==ids and citizens.activities.scheduler.jobs.values().map(func(job: Dictionary):return job["id"])==old_jobs,"Export preserves the original visit, bodies, jobs, authored geometry and history: "+name)
			var previews: Dictionary={}
			for id in ["3d:HanX_School/School_Building","3d:HanX_School/Student_Chair"]:previews[id]=studio.library.assets[id]["data"].get("preview_path","res://resources/previews_3d/"+id.trim_prefix("3d:")+".png")
			FileAccess.open(OUT+name+"_expected.json",FileAccess.WRITE).store_string(JSON.stringify({"source":original,"kind":kind,"enabled":true,"previews":previews},"\t"))
			if kind=="stairs":
				var legacy: Dictionary=original.duplicate(true);legacy["citizens"].erase("interior_activities");var disabled: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(world,legacy,studio.library,OUT+"legacy_"+mode+".zip")
				check(disabled["ok"],"Allowed legacy portable export retains the absent/default-off option: "+mode+" "+disabled["message"])
				FileAccess.open(OUT+"legacy_"+mode+"_expected.json",FileAccess.WRITE).store_string(JSON.stringify({"source":legacy,"kind":"stairs","enabled":false,"previews":previews},"\t"))
			citizens.clear();world.exploration.leave_interior();studio.set_walking(false);await settle()
	studio.free();await settle();print("RESIDENT ACTIVITY EXPORTS: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
