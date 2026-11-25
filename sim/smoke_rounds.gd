extends SceneTree
## UI smoke test for the round mode: menu -> 3V3 rounds setup -> play with the player on autopilot,
## buy/sell in the buy phase, scoreboard, until the map ends. Any SCRIPT ERROR in the output is a bug.
## godot --headless --fixed-fps 60 --script res://sim/smoke_rounds.gd

const C = preload("res://game/consts.gd")
var main: Node
var f := 0
var done_at := -1

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func key(k: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.pressed = pressed
		Input.parse_input_event(ev)

func _process(_d: float) -> bool:
	f += 1
	var gm = main.gm
	match f:
		5: key(KEY_1)
		10: main.mnu._start_arena_from_menu()
		12: key(KEY_F6)
		20: key(KEY_B)
		25: main.shp._buy("boots")
		30: main.shp._sell(0)
		35: key(KEY_B)
		40: key(KEY_TAB)
		60: key(KEY_TAB)
	if f % 1200 == 0 and gm.rounds != null:
		print("f%d t=%.0f round=%d phase=%s score=%s gold=%d inv=%s" % [f, gm.t, gm.rounds.round_n, gm.rounds.phase, gm.rounds.score, gm.player.gold, gm.player.inv])
	if gm.state == C.S.END and done_at < 0:
		done_at = f
		print("map over at t=%.0f score=%s history=%s" % [gm.t, gm.rounds.score, gm.rounds.history])
	if done_at > 0 and f > done_at + 120:
		key(KEY_R)
	if done_at > 0 and f > done_at + 240:
		print("restarted state=%d mode=%d round=%d" % [gm.state, gm.mode, gm.rounds.round_n if gm.rounds != null else -1])
		return true
	return f > 60 * 60 * 12
