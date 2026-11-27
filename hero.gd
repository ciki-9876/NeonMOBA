extends "res://unit.gd"
## A hero: attributes, levels, items, the virtual controller (3C: move / aim / fire / skills) and the attack state machine.
## Player input and the AI both drive heroes through the same controller (ctl_* + press()).

const ItemsDB = preload("res://items_db.gd")
const HeroesDB = preload("res://heroes_db.gd")
const Tune = preload("res://game/tuning.gd")
const PIXS := 3.0

enum C { IDLE, MOVE, ATTACK, AMOVE, HOLD, CAST }

var g
var hid := ""
var def: Dictionary = {}
var sdef: Dictionary = {}
var kit
var ai
var is_player := false
var god := false
var hp_mult := 1.0
var regen_bonus := 0.0

var level := 1
var xp := 0.0
var skill_points := 1
var sk := {"q": 0, "w": 0, "e": 0, "r": 0}
var cds := {"q": 0.0, "w": 0.0, "e": 0.0, "r": 0.0}
var mana := 0.0
var mana_max := 1.0
var ST := {}
var inv: Array = []
var gold := 600.0
var shard_owned := false
var arc_n := 0               # attacks counted toward the next item chain arc
var spell_shield_used := false   # 屏障发生器: once per round
var regen_buffs: Array = []
var haste_t := 0.0
var dd_t := 0.0
var ms_buff_t := 0.0
var ms_buff_pct := 0.0

var face := 0.0
var cmd := C.IDLE
var cmd_target = null
var cmd_pos := Vector2.ZERO
var cast_skill := ""
var cast_target = null
var cast_pos := Vector2.ZERO
var cast_t := -1.0
var atk_phase := 0
var atk_t := 0.0
var atk_ready := 0.0
var atk_target = null
var atk_total := 0.25
var atk_bs_total := 0.35
var recoil := 0.0
var vel := Vector2.ZERO
var dash := {}

var spr: Sprite2D
var trail: Line2D
var kills := 0
var deaths := 0
var assists := 0
var streak := 0
var respawn_t := 0.0
var dmg_log := {}
var hurt_cd := 0.0
var heal_done := 0.0
var last_hurt := -99.0
var revive_t := -1.0          # round mode: revive countdown (>= 0 while counting)
var revive_wait := false      # round mode: dead, revive not decided yet
var revive_ask_t := 0.0       # when the hero died (AI decision delay)
var engage_t := 0.0           # when the current fight started for this hero (TTK statistics)
## round mode: a losing team may sell one item at full price during the next buy phase
var refund_tokens := 0
## the player (选手) controlling this hero (game/profiles.gd); {} = none
var profile := {}
## stat bonuses from runes / signature abilities (same keys as item stats)
var mods_stats := {}
## measurement for the batch simulator (sim/sim_cli.gd): damage, skillshots, telegraph hits, ...
var stats := {}
var _prev_pos := Vector2.ZERO
var _path := PackedVector2Array()
var _path_goal := Vector2.INF
var _path_t := -99.0

# ============================================================ setup
func setup(game, id: String, tm: int, player: bool) -> void:
	g = game
	hid = id
	def = HeroesDB.HEROES[id]
	sdef = def["skills"]
	team = tm
	is_player = player
	is_hero = true
	radius = float(def["radius"]) * Tune.HERO_RADIUS_MULT
	base_col = def["col"]
	var ks: Script = load(str(def["kit"]))
	kit = ks.new()
	kit.setup(self, game)
	spr = Sprite2D.new()
	spr.texture = g.TEX[def["sprite"]]
	spr.hframes = 2
	spr.scale = Vector2(PIXS, PIXS) * Tune.HERO_RADIUS_MULT
	add_child(spr)
	trail = Line2D.new()
	trail.width = 10.0
	var wc := Curve.new()
	wc.add_point(Vector2(0, 0))
	wc.add_point(Vector2(1, 1))
	trail.width_curve = wc
	var tg := Gradient.new()
	var tc: Color = team_color()
	tg.set_color(0, Color(tc.r, tc.g, tc.b, 0.0))
	tg.set_color(1, Color(tc.r, tc.g, tc.b, 0.5))
	trail.gradient = tg
	reset_full()

