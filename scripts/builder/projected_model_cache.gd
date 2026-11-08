extends Node

const MAX_ENTRIES = 96
const MAX_BYTES = 32*1024*1024
const MAX_PENDING = 32

var entries: Dictionary = {}
var pending: Dictionary = {}
var bytes: int = 0
var hits: int = 0
var misses: int = 0
var scheduled: bool = false

func request(key: String, make_view: Callable, consumer: Node) -> Texture2D:
	if entries.has(key):
		var entry: Dictionary = entries[key]
		entries.erase(key)
		entries[key] = entry
		hits += 1
		return entry["texture"]
	if not pending.has(key):
		if pending.size() >= MAX_PENDING: return null
		var viewport: SubViewport = make_view.call(self)
		pending[key] = {"viewport":viewport,"consumers":{}}
		misses += 1
		if not scheduled:
			scheduled = true
			RenderingServer.frame_post_draw.connect(_drawn,CONNECT_ONE_SHOT)
	var entry: Dictionary = pending[key]
	entry["consumers"][consumer.get_instance_id()] = weakref(consumer)
	return entry["viewport"].get_texture()

func _drawn() -> void:
	_finish.call_deferred()

func _finish() -> void:
	scheduled = false
	var rendered: Dictionary = pending
	pending = {}
	for key in rendered:
		var entry: Dictionary = rendered[key]
		var viewport: SubViewport = entry["viewport"]
		var image: Image = viewport.get_texture().get_image()
		var texture: Texture2D
		if image and not image.is_empty() and image.get_used_rect().has_area():
			texture = ImageTexture.create_from_image(image)
			store(key,texture,image.get_data_size())
		for reference in entry["consumers"].values():
			var node: Node = reference.get_ref()
			if is_instance_valid(node): node.finish_projection(key,texture)
		viewport.queue_free()

func store(key: String, texture: Texture2D, size: int) -> void:
	while not entries.is_empty() and (entries.size() >= MAX_ENTRIES or bytes+size > MAX_BYTES):
		var oldest: String = entries.keys()[0]
		bytes -= entries[oldest]["bytes"]
		entries.erase(oldest)
	if size <= MAX_BYTES:
		entries[key] = {"texture":texture,"bytes":size}
		bytes += size
