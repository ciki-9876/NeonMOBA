extends Node2D
## (moved out of main.gd)

var r0 := 10.0
var r1 := 120.0
var life := 0.35
var t := 0.0
var col := Color.WHITE
var width := 6.0
func _process(d: float) -> void:
	t += d
	queue_redraw()
	if t >= life:
		queue_free()
func _draw() -> void:
	var k := clampf(t / life, 0.0, 1.0)
	var rr := lerpf(r0, r1, 1.0 - pow(1.0 - k, 3.0))
	var c := col
	c.a = 1.0 - k
	draw_arc(Vector2.ZERO, rr, 0.0, TAU, 64, c, width * (1.0 - k) + 1.0)
