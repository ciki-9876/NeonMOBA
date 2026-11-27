extends Node2D
## (moved out of main.gd)

var cam_pos := Vector2.ZERO
var half := Vector2(1000, 640)
var pulse := 0.0
var tint := Color("53616a")
func _draw() -> void:
	var step := 384.0
	var minor_col := Color(tint.r, tint.g, tint.b, 0.035 + pulse * 0.02)
	var major_col := Color(tint.r, tint.g, tint.b, 0.075 + pulse * 0.03)
	var x := floorf((cam_pos.x - half.x) / step) * step
	while x < cam_pos.x + half.x:
		var major := posmod(int(roundf(x / step)), 3) == 0
		var width := 4.0 if major else 2.0
		draw_rect(Rect2(x - width * 0.5, cam_pos.y - half.y, width, half.y * 2.0), major_col if major else minor_col)
		x += step
	var y := floorf((cam_pos.y - half.y) / step) * step
	while y < cam_pos.y + half.y:
		var major := posmod(int(roundf(y / step)), 3) == 0
		var height := 4.0 if major else 2.0
		draw_rect(Rect2(cam_pos.x - half.x, y - height * 0.5, half.x * 2.0, height), major_col if major else minor_col)
		y += step
