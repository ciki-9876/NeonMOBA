extends RefCounted
## The shared vocabulary of the story (M2): conditions and effects used by timeline entries, generic events and
## choice events (docs/design/角色设计规范.md 第四节第 3 条). Authors only use these words; a missing word is added here.
##
## A condition is an Array: [name, args...]; a list of conditions is true when all are true.
## Arguments starting with "$" are taken from the context (e.g. "$p" = the subject player of a generic event).
## Comparisons: ">=", "<=", ">", "<", "==", "!=".
const World = preload("res://game/league/world.gd")
const Profiles = preload("res://game/profiles.gd")
const People = preload("res://game/league/people.gd")

const CONDITIONS := ["season", "week", "phase", "team_of", "same_team", "free_agent", "human_team", "league_of", "team_rank",
	"made_playoffs", "champion", "streak", "attr_avg", "fame", "fatigue", "form", "satisfaction", "bench_streak", "age",
	"persona", "contract_pay", "rel", "flag", "happened", "failed", "not", "any", "retired", "staff_free", "coach_of", "comm_low", "role", "suspended"]
const EFFECTS := ["attr", "prof", "potential", "persona", "trait_add", "trait_remove", "fame", "form", "satisfaction", "respect",
	"fatigue", "rel", "contract_pay", "move", "release", "retire", "coach", "flag", "unflag", "news", "chain", "recall", "money",
	"suspend", "suspend_team", "relegate", "fold", "lang"]

static func arg(v, ctx: Dictionary):
	if typeof(v) == TYPE_STRING and str(v).begins_with("$"):
		return ctx.get(str(v), v)
	return v

static func cmp(a: float, op: String, b: float) -> bool:
	match op:
		">=": return a >= b
		"<=": return a <= b
		">": return a > b
		"<": return a < b
		"==": return is_equal_approx(a, b)
		"!=": return not is_equal_approx(a, b)
	return false

static func all(season: Dictionary, conds: Array, ctx := {}) -> bool:
	for c in conds:
		if not test(season, c, ctx):
			return false
	return true

static func _p(season: Dictionary, pid) -> Dictionary:
	return season["world"]["players"].get(str(pid), {})

static func test(season: Dictionary, c: Array, ctx := {}) -> bool:
	var w: Dictionary = season["world"]
	var st: Dictionary = w.get("story", {})
	var a := []
	for x in c:
		a.append(arg(x, ctx))
	match str(a[0]):
		"season": return cmp(float(season.get("no", 1)), str(a[1]), float(a[2]))
		"week": return cmp(float(week_no(season)), str(a[1]), float(a[2]))
		"phase": return str(season["phase"]) == str(a[1])
		"team_of": return str(_p(season, a[1]).get("team", "?")) == str(a[2]) and not bool(_p(season, a[1]).get("retired", false))
		"same_team":
			var ta: String = str(_p(season, a[1]).get("team", ""))
			return ta != "" and ta == str(_p(season, a[2]).get("team", "-"))
		"free_agent": return str(_p(season, a[1]).get("team", "?")) == "" and not bool(_p(season, a[1]).get("retired", false))
		"human_team": return str(_p(season, a[1]).get("team", "?")) == str(season["human"])
		"league_of": return str(World.team(w, str(a[1])).get("league", "")) == str(a[2])
		"team_rank": return cmp(float(rank_of(season, str(a[1]))), str(a[2]), float(a[3]))
		"made_playoffs":
			for lg in season["leagues"]:
				var po: Array = season["leagues"][lg]["playoffs"]
				if not po.is_empty():
					for s in po[0]:
						if str(s["a"]) == str(a[1]) or str(s["b"]) == str(a[1]):
							return true
			return false
		"champion": return str(season["leagues"][str(a[1])]["champion"]) == str(a[2])
		"streak":
			var Season = load("res://game/league/season.gd")
			for r in Season.standings(season, Season.league_of(season, str(a[1]))):
				if str(r["id"]) == str(a[1]):
					return cmp(float(r["streak"]), str(a[2]), float(a[3]))
			return false
		"attr_avg": return cmp(World.rating(_p(season, a[1])), str(a[2]), float(a[3]))
		"fame": return cmp(float(_p(season, a[1]).get("fame", 0)), str(a[2]), float(a[3]))
		"fatigue": return cmp(float(_p(season, a[1]).get("fatigue", 0)), str(a[2]), float(a[3]))
		"form": return cmp(float(_p(season, a[1]).get("form", 0)), str(a[2]), float(a[3]))
		"satisfaction": return cmp(float(_p(season, a[1]).get("sat", 70)), str(a[2]), float(a[3]))
		"bench_streak": return cmp(float(_p(season, a[1]).get("bench_streak", 0)), str(a[2]), float(a[3]))
		"age": return cmp(float(_p(season, a[1]).get("age", 20)), str(a[2]), float(a[3]))
		"persona": return cmp(float(_p(season, a[1]).get("persona", {}).get(str(a[2]), 5)), str(a[3]), float(a[4]))
		"contract_pay":
			var pi: int = World.PAY_TIERS.find(str(_p(season, a[1]).get("contract", {}).get("pay", "low")))
			return cmp(float(pi), str(a[2]), float(World.PAY_TIERS.find(str(a[3]))))
		"rel": return cmp(World.rel(w, str(a[1]), str(a[2])), str(a[3]), float(a[4]))
		"flag": return st.get("flags", {}).has(str(a[1]))
		"happened": return st.get("happened", {}).has(str(a[1]))
		"failed": return st.get("failed", {}).has(str(a[1]))
		"not": return not test(season, c[1], ctx)
		"any":
			for sub in c[1]:
				if test(season, sub, ctx):
					return true
			return false
		"retired": return bool(_p(season, a[1]).get("retired", false))
		"staff_free": return str(w["staff"].get(str(a[1]), {}).get("team", "?")) == ""
		"coach_of": return str(World.team(w, str(a[1])).get("coach", "")) == str(a[2])
		"comm_low":
			var p: Dictionary = _p(season, a[1])
			if str(p.get("team", "")) == "":
				return false
			var tot := 0.0
			var n := 0
			for q in World.team(w, str(p["team"]))["players"]:
				if q != p["id"]:
					tot += People.common_lang(p, w["players"][q])
					n += 1
			return n > 0 and tot / n < float(a[2])
		"role": return str(_p(season, a[1]).get("role", "")) == str(a[2])
		"suspended": return int(_p(season, a[1]).get("suspended", 0)) > 0
	push_warning("story: unknown condition %s" % str(a[0]))
	return false

