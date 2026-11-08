extends RefCounted
const MAX_FRAME=32*1024*1024
const MAX_QUEUE=64*1024*1024
var socket: StreamPeerTCP
var incoming:=PackedByteArray()
var outgoing:=PackedByteArray()
var messages: Array[Dictionary]=[]
var failed: bool=false
var max_frame: int=MAX_FRAME
var connected_once: bool=false
func _init(peer: StreamPeerTCP) -> void: socket=peer; socket.set_no_delay(true)
func send(value: Dictionary) -> bool:
	var body: PackedByteArray=JSON.stringify(value).to_utf8_buffer()
	if body.is_empty() or body.size()>MAX_FRAME or outgoing.size()+body.size()+4>MAX_QUEUE: failed=true; return false
	var header:=PackedByteArray(); header.resize(4); header.encode_u32(0,body.size()); outgoing.append_array(header); outgoing.append_array(body); return true
func step() -> void:
	if failed: return
	if socket.poll()!=OK: failed=true; return
	var status: int=socket.get_status()
	if status==StreamPeerTCP.STATUS_CONNECTED: connected_once=true
	elif status==StreamPeerTCP.STATUS_ERROR or (connected_once and status==StreamPeerTCP.STATUS_NONE): failed=true; return
	else: return
	if not outgoing.is_empty():
		var result: Array=socket.put_partial_data(outgoing.slice(0,mini(outgoing.size(),256*1024)))
		if result[0]!=OK: failed=true; return
		outgoing=outgoing.slice(int(result[1]))
	var available: int=socket.get_available_bytes()
	if available>0:
		var result: Array=socket.get_partial_data(mini(available,256*1024))
		if result[0]!=OK: failed=true; return
		incoming.append_array(result[1])
	for packet in 16:
		if incoming.size()<4: break
		var length: int=incoming.decode_u32(0)
		if length<2 or length>max_frame: failed=true; return
		if incoming.size()<length+4: break
		var parser:=JSON.new(); var error: Error=parser.parse(incoming.slice(4,4+length).get_string_from_utf8()); incoming=incoming.slice(4+length)
		if error!=OK or not parser.data is Dictionary: failed=true; return
		messages.append(parser.data)
	if incoming.size()>max_frame+4: failed=true
func close() -> void:
	socket.disconnect_from_host(); failed=true; incoming.clear(); outgoing.clear(); messages.clear()
