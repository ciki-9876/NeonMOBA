extends Node2D
## (moved out of main.gd)

var cam_pos := Vector2.ZERO
var half := Vector2(1000, 640)
var pulse := 0.0
var tint := Color(0.2, 0.4, 1.0)
func _draw() -> void:
	var step := 64.0
	var col := Color(tint.r, tint.g, tint.b, 0.16 + pulse * 0.3)
	var x := floorf((cam_pos.x - half.x) / step) * step
	while x < cam_pos.x + half.x:
		var major := posmod(int(roundf(x / step)), 4) == 0
		draw_line(Vector2(x, cam_pos.y - half.y), Vector2(x, cam_pos.y + half.y), col * Color(1, 1, 1, 2.0 if major else 1.0), 2.0 if major else 1.0)
		x += step
	var y := floorf((cam_pos.y - half.y) / step) * step
	while y < cam_pos.y + half.y:
		var major := posmod(int(roundf(y / step)), 4) == 0
		draw_line(Vector2(cam_pos.x - half.x, y), Vector2(cam_pos.x + half.x, y), col * Color(1, 1, 1, 2.0 if major else 1.0), 2.0 if major else 1.0)
		y += step
