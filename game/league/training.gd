extends RefCounted
## Stage 3 (C1/C2) — weekly schedule and training. Pure data on the season Dictionary, no scene dependencies.
##
## Every stage of the season (regular season week, semi-finals, final) is one "week". Before a team plays it
## trains: each player has one focus per week —
##   "attr:<ability>"  one of the 6 abilities gains experience, 1 point when the bar is full (harder the higher it is)
##   "hero:<hero id>"  hero proficiency grows (signature heroes ×2, slower near 100)
##   "rest"            fatigue −35
## Fatigue (0..100): training +14, natural recovery −12 per week; playing a series +6 (game/league/people.gd, only for
## the players who were on the field). Above 40 training gets less effective,
## and at ≥70 / ≥90 the player is 1 / 2 ability points below his sheet in matches (see in_form). Heroes a player
## does not train slowly lose proficiency (0.5 / week, signature 0.25; only above 60).
## AI teams follow the same rules with auto_plan(); the human team uses the plan set by the UI (or auto_plan).
## Design: docs/design/经营与养成设计.md, 赛事层设计.md.
const Profiles = preload("res://game/profiles.gd")
const World = preload("res://game/league/world.gd")
const HeroesDB = preload("res://heroes_db.gd")

const ATTR_XP := 4.5          # experience of one attribute session at age factor 1 and no fatigue
const HERO_GAIN := 10.0       # proficiency of one hero session (before signature ×2 and the slow-down near 100)
const TRAIN_FATIGUE := 14.0
const RECOVER := 12.0
const REST_RECOVER := 35.0
const DECAY := 0.5
const MAX_ATTR := 20
const AI_GROWTH := 0.5       # AI teams develop slower than a team that is managed by hand (their plans are not optimised)

## --- state --------------------------------------------------------------------------------------

## the training state lives in season["train"]; players get fatigue / xp lazily
static func ensure(season: Dictionary) -> Dictionary:
	if not season.has("train"):
		season["train"] = {"ai_key": -1, "human_key": -1, "plans": {}, "log": []}
	for pid in season["world"]["players"]:
		var p: Dictionary = season["world"]["players"][pid]
		if not p.has("fatigue"):
			p["fatigue"] = 0.0
		if not p.has("xp"):
			p["xp"] = {}
	return season["train"]

## identifies the current stage: regular week index, 100+n for playoff stage n, -1 when the season is over
static func stage_key(season: Dictionary) -> int:
	var base: int = 1000 * int(season.get("no", 1))
	match str(season["phase"]):
		"regular": return base + int(season["week"])
		"playoffs": return base + 100 + (season["leagues"]["pro"]["playoffs"] as Array).size()
		"promo": return base + 200
	return -1

static func need(v: int) -> float:
	return 1.5 + 0.45 * float(maxi(0, v - 8))

static func age_factor(p: Dictionary) -> float:
	return clampf(1.3 - 0.07 * float(int(p.get("age", 20)) - 17), 0.6, 1.3)

static func efficiency(p: Dictionary) -> float:
	return 1.0 - clampf((float(p.get("fatigue", 0.0)) - 40.0) / 80.0, 0.0, 0.7)

## ability points lost to tiredness in a match
static func form_penalty(p: Dictionary) -> int:
	var f: float = float(p.get("fatigue", 0.0))
	return 2 if f >= 90.0 else (1 if f >= 70.0 else 0)

## the profile used in a match: the player's sheet minus the tiredness penalty (same dict when fresh)
static func in_form(p: Dictionary) -> Dictionary:
	var pen := form_penalty(p)
	if pen == 0:
		return p
	var q: Dictionary = p.duplicate(false)
	var a: Dictionary = (p["attrs"] as Dictionary).duplicate()
	for k in Profiles.ATTRS:
		a[k] = maxi(1, int(a[k]) - pen)
	q["attrs"] = a
	return q

# --- plans ---------------------------------------------------------------------------------------

