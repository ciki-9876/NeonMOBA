extends RefCounted
## The league world: clubs, players, staff, relations. Pure data (Dictionaries), no scene dependencies.
## Two builders:
##   build_fixed(run_seed, pick)  the fixed world (固定世界, game/league/cast_db.gd). Everything is the same in every run
##                                except the realised potential of each player and the walk-on youth (路人).
##   generate(seed)               a random world of the same shape (平行世界 mode, kept for tests and later).
##
## world  = {"seed", "fixed": bool, "teams": [team...], "players": {pid: player}, "staff": {id: person}, "rels": {"a|b": v},
##           "free": [pid] free agents, "walkons": [pid] walk-on candidates for the human team, "story": {...} (game/story)}
## team   = {"id", "name", "short", "tier": 1..3, "col", "league": "pro"|"sec", "players": [pid x4: 3 starters by role + bench],
##           "runes": {hid: page}, "human": bool, "coach": staff id or ""}
## player = profile (game/profiles.gd: name, attrs, prof, sig) + identity, personality and state, see docs/design/角色机制设计.md:
##           {"id", "name" (handle shown everywhere), "real", "role", "team", "gender", "nation", "langs": {code: 0..3}, "age",
##            "traits", "persona": {ambition, loyalty, greed, pride, social}, "pot_range": [lo, hi], "pot": realised cap,
##            "curve", "focus": [attr x2], "fame", "contract": {"years", "pay"}, "cast": "core"|"regular"|"gen"|"walkon",
##            state: "fatigue", "xp", "form", "sat", "wt" (weeks with the current team), "bench_streak", "respect"}
const HeroesDB = preload("res://heroes_db.gd")
const Profiles = preload("res://game/profiles.gd")
const RunesDB = preload("res://game/runes_db.gd")
const Cast = preload("res://game/league/cast_db.gd")

const ROLES := ["tank", "carry", "support"]
const TIER_MEAN := {1: 13.0, 2: 11.0, 3: 9.5}
const TIER_NAMES := {1: "豪门", 2: "中游", 3: "新军"}
const LEAGUE_NAMES := {"pro": "职业联赛", "sec": "次级联赛"}
const TRAITS := {"clutch": "残局之王", "big_stage": "大赛型", "slow_start": "慢热", "initiator": "开团手", "narrow_pool": "英雄池狭窄"}
const PERSONA_KEYS := ["ambition", "loyalty", "greed", "pride", "social"]
const PAY_TIERS := ["low", "mid", "high", "top"]
const ROSTER := 4

