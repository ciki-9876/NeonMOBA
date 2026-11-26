extends SceneTree
## Headless league season (stages 2–3, M1/M2). Plays a whole season and prints standings, playoffs, awards and news.
##   godot --headless --script res://sim/season_cli.gd -- [--seed N] [--full K] [--seasons S] [--out file.json]
##   --replay N   N careers of --years Y seasons (default 5) with no intervention: how often the original history
##                (game/story/events_db.gd TIMELINE) happens; --intervene 1 = the human club signs 秦岚 and Rex in S1
##   --full K     the human team's first K series are played as real matches (game/match.gd, AI on both sides)
##                instead of the instant resolver: exercises the draft -> match -> result path end to end
##   --seasons S  run S seasons (seeds N, N+1, ...) and print aggregate checks only
##   --train S    with --seasons: how the human team trains: none | auto | smart (default auto); prints its results
##   --calib M    compare the quick resolver with the full simulation on M maps of random drafted lineups
const Season = preload("res://game/league/season.gd")
const Series = preload("res://game/league/series.gd")
const Bridge = preload("res://game/league/match_bridge.gd")
const QuickSim = preload("res://game/league/quick_sim.gd")
const Stories = preload("res://game/league/stories.gd")
const Training = preload("res://game/league/training.gd")
const World = preload("res://game/league/world.gd")
const HeroesDB = preload("res://heroes_db.gd")
const Profiles = preload("res://game/profiles.gd")
const MatchT = preload("res://game/match.gd")
const C = preload("res://game/consts.gd")

var gm: MatchT

func _initialize() -> void:
	var opt := {"seed": "1", "full": "0", "seasons": "1", "out": "", "calib": "0", "train": "", "replay": "0", "years": "5", "intervene": "0"}
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var k: String = args[i].trim_prefix("--")
		if i + 1 < args.size():
			opt[k] = args[i + 1]
		i += 2
	gm = MatchT.new()
	root.add_child(gm)
	if int(opt["replay"]) > 0:
		_replay(int(opt["replay"]), int(opt["seed"]), int(opt["years"]), int(opt["intervene"]) > 0)
		quit()
		return
	if int(opt["calib"]) > 0:
		_calib(int(opt["calib"]), int(opt["seed"]))
		quit()
		return
	var n_s := int(opt["seasons"])
	if str(opt["train"]) != "":
		_train_test(n_s, int(opt["seed"]), str(opt["train"]))
		quit()
		return
	if n_s > 1:
		_many(n_s, int(opt["seed"]))
		quit()
		return
	var season: Dictionary = Season.create(int(opt["seed"]))
	var full_left := int(opt["full"])
	var guard := 0
	while str(season["phase"]) != "done" and guard < 60:
		guard += 1
		var hs: Dictionary = Season.human_series(season)
		if not hs.is_empty() and not Series.done(hs) and full_left > 0:
			full_left -= 1
			_play_full(season, hs)
			Season.finish_series(season, hs)
		Season.quick_rest(season, false)
		Season.advance(season)
	_report(season)
	if str(opt["out"]) != "":
		var f := FileAccess.open(str(opt["out"]), FileAccess.WRITE)
		f.store_string(JSON.stringify({"news": season["news"], "awards": season.get("awards", {}), "standings": Season.standings(season, "pro"),
			"leaderboard": Stories.leaderboard(season).slice(0, 10), "hstats": season["hstats"], "champion": season["champion"]}, "  "))
	quit()

