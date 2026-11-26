extends SceneTree
## Headless league season (stage 2). Plays a whole season and prints standings, playoffs, awards and news.
##   godot --headless --script res://sim/season_cli.gd -- [--seed N] [--full K] [--seasons S] [--out file.json]
##   --full K     the human team's first K series are played as real matches (game/match.gd, AI on both sides)
##                instead of the instant resolver: exercises the draft -> match -> result path end to end
##   --seasons S  run S seasons (seeds N, N+1, ...) and print aggregate checks only
##   --calib M    compare the quick resolver with the full simulation on M maps of random drafted lineups
const Season = preload("res://game/league/season.gd")
const Series = preload("res://game/league/series.gd")
const Bridge = preload("res://game/league/match_bridge.gd")
const QuickSim = preload("res://game/league/quick_sim.gd")
const Stories = preload("res://game/league/stories.gd")
const MatchT = preload("res://game/match.gd")
const C = preload("res://game/consts.gd")

var gm: MatchT

func _initialize() -> void:
	var opt := {"seed": "1", "full": "0", "seasons": "1", "out": "", "calib": "0"}
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var k: String = args[i].trim_prefix("--")
		if i + 1 < args.size():
			opt[k] = args[i + 1]
		i += 2
	gm = MatchT.new()
	root.add_child(gm)
	if int(opt["calib"]) > 0:
		_calib(int(opt["calib"]), int(opt["seed"]))
		quit()
		return
	var n_s := int(opt["seasons"])
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
		f.store_string(JSON.stringify({"news": season["news"], "awards": season.get("awards", {}), "standings": Season.standings(season),
			"leaderboard": Stories.leaderboard(season).slice(0, 10), "hstats": season["hstats"], "champion": season["champion"]}, "  "))
	quit()

## a series with real matches for every map (both teams AI-driven, the human team plays as team 0)
func _play_full(season: Dictionary, s: Dictionary) -> void:
	var rng := Season.rng_of(season)
	var world: Dictionary = season["world"]
	Series.ai_veto(s, season, rng)
	while not Series.done(s):
		Series.start_draft(s)
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
	print("== standings")
	for r in Season.standings(season):
		print("  %-6s %-6s  %d-%d  maps %d-%d" % [r["id"], r["name"], r["w"], r["l"], r["mw"], r["ml"]])
	for st in season["playoffs"]:
		for s in st:
			print("  %s  %s %d:%d %s  -> %s" % [s["kind"], Stories.team_name(season, s["a"]), s["score"][0], s["score"][1], Stories.team_name(season, s["b"]), Stories.team_name(season, s["winner"])])
	print("== champion: %s" % Stories.team_name(season, season["champion"]))
	print("== leaderboard")
	for r in Stories.leaderboard(season).slice(0, 6):
		print("  %-6s %-6s maps %d  %d/%d/%d  kda %.1f  dmg/map %d  mvp %d" % [r["name"], r["team"], r["maps"], r["k"], r["d"], r["a"], r["kda"], int(float(r["dmg"]) / maxf(1, r["maps"])), r["mvp"]])
	print("== news (%d)" % (season["news"] as Array).size())
	for n in season["news"]:
		print("  [w%d %s] %s" % [int(n["week"]) + 1, n["kind"], n["text"]])

## many seasons: do stronger teams win more, how often upsets, are stories varied
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
			series_n += 1
			if int(s["score"][0]) == 0 or int(s["score"][1]) == 0:
				sweeps += 1
			for side in 2:
				var tier: int = int(Stories.World.team(season["world"], Series.tid(s, side))["tier"])
				tier_w[tier][0 if str(s["winner"]) == Series.tid(s, side) else 1] += 1
		champs[int(Stories.World.team(season["world"], str(season["champion"]))["tier"])] += 1
		for nw in season["news"]:
			kinds[nw["kind"]] = int(kinds.get(nw["kind"], 0)) + 1
	print("seasons %d  series %d  2:0 share %d%%" % [n, series_n, int(100.0 * sweeps / maxf(1, series_n))])
	for t in [1, 2, 3]:
		var w: Array = tier_w[t]
		print("  tier %d (%s): series win %d%%   champions %d" % [t, Stories.World.TIER_NAMES[t], int(100.0 * w[0] / maxf(1, w[0] + w[1])), champs[t]])
	print("  news per season: %s" % str(kinds))

## quick resolver vs full simulation on the same drafted lineups
func _calib(m: int, seed0: int) -> void:
	var season: Dictionary = Season.create(seed0, 8, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed0
	var full_w := 0
	var quick_p := 0.0
	var n := 0
	var rows := []
	for k in m:
		var teams: Array = season["world"]["teams"]
		var a: String = str(teams[rng.randi() % teams.size()]["id"])
		var b := a
		while b == a:
			b = str(teams[rng.randi() % teams.size()]["id"])
		var s: Dictionary = Series.create("c%d" % k, a, b)
		Series.ai_veto(s, season, rng)
		Series.start_draft(s)
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
