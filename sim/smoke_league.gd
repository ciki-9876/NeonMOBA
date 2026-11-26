extends SceneTree
## UI smoke test for the league (stage 2): menu [3] -> hub tabs -> my series: map veto, hero draft (human
## choices made by this script), one map watched as a real match (AI on both sides), one map skipped,
## watch / skip other series, next week, simulate to the end of the season. Any SCRIPT ERROR is a bug.
## godot --headless --fixed-fps 60 --script res://sim/smoke_league.gd
const C = preload("res://game/consts.gd")
const Draft = preload("res://game/league/draft.gd")
const Series = preload("res://game/league/series.gd")
const Season = preload("res://game/league/season.gd")
var main: Node
var f := 0
var phase := "start"
var wait := 0

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

func note(t: String) -> void:
	print("f%d [%s] %s" % [f, phase, t])

func _process(_d: float) -> bool:
	f += 1
	var lg = main.lg
	if wait > 0:
		wait -= 1
		return false
	match phase:
		"start":
			if f == 5:
				key(KEY_3)
			elif f == 10:
				for t in ["table", "teams", "stats", "news", "schedule"]:
					lg._set_tab(t)
				note("hub ok: %s" % lg.title.text)
				lg._open_series(Season.human_series(lg.season))
				phase = "veto"
		"veto":
			var v: Dictionary = lg.cur["veto"]
			if Draft.veto_action(v) == "done":
				note("maps %s" % str(v["maps"]))
				lg._start_map_draft()
				phase = "draft"
			elif Draft.veto_side(v) == lg.human_side:
				lg._human_veto(str(Draft.veto_left(v)[0]))
			else:
				wait = 30
		"draft":
			var d: Dictionary = lg.cur["draft"]
			if Draft.done(d):
				note("picks %s vs %s" % [str(d["picks"][0]), str(d["picks"][1])])
				lg._play_map(false)
				phase = "match"
			elif int(Draft.current(d)[1]) == lg.human_side:
				var cur: Array = Draft.current(d)
				lg._human_draft(str(Draft.available(d, lg.human_side, str(cur[0]))[0]))
			else:
				wait = 30
		"match":
			if main.gm.state == C.S.END:
				wait = 60
				phase = "end"
			elif f % 3000 == 0:
				note("t=%.0f score=%s" % [main.gm.t, str(main.gm.rounds.score)])
		"end":
			key(KEY_ENTER)
			phase = "after"
			wait = 10
		"after":
			note("series %s score %s maps %d" % [lg.cur["id"], str(lg.cur["score"]), (lg.cur["maps"] as Array).size()])
			# next map: draft by AI for both (human picks the first option), then skip it
			if not Series.done(lg.cur):
				lg._start_map_draft()
				phase = "draft2"
			else:
				phase = "hub"
		"draft2":
			var d2: Dictionary = lg.cur["draft"]
			if Draft.done(d2):
				lg._quick_map()
				note("quick map -> score %s" % str(lg.cur["score"]))
				if Series.done(lg.cur):
					phase = "hub"
				else:
					lg._start_map_draft()
			elif int(Draft.current(d2)[1]) == lg.human_side:
				var c2: Array = Draft.current(d2)
				lg._human_draft(str(Draft.available(d2, lg.human_side, str(c2[0]))[0]))
			else:
				wait = 20
		"hub":
			lg._back_to_hub()
			# watch-mode series of two AI teams: open it, skip it
			for s in Season.current_series(lg.season):
				if not Series.done(s):
					lg._open_series(s)
					lg._skip_series()
					break
			lg._skip_others()
			lg._advance()
			note("week now %d, news %d" % [int(lg.season["week"]), (lg.season["news"] as Array).size()])
			lg._sim_to_end()
			for t in ["table", "teams", "stats", "news", "schedule"]:
				lg._set_tab(t)
			note("season %s champion %s" % [lg.season["phase"], lg.season["champion"]])
			lg.new_season()
			key(KEY_ESCAPE)
			phase = "done"
			wait = 20
		"done":
			note("state %d (menu=%d)" % [main.gm.state, C.S.MENU])
			return true
	return f > 60 * 60 * 12
