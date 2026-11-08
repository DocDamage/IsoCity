extends "res://tools/test_floor_stairs_3d.gd"
func flight_case(city: Dictionary,lower: String,upper: String,height: float,start: Vector2,end: Vector2,width: float,title: String) -> void:
	world.player.move_speed=1.8
	await super.flight_case(city,lower,upper,height,start,end,width,title+" at resident walking speed")