## a series with real matches for every map (both teams AI-driven, the human team plays as team 0)
func _play_full(season: Dictionary, s: Dictionary) -> void:
	var rng := Season.rng_of(season)
	var world: Dictionary = season["world"]
	Series.ai_veto(s, season, rng)
	while not Series.done(s):
		Series.start_draft(s, world)
		Series.ai_draft(s, world, rng)
		var args: Dictionary = Bridge.match_args(s, world, str(season["human"]), false)
		args["setup"]["league"] = true
		gm._start_rounds(args["a"], args["b"], 1, rng.randi() % 100000, args["setup"])
		var steps := 0
		while gm.state == C.S.PLAY and steps < int(1500.0 / MatchT.DT):
			gm.step(MatchT.DT)
			steps += 1
		var res: Dictionary = Bridge.result_from(gm, s, bool(args["swap"]))
		print("  full map %s  %s %d:%d  (%s)" % [res["map"], s["a"] + " vs " + s["b"], res["score"][0], res["score"][1], res["winner_tid"]])
		Series.record_map(s, res)
	Season.save_rng(season, rng)

func _report(season: Dictionary) -> void:
	for lg in Season.LEAGUES:
		print("== standings %s" % lg)
		for r in Season.standings(season, lg):
			print("  %-6s %-6s  %d-%d  maps %d-%d" % [r["id"], r["name"], r["w"], r["l"], r["mw"], r["ml"]])
		for st in season["leagues"][lg]["playoffs"]:
			for s in st:
				print("  %s  %s %d:%d %s  -> %s" % [s["kind"], Stories.team_name(season, s["a"]), s["score"][0], s["score"][1], Stories.team_name(season, s["b"]), Stories.team_name(season, s["winner"])])
		print("  champion: %s" % Stories.team_name(season, str(season["leagues"][lg]["champion"])))
	print("== moves up %s down %s" % [str(season["moves"]["up"]), str(season["moves"]["down"])])
	print("== leaderboard")
	for r in Stories.leaderboard(season).slice(0, 6):
		print("  %-6s %-6s maps %d  %d/%d/%d  kda %.1f  dmg/map %d  mvp %d" % [r["name"], r["team"], r["maps"], r["k"], r["d"], r["a"], r["kda"], int(float(r["dmg"]) / maxf(1, r["maps"])), r["mvp"]])
	print("== news (%d)" % (season["news"] as Array).size())
	for n in season["news"]:
		print("  [w%d %s] %s" % [int(n["week"]) + 1, n["kind"], n["text"]])

## many seasons: do stronger clubs win more, how often upsets, are stories varied
func _many(n: int, seed0: int) -> void:
	var tier_w := {1: [0, 0], 2: [0, 0], 3: [0, 0]}
	var champs := {1: 0, 2: 0, 3: 0}
	var kinds := {}
	var series_n := 0
	var sweeps := 0
	for k in n:
		var season: Dictionary = Season.create(seed0 + k)
		Season.quick_to_end(season)
		for s in season["done"]:
			if str(s.get("league", "")) != "pro":
				continue
			series_n += 1
			if int(s["score"][0]) == 0 or int(s["score"][1]) == 0:
				sweeps += 1
			for side in 2:
				var tier: int = int(World.team(season["world"], Series.tid(s, side))["tier"])
				tier_w[tier][0 if str(s["winner"]) == Series.tid(s, side) else 1] += 1
		champs[int(World.team(season["world"], str(season["champion"]))["tier"])] += 1
		for nw in season["news"]:
			kinds[nw["kind"]] = int(kinds.get(nw["kind"], 0)) + 1
	print("seasons %d  pro series %d  2:0 share %d%%" % [n, series_n, int(100.0 * sweeps / maxf(1, series_n))])
	for t in [1, 2, 3]:
		var w: Array = tier_w[t]
		print("  tier %d (%s): series win %d%%   champions %d" % [t, World.TIER_NAMES[t], int(100.0 * w[0] / maxf(1, w[0] + w[1])), champs[t]])
	print("  news per season: %s" % str(kinds))

