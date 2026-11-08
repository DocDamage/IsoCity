extends RefCounted

# CitizenPlan consumes rectangles in walking coordinates. Keep the actual
# polygon/height-band wall coverage instead of filling its entire bounding box:
# that box can cover an isometric building's clear front-door approach.
const STEP = 0.5
const MAX_STRIPS = 512
const MAX_SEGMENT_BOXES = 16384

static func bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty(): return Rect2()
	var result := Rect2(points[0], Vector2.ZERO)
	for point in points: result = result.expand(point)
	return result

static func polygon(points: PackedVector2Array) -> Array[Rect2]:
	var result: Array[Rect2] = []
	if points.size() < 3: return result
	var box: Rect2 = bounds(points)
	if not box.position.is_finite() or not box.size.is_finite(): return result
	if box.size.y <= 0: return [box]
	var count: int = clampi(ceili(box.size.y / STEP), 1, MAX_STRIPS)
	var height: float = box.size.y / count
	for row in count:
		var low: float = box.position.y + row * height
		var high: float = low + height
		var left: float = INF; var right: float = -INF
		for index in points.size():
			var a: Vector2 = points[index]; var b: Vector2 = points[(index + 1) % points.size()]
			if a.y >= low and a.y <= high: left = minf(left, a.x); right = maxf(right, a.x)
			if is_zero_approx(b.y - a.y): continue
			for level in [low, high]:
				var fraction: float = (level - a.y) / (b.y - a.y)
				if fraction >= 0 and fraction <= 1:
					var x: float = lerpf(a.x, b.x, fraction)
					left = minf(left, x); right = maxf(right, x)
		if left <= right: result.append(Rect2(left, low, right - left, height))
	return result

static func segments(points: PackedVector2Array) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for index in range(0, points.size() - 1, 2):
		var a: Vector2 = points[index]; var b: Vector2 = points[index + 1]
		if not a.is_finite() or not b.is_finite(): continue
		var length: Vector2 = (b - a).abs()
		var count: int = maxi(1, ceili(maxf(length.x, length.y) / STEP))
		# Very large/custom geometry stays conservative, with bounded preparation.
		if count > MAX_SEGMENT_BOXES - result.size(): return [bounds(points)]
		for step in count:
			var start: Vector2 = a.lerp(b, float(step) / count)
			var end: Vector2 = a.lerp(b, float(step + 1) / count)
			result.append(Rect2(start.min(end), (end - start).abs()))
	return result

static func metric(points: PackedVector2Array, transform_value: Transform2D) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		var world: Vector2 = transform_value * point
		result.append(Vector2(world.x / 16, world.y / 8))
	return result
