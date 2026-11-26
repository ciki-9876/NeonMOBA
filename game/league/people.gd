extends RefCounted
## Character state and its mechanics (M1): the match profile (战力管线), form, satisfaction, weeks together (磨合),
## language and relations in the lineup, aging and retirement. Pure data on the world / season dictionaries.
## Design: docs/design/角色机制设计.md.
const Profiles = preload("res://game/profiles.gd")
const World = preload("res://game/league/world.gd")
const Cast = preload("res://game/league/cast_db.gd")

const FORM_MAX := 3.0
const FORM_DECAY := 0.6          # form keeps 60% per week
const PLAY_FATIGUE := 6.0        # fatigue of playing a series (only players who were on the field)
const GEL_WEEKS := 6.0           # a new player's teamwork malus fades over this many weeks
const GEL_MALUS := 2.0
## team communication: mean common language level of the three starters -> teamwork modifier
const COMM_MOD := [-3.0, -1.5, -0.5, 0.0]
## peak ages of the growth curves: [growth until, decline after]
const CURVE := {"early": [19, 22], "standard": [22, 25], "late": [24, 27], "flash": [19, 20]}

# ============================================================ match profile (战力管线)
## the profile a player takes into a match: sheet -> fatigue -> form -> teamwork modifiers (language, 磨合, relations).
## The proficiency stage, signature hero, traits and composure swings are applied later (Profiles.effective, hero_ai).
## mates: pids of the three starters (including p)
static func match_profile(world: Dictionary, p: Dictionary, mates: Array) -> Dictionary:
	var q: Dictionary = p.duplicate(false)
	var a := {}
	var pen := fatigue_penalty(p)
	var form: float = float(p.get("form", 0.0))
	for k in Profiles.ATTRS:
		a[k] = clampf(float(p["attrs"][k]) - pen + form, 1.0, 20.0)
	a["teamwork"] = clampf(float(a["teamwork"]) + teamwork_mod(world, str(p["id"]), mates), 1.0, 20.0)
	q["attrs"] = a
	return q

static func fatigue_penalty(p: Dictionary) -> float:
	var f: float = float(p.get("fatigue", 0.0))
	return 2.0 if f >= 90.0 else (1.0 if f >= 70.0 else 0.0)

## teamwork change of one player in a lineup: team communication + his own 磨合 + relations with the other two
static func teamwork_mod(world: Dictionary, pid: String, mates: Array) -> float:
	var m: float = comm_mod(world, mates)
	var p: Dictionary = world["players"][pid]
	m -= GEL_MALUS * maxf(0.0, GEL_WEEKS - float(p.get("wt", 0))) / GEL_WEEKS
	for q in mates:
		if str(q) == pid:
			continue
		var r := World.rel(world, pid, str(q))
		if r >= 50.0:
			m += 0.5
		elif r <= -50.0:
			m -= 1.0
	return m

## common language of two players: the best level both reach
static func common_lang(a: Dictionary, b: Dictionary) -> int:
	var best := 0
	for l in a.get("langs", {}):
		best = maxi(best, mini(int(a["langs"][l]), int(b.get("langs", {}).get(l, 0))))
	return best

static func comm_level(world: Dictionary, mates: Array) -> float:
	var tot := 0.0
	var n := 0
	for i in mates.size():
		for j in range(i + 1, mates.size()):
			tot += common_lang(world["players"][mates[i]], world["players"][mates[j]])
			n += 1
	return tot / n if n > 0 else 3.0

static func comm_mod(world: Dictionary, mates: Array) -> float:
	var c: float = comm_level(world, mates)
	var lo: int = clampi(int(floor(c)), 0, 3)
	var hi: int = mini(lo + 1, 3)
	return lerpf(float(COMM_MOD[lo]), float(COMM_MOD[hi]), c - float(lo))

## for the UI: {"comm": level 0..3, "mods": {pid: teamwork change}}
static func lineup_info(world: Dictionary, mates: Array) -> Dictionary:
	var mods := {}
	for q in mates:
		mods[q] = teamwork_mod(world, str(q), mates)
	return {"comm": comm_level(world, mates), "mods": mods}

