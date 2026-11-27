shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform vec2 pixel_resolution = vec2(640.0, 360.0);

void fragment() {
	vec2 pixel = floor(SCREEN_UV * pixel_resolution);
	vec2 sample_uv = (pixel + vec2(0.5)) / pixel_resolution;
	COLOR = texture(screen_texture, sample_uv);
}
