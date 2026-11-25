extends "res://unit.gd"
## A hero: attributes, levels, items, orders, the DOTA-style attack state machine.
## Player input and the AI both drive heroes through the same order_* API.

const ItemsDB = preload("res://items_db.gd")
const HeroesDB = preload("res://heroes_db.gd")
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
var sk := {"q": 0, "w": 0, "e": 0, "r": 0, "attr": 0}
var cds := {"q": 0.0, "w": 0.0, "e": 0.0, "r": 0.0}
var mana := 0.0
var mana_max := 1.0
var ST := {}
var inv: Array = []
var gold := 600.0
var moon_used := false
var shard_owned := false
var regen_buffs: Array = []
var radiance_t := 0.0
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
## round mode: a losing team may sell one item at full price during the next buy phase
var refund_tokens := 0
## the player (选手) controlling this hero (game/profiles.gd); {} = none
var profile := {}
## stat bonuses from runes / signature abilities (same keys as item stats)
var mods_stats := {}
## measurement for the batch simulator (sim/sim_cli.gd): damage, skillshots, telegraph hits, ...
var stats := {}
var _prev_pos := Vector2.ZERO

# ============================================================ setup
func setup(game, id: String, tm: int, player: bool) -> void:
	g = game
	hid = id
	def = HeroesDB.HEROES[id]
	sdef = def["skills"]
	team = tm
	is_player = player
	is_hero = true
	radius = float(def["radius"])
	base_col = def["col"]
	var ks: Script = load(str(def["kit"]))
	kit = ks.new()
	kit.setup(self, game)
	spr = Sprite2D.new()
	spr.texture = g.TEX[def["sprite"]]
	spr.hframes = 2
	spr.scale = Vector2(PIXS, PIXS)
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
	sk = {"q": 0, "w": 0, "e": 0, "r": 0, "attr": 0}
	cds = {"q": 0.0, "w": 0.0, "e": 0.0, "r": 0.0}
	inv = []
	gold = 600.0
	moon_used = false
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
	if trail:
		trail.clear_points()

# ============================================================ stats
func hp_regen() -> float:
	var v: float = float(ST.get("hpr", 2.0)) + buff_v("regen")
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
	return base * (2.0 if dd_t > 0.0 else 1.0) + float(ST.get("dmg_bonus", 0.0))

func atk_rate() -> float:
	return clampf(float(ST.get("as", 100.0)) + buff_v("as"), 20.0, 700.0) / 100.0

func as_bonus() -> float:
	return atk_rate() - 1.0

func atk_interval() -> float:
	return float(def["bat"]) / atk_rate() * (1.0 + shiva_v)

func atk_range() -> float:
	return float(ST.get("range", def["range"]))

func move_speed() -> float:
	var ms: float = float(ST.get("ms", 300.0))
	if ms_buff_t > 0.0:
		ms *= 1.0 + ms_buff_pct
	ms *= 1.0 + buff_v("haste")
	if haste_t > 0.0:
		ms = 550.0
	if slow > 0.0:
		ms *= 1.0 - slow_pct
	return minf(ms, 550.0)

func armor_val() -> float:
	var a: float = float(ST.get("armor", 0.0)) + buff_v("armor")
	if deso_t > 0.0:
		a -= deso_v
	return a - ac_v

func mr_val() -> float:
	return float(ST.get("mr", 0.25))

func sp() -> Dictionary:
	return ST.get("sp", {})

func has_scepter() -> bool:
	return bool(sp().get("scepter", false))

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

func armor_mult(a: float) -> float:
	return 1.0 - (0.06 * a) / (1.0 + 0.06 * absf(a))

