extends RefCounted

const LIMIT: int = 16384

static func stamp(center: Vector2i, width: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var radius: int = clampi(width, 1, 5) / 2
	for x in range(center.x - radius, center.x + radius + 1):
		for y in range(center.y - radius, center.y + radius + 1): result.append(Vector2i(x, y))
	return result

static func line(a: Vector2i, b: Vector2i, width: int = 1) -> Array[Vector2i]:
	var cells: Dictionary = {}
	var current := a
	var distance := Vector2i(absi(b.x - a.x), absi(b.y - a.y))
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var error: int = distance.x - distance.y
	while cells.size() < LIMIT:
		for cell in stamp(current, width):
			if cells.size() < LIMIT: cells[cell] = true
		if current == b: break
		var twice: int = error * 2
		if twice > -distance.y: error -= distance.y; current.x += step.x
		if twice < distance.x: error += distance.x; current.y += step.y
	var result: Array[Vector2i] = []
	result.assign(cells.keys())
	return result

static func rectangle(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
		for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
			if result.size() == LIMIT: return result
			result.append(Vector2i(x, y))
	return result

static func flood(seed: Vector2i, surfaces: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not surfaces.has(seed) or not surfaces[seed].get("editable", true): return result
	var asset: String = surfaces[seed]["asset"]
	var queue: Array[Vector2i] = [seed]
	var visited: Dictionary = {seed: true}
	var cursor: int = 0
	while cursor < queue.size() and result.size() < LIMIT:
		var cell: Vector2i = queue[cursor]
		cursor += 1
		if not surfaces.has(cell) or surfaces[cell]["asset"] != asset or not surfaces[cell].get("editable", true): continue
		result.append(cell)
		for offset in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var next: Vector2i = cell + offset
			if not visited.has(next): visited[next] = true; queue.append(next)
	return result
