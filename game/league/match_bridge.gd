extends RefCounted
## Connects a league series map to a real match (game/match.gd): builds the _start_rounds() arguments from the
## drafted lineups and turns the finished match back into a map result (same shape as quick_sim.gd).
## In the match, team 0 is the human's team when the human plays in this series (so the player controls it);
## otherwise series side 0. `swap` remembers whether series sides were flipped.
const Series = preload("res://game/league/series.gd")

## {"a": [hid], "b": [hid], "setup": {...for _start_rounds}, "swap": bool, "map": id, "names": [name0, name1]}
static func match_args(s: Dictionary, world: Dictionary, human_tid: String, human_plays: bool) -> Dictionary:
	var lu: Array = Series.lineups(s, world)
	var swap: bool = human_tid != "" and str(s["b"]) == human_tid
	var t0: Dictionary = lu[1] if swap else lu[0]
	var t1: Dictionary = lu[0] if swap else lu[1]
	var World = load("res://game/league/world.gd")
	return {"a": t0["heroes"], "b": t1["heroes"], "swap": swap, "map": Series.next_map(s),
		"names": [str(World.team(world, t0["team"])["name"]), str(World.team(world, t1["team"])["name"])],
		"setup": {"human": human_plays, "map": Series.next_map(s), "profiles": [t0["profiles"], t1["profiles"]],
			"runes": [t0["runes"], t1["runes"]],
			"team_names": [str(World.team(world, t0["team"])["name"]), str(World.team(world, t1["team"])["name"])]}}

## map result from a finished match (gm.state == END)
static func result_from(gm, s: Dictionary, swap: bool) -> Dictionary:
	var players := {}
	for h in gm.heroes:
		var pid: String = str(h.profile.get("id", "%d_%d" % [h.team, h.uid]))
		players[pid] = {"hero": str(h.hid), "k": int(h.kills), "d": int(h.deaths), "a": int(h.assists),
			"dmg": float(h.stats.get("dmg_hero", 0.0)), "heal": float(h.heal_done)}
	var w: int = int(gm.winner)
	var score: Array = gm.rounds.score.duplicate()
	if swap:
		w = 1 - w
		score.reverse()
	var rounds := []
	for r in gm.rounds.history:
		var rw: int = int(r["winner"])
		rounds.append({"winner": (1 - rw) if swap else rw, "reason": str(r["reason"])})
	return {"map": str(gm.map_id), "score": score, "winner": w, "winner_tid": Series.tid(s, w), "players": players,
		"rounds": rounds, "mode": "full"}
