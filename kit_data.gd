extends "res://kit_base.gd"
## Data-driven kit — the "skill effect assembly" system.
## A hero using this kit has NO hero-specific code: every skill is a list of effect blocks in
## heroes_db.gd, assembled from a small vocabulary. The same data also drives:
##   * the AI   (ai_meta() infers roles / aim / radius / damage / healing from the effects)
##   * tooltips (tip() writes the description from the effects)
##
## Effect block: {"do": <op>, "on": <selector>, ...params}. Any numeric param may be a per-level array.
## Selectors (on):  target | self | enemies | allies | line | all_allies      (+ "at": pos|self|target, "r": radius)
## Ops:
##   damage {amt, amt_hp (fraction of caster max hp), dtype: magic|phys|pure}
##   heal {amt, pct (of target max hp)}            barrier {amt, amt_hp, dur}
##   stun {dur}  root {dur}  slow {pct, dur}  silence {dur}  taunt {dur}  banish {dur}  cleanse {strong}
##   buff {id: haste|as|armor|dr|regen, v, dur}    status {id: mark|charged, dur}
##   dash {to: target|pos, speed, max, then:[...]}           pull {to: caster|pos, speed}
##   shot {speed, len, w, col, pierce, then:[...]}  (skillshot; "then" runs on each unit hit)
##   delay {t, r, col, then:[...]}                 zone {dur, tick, r, col, at, follow, each:[...]}
##   fx {kind: ring|burst, at, r, col}              sfx {name, pitch, vol}      shake {v}
## Passive skill: "passive": {dr, regen, armor, as, ms, aura: {id, v, r}}

var shots: Array = []
var zones: Array = []
var aura_t := 0.0
var _meta_cache := {}

func reset() -> void:
	aura_t = 0.0

func round_reset() -> void:
	reset()
	shots.clear()
	zones.clear()

func threats() -> Array:
	var out := []
	# only telegraphs and projectiles: lingering zones are not "dodgeable" (fleeing them abandons the objective)
	for z in zones:
		if z["kind"] == "delay":
			out.append({"kind": "area", "pos": z["pos"], "r": float(z["r"]), "t": float(z["dur"]) - float(z["t"])})
	for sh in shots:
		out.append({"kind": "shot", "pos": sh["pos"], "dir": sh["dir"], "w": float(sh["w"]), "speed": float(sh["speed"]), "left": float(sh["left"])})
	return out

# ------------------------------------------------------------ values
func val(p, lv: int) -> float:
	if p == null:
		return 0.0
	if p is Array:
		var a: Array = p
		if a.is_empty():
			return 0.0
		return float(a[clampi(lv, 1, a.size()) - 1])
	return float(p)

func _col(e: Dictionary) -> Color:
	var c = e.get("col", null)
	return c if c is Color else Color(h.def["col"])

# ------------------------------------------------------------ hero hooks
func cast_range(s: String, _tgt) -> float:
	var r: float = val(h.sdef[s].get("range", 0.0), maxi(1, int(h.sk[s])))
	return r + float(h.ST.get("cast", 0.0)) if r > 0.0 else 0.0

func skill_radius(s: String) -> float:
	var m := ai_meta(s)
	return float(m.get("radius", 0.0))

func stat_mods(n: Dictionary) -> void:
	for s in ["q", "w", "e", "r"]:
		var st: Dictionary = h.sdef[s]
		if not st.has("passive") or int(h.sk[s]) <= 0:
			continue
		var p: Dictionary = st["passive"]
		var lv: int = int(h.sk[s])
		if p.has("armor"): n["armor"] = float(n["armor"]) + val(p["armor"], lv)
		if p.has("regen"): n["hpr"] = float(n["hpr"]) + val(p["regen"], lv)
		if p.has("as"): n["as"] = float(n["as"]) + val(p["as"], lv)
		if p.has("ms"): n["ms"] = float(n["ms"]) + val(p["ms"], lv)

