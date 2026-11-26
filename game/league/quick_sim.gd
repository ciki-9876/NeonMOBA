extends RefCounted
## Stage 2D — instant result of one map ("跳过直接出结果"), without running game/match.gd.
## A statistical stand-in calibrated against the full simulation (sim/sim_cli.gd):
##   * team strength S = mean over its 3 players of Draft.value(player, hero) + rune bonus + a per-map form swing;
##   * every round is won with p = sigmoid(K_ROUND × (S_a − S_b)); first to 4 rounds (game/rounds.gd) wins the map.
##     K_ROUND = 0.112 gives the calibrated ability curve of the full simulation: +2 ability → ~62% maps, +5 → ~78%.
##   * kills / deaths / assists, damage and healing per round follow the averages of the full simulation
##     (about 2.1 knock-outs per round, carries deal most damage, healers heal).
## Output has the same shape as a map played for real (league/series.gd map result).
const HeroesDB = preload("res://heroes_db.gd")
const Rounds = preload("res://game/rounds.gd")
const Draft = preload("res://game/league/draft.gd")

const K_ROUND := 0.112
const FORM_SD := 0.8          # day-to-day form of a whole team, ability points
const RUNE_PER_STACK := 0.37  # ability points per rune stack on the hero (a full 15-stack page ≈ +5.5)
const DMG_PER_ROUND := {"carry": 2300.0, "tank": 1300.0, "support": 750.0}
## healing per round of the healers (full-simulation averages per map / 5 rounds)
const HEAL_PER_ROUND := {"lumen": 1400.0, "tide": 1300.0, "seer": 260.0, "echo": 220.0}
const KILL_W := {"carry": 0.5, "tank": 0.25, "support": 0.25}
const DEATH_W := {"carry": 0.35, "tank": 0.25, "support": 0.4}

## side = {"team": tid, "heroes": [hid x3], "profiles": [p x3], "runes": {hid: page}}
static func strength(side: Dictionary) -> float:
	var s := 0.0
	for i in 3:
		var hid: String = side["heroes"][i]
		s += Draft.value(side["profiles"][i], hid)
		var page: Dictionary = side.get("runes", {}).get(hid, {})
		var stacks := 0
		for r in page:
			stacks += int(page[r])
		s += float(stacks) * RUNE_PER_STACK
	return s / 3.0

static func play_map(a: Dictionary, b: Dictionary, map_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var sa: float = strength(a) + rng.randfn(0.0, FORM_SD)
	var sb: float = strength(b) + rng.randfn(0.0, FORM_SD)
	var p: float = 1.0 / (1.0 + exp(-K_ROUND * (sa - sb)))
	var score := [0, 0]
	var st := {}
	for si in 2:
		var side: Dictionary = [a, b][si]
		for i in 3:
			st[str(side["profiles"][i]["id"])] = {"hero": str(side["heroes"][i]), "k": 0, "d": 0, "a": 0, "dmg": 0.0, "heal": 0.0, "side": si}
	var rounds := []
	while score[0] < Rounds.ROUNDS_TO_WIN and score[1] < Rounds.ROUNDS_TO_WIN:
		var w: int = 0 if rng.randf() < p else 1
		score[w] += 1
		# 2026-11-26 combat pass (lower TTK + revives): ~55% wipes, ~3 deaths per round
		var wipe: bool = rng.randf() < 0.55
		var lose_deaths: int = 3 if wipe else [0, 1, 1, 2, 2, 2][rng.randi() % 6]
		var win_deaths: int = [0, 0, 0, 1, 1, 2][rng.randi() % 6]
		var sides := [a, b]
		_deaths(sides[w], sides[1 - w], mini(win_deaths, 2), st, rng)
		_deaths(sides[1 - w], sides[w], lose_deaths, st, rng)
		if rng.randf() < 0.3:  # a revived hero who goes down again
			_deaths(sides[1 - w], sides[w], 1, st, rng)
		for side in sides:
			for i in 3:
				var role: String = str(HeroesDB.HEROES[side["heroes"][i]]["role"])
				var q: float = Draft.value(side["profiles"][i], side["heroes"][i]) / 11.0
				var r: Dictionary = st[str(side["profiles"][i]["id"])]
				r["dmg"] = float(r["dmg"]) + DMG_PER_ROUND[role] * q * rng.randf_range(0.7, 1.3)
				r["heal"] = float(r["heal"]) + float(HEAL_PER_ROUND.get(side["heroes"][i], 0.0)) * rng.randf_range(0.7, 1.3)
		rounds.append({"winner": w, "reason": "全歼" if wipe else "占领核心"})
	var win: int = 0 if score[0] > score[1] else 1
	return {"map": map_id, "score": score, "winner": win, "players": st, "rounds": rounds, "mode": "quick"}

## n deaths on `victims`, each credited to a killer (and assisters) of `killers`
static func _deaths(victims: Dictionary, killers: Dictionary, n: int, st: Dictionary, rng: RandomNumberGenerator) -> void:
	var alive := [0, 1, 2]
	for _k in n:
		if alive.is_empty():
			return
		var vi: int = _weighted(alive, victims, DEATH_W, rng, false)
		alive.erase(vi)
		var ki: int = _weighted([0, 1, 2], killers, KILL_W, rng, true)
		st[str(victims["profiles"][vi]["id"])]["d"] += 1
		st[str(killers["profiles"][ki]["id"])]["k"] += 1
		for j in 3:
			if j != ki and rng.randf() < 0.55:
				st[str(killers["profiles"][j]["id"])]["a"] += 1

static func _weighted(idx: Array, side: Dictionary, w: Dictionary, rng: RandomNumberGenerator, skill_up: bool) -> int:
	var tot := 0.0
	var ws := []
	for i in idx:
		var role: String = str(HeroesDB.HEROES[side["heroes"][i]]["role"])
		var q: float = Draft.value(side["profiles"][i], side["heroes"][i]) / 11.0
		var x: float = float(w[role]) * (q if skill_up else 1.0 / maxf(q, 0.3))
		ws.append(x)
		tot += x
	var r := rng.randf() * tot
	for k in idx.size():
		r -= float(ws[k])
		if r <= 0.0:
			return int(idx[k])
	return int(idx[idx.size() - 1])
