extends SceneTree
## Headless batch simulator (no window, no audio, no UI). Every hero is AI controlled.
##
## godot --headless --script res://sim/sim_cli.gd -- [options]
##   --mode M         rounds (default, the stage 1 core mode) | arena (old kill-race mode)
##   --games N        number of matches (default 10)
##   --seed S         first seed; match i uses S + i (default 1)
##   --a ids          team A heroes, comma separated; empty slot = random by role (default random)
##   --b ids          team B heroes
##   --diff D         AI difficulty 0-2 for the old arena mode (default 1)
##   --attr_a V       rounds: every ability of team A's players = V (1..20, default 11)
##   --attr_b V       rounds: same for team B
##   --set_a k=v,...  rounds: override single abilities of team A, e.g. reaction=18,mechanics=6
##   --set_b k=v,...  rounds: same for team B
##   --prof_a P       rounds: hero proficiency 0..100 of team A (default 60 = 精通)
##   --prof_b P
##   --runes_a r=n,.. rounds: rune page applied to every team A hero, e.g. r_vital=5,r_edge=5
##   --runes_b r=n,..
##   --sig_a id,..    rounds: signature abilities for team A (applied to the matching hero)
##   --sig_b id,..
##   --mirror         team B gets exactly team A's heroes (isolates player ability from the draft)
##   --ai_a k=v,...   tuning: override raw AI parameters of team A (react, dodge, aim_err, combo, aware_noise,
##                    obj_discipline, decide_err, follow, engage_delay), e.g. --ai_a dodge=0
##   --ai_b k=v,...
##   --check          determinism check: play every seed twice and compare the event trace
##   --out path       also write one JSON object per match to this file
## Prints one JSON line per match and a SUMMARY line (wins, length, and per-team metrics).

const MatchT = preload("res://game/match.gd")
const C = preload("res://game/consts.gd")
const Profiles = preload("res://game/profiles.gd")
const RunesDB = preload("res://game/runes_db.gd")

var gm: MatchT
var opt := {}
## steps between trace samples in the determinism check (lower = finer, for hunting divergences)
var trace_every := 600

func _initialize() -> void:
	opt = {"mode": "rounds", "games": "10", "seed": "1", "a": ",,", "b": ",,", "diff": "1", "check": false, "out": "",
		"attr_a": "11", "attr_b": "11", "set_a": "", "set_b": "", "prof_a": "60", "prof_b": "60",
		"runes_a": "", "runes_b": "", "sig_a": "", "sig_b": "", "trace_every": "600", "quiet": false, "mirror": false, "ai_a": "", "ai_b": ""}
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var k: String = args[i].trim_prefix("--")
		if k == "check" or k == "quiet" or k == "mirror":
			opt[k] = true
		elif i + 1 < args.size():
			opt[k] = args[i + 1]
			i += 1
		i += 1
	trace_every = int(opt["trace_every"])
	gm = MatchT.new()
	root.add_child(gm)
	var n := int(opt["games"])
	var s0 := int(opt["seed"])
	var f: FileAccess = null
	if str(opt["out"]) != "":
		f = FileAccess.open(str(opt["out"]), FileAccess.WRITE)
	var wins := [0, 0]
	var total_t := 0.0
	var total_kills := 0
	var total_rounds := 0
	var agg := [{}, {}]
	var wall0 := Time.get_ticks_msec()
	var mismatches := 0
	for gi in n:
		var mseed := s0 + gi
		var r := play(mseed)
		if bool(opt["check"]):
			var r2 := play(mseed)
			r["deterministic"] = r["trace"] == r2["trace"]
			if not r["deterministic"]:
				mismatches += 1
				var t1: PackedStringArray = str(r["trace"]).split("\n")
				var t2: PackedStringArray = str(r2["trace"]).split("\n")
				for j in mini(t1.size(), t2.size()):
					if t1[j] != t2[j]:
						printerr("first divergence (seed %d):\n  run1 %s\n  run2 %s" % [mseed, t1[j], t2[j]])
						break
		r.erase("trace")
		if not bool(opt["quiet"]):
			print(JSON.stringify(r))
		if f != null:
			f.store_line(JSON.stringify(r))
		if int(r["winner"]) >= 0:
			wins[int(r["winner"])] += 1
		total_t += float(r["time"])
		total_kills += int(r["kills"][0]) + int(r["kills"][1])
		total_rounds += int(r.get("rounds_played", 0))
		for hh in r["heroes"]:
			var a: Dictionary = agg[int(hh["team"])]
			for k in hh["stats"]:
				a[k] = float(a.get(k, 0.0)) + float(hh["stats"][k])
	var wall := (Time.get_ticks_msec() - wall0) / 1000.0
	var line := "SUMMARY mode=%s games=%d  wins A:B=%d:%d (A %.0f%%)  avg_len=%.0fs  kills/min=%.2f" % [
		opt["mode"], n, wins[0], wins[1], 100.0 * wins[0] / maxf(wins[0] + wins[1], 1), total_t / maxf(n, 1), total_kills / maxf(total_t / 60.0, 0.01)]
	if str(opt["mode"]) == "rounds":
		line += "  rounds/map=%.1f" % (float(total_rounds) / maxf(n, 1))
		for tm in 2:
			var a: Dictionary = agg[tm]
			line += "  | %s: shot_acc=%.0f%% dodge=%.0f%% tele_taken/map=%.1f dmg/map=%.0f" % ["A" if tm == 0 else "B",
				100.0 * float(a.get("shot_hit", 0.0)) / maxf(float(a.get("shot_fired", 0.0)), 1.0),
				100.0 * float(a.get("dodge_try", 0.0)) / maxf(float(a.get("dodge_seen", 0.0)), 1.0),
				float(a.get("tele_taken", 0.0)) / maxf(n, 1), float(a.get("dmg_hero", 0.0)) / maxf(n, 1)]
	line += "  wall=%.1fs (%.2fs/match%s)" % [wall, wall / maxf(n, 1) / (2.0 if bool(opt["check"]) else 1.0), ", each played twice" if bool(opt["check"]) else ""]
	if bool(opt["check"]):
		line += "  DETERMINISM: %s" % ("OK" if mismatches == 0 else "%d MISMATCH" % mismatches)
	print(line)
	quit(1 if mismatches > 0 else 0)

