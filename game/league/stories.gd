extends RefCounted
## Stage 2E — turns season data into stories: news items (冷门、横扫、逆转、连胜、高光表现、季后赛),
## season awards and the player / hero leaderboards shown by the league screens.
## news item = {"week": int, "text": String, "kind": "upset"|"sweep"|"comeback"|"streak"|"star"|"stage"|"award"|"intro"}
const World = preload("res://game/league/world.gd")
const HeroesDB = preload("res://heroes_db.gd")

static func add(season: Dictionary, text: String, kind: String) -> void:
	season["news"].append({"week": int(season["week"]), "text": text, "kind": kind})

static func team_name(season: Dictionary, tid: String) -> String:
	return str(World.team(season["world"], tid).get("name", tid))

static func player_name(season: Dictionary, pid: String) -> String:
	return str(season["world"]["players"].get(pid, {}).get("name", pid))

static func team_rating(season: Dictionary, tid: String) -> float:
	var s := 0.0
	var ps := World.team_players(season["world"], tid)
	for p in ps:
		s += World.rating(p)
	return s / maxf(1.0, ps.size())

static func preseason(season: Dictionary) -> void:
	var teams: Array = season["world"]["teams"].duplicate()
	teams.sort_custom(func(x, y): return team_rating(season, str(x["id"])) > team_rating(season, str(y["id"])))
	add(season, "新赛季开幕：%d 支战队单循环，前四名进入季后赛。夺冠热门：%s、%s。" % [teams.size(), teams[0]["name"], teams[1]["name"]], "intro")
	if str(season["human"]) != "":
		var me: Dictionary = World.team(season["world"], str(season["human"]))
		var rank := 1
		for t in teams:
			if str(t["id"]) == str(season["human"]):
				break
			rank += 1
		add(season, "%s 以实力第 %d 的身份参赛（共 %d 队），外界普遍不看好。" % [me["name"], rank, teams.size()], "intro")

static func on_series(season: Dictionary, s: Dictionary) -> void:
	var w: String = str(s["winner"])
	var l: String = str(s["b"]) if w == str(s["a"]) else str(s["a"])
	var ws: Array = s["score"].duplicate()
	ws.sort()
	ws.reverse()
	var gap: float = team_rating(season, l) - team_rating(season, w)
	var stage: String = str({"regular": "", "semi": "半决赛", "final": "总决赛"}[str(s["kind"])])
	var tag := ("%s：" % stage) if stage != "" else ""
	if gap >= 1.8:
		add(season, "%s爆冷！%s %d:%d 击败实力更强的 %s。" % [tag, team_name(season, w), ws[0], ws[1], team_name(season, l)], "upset")
	elif ws[1] == 0 and gap <= -1.5:
		add(season, "%s%s 2:0 横扫 %s，毫无悬念。" % [tag, team_name(season, w), team_name(season, l)], "sweep")
	elif ws[1] == 1 and int(s["maps"][0]["winner"]) != (0 if w == str(s["a"]) else 1):
		add(season, "%s逆转！%s 先丢一图后连扳两局，2:1 拿下 %s。" % [tag, team_name(season, w), team_name(season, l)], "comeback")
	elif stage != "":
		add(season, "%s%s %d:%d 战胜 %s。" % [tag, team_name(season, w), ws[0], ws[1], team_name(season, l)], "stage")
	# standout single-map performances
	for m in s["maps"]:
		for pid in m["players"]:
			var r: Dictionary = m["players"][pid]
			if int(r["k"]) >= 8 and int(r["d"]) <= 2:
				add(season, "%s（%s）在%s用%s打出 %d/%d/%d 的统治级表现。" % [player_name(season, pid), team_name(season, str(season["world"]["players"][pid]["team"])),
					_map_name(str(m["map"])), HeroesDB.HEROES[r["hero"]]["name"], r["k"], r["d"], r["a"]], "star")

static func _map_name(mid: String) -> String:
	var Maps = load("res://game/maps.gd")
	return "「%s」" % str(Maps.MAPS[mid]["name"]) if Maps.MAPS.has(mid) else mid

static func on_stage_end(season: Dictionary) -> void:
	if str(season["phase"]) != "regular":
		return
	var Season = load("res://game/league/season.gd")
	var st: Array = Season.standings(season)
	var wk: int = int(season["week"]) + 1
	add(season, "第 %d 周结束：%s 以 %d 胜 %d 负领跑积分榜。" % [wk, st[0]["name"], st[0]["w"], st[0]["l"]], "stage")
	for r in st:
		if int(r["streak"]) in [3, 5, 7]:
			add(season, "%s 已经取得 %d 连胜。" % [r["name"], r["streak"]], "streak")
		elif int(r["streak"]) in [-3, -5, -7]:
			add(season, "%s 陷入 %d 连败，压力山大。" % [r["name"], -int(r["streak"])], "streak")

