extends RefCounted

const MAX_ROWS: int=128
const MAX_SHAPES: int=256
const MAX_POINTS: int=2048
const PERIOD: float=.25
const OVERLAYS: Dictionary={
	"off":["Off",""],
	"traffic":["Road traffic","Solid lines show current lane segments."],
	"transit":["Public transit","Solid lines show verified bus segments. Numbered squares show waiting passengers at a platform."],
	"services":["City services","Dashed lines show the selected service's road coverage. Solid lines show active crew paths."],
	"water":["Water network","Solid lines show connected ports. Dashed lines show interrupted runs and candidate connections. Facility findings report supplied demand, shortage and outage."],
	"power":["Power network","Amber lines show connected power ports. Dashed lines show interrupted cables and candidate connections. P markers identify power facilities. Findings report supplied demand, brownout and outage."],
	"residents":["Residents","Dotted lines show active walking paths."],
	"fixtures":["Interaction routes","Dotted lines show checked walking paths on this floor."],
	"zoning":["Zoning","Dotted lines show verified lot approaches. Markers show readiness and obstacles."],
	"challenges":["Challenges","Dotted lines show checked neighborhood routes. Construction markers show the current work step."],
	"deliveries":["Local deliveries","Solid lines show verified lane edges. Squares mark the active cargo station."],
	"vehicle_care":["Vehicle care","Numbered squares show waiting vehicles at their service bay."],
	"businesses":["Businesses","Numbered squares show queued visits at the building entrance."],
	"markets":["Market days","Numbered squares show waiting shoppers at a vendor queue."],
}

static func record(code: String,severity: String,scope: String,uid: String,related: Array,message: String,revision: String,details: Dictionary={},domain: String="simulation") -> Dictionary:
	var fields: Dictionary=details.duplicate()
	fields["message"]=message
	return {"code":code,"severity":severity,"scope":scope,"object_uid":uid,"related_uids":related.duplicate(),
		"message_key":domain+"."+code+"."+severity,"details":fields,"revision":revision}

static func scope(mode: String,building: String="",floor_uid: String="") -> String:
	return JSON.stringify([mode,building,floor_uid])

static func identity(row: Dictionary) -> Array:
	return [row.get("scope",""),row.get("object_uid",""),row.get("code",""),
		row.get("details",{}).get("entity",""),row.get("details",{}).get("key","")]

static func label(row: Dictionary) -> String:
	var prefix: String={"error":"Blocked","warning":"Issue","pending":"Checking","info":"Info","ok":"Ready"}.get(row["severity"],"Info")
	return prefix+" · "+row["details"].get("title",row["code"].replace("_"," ").capitalize())
