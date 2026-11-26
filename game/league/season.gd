extends RefCounted
## Stage 2D — one league season: schedule (single round robin), standings, playoffs (top 4: semis + final, BO3),
## result records and the statistics that 2E's stories are made from. Pure data, reproducible from the seed.
##
## season = {"seed", "world", "week": current week index, "phase": "regular"|"playoffs"|"done",
##           "weeks": [[series...] per week], "playoffs": [[semi1, semi2], [final]], "done": [finished series],
##           "pstats": {pid: stat line}, "hstats": {hid: {picks, bans, wins, maps}}, "news": [{week, text, kind}],
##           "rng_state": int, "human": tid of the human team ("" = none), "champion": tid}
const World = preload("res://game/league/world.gd")
const Series = preload("res://game/league/series.gd")
const Stories = preload("res://game/league/stories.gd")

static func create(seed: int, n_teams := 8, human := true) -> Dictionary:
	var world: Dictionary = World.generate(seed, n_teams, human)
	var ids := []
	for t in world["teams"]:
		ids.append(str(t["id"]))
	var season := {"seed": seed, "world": world, "week": 0, "phase": "regular", "weeks": _round_robin(ids),
		"playoffs": [], "done": [], "pstats": {}, "hstats": {}, "news": [], "rng_state": 0,
		"human": str(ids[0]) if human else "", "champion": ""}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919 + 13
	season["rng_state"] = rng.state
	Stories.preseason(season)
	return season

## circle method: n-1 weeks, n/2 series per week, every pair meets once
static func _round_robin(ids: Array) -> Array:
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
			week.append(Series.create("w%d_%d" % [w + 1, i], a, b, "regular", w))
		weeks.append(week)
		arr.insert(1, arr.pop_back())   # rotate everyone but the first
	return weeks

static func rng_of(season: Dictionary) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.state = int(season["rng_state"])
	return rng

static func save_rng(season: Dictionary, rng: RandomNumberGenerator) -> void:
	season["rng_state"] = rng.state

## the series of the current week / playoff stage
static func current_series(season: Dictionary) -> Array:
	match str(season["phase"]):
		"regular": return season["weeks"][int(season["week"])]
		"playoffs": return season["playoffs"][(season["playoffs"] as Array).size() - 1]
	return []

static func human_series(season: Dictionary) -> Dictionary:
	for s in current_series(season):
		if str(season["human"]) != "" and (str(s["a"]) == str(season["human"]) or str(s["b"]) == str(season["human"])):
			return s
	return {}

## resolve every unfinished series of the current stage instantly (skip_human: leave the human's series alone)
static func quick_rest(season: Dictionary, skip_human := true) -> void:
	var rng := rng_of(season)
	for s in current_series(season):
		if Series.done(s):
			continue
		if skip_human and not human_series(season).is_empty() and str(s["id"]) == str(human_series(season)["id"]):
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
			var side_of: int = 0 if str(pid).begins_with(str(s["a"]) + "_") else 1
			ps["maps"] = int(ps["maps"]) + 1
			ps["wins"] = int(ps["wins"]) + (1 if int(m["winner"]) == side_of else 0)
			for k in ["k", "d", "a"]:
				ps[k] = int(ps[k]) + int(r[k])
			ps["dmg"] = float(ps["dmg"]) + float(r["dmg"])
			ps["heal"] = float(ps["heal"]) + float(r["heal"])
			ps["mvp"] = int(ps["mvp"]) + (1 if str(m["mvp"]) == str(pid) else 0)
			ps["heroes"][r["hero"]] = int(ps["heroes"].get(r["hero"], 0)) + 1
			season["pstats"][pid] = ps
	Stories.on_series(season, s)

## all series of the stage finished? then move on (next week / playoffs / champion)
static func stage_done(season: Dictionary) -> bool:
	for s in current_series(season):
		if not Series.done(s):
			return false
	return true

static func advance(season: Dictionary) -> void:
	if not stage_done(season):
		return
	Stories.on_stage_end(season)
	match str(season["phase"]):
		"regular":
			season["week"] = int(season["week"]) + 1
			if int(season["week"]) >= (season["weeks"] as Array).size():
				season["phase"] = "playoffs"
				var st := standings(season)
				season["playoffs"] = [[Series.create("semi1", st[0]["id"], st[3]["id"], "semi", int(season["week"])),
					Series.create("semi2", st[1]["id"], st[2]["id"], "semi", int(season["week"]))]]
				Stories.add(season, "常规赛结束，季后赛对阵：%s 对 %s，%s 对 %s。" % [st[0]["name"], st[3]["name"], st[1]["name"], st[2]["name"]], "stage")
		"playoffs":
			var stage: Array = season["playoffs"][(season["playoffs"] as Array).size() - 1]
			if str(stage[0]["kind"]) == "semi":
				season["playoffs"].append([Series.create("final", str(stage[0]["winner"]), str(stage[1]["winner"]), "final", int(season["week"]) + 1)])
			else:
				season["phase"] = "done"
				season["champion"] = str(stage[0]["winner"])
				Stories.on_season_end(season)

## regular-season table: series wins, then map difference, then head-to-head
static func standings(season: Dictionary) -> Array:
	var rows := {}
	for t in season["world"]["teams"]:
		rows[str(t["id"])] = {"id": str(t["id"]), "name": str(t["name"]), "w": 0, "l": 0, "mw": 0, "ml": 0, "streak": 0, "form": []}
	for s in season["done"]:
		if str(s["kind"]) != "regular":
			continue
		for side in 2:
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

## play the rest of the season instantly (headless tests, or "模拟到赛季结束")
static func quick_to_end(season: Dictionary) -> void:
	var guard := 0
	while str(season["phase"]) != "done" and guard < 50:
		guard += 1
		quick_rest(season, false)
		advance(season)