## careers without intervention: how much of the original history comes back
func _replay(n: int, seed0: int, years: int, intervene: bool) -> void:
	var Story = load("res://game/story/story.gd")
	var DB = load("res://game/story/events_db.gd")
	var Rules = load("res://game/story/rules.gd")
	var hap := {}
	var fail := {}
	var champs := {}
	var human_up := 0
	var notes := {}
	var errors := 0
	for k in n:
		var season: Dictionary = Season.create(seed0 + k)
		if intervene:
			Rules.apply(season, [["coach", "qin", "spark"], ["move", "rex", "spark"]])
		for y in years:
			Season.quick_to_end(season)
			var lc: String = str(season["leagues"]["pro"]["champion"])
			champs["S%d %s" % [y + 1, lc]] = int(champs.get("S%d %s" % [y + 1, lc], 0)) + 1
			if y == 0 and (season["moves"]["up"] as Array).has(str(season["human"])):
				human_up += 1
			for t in season["world"]["teams"]:
				if (t["players"] as Array).size() != 4:
					errors += 1
			if y < years - 1:
				season = Season.next_season(season)
		Story.on_offseason(season, Season.rng_of(season))
		var st: Dictionary = Story.state(season)
		for e in DB.TIMELINE:
			var id: String = str(e["id"])
			if int(e["s"]) > years:
				continue
			if st["happened"].has(id):
				hap[id] = int(hap.get(id, 0)) + 1
			else:
				fail[id] = int(fail.get(id, 0)) + 1
		for nt in Story.notes(season):
			var key: String = "%s:%s" % [nt["id"], nt["status"]]
			notes[key] = int(notes.get(key, 0)) + 1
	print("careers %d x %d seasons  intervene=%s  roster errors %d  human club promoted after S1: %d%%" % [n, years, intervene, errors, int(100.0 * human_up / n)])
	print("timeline entry                 happened")
	var tot := 0.0
	var cnt := 0
	for e in DB.TIMELINE:
		var id: String = str(e["id"])
		if int(e["s"]) > years:
			continue
		var h: int = int(hap.get(id, 0))
		var pct: float = 100.0 * h / n
		print("  S%d %-22s %3d%%  %s" % [int(e["s"]), id, int(pct), "(check)" if bool(e.get("check", false)) else ""])
		if not bool(e.get("check", false)):
			tot += pct
			cnt += 1
	print("mean of the character / world entries: %d%%" % int(tot / maxf(1, cnt)))
	var ck: Array = champs.keys()
	ck.sort()
	print("pro champions: %s" % str(ck.map(func(x): return "%s=%d" % [x, champs[x]])))
	var nk: Array = notes.keys()
	nk.sort()
	print("notes at the end: %s" % str(nk.map(func(x): return "%s=%d" % [x, notes[x]])))

