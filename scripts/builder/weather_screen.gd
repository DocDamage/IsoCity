extends Control

const MAX_PARTICLES: int=360
var particles: Array[Vector4]=[]
var clock: float=0
var rain: float=0
var snow: float=0
var wind: Vector2=Vector2.ZERO
var gust: float=0
var seed_value: int=-1

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE; set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func configure(state: Dictionary,delta: float,screen_wind: Vector2) -> void:
	if seed_value!=state["seed"]:
		seed_value=state["seed"]; var random:=RandomNumberGenerator.new(); random.seed=seed_value; particles.clear()
		for index in MAX_PARTICLES: particles.append(Vector4(random.randf(),random.randf(),random.randf_range(.65,1.4),random.randf()))
	clock=fposmod(clock+maxf(0,delta),10000)
	rain=state["rain"]; snow=state["snow"]; wind=screen_wind
	gust=float(state["intensity"]) if state["condition"]=="wind" and state["enabled"] else 0.0
	visible=rain>0 or snow>0 or gust>0; queue_redraw()

func particle_position(particle: Vector4,kind: String) -> Vector2:
	var fall: float=(.75 if kind=="rain" else .09)*particle.z
	var drift: float=wind.x*(.23 if kind=="rain" else .12)
	var x: float=particle.x+clock*drift+(sin(clock*.7+particle.w*TAU)*.025 if kind=="snow" else 0.0)
	var y: float=particle.y+clock*(fall+wind.y*.04)
	return Vector2(fposmod(x,1)*size.x,fposmod(y,1)*size.y)

func _draw() -> void:
	if size.x<=0 or size.y<=0: return
	if rain>0:
		draw_rect(Rect2(Vector2.ZERO,size),Color(.08,.16,.23,rain*.08))
		for index in ceili(MAX_PARTICLES*rain):
			var p: Vector4=particles[index]; var point: Vector2=particle_position(p,"rain")
			draw_line(point,point+Vector2(wind.x*12,10+p.z*8),Color(.7,.84,.96,.22+p.w*.3),1,true)
	if snow>0:
		for index in ceili(MAX_PARTICLES*snow):
			var p: Vector4=particles[index]; draw_circle(particle_position(p,"snow"),1.1+p.w*1.7,Color(.93,.97,1,.55+p.w*.35),true,-1,true)
	if gust>0:
		for index in ceili(48*gust):
			var p: Vector4=particles[index]; var point: Vector2=Vector2(fposmod(p.x+clock*(wind.x*.3+.02),1)*size.x,fposmod(p.y+clock*wind.y*.2,1)*size.y)
			var direction: Vector2=Vector2(wind.x,wind.y*.4).normalized()
			draw_line(point,point+direction*(18+p.w*38),Color(.85,.9,.84,.1+p.w*.15),1,true)
