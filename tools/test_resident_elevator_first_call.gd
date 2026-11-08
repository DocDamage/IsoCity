extends "res://tools/test_resident_elevator_first_visit.gd"
func target_phase() -> String:return "calling"
func expected_attachments(mode: String) -> int:return 1 if mode=="2d" else 2
func expected_rides() -> int:return 3
func facts_path() -> String:return "res://output/verification/asset_expansion/I14/elevator_first_call_facts.json"
