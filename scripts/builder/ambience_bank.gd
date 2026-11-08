extends RefCounted
const CREDITS: String="res://assets/audio/LICENSE.txt"
const PATHS: Dictionary = {
	"traffic":"res://assets/audio/traffic.wav", "fountain":"res://assets/audio/fountain.wav",
	"birds":"res://assets/audio/birds.wav", "shop":"res://assets/audio/shop.wav",
	"interior":"res://assets/audio/interior.wav", "school":"res://assets/audio/school.wav",
	"arcade":"res://assets/audio/arcade.wav", "workshop":"res://assets/audio/workshop.wav",
	"market":"res://assets/audio/market.wav", "harbor":"res://assets/audio/harbor.wav",
}
static var streams: Dictionary={}
static func stream(kind: String) -> AudioStreamWAV:
	if not PATHS.has(kind): return null
	if not streams.has(kind):
		var value := load_loop(PATHS[kind])
		if value: streams[kind] = value
	return streams.get(kind)

static func load_loop(path: String) -> AudioStreamWAV:
	if not ResourceLoader.exists(path,"AudioStreamWAV"): return null
	var source := ResourceLoader.load(path,"AudioStreamWAV") as AudioStreamWAV
	if not source or source.get_length() <= 0: return null
	var value := source.duplicate() as AudioStreamWAV
	value.loop_mode = AudioStreamWAV.LOOP_FORWARD
	value.loop_begin = 0
	value.loop_end = roundi(value.get_length()*value.mix_rate)
	return value