## 1-based regular-season week; playoffs and later count on after the last week
static func week_no(season: Dictionary) -> int:
	var Season = load("res://game/league/season.gd")
	match str(season["phase"]):
		"regular": return int(season["week"]) + 1
		"playoffs": return Season.n_weeks(season) + (season["leagues"]["pro"]["playoffs"] as Array).size()
		"promo": return Season.n_weeks(season) + 3
	return Season.n_weeks(season) + 4

static func rank_of(season: Dictionary, tid: String) -> int:
	var Season = load("res://game/league/season.gd")
	var lg: String = Season.league_of(season, tid)
	if lg == "":
		return 99
	var st: Array = Season.standings(season, lg)
	for i in st.size():
		if str(st[i]["id"]) == tid:
			return i + 1
	return 99

# ============================================================ effects
## apply a list of effects; returns the news lines they produced
static func apply(season: Dictionary, effects: Array, ctx := {}, rng: RandomNumberGenerator = null) -> Array:
	var out := []
	for e in effects:
		var line := apply_one(season, e, ctx, rng)
		if line != "":
			out.append(line)
	return out

static func apply_one(season: Dictionary, e: Array, ctx: Dictionary, rng: RandomNumberGenerator) -> String:
	var w: Dictionary = season["world"]
	var st: Dictionary = w["story"]
	var a := []
	for x in e:
		a.append(arg(x, ctx))
	var p: Dictionary = _p(season, a[1]) if a.size() > 1 else {}
	match str(a[0]):
		"attr":
			if p.is_empty(): return ""
			var keys: Array = Profiles.ATTRS if str(a[2]) == "all" else [str(a[2])]
			for k in keys:
				p["attrs"][k] = clampi(int(p["attrs"][k]) + int(a[3]), 1, 20)
			if World.rating(p) > float(p.get("pot", 20.0)):
				p["pot"] = World.rating(p)
		"prof":
			if p.is_empty(): return ""
			p["prof"][str(a[2])] = clampf(float(p["prof"].get(str(a[2]), 0.0)) + float(a[3]), 0.0, 100.0)
		"potential":
			if p.is_empty(): return ""
			p["pot"] = clampf(float(p.get("pot", 15.0)) + float(a[2]), World.rating(p), 20.0)
		"persona":
			if p.is_empty(): return ""
			p["persona"][str(a[2])] = clampi(int(p["persona"].get(str(a[2]), 5)) + clampi(int(a[3]), -1, 1), 0, 10)
		"trait_add":
			if not p.is_empty() and not (p["traits"] as Array).has(str(a[2])):
				p["traits"].append(str(a[2]))
		"trait_remove":
			if not p.is_empty():
				p["traits"].erase(str(a[2]))
		"fame":
			if not p.is_empty():
				p["fame"] = clampi(int(p.get("fame", 0)) + int(a[2]), 0, 100)
		"form":
			if not p.is_empty():
				p["form"] = clampf(float(p.get("form", 0.0)) + float(a[2]), -3.0, 3.0)
		"satisfaction":
			if not p.is_empty():
				p["sat"] = clampf(float(p.get("sat", 70.0)) + float(a[2]), 0.0, 100.0)
		"respect":
			if not p.is_empty():
				p["respect"] = clampf(float(p.get("respect", 70.0)) + float(a[2]), 0.0, 100.0)
		"fatigue":
			if not p.is_empty():
				p["fatigue"] = clampf(float(p.get("fatigue", 0.0)) + float(a[2]), 0.0, 100.0)
		"rel": World.add_rel(w, str(a[1]), str(a[2]), float(a[3]))
		"contract_pay":
			if not p.is_empty():
				p["contract"]["pay"] = str(a[2])
		"move":
			if p.is_empty(): return ""
			var old: String = str(p["team"])
			World.move_player(w, str(a[1]), str(a[2]))
			_refill(season, old, rng)
		"release":
			if p.is_empty(): return ""
			var old2: String = str(p["team"])
			World.move_player(w, str(a[1]), "")
			_refill(season, old2, rng)
		"retire":
			if p.is_empty(): return ""
			var old3: String = str(p["team"])
			World.retire(w, str(a[1]))
			_refill(season, old3, rng)
		"coach":
			var sid: String = str(a[1])
			if w["staff"].has(sid):
				var prev: String = str(w["staff"][sid].get("team", ""))
				if prev != "":
					World.team(w, prev)["coach"] = ""
				w["staff"][sid]["team"] = str(a[2])
				if str(a[2]) != "":
					World.team(w, str(a[2]))["coach"] = sid
		"flag": st["flags"][str(a[1])] = true
		"unflag": st["flags"].erase(str(a[1]))
		"news": return fill(season, str(a[1]), ctx)
		"chain":
			var Story = load("res://game/story/story.gd")
			Story.raise(season, str(a[1]), ctx)
		"recall": st["known"][str(a[1])] = true
		"money": season["money"] = int(season.get("money", 0)) + int(a[1])
		"suspend":
			if not p.is_empty():
				p["suspended"] = int(a[2])
		"suspend_team":
			for q in World.team(w, str(a[1])).get("players", []):
				w["players"][q]["suspended"] = int(a[2])
		"relegate": _force_relegate(season, str(a[1]))
		"fold":
			for q in World.team(w, str(a[1])).get("players", []).duplicate():
				World.move_player(w, str(q), "")
			_refill(season, str(a[1]), rng)
		"lang":
			if not p.is_empty():
				p["langs"][str(a[2])] = clampi(int(p["langs"].get(str(a[2]), 0)) + int(a[3]), 0, 3)
		_:
			push_warning("story: unknown effect %s" % str(a[0]))
	return ""

