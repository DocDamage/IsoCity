extends "res://tools/test_resident_elevator_context.gd"
func interrupt(lift: Node) -> bool:return lift.npc_token!=0 and lift.target=="ground" and lift.phase=="moving" and lift.height>=1.1 and lift.height<=1.7
func facts_path() -> String:return "res://output/verification/asset_expansion/I14/elevator_context_descending_facts.json"
