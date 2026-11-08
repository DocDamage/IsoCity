shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D sprite_texture : source_color, filter_nearest;
uniform int turns = 0;
uniform float angle_radians = 0.0;
uniform bool diamond_ground = true;
uniform vec4 frame_region = vec4(0.0, 0.0, 1.0, 1.0);
uniform bool calibrated_source = false;
uniform vec2 source_back = vec2(0.5, 0.0);
uniform vec2 source_u = vec2(0.5, 0.5);
uniform vec2 source_v = vec2(-0.5, 0.5);
void fragment() {
	vec2 uv = UV;
	float c = cos(angle_radians);
	float s = sin(angle_radians);
	vec2 p = uv - vec2(0.5);
	uv = vec2(c * p.x + s * p.y, -s * p.x + c * p.y) + vec2(0.5);
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThanEqual(uv, vec2(1.0)))) { discard; }
	vec2 diamond = vec2(0.5 + 0.5 * (uv.x - uv.y), 0.5 * (uv.x + uv.y));
	if (!diamond_ground) { diamond = uv; }
	if (calibrated_source) { diamond = source_back + uv.x * source_u + uv.y * source_v; }
	if (any(lessThan(diamond, vec2(0.0))) || any(greaterThanEqual(diamond, vec2(1.0)))) { discard; }
	vec4 pixel = texture(sprite_texture, frame_region.xy + diamond * frame_region.zw);
	ALBEDO = pixel.rgb;
	ALPHA = pixel.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