# ============================================================ fixed world
## pick: the 4th player of the human team (a Cast.CANDIDATES id or a walk-on id); "" = leave the slot open
static func build_fixed(run_seed: int, pick := "") -> Dictionary:
	var cast_rng := RandomNumberGenerator.new()
	cast_rng.seed = Cast.CAST_SEED
	var run := RandomNumberGenerator.new()
	run.seed = run_seed
	var world := {"seed": run_seed, "fixed": true, "teams": [], "players": {}, "staff": {}, "rels": {}, "free": [], "walkons": [], "story": {}}
	var used := {}
	for tid in Cast.TEAMS:
		var td: Dictionary = Cast.TEAMS[tid]
		world["teams"].append({"id": tid, "name": td["name"], "short": td["short"], "tier": int(td["tier"]), "col": td["col"],
			"league": td["league"], "players": [], "runes": {}, "human": tid == Cast.HUMAN_TEAM, "coach": ""})
	# core characters
	for pid in Cast.CORE:
		var c: Dictionary = Cast.CORE[pid]
		var p := {"id": pid, "name": c["handle"], "real": c["name"], "role": c["role"], "team": c["team"], "gender": c["gender"],
			"nation": c["nation"], "langs": (c["langs"] as Dictionary).duplicate(), "age": int(c["age"]), "attrs": {}, "prof": (c["prof"] as Dictionary).duplicate(),
			"sig": (c["sig"] as Dictionary).duplicate(), "traits": [], "persona": {}, "pot_range": (c["potential"] as Array).duplicate(),
			"curve": c["curve"], "focus": (c["focus"] as Array).duplicate(), "fame": int(c["fame"]),
			"contract": {"years": int(c["contract"][0]), "pay": str(c["contract"][1])}, "cast": "core", "tagline": c.get("tagline", "")}
		for i in 6:
			p["attrs"][Profiles.ATTRS[i]] = int(c["attrs"][i])
		for i in 5:
			p["persona"][PERSONA_KEYS[i]] = int(c["persona"][i])
		used[p["name"]] = true
		_add_player(world, p, str(c.get("slot", "starter")))
	# named regular players (numbers from the fixed cast rng)
	for pid in Cast.REGULAR:
		var r: Dictionary = Cast.REGULAR[pid]
		var mean: float = float(Cast.TEAMS[r["team"]]["mean"]) + float(r.get("boost", 0.0)) - (0.8 if str(r["slot"]) == "bench" else 0.0)
		var p := _gen_player(cast_rng, pid, str(r["handle"]), str(r["role"]), mean, int(r["age"]), str(r["gender"]), str(r["nation"]))
		if r.has("langs"):
			p["langs"] = (r["langs"] as Dictionary).duplicate()
		p["team"] = r["team"]
		p["cast"] = "regular"
		p["fame"] = _fame_for(cast_rng, int(Cast.TEAMS[r["team"]]["tier"]), str(r["slot"]) == "bench", str(Cast.TEAMS[r["team"]]["league"]))
		used[p["name"]] = true
		_add_player(world, p, str(r["slot"]))
	# 次级联赛 clubs: four generated players each (fixed by the cast rng)
	var n := 0
	for tid in Cast.TEAMS:
		if str(Cast.TEAMS[tid]["league"]) != "sec" or tid == Cast.HUMAN_TEAM:
			continue
		var roles: Array = ROLES.duplicate()
		roles.append(ROLES[cast_rng.randi() % 3])
		for i in 4:
			n += 1
			var nat := _rand_nation(cast_rng, 0.25)
			var p := _gen_player(cast_rng, "g%d" % n, _rand_name(cast_rng, nat, used), str(roles[i]), float(Cast.TEAMS[tid]["mean"]) - (0.8 if i == 3 else 0.0),
				18 + cast_rng.randi() % 8, "f" if cast_rng.randf() < 0.34 else "m", nat)
			p["team"] = tid
			p["cast"] = "gen"
			p["fame"] = _fame_for(cast_rng, 3, i == 3, "sec")
			_add_player(world, p, "bench" if i == 3 else "starter")
	# staff
	for sid in Cast.STAFF:
		var st: Dictionary = (Cast.STAFF[sid] as Dictionary).duplicate(true)
		st["id"] = sid
		var per := {}
		for i in 5:
			per[PERSONA_KEYS[i]] = int(st["persona"][i])
		st["persona"] = per
		world["staff"][sid] = st
		if str(st["kind"]) == "coach" and str(st["team"]) != "":
			team(world, str(st["team"]))["coach"] = sid
	# relations
	for l in Cast.LINKS:
		set_rel(world, str(l[0]), str(l[1]), float(Cast.LINK_VALUE[str(l[2])]) * (0.5 + 0.5 * float(l[3])))
	# per run: realised potential, walk-on youth, runes of the strong clubs
	for pid in world["players"]:
		_roll_potential(world["players"][pid], run)
	for i in 2:
		var w := new_walkon(world, run, ROLES[run.randi() % 3], used)
		world["walkons"].append(w)
	for i in 6:
		new_walkon(world, run, ROLES[i % 3], used)
	for t in world["teams"]:
		t["runes"] = _rune_pages(int(t["tier"]) if str(t["league"]) == "pro" else 3, t, world["players"])
	if pick != "":
		assign_pick(world, pick)
	return world

## the human team's 4th player (bench) at the start of a career
static func assign_pick(world: Dictionary, pid: String) -> void:
	if not world["players"].has(pid):
		return
	move_player(world, pid, Cast.HUMAN_TEAM)
	world["players"][pid]["wt"] = 0

## candidates for the 4th slot: the remembered names that are still free + the walk-ons
static func pick_options(world: Dictionary) -> Array:
	var out := []
	for pid in Cast.CANDIDATES:
		if world["players"].has(pid) and str(world["players"][pid]["team"]) == "":
			out.append(pid)
	for pid in world["walkons"]:
		if str(world["players"][pid]["team"]) == "":
			out.append(pid)
	return out

