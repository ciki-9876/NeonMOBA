extends RefCounted
## Connects a league series map to a real match (game/match.gd): builds the _start_rounds() arguments from the
## drafted lineups and turns the finished match back into a map result (same shape as quick_sim.gd).
## In the match, team 0 is the human's club when it plays in this series; otherwise series side 0. `swap` remembers
## whether series sides were flipped. The human controls the protagonist when he is in the lineup ("player_slot");
## otherwise the match is watched. Both clubs bring their bench (4 选 3) for substitutions in the buy phase.
const Series = preload("res://game/league/series.gd")
const Cast = preload("res://game/league/cast_db.gd")

## {"a": [hid], "b": [hid], "setup": {...for _start_rounds}, "swap": bool, "map": id, "names": [name0, name1]}
static func match_args(s: Dictionary, world: Dictionary, human_tid: String, human_plays: bool) -> Dictionary:
	var lu: Array = Series.lineups(s, world)
	var swap: bool = human_tid != "" and str(s["b"]) == human_tid
	var t0: Dictionary = lu[1] if swap else lu[0]
	var t1: Dictionary = lu[0] if swap else lu[1]
	var World = load("res://game/league/world.gd")
	var slot := -1
	if human_tid != "" and str(t0["team"]) == human_tid:
		for i in 3:
			if str(t0["profiles"][i].get("id", "")) == Cast.PROTAGONIST:
				slot = i
	return {"a": t0["heroes"], "b": t1["heroes"], "swap": swap, "map": Series.next_map(s),
		"names": [str(World.team(world, t0["team"])["name"]), str(World.team(world, t1["team"])["name"])],
		"setup": {"human": human_plays and slot >= 0, "player_slot": maxi(slot, 0), "map": Series.next_map(s),
			"profiles": [t0["profiles"], t1["profiles"]], "bench": [t0.get("bench", []), t1.get("bench", [])],
			"runes": [t0["runes"], t1["runes"]], "captain": Cast.PROTAGONIST if human_tid != "" and str(t0["team"]) == human_tid else "",
			"team_names": [str(World.team(world, t0["team"])["name"]), str(World.team(world, t1["team"])["name"])]}}

## map result from a finished match (gm.state == END). Players substituted during the map keep their own numbers.
static func result_from(gm, s: Dictionary, swap: bool) -> Dictionary:
	var players := {}
	for h in gm.heroes:
		var side: int = (1 - int(h.team)) if swap else int(h.team)
		var pid: String = str(h.profile.get("id", "%d_%d" % [h.team, h.uid]))
		var base: Dictionary = h.get_meta("sub_base", {})
		players[pid] = {"hero": str(h.hid), "side": side, "k": int(h.kills) - int(base.get("k", 0)), "d": int(h.deaths) - int(base.get("d", 0)),
			"a": int(h.assists) - int(base.get("a", 0)), "dmg": float(h.stats.get("dmg_hero", 0.0)) - float(base.get("dmg", 0.0)),
			"heal": float(h.heal_done) - float(base.get("heal", 0.0))}
	for pid in gm.sub_records:
		var r: Dictionary = (gm.sub_records[pid] as Dictionary).duplicate()
		r["side"] = (1 - int(r["team"])) if swap else int(r["team"])
		r.erase("team")
		players[pid] = r
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
