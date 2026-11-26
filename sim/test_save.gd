extends SceneTree
## Save / load and weekly training checks. godot --headless --script res://sim/test_save.gd
const Season = preload("res://game/league/season.gd")
const Training = preload("res://game/league/training.gd")
const Save = preload("res://game/save.gd")
const World = preload("res://game/league/world.gd")
const Profiles = preload("res://game/profiles.gd")
var fails := 0

func check(name: String, ok: bool, info := "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if info == "" else "  (" + info + ")"))
	if not ok:
		fails += 1

func _initialize() -> void:
	# --- save / load round trip, and the loaded season plays on exactly like the original
	var a: Dictionary = Season.create(77)
	for _i in 2:
		Season.quick_rest(a, false)
		Season.advance(a)
	check("save succeeds", Save.save_season(a, "test"))
	var peek: Dictionary = Save.peek("test")
	check("peek header", str(peek.get("phase", "")) == "regular" and int(peek.get("week", -1)) == 2, str(peek))
	var b: Dictionary = Save.load_season("test")
	check("load returns the season", not b.is_empty())
	check("identical after the round trip", var_to_str(a) == var_to_str(b))
	check("colors survive", (b["world"]["teams"][0]["col"] as Color) == (a["world"]["teams"][0]["col"] as Color))
	Season.quick_to_end(a)
	Season.quick_to_end(b)
	check("loaded season ends the same", str(a["champion"]) == str(b["champion"]) and var_to_str(Season.standings(a)) == var_to_str(Season.standings(b)))
	check("broken file is rejected", _broken())
	Save.delete("test")
	check("delete", not Save.exists("test"))
	# --- training
	var s: Dictionary = Season.create(5)
	var me: Dictionary = World.team(s["world"], str(s["human"]))
	var pid: String = str(me["players"][0])
	var p: Dictionary = s["world"]["players"][pid]
	var before: int = int(p["attrs"]["reaction"])
	Training.set_plan(s, pid, "attr:reaction")
	check("not committed yet", not Training.committed(s))
	var lines: Array = Training.commit_human(s)
	check("committed, 4 reports", Training.committed(s) and lines.size() == 4)
	check("second commit does nothing", Training.commit_human(s).is_empty())
	check("fatigue rose", float(p["fatigue"]) > 0.0, str(p["fatigue"]))
	var xp_total: float = float(p["xp"].get("reaction", 0.0)) + 100.0 * (int(p["attrs"]["reaction"]) - before)
	check("experience gained", xp_total > 0.0)
	# rest
	p["fatigue"] = 80.0
	Training.apply_plan(p, "rest", RandomNumberGenerator.new())
	check("rest lowers fatigue", float(p["fatigue"]) < 60.0, str(p["fatigue"]))
	# tiredness penalty
	p["fatigue"] = 75.0
	var q: Dictionary = Training.in_form(p)
	check("tired player is 1 point down", int(q["attrs"]["mechanics"]) == int(p["attrs"]["mechanics"]) - 1 and q != p)
	check("original sheet untouched", int(p["attrs"]["mechanics"]) >= 1)
	p["fatigue"] = 10.0
	check("fresh player: same dict", Training.in_form(p) == p)
	# hero training and signature bonus
	var hid := ""
	for h in p["sig"]:
		hid = str(h)
	if hid != "":
		p["fatigue"] = 0.0
		var pr0: float = float(p["prof"][hid])
		p["prof"][hid] = 50.0
		Training.apply_plan(p, "hero:" + hid, RandomNumberGenerator.new())
		check("signature hero proficiency grows", float(p["prof"][hid]) > 55.0, str(p["prof"][hid]))
		p["prof"][hid] = pr0
	# a whole season keeps the abilities inside 1..20 and the stage keys advance
	var ok := true
	var t: Dictionary = Season.create(9)
	Season.quick_to_end(t)
	for pid2 in t["world"]["players"]:
		for k in Profiles.ATTRS:
			var v: int = int(t["world"]["players"][pid2]["attrs"][k])
			if v < 1 or v > 20:
				ok = false
	check("abilities stay in 1..20 over a season", ok)
	check("season finished with training on", str(t["phase"]) == "done")
	print("RESULT %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)

func _broken() -> bool:
	var f := FileAccess.open("user://league_bad.sav", FileAccess.WRITE)
	f.store_string("garbage\nnot a save")
	f.close()
	var r: Dictionary = Save.load_season("bad")
	Save.delete("bad")
	return r.is_empty()