func team_color() -> Color:
	if is_player:
		return Color(0.3, 1.8, 2.2)
	return Color(0.4, 2.0, 0.8) if team == 0 else Color(2.4, 0.4, 0.4)

func role() -> String:
	return str(def.get("role", "carry"))

func display_name() -> String:
	return str(def["short"])

func reset_full() -> void:
	level = 1
	xp = 0.0
	skill_points = 1
	sk = {"q": 0, "w": 0, "e": 0, "r": 0}
	if is_c3():
		sk["w"] = 1   # the right-click skill is never levelled: it is there from the start and scales with attributes
	cds = {"q": 0.0, "w": 0.0, "e": 0.0, "r": 0.0}
	inv = []
	gold = 600.0
	shard_owned = false
	regen_buffs = []
	kills = 0
	heal_done = 0.0
	deaths = 0
	assists = 0
	streak = 0
	dmg_log = {}
	ST = {}
	kit.reset()
	recalc()
	_reset_state()

func _reset_state() -> void:
	dead = false
	visible = true
	hp = max_hp
	mana = mana_max
	cmd = C.IDLE
	cmd_target = null
	atk_phase = 0
	atk_ready = 0.0
	cast_t = -1.0
	dash = {}
	stun = 0.0
	slow = 0.0
	silence = 0.0
	invuln = 0.0
	haste_t = 0.0
	dd_t = 0.0
	ms_buff_t = 0.0
	charged = 0.0
	mark = 0.0
	deso_t = 0.0
	knock = Vector2.ZERO
	pull = Vector2.ZERO
	buffs = {}
	barrier = 0.0
	barrier_t = 0.0
	recoil = 0.0
	arc_n = 0
	spell_shield_used = false
	if trail:
		trail.clear_points()

# ============================================================ stats
func hp_regen() -> float:
	var v: float = float(ST.get("hpr", 2.0)) + buff_v("regen")
	var ooc: float = float(sp().get("regen_ooc", 1.0))
	if ooc > 1.0 and g != null and g.t - last_hurt > 3.0:
		v *= ooc
	for b in regen_buffs:
		v += float(b.get("hp", 0.0))
	return v

func mp_regen() -> float:
	var v: float = float(ST.get("mpr", 1.0))
	for b in regen_buffs:
		v += float(b.get("mp", 0.0))
	return v

func atk_dmg() -> float:
	var base: float = float(ST.get("dmg_base", 50.0))
	return (base * (2.0 if dd_t > 0.0 else 1.0) + float(ST.get("dmg_bonus", 0.0))) * Tune.ATTACK_DAMAGE_MULT

func atk_base_display() -> float:
	return float(ST.get("dmg_base", 50.0)) * Tune.ATTACK_DAMAGE_MULT * (2.0 if dd_t > 0.0 else 1.0)

func atk_bonus_display() -> float:
	return float(ST.get("dmg_bonus", 0.0)) * Tune.ATTACK_DAMAGE_MULT

func atk_rate() -> float:
	return clampf(float(ST.get("as", 100.0)) + buff_v("as"), 20.0, 700.0) / 100.0 * Tune.ATTACK_SPEED_MULT

func as_bonus() -> float:
	return atk_rate() - 1.0

func atk_interval() -> float:
	return float(def["stats"]["interval"]) / atk_rate() * (1.0 + shiva_v)

func atk_range() -> float:
	return float(ST.get("range", def["range"]))

func move_speed() -> float:
	var ms: float = float(ST.get("ms", 300.0)) * Tune.MS_MULT
	if ms_buff_t > 0.0:
		ms *= 1.0 + ms_buff_pct
	ms *= 1.0 + buff_v("haste")
	var hh: Array = sp().get("hurt_haste", [])
	if not hh.is_empty() and g != null and g.t - last_hurt < float(hh[1]):
		ms *= 1.0 + float(hh[0])
	if haste_t > 0.0:
		ms = 550.0
	if slow > 0.0:
		ms *= 1.0 - slow_pct
	return minf(ms, 550.0)

## physical defense right now (buffs, 破甲 debuff)
func armor_val() -> float:
	var a: float = float(ST.get("def", 0.0)) + buff_v("def")
	if deso_t > 0.0:
		a -= deso_v
	return a - ac_v

## magic resist points right now
func mr_val() -> float:
	return float(ST.get("res", 0.0)) + buff_v("res")

func sp() -> Dictionary:
	return ST.get("sp", {})

