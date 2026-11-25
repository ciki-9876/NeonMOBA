extends SceneTree
## Headless batch simulator for 3V3 matches (no window, no audio, no UI).
##
## godot --headless --script res://sim/sim_cli.gd -- [options]
##   --games N        number of matches (default 10)
##   --seed S         first seed; match i uses S + i (default 1)
##   --a ids          team A heroes, comma separated, empty slot = random by role (default random)
##   --b ids          team B heroes (default random)
##   --diff D         AI difficulty 0-2 (default 1)
##   --check          determinism check: play every seed twice and compare the event trace
##   --out path       also write one JSON object per match to this file
## Prints one JSON line per match and a summary.

const MatchT = preload("res://game/match.gd")
const C = preload("res://game/consts.gd")
const HeroesDB = preload("res://heroes_db.gd")

var gm: MatchT
## steps between trace samples in the determinism check (lower = finer, for hunting divergences)
var trace_every := 600

func _initialize() -> void:
	var opt := {"games": "10", "seed": "1", "a": ",,", "b": ",,", "diff": "1", "check": false, "out": ""}
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var k: String = args[i].trim_prefix("--")
		if k == "check":
			opt["check"] = true
		elif i + 1 < args.size():
			opt[k] = args[i + 1]
			i += 1
		i += 1
	trace_every = int(opt.get("trace_every", "600"))
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
	var wall0 := Time.get_ticks_msec()
	var mismatches := 0
	for g in n:
		var mseed := s0 + g
		var r := play(str(opt["a"]), str(opt["b"]), int(opt["diff"]), mseed)
		if bool(opt["check"]):
			var r2 := play(str(opt["a"]), str(opt["b"]), int(opt["diff"]), mseed)
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
		print(JSON.stringify(r))
		if f != null:
			f.store_line(JSON.stringify(r))
		if int(r["winner"]) >= 0:
			wins[int(r["winner"])] += 1
		total_t += float(r["time"])
		total_kills += int(r["kills"][0]) + int(r["kills"][1])
	var wall := (Time.get_ticks_msec() - wall0) / 1000.0
	print("SUMMARY games=%d  wins A:B=%d:%d  avg_len=%.0fs  kills/min=%.2f  wall=%.1fs (%.2fs per match%s)%s" % [
		n, wins[0], wins[1], total_t / maxf(n, 1), total_kills / maxf(total_t / 60.0, 0.01), wall,
		wall / maxf(n, 1) / (2.0 if bool(opt["check"]) else 1.0), ", each played twice" if bool(opt["check"]) else "",
		("  DETERMINISM: %s" % ("OK" if mismatches == 0 else "%d MISMATCH" % mismatches)) if bool(opt["check"]) else ""])
	quit(1 if mismatches > 0 else 0)

func _team(spec: String) -> Array:
	var ids := []
	for id in spec.split(",", true):
		ids.append(id.strip_edges())
	while ids.size() < C.TEAM_SIZE:
		ids.append("")
	return ids.slice(0, C.TEAM_SIZE)

func play(a_spec: String, b_spec: String, diff: int, mseed: int) -> Dictionary:
	gm.reseed(mseed)
	var a := _team(a_spec)
	var b := _team(b_spec)
	gm._fill_random(a)
	gm._fill_random(b)
	gm._start_arena(a, b, diff, mseed)
	gm.set_autopilot(true)
	var trace := PackedStringArray()
	var steps := 0
	var max_steps := int((C.ARENA_LEN + 30.0) / MatchT.DT)
	var last_k := [0, 0]
	while gm.state == C.S.PLAY and steps < max_steps:
		gm.step(MatchT.DT)
		steps += 1
		if gm.team_kills[0] != last_k[0] or gm.team_kills[1] != last_k[1] or steps % trace_every == 0:
			last_k = gm.team_kills.duplicate()
			var line := "%d|%d:%d" % [steps, last_k[0], last_k[1]]
			for h in gm.heroes:
				line += "|%.2f,%.2f,%.1f" % [h.position.x, h.position.y, h.hp]
			trace.append(line)
	var heroes := []
	for h in gm.heroes:
		heroes.append({"id": h.def_id if "def_id" in h else str(h.def["short"]), "team": h.team, "lv": h.level,
			"k": h.kills, "d": h.deaths, "a": h.assists, "gold": int(h.gold), "heal": int(h.heal_done)})
	var w := -1
	if gm.team_kills[0] != gm.team_kills[1]:
		w = 0 if gm.team_kills[0] > gm.team_kills[1] else 1
	return {"seed": mseed, "a": a, "b": b, "winner": w, "kills": gm.team_kills.duplicate(), "time": snappedf(gm.t, 0.1),
		"heroes": heroes, "trace": "\n".join(trace)}