func _team(spec: String) -> Array:
	var ids := []
	for id in spec.split(",", true):
		ids.append(id.strip_edges())
	while ids.size() < C.TEAM_SIZE:
		ids.append("")
	return ids.slice(0, C.TEAM_SIZE)

func _kv(spec: String) -> Dictionary:
	var out := {}
	for part in spec.split(",", false):
		var kv := part.split("=")
		out[kv[0].strip_edges()] = float(kv[1]) if kv.size() > 1 else 1.0
	return out

func _profiles(side: String, ids: Array) -> Array:
	var out := []
	var sets := _kv(str(opt["set_" + side]))
	var sigs: PackedStringArray = str(opt["sig_" + side]).split(",", false)
	for i in ids.size():
		var hid := str(ids[i])
		var p := Profiles.make("%s%d" % [side.to_upper(), i + 1], int(opt["attr_" + side]), {hid: float(opt["prof_" + side])}, {})
		for k in sets:
			p["attrs"][k] = int(sets[k])
		var over := _kv(str(opt["ai_" + side]))
		if not over.is_empty():
			p["ai_over"] = over
		for sid in sigs:
			if RunesDB.SIGNATURES.has(sid) and str(RunesDB.SIGNATURES[sid]["hero"]) == hid:
				p["sig"][hid] = sid
		out.append(p)
	return out

func _runes(side: String, ids: Array) -> Dictionary:
	var page := {}
	var kv := _kv(str(opt["runes_" + side]))
	for rid in kv:
		page[rid] = int(kv[rid])
	var out := {}
	for hid in ids:
		out[hid] = page
	return out

func play(mseed: int) -> Dictionary:
	gm.reseed(mseed)
	var a := _team(str(opt["a"]))
	var b := _team(str(opt["b"]))
	gm._fill_random(a)
	gm._fill_random(b)
	if bool(opt["mirror"]):
		b = a.duplicate()
	var rounds_mode := str(opt["mode"]) == "rounds"
	if rounds_mode:
		gm._start_rounds(a, b, int(opt["diff"]), mseed, {"human": false,
			"profiles": [_profiles("a", a), _profiles("b", b)], "runes": [_runes("a", a), _runes("b", b)]})
	else:
		gm._start_arena(a, b, int(opt["diff"]), mseed)
		gm.set_autopilot(true)
	var trace := PackedStringArray()
	var steps := 0
	var max_steps := int(((C.ARENA_LEN + 30.0) if not rounds_mode else 1500.0) / MatchT.DT)
	var last_k := [0, 0]
	while gm.state == C.S.PLAY and steps < max_steps:
		gm.step(MatchT.DT)
		steps += 1
		if gm.team_kills[0] != last_k[0] or gm.team_kills[1] != last_k[1] or steps % trace_every == 0:
			last_k = gm.team_kills.duplicate()
			var tl := "%d|%d:%d" % [steps, last_k[0], last_k[1]]
			for h in gm.heroes:
				tl += "|%.2f,%.2f,%.1f" % [h.position.x, h.position.y, h.hp]
			trace.append(tl)
	var heroes := []
	for h in gm.heroes:
		heroes.append({"id": str(h.hid), "name": str(h.def["short"]), "team": h.team, "lv": h.level,
			"k": h.kills, "d": h.deaths, "a": h.assists, "gold": int(h.gold), "heal": int(h.heal_done),
			"items": h.inv.duplicate(), "stats": h.stats.duplicate()})
	var w := -1
	var res := {"seed": mseed, "a": a, "b": b, "kills": gm.team_kills.duplicate(), "time": snappedf(gm.t, 0.1), "heroes": heroes}
	if rounds_mode:
		var r = gm.rounds
		if r.score[0] != r.score[1]:
			w = 0 if r.score[0] > r.score[1] else 1
		res["score"] = r.score.duplicate()
		res["rounds_played"] = r.history.size()
		res["rounds"] = r.history.duplicate()
	elif gm.team_kills[0] != gm.team_kills[1]:
		w = 0 if gm.team_kills[0] > gm.team_kills[1] else 1
	res["winner"] = w
	res["trace"] = "\n".join(trace)
	return res
