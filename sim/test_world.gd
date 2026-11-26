extends SceneTree
## Checks of the M1 world mechanics and the M2 story engine. godot --headless --script res://sim/test_world.gd
const Season = preload("res://game/league/season.gd")
const World = preload("res://game/league/world.gd")
const People = preload("res://game/league/people.gd")
const Series = preload("res://game/league/series.gd")
const Story = preload("res://game/story/story.gd")
const Rules = preload("res://game/story/rules.gd")
var fails := 0

func check(name: String, ok: bool, info := "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if info == "" else "  (" + info + ")"))
	if not ok:
		fails += 1

func _initialize() -> void:
	# ---- fixed world is fixed
	var a: Dictionary = World.build_fixed(1, "rin")
	var b: Dictionary = World.build_fixed(999, "rin")
	var same := true
	for pid in a["players"]:
		if str(a["players"][pid]["cast"]) == "walkon":
			continue
		if not b["players"].has(pid) or var_to_str(a["players"][pid]["attrs"]) != var_to_str(b["players"][pid]["attrs"]):
			same = false
	check("the fixed world is the same in every run (except walk-ons)", same)
	var pot_diff := false
	for pid in ["zero", "rin", "rock", "fish"]:
		if float(a["players"][pid]["pot"]) != float(b["players"][pid]["pot"]):
			pot_diff = true
	check("realised potential differs between runs", pot_diff)
	# ---- match profile (战力管线)
	var w: Dictionary = a
	var bear: Dictionary = w["players"]["bear"]
	var mates := ["bear", "hero_pc", "fish"]
	var base: float = float(People.match_profile(w, bear, mates)["attrs"]["mechanics"])
	bear["fatigue"] = 75.0
	check("fatigue 75: one point down", is_equal_approx(float(People.match_profile(w, bear, mates)["attrs"]["mechanics"]), base - 1.0))
	bear["fatigue"] = 0.0
	bear["form"] = 2.0
	check("form +2: two points up", is_equal_approx(float(People.match_profile(w, bear, mates)["attrs"]["mechanics"]), base + 2.0))
	bear["form"] = 0.0
	var rin_tw: float = People.teamwork_mod(w, "rin", ["bear", "rin", "fish"])
	check("a new player (0 weeks) has a teamwork malus", rin_tw <= -1.9, "%.2f" % rin_tw)
	World.move_player(w, "rex", "spark")
	var rex_mates := ["rex", "hero_pc", "fish"]
	check("a Portuguese speaker with little English: worse communication", People.comm_level(w, rex_mates) < 2.0 and People.comm_mod(w, rex_mates) <= -0.5,
		"level %.2f mod %.2f" % [People.comm_level(w, rex_mates), People.comm_mod(w, rex_mates)])
	check("brothers in the lineup get a relation bonus", People.teamwork_mod(w, "hero_pc", mates) > People.comm_mod(w, mates), "%.2f" % People.teamwork_mod(w, "hero_pc", mates))
	# ---- lineups
	var l: Dictionary = People.best_lineup(w, "spark")
	check("best lineup: 3 different players, one per role", Series.valid_lineup(w, "spark", l), str(l))
	w["players"]["hero_pc"]["fatigue"] = 95.0
	w["players"]["hero_pc"]["form"] = -3.0
	var l2: Dictionary = People.best_lineup(w, "spark")
	check("an exhausted, out-of-form player is rested", not l2.values().has("hero_pc"), str(l2))
	# ---- seasons: leagues, promotion, aging, story
	var s: Dictionary = Season.create(42, {"pick": "mute"})
	var ages: int = int(s["world"]["players"]["zero"]["age"])
	# S1 week 5: the bear event is offered to the player
	for i in 4:
		Season.quick_rest(s, true)
		for hs in [Season.human_series(s)]:
			if not hs.is_empty() and not Series.done(hs):
				Series.quick_play(hs, s, Season.rng_of(s))
				Season.finish_series(s, hs)
		Season.advance(s)
	var pend: Array = Story.pending(s)
	var bear_ev := {}
	for it in pend:
		if str(it["event"]) == "bear_family_call":
			bear_ev = it
	check("S1 week 5: 大熊的家里来电 is waiting for the player", not bear_ev.is_empty(), str(pend.map(func(x): return x["event"])))
	if not bear_ev.is_empty():
		Story.resolve(s, int(bear_ev["uid"]), 0)
		check("choosing a raise keeps him (flag)", Story.state(s)["flags"].has("bear_stayed"))
		check("the bear note is still pending, the entry was changed", Story.state(s)["failed"].has("bear_family"))
	Season.quick_to_end(s)
	check("season ends with champions in both leagues", str(s["leagues"]["pro"]["champion"]) != "" and str(s["leagues"]["sec"]["champion"]) != "")
	var up: Array = s["moves"]["up"]
	var down: Array = s["moves"]["down"]
	var n: Dictionary = Season.next_season(s)
	check("next season: 8 + 8 clubs", (n["leagues"]["pro"]["teams"] as Array).size() == 8 and (n["leagues"]["sec"]["teams"] as Array).size() == 8)
	check("promoted clubs play pro", up.all(func(t): return (n["leagues"]["pro"]["teams"] as Array).has(t)), str(up))
	check("relegated clubs play sec", down.all(func(t): return (n["leagues"]["sec"]["teams"] as Array).has(t)), str(down))
	check("everyone is a year older", int(n["world"]["players"]["zero"]["age"]) == ages + 1)
	check("大熊 stayed after the raise", str(n["world"]["players"]["bear"]["team"]) == "spark" and not bool(n["world"]["players"]["bear"].get("retired", false)))
	check("the S1 story was settled", not Story.state(n)["happened"].has("bear_quit") and Story.state(n)["failed"].has("bear_quit"))
	check("history kept", (n["history"] as Array).size() == 1 and int(n["no"]) == 2)
	var stats := {}
	for nt in Story.notes(n):
		stats[nt["id"]] = nt["status"]
	check("notes: 大熊's note changed, 秦岚's is known", str(stats.get("n_bear", "")) == "changed" and stats.has("n_qin"), str(stats))
	# rosters valid all the time
	var ok := true
	for t in n["world"]["teams"]:
		if (t["players"] as Array).size() != 4:
			ok = false
	check("all clubs have 4 players after the off-season", ok)
	# ---- rules: unknown words are reported, fill works
	check("text placeholders", Rules.fill(n, "{zero} 和 {sky}") == "Zero 和 天穹", Rules.fill(n, "{zero} 和 {sky}"))
	print("RESULT %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