func has_scepter() -> bool:
	for id in inv:
		if (ItemsDB.DB[id]["special"] as Dictionary).has("scepter"):
			return true
	return false

func sv(s: String, key: String) -> float:
	var lv: int = int(sk.get(s, 0))
	if lv <= 0 or not sdef.has(s):
		return 0.0
	var v = sdef[s].get(key, 0.0)
	if v is Array:
		var arr: Array = v
		return float(arr[mini(lv, arr.size()) - 1])
	return float(v)

func skill_cd(s: String) -> float:
	var c: float = sv(s, "cd") - float(kit.cd_reduction(s))
	return maxf(0.5, c * (1.0 - float(ST.get("cdr", 0.0))))

## fraction of damage that gets through x points of def / res: 100 / (100 + x); negative values amplify
func def_mult(x: float) -> float:
	return 100.0 / (100.0 + x) if x >= 0.0 else 2.0 - 100.0 / (100.0 - x)

## kept for old callers (team AI threat estimates): same curve as def_mult
func armor_mult(a: float) -> float:
	return def_mult(a)

## stat keys an item / rune may add (design: docs/design/属性与装备迭代设计案.md)
const STAT_KEYS := ["hp", "hpr", "mana", "mpr", "atk", "as", "def", "res", "ms", "range", "pspd", "vision", "ls", "pow", "cdr"]
## old rune keys still accepted
const STAT_ALIAS := {"dmg": "atk", "armor": "def", "amp": "pow", "mr": "res"}

## Fixed hero panel (def["stats"]) + items + runes + passives. Levels only give skill points.
func recalc() -> void:
	_sync_skill_mods()
	var hp_frac := 1.0
	var mp_frac := 1.0
	if ST.has("hp_max"):
		hp_frac = clampf(hp / max_hp, 0.0, 1.0)
		mp_frac = clampf(mana / mana_max, 0.0, 1.0)
	var b := {}
	for k in STAT_KEYS:
		b[k] = 0.0
	var cdr_keep := 1.0
	var spx := {"crit": [0.0, 1.0], "arc": [], "pierce": 0, "armor_break": [], "grievous": [], "charge_fast": 0.0,
		"tenacity": 0.0, "spell_shield": 0.0, "regen_ooc": 1.0, "charge_move": 1.0, "hurt_haste": [], "far_bonus": 0.0,
		"heal_amp": 0.0, "as_aura": [], "heart": 0.0, "low_ls": 0.0, "spell_vamp": 0.0, "scepter": false}
	for k0 in mods_stats:
		var k: String = STAT_ALIAS.get(k0, k0)
		if k == "cdr":
			cdr_keep *= 1.0 - float(mods_stats[k0]) / 100.0
		elif b.has(k):
			b[k] += float(mods_stats[k0])
	for id in inv:
		var it: Dictionary = ItemsDB.DB[id]
		var stv: Dictionary = it["stats"]
		for k in stv:
			if k == "cdr":
				cdr_keep *= 1.0 - float(stv[k]) / 100.0
			elif b.has(k):
				b[k] += float(stv[k])
		var spc: Dictionary = it["special"]
		for k in spc:
			match k:
				"crit":
					if float(spc[k][1]) > float(spx["crit"][1]): spx["crit"] = spc[k]
				"arc":
					if spx["arc"].is_empty() or int(spc[k][1]) > int(spx["arc"][1]): spx["arc"] = spc[k]
				"armor_break", "grievous", "hurt_haste", "as_aura":
					if spx[k].is_empty() or float(spc[k][0]) > float(spx[k][0]): spx[k] = spc[k]
				"pierce": spx["pierce"] = maxi(int(spx["pierce"]), int(spc[k]))
				"regen_ooc": spx["regen_ooc"] = maxf(float(spx["regen_ooc"]), float(spc[k]))
				"charge_move": spx["charge_move"] = minf(float(spx["charge_move"]), float(spc[k]))
				"scepter": spx["scepter"] = true
				"shard": pass
				_:
					if spx.has(k): spx[k] = maxf(float(spx[k]), float(spc[k]))
	var base: Dictionary = def["stats"]
	var melee: bool = bool(def["melee"])
	var n := {}
	n["dmg_base"] = float(base["atk"])
	n["dmg_bonus"] = b["atk"]
	n["as"] = 100.0 + b["as"]        # percent of the hero's own attack rate (100 = base interval)
	n["def"] = float(base["def"]) + b["def"]
	n["res"] = float(base["res"]) + b["res"]
	n["ms"] = float(base["ms"]) + b["ms"]
	n["hp_max"] = (float(base["hp"]) + b["hp"]) * hp_mult
	n["mana_max"] = float(base["mana"]) + b["mana"]
	n["hpr"] = float(base["hpr"]) + regen_bonus + b["hpr"]
	n["mpr"] = float(base["mpr"]) + b["mpr"]
	n["ls"] = b["ls"] / 100.0
	n["pow"] = b["pow"] / 100.0
	n["cdr"] = 1.0 - cdr_keep
	# melee heroes get half of any attack range bonus (it widens the swing radius)
	n["range"] = float(def["range"]) + b["range"] * (0.5 if melee else 1.0)
	n["pspd"] = float(def.get("proj_speed", 1100.0)) + b["pspd"]
	n["vision"] = float(def.get("vision", 900.0)) + b["vision"]
	n["arc"] = float(def.get("arc", 0.0)) + (20.0 if melee and int(spx["pierce"]) > 0 else 0.0)
	n["sp"] = spx
	kit.stat_mods(n)
	n["hpr"] = float(n["hpr"]) + float(n["hp_max"]) * float(spx["heart"]) / 100.0
	n["as"] = clampf(float(n["as"]), 20.0, 700.0)
	n["ms"] = minf(550.0, float(n["ms"]))
	ST = n
	max_hp = float(n["hp_max"])
	mana_max = float(n["mana_max"])
	hp = max_hp * hp_frac
	mana = mana_max * mp_frac