func recalc() -> void:
	var hp_frac := 1.0
	var mp_frac := 1.0
	if ST.has("hp_max"):
		hp_frac = clampf(hp / max_hp, 0.0, 1.0)
		mp_frac = clampf(mana / mana_max, 0.0, 1.0)
	var b := {"str": 0.0, "agi": 0.0, "int": 0.0, "dmg": 0.0, "as": 0.0, "armor": 0.0, "ms": 0.0, "ms_pct": 0.0,
		"hp": 0.0, "mana": 0.0, "hpr": 0.0, "mpr": 0.0, "ls": 0.0, "amp": 0.0, "cast": 0.0, "range": 0.0}
	var mr_keep := 1.0
	var eva_keep := 1.0
	var cdr_keep := 1.0
	var spx := {"crit": [0.0, 1.0], "chain": [], "deso": 0.0, "skadi": [], "mkb": [], "radiance": [], "ac_aura": 0.0, "shiva": 0.0, "scepter": false, "heart": 0.0}
	for k in mods_stats:
		if k == "cdr":
			cdr_keep *= 1.0 - float(mods_stats[k]) / 100.0
		elif b.has(k):
			b[k] += float(mods_stats[k])
	for id in inv:
		var it: Dictionary = ItemsDB.DB[id]
		var stv: Dictionary = it["stats"]
		for k in stv:
			var v := float(stv[k])
			match k:
				"all":
					b["str"] += v
					b["agi"] += v
					b["int"] += v
				"mr": mr_keep *= 1.0 - v / 100.0
				"eva": eva_keep *= 1.0 - v / 100.0
				"cdr": cdr_keep *= 1.0 - v / 100.0
				_: b[k] += v
		var spc: Dictionary = it["special"]
		for k in spc:
			match k:
				"crit":
					if spc[k][1] > spx["crit"][1]: spx["crit"] = spc[k]
				"chain":
					if spx["chain"].is_empty() or spc[k][2] > spx["chain"][2]: spx["chain"] = spc[k]
				"deso": spx["deso"] = maxf(spx["deso"], spc[k])
				"skadi": spx["skadi"] = spc[k]
				"mkb": spx["mkb"] = spc[k]
				"radiance": spx["radiance"] = spc[k]
				"ac_aura": spx["ac_aura"] = maxf(spx["ac_aura"], spc[k])
				"shiva": spx["shiva"] = maxf(spx["shiva"], spc[k])
				"scepter": spx["scepter"] = true
				"heart": spx["heart"] = maxf(spx["heart"], spc[k])
	var base: Dictionary = def["base"]
	var gain: Dictionary = def["gain"]
	var lv := float(level - 1)
	var bs := 2.0 * float(sk["attr"])
	var n := {}
	for a in ["str", "agi", "int"]:
		var bv: float = float(base[a]) + float(gain[a]) * lv
		n[a + "_base"] = bv
		n[a] = bv + bs + float(b[a])
	var STR: float = n["str"]
	var AGI: float = n["agi"]
	var INT: float = n["int"]
	var prim: String = def["primary"]
	n["dmg_base"] = float(def["base_dmg"]) + float(n[prim])
	n["dmg_bonus"] = b["dmg"]
	n["as"] = 100.0 + AGI + b["as"] + (60.0 if moon_used else 0.0)
	n["armor"] = float(def["armor"]) + AGI / 6.0 + b["armor"]
	n["mr"] = 1.0 - (1.0 - 0.25) * (1.0 - INT * 0.001) * mr_keep
	n["ms"] = (float(def["ms"]) + b["ms"]) * (1.0 + b["ms_pct"] / 100.0)
	n["hp_max"] = (200.0 + STR * 22.0 + b["hp"]) * hp_mult
	n["mana_max"] = 75.0 + INT * 12.0 + b["mana"]
	n["hpr"] = 1.0 + regen_bonus + STR * 0.1 + b["hpr"] + n["hp_max"] * spx["heart"] / 100.0
	n["mpr"] = 0.5 + INT * 0.05 + b["mpr"]
	n["ls"] = b["ls"] / 100.0
	n["eva"] = 1.0 - eva_keep
	n["amp"] = b["amp"] / 100.0
	n["cdr"] = 1.0 - cdr_keep
	n["cast"] = b["cast"]
	n["range"] = float(def["range"]) + (0.0 if bool(def["melee"]) else b["range"])
	n["sp"] = spx
	kit.stat_mods(n)
	n["as"] = clampf(float(n["as"]), 20.0, 700.0)
	n["ms"] = minf(550.0, float(n["ms"]))
	ST = n
	max_hp = float(n["hp_max"])
	mana_max = float(n["mana_max"])
	hp = max_hp * hp_frac
	mana = mana_max * mp_frac

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

