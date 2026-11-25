extends SceneTree
## Smoke test for the 3C experiment scene: scripted input drives every action of the sniper.
## godot --headless --fixed-fps 60 --script res://sim/smoke_3c.gd   (any SCRIPT ERROR in the output is a bug)
var a: Node
var f := 0
var max_zoom_out := 1.0
func _initialize() -> void:
	a = load("res://exp3c/exp3c.tscn").instantiate()
	root.add_child(a)
func _process(d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var s = a.sniper
	var tgt = a.dummies[f / 400 % a.dummies.size()]
	if f % 400 == 3:
		s.position = tgt.position + Vector2(-450, 60)   # stand within range of the next dummy
	var ph := f % 400
	a.test_input = {"move": Vector2(0, 1) if (f / 60) % 2 == 0 else Vector2(0, -1), "mouse": tgt.position,
		"lmb": ph < 150, "rmb": ph > 170 and ph < 290}
	if ph == 300: s.cast("q", a.test_input)
	if ph == 330: s.cast("e", a.test_input)
	if f == 1210: s.cast("r", a.test_input)
	max_zoom_out = minf(max_zoom_out, a.cam.zoom.x)
	if f % 800 == 0:
		print("f%d %s zoom_min=%.2f" % [f, a.stats, max_zoom_out])
	return f >= 3200