func tick(d: float) -> void:
	aura_t -= d
	if aura_t > 0.0:
		return
	aura_t = 0.4
	for s in ["q", "w", "e", "r"]:
		var st: Dictionary = h.sdef[s]
		if not st.has("passive") or int(h.sk[s]) <= 0:
			continue
		var p: Dictionary = st["passive"]
		var lv: int = int(h.sk[s])
		if p.has("dr"):
			h.add_buff("dr", 0.6, val(p["dr"], lv))
		if p.has("aura"):
			var a: Dictionary = p["aura"]
			for u in g.allies_in(h.team, h.position, float(a.get("r", 700.0))):
				u.add_buff(str(a["id"]), 0.6, val(a["v"], lv))

func cast(s: String, tgt, pos: Vector2) -> void:
	var dir: Vector2 = (pos - h.position).normalized()
	if tgt != null and is_instance_valid(tgt) and tgt != h:
		dir = (tgt.position - h.position).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.from_angle(h.face)
	var ctx := {"s": s, "lv": int(h.sk[s]), "target": tgt, "pos": pos, "dir": dir, "origin": h.position}
	run(h.sdef[s].get("effects", []), ctx)

# ------------------------------------------------------------ effect interpreter
func run(effects: Array, ctx: Dictionary) -> void:
	for e in effects:
		_do(e, ctx)

func _center(e: Dictionary, ctx: Dictionary) -> Vector2:
	match str(e.get("at", "pos")):
		"self": return h.position
		"target":
			var t = ctx["target"]
			if t != null and is_instance_valid(t):
				return t.position
	return ctx["pos"]

func _units(e: Dictionary, ctx: Dictionary) -> Array:
	var lv: int = ctx["lv"]
	match str(e.get("on", "target")):
		"self":
			return [h] if not h.dead else []
		"target":
			var t = ctx["target"]
			if t != null and is_instance_valid(t) and not t.dead:
				return [t]
			return []
		"enemies":
			return g.foes_in(h.team, _center(e, ctx), val(e.get("r", 200.0), lv))
		"allies":
			return g.allies_in(h.team, _center(e, ctx), val(e.get("r", 200.0), lv))
		"all_allies":
			return g.allies_in(h.team, h.position, val(e.get("r", 99999.0), lv))
		"line":
			var out := []
			var a: Vector2 = ctx["origin"]
			var dir: Vector2 = ctx["dir"]
			var ln: float = val(e.get("len", 800.0), lv)
			var w: float = val(e.get("w", 80.0), lv)
			for u in g.foes_all(h.team):
				var rel: Vector2 = u.position - a
				var tp: float = clampf(rel.dot(dir), 0.0, ln)
				if (rel - dir * tp).length() < w / 2.0 + float(u.radius):
					out.append(u)
			return out
	return []