# ============================================================ random world (平行世界)
static func generate(seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var world := {"seed": seed, "fixed": false, "teams": [], "players": {}, "staff": {}, "rels": {}, "free": [], "walkons": [], "story": {}}
	var used := {}
	var ids: Array = Cast.TEAMS.keys()
	var n := 0
	for i in ids.size():
		var tid: String = ids[i]
		var td: Dictionary = Cast.TEAMS[tid]
		var tier: int = int(td["tier"])
		var t := {"id": tid, "name": td["name"], "short": td["short"], "tier": tier, "col": td["col"], "league": td["league"],
			"players": [], "runes": {}, "human": tid == Cast.HUMAN_TEAM, "coach": ""}
		world["teams"].append(t)
		var roles: Array = ROLES.duplicate()
		roles.append(ROLES[rng.randi() % 3])
		var mean: float = float(TIER_MEAN[tier]) if str(td["league"]) == "pro" else rng.randf_range(8.5, 10.0)
		for k in 4:
			n += 1
			var nat := _rand_nation(rng, 0.35)
			var p := _gen_player(rng, "r%d" % n, _rand_name(rng, nat, used), str(roles[k]), mean - (0.8 if k == 3 else 0.0), 17 + rng.randi() % 10,
				"f" if rng.randf() < 0.34 else "m", nat)
			p["team"] = tid
			p["cast"] = "gen"
			p["fame"] = _fame_for(rng, tier, k == 3, str(td["league"]))
			_add_player(world, p, "bench" if k == 3 else "starter")
	for pid in world["players"]:
		_roll_potential(world["players"][pid], rng)
	for i in 6:
		new_walkon(world, rng, ROLES[i % 3], used)
	for t in world["teams"]:
		t["runes"] = _rune_pages(int(t["tier"]) if str(t["league"]) == "pro" else 3, t, world["players"])
	return world

# ============================================================ generation helpers
static func _add_player(world: Dictionary, p: Dictionary, slot: String) -> void:
	for k in ["fatigue", "form"]:
		p[k] = 0.0
	p["xp"] = {}
	p["sat"] = 70.0
	p["wt"] = 20
	p["bench_streak"] = 0
	p["respect"] = 70.0
	if not p.has("traits"):
		p["traits"] = []
	world["players"][p["id"]] = p
	var tid: String = str(p["team"])
	if tid == "":
		world["free"].append(p["id"])
		p["wt"] = 0
		return
	var t := team(world, tid)
	if slot == "bench":
		t["players"].append(p["id"])
	else:
		# starters in role order, bench last
		var at := 0
		for q in t["players"]:
			if ROLES.find(str(world["players"][q]["role"])) < ROLES.find(str(p["role"])):
				at += 1
		t["players"].insert(mini(at, (t["players"] as Array).size()), p["id"])

static func _gen_player(rng: RandomNumberGenerator, pid: String, nm: String, role: String, mean: float, age: int, gender: String, nation: String) -> Dictionary:
	var p: Dictionary = Profiles.random(rng, nm, mean, 2.0)
	p["id"] = pid
	p["real"] = nm
	p["role"] = role
	p["age"] = age
	p["gender"] = gender
	p["nation"] = nation
	var lang: String = str(Cast.NATION_LANG.get(nation, "en"))
	p["langs"] = {lang: 3}
	if lang != "en":
		var en := rng.randi() % 3 if nation != "CN" else (1 if rng.randf() < 0.3 else 0)
		if en > 0:
			p["langs"]["en"] = en
	if nation != "CN" and rng.randf() < 0.5:
		p["langs"]["zh"] = 1 + rng.randi() % 2
	# hero pool: every hero of the role, 1-2 signature heroes
	var own := []
	var other := []
	for id in HeroesDB.ORDER:
		(own if str(HeroesDB.HEROES[id]["role"]) == role else other).append(id)
	_shuffle(rng, own)
	var prof := {}
	var sig := {}
	var n_sig := 1 + (1 if rng.randf() < 0.35 else 0)
	for i in own.size():
		var hid: String = own[i]
		if i < n_sig:
			prof[hid] = 70 + rng.randi() % 28
			var abil := _sig_for(hid)
			sig[hid] = str(abil[rng.randi() % abil.size()]) if not abil.is_empty() else ""
		else:
			prof[hid] = 20 + rng.randi() % 55
	_shuffle(rng, other)
	for i in 2:
		prof[other[i]] = 5 + rng.randi() % 40
	p["prof"] = prof
	p["sig"] = sig
	p["traits"] = [str(TRAITS.keys()[rng.randi() % TRAITS.size()])] if rng.randf() < 0.3 else []
	var per := {}
	for k in PERSONA_KEYS:
		per[k] = 2 + rng.randi() % 7
	p["persona"] = per
	var r := rating(p)
	var head: float = 3.0 if age <= 20 else (2.0 if age <= 23 else 1.0)
	p["pot_range"] = [snappedf(r, 0.1), snappedf(minf(19.0, r + head), 0.1)]
	p["curve"] = ["early", "standard", "standard", "late", "flash"][rng.randi() % 5]
	var fa: Array = Profiles.ATTRS.duplicate()
	_shuffle(rng, fa)
	p["focus"] = [fa[0], fa[1]]
	p["contract"] = {"years": 1 + rng.randi() % 3, "pay": pay_for_rating(r)}
	return p

static func _roll_potential(p: Dictionary, rng: RandomNumberGenerator) -> void:
	var lo: float = float(p["pot_range"][0])
	var hi: float = float(p["pot_range"][1])
	p["pot"] = snappedf(maxf(rating(p), rng.randf_range(lo, hi)), 0.1)

static func _fame_for(rng: RandomNumberGenerator, tier: int, bench: bool, league: String) -> int:
	if league == "sec":
		return rng.randi() % 10
	var base: int = {1: 45, 2: 20, 3: 8}[tier]
	return maxi(0, base + rng.randi() % 25 - (20 if bench else 0))

static func pay_for_rating(r: float) -> String:
	return "low" if r < 9.5 else ("mid" if r < 11.5 else ("high" if r < 13.5 else "top"))

static func _rand_nation(rng: RandomNumberGenerator, foreign: float) -> String:
	if rng.randf() >= foreign:
		return "CN"
	var keys: Array = Cast.NAMES_INT.keys()
	return str(keys[rng.randi() % keys.size()])

static func _rand_name(rng: RandomNumberGenerator, nation: String, used: Dictionary) -> String:
	var pool: Array = Cast.NAMES_ZH if nation == "CN" else Cast.NAMES_INT.get(nation, Cast.NAMES_ZH)
	for _i in 40:
		var nm := str(pool[rng.randi() % pool.size()])
		if not used.has(nm):
			used[nm] = true
			return nm
	var nm2 := "%s%d" % [str(pool[rng.randi() % pool.size()]), 2 + rng.randi() % 98]
	used[nm2] = true
	return nm2

## a walk-on youth (路人): free agent, young, low ability, sometimes a hidden talent
static func new_walkon(world: Dictionary, rng: RandomNumberGenerator, role: String, used := {}) -> String:
	if used.is_empty():
		for q in world["players"]:
			used[str(world["players"][q]["name"])] = true
	var k: int = (world["players"] as Dictionary).size() + 1
	var pid := "w%d_%d" % [int(world["seed"]) % 100000, k]
	while world["players"].has(pid):
		k += 1
		pid = "w%d_%d" % [int(world["seed"]) % 100000, k]
	var nat := _rand_nation(rng, 0.2)
	var p := _gen_player(rng, pid, _rand_name(rng, nat, used), role, rng.randf_range(7.5, 9.0), 16 + rng.randi() % 4, "f" if rng.randf() < 0.34 else "m", nat)
	p["team"] = ""
	p["cast"] = "walkon"
	p["fame"] = 0
	p["contract"] = {"years": 0, "pay": "low"}
	var r := rating(p)
	p["pot_range"] = [snappedf(r + 1.0, 0.1), snappedf(minf(19.0, r + (6.0 if rng.randf() < 0.15 else 3.5)), 0.1)]   # 15%: a hidden talent
	_add_player(world, p, "")
	_roll_potential(p, rng)
	return pid

static func _sig_for(hid: String) -> Array:
	var out := []
	for k in RunesDB.SIGNATURES:
		if str(RunesDB.SIGNATURES[k]["hero"]) == hid:
			out.append(k)
	return out

## AI clubs own a few rune pages for their players' signature heroes (stronger tiers own more)
static func _rune_pages(tier: int, t: Dictionary, players: Dictionary) -> Dictionary:
	var pages := {}
	var stacks: int = {1: 2, 2: 1, 3: 0}[tier]
	if stacks <= 0 or bool(t.get("human", false)):
		return pages
	for pid in t["players"]:
		for hid in players[pid]["sig"]:
			pages[hid] = {"r_vital": stacks, "r_edge": stacks, "r_guard": stacks}
	return pages

static func _shuffle(rng: RandomNumberGenerator, a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t

# ============================================================ queries
static func team(world: Dictionary, tid: String) -> Dictionary:
	for t in world["teams"]:
		if str(t["id"]) == tid:
			return t
	return {}

static func team_players(world: Dictionary, tid: String) -> Array:
	var out := []
	for pid in team(world, tid).get("players", []):
		out.append(world["players"][pid])
	return out

static func league_teams(world: Dictionary, league: String) -> Array:
	var out := []
	for t in world["teams"]:
		if str(t["league"]) == league:
			out.append(str(t["id"]))
	return out

static func human_team(world: Dictionary) -> String:
	for t in world["teams"]:
		if bool(t.get("human", false)):
			return str(t["id"])
	return ""

## mean ability of a player (6 attrs)
static func rating(p: Dictionary) -> float:
	var s := 0.0
	for k in Profiles.ATTRS:
		s += float(p["attrs"][k])
	return s / Profiles.ATTRS.size()

static func person(world: Dictionary, id: String) -> Dictionary:
	if world["players"].has(id):
		return world["players"][id]
	return world["staff"].get(id, {})

static func display_name(world: Dictionary, id: String) -> String:
	return str(person(world, id).get("name", id))

# ============================================================ relations
static func rel_key(a: String, b: String) -> String:
	return (a + "|" + b) if a < b else (b + "|" + a)

static func rel(world: Dictionary, a: String, b: String) -> float:
	return float(world["rels"].get(rel_key(a, b), 0.0))

static func set_rel(world: Dictionary, a: String, b: String, v: float) -> void:
	world["rels"][rel_key(a, b)] = clampf(v, -100.0, 100.0)

static func add_rel(world: Dictionary, a: String, b: String, d: float) -> void:
	set_rel(world, a, b, rel(world, a, b) + d)

# ============================================================ roster moves
## move a player to a club (tid "" = free agent). The club keeps at most ROSTER players: when it is full, the player
## whose departure costs the least (see _roster_strength) is released.
static func move_player(world: Dictionary, pid: String, tid: String) -> String:
	var p: Dictionary = world["players"][pid]
	var old: String = str(p["team"])
	if old != "":
		team(world, old)["players"].erase(pid)
	world["free"].erase(pid)
	var released := ""
	p["team"] = tid
	p["wt"] = 0
	p["bench_streak"] = 0
	if tid == "":
		world["free"].append(pid)
		return ""
	var t := team(world, tid)
	if (t["players"] as Array).size() >= ROSTER:
		# release the player whose departure costs the club the least (best player per role + a little for depth)
		var worst := ""
		var worst_v := 1e9
		for q in t["players"]:
			if q == Cast.PROTAGONIST:
				continue
			var left: Array = t["players"].duplicate()
			left.erase(q)
			left.append(pid)
			var loss: float = -_roster_strength(world, left)
			if loss < worst_v:
				worst_v = loss
				worst = q
		if worst != "":
			t["players"].erase(worst)
			world["players"][worst]["team"] = ""
			world["players"][worst]["wt"] = 0
			world["free"].append(worst)
			released = worst
	t["players"].append(pid)
	return released

## strength of a roster: the best player of each role (a missing role costs a lot) + 30% of the rest
static func _roster_strength(world: Dictionary, ids: Array) -> float:
	var used := {}
	var tot := 0.0
	for r in ROLES:
		var best := ""
		var bv := -1.0
		for x in ids:
			if not used.has(x) and str(world["players"][x]["role"]) == r and rating(world["players"][x]) > bv:
				bv = rating(world["players"][x])
				best = x
		if best == "":
			tot -= 20.0
		else:
			used[best] = true
			tot += bv
	for x in ids:
		if not used.has(x):
			tot += 0.3 * rating(world["players"][x])
	return tot

## a player leaves the game (retirement)
static func retire(world: Dictionary, pid: String) -> void:
	var p: Dictionary = world["players"][pid]
	if str(p["team"]) != "":
		team(world, str(p["team"]))["players"].erase(pid)
	world["free"].erase(pid)
	p["team"] = ""
	p["retired"] = true

## fill a club up to ROSTER and make sure every role has someone: best fitting free agent, else a new walk-on
static func fix_roster(world: Dictionary, tid: String, rng: RandomNumberGenerator) -> Array:
	var t := team(world, tid)
	var added := []
	var guard := 0
	while (t["players"] as Array).size() < ROSTER and guard < 8:
		guard += 1
		var need := ""
		for r in ROLES:
			var has := false
			for q in t["players"]:
				if str(world["players"][q]["role"]) == r:
					has = true
			if not has:
				need = r
				break
		if need == "":
			need = ROLES[rng.randi() % 3]
		var best := ""
		var best_v := -1e9
		for q in world["free"]:
			var fp: Dictionary = world["players"][q]
			if bool(fp.get("retired", false)) or str(fp["role"]) != need or str(fp.get("cast", "")) == "core":
				continue   # core characters move only through their own story
			var v: float = rating(fp) + rng.randf() * 0.5
			if v > best_v:
				best_v = v
				best = q
		if best == "" or (bool(t.get("human", false))):
			best = new_walkon(world, rng, need)
		move_player(world, best, tid)
		added.append(best)
	return added
