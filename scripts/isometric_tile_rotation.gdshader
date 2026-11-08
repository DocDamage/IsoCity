shader_type canvas_item;

uniform int quarter_turns = 0;
uniform float angle_radians = 0.0;
uniform vec2 region_origin = vec2(0.0);
uniform int frame_columns = 1;
uniform vec2 tile_size = vec2(32.0, 16.0);
varying vec4 vertex_tint;

void vertex() {
	vertex_tint = COLOR;
}

void fragment() {
	// Rotate in the 2:1 ground plane, keeping the tile's diamond and atlas cell.
	vec2 pixel = UV / TEXTURE_PIXEL_SIZE;
	float frame = clamp(floor((pixel.x - region_origin.x) / tile_size.x), 0.0, float(frame_columns - 1));
	vec2 cell_origin = region_origin + vec2(frame * tile_size.x, 0.0);
	vec2 point = pixel - cell_origin - tile_size * 0.5;
	float c = cos(angle_radians);
	float s = sin(angle_radians);
	float ratio = tile_size.x / tile_size.y;
	vec2 source = vec2(c * point.x + s * point.y * ratio, -s * point.x / ratio + c * point.y);
	source += tile_size * 0.5;
	if (any(lessThan(source, vec2(0.0))) || any(greaterThanEqual(source, tile_size))) {
		COLOR = vec4(0.0);
	} else {
		vec2 sample_pixel = cell_origin + clamp(source, vec2(0.5), tile_size - vec2(0.5));
		COLOR = texture(TEXTURE, sample_pixel * TEXTURE_PIXEL_SIZE) * vertex_tint;
	}
}