func _do(e: Dictionary, ctx: Dictionary) -> void:
	var lv: int = ctx["lv"]
	var op: String = str(e["do"])
	match op:
		"damage":
			var amt: float = val(e.get("amt", 0.0), lv) + val(e.get("amt_hp", 0.0), lv) * h.max_hp
			for u in _units(e, ctx):
				if u.team != h.team:
					if bool(ctx.get("tele", false)) and u.is_hero:
						u.stat_add("tele_taken")
						h.stat_add("tele_hit")
					g.damage(h, u, amt, str(e.get("kind", "skill")), str(e.get("dtype", "magic")), Vector2.ZERO)
		"heal":
			for u in _units(e, ctx):
				if u.team == h.team:
					g.heal(h, u, val(e.get("amt", 0.0), lv) + val(e.get("pct", 0.0), lv) * float(u.max_hp))
		"barrier":
			for u in _units(e, ctx):
				u.add_barrier(val(e.get("amt", 0.0), lv) + val(e.get("amt_hp", 0.0), lv) * h.max_hp, val(e.get("dur", 4.0), lv))
		"stun":
			for u in _units(e, ctx):
				if u.team != h.team:
					u.stun = maxf(float(u.stun), val(e["dur"], lv) * (0.3 if bool(u.boss) else 1.0))
		"root":
			for u in _units(e, ctx):
				if u.team != h.team:
					u.add_buff("root", val(e["dur"], lv))
		"slow":
			for u in _units(e, ctx):
				if u.team != h.team:
					u.slow = maxf(float(u.slow), val(e["dur"], lv))
					u.slow_pct = val(e.get("pct", 0.3), lv)
		"silence":
			for u in _units(e, ctx):
				if u.team != h.team:
					u.silence = maxf(float(u.silence), val(e["dur"], lv))
		"taunt":
			for u in _units(e, ctx):
				if u.team != h.team and not bool(u.boss):
					u.add_buff("taunt", val(e["dur"], lv), 0.0, h)
		"banish":
			for u in _units(e, ctx):
				var bd: float = val(e["dur"], lv)
				u.add_buff("banish", bd)
				u.invuln = maxf(float(u.invuln), bd)
				u.stun = 0.0
		"cleanse":
			for u in _units(e, ctx):
				if u.team == h.team:
					u.cleanse(bool(e.get("strong", false)))
		"buff":
			for u in _units(e, ctx):
				u.add_buff(str(e["id"]), val(e["dur"], lv), val(e.get("v", 0.0), lv))
		"status":
			for u in _units(e, ctx):
				u.set(str(e["id"]), val(e["dur"], lv))
		"dash":
			var dest: Vector2 = ctx["pos"]
			var t = ctx["target"]
			if str(e.get("to", "pos")) == "target" and t != null and is_instance_valid(t):
				var dv: Vector2 = (t.position - h.position).normalized()
				dest = t.position - dv * (float(t.radius) + h.radius + 6.0)
			var mx: float = val(e.get("max", 0.0), lv)
			if mx > 0.0:
				dest = h.position + (dest - h.position).limit_length(mx)
			var c2 := ctx.duplicate()
			g.ghost(h, h.position, Color(h.def["col"]) * Color(1, 1, 1, 0.6))
			h.start_dash(dest, val(e.get("speed", 1800.0), lv), _after_dash.bind(e.get("then", []), c2))
		"pull":
			var to_caster: bool = str(e.get("to", "caster")) == "caster"
			var cpos: Vector2 = h.position if to_caster else _center(e, ctx)
			for u in _units(e, ctx):
				if u.team == h.team or bool(u.boss):
					continue
				var away: Vector2 = (u.position - cpos).normalized()
				if away == Vector2.ZERO:
					away = Vector2.RIGHT
				var gap: float = (h.radius + float(u.radius) + 8.0) if to_caster else float(u.radius) * 0.6
				g.displace(u, cpos + away * gap, val(e.get("speed", 1600.0), lv))
		"shot":
			h.stat_add("shot_fired")
			shots.append({"pos": ctx["origin"], "dir": ctx["dir"], "speed": val(e.get("speed", 1400.0), lv),
				"left": val(e.get("len", 900.0), lv), "w": val(e.get("w", 60.0), lv), "col": _col(e),
				"pierce": bool(e.get("pierce", false)), "then": e.get("then", []), "ctx": ctx.duplicate(), "hit": {}, "trail": []})
		"delay":
			zones.append({"kind": "delay", "pos": _center(e, ctx), "r": val(e.get("r", 200.0), lv), "t": 0.0,
				"dur": val(e.get("t", 0.6), lv), "col": _col(e), "then": e.get("then", []), "ctx": ctx.duplicate()})
		"zone":
			var fol = h if bool(e.get("follow", false)) else null
			zones.append({"kind": "zone", "pos": _center(e, ctx), "r": val(e.get("r", 200.0), lv), "t": 0.0,
				"dur": val(e.get("dur", 3.0), lv), "tick": val(e.get("tick", 0.5), lv), "acc": 0.0, "follow": fol,
				"col": _col(e), "each": e.get("each", []), "ctx": ctx.duplicate()})
		"fx":
			var p := _center(e, ctx)
			var col := _col(e)
			if str(e.get("kind", "ring")) == "ring":
				g._ring(p, 10.0, val(e.get("r", 200.0), lv), 0.45, col, 10.0)
			else:
				g._burst(p, col, 24, val(e.get("r", 300.0), lv), 0.5, 3.0)
		"sfx":
			g.sfx(str(e["name"]), float(e.get("pitch", 1.0)), float(e.get("vol", -2.0)))
		"shake":
			g.add_shake(float(e.get("v", 6.0)), h)