static func _refill(season: Dictionary, tid: String, rng: RandomNumberGenerator) -> void:
	if tid == "":
		return
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.seed = int(season["seed"]) * 31 + int(season.get("no", 1)) * 977 + (season["world"]["players"] as Dictionary).size()
	World.fix_roster(season["world"], tid, rng)

## a club is thrown out of the pro league (scandal): recorded on the season, applied by Season.next_season (the best
## sec club that is not promoted anyway goes up instead, so both leagues keep 8 clubs)
static func _force_relegate(season: Dictionary, tid: String) -> void:
	if not season.has("forced_down"):
		season["forced_down"] = []
	if not (season["forced_down"] as Array).has(tid):
		season["forced_down"].append(tid)

## text with {id} placeholders (character / club ids, or $-context keys) replaced by names
static func fill(season: Dictionary, text: String, ctx := {}) -> String:
	var out := text
	var w: Dictionary = season["world"]
	var guard := 0
	while out.find("{") >= 0 and guard < 20:
		guard += 1
		var i := out.find("{")
		var j := out.find("}", i)
		if j < 0:
			break
		var key := out.substr(i + 1, j - i - 1)
		var id := str(ctx.get(key, key))
		var nm := id
		if w["players"].has(id) or w["staff"].has(id):
			nm = World.display_name(w, id)
		elif not World.team(w, id).is_empty():
			nm = str(World.team(w, id)["name"])
		out = out.substr(0, i) + nm + out.substr(j + 1)
	return out
