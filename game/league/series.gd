extends RefCounted
## Stage 2C — a BO3 series (系列赛) between two teams: map veto, then for every map a hero draft and a result.
## Side 0 = team "a", side 1 = team "b" for the whole series (map results use these sides).
## The first pick of each map's draft goes to the team that did not choose the map (the decider: side 0 = higher seed).
##
## series = {"id", "a", "b", "kind": "regular"|"semi"|"final", "week",
##           "veto": Draft veto state, "maps": [map result...], "draft": current map draft, "score": [x, y],
##           "winner": "" | tid, "best_of": 3, "league": "pro"|"sec"|"promo",
##           "lineup": [{role: pid}, {role: pid}] starters of the current map (4 选 3; set before the draft)}
## map result = quick_sim.gd play_map() output + {"picks": [[hid x3], [hid x3]], "bans": [[...], [...]],
##           "first": side, "mvp": pid}
const Draft = preload("res://game/league/draft.gd")
const QuickSim = preload("res://game/league/quick_sim.gd")
const World = preload("res://game/league/world.gd")
const HeroesDB = preload("res://heroes_db.gd")
const People = preload("res://game/league/people.gd")

const ROLE_ORDER := ["carry", "tank", "support"]

static func create(id: String, a: String, b: String, kind := "regular", week := 0) -> Dictionary:
	return {"id": id, "a": a, "b": b, "kind": kind, "week": week, "veto": Draft.new_veto(), "maps": [],
		"draft": {}, "score": [0, 0], "winner": "", "best_of": 3}

static func tid(s: Dictionary, side: int) -> String:
	return str(s["a"] if side == 0 else s["b"])

static func done(s: Dictionary) -> bool:
	return str(s["winner"]) != ""

## map of the next game, after the veto
static func next_map(s: Dictionary) -> String:
	var i: int = (s["maps"] as Array).size()
	return str(s["veto"]["maps"][i]) if i < (s["veto"]["maps"] as Array).size() else ""

## side that drafts first on map i: map 1 was picked by side 0, map 2 by side 1, the decider: side 0
static func first_pick(i: int) -> int:
	return [1, 0, 0][clampi(i, 0, 2)]

## next map: the draft state and both lineups (human_side keeps human_lineup if given, otherwise the AI suggestion)
static func start_draft(s: Dictionary, world := {}, human_side := -1, human_lineup := {}) -> void:
	s["draft"] = Draft.new_draft(first_pick((s["maps"] as Array).size()))
	if not world.is_empty():
		set_lineups(s, world, human_side, human_lineup)

static func set_lineups(s: Dictionary, world: Dictionary, human_side := -1, human_lineup := {}) -> void:
	var lu := [{}, {}]
	for side in 2:
		if side == human_side and valid_lineup(world, tid(s, side), human_lineup):
			lu[side] = human_lineup.duplicate()
		else:
			lu[side] = People.best_lineup(world, tid(s, side))
	s["lineup"] = lu

## three different players of the club, one per role
static func valid_lineup(world: Dictionary, t: String, l: Dictionary) -> bool:
	var seen := {}
	var team_ids: Array = World.team(world, t).get("players", [])
	for r in ROLE_ORDER:
		var pid: String = str(l.get(r, ""))
		if pid == "" or seen.has(pid) or not team_ids.has(pid):
			return false
		seen[pid] = true
	return true

## {role: match profile} of a side's starters (fatigue, form, teamwork modifiers applied)
static func roles_of(s: Dictionary, world: Dictionary, side: int) -> Dictionary:
	if not s.has("lineup") or (s["lineup"][side] as Dictionary).is_empty():
		set_lineups(s, world)
	var l: Dictionary = s["lineup"][side]
	var mates := [str(l["tank"]), str(l["carry"]), str(l["support"])]
	var out := {}
	for r in ROLE_ORDER:
		out[r] = People.match_profile(world, world["players"][str(l[r])], mates)
	return out

## players of a side not in the lineup (match profiles), for substitutions
static func bench_of(s: Dictionary, world: Dictionary, side: int) -> Array:
	var l: Dictionary = s["lineup"][side]
	var on: Array = l.values()
	var out := []
	for pid in World.team(world, tid(s, side))["players"]:
		if not on.has(pid):
			out.append(People.match_profile(world, world["players"][pid], on))
	return out