func _after_dash(effects: Array, ctx: Dictionary) -> void:
	ctx["pos"] = h.position
	ctx["origin"] = h.position
	run(effects, ctx)
	var t = ctx["target"]
	if h.is_foe(t):
		h.order_attack(t)

# ------------------------------------------------------------ lingering things (run even when the hero is dead)
func tick_world(d: float) -> void:
	if not shots.is_empty():
		var keep := []
		for sh in shots:
			var step: float = float(sh["speed"]) * d
			var p0: Vector2 = sh["pos"]
			var dir: Vector2 = sh["dir"]
			var done := false
			var n: int = maxi(1, int(ceil(step / 30.0)))
			for k in n:
				var p: Vector2 = p0 + dir * step * float(k + 1) / float(n)
				if g.blocked_at(p):
					done = true
					break
				for u in g.foes_in(h.team, p, float(sh["w"]) / 2.0):
					if sh["hit"].has(u):
						continue
					sh["hit"][u] = true
					if u.is_hero:
						if sh["hit"].size() == 1:
							h.stat_add("shot_hit")
						u.stat_add("shot_taken")
					var c2: Dictionary = sh["ctx"].duplicate()
					c2["target"] = u
					c2["pos"] = u.position
					run(sh["then"], c2)
					if not bool(sh["pierce"]):
						done = true
						break
				if done:
					break
			sh["pos"] = p0 + dir * step
			sh["left"] = float(sh["left"]) - step
			var tr: Array = sh["trail"]
			tr.append(sh["pos"])
			if tr.size() > 8:
				tr.pop_front()
			if not done and float(sh["left"]) > 0.0:
				keep.append(sh)
		shots = keep
	if not zones.is_empty():
		var keepz := []
		for z in zones:
			z["t"] = float(z["t"]) + d
			if z["kind"] == "delay":
				if float(z["t"]) >= float(z["dur"]):
					var c3: Dictionary = z["ctx"].duplicate()
					c3["pos"] = z["pos"]
					c3["tele"] = true
					run(z["then"], c3)
				else:
					keepz.append(z)
			else:
				var fol = z["follow"]
				if fol != null and is_instance_valid(fol) and not fol.dead:
					z["pos"] = fol.position
				z["acc"] = float(z["acc"]) + d
				if float(z["acc"]) >= float(z["tick"]):
					z["acc"] = float(z["acc"]) - float(z["tick"])
					var c4: Dictionary = z["ctx"].duplicate()
					c4["pos"] = z["pos"]
					run(z["each"], c4)
				if float(z["t"]) < float(z["dur"]):
					keepz.append(z)
		zones = keepz

