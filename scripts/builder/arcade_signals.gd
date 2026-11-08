extends Control

const ACTIONS = ["move_left","move_up","move_down","move_right"]
const NAMES = ["Left","Up","Down","Right"]
const PATTERNS = [
	[0,2],[1,3,0],[2,2,1],[3,0,2,1],
	[1,0,3,2],[0,3,1,2,0],[2,1,1,3,0],[3,2,0,1,3],
]
const SLOT_TICKS = 42
const LIT_TICKS = 30
const REPLY_TICKS = 540
const BASE = Vector2(620,248)
const ACCENT = Color("f4d06f")

var round_index: int = 0
var stage: String = "intro"
var clock: int = 0
var cursor: int = 0
var strikes: int = 0
var score: int = 0
var finished: bool = false
var feedback: String = "Watch each signal before entering it."
var high_contrast: bool = false

func begin() -> void:
	stage = "watch"
	feedback = "Watch the pattern."

func cue() -> int:
	if stage != "watch" or clock % SLOT_TICKS >= LIT_TICKS: return -1
	var pattern: Array = PATTERNS[round_index]
	return pattern[mini(int(clock / float(SLOT_TICKS)),pattern.size()-1)]

func tick() -> void:
	if finished: return
	clock += 1
	if stage == "watch" and clock >= PATTERNS[round_index].size()*SLOT_TICKS:
		stage = "reply"
		clock = 0
		feedback = "Your turn. Repeat the pattern."
	elif stage == "reply" and clock >= REPLY_TICKS:
		strikes += 1
		next_round("Time ran out.")
	queue_redraw()

func command(action: String) -> void:
	if stage != "reply" or finished: return
	var direction: int = ACTIONS.find(action)
	if direction < 0: return
	var pattern: Array = PATTERNS[round_index]
	if direction != pattern[cursor]:
		strikes += 1
		next_round("Wrong signal.")
		return
	score += 100
	cursor += 1
	feedback = "Correct signal · 100 points."
	if cursor == pattern.size():
		score += 150
		next_round("Pattern complete · 150 bonus points.")
	queue_redraw()

func next_round(message: String) -> void:
	round_index += 1
	cursor = 0
	clock = 0
	finished = round_index == PATTERNS.size() or strikes == 3
	stage = "done" if finished else "watch"
	feedback = message + (" Sequence finished." if finished else " Watch the next pattern.")
	queue_redraw()

func status() -> String:
	return "Score %d · Pattern %d/%d · %d mistakes" % [score,mini(round_index+1,PATTERNS.size()),PATTERNS.size(),strikes]

func cue_text() -> String:
	var index: int = cue()
	if index >= 0: return "Signal · "+NAMES[index]
	if stage == "watch": return "Watch the pattern."
	if stage == "reply":
		return "Repeat · %d/%d · %d s" % [cursor,PATTERNS[round_index].size(),ceili(float(REPLY_TICKS-clock)/60)]
	return feedback

func _draw() -> void:
	if size.x <= 0 or size.y <= 0: return
	draw_set_transform(Vector2.ZERO,0,size/BASE)
	draw_rect(Rect2(Vector2.ZERO,BASE),Color.BLACK if high_contrast else Color("101b2c"))
	var active: int = cue()
	for index in 4:
		var center := Vector2(85+150*index,112)
		var highlighted: bool = index == active
		var tile := Rect2(center-Vector2(58,61),Vector2(116,122))
		draw_rect(tile,Color("5d4827") if highlighted else Color("24344a"))
		draw_rect(tile,ACCENT if highlighted else Color("66819a"),false,5 if highlighted else 2)
		var direction: Vector2 = [Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2.RIGHT][index]
		var cross: Vector2 = direction.orthogonal()
		draw_colored_polygon(PackedVector2Array([
			center+direction*31,center+direction*6+cross*23,center+direction*6+cross*9,
			center-direction*27+cross*9,center-direction*27-cross*9,center+direction*6-cross*9,
			center+direction*6-cross*23]),ACCENT if highlighted else Color("deedf1"))
	var slots: int = PATTERNS[round_index].size() if not finished else 0
	for index in slots:
		var at := Vector2(310+(index-(slots-1)*.5)*23,207)
		draw_circle(at,6,ACCENT if index < cursor else Color("516982"))