func tenacity() -> float:
	return float(sp().get("tenacity", 0.0))

## outgoing skill heals and shields: skill power and 支援信标
func support_mult() -> float:
	return pow_mult() * (1.0 + float(sp().get("heal_amp", 0.0)))

## skill power multiplier for skill damage, heals and shields
func pow_mult() -> float:
	return 1.0 + float(ST.get("pow", 0.0))

# ============================================================ levels & skills
func xp_need() -> float:
	return 60.0 + 30.0 * level + 2.0 * level * level

func gain_xp(v: float) -> void:
	if level >= 25 or dead:
		return
	xp += v
	while xp >= xp_need() and level < 25:
		xp -= xp_need()
		level += 1
		skill_points += 1
		recalc()
		g.on_level_up(self)

## heroes rebuilt for the 3C scheme (right-click signature skill in slot "w")
func is_c3() -> bool:
	return bool(def.get("c3", false))

func can_learn(s: String) -> bool:
	if skill_points <= 0:
		return false
	if s == "w" and is_c3():
		return false
	var lv: int = int(sk[s])
	var mx: int = int(sdef[s]["max"])
	if s == "r":
		return lv < mx and level >= [6, 12, 18][lv]
	return lv < mx and lv < int((level + 1) / 2)

func learn(s: String) -> bool:
	if not can_learn(s):
		return false
	skill_points -= 1
	sk[s] = int(sk[s]) + 1
	recalc()
	return true

func cast_error(s: String, tgt) -> String:
	var st: Dictionary = sdef[s]
	if st["type"] == "passive":
		return "%s是被动技能" % st["name"]
	if int(sk[s]) <= 0:
		return "技能尚未学习"
	if silence > 0.0:
		return "你被沉默了！"
	if has_buff("taunt"):
		return "被嘲讽了！"
	if float(cds[s]) > 0.0:
		return "技能冷却中"
	if mana < sv(s, "mana"):
		return "魔法不足"
	if st["type"] == "unit" and not is_foe(tgt):
		return "需要选择一个对方单位"
	if st["type"] == "unit" and not g.has_los(position, tgt.position):
		return "被地形挡住了"
	if st["type"] == "ally" and not is_ally(tgt):
		return "需要选择一个友方英雄"
	return str(kit.check(s, tgt))

func is_foe(u) -> bool:
	return u != null and is_instance_valid(u) and u.team != team and u.targetable() and g.visible_to(u, team)

func is_ally(u) -> bool:
	return u != null and is_instance_valid(u) and u.team == team and not u.dead and bool(u.is_hero)

func taunter():
	if not has_buff("taunt"):
		return null
	var s = buff_src("taunt")
	return s if is_foe(s) else null

