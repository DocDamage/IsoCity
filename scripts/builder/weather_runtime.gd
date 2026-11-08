extends Node

const Plan=preload("res://scripts/builder/weather_plan.gd")
var foliage=preload("res://scripts/builder/weather_foliage.gd").new()
var layer: CanvasLayer
var screen: Control
var elapsed: float=0
var settings_stamp: int=0
var current_state: Dictionary={}

func _ready() -> void:
	layer=CanvasLayer.new(); layer.name="WeatherLayer"; layer.layer=4; add_child(layer)
	screen=preload("res://scripts/builder/weather_screen.gd").new(); screen.name="Precipitation"; layer.add_child(screen)

func step(delta: float,data: Dictionary,instances: Dictionary,exterior: bool=true,right: Vector3=Vector3.RIGHT) -> void:
	if not is_finite(delta) or delta<0: return
	var settings: Dictionary=Plan.settings(data); var stamp: int=hash(settings)
	if stamp!=settings_stamp: elapsed=0; settings_stamp=stamp
	if settings["enabled"] and exterior: elapsed+=delta
	current_state=Plan.state(data,elapsed)
	var visible_state: Dictionary=current_state.duplicate()
	if not exterior: visible_state["enabled"]=false; visible_state["rain"]=0.0; visible_state["snow"]=0.0; visible_state["wind_vector"]=Vector2.ZERO
	foliage.sync(data,instances,visible_state,minf(delta,.25))
	var force: Vector2=visible_state["wind_vector"]; var horizontal:=Vector2(right.x,right.z).normalized()
	if horizontal.is_zero_approx(): horizontal=Vector2.RIGHT
	var screen_wind:=Vector2(force.dot(horizontal),force.dot(Vector2(-horizontal.y,horizontal.x))*.5)
	screen.configure(visible_state,minf(delta,.25),screen_wind)

func reset() -> void:
	foliage.reset(); elapsed=0; settings_stamp=0; current_state={}
	if screen: screen.visible=false

func _exit_tree() -> void: foliage.reset()