# ============================================================ after a series / every week
## players who were on the field: fatigue, form, fame, relations between teammates who played together
static func after_series(world: Dictionary, s: Dictionary) -> void:
	for side in 2:
		var tid: String = str(s["a"] if side == 0 else s["b"])
		var played := {}
		var mvps := {}
		var won_maps := 0
		var lost_maps := 0
		for m in s["maps"]:
			if int(m["winner"]) == side:
				won_maps += 1
			else:
				lost_maps += 1
			for pid in m["players"]:
				if int(m["players"][pid].get("side", -1)) == side:
					played[pid] = true
			if str(m.get("mvp", "")) != "":
				mvps[str(m["mvp"])] = int(mvps.get(str(m["mvp"]), 0)) + 1
		var won: bool = str(s["winner"]) == tid
		for pid in played:
			if not world["players"].has(pid):
				continue
			var p: Dictionary = world["players"][pid]
			p["played_wk"] = true
			p["fatigue"] = clampf(float(p.get("fatigue", 0.0)) + PLAY_FATIGUE, 0.0, 100.0)
			var df := 0.4 * float(won_maps) - 0.4 * float(lost_maps) + 0.6 * float(mvps.get(pid, 0))
			p["form"] = clampf(float(p.get("form", 0.0)) + df, -FORM_MAX, FORM_MAX)
			p["fame"] = clampi(int(p.get("fame", 0)) + (1 if won else 0) + int(mvps.get(pid, 0)) + (2 if won and str(s["kind"]) == "final" else 0), 0, 100)
		var ids: Array = played.keys()
		for i in ids.size():
			for j in range(i + 1, ids.size()):
				World.add_rel(world, str(ids[i]), str(ids[j]), 2.0 if won else -0.5)

## end of a week (stage): form fades, bench streaks, 磨合, satisfaction. ranks: {tid: [rank, teams in league]}
static func weekly(world: Dictionary, ranks: Dictionary, playing: Dictionary) -> void:
	for pid in world["players"]:
		var p: Dictionary = world["players"][pid]
		if bool(p.get("retired", false)):
			continue
		p["form"] = float(p.get("form", 0.0)) * FORM_DECAY
		var tid: String = str(p["team"])
		if tid != "":
			p["wt"] = int(p.get("wt", 0)) + 1
			if playing.has(tid):
				p["bench_streak"] = 0 if bool(p.get("played_wk", false)) else int(p.get("bench_streak", 0)) + 1
		p["played_wk"] = false
		p["respect"] = lerpf(float(p.get("respect", 70.0)), 70.0, 0.2)
		var target := sat_target(world, p, ranks)
		var cur: float = float(p.get("sat", 70.0))
		var rate := 0.3
		if target < cur:
			rate = maxf(0.08, 0.3 - 0.02 * float(p["persona"].get("loyalty", 5)))
		p["sat"] = clampf(cur + (target - cur) * rate, 0.0, 100.0)

## satisfaction target (0..100): playing time, team success, pay, relations, respect — weighted by personality
static func sat_target(world: Dictionary, p: Dictionary, ranks: Dictionary) -> float:
	var per: Dictionary = p["persona"]
	var tid: String = str(p["team"])
	if tid == "":
		return 50.0
	var play: float = clampf(100.0 - 22.0 * float(p.get("bench_streak", 0)), 0.0, 100.0)
	var rk: Array = ranks.get(tid, [4, 8])
	var success: float = 100.0 * float(int(rk[1]) - int(rk[0])) / maxf(1.0, float(int(rk[1]) - 1))
	var pay_i: int = World.PAY_TIERS.find(str(p["contract"].get("pay", "low")))
	var want_i: int = World.PAY_TIERS.find(World.pay_for_rating(World.rating(p) + float(p.get("fame", 0)) / 40.0))
	var pay: float = clampf(60.0 + 25.0 * float(pay_i - want_i), 0.0, 100.0)
	var mates := 0.0
	var n := 0
	for q in World.team(world, tid)["players"]:
		if q != p["id"]:
			mates += (World.rel(world, str(p["id"]), str(q)) + 100.0) / 2.0
			n += 1
	var social: float = mates / maxf(1.0, n) if n > 0 else 50.0
	var resp: float = float(p.get("respect", 70.0))
	var w := [0.5 + 0.1 * float(per.get("ambition", 5)), 0.3 + 0.07 * float(per.get("ambition", 5)), 0.2 + 0.1 * float(per.get("greed", 5)),
		0.2 + 0.1 * float(per.get("social", 5)), 0.2 + 0.06 * float(per.get("pride", 5))]
	var v := [play, success, pay, social, resp]
	var tot := 0.0
	var ws := 0.0
	for i in 5:
		tot += float(w[i]) * float(v[i])
		ws += float(w[i])
	return tot / ws

