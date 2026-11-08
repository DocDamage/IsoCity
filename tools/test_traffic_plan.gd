extends SceneTree

const Plan=preload("res://scripts/builder/traffic_plan.gd")
const Junctions=preload("res://scripts/builder/traffic_junctions.gd")
const Roads=preload("res://scripts/builder/roads.gd")
var checks: int=0
var failures: int=0

func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	check(not Plan.settings({})["enabled"],"Traffic is opt-in for existing projects")
	var bad: Dictionary=Plan.settings({"traffic":{"enabled":1,"population":999,"seed":NAN,"speed":-1,"parking_seconds":INF}})
	check(not bad["enabled"] and bad["population"]==64 and bad["seed"]==1 and bad["speed"]==1 and bad["parking_seconds"]==8,"Invalid traffic settings have finite bounded fallbacks")
	check(Plan.valid_settings({"enabled":true,"population":4,"custom":"kept"}) and not Plan.valid_settings({"population":2.5}) and not Plan.valid_settings({"speed":NAN}),"Settings validate known fields and allow extensions")
	check(not Plan.valid_settings({"enabled":1}) and not Plan.valid_settings([]),"Traffic configuration requires explicit types")
	for mode in ["2d","3d"]:
		var data: Dictionary={"mode":mode,"roads":[{"cell":[0,0]},{"cell":[1,0],"width":2},{"cell":[-1,0]},{"cell":[0,1],"crossing":true},{"cell":[0,-1]},{"cell":[10,10]}]}
		var original: Dictionary=data.duplicate(true)
		var plan: Dictionary=Plan.build(data)
		check(plan["sections"].size()==6 and plan["edges"].size()==8,"Only orthogonally connected road sections produce paired lanes: "+mode)
		check(data==original,"Traffic planning preserves the authored document: "+mode)
		check(plan["sections"]["10,10"]["neighbors"].is_empty(),"Disconnected road sections do not invent links: "+mode)
		check(Plan.route(plan,"-1,0","1,0")==PackedStringArray(["-1,0","0,0","1,0"]),"A shortest route crosses a real connected intersection: "+mode)
		check(Plan.route(plan,"0,0","10,10").is_empty() and Plan.route(plan,"missing","0,0").is_empty(),"Disconnected or missing destinations cannot be routed: "+mode)
		check(Plan.route(plan,"0,0","0,0")==PackedStringArray(["0,0"]),"A stationary route remains well defined: "+mode)
		var point:=Vector2(-12.5,19.25)
		check(Plan.metric(Plan.world(point,mode,2),mode).is_equal_approx(point),"Road coordinates round-trip in both dimensions: "+mode)
		check(Roads.cell_at(Plan.world(Plan.center(Vector2i(3,-4),mode),mode),mode)==Vector2i(3,-4),"Road centers match the editor's actual road grid and sprite contact offset: "+mode)
		var forward: Dictionary=plan["edges"]["0,0>1,0"]
		var backward: Dictionary=plan["edges"]["1,0>0,0"]
		var center: Vector2=Plan.center(Vector2i.ZERO,mode)
		check(is_equal_approx(forward["points"][0].y-center.y,1.5) and is_equal_approx(backward["points"][-1].y-center.y,-1.5),"Opposing traffic stays on separate right-hand lanes: "+mode)
		check(is_equal_approx(forward["points"][-1].y-Plan.center(Vector2i(1,0),mode).y,.5),"Lane offsets taper to a narrow connected road: "+mode)
		for previous in plan["sections"]["0,0"]["neighbors"]:
			for next in plan["sections"]["0,0"]["neighbors"]:
				var turn: PackedVector2Array=Plan.turn(plan,previous,"0,0",next)
				var incoming: Dictionary=plan["edges"][previous+">0,0"]
				var outgoing: Dictionary=plan["edges"]["0,0>"+next]
				check(turn[0]==incoming["points"][-1] and turn[-1]==outgoing["points"][0],"Turns connect exact incoming and outgoing lane ports: "+mode+previous+next)
				check((turn[1]-turn[0]).normalized().dot(incoming["axis"])>.95 and (turn[-1]-turn[-2]).normalized().dot(outgoing["axis"])>.95,"Turns preserve travel direction at entry and exit: "+mode+previous+next)
				check(Array(turn).all(func(p: Vector2):return absf(p.x-center.x)<=3.501 and absf(p.y-center.y)<=3.501),"Straight, curved and dead-end movements stay inside the junction footprint: "+mode+previous+next)
				var travel: Dictionary=Plan.sample(turn,Plan.length(turn)*.5)
				check(not travel["finished"] and travel["heading"].length()>.99 and Plan.sample(turn,Plan.length(turn)+1)["point"]==turn[-1],"Arc-length sampling advances and ends on the physical route: "+mode+previous+next)
		check(Plan.turn(plan,"missing","0,0","1,0").is_empty(),"Removed roads cannot produce a turn: "+mode)
		var a:=RandomNumberGenerator.new(); a.seed=51
		var b:=RandomNumberGenerator.new(); b.seed=51
		var choices: Array=[]; var repeated: Array=[]
		for index in 20:
			choices.append(Plan.next_section(plan,"0,0","-1,0",a)); repeated.append(Plan.next_section(plan,"0,0","-1,0",b))
		check(choices==repeated and not "-1,0" in choices,"Seeded journeys avoid reversing when a continuing route exists: "+mode)
		check(Plan.next_section(plan,"1,0","0,0",a)=="0,0" and Plan.next_section(plan,"10,10","",a).is_empty(),"Dead ends allow turnaround while isolated sections remain stationary: "+mode)
		var gates:=Junctions.new()
		check(not gates.request(plan,"first","0,0",3)["allowed"],"Intersection arrivals stop before entering: "+mode)
		check(not gates.request(plan,"first","0,0",3.9)["allowed"],"The complete mandatory stop is observed: "+mode)
		check(gates.request(plan,"first","0,0",4)["allowed"],"The first stopped vehicle receives the intersection reservation: "+mode)
		check(not gates.request(plan,"second","0,0",4)["allowed"] and not gates.request(plan,"second","0,0",5.1)["allowed"],"Conflicting movement cannot enter an occupied intersection: "+mode)
		check(gates.request(plan,"first","0,0",10,true)["allowed"],"An admitted vehicle can clear the intersection when the pedestrian phase changes: "+mode)
		gates.release("first","0,0")
		check(gates.request(plan,"second","0,0",5.2)["allowed"],"The next queued stopped vehicle proceeds after the owner clears: "+mode)
		gates.release("second")
		check(not gates.request(plan,"third","0,0",10)["allowed"],"Intersection pedestrian phases stop incoming vehicles: "+mode)
		check(not gates.request(plan,"car","0,1",0)["allowed"] and gates.request(plan,"car","0,1",3)["allowed"],"Authored crossings alternate pedestrian and vehicle admission: "+mode)
		check(not gates.request(plan,"car","0,1",4,true)["allowed"],"An occupied crossing holds traffic even outside its timed phase: "+mode)
		check(gates.request(plan,"car","1,0",1)["allowed"],"An ordinary road without a crossing has no artificial stop: "+mode)
		check(not gates.request(plan,"car","gone",4)["allowed"],"A removed section cannot grant admission: "+mode)
		gates.clear()
		check(gates.owners.is_empty() and gates.queues.is_empty() and gates.waiting_since.is_empty(),"Rebuilding a road network clears all junction reservations: "+mode)
	var malformed: Dictionary=Plan.build({"roads":[{"cell":[0,0]},{"cell":[0,0]},{"cell":[1.5,0]},{"cell":[INF,0]},{"cell":[100001,0]},{"cell":[0]},{"cell":[1,0],"width":3},null]})
	check(malformed["sections"].size()==1 and not malformed["notices"].is_empty(),"Duplicate, malformed and unsupported roads do not enter the network")
	check(Plan.sample([],4)["finished"] and Plan.sample(PackedVector2Array([Vector2.ONE]),4)["point"]==Vector2.ONE,"Empty and stationary movement samples are safe")
	print("TRAFFIC PLAN: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