func can_learn(s: String) -> bool:
	if skill_points <= 0:
		return false
	if s == "attr":
		return int(sk["attr"]) < 10
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
	if st["type"] == "ally" and not is_ally(tgt):
		return "需要选择一个友方英雄"
	return str(kit.check(s, tgt))

func is_foe(u) -> bool:
	return u != null and is_instance_valid(u) and u.team != team and u.targetable()

func is_ally(u) -> bool:
	return u != null and is_instance_valid(u) and u.team == team and not u.dead and bool(u.is_hero)

func taunter():
	if not has_buff("taunt"):
		return null
	var s = buff_src("taunt")
	return s if is_foe(s) else null

func valid(u) -> bool:
	return u != null and is_instance_valid(u) and not u.dead

# ============================================================ orders
func busy() -> bool:
	return dead or not dash.is_empty() or bool(kit.busy()) or has_buff("taunt") or has_buff("banish")

func _cancel() -> void:
	atk_phase = 0
	cast_t = -1.0

func order_move(p: Vector2) -> void:
	if busy(): return
	if cmd == C.MOVE:
		cmd_pos = p
		return
	_cancel()
	cmd = C.MOVE
	cmd_pos = p
	cmd_target = null

func order_attack(u) -> void:
	if busy() or not is_foe(u): return
	if cmd == C.ATTACK and cmd_target == u:
		return
	if atk_phase == 1 and atk_target == u:
		# already winding up an attack on this unit (e.g. from attack-move): keep it
		cmd = C.ATTACK
		cmd_target = u
		return
	_cancel()
	cmd = C.ATTACK
	cmd_target = u

func order_amove(p: Vector2) -> void:
	if busy(): return
	if cmd == C.AMOVE:
		cmd_pos = p
		return
	if atk_phase == 1:
		# attack-move keeps the attack that is winding up (it would re-acquire a target anyway)
		cmd = C.AMOVE
		cmd_pos = p
		return
	_cancel()
	cmd = C.AMOVE
	cmd_pos = p

func order_hold() -> void:
	if busy(): return
	_cancel()
	cmd = C.HOLD

func order_stop() -> void:
	if busy(): return
	_cancel()
	cmd = C.IDLE

func order_cast(s: String, tgt, p: Vector2) -> String:
	if busy():
		return "无法行动"
	var typ: String = sdef[s]["type"]
	if typ == "unit_or_point" and not is_foe(tgt):
		tgt = null
	if typ == "ally" and not is_ally(tgt):
		tgt = self
	var err := cast_error(s, tgt)
	if err != "":
		return err
	_cancel()
	cmd = C.CAST
	cast_skill = s
	cast_target = tgt
	cast_pos = p
	cast_t = -1.0
	return ""

# ============================================================ update
func update(d: float) -> void:
	if dead:
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
	var rad: Array = sp().get("radiance", [])
	if not rad.is_empty():
		radiance_t -= d
		if radiance_t <= 0.0:
			radiance_t = 1.0
			for u in g.foes_in(team, position, float(rad[1])):
				g.damage(self, u, float(rad[0]), "dot", "magic")
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
		atk_phase = 0
		cast_t = -1.0
	elif taunter() != null:
		var tt = taunter()
		if cmd != C.ATTACK or cmd_target != tt:
			_cancel()
			cmd = C.ATTACK
			cmd_target = tt
		_update_attack(d)
		_attack_logic(tt, d, true)
	else:
		_update_attack(d)
		_update_cmd(d)
	vel = (position - _prev_pos) / maxf(d, 0.0001)
	_visuals(d)

