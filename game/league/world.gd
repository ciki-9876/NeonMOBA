extends RefCounted
## Stage 2A — generates the league world from a seed: teams, players (选手) and their hero pools.
## Pure data (Dictionaries), reproducible from the seed, no scene dependencies (used by the season,
## the headless runner and the UI alike). Design: docs/design/赛事层设计.md.
##
## world = {"seed": int, "teams": [team...], "players": {pid: player}}
## team   = {"id": "t0", "name": "霓虹猎手", "short": "NH", "tier": 1..3, "col": Color, "players": [pid x3],
##           "runes": {hero_id: {rune_id: stacks}}, "human": bool}
## player = profile (game/profiles.gd format: name, attrs, prof, sig) + {"id", "team", "role", "age", "traits"}
const HeroesDB = preload("res://heroes_db.gd")
const Profiles = preload("res://game/profiles.gd")
const RunesDB = preload("res://game/runes_db.gd")

const ROLES := ["tank", "carry", "support"]
## league tiers: ability mean of the team's players (11 = average pro)
const TIER_MEAN := {1: 13.0, 2: 11.0, 3: 9.5}
const TIER_NAMES := {1: "豪门", 2: "中游", 3: "新军"}

const TEAM_NAMES := [["霓虹猎手", "NH"], ["极光", "AUR"], ["赤焰", "RF"], ["深空", "DS"], ["零点", "ZP"], ["雷霆", "THD"],
	["幻影", "PHM"], ["钢铁意志", "IW"], ["星环", "SR"], ["夜枭", "OWL"], ["狂澜", "TDL"], ["天穹", "SKY"]]
const TEAM_COLS := [Color(0.3, 0.9, 1.0), Color(0.6, 1.0, 0.6), Color(1.0, 0.45, 0.3), Color(0.55, 0.5, 1.0), Color(0.9, 0.9, 0.95),
	Color(1.0, 0.85, 0.3), Color(0.85, 0.5, 1.0), Color(0.7, 0.75, 0.8), Color(0.4, 0.7, 1.0), Color(0.75, 0.55, 0.35),
	Color(0.3, 0.6, 0.9), Color(0.5, 0.95, 0.95)]
## player handles: an ID like real esports names, mixing Chinese nicknames and latin tags
const NICK_A := ["阿", "小", "老", "大", "白", "黑", "夜", "风", "冷", "疾", "青", "火", "星", "月", "云", "雪"]
const NICK_B := ["星", "猫", "狼", "鹰", "刀", "风", "雨", "光", "影", "龙", "虎", "鱼", "羽", "弦", "石", "火", "辰", "川"]
const TAGS := ["Neo", "Ace", "Zed", "Kai", "Rex", "Vex", "Lux", "Nova", "Echo", "Jin", "Leo", "Sky", "Fox", "Ray", "Max",
	"Mint", "Rin", "Taro", "Yuki", "Bolt", "Ghost", "Dash", "Pixel", "Zero", "Volt", "Hex", "Kite", "Moss", "Jet", "Sol"]
const TRAITS := {"clutch": "残局之王", "big_stage": "大赛型", "slow_start": "慢热", "initiator": "开团手", "narrow_pool": "英雄池狭窄"}

## n_teams teams; team 0 is the human player's team (tier 3, the "网吧队" start of the story)
static func generate(seed: int, n_teams := 8, human := true) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var teams := []
	var players := {}
	var names_used := {}
	var order: Array = range(TEAM_NAMES.size())
	_shuffle(rng, order)
	for t in n_teams:
		var tier: int = 3 if (t == 0 and human) else int([1, 1, 2, 2, 2, 3, 3, 2, 1, 3, 2, 2][t % 12])
		var nm: Array = TEAM_NAMES[order[t]]
		var team := {"id": "t%d" % t, "name": str(nm[0]), "short": str(nm[1]), "tier": tier, "col": TEAM_COLS[order[t]],
			"players": [], "runes": {}, "human": human and t == 0}
		for r in ROLES:
			var p := _make_player(rng, team, r, names_used)
			players[p["id"]] = p
			team["players"].append(p["id"])
		team["runes"] = _rune_pages(rng, tier, team, players)
		teams.append(team)
	return {"seed": seed, "teams": teams, "players": players}

static func _make_player(rng: RandomNumberGenerator, team: Dictionary, role: String, used: Dictionary) -> Dictionary:
	var nm := ""
	for _i in 50:
		nm = (str(NICK_A[rng.randi() % NICK_A.size()]) + str(NICK_B[rng.randi() % NICK_B.size()])) if rng.randf() < 0.45 else str(TAGS[rng.randi() % TAGS.size()])
		if not used.has(nm):
			break
	used[nm] = true
	var p: Dictionary = Profiles.random(rng, nm, float(TIER_MEAN[int(team["tier"])]), 2.5)
	p["id"] = "%s_%s" % [team["id"], role]
	p["team"] = team["id"]
	p["role"] = role
	p["age"] = 17 + rng.randi() % 9
	# hero pool: every hero of the main role gets a proficiency, 1-2 signature heroes are mastered
	var own := []
	var other := []
	for id in HeroesDB.ORDER:
		(own if str(HeroesDB.HEROES[id]["role"]) == role else other).append(id)
	_shuffle(rng, own)
	var prof := {}
	var sig := {}
	var n_sig := 1 + (1 if rng.randf() < 0.4 else 0)
	for i in own.size():
		var hid: String = own[i]
		if i < n_sig:
			prof[hid] = 70 + rng.randi() % 30
			var abil := _sig_for(hid)
			if not abil.is_empty():
				sig[hid] = str(abil[rng.randi() % abil.size()])
			else:
				sig[hid] = ""
		else:
			prof[hid] = 20 + rng.randi() % 55
	# a hero or two outside the main role
	_shuffle(rng, other)
	for i in 2:
		prof[other[i]] = 5 + rng.randi() % 45
	p["prof"] = prof
	p["sig"] = sig
	var traits := []
	if rng.randf() < 0.35:
		var keys: Array = TRAITS.keys()
		traits.append(str(keys[rng.randi() % keys.size()]))
	p["traits"] = traits
	return p

## signature abilities defined for a hero (game/runes_db.gd SIGNATURES)
static func _sig_for(hid: String) -> Array:
	var out := []
	for k in RunesDB.SIGNATURES:
		if str(RunesDB.SIGNATURES[k]["hero"]) == hid:
			out.append(k)
	return out

## AI teams own a few rune pages for their players' signature heroes (stronger tiers own more)
static func _rune_pages(rng: RandomNumberGenerator, tier: int, team: Dictionary, players: Dictionary) -> Dictionary:
	var pages := {}
	var stacks: int = {1: 2, 2: 1, 3: 0}[tier]
	if stacks <= 0:
		return pages
	for pid in team["players"]:
		for hid in players[pid]["sig"]:
			pages[hid] = {"r_vital": stacks, "r_edge": stacks, "r_guard": stacks}
	return pages

static func _shuffle(rng: RandomNumberGenerator, a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t

static func team(world: Dictionary, tid: String) -> Dictionary:
	for t in world["teams"]:
		if str(t["id"]) == tid:
			return t
	return {}

static func team_players(world: Dictionary, tid: String) -> Array:
	var out := []
	for pid in team(world, tid)["players"]:
		out.append(world["players"][pid])
	return out

## mean ability of a player (6 attrs)
static func rating(p: Dictionary) -> float:
	var s := 0.0
	for k in Profiles.ATTRS:
		s += float(p["attrs"][k])
	return s / Profiles.ATTRS.size()
