extends RefCounted
## Stage 2B — map veto and hero ban/pick (禁选) for a BO3 series. Pure logic, used by the AI teams,
## the human draft screen (ui/league_ui.gd) and the headless season runner.
##
## Map veto (4-map pool, game/maps.gd POOL): A picks map 1, B picks map 2, A bans one of the two left,
## the last one is the decider (map 3).
## Hero draft per map, role-locked (each team ends with 1 tank, 1 carry, 1 support — one per player):
##   ban A, ban B, ban A, ban B, pick A, pick B, pick B, pick A, pick A, pick B
## A hero banned or picked by either side is gone for this map.
const HeroesDB = preload("res://heroes_db.gd")
const Profiles = preload("res://game/profiles.gd")
const Maps = preload("res://game/maps.gd")
const World = preload("res://game/league/world.gd")

const ORDER := [["ban", 0], ["ban", 1], ["ban", 0], ["ban", 1],
	["pick", 0], ["pick", 1], ["pick", 1], ["pick", 0], ["pick", 0], ["pick", 1]]

## win-rate prior of each hero in AI-vs-AI play (logit units, + = stronger). Updated from the 60-map balance run
## (docs/design/英雄设计体系_3C.md), halved for noise: (win rate − 50%) / 100. The AI drafts with it and the quick
## resolver uses it (Draft.value adds 2 × prior ability points).
const HERO_PRIOR := {"ember": 0.12, "lumen": 0.09, "drift": 0.08, "aegis": 0.08, "seer": 0.05, "echo": 0.02, "anchor": 0.02, "frost": 0.00, "falcon": -0.05, "rail": -0.09, "blade": -0.10, "tide": -0.15}

# ------------------------------------------------------------ map veto
## state: {"pool": [...], "maps": [m1, m2, m3], "bans": [...], "step": 0..3}; steps: A pick, B pick, A ban, done
static func new_veto() -> Dictionary:
	return {"pool": Maps.POOL.duplicate(), "maps": [], "bans": [], "step": 0}

static func veto_side(v: Dictionary) -> int:
	return [0, 1, 0, -1][mini(int(v["step"]), 3)]

static func veto_action(v: Dictionary) -> String:
	return ["pick", "pick", "ban", "done"][mini(int(v["step"]), 3)]

static func veto_left(v: Dictionary) -> Array:
	var out := []
	for m in v["pool"]:
		if not v["maps"].has(m) and not v["bans"].has(m):
			out.append(m)
	return out

static func veto_apply(v: Dictionary, m: String) -> void:
	match veto_action(v):
		"pick": v["maps"].append(m)
		"ban":
			v["bans"].append(m)
			v["maps"].append(veto_left(v)[0])
	v["step"] = int(v["step"]) + 1

## AI map choice: pick the map where its own lineup did best (per-team map record), ban the opponent's best;
## without history it picks at random (rng = the season rng)
static func veto_ai(v: Dictionary, side: int, record: Dictionary, rng: RandomNumberGenerator) -> String:
	var left := veto_left(v)
	var best := ""
	var best_v := -1e9
	for m in left:
		var r: Array = record.get(m, [0, 0])
		var wr: float = (float(r[0]) + 1.0) / (float(r[0]) + float(r[1]) + 2.0)
		var val: float = wr + rng.randf() * 0.2
		if veto_action(v) == "ban":
			val = -val
		if val > best_v:
			best_v = val
			best = m
	return best

# ------------------------------------------------------------ hero draft
## state: {"step", "first": side with the first ban and pick, "bans": [[], []], "picks": [{role: hid}, {role: hid}], "taken": {hid: true}}
static func new_draft(first := 0) -> Dictionary:
	return {"step": 0, "first": first, "bans": [[], []], "picks": [{}, {}], "taken": {}}

static func done(d: Dictionary) -> bool:
	return int(d["step"]) >= ORDER.size()

## [action, side] of the next step ("done", -1 at the end)
static func current(d: Dictionary) -> Array:
	if done(d):
		return ["done", -1]
	var o: Array = ORDER[int(d["step"])]
	return [o[0], (int(o[1]) + int(d.get("first", 0))) % 2]

## heroes the side may ban / pick now. A ban may not leave a role with fewer heroes than the teams still need.
static func available(d: Dictionary, side: int, action: String) -> Array:
	var out := []
	for hid in HeroesDB.ORDER:
		if d["taken"].has(hid):
			continue
		var role: String = str(HeroesDB.HEROES[hid]["role"])
		if action == "pick" and (d["picks"][side] as Dictionary).has(role):
			continue
		if action == "ban" and _open_in_role(d, role) - 1 < _need(d, role):
			continue
		out.append(hid)
	return out