func draw(o: Node2D) -> void:
	var tick := Time.get_ticks_msec() * 0.001
	for z in zones:
		var p: Vector2 = z["pos"]
		var r: float = z["r"]
		var c: Color = z["col"]
		var k: float = clampf(float(z["t"]) / maxf(float(z["dur"]), 0.01), 0.0, 1.0)
		if z["kind"] == "delay":
			o.draw_circle(p, r, Color(c.r, c.g, c.b, 0.1))
			o.draw_circle(p, r * k, Color(c.r, c.g, c.b, 0.2))
			o.draw_arc(p, r, 0, TAU, 64, Color(c.r, c.g, c.b, 0.9), 2.5)
		else:
			o.draw_circle(p, r, Color(c.r, c.g, c.b, 0.08))
			o.draw_arc(p, r, tick * 1.5, tick * 1.5 + TAU, 64, Color(c.r, c.g, c.b, 0.6 * (1.0 - k * 0.5)), 2.5)
	for sh in shots:
		var c: Color = sh["col"]
		var tr: Array = sh["trail"]
		if tr.size() >= 2:
			o.draw_polyline(PackedVector2Array(tr), Color(c.r, c.g, c.b, 0.5), float(sh["w"]) * 0.4)
		o.draw_circle(sh["pos"], float(sh["w"]) * 0.35, c)
		o.draw_circle(sh["pos"], float(sh["w"]) * 0.18, Color(3, 3, 3))

# ------------------------------------------------------------ AI metadata inferred from the effects
func _walk(effects: Array, acc: Dictionary, lv: int, mult: float) -> void:
	for e in effects:
		var op: String = str(e["do"])
		var on: String = str(e.get("on", "target"))
		var foe_side: bool = on in ["target", "enemies", "line"] and not (op in ["heal", "barrier", "cleanse", "buff", "banish"])
		var ally_side: bool = on in ["allies", "all_allies", "self"] or (on == "target" and op in ["heal", "barrier", "cleanse", "buff", "banish"])
		if on in ["enemies", "allies", "all_allies"]:
			acc["radius"] = maxf(float(acc["radius"]), val(e.get("r", 200.0), lv))
			acc["at"] = str(e.get("at", "pos"))
		match op:
			"damage":
				if foe_side:
					acc["dmg"] = float(acc["dmg"]) + (val(e.get("amt", 0.0), lv) + val(e.get("amt_hp", 0.0), lv) * h.max_hp) * mult
					acc["roles"]["nuke"] = true
			"heal":
				acc["heal"] = float(acc["heal"]) + (val(e.get("amt", 0.0), lv) + val(e.get("pct", 0.0), lv) * h.max_hp) * mult
				acc["roles"]["heal"] = true
			"barrier", "banish":
				if ally_side or on == "target":
					acc["roles"]["save"] = true
				if op == "barrier":
					acc["heal"] = float(acc["heal"]) + (val(e.get("amt", 0.0), lv) + val(e.get("amt_hp", 0.0), lv) * h.max_hp) * 0.8 * mult
			"stun", "root", "taunt":
				if foe_side:
					acc["roles"]["disable"] = true
			"slow", "silence":
				if foe_side:
					acc["roles"]["soft"] = true
			"buff":
				if str(e["id"]) in ["as", "haste", "armor", "dr"]:
					acc["roles"]["buff_ally" if on == "target" or on == "allies" else "buff_self"] = true
			"dash":
				acc["roles"]["gap_close"] = true
				if str(e.get("to", "pos")) == "pos":
					acc["roles"]["escape"] = true
			"pull":
				acc["roles"]["disable"] = true
			"shot":
				acc["skillshot"] = true
				acc["reach"] = maxf(float(acc["reach"]), val(e.get("len", 900.0), lv))
		for key in ["then"]:
			if e.has(key):
				_walk(e[key], acc, lv, mult)
		if e.has("each"):
			var ticks: float = val(e.get("dur", 3.0), lv) / maxf(val(e.get("tick", 0.5), lv), 0.05)
			_walk(e["each"], acc, lv, mult * ticks)

