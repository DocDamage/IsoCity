extends "res://tools/test_resident_elevator_context.gd"
func interrupt(lift: Node) -> bool:return lift.npc_token!=0 and lift.phase=="opening" and lift.elapsed>.05
func facts_path() -> String:return "res://output/verification/asset_expansion/I14/elevator_context_opening_facts.json"
