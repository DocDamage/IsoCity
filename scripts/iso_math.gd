class_name IsoMath
extends RefCounted

## 2:1 Isometric Grid Math for 32x16 pixel diamonds
## One floor tile = a 32x16 px diamond.
## Tile (i, j) has its back (top) corner at screen:
##   x = 16 * (i - j)
##   y = 8 * (i + j) - elevation * 8

const TILE_WIDTH: int = 32
const TILE_HEIGHT: int = 16
const HALF_WIDTH: int = 16
const HALF_HEIGHT: int = 8

static func tile_to_world(tile: Vector2i, elevation: int = 0) -> Vector2:
	var wx: float = float(HALF_WIDTH * (tile.x - tile.y))
	var wy: float = float(HALF_HEIGHT * (tile.x + tile.y) - elevation * HALF_HEIGHT)
	return Vector2(wx, wy)

static func world_to_tile(world: Vector2, elevation: int = 0) -> Vector2i:
	var adjusted_y: float = world.y + float(elevation * HALF_HEIGHT)
	var x_div: float = world.x / float(HALF_WIDTH)
	var y_div: float = adjusted_y / float(HALF_HEIGHT)
	var ti: int = int(floor((y_div + x_div) * 0.5))
	var tj: int = int(floor((y_div - x_div) * 0.5))
	return Vector2i(ti, tj)

static func get_footprint_diamond(tile: Vector2i, footprint: Vector2i, elevation: int = 0) -> PackedVector2Array:
	# 4 corners of footprint on floor level
	# Back corner (tile.x, tile.y)
	var top_corner: Vector2 = tile_to_world(tile, elevation)
	# Right corner (tile.x + footprint.x, tile.y)
	var right_corner: Vector2 = tile_to_world(tile + Vector2i(footprint.x, 0), elevation)
	# Front corner (tile.x + footprint.x, tile.y + footprint.y)
	var bottom_corner: Vector2 = tile_to_world(tile + footprint, elevation)
	# Left corner (tile.x, tile.y + footprint.y)
	var left_corner: Vector2 = tile_to_world(tile + Vector2i(0, footprint.y), elevation)
	
	return PackedVector2Array([top_corner, right_corner, bottom_corner, left_corner])