static func on_season_end(season: Dictionary) -> void:
	var champ: String = str(season["champion"])
	add(season, "%s 夺得本赛季冠军！" % team_name(season, champ), "award")
	var aw := awards(season)
	season["awards"] = aw
	if aw.has("mvp"):
		add(season, "赛季 MVP：%s（%s），%d 次单图 MVP，KDA %.1f。" % [player_name(season, aw["mvp"]), team_name(season, str(season["world"]["players"][aw["mvp"]]["team"])),
			int(season["pstats"][aw["mvp"]]["mvp"]), kda(season["pstats"][aw["mvp"]])], "award")
	if aw.has("rookie"):
		add(season, "最佳新秀：%s（%d 岁）。" % [player_name(season, aw["rookie"]), int(season["world"]["players"][aw["rookie"]]["age"])], "award")
	if aw.has("hero"):
		add(season, "版本之子：%s，出场 %d 次，胜率 %d%%。" % [HeroesDB.HEROES[aw["hero"]]["name"], int(season["hstats"][aw["hero"]]["picks"]),
			int(100.0 * float(season["hstats"][aw["hero"]]["wins"]) / maxf(1.0, float(season["hstats"][aw["hero"]]["picks"])))], "award")

static func kda(ps: Dictionary) -> float:
	return (float(ps["k"]) + float(ps["a"])) / maxf(1.0, float(ps["d"]))

## player rating for leaderboards / MVP: impact per map
static func impact(ps: Dictionary) -> float:
	var n := maxf(1.0, float(ps["maps"]))
	return (float(ps["k"]) * 3.0 + float(ps["a"]) * 1.5 - float(ps["d"]) * 1.5 + float(ps["dmg"]) / 1500.0 + float(ps["heal"]) / 1500.0) / n + float(ps["mvp"]) * 0.8 / n * 4.0

## impact relative to the average player of the same role (supports and tanks are not compared with carries)
static func rel_impact(season: Dictionary, pid: String) -> float:
	var role: String = str(season["world"]["players"][pid]["role"])
	var tot := 0.0
	var n := 0
	for q in season["pstats"]:
		if str(season["world"]["players"][q]["role"]) == role and int(season["pstats"][q]["maps"]) > 0:
			tot += impact(season["pstats"][q])
			n += 1
	var avg: float = tot / maxf(1.0, n)
	return (impact(season["pstats"][pid]) - avg) / maxf(1.0, absf(avg))

static func awards(season: Dictionary) -> Dictionary:
	var out := {}
	var best := -1e9
	var best_r := -1e9
	for pid in season["pstats"]:
		var ps: Dictionary = season["pstats"][pid]
		if int(ps["maps"]) < 4:
			continue
		var v := rel_impact(season, str(pid)) + (float(ps["wins"]) * 0.5 + float(ps["mvp"]) * 1.5) / maxf(1.0, float(ps["maps"]))
		if v > best:
			best = v
			out["mvp"] = pid
		if int(season["world"]["players"][pid]["age"]) <= 19 and v > best_r:
			best_r = v
			out["rookie"] = pid
	var hb := -1.0
	for hid in season["hstats"]:
		var hs: Dictionary = season["hstats"][hid]
		if int(hs["picks"]) < 6:
			continue
		var v: float = float(hs["wins"]) / float(hs["picks"]) + float(hs["picks"]) * 0.004
		if v > hb:
			hb = v
			out["hero"] = hid
	return out

## leaderboard rows sorted by impact: [{pid, name, team, maps, k, d, a, kda, dmg, heal, mvp, impact}]
static func leaderboard(season: Dictionary) -> Array:
	var rows := []
	for pid in season["pstats"]:
		var ps: Dictionary = season["pstats"][pid]
		rows.append({"pid": pid, "name": player_name(season, pid), "team": team_name(season, str(season["world"]["players"][pid]["team"])),
			"maps": ps["maps"], "k": ps["k"], "d": ps["d"], "a": ps["a"], "kda": kda(ps), "dmg": ps["dmg"], "heal": ps["heal"],
			"mvp": ps["mvp"], "impact": rel_impact(season, str(pid)), "role": str(season["world"]["players"][pid]["role"])})
	rows.sort_custom(func(x, y): return float(x["impact"]) > float(y["impact"]))
	return rows
