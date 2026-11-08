shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float focus_band = 0.55;
uniform float band_width = 0.3;
uniform float amount = 0.15;
void fragment() {
 float distance_from_band = max(0.0, abs(SCREEN_UV.y - focus_band) - band_width * 0.5);
 float blur_level = smoothstep(0.0, 0.25, distance_from_band) * amount * 4.0;
 COLOR = textureLod(screen_texture, SCREEN_UV, blur_level);
}