func valid(u) -> bool:
	return u != null and is_instance_valid(u) and not u.dead

# ============================================================ control (3C: WASD + mouse aim)
## Every hero — player or AI — is driven through this virtual controller, written before each step:
##   ctl_move  movement direction (length <= 1)          ctl_aim   world point the hero aims at
##   ctl_fire  basic attack held                         ctl_hold  right-click (skill "w") held
## press(s) asks for a skill toward ctl_aim. A skill with a "charge" block (normally the right-click)
## starts charging on press and fires when ctl_hold is released.
var ctl_move := Vector2.ZERO
var ctl_aim := Vector2.ZERO
var ctl_fire := false
var ctl_hold := false
var charging := ""
var charge := 0.0

func busy() -> bool:
	return dead or not dash.is_empty() or bool(kit.busy()) or has_buff("banish")

func casting() -> bool:
	return cast_t >= 0.0

func interrupt() -> void:
	atk_phase = 0
	cast_t = -1.0
	charging = ""
	charge = 0.0
	cmd = C.IDLE

## ally skills lock on the ally closest to the aim point (self when none in range);
## legacy unit skills lock on the visible foe closest to the aim point
func soft_target(s: String):
	var typ: String = sdef[s]["type"]
	var cr: float = float(kit.cast_range(s, null))
	if cr <= 0.0:
		cr = 99999.0
	var best = null
	var bd := 1e9
	if typ == "ally":
		for u in g.heroes:
			if is_ally(u) and position.distance_to(u.position) <= cr + float(u.radius):
				var dd: float = u.position.distance_to(ctl_aim)
				if dd < bd:
					bd = dd
					best = u
		return best if best != null else self
	if typ == "unit":
		for u in g.seen_foes(team, position, cr + 40.0):
			if bool(u.is_hero) and g.has_los(position, u.position):
				var dd2: float = u.position.distance_to(ctl_aim)
				if dd2 < bd:
					bd = dd2
					best = u
	return best

func press(s: String) -> String:
	if not sdef.has(s):
		return ""
	if busy() or stun > 0.0:
		return "无法行动"
	if casting() or charging != "":
		return "正在施法"
	var st: Dictionary = sdef[s]
	var tgt = soft_target(s)
	var err := cast_error(s, tgt)
	if err != "":
		return err
	atk_phase = 0
	if st.has("charge"):
		charging = s
		charge = 0.0
		return ""
	cast_skill = s
	cast_target = tgt
	cast_t = float(st.get("cast_point", 0.15))
	cmd = C.CAST
	return ""

func charge_cfg() -> Dictionary:
	return sdef[charging].get("charge", {}) if charging != "" else {}

## target point of a cast: the aim, pulled in to the cast range for ground-targeted skills
func cast_pos_for(s: String, aim: Vector2) -> Vector2:
	var cr: float = float(kit.cast_range(s, null))
	if cr > 0.0 and position.distance_to(aim) > cr:
		return position + (aim - position).normalized() * cr
	return aim

func _finish_cast(s: String, tgt, aim: Vector2, chg: float) -> void:
	cmd = C.IDLE
	if s == "":
		return
	var typ: String = sdef[s]["type"]
	var unit_cast: bool = typ in ["ally", "unit"]
	if cast_error(s, tgt if unit_cast else null) != "":
		return
	var tpos := cast_pos_for(s, aim)
	if unit_cast and tgt != null and is_instance_valid(tgt):
		tpos = tgt.position
	mana -= sv(s, "mana")
	cds[s] = skill_cd(s)
	g.reveal(self)
	kit.cast(s, tgt if unit_cast else null, tpos, chg)
	kit.on_cast(s)
	g.on_hero_cast(self, s)

func _update_charge(d: float) -> void:
	if charging == "":
		return
	if silence > 0.0:
		charging = ""
		charge = 0.0
		return
	var cfg := charge_cfg()
	charge = minf(1.0, charge + d / maxf(0.05, float(cfg.get("time", 1.0)) * (1.0 - float(sp().get("charge_fast", 0.0)))))
	if not ctl_hold:
		var s := charging
		var c := charge
		charging = ""
		charge = 0.0
		if c >= float(cfg.get("min", 0.15)):
			_finish_cast(s, soft_target(s), ctl_aim, c)

