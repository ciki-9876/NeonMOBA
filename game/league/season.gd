extends RefCounted
## One season of the two-tier league (M1): 职业联赛 "pro" and 次级联赛 "sec", 8 clubs each, played in lockstep:
## single round robin (7 weeks) -> playoffs (top 4: semis, final; BO3) -> 升降级附加赛 (pro 7th vs sec runner-up) -> done.
## Promotion / relegation: sec champion up, pro 8th down, the play-off winner plays in pro next season.
## next_season() runs the off-season (aging, retirement, contracts, rosters, the story's off-season events) and returns
## the next season, which carries the same world and the career history.
## Pure data, reproducible from the seed. Design: docs/design/游戏框架与开发路线.md (联赛层级).
##
## season = {"seed", "no": season number (1 = S1), "world", "week", "phase": "regular"|"playoffs"|"promo"|"done",
##           "leagues": {"pro"|"sec": {"teams": [tid], "weeks": [[series]], "playoffs": [[series]], "champion", "runner"}},
##           "promo": [series] (附加赛), "done": [finished series], "pstats", "hstats", "news", "rng_state",
##           "human": tid, "champion": pro champion, "moves": {"up": [tid], "down": [tid]}, "history": [past seasons], "train"}
const World = preload("res://game/league/world.gd")
const Series = preload("res://game/league/series.gd")
const Stories = preload("res://game/league/stories.gd")
const Training = preload("res://game/league/training.gd")
const People = preload("res://game/league/people.gd")
const Cast = preload("res://game/league/cast_db.gd")
const Story = preload("res://game/story/story.gd")

const LEAGUES := ["pro", "sec"]

## a new career at S1. opts: {"pick": 4th player of the human team, "random": true = 平行世界 (random world)}
static func create(seed: int, opts := {}) -> Dictionary:
	var world: Dictionary
	if bool(opts.get("random", false)):
		world = World.generate(seed)
	else:
		world = World.build_fixed(seed)
		var pick: String = str(opts.get("pick", ""))
		if pick == "":
			pick = str(Cast.CANDIDATES[absi(seed) % Cast.CANDIDATES.size()])
		World.assign_pick(world, pick)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919 + 13
	for t in world["teams"]:
		World.fix_roster(world, str(t["id"]), rng)
	var season := _make(world, seed, 1, [])
	Story.start_career(season)
	_open_stage(season)
	return season

static func _make(world: Dictionary, seed: int, no: int, history: Array) -> Dictionary:
	var season := {"seed": seed, "no": no, "world": world, "week": 0, "phase": "regular", "leagues": {}, "promo": [], "done": [],
		"pstats": {}, "hstats": {}, "news": [], "rng_state": 0, "human": World.human_team(world), "champion": "",
		"moves": {"up": [], "down": []}, "history": history}
	for lg in LEAGUES:
		var ids: Array = World.league_teams(world, lg)
		season["leagues"][lg] = {"teams": ids, "weeks": _round_robin(ids, lg), "playoffs": [], "champion": "", "runner": ""}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919 + 13 + no * 104729
	season["rng_state"] = rng.state
	Training.ensure(season)
	Stories.preseason(season)
	return season

## circle method: n-1 weeks, n/2 series per week, every pair meets once
static func _round_robin(ids: Array, lg: String) -> Array:
	var n := ids.size()
	var arr := ids.duplicate()
	var weeks := []
	for w in n - 1:
		var week := []
		for i in n / 2:
			var a: String = arr[i]
			var b: String = arr[n - 1 - i]
			if w % 2 == 1:
				var t := a
				a = b
				b = t
			var s: Dictionary = Series.create("%s_w%d_%d" % [lg, w + 1, i], a, b, "regular", w)
			s["league"] = lg
			week.append(s)
		weeks.append(week)
		arr.insert(1, arr.pop_back())
	return weeks

static func rng_of(season: Dictionary) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.state = int(season["rng_state"])
	return rng

static func save_rng(season: Dictionary, rng: RandomNumberGenerator) -> void:
	season["rng_state"] = rng.state

