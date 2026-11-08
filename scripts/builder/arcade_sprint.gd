extends Control

const GAP = 40
# Each section has one barrier and a gate in a different lane.
const COURSE = [
	Vector2i(1,2), Vector2i(2,0), Vector2i(0,1), Vector2i(1,0),
	Vector2i(0,2), Vector2i(2,1), Vector2i(1,2), Vector2i(2,0),
	Vector2i(0,2), Vector2i(2,1), Vector2i(1,0), Vector2i(0,2),
	Vector2i(2,0), Vector2i(1,2), Vector2i(0,1), Vector2i(2,1),
]
const BASE = Vector2(620,248)
const START_COLOR = Color("101b2c")
const GATE_COLOR = Color("f4d06f")
const BARRIER_COLOR = Color("ff775e")
const CAR_COLOR = Color("55dfcf")

var ticks: int = 0
var lane: int = 1
var section: int = 0
var strikes: int = 0
var score: int = 0
var finished: bool = false
var feedback: String = "Ready to race."
var high_contrast: bool = false

func begin() -> void:
	feedback = "Choose a lane before the next marker."

func command(action: String) -> void:
	if finished: return
	var offset: int = int(action == "move_right")-int(action == "move_left")
	lane = clampi(lane+offset,0,2)
	queue_redraw()

func tick() -> void:
	if finished: return
	ticks += 1
	if ticks % GAP == 0:
		var pattern: Vector2i = COURSE[section]
		if lane == pattern.x:
			strikes += 1
			feedback = "Barrier hit."
		elif lane == pattern.y:
			score += 200
			feedback = "Gate collected · 200 points."
		else:
			score += 100
			feedback = "Section clear · 100 points."
		section += 1
		finished = section == COURSE.size() or strikes == 3
		if finished: feedback = "Course complete." if strikes < 3 else "Three crashes ended the run."
	queue_redraw()

func status() -> String:
	return "Score %d · Section %d/%d · %d crashes" % [score,section,COURSE.size(),strikes]

func draw_road() -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(251,14),Vector2(369,14),Vector2(563,248),Vector2(57,248)]),
		Color("263544") if not high_contrast else Color("202020"))
	for sign_value in [-1,1]:
		var side: float = float(sign_value)
		draw_line(Vector2(310+59*side,14),Vector2(310+253*side,248),Color("78a8b0"),3)
		draw_line(Vector2(310+20*side,14),Vector2(310+84*side,248),Color("b1c5d1"),2)
	for index in 6:
		var y: float = 35+fposmod(index*37+ticks*.9,205)
		var edge: float = lerpf(55,249,y/248)
		draw_line(Vector2(310-edge-8,y),Vector2(310-edge-23,y),Color("4d677e"),2)
		draw_line(Vector2(310+edge+8,y),Vector2(310+edge+23,y),Color("4d677e"),2)

func draw_event(index: int) -> void:
	var distance: float = float((index+1)*GAP-ticks)/float(GAP)
	var depth: float = clampf(1-distance/3.35,0,1)
	var y: float = lerpf(22,219,depth)
	var span: float = lerpf(42,124,depth)
	var scale_value: float = lerpf(.38,1.0,depth)
	var pair: Vector2i = COURSE[index]
	var hazard := Vector2(310+(pair.x-1)*span,y)
	var gate := Vector2(310+(pair.y-1)*span,y)
	draw_rect(Rect2(hazard-Vector2(20,9)*scale_value,Vector2(40,18)*scale_value),BARRIER_COLOR)
	draw_line(hazard+Vector2(-13,5)*scale_value,hazard+Vector2(13,-5)*scale_value,Color("472827"),3*scale_value)
	draw_arc(gate,14*scale_value,0,TAU,28,GATE_COLOR,4*scale_value,true)
	draw_circle(gate,4*scale_value,GATE_COLOR)

func _draw() -> void:
	if size.x <= 0 or size.y <= 0: return
	draw_set_transform(Vector2.ZERO,0,size/BASE)
	draw_rect(Rect2(Vector2.ZERO,BASE),Color.BLACK if high_contrast else START_COLOR)
	draw_road()
	var last: int = mini(COURSE.size()-1,section+2)
	for index in range(last,section-1,-1): draw_event(index)
	var car := Vector2(310+(lane-1)*124,220)
	draw_colored_polygon(PackedVector2Array([car+Vector2(0,-18),car+Vector2(18,14),car+Vector2(0,8),car+Vector2(-18,14)]),CAR_COLOR)
	draw_rect(Rect2(car+Vector2(-6,-1),Vector2(12,7)),Color("18373e"))