func _update_attack(d: float) -> void:
	if atk_phase == 1:
		if not is_foe(atk_target):
			atk_phase = 0
		else:
			_turn_to((atk_target.position - position).angle(), d)
			atk_t -= d
			if atk_t <= 0.0:
				_fire_attack(atk_target)
				atk_phase = 2
				atk_t = float(def["backswing"]) / (1.0 + as_bonus())
				atk_bs_total = atk_t
				atk_ready = atk_interval()
	elif atk_phase == 2:
		atk_t -= d
		if atk_t <= 0.0:
			atk_phase = 0

func _update_cmd(d: float) -> void:
	match cmd:
		C.MOVE:
			if atk_phase == 0 and _move_to(cmd_pos, d):
				cmd = C.IDLE
		C.ATTACK:
			if not is_foe(cmd_target):
				cmd = C.IDLE
			else:
				_attack_logic(cmd_target, d, true)
		C.AMOVE:
			var tgt = g.nearest_foe(team, position, atk_range() + 160.0)
			if tgt != null:
				_attack_logic(tgt, d, true)
			elif atk_phase == 0 and _move_to(cmd_pos, d):
				cmd = C.IDLE
		C.HOLD:
			var tgt2 = g.nearest_foe(team, position, atk_range())
			if tgt2 != null:
				_attack_logic(tgt2, d, false)
		C.IDLE:
			var tgt3 = g.nearest_foe(team, position, atk_range() + (0.0 if is_player else 200.0))
			if tgt3 != null:
				_attack_logic(tgt3, d, not is_player)
		C.CAST:
			_cast_logic(d)

func _turn_to(ang: float, d: float) -> bool:
	face = rotate_toward(face, ang, float(def["turn"]) * d)
	return absf(angle_difference(face, ang)) < 0.2

func _move_to(p: Vector2, d: float) -> bool:
	var to := p - position
	if has_buff("root"):
		_turn_to(to.angle(), d)
		return false
	if to.length() < 8.0:
		return true
	var ok := _turn_to(to.angle(), d)
	if ok or absf(angle_difference(face, to.angle())) < 0.5:
		var step := to.normalized() * minf(move_speed() * d, to.length())
		var np: Vector2 = g.clamp_pos(position + step, radius)
		if np.distance_to(position) < 0.01 and step.length() > 0.5:
			return true
		position = np
	return false

func _attack_logic(tgt, d: float, chase: bool) -> void:
	if atk_phase != 0:
		return
	var dist: float = position.distance_to(tgt.position) - float(tgt.radius)
	if dist > atk_range():
		if chase:
			_move_to(tgt.position, d)
		return
	if _turn_to((tgt.position - position).angle(), d) and atk_ready <= 0.0:
		atk_phase = 1
		atk_t = float(def["atk_point"]) / (1.0 + as_bonus())
		atk_total = atk_t
		atk_target = tgt

func _fire_attack(tgt) -> void:
	recoil = 7.0
	var info := {"proc": false, "bonus": 0.0, "ls": 0.0}
	kit.on_attack_fire(tgt, info)
	var dmg: float = atk_dmg() * g.rng.randf_range(0.95, 1.05)
	if bool(def["melee"]):
		if position.distance_to(tgt.position) - float(tgt.radius) <= atk_range() + 350.0:
			attack_hit(tgt, dmg, info)
		g.slash_fx(self, tgt, bool(info.get("proc", false)) or float(info["bonus"]) > 0.0)
	else:
		g.spawn_hero_shot(self, tgt, dmg, info)