static func n_weeks(season: Dictionary) -> int:
	return (season["leagues"]["pro"]["weeks"] as Array).size()

static func league_of(season: Dictionary, tid: String) -> String:
	for lg in LEAGUES:
		if (season["leagues"][lg]["teams"] as Array).has(tid):
			return lg
	return ""

static func human_league(season: Dictionary) -> String:
	return league_of(season, str(season["human"]))

## the series of the current stage, both leagues (human's league first)
static func current_series(season: Dictionary) -> Array:
	var out := []
	var order := [human_league(season)]
	for lg in LEAGUES:
		if not order.has(lg):
			order.append(lg)
	match str(season["phase"]):
		"regular":
			for lg in order:
				if lg != "":
					out.append_array(season["leagues"][lg]["weeks"][int(season["week"])])
		"playoffs":
			for lg in order:
				if lg != "":
					var po: Array = season["leagues"][lg]["playoffs"]
					if not po.is_empty():
						out.append_array(po[po.size() - 1])
		"promo":
			out.append_array(season["promo"])
	return out

static func human_series(season: Dictionary) -> Dictionary:
	for s in current_series(season):
		if str(season["human"]) != "" and (str(s["a"]) == str(season["human"]) or str(s["b"]) == str(season["human"])):
			return s
	return {}

## resolve every unfinished series of the current stage instantly (skip_human: leave the human's series alone)
static func quick_rest(season: Dictionary, skip_human := true) -> void:
	if not skip_human:
		Training.commit_human(season)
		Story.auto_resolve(season)
	var rng := rng_of(season)
	var hs := human_series(season)
	for s in current_series(season):
		if Series.done(s):
			continue
		if skip_human and not hs.is_empty() and str(s["id"]) == str(hs["id"]):
			continue
		Series.quick_play(s, season, rng)
		finish_series(season, s)
	save_rng(season, rng)

## bookkeeping of a finished series (call exactly once per series)
static func finish_series(season: Dictionary, s: Dictionary) -> void:
	season["done"].append(s)
	for m in s["maps"]:
		for side in 2:
			var won: bool = int(m["winner"]) == side
			for i in 3:
				var hid: String = str(m["picks"][side][i])
				var hs: Dictionary = season["hstats"].get(hid, {"picks": 0, "bans": 0, "wins": 0})
				hs["picks"] = int(hs["picks"]) + 1
				hs["wins"] = int(hs["wins"]) + (1 if won else 0)
				season["hstats"][hid] = hs
			for hid in m["bans"][side]:
				var hb: Dictionary = season["hstats"].get(hid, {"picks": 0, "bans": 0, "wins": 0})
				hb["bans"] = int(hb["bans"]) + 1
				season["hstats"][hid] = hb
		for pid in m["players"]:
			var r: Dictionary = m["players"][pid]
			var ps: Dictionary = season["pstats"].get(pid, {"maps": 0, "wins": 0, "k": 0, "d": 0, "a": 0, "dmg": 0.0, "heal": 0.0, "mvp": 0, "heroes": {}})
			ps["maps"] = int(ps["maps"]) + 1
			ps["wins"] = int(ps["wins"]) + (1 if int(m["winner"]) == int(r.get("side", 0)) else 0)
			for k in ["k", "d", "a"]:
				ps[k] = int(ps[k]) + int(r[k])
			ps["dmg"] = float(ps["dmg"]) + float(r["dmg"])
			ps["heal"] = float(ps["heal"]) + float(r["heal"])
			ps["mvp"] = int(ps["mvp"]) + (1 if str(m["mvp"]) == str(pid) else 0)
			ps["heroes"][r["hero"]] = int(ps["heroes"].get(r["hero"], 0)) + 1
			season["pstats"][pid] = ps
	People.after_series(season["world"], s)
	Stories.on_series(season, s)
	Story.on_series(season, s)

static func stage_done(season: Dictionary) -> bool:
	for s in current_series(season):
		if not Series.done(s):
			return false
	return true