func _control(d: float) -> void:
	var tt = taunter()
	var aim: Vector2 = tt.position if tt != null else ctl_aim
	var to := aim - position
	if to.length() > 2.0:
		face = to.angle()
	if cast_t >= 0.0:
		cast_t -= d
		if cast_t < 0.0:
			cast_t = -1.0
			_finish_cast(cast_skill, cast_target, aim, 0.0)
		return
	_update_charge(d)
	var mv: Vector2 = ctl_move.limit_length(1.0)
	if tt != null:
		mv = Vector2.ZERO if to.length() < atk_range() * 0.8 + float(tt.radius) else to.normalized()
	if mv.length() > 0.01 and not has_buff("root"):
		var spd := move_speed()
		if charging != "":
			spd *= 1.0 - (1.0 - float(charge_cfg().get("move", 0.5))) * float(sp().get("charge_move", 1.0))
		position = g.clamp_pos(position + mv * spd * d, radius)
	var want: bool = tt != null or (ctl_fire and charging == "")
	_update_attack(d, aim, want)

func _update_attack(d: float, aim: Vector2, want: bool) -> void:
	match atk_phase:
		0:
			if want and atk_ready <= 0.0:
				atk_phase = 1
				atk_t = float(def["atk_point"]) / (1.0 + as_bonus())
				atk_total = atk_t
		1:
			atk_t -= d
			if atk_t <= 0.0:
				_fire_attack(aim)
				atk_phase = 2
				atk_t = float(def["backswing"]) / (1.0 + as_bonus())
				atk_bs_total = atk_t
				atk_ready = atk_interval()
		2:
			atk_t -= d
			if atk_t <= 0.0:
				atk_phase = 0

## melee: radius of the swing arc (= attack range) and its full angle in radians
func melee_reach() -> float:
	return atk_range()

func melee_arc() -> float:
	return deg_to_rad(float(ST.get("arc", def.get("arc", 100.0))))

func proj_speed() -> float:
	return float(ST.get("pspd", def.get("proj_speed", 1100.0))) * Tune.BOLT_SPEED_MULT

## perception radius (AI) and camera height (player)
func vision() -> float:
	return float(ST.get("vision", def.get("vision", 900.0)))

## ranged basic attacks fly up to 1.5x the attack range
func bolt_reach() -> float:
	return atk_range() * 1.5

func _fire_attack(_aim: Vector2) -> void:
	recoil = 7.0
	g.reveal(self)
	var info := {"proc": false, "bonus": 0.0, "ls": 0.0}
	kit.on_attack_fire(null, info)
	var dmg: float = atk_dmg() * g.rng.randf_range(0.95, 1.05)
	var dir := Vector2.from_angle(face)
	stat_add("atk_fired")
	if bool(def["melee"]):
		var hits: Array = g.foes_in_arc(team, position, dir, melee_reach(), melee_arc())
		var hit_hero := false
		for u in hits:
			attack_hit(u, dmg, info)
			if bool(u.is_hero):
				hit_hero = true
		if hit_hero:
			stat_add("atk_hit")
		g.swing_fx(self, dir, bool(info.get("proc", false)) or float(info["bonus"]) > 0.0)
	else:
		g.spawn_bolt(self, position + dir * (radius + 8.0), dir, dmg, info)

func attack_hit(tgt, base: float, info: Dictionary) -> void:
	if not valid(tgt):
		return
	var spx := sp()
	var dmg: float = base + float(info.get("bonus", 0.0))
	if bool(info.get("far", false)):
		dmg *= 1.0 + float(spx.get("far_bonus", 0.0))
	var kind := "attack"
	var crit: Array = spx.get("crit", [0.0, 1.0])
	if float(crit[0]) > 0.0 and g.rng.randf() < float(crit[0]):
		dmg *= float(crit[1])
		kind = "crit"
	var dir: Vector2 = (tgt.position - position).normalized()
	var dealt: float = g.damage(self, tgt, dmg, kind, "phys", dir * 0.3, true)
	if dealt <= 0.0:
		return
	var ls: float = float(ST.get("ls", 0.0)) + float(info.get("ls", 0.0))
	if ls > 0.0 and hp < max_hp * float(spx.get("low_ls", 0.0)):
		ls *= 2.0   # 嗜血狂刃
	if ls > 0.0:
		g.heal(null, self, dealt * ls)
	var ab: Array = spx.get("armor_break", [])
	if not tgt.dead and not ab.is_empty():
		tgt.deso_t = float(ab[1])
		tgt.deso_v = float(ab[0])
	# 超载线圈 / 风暴核心: every Nth attack (one count per swing or bolt) releases a chain arc
	var arc: Array = spx.get("arc", [])
	if not arc.is_empty() and not info.has("arc_counted"):
		info["arc_counted"] = true
		arc_n += 1
		if arc_n >= int(arc[0]):
			arc_n = 0
			g.item_chain(self, tgt, int(arc[1]), float(arc[2]))
	kit.on_attack_hit(tgt, info)