## everything the AI decides for the given sides (both when none is human): veto, draft
static func ai_veto(s: Dictionary, season: Dictionary, rng: RandomNumberGenerator, human_side := -1) -> void:
	var v: Dictionary = s["veto"]
	while Draft.veto_action(v) != "done" and Draft.veto_side(v) != human_side:
		var side: int = Draft.veto_side(v)
		Draft.veto_apply(v, Draft.veto_ai(v, side, map_record(season, tid(s, side)), rng))

static func ai_draft(s: Dictionary, world: Dictionary, rng: RandomNumberGenerator, human_side := -1) -> void:
	var d: Dictionary = s["draft"]
	var roles := [roles_of(s, world, 0), roles_of(s, world, 1)]
	while not Draft.done(d):
		var side: int = int(Draft.current(d)[1])
		if side == human_side:
			return
		var team: Dictionary = World.team(world, tid(s, side))
		Draft.apply(d, Draft.ai_choice(d, side, roles[side], roles[1 - side], rng, Draft.noise_for(team, world)))

## match setup of the current map: {"sides": [side dict for QuickSim / match.gd, x2], "map"}
static func lineups(s: Dictionary, world: Dictionary) -> Array:
	var out := []
	for side in 2:
		var t := tid(s, side)
		var lu: Array = Draft.lineup(s["draft"], side, roles_of(s, world, side), ROLE_ORDER)
		out.append({"team": t, "heroes": lu[0], "profiles": lu[1], "runes": World.team(world, t).get("runes", {}),
			"bench": bench_of(s, world, side)})
	return out

## store a finished map (quick or full) and update the series score
static func record_map(s: Dictionary, res: Dictionary) -> void:
	var d: Dictionary = s["draft"]
	res["picks"] = [_pick_list(d, 0), _pick_list(d, 1)]
	res["bans"] = [(d["bans"][0] as Array).duplicate(), (d["bans"][1] as Array).duplicate()]
	res["first"] = int(d.get("first", 0))
	res["mvp"] = mvp(res)
	if s.has("lineup"):
		res["lineup"] = (s["lineup"] as Array).duplicate(true)
	s["maps"].append(res)
	s["score"][int(res["winner"])] += 1
	var need: int = int(s["best_of"]) / 2 + 1
	for side in 2:
		if int(s["score"][side]) >= need:
			s["winner"] = tid(s, side)
	s["draft"] = {}

static func _pick_list(d: Dictionary, side: int) -> Array:
	var out := []
	for role in ROLE_ORDER:
		out.append(str(d["picks"][side].get(role, "")))
	return out

## best player of the winning side: kills, assists, deaths, damage and healing
static func mvp(res: Dictionary) -> String:
	var best := ""
	var best_v := -1e9
	for pid in res["players"]:
		var r: Dictionary = res["players"][pid]
		var v: float = float(r["k"]) * 3.0 + float(r["a"]) * 1.5 - float(r["d"]) + float(r["dmg"]) / 1500.0 + float(r["heal"]) / 1500.0
		if int(r.get("side", -1)) == int(res["winner"]):
			v += 6.0
		if v > best_v:
			best_v = v
			best = str(pid)
	return best

## play the whole series instantly (both teams AI)
static func quick_play(s: Dictionary, season: Dictionary, rng: RandomNumberGenerator) -> void:
	var world: Dictionary = season["world"]
	ai_veto(s, season, rng)
	while not done(s):
		start_draft(s, world)
		ai_draft(s, world, rng)
		var lu := lineups(s, world)
		var res: Dictionary = QuickSim.play_map(lu[0], lu[1], next_map(s), rng)
		res["winner_tid"] = tid(s, int(res["winner"]))
		record_map(s, res)

## a team's map record so far this season: {map_id: [wins, losses]}
static func map_record(season: Dictionary, t: String) -> Dictionary:
	var out := {}
	for s in season.get("done", []):
		for side in 2:
			if tid(s, side) != t:
				continue
			for m in s["maps"]:
				var r: Array = out.get(m["map"], [0, 0])
				r[0 if int(m["winner"]) == side else 1] += 1
				out[m["map"]] = r
	return out