## a sensible plan for a player: rest when tired, otherwise work on a weak ability or a main hero
static func auto_plan(p: Dictionary, rng: RandomNumberGenerator) -> String:
	if float(p.get("fatigue", 0.0)) > 62.0:
		return "rest"
	if rng.randf() < 0.35:
		var cand := []
		for hid in (p["prof"] as Dictionary):
			var pr: float = float(p["prof"][hid])
			if pr < 92.0 and str(HeroesDB.HEROES[hid]["role"]) == str(p["role"]):
				cand.append([hid, pr])
		if not cand.is_empty():
			# train the best hero of the pool that is not mastered yet (the one most likely to be played)
			cand.sort_custom(func(x, y): return float(x[1]) > float(y[1]))
			var pick: int = mini(cand.size() - 1, int(rng.randf() * rng.randf() * float(cand.size())))
			return "hero:" + str(cand[pick][0])
	var weights := []
	var tot := 0.0
	for k in Profiles.ATTRS:
		var w: float = pow(maxf(0.5, float(MAX_ATTR) - float(p["attrs"][k])), 1.5)
		weights.append(w)
		tot += w
	var r := rng.randf() * tot
	for i in Profiles.ATTRS.size():
		r -= float(weights[i])
		if r <= 0.0:
			return "attr:" + str(Profiles.ATTRS[i])
	return "attr:" + str(Profiles.ATTRS[0])

static func plan_text(plan: String) -> String:
	if plan == "rest":
		return "休息"
	if plan.begins_with("attr:"):
		return "训练 " + str(Profiles.ATTR_NAMES.get(plan.substr(5), plan))
	if plan.begins_with("hero:"):
		return "练英雄 " + str(HeroesDB.HEROES.get(plan.substr(5), {}).get("name", plan))
	return plan

# --- applying a week ---------------------------------------------------------------------------------

## one player's week. Returns {"pid", "plan", "text"} (text: what happened, for the UI)
static func apply_plan(p: Dictionary, plan: String, rng: RandomNumberGenerator, growth := 1.0) -> Dictionary:
	var eff := efficiency(p) * growth
	var text := ""
	var trained_hero := ""
	var f: float = float(p.get("fatigue", 0.0))
	if plan == "none":
		text = ""       # no training at all (tests: the "do nothing" baseline)
	elif plan == "rest":
		f -= REST_RECOVER
		text = "休息，疲劳 -%d" % int(REST_RECOVER)
	elif plan.begins_with("attr:"):
		var k := plan.substr(5)
		var v: int = int(p["attrs"][k])
		var xp: Dictionary = p["xp"]
		var gain := ATTR_XP * age_factor(p) * eff * rng.randf_range(0.8, 1.2)
		if World.rating(p) >= float(p.get("pot", 20.0)):
			gain = 0.0      # at the potential cap: training keeps the level but cannot raise it
		xp[k] = float(xp.get(k, 0.0)) + gain
		var up := 0
		while v < MAX_ATTR and float(xp[k]) >= need(v):
			xp[k] = float(xp[k]) - need(v)
			v += 1
			up += 1
		p["attrs"][k] = v
		f += TRAIN_FATIGUE
		var prog := "已满" if v >= MAX_ATTR else ("已到瓶颈" if gain == 0.0 else "下一点 %d%%" % int(100.0 * float(xp[k]) / need(v)))
		text = ("%s +%d（%s）" if up > 0 else "%s 进度（%s）") % ([Profiles.ATTR_NAMES[k], up, prog] if up > 0 else [Profiles.ATTR_NAMES[k], prog])
	elif plan.begins_with("hero:"):
		var hid := plan.substr(5)
		trained_hero = hid
		var pr: float = float(p["prof"].get(hid, 0.0))
		var mult: float = Profiles.SIG_PROF_BONUS if (p["sig"] as Dictionary).has(hid) else 1.0
		var gain := HERO_GAIN * mult * (1.0 - pr / 130.0) * eff * rng.randf_range(0.8, 1.2)
		var before: String = str(Profiles.stage(p, hid)[1])
		p["prof"][hid] = minf(100.0, pr + gain)
		var after: String = str(Profiles.stage(p, hid)[1])
		f += TRAIN_FATIGUE
		text = "%s 熟练度 +%d" % [HeroesDB.HEROES[hid]["name"], int(round(gain))]
		if after != before:
			text += "，升到「%s」" % after
	# natural recovery, then slow proficiency decay of heroes not trained this week
	f = clampf(f - RECOVER, 0.0, 100.0)
	p["fatigue"] = f
	for hid in (p["prof"] as Dictionary):
		if hid == trained_hero:
			continue
		var pr2: float = float(p["prof"][hid])
		if pr2 > 60.0:
			p["prof"][hid] = maxf(60.0, pr2 - (DECAY * 0.5 if (p["sig"] as Dictionary).has(hid) else DECAY))
	return {"pid": str(p["id"]), "plan": plan, "text": text}

