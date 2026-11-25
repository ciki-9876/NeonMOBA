extends RefCounted
## Player (选手) profiles: the 6 abilities, hero proficiency and signature heroes.
## A profile is a plain Dictionary so it can be saved, generated and shown in UI easily:
##   {"name": "阿星",
##    "attrs": {"reaction": 12, "mechanics": 14, "awareness": 10, "decision": 11, "teamwork": 9, "composure": 13},   # 1..20
##    "prof": {"anchor": 95, "frost": 40},        # hero proficiency 0..100 (missing = 0)
##    "sig": {"anchor": "anchor_far_hook"}}       # signature heroes -> their exclusive ability (game/runes_db.gd SIGNATURES)
## How each ability drives the AI: hero_ai.gd apply_profile(); design: docs (核心对战规则与选手属性设计).

const ATTRS := ["reaction", "mechanics", "awareness", "decision", "teamwork", "composure"]
const ATTR_NAMES := {"reaction": "反应", "mechanics": "操作", "awareness": "意识", "decision": "决断", "teamwork": "配合", "composure": "心态"}

## proficiency stages: [min proficiency, name, ability multiplier]
## calibrated: 生疏 vs 精通 on the same player should cost roughly 10–15% win rate (stage 1 batch)
const STAGES := [[0, "生疏", 0.88], [25, "熟悉", 0.94], [60, "精通", 1.00], [90, "大师", 1.03]]
const SIG_PROF_BONUS := 2.0      # signature heroes gain proficiency twice as fast (training, stage 3)

static func make(pname: String, v: int, prof := {}, sig := {}) -> Dictionary:
	var a := {}
	for k in ATTRS:
		a[k] = v
	return {"name": pname, "attrs": a, "prof": prof, "sig": sig}

## the profile used when a match is started without explicit players (menu difficulty 0/1/2)
static func from_difficulty(diff: int) -> Dictionary:
	return make("AI", [6, 11, 16][clampi(diff, 0, 2)], {}, {})

## random profile around `mean` (rng = the match rng, so generation is reproducible)
static func random(rng: RandomNumberGenerator, pname: String, mean: float, spread := 3.0) -> Dictionary:
	var a := {}
	for k in ATTRS:
		a[k] = clampi(int(round(mean + rng.randfn(0.0, spread))), 1, 20)
	return {"name": pname, "attrs": a, "prof": {}, "sig": {}}

static func proficiency(p: Dictionary, hero_id: String) -> float:
	return float(p.get("prof", {}).get(hero_id, 60.0 if p.get("prof", {}).is_empty() else 0.0))

static func stage(p: Dictionary, hero_id: String) -> Array:
	var v := proficiency(p, hero_id)
	var out: Array = STAGES[0]
	for s in STAGES:
		if v >= float(s[0]):
			out = s
	return out

## how strongly ability differences show around an average player (11): calibration knob, see
## docs/design/核心对战规则与选手属性设计.md (target: +2 -> ~60% win rate, +5 -> ~80%)
const SENSITIVITY := 1.2
const AVERAGE := 11.0

## 0..1 effective ability on this hero: ((attr * stage multiplier) around AVERAGE, scaled by SENSITIVITY),
## plus an optional composure swing
static func effective(p: Dictionary, hero_id: String, swing := {}) -> Dictionary:
	var mult: float = float(stage(p, hero_id)[2])
	var out := {}
	for k in ATTRS:
		var v: float = float(p["attrs"].get(k, 10)) * (mult if k != "composure" else 1.0) + float(swing.get(k, 0.0))
		v = AVERAGE + (v - AVERAGE) * SENSITIVITY
		out[k] = clampf((v - 1.0) / 19.0, 0.0, 1.0)
	return out

static func signature(p: Dictionary, hero_id: String) -> String:
	return str(p.get("sig", {}).get(hero_id, ""))