static func _open_in_role(d: Dictionary, role: String) -> int:
	var n := 0
	for hid in HeroesDB.ORDER:
		if not d["taken"].has(hid) and str(HeroesDB.HEROES[hid]["role"]) == role:
			n += 1
	return n

static func _need(d: Dictionary, role: String) -> int:
	var n := 0
	for side in 2:
		if not (d["picks"][side] as Dictionary).has(role):
			n += 1
	return n

static func apply(d: Dictionary, hid: String) -> void:
	var cur := current(d)
	var side: int = int(cur[1])
	if str(cur[0]) == "ban":
		d["bans"][side].append(hid)
	else:
		d["picks"][side][str(HeroesDB.HEROES[hid]["role"])] = hid
	d["taken"][hid] = true
	d["step"] = int(d["step"]) + 1

## how good player p is on hero hid, in "ability points" (the unit of game/profiles.gd attrs):
## the mean ability scaled by the proficiency stage, a signature-hero bonus and the hero's general strength
static func value(p: Dictionary, hid: String) -> float:
	var v: float = World.rating(p) * float(Profiles.stage(p, hid)[2])
	if (p.get("sig", {}) as Dictionary).has(hid):
		v += 0.6
	return v + float(HERO_PRIOR.get(hid, 0.0)) * 2.0

## best value of a player over the heroes of a role (lineup choice, 4 选 3)
static func role_value(p: Dictionary, role: String) -> float:
	var best := -1e9
	for hid in HeroesDB.ORDER:
		if str(HeroesDB.HEROES[hid]["role"]) == role:
			best = maxf(best, value(p, hid))
	return best

## AI ban / pick. noise (ability points) makes weaker teams draft worse.
static func ai_choice(d: Dictionary, side: int, mine: Dictionary, theirs: Dictionary, rng: RandomNumberGenerator, noise := 0.5) -> String:
	var cur := current(d)
	var action: String = str(cur[0])
	var best := ""
	var best_v := -1e9
	for hid in available(d, side, action):
		var role: String = str(HeroesDB.HEROES[hid]["role"])
		var v := 0.0
		if action == "pick":
			if not mine.has(role):
				continue
			# value over this player's next best option still open: grab what would otherwise be lost
			v = value(mine[role], hid) + 0.3 * (value(mine[role], hid) - _second_best(d, mine[role], role, hid))
		else:
			# ban what the opponent player of that role would gain most from, unless they already picked that role
			if not theirs.has(role) or (d["picks"][1 - side] as Dictionary).has(role):
				continue
			v = value(theirs[role], hid) - _second_best(d, theirs[role], role, hid)
			if (theirs[role].get("sig", {}) as Dictionary).has(hid):
				v += 0.4
		v += rng.randfn(0.0, noise)
		if v > best_v:
			best_v = v
			best = hid
	if best == "":
		var av := available(d, side, action)
		best = str(av[rng.randi() % av.size()])
	return best

static func _second_best(d: Dictionary, p: Dictionary, role: String, skip: String) -> float:
	var best := -1e9
	for hid in HeroesDB.ORDER:
		if hid == skip or d["taken"].has(hid) or str(HeroesDB.HEROES[hid]["role"]) != role:
			continue
		best = maxf(best, value(p, hid))
	return best if best > -1e8 else 0.0

## lineup in slot order for game/match.gd: [hero ids], [profiles] — the player listed first in `order` goes first
static func lineup(d: Dictionary, side: int, roles: Dictionary, order: Array) -> Array:
	var heroes := []
	var profs := []
	for role in order:
		heroes.append(str(d["picks"][side][role]))
		profs.append(roles[role])
	return [heroes, profs]

## noise of a team's drafting (coach quality): tier 1 drafts sharply, tier 3 makes mistakes
## a coach with the 禁选大师 skill removes the mistakes (game/league/cast_db.gd COACH_SKILLS)
static func noise_for(team: Dictionary, world := {}) -> float:
	var coach: String = str(team.get("coach", ""))
	if coach != "" and not world.is_empty():
		var sk: String = str(world.get("staff", {}).get(coach, {}).get("skill", ""))
		var Cast = load("res://game/league/cast_db.gd")
		if Cast.COACH_SKILLS.has(sk):
			return float(Cast.COACH_SKILLS[sk]["draft_noise"])
	return {1: 0.3, 2: 0.6, 3: 1.0}.get(int(team["tier"]), 0.6)
