extends "res://tools/test_resident_elevator_context.gd"
func interrupt(lift: Node) -> bool:return lift.call_owner_token!=0 and lift.npc_token==0 and lift.phase=="idle" and lift.last_stop=="upper" and lift.target=="upper"
func facts_path() -> String:return "res://output/verification/asset_expansion/I14/elevator_context_alighting_facts.json"