## per-club rank in its league: {tid: [rank, teams]}
static func ranks(season: Dictionary) -> Dictionary:
	var out := {}
	for lg in LEAGUES:
		var st: Array = standings(season, lg)
		for i in st.size():
			out[str(st[i]["id"])] = [i + 1, st.size()]
	return out

## next stage (call when stage_done)
static func advance(season: Dictionary) -> void:
	if not stage_done(season):
		return
	Training.commit_human(season)
	var playing := {}
	for s in current_series(season):
		playing[str(s["a"])] = true
		playing[str(s["b"])] = true
	People.weekly(season["world"], ranks(season), playing)
	Stories.on_stage_end(season)
	match str(season["phase"]):
		"regular":
			season["week"] = int(season["week"]) + 1
			if int(season["week"]) >= n_weeks(season):
				season["phase"] = "playoffs"
				for lg in LEAGUES:
					var st := standings(season, lg)
					var semi := []
					for pair in [[0, 3, "semi1"], [1, 2, "semi2"]]:
						var s: Dictionary = Series.create("%s_%s" % [lg, pair[2]], str(st[pair[0]]["id"]), str(st[pair[1]]["id"]), "semi", int(season["week"]))
						s["league"] = lg
						semi.append(s)
					season["leagues"][lg]["playoffs"] = [semi]
				Stories.playoffs_start(season)
		"playoffs":
			var po: Array = season["leagues"]["pro"]["playoffs"]
			if str(po[po.size() - 1][0]["kind"]) == "semi":
				for lg in LEAGUES:
					var stg: Array = season["leagues"][lg]["playoffs"][0]
					var f: Dictionary = Series.create("%s_final" % lg, str(stg[0]["winner"]), str(stg[1]["winner"]), "final", int(season["week"]) + 1)
					f["league"] = lg
					season["leagues"][lg]["playoffs"].append([f])
			else:
				for lg in LEAGUES:
					var f2: Dictionary = season["leagues"][lg]["playoffs"][1][0]
					season["leagues"][lg]["champion"] = str(f2["winner"])
					season["leagues"][lg]["runner"] = str(f2["b"]) if str(f2["winner"]) == str(f2["a"]) else str(f2["a"])
				season["champion"] = str(season["leagues"]["pro"]["champion"])
				var pro_st := standings(season, "pro")
				var p7: String = str(pro_st[6]["id"])
				var s2: Dictionary = Series.create("promo", p7, str(season["leagues"]["sec"]["runner"]), "promo", int(season["week"]) + 2)
				s2["league"] = "promo"
				season["promo"] = [s2]
				season["phase"] = "promo"
				season["moves"] = {"up": [str(season["leagues"]["sec"]["champion"])], "down": [str(pro_st[7]["id"])]}
		"promo":
			var pm: Dictionary = season["promo"][0]
			if str(pm["winner"]) != str(pm["a"]):
				season["moves"]["up"].append(str(pm["winner"]))
				season["moves"]["down"].append(str(pm["a"]))
			season["phase"] = "done"
			Stories.on_season_end(season)
	_open_stage(season)

## start of a stage: AI clubs train, the story looks at its calendar
static func _open_stage(season: Dictionary) -> void:
	Training.start_stage(season)
	Story.on_stage_start(season)

