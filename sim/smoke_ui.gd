extends SceneTree
## UI smoke test: runs the real main scene headless and drives it through menus, both modes,
## shop, scoreboard, stats panel, end screen and restart. Any SCRIPT ERROR in the output is a bug.
## godot --headless --fixed-fps 60 --script res://sim/smoke_ui.gd

const C = preload("res://game/consts.gd")
var main: Node
var f := 0

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func key(k: Key, ctrl := false) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.pressed = pressed
		ev.ctrl_pressed = ctrl
		Input.parse_input_event(ev)

func click(button: MouseButton, pos: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		Input.parse_input_event(ev)

func _process(_d: float) -> bool:
	f += 1
	var gm = main.gm
	match f:
		5: key(KEY_1)
		10: main.mnu.menu_surv.get_child(0)
		12: gm._start_survival("ember")
		14: key(KEY_Q, true)
		20: key(KEY_Q)
		21: click(MOUSE_BUTTON_LEFT, Vector2(700, 300))
		25: key(KEY_F6)
		30: key(KEY_F7)
		40: key(KEY_B)
		45: main.shp._buy("tango")
		50: key(KEY_B)
		60: key(KEY_C)
		70: key(KEY_C)
		80: key(KEY_F8)
		90: click(MOUSE_BUTTON_RIGHT, Vector2(900, 500))
		44, 55, 65, 85, 100, 600, 1200: print("f%d t=%.2f shop=%s paused=%s hitstop=%.2f state=%d" % [f, gm.t, main.shp.shop_open, gm.paused, gm.hitstop, gm.state])
		2400: print("survival t=%.1f lv=%d kills=%d gold=%d" % [gm.t, gm.player.level, gm.kills, gm.player.gold])
		2410: key(KEY_ESCAPE)
		2415: key(KEY_Q)
		2420: key(KEY_2)
		2425: main.mnu._start_arena_from_menu()
		2430: key(KEY_F6)
		2440: key(KEY_TAB)
		2450: key(KEY_TAB)
		2460: key(KEY_F9)
		2470: key(KEY_B)
		2475: main.shp._buy("boots")
		2480: key(KEY_B)
		9000: print("arena t=%.1f score=%s state=%d" % [gm.t, gm.team_kills, gm.state])
		9010: gm._end(true)
		9100: key(KEY_R)
		9200: print("restarted state=%d mode=%d t=%.1f" % [gm.state, gm.mode, gm.t])
		9210: gm._end(false)
		9300: key(KEY_ESCAPE)
		9310: print("menu state=%d" % gm.state)
		9320: return true
	return false