func attack_hit(tgt, base: float, info: Dictionary) -> void:
	if not valid(tgt):
		return
	var spx := sp()
	var dmg: float = base + float(info.get("bonus", 0.0))
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
	if ls > 0.0:
		hp = minf(max_hp, hp + dealt * ls)
	if not tgt.dead:
		if float(spx.get("deso", 0.0)) > 0.0:
			tgt.deso_t = 7.0
			tgt.deso_v = float(spx["deso"])
		var skd: Array = spx.get("skadi", [])
		if not skd.is_empty():
			tgt.slow = maxf(tgt.slow, float(skd[1]))
			tgt.slow_pct = float(skd[0])
		var mkb: Array = spx.get("mkb", [])
		if not mkb.is_empty() and g.rng.randf() < float(mkb[0]):
			g.damage(self, tgt, float(mkb[1]), "proc", "magic")
	var ch: Array = spx.get("chain", [])
	if not ch.is_empty() and g.rng.randf() < float(ch[0]):
		g.item_chain(self, tgt, int(ch[1]), float(ch[2]))
	kit.on_attack_hit(tgt, info)

func _cast_logic(d: float) -> void:
	var s := cast_skill
	if cast_error(s, cast_target) != "":
		cmd = C.IDLE
		return
	var typ: String = sdef[s]["type"]
	var tpos := cast_pos
	var unit_cast: bool = typ == "unit" or typ == "ally" or (typ == "unit_or_point" and cast_target != null)
	if unit_cast:
		var ok: bool = is_ally(cast_target) if typ == "ally" else is_foe(cast_target)
		if not ok:
			cmd = C.IDLE
			return
		tpos = cast_target.position
	if typ != "no_target":
		var cr: float = float(kit.cast_range(s, cast_target if unit_cast else null))
		var slack: float = float(cast_target.radius) if unit_cast else 0.0
		if cr > 0.0 and position.distance_to(tpos) > cr + slack:
			_move_to(tpos, d)
			cast_t = -1.0
			return
		var ang := (tpos - position).angle()
		if cast_t < 0.0:
			if position.distance_to(tpos) < 4.0 or _turn_to(ang, d):
				cast_t = float(sdef[s].get("cast_point", 0.25))
			return
		_turn_to(ang, d)
	elif cast_t < 0.0:
		cast_t = float(sdef[s].get("cast_point", 0.0))
	cast_t -= d
	if cast_t > 0.0:
		return
	cast_t = -1.0
	mana -= sv(s, "mana")
	cds[s] = skill_cd(s)
	cmd = C.IDLE
	kit.cast(s, cast_target if unit_cast else null, tpos)
	kit.on_cast(s)
	g.on_hero_cast(self, s)

func cast_point_total() -> float:
	return float(sdef[cast_skill].get("cast_point", 0.25)) if cast_skill != "" else 0.25

# ============================================================ dash (used by kits)
func start_dash(to: Vector2, speed: float, cb: Callable) -> void:
	dash = {"to": g.clamp_pos(to, radius), "speed": speed, "cb": cb}
	atk_phase = 0
	cast_t = -1.0

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
	atk_phase = 0
	cmd = C.IDLE
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
	var charge := 0.0
	if atk_phase == 1:
		charge = clampf(1.0 - atk_t / maxf(atk_total, 0.01), 0.0, 1.0)
	elif cmd == C.CAST and cast_t > 0.0:
		charge = clampf(1.0 - cast_t / maxf(cast_point_total(), 0.01), 0.0, 1.0)
	recoil = move_toward(recoil, 0.0, 40.0 * d)
	spr.position = -fdir * (charge * 4.0 + recoil)
	var base := Color(1.5, 1.5, 1.5)
	if not is_player and team == 1:
		base = Color(1.9, 1.1, 1.1)
	var col: Color = base.lerp(Color(2.2, 2.7, 2.9), charge)
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
	if mods.is_empty():
		return
	sdef = sdef.duplicate(true)   # never patch the shared HeroesDB definition
	for m in mods:
		match str(m["type"]):
			"stat":
				mods_stats[m["key"]] = float(mods_stats.get(m["key"], 0.0)) + float(m["v"])
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
	recalc()

func _patch_effects(effects: Array, op: String, key: String, m: Dictionary) -> void:
	for e in effects:
		if str(e.get("do", "")) == op and e.has(key):
			e[key] = _patch_value(e[key], m)
		for sub in ["then", "each"]:
			if e.has(sub):
				_patch_effects(e[sub], op, key, m)

func _patch_value(v, m: Dictionary):
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

