extends RefCounted
## Stage 2C — a BO3 series (系列赛) between two teams: map veto, then for every map a hero draft and a result.
## Side 0 = team "a", side 1 = team "b" for the whole series (map results use these sides).
## The first pick of each map's draft goes to the team that did not choose the map (the decider: side 0 = higher seed).
##
## series = {"id", "a", "b", "kind": "regular"|"semi"|"final", "week",
##           "veto": Draft veto state, "maps": [map result...], "draft": current map draft, "score": [x, y],
##           "winner": "" | tid, "best_of": 3}
## map result = quick_sim.gd play_map() output + {"picks": [[hid x3], [hid x3]], "bans": [[...], [...]],
##           "first": side, "mvp": pid}
const Draft = preload("res://game/league/draft.gd")
const QuickSim = preload("res://game/league/quick_sim.gd")
const World = preload("res://game/league/world.gd")
const HeroesDB = preload("res://heroes_db.gd")
const Training = preload("res://game/league/training.gd")

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

static func start_draft(s: Dictionary) -> void:
	s["draft"] = Draft.new_draft(first_pick((s["maps"] as Array).size()))

## everything the AI decides for the given sides (both when none is human): veto, draft
static func ai_veto(s: Dictionary, season: Dictionary, rng: RandomNumberGenerator, human_side := -1) -> void:
	var v: Dictionary = s["veto"]
	while Draft.veto_action(v) != "done" and Draft.veto_side(v) != human_side:
		var side: int = Draft.veto_side(v)
		Draft.veto_apply(v, Draft.veto_ai(v, side, map_record(season, tid(s, side)), rng))

static func ai_draft(s: Dictionary, world: Dictionary, rng: RandomNumberGenerator, human_side := -1) -> void:
	var d: Dictionary = s["draft"]
	var roles := [Draft.by_role(world, tid(s, 0)), Draft.by_role(world, tid(s, 1))]
	while not Draft.done(d):
		var side: int = int(Draft.current(d)[1])
		if side == human_side:
			return
		var team: Dictionary = World.team(world, tid(s, side))
		Draft.apply(d, Draft.ai_choice(d, side, roles[side], roles[1 - side], rng, Draft.noise_for(team)))

## match setup of the current map: {"sides": [side dict for QuickSim / match.gd, x2], "map"}
static func lineups(s: Dictionary, world: Dictionary) -> Array:
	var out := []
	for side in 2:
		var t := tid(s, side)
		var lu: Array = Draft.lineup(s["draft"], side, Draft.by_role(world, t), ROLE_ORDER)
		var profs := []
		for pr in lu[1]:
			profs.append(Training.in_form(pr))   # tired players play below their sheet
		out.append({"team": t, "heroes": lu[0], "profiles": profs, "runes": World.team(world, t).get("runes", {})})
	return out

## store a finished map (quick or full) and update the series score
static func record_map(s: Dictionary, res: Dictionary) -> void:
	var d: Dictionary = s["draft"]
	res["picks"] = [_pick_list(d, 0), _pick_list(d, 1)]
	res["bans"] = [(d["bans"][0] as Array).duplicate(), (d["bans"][1] as Array).duplicate()]
	res["first"] = int(d.get("first", 0))
	res["mvp"] = mvp(res)
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
		if str(pid).begins_with(str(res.get("winner_tid", "")) + "_"):
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
		start_draft(s)
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