func ai_meta(s: String) -> Dictionary:
	var st: Dictionary = h.sdef[s]
	var lv: int = maxi(1, int(h.sk[s]))
	var key := "%s%d%d" % [s, lv, int(h.max_hp / 200.0)]
	if _meta_cache.has(key):
		return _meta_cache[key]
	var m := {}
	if st["type"] == "passive" or not st.has("effects"):
		m = st.get("ai", {})
		_meta_cache[key] = m
		return m
	var acc := {"roles": {}, "dmg": 0.0, "heal": 0.0, "radius": 0.0, "at": "pos", "skillshot": false, "reach": 0.0}
	_walk(st["effects"], acc, lv, 1.0)
	var roles: Array = acc["roles"].keys()
	if roles.has("nuke") and float(acc["radius"]) > 0.0 and not roles.has("heal"):
		roles.append("aoe")
	var typ: String = st["type"]
	var aim := "target"
	match typ:
		"unit": aim = "unit"
		"ally": aim = "ally"
		"unit_or_point": aim = "unit"
		"no_target": aim = "self"
		"point":
			aim = "target" if bool(acc["skillshot"]) or float(acc["radius"]) <= 0.0 else "cluster"
	if typ == "no_target" and (roles.has("heal") or roles.has("save")):
		aim = "self"
		roles.erase("save")
		if not roles.has("heal"):
			roles.append("heal")
		roles.append("team_heal")
	m = {"roles": roles, "aim": aim, "radius": float(acc["radius"]), "est_dmg": float(acc["dmg"]),
		"est_heal": float(acc["heal"]), "reach": maxf(float(acc["reach"]), cast_range(s, null))}
	var over: Dictionary = st.get("ai", {})
	for k in over:
		m[k] = over[k]
	if s == "r" and not m.has("ult"):
		m["ult"] = true
	if bool(m.get("ult", false)) and not roles.has("ult"):
		roles.append("ult")
	_meta_cache[key] = m
	return m

func est_damage(s: String) -> float:
	return float(ai_meta(s).get("est_dmg", 0.0))

func est_heal(s: String) -> float:
	return float(ai_meta(s).get("est_heal", 0.0))

# ------------------------------------------------------------ auto-generated tooltip
const BUFF_NAMES := {"haste": "移速", "as": "攻速", "armor": "护甲", "dr": "伤害减免", "regen": "生命回复"}

func _vals(p) -> String:
	if p is Array:
		var parts := []
		for x in p:
			parts.append(_n(float(x)))
		return "/".join(PackedStringArray(parts))
	return _n(float(p))

func _pct(p) -> String:
	if p is Array:
		var parts := []
		for x in p:
			parts.append(_n(float(x) * 100.0))
		return "/".join(PackedStringArray(parts)) + "%"
	return _n(float(p) * 100.0) + "%"

func _n(v: float) -> String:
	return str(int(round(v))) if absf(v - roundf(v)) < 0.05 else ("%.1f" % v)

func _who(e: Dictionary) -> String:
	match str(e.get("on", "target")):
		"self": return "自身"
		"target": return "目标"
		"enemies": return "%s范围内的对手" % _vals(e.get("r", 200))
		"allies": return "%s范围内的友方" % _vals(e.get("r", 200))
		"all_allies": return "所有友方英雄"
		"line": return "直线上的对手"
	return ""