# ============================================================ off-season
## once a year: age, natural growth / decline, retirement, contracts, state reset. Returns news lines.
## season_no: the season that just ended. Core characters do not retire at random while the story still needs them
## (before S5); their own timeline decides.
static func offseason(world: Dictionary, rng: RandomNumberGenerator, season_no := 1) -> Array:
	var news := []
	for pid in world["players"].keys():
		var p: Dictionary = world["players"][pid]
		if bool(p.get("retired", false)):
			continue
		p["age"] = int(p["age"]) + 1
		_age_curve(p, rng)
		p["fatigue"] = 0.0
		p["form"] = 0.0
		p["sat"] = lerpf(float(p.get("sat", 70.0)), 70.0, 0.5)
		var c: Dictionary = p["contract"]
		if str(p["team"]) != "":
			c["years"] = int(c.get("years", 1)) - 1
			if int(c["years"]) <= 0:
				# automatic renewal until the transfer system (M3): pay follows the current level
				c["years"] = 1 + rng.randi() % 2
				c["pay"] = World.pay_for_rating(World.rating(p))
		if pid == Cast.PROTAGONIST:
			continue
		var age: int = int(p["age"])
		if str(p.get("cast", "")) == "core" and season_no < 5 and age < 33:
			continue
		if age >= 28:
			var pr: float = 0.1 + 0.12 * float(age - 28) + (0.15 if float(p["sat"]) < 30.0 else 0.0) + (0.05 if int(p.get("fame", 0)) < 20 else 0.0)
			if age >= 32 or rng.randf() < pr:
				var tid: String = str(p["team"])
				World.retire(world, pid)
				if tid != "" or str(p.get("cast", "")) != "walkon":
					news.append("%s（%d 岁）宣布退役。" % [p["name"], age])
	return news

## natural growth before the peak, decline some years after it (reaction and mechanics first)
static func _age_curve(p: Dictionary, rng: RandomNumberGenerator) -> void:
	var cv: Array = CURVE.get(str(p.get("curve", "standard")), CURVE["standard"])
	var age: int = int(p["age"])
	var delta := 0.0
	var order: Array = []
	if age <= int(cv[0]):
		if World.rating(p) < float(p.get("pot", 20.0)):
			delta = rng.randf_range(0.3, 0.8)
		order = (p.get("focus", []) as Array).duplicate()
		for k in Profiles.ATTRS:
			if not order.has(k):
				order.append(k)
	elif age > int(cv[1]) + (0 if str(p.get("curve", "")) == "flash" else 2):
		delta = -rng.randf_range(0.5, 1.5) * (1.6 if str(p.get("curve", "")) == "flash" else 1.0)
		order = ["reaction", "mechanics", "teamwork", "composure", "decision", "awareness"]
	if delta == 0.0:
		return
	# spread |delta| x 6 attribute points, front of the list first
	var pts: float = absf(delta) * 6.0
	var i := 0
	while pts > 0.0 and i < 60:
		var k: String = str(order[mini(i % order.size(), order.size() - 1) if i < order.size() * 2 else rng.randi() % order.size()])
		var step := 1 if pts >= 1.0 or rng.randf() < pts else 0
		pts -= 1.0
		i += 1
		if step == 0:
			continue
		if delta > 0.0:
			if int(p["attrs"][k]) < 20 and World.rating(p) < float(p.get("pot", 20.0)):
				p["attrs"][k] = int(p["attrs"][k]) + 1
		else:
			p["attrs"][k] = maxi(1, int(p["attrs"][k]) - 1)

# ============================================================ lineups (4 选 3)
## best 3 starters of a club for the next map: {role: pid}. Uses the match profile (fatigue, form, teamwork) and the
## best open hero of that role. avoid: pids that should not play (e.g. a benched captain). Off-role is allowed.
static func best_lineup(world: Dictionary, tid: String, avoid := []) -> Dictionary:
	var Draft = load("res://game/league/draft.gd")
	var ids: Array = World.team(world, tid)["players"].duplicate()
	for a in avoid:
		ids.erase(a)
	var best := {}
	var best_v := -1e9
	var roles: Array = World.ROLES
	for i in ids.size():
		for j in ids.size():
			for k in ids.size():
				if i == j or j == k or i == k:
					continue
				var trio := [ids[i], ids[j], ids[k]]
				var v := 0.0
				for r in 3:
					var p: Dictionary = match_profile(world, world["players"][trio[r]], trio)
					v += Draft.role_value(p, str(roles[r]))
				if v > best_v:
					best_v = v
					best = {roles[0]: trio[0], roles[1]: trio[1], roles[2]: trio[2]}
	return best
