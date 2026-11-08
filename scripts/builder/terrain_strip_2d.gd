extends Node2D
var faces: Array[Dictionary]=[]
var animated: bool=false
var elapsed: float=0
var last_frame: int=-1
var clock: Node
func current_time() -> float: return clock.elapsed if is_instance_valid(clock) else elapsed
func _ready() -> void: set_process(animated)
static func frame_at(face: Dictionary,time: float) -> int:
	if face.get("textures",[]).size()<2: return 0
	var total: float=0
	for duration in face["durations"]: total+=duration
	var cursor: float=fposmod(time*face["speed"],total)
	for index in face["durations"].size():
		cursor-=face["durations"][index]
		if cursor<0: return index
	return 0
func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	if not is_instance_valid(clock): elapsed+=delta
	var stamp: int=0
	for face in faces:
		if face.get("textures",[]).size()>1: stamp=hash([stamp,frame_at(face,current_time())])
	if stamp!=last_frame: last_frame=stamp; queue_redraw()
func _draw() -> void:
	for face in faces:
		draw_colored_polygon(face["points"],face["color"])
		if face.has("textures"): draw_polygon(face["points"],PackedColorArray([face["tint"]]),face["uv"],face["textures"][frame_at(face,current_time())])