## next point to walk toward on the way to p: straight when the line is clear, otherwise the path
func steer_point(p: Vector2) -> Vector2:
	if g.terrain == null or not g.terrain.seg_blocked(position, p, radius):
		_path = PackedVector2Array()
		return p
	if _path.is_empty() or _path_goal.distance_to(p) > 48.0 or g.t - _path_t > 0.8:
		_path = g.terrain.path(position, p, radius + 2.0)
		_path_goal = p
		_path_t = g.t
	while _path.size() > 1 and (position.distance_to(_path[0]) < 14.0 or not g.terrain.seg_blocked(position, _path[1], radius)):
		_path.remove_at(0)
	return _path[0] if not _path.is_empty() else p

# ============================================================ update
func update(d: float) -> void:
	if dead:
		for s in cds:   # cooldowns keep running while dead: a revive does not refresh them
			cds[s] = maxf(0.0, float(cds[s]) - d)
		return
	_prev_pos = position
	tick_status(d)
	hp = minf(max_hp, hp + hp_regen() * d)
	mana = minf(mana_max, mana + mp_regen() * d)
	for s in cds:
		cds[s] = maxf(0.0, float(cds[s]) - d)
	haste_t = maxf(0.0, haste_t - d)
	dd_t = maxf(0.0, dd_t - d)
	ms_buff_t = maxf(0.0, ms_buff_t - d)
	atk_ready = maxf(0.0, atk_ready - d)
	hurt_cd -= d
	var keep_b := []
	for bf in regen_buffs:
		bf["t"] = float(bf["t"]) - d
		if float(bf["t"]) > 0.0:
			keep_b.append(bf)
	regen_buffs = keep_b
	if knock != Vector2.ZERO or pull != Vector2.ZERO:
		position = g.clamp_pos(position + (knock + pull) * d, radius)
		knock = knock.move_toward(Vector2.ZERO, 1200.0 * d)
		pull = Vector2.ZERO
	kit.tick(d)
	if dead:
		return
	if not dash.is_empty():
		_do_dash(d)
	elif kit.busy():
		pass
	elif stun > 0.0 or has_buff("banish"):
		interrupt()
	else:
		_control(d)
	vel = (position - _prev_pos) / maxf(d, 0.0001)
	_visuals(d)

func cast_point_total() -> float:
	return float(sdef[cast_skill].get("cast_point", 0.15)) if cast_skill != "" else 0.15

# ============================================================ dash (used by kits)
func start_dash(to: Vector2, speed: float, cb: Callable) -> void:
	var dest: Vector2 = g.clamp_pos(to, radius)
	if g.terrain != null:
		dest = g.terrain.sweep(position, dest, radius)   # dashes stop at walls and pillars
	dash = {"to": dest, "speed": speed, "cb": cb}
	atk_phase = 0
	cast_t = -1.0
	cmd = C.IDLE

func _do_dash(d: float) -> void:
	var to: Vector2 = dash["to"]
	var dv := to - position
	var step: float = float(dash["speed"]) * d
	if dv.length() > 1.0:
		face = dv.angle()
	if dv.length() <= step:
		position = to
		var cb: Callable = dash["cb"]
		dash = {}
		if cb.is_valid():
			cb.call()
	else:
		position += dv.normalized() * step

# ============================================================ life & death
func die() -> void:
	buffs = {}
	barrier = 0.0
	dead = true
	visible = false
	interrupt()
	dash = {}
	trail.clear_points()

func respawn(p: Vector2) -> void:
	position = p
	_reset_state()
	kit.reset()

func log_damage(src) -> void:
	if src != null and is_instance_valid(src) and src.is_hero and src.team != team:
		dmg_log[src.get_instance_id()] = [src, g.t]