## table of one league: series wins, then map difference, then id
static func standings(season: Dictionary, league := "") -> Array:
	if league == "":
		league = human_league(season) if human_league(season) != "" else "pro"
	var rows := {}
	for tid in season["leagues"][league]["teams"]:
		var t := World.team(season["world"], str(tid))
		rows[str(tid)] = {"id": str(tid), "name": str(t.get("name", tid)), "w": 0, "l": 0, "mw": 0, "ml": 0, "streak": 0, "form": []}
	for s in season["done"]:
		if str(s["kind"]) != "regular" or str(s.get("league", "")) != league:
			continue
		for side in 2:
			if not rows.has(Series.tid(s, side)):
				continue
			var r: Dictionary = rows[Series.tid(s, side)]
			var won: bool = str(s["winner"]) == Series.tid(s, side)
			r["w"] = int(r["w"]) + (1 if won else 0)
			r["l"] = int(r["l"]) + (0 if won else 1)
			r["mw"] = int(r["mw"]) + int(s["score"][side])
			r["ml"] = int(r["ml"]) + int(s["score"][1 - side])
			r["form"].append(won)
			var sk: int = int(r["streak"])
			r["streak"] = (maxi(sk, 0) + 1) if won else (mini(sk, 0) - 1)
	var out: Array = rows.values()
	out.sort_custom(func(x, y):
		if int(x["w"]) != int(y["w"]): return int(x["w"]) > int(y["w"])
		var dx: int = int(x["mw"]) - int(x["ml"])
		var dy: int = int(y["mw"]) - int(y["ml"])
		if dx != dy: return dx > dy
		return str(x["id"]) < str(y["id"]))
	return out

## play the rest of the season instantly
static func quick_to_end(season: Dictionary) -> void:
	var guard := 0
	while str(season["phase"]) != "done" and guard < 60:
		guard += 1
		quick_rest(season, false)
		advance(season)

# ============================================================ off-season
## the next season: promotion / relegation, the story's off-season, aging and retirement, rosters, history
static func next_season(season: Dictionary) -> Dictionary:
	var world: Dictionary = season["world"]
	var rng := rng_of(season)
	var hist: Array = (season.get("history", []) as Array).duplicate()
	hist.append(summary(season))
	for tid in season["moves"]["up"]:
		World.team(world, str(tid))["league"] = "pro"
	for tid in season["moves"]["down"].duplicate():
		World.team(world, str(tid))["league"] = "sec"
	Story.on_offseason(season, rng)
	# clubs thrown out by the story (scandal): the best sec club not yet promoted takes the place
	for tid in season.get("forced_down", []):
		if str(World.team(world, str(tid))["league"]) != "pro":
			continue
		World.team(world, str(tid))["league"] = "sec"
		season["moves"]["down"].append(str(tid))
		for r in standings(season, "sec"):
			if str(World.team(world, str(r["id"]))["league"]) == "sec" and str(r["id"]) != str(tid):
				World.team(world, str(r["id"]))["league"] = "pro"
				season["moves"]["up"].append(str(r["id"]))
				break
	var news: Array = People.offseason(world, rng, int(season["no"]))
	for t in world["teams"]:
		World.fix_roster(world, str(t["id"]), rng)
		var lg: String = str(t["league"])
		t["tier"] = clampi(int(t["tier"]), 1, 3) if lg == "pro" else 3
	var nxt := _make(world, int(season["seed"]), int(season["no"]) + 1, hist)
	nxt["train"] = season.get("train", {})
	nxt["train"]["ai_key"] = -1
	nxt["train"]["human_key"] = -1
	nxt["train"]["plans"] = {}
	for line in news:
		Stories.add(nxt, str(line), "stage")
	for tid in season["moves"]["up"]:
		Stories.add(nxt, "%s 升入职业联赛。" % Stories.team_name(nxt, str(tid)), "stage")
	for tid in season["moves"]["down"]:
		Stories.add(nxt, "%s 降入次级联赛。" % Stories.team_name(nxt, str(tid)), "stage")
	Story.on_new_season(nxt)
	_open_stage(nxt)
	return nxt

## what the history keeps of a finished season
static func summary(season: Dictionary) -> Dictionary:
	var out := {"no": int(season["no"]), "champions": {}, "runners": {}, "tables": {}, "moves": season.get("moves", {}).duplicate(true), "awards": season.get("awards", {}).duplicate()}
	for lg in LEAGUES:
		out["champions"][lg] = str(season["leagues"][lg]["champion"])
		out["runners"][lg] = str(season["leagues"][lg]["runner"])
		var rows := []
		for r in standings(season, lg):
			rows.append(str(r["id"]))
		out["tables"][lg] = rows
	return out