## quick resolver vs full simulation on the same drafted lineups
func _calib(m: int, seed0: int) -> void:
	var season: Dictionary = Season.create(seed0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed0
	var full_w := 0
	var quick_p := 0.0
	var n := 0
	var rows := []
	for k in m:
		var teams: Array = season["leagues"]["pro"]["teams"]
		var a: String = str(teams[rng.randi() % teams.size()])
		var b := a
		while b == a:
			b = str(teams[rng.randi() % teams.size()])
		var s: Dictionary = Series.create("c%d" % k, a, b)
		Series.ai_veto(s, season, rng)
		Series.start_draft(s, season["world"])
		Series.ai_draft(s, season["world"], rng)
		var args: Dictionary = Bridge.match_args(s, season["world"], "", false)
		gm._start_rounds(args["a"], args["b"], 1, rng.randi() % 100000, args["setup"])
		var steps := 0
		while gm.state == C.S.PLAY and steps < int(1500.0 / MatchT.DT):
			gm.step(MatchT.DT)
			steps += 1
		var lu: Array = Series.lineups(s, season["world"])
		var wins := 0
		for j in 200:
			wins += 1 if int(QuickSim.play_map(lu[0], lu[1], str(args["map"]), rng)["winner"]) == 0 else 0
		var pq := wins / 200.0
		var fw: int = 1 if int(gm.winner) == 0 else 0
		full_w += fw
		quick_p += pq
		n += 1
		rows.append([QuickSim.strength(lu[0]) - QuickSim.strength(lu[1]), pq, fw])
		print("  map %d  dS=%+.2f  quick P(A)=%.2f  full winner=%s" % [k, rows[-1][0], pq, "A" if fw == 1 else "B"])
	# Brier score of the quick model on the full results, and the same for a coin flip
	var brier := 0.0
	for r in rows:
		brier += pow(float(r[1]) - float(r[2]), 2)
	print("maps %d  full A wins %d  quick mean P(A) %.2f  brier %.3f (coin 0.250)" % [n, full_w, quick_p / maxf(1, n), brier / maxf(1, n)])


## the human team's plan for this stage under a strategy
func _plan_for(season: Dictionary, strategy: String, rng: RandomNumberGenerator) -> void:
	var team: Dictionary = World.team(season["world"], str(season["human"]))
	for pid in team["players"]:
		var p: Dictionary = season["world"]["players"][pid]
		var plan := "none"
		match strategy:
			"auto":
				plan = ""   # Training.commit_human falls back to auto_plan
			"smart":
				if float(p["fatigue"]) >= 66.0:
					plan = "rest"
				else:
					# main heroes first (the two best of the role that are not mastered), then the weakest ability
					var best := ""
					var best_v := -1.0
					for hid in p["prof"]:
						var pr: float = float(p["prof"][hid])
						if str(HeroesDB.HEROES[hid]["role"]) == str(p["role"]) and pr < 88.0 and pr > best_v:
							best_v = pr
							best = str(hid)
					var weakest := str(Profiles.ATTRS[0])
					for k in Profiles.ATTRS:
						if int(p["attrs"][k]) < int(p["attrs"][weakest]):
							weakest = str(k)
					plan = ("hero:" + best) if (best != "" and best_v < 78.0) else ("attr:" + weakest)
		if plan != "":
			Training.set_plan(season, str(pid), plan)

## n seasons, the human team (tier 3) follows a training strategy; prints its average rank / series win % / abilities
func _train_test(n: int, seed0: int, strategy: String) -> void:
	var rank_sum := 0.0
	var wins := 0
	var series := 0
	var top4 := 0
	var champs := 0
	var rating0 := 0.0
	var rating1 := 0.0
	var prof_gain := 0.0
	for k in n:
		var season: Dictionary = Season.create(seed0 + k)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed0 + k
		var team: Dictionary = World.team(season["world"], str(season["human"]))
		var r0 := 0.0
		for pid in team["players"]:
			r0 += World.rating(season["world"]["players"][pid])
		rating0 += r0 / float((team["players"] as Array).size())
		var guard := 0
		while str(season["phase"]) != "done" and guard < 60:
			guard += 1
			_plan_for(season, strategy, rng)
			Season.quick_rest(season, false)
			Season.advance(season)
		var r1 := 0.0
		for pid in team["players"]:
			r1 += World.rating(season["world"]["players"][pid])
		rating1 += r1 / float((team["players"] as Array).size())
		var st: Array = Season.standings(season)
		for i in st.size():
			if str(st[i]["id"]) == str(season["human"]):
				rank_sum += i + 1
				top4 += 1 if i < 4 else 0
				wins += int(st[i]["w"])
				series += int(st[i]["w"]) + int(st[i]["l"])
		champs += 1 if str(season["leagues"]["sec"]["champion"]) == str(season["human"]) else 0
	print("train=%s  seasons %d  avg rank %.2f / 8 (次级联赛)  top4 %d%%  regular-season series win %d%%  sec champion %d%%  ability %.2f -> %.2f" % [
		strategy, n, rank_sum / n, int(100.0 * top4 / n), int(100.0 * wins / maxf(1, series)), int(100.0 * champs / n), rating0 / n, rating1 / n])