## the AI teams train once at the start of a stage (idempotent per stage)
static func start_stage(season: Dictionary) -> void:
	var tr := ensure(season)
	var key := stage_key(season)
	if key < 0 or int(tr["ai_key"]) == key:
		return
	tr["ai_key"] = key
	var rng := RandomNumberGenerator.new()
	rng.seed = int(season["seed"]) * 131 + key * 17 + 5
	for t in season["world"]["teams"]:
		if str(t["id"]) == str(season["human"]):
			continue
		for pid in t["players"]:
			var p: Dictionary = season["world"]["players"][pid]
			apply_plan(p, auto_plan(p, rng), rng, AI_GROWTH)

## the human team's players train (idempotent per stage); a player without a set plan gets auto_plan.
## Returns the report lines [{pid, plan, text}] (also stored in season["train"]["log"])
static func commit_human(season: Dictionary) -> Array:
	var tr := ensure(season)
	var key := stage_key(season)
	if key < 0 or str(season["human"]) == "" or int(tr["human_key"]) == key:
		return []
	tr["human_key"] = key
	var rng := RandomNumberGenerator.new()
	rng.seed = int(season["seed"]) * 977 + key * 31 + 9
	var lines := []
	var team: Dictionary = World.team(season["world"], str(season["human"]))
	for pid in team["players"]:
		var p: Dictionary = season["world"]["players"][pid]
		var plan: String = str(tr["plans"].get(pid, ""))
		if plan == "":
			plan = auto_plan(p, rng)
		lines.append(apply_plan(p, plan, rng))
	tr["plans"] = {}
	tr["log"] = lines
	tr["log_key"] = key
	return lines

static func set_plan(season: Dictionary, pid: String, plan: String) -> void:
	ensure(season)["plans"][pid] = plan

static func plan_of(season: Dictionary, pid: String) -> String:
	return str(ensure(season)["plans"].get(pid, ""))

## has the human team already trained in the current stage?
static func committed(season: Dictionary) -> bool:
	return int(ensure(season)["human_key"]) == stage_key(season)

## options of a player for the UI: [[plan, label]]
static func options(p: Dictionary) -> Array:
	var out := []
	for k in Profiles.ATTRS:
		out.append(["attr:" + k, "能力 · %s（%d）" % [Profiles.ATTR_NAMES[k], int(p["attrs"][k])]])
	var heroes: Array = (p["prof"] as Dictionary).keys()
	heroes.sort_custom(func(x, y): return float(p["prof"][x]) > float(p["prof"][y]))
	for hid in heroes:
		if float(p["prof"][hid]) >= 100.0:
			continue
		var star := "★" if (p["sig"] as Dictionary).has(hid) else ""
		out.append(["hero:" + hid, "英雄 · %s%s（%s %d）" % [star, HeroesDB.HEROES[hid]["name"], Profiles.stage(p, hid)[1], int(float(p["prof"][hid]))]])
	out.append(["rest", "休息（疲劳 -35）"])
	return out