func _desc(effects: Array) -> String:
	var parts := []
	for e in effects:
		var w := _who(e)
		match str(e["do"]):
			"damage":
				var extra := (" + 自身最大生命 %s" % _pct(e["amt_hp"])) if e.has("amt_hp") else ""
				parts.append("对%s造成 %s%s %s伤害" % [w, _vals(e.get("amt", 0)), extra, {"magic": "魔法", "phys": "物理", "pure": "纯粹"}[str(e.get("dtype", "magic"))]])
			"heal":
				var hp := _vals(e.get("amt", 0)) if e.has("amt") else ""
				if e.has("pct"):
					hp += ("+" if hp != "" else "") + "%s 最大生命" % _pct(e["pct"])
				parts.append("为%s恢复 %s 生命" % [w, hp])
			"barrier": parts.append("给%s %s 点护盾（%s 秒）" % [w, _vals(e.get("amt", 0)) + ((" + 施法者最大生命 %s" % _pct(e["amt_hp"])) if e.has("amt_hp") else ""), _vals(e.get("dur", 4))])
			"stun": parts.append("晕眩%s %s 秒" % [w, _vals(e["dur"])])
			"root": parts.append("缠绕%s %s 秒" % [w, _vals(e["dur"])])
			"slow": parts.append("使%s减速 %s，持续 %s 秒" % [w, _pct(e.get("pct", 0.3)), _vals(e["dur"])])
			"silence": parts.append("沉默%s %s 秒" % [w, _vals(e["dur"])])
			"taunt": parts.append("嘲讽%s %s 秒（强制攻击你）" % [w, _vals(e["dur"])])
			"banish": parts.append("使%s进入星界 %s 秒（无法行动、不受任何伤害）" % [w, _vals(e["dur"])])
			"cleanse": parts.append("驱散%s的负面效果%s" % [w, "（包括晕眩）" if bool(e.get("strong", false)) else ""])
			"buff":
				var bid: String = str(e["id"])
				var bv = e.get("v", 0)
				parts.append("%s%s +%s，持续 %s 秒" % [w, BUFF_NAMES.get(bid, bid), _pct(bv) if bid in ["haste", "dr"] else _vals(bv), _vals(e["dur"])])
			"dash": parts.append("冲向目标%s" % ("，然后" + _desc(e.get("then", [])) if not e.get("then", []).is_empty() else ""))
			"pull": parts.append("把%s拉向%s" % [w, "自己" if str(e.get("to", "caster")) == "caster" else "中心"])
			"shot": parts.append("射出长度 %s 的弹道，命中%s时：%s" % [_vals(e.get("len", 900)), "每个对手" if bool(e.get("pierce", false)) else "第一个对手", _desc(e.get("then", []))])
			"delay": parts.append("%s 秒后在半径 %s 的区域内：%s" % [_vals(e.get("t", 0.6)), _vals(e.get("r", 200)), _desc(e.get("then", []))])
			"zone": parts.append("产生持续 %s 秒的领域，每 %s 秒：%s" % [_vals(e.get("dur", 3)), _vals(e.get("tick", 0.5)), _desc(e.get("each", []))])
	return "，".join(PackedStringArray(parts))

func tip(s: String) -> String:
	var tips: Dictionary = h.def.get("tips", {})
	if tips.has(s):
		return str(tips[s])
	var st: Dictionary = h.sdef[s]
	var typ_name: String = {"passive": "被动", "no_target": "主动·无目标", "point": "主动·地点", "unit": "主动·对方单位",
		"ally": "主动·友方英雄", "unit_or_point": "主动·单位或地点"}[st["type"]]
	var head := "%s %s（%s%s）\n" % [s.to_upper(), st["name"], typ_name, "，6/12/18 级可学" if s == "r" else ""]
	if st.has("note"):
		head += str(st["note"]) + "\n"
	var body := ""
	if st.has("effects"):
		body = _desc(st["effects"]) + "。"
	if st.has("passive"):
		var p: Dictionary = st["passive"]
		var bits := []
		if p.has("dr"): bits.append("受到的伤害 -%s" % _pct(p["dr"]))
		if p.has("armor"): bits.append("护甲 +%s" % _vals(p["armor"]))
		if p.has("regen"): bits.append("生命回复 +%s" % _vals(p["regen"]))
		if p.has("as"): bits.append("攻速 +%s" % _vals(p["as"]))
		if p.has("aura"):
			var a: Dictionary = p["aura"]
			bits.append("光环：%s 范围内的友方%s +%s" % [_n(float(a.get("r", 700))), BUFF_NAMES.get(str(a["id"]), str(a["id"])), _vals(a["v"])])
		body += "，".join(PackedStringArray(bits)) + "。"
	var tail := ""
	if st.has("mana"):
		tail = "\n魔法 %s  冷却 %s" % [_vals(st["mana"]), _vals(st["cd"])]
	if float(val(st.get("range", 0.0), 1)) > 0.0:
		tail += "  施法距离 %s" % _vals(st["range"])
	return head + body + tail
