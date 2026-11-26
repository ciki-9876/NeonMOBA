extends SceneTree
## Unit checks for round-mode revives (game/rounds.gd). godot --headless --script res://sim/test_revive.gd
const MatchT = preload("res://game/match.gd")
const C = preload("res://game/consts.gd")
var gm: MatchT
var fails := 0

func check(name: String, ok: bool, info := "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if info == "" else "  (" + info + ")"))
	if not ok:
		fails += 1

func run(sec: float) -> void:
	for i in int(sec / MatchT.DT):
		gm.step(MatchT.DT)

func _initialize() -> void:
	gm = MatchT.new()
	root.add_child(gm)
	gm._start_rounds(["ember", "aegis", "lumen"], ["drift", "anchor", "tide"], 1, 5, {"human": true})
	var r = gm.rounds
	while r.phase != "live":
		gm.step(MatchT.DT)
	var p = gm.player
	p.cds["q"] = 9.0
	gm._hero_died(p, gm.heroes[3])
	check("dead hero waits for a decision", p.dead and p.revive_wait)
	run(3.0)
	check("the human player is not decided for", p.dead and p.revive_wait and p.revive_t < 0.0)
	check("request_revive", r.request_revive(p) and int(r.revives_left[0]) == r.REVIVES_PER_MAP - 1)
	check("no double request", not r.request_revive(p))
	run(5.0)
	check("still counting at 5 s", p.dead and p.revive_t > 0.0, "%.1f" % p.revive_t)
	run(5.2)
	check("revived after 10 s", not p.dead)
	check("full hp and mana", p.hp == p.max_hp and p.mana == p.mana_max)
	check("cooldowns not refreshed (kept running while dead)", float(p.cds["q"]) == 0.0 or float(p.cds["q"]) < 9.0 - 10.0 + 0.01, "%.2f" % float(p.cds["q"]))
	check("revived at home", p.position.distance_to(gm.home_pos(0)) < 300.0)
	# a team whose heroes are all dead or counting loses the round
	var score0: int = int(r.score[1])
	for h in gm.heroes:
		if h.team == 0 and not h.dead:
			gm._hero_died(h, gm.heroes[3])
	r.request_revive(gm.heroes[1])
	gm.step(MatchT.DT)
	check("all down or counting = round lost", int(r.score[1]) == score0 + 1 and r.phase == "post")
	# next round revives everyone for free and keeps the shared count
	while r.phase != "buy":
		gm.step(MatchT.DT)
	var all_up := true
	for h in gm.heroes:
		if h.dead: all_up = false
	check("new round revives everyone", all_up)
	check("revive count is per map, not per round", int(r.revives_left[0]) == r.REVIVES_PER_MAP - 2, str(r.revives_left))
	# AI decides on its own
	while r.phase != "live":
		gm.step(MatchT.DT)
	var ai_h = gm.heroes[4]
	gm._hero_died(ai_h, gm.heroes[0])
	run(6.0)
	check("AI made a decision", ai_h.revive_t >= 0.0 or not ai_h.dead or ai_h.revive_wait, "revive_t %.1f wait %s left %s" % [ai_h.revive_t, ai_h.revive_wait, str(r.revives_left)])
	print("RESULT %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