# ============================================================ visuals
func _visuals(d: float) -> void:
	spr.rotation = face
	var fdir := Vector2.from_angle(face)
	var glow := 0.0
	if atk_phase == 1:
		glow = clampf(1.0 - atk_t / maxf(atk_total, 0.01), 0.0, 1.0)
	elif cast_t > 0.0:
		glow = clampf(1.0 - cast_t / maxf(cast_point_total(), 0.01), 0.0, 1.0)
	elif charging != "":
		glow = charge
	recoil = move_toward(recoil, 0.0, 40.0 * d)
	spr.position = -fdir * (glow * 4.0 + recoil)
	var base := Color(1.5, 1.5, 1.5)
	if not is_player and team == 1:
		base = Color(1.9, 1.1, 1.1)
	var col: Color = base.lerp(Color(2.2, 2.7, 2.9), glow)
	if flash > 0.0:
		col = Color(2.6, 2.6, 2.6)
	if invuln > 0.0:
		col = Color(2.6, 1.0, 1.2, 0.55)
	if stun > 0.0:
		col = col * Color(0.7, 0.7, 0.8)
	spr.modulate = col
	spr.frame = int(Engine.get_process_frames() / 4 + get_instance_id()) % 2
	trail.add_point(position - fdir * 14.0)
	while trail.get_point_count() > 14:
		trail.remove_point(0)

# ============================================================ runes & signature abilities
## apply rune / signature mods (format: game/runes_db.gd). Call once, right after setup().
func apply_mods(mods: Array) -> void:
	if mods.is_empty() and rune_mods.is_empty():
		return
	rune_mods = mods.duplicate()
	mods_stats = {}
	for m in mods:
		if str(m["type"]) == "stat":
			mods_stats[m["key"]] = float(mods_stats.get(m["key"], 0.0)) + float(m["v"])
	_upg_state = "?"
	recalc()

## hero upgrades (特化芯片 -> def["shard"], 终极协议 -> def["scepter"]) use the same mod format as runes.
## sdef = the shared HeroesDB skills, patched by rune mods and owned upgrades (rebuilt when they change)
var rune_mods: Array = []
var _upg_state := ""

func _sync_skill_mods() -> void:
	var state := "%s%s" % [shard_owned, has_scepter()]
	if state == _upg_state:
		return
	_upg_state = state
	var mods: Array = rune_mods.duplicate()
	if shard_owned:
		mods.append_array(def.get("shard", []))
	if has_scepter():
		mods.append_array(def.get("scepter", []))
	sdef = def["skills"]
	var touched := false
	for m in mods:
		var ty := str(m["type"])
		if ty == "stat":
			continue
		if not touched:
			sdef = sdef.duplicate(true)   # never patch the shared HeroesDB definition
			touched = true
		match ty:
			"skill":
				var st: Dictionary = sdef[m["skill"]]
				if m.has("op"):
					_patch_effects(st.get("effects", []), str(m["op"]), str(m["key"]), m)
				elif st.has(m["key"]):
					st[m["key"]] = _patch_value(st[m["key"]], m)
			"append":
				var st2: Dictionary = sdef[m["skill"]]
				if st2.has("effects"):
					st2["effects"].append((m["effect"] as Dictionary).duplicate(true))
	if "_meta_cache" in kit:
		kit._meta_cache = {}

func _patch_effects(effects: Array, op: String, key: String, m: Dictionary) -> void:
	for e in effects:
		if str(e.get("do", "")) == op and e.has(key):
			e[key] = _patch_value(e[key], m)
		for sub in ["then", "each"]:
			if e.has(sub):
				_patch_effects(e[sub], op, key, m)

func _patch_value(v, m: Dictionary):
	if v is Dictionary:
		var dct: Dictionary = (v as Dictionary).duplicate(true)
		dct["v"] = _patch_value(dct.get("v", 0.0), m)
		return dct
	if v is Array:
		var out := []
		for x in v:
			out.append(_patch_value(x, m))
		return out
	var f := float(v)
	if m.has("mul"):
		f *= float(m["mul"])
	if m.has("add"):
		f += float(m["add"])
	return f

func stat_add(key: String, v := 1.0) -> void:
	stats[key] = float(stats.get(key, 0.0)) + v

