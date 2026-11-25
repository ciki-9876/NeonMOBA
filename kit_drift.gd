extends "res://kit_base.gd"
## 霓虹漂移者 (3C) — 右键 脉冲射线（蓄力）/ Q 相位闪烁 / E 超载 / R 奇点
## Slot keys: "w" = right-click beam (never levelled, scales with agility and charge), "q" = blink.

var attack_count := 0
var empowered := false
var sings: Array = []

func reset() -> void:
	attack_count = 0
	empowered = false

func round_reset() -> void:
	reset()
	sings.clear()

func stat_mods(n: Dictionary) -> void:
	if int(h.sk["e"]) > 0:
		n["as"] = float(n["as"]) + h.sv("e", "as")

func cd_reduction(s: String) -> float:
	return 20.0 if s == "r" and h.has_scepter() else 0.0

func cast_range(s: String, _tgt) -> float:
	if s == "r":
		return float(h.sdef["r"]["range"]) + float(h.ST.get("cast", 0.0))
	return 0.0

func skill_radius(s: String) -> float:
	if s == "r":
		return r_radius()
	return float(h.sdef[s].get("radius", 0.0))

func r_radius() -> float:
	return float(h.sdef["r"]["radius"]) + (100.0 if h.has_scepter() else 0.0)

func blink_dist() -> float:
	return h.sv("q", "dist") + float(h.ST.get("cast", 0.0))

func est_damage(s: String) -> float:
	match s:
		"w": return sval("w", "dmg", 1.0)
		"q": return h.sv("q", "nova") + h.sv("q", "det")
		"r": return h.sv("r", "burst") + h.sv("r", "dps") * 3.0
	return 0.0

func cast(s: String, _tgt, pos: Vector2, chg := 0.0) -> void:
	match s:
		"w": _cast_beam(pos, chg)
		"q": _cast_blink(pos)
		"r": _cast_r(pos)

func on_cast(_s: String) -> void:
	if int(h.sk["e"]) > 0:
		empowered = true

func on_attack_fire(_tgt, info: Dictionary) -> void:
	attack_count += 1
	if int(h.sk["e"]) > 0 and (empowered or attack_count % 4 == 0):
		info["proc"] = true
		empowered = false

func on_attack_hit(tgt, info: Dictionary) -> void:
	if bool(info.get("proc", false)) and int(h.sk["e"]) > 0:
		_chain(tgt)

# ------------------------------------------------------------ right-click: 脉冲射线 (charge)
func _cast_beam(p: Vector2, chg: float) -> void:
	var dir: Vector2 = (p - h.position).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.from_angle(h.face)
	var hit := {}
	if h.shard_owned:
		for ang in [-0.28, 0.0, 0.28]:
			_beam(dir.rotated(ang), hit, chg)
	else:
		_beam(dir, hit, chg)

func _beam(dir: Vector2, hit: Dictionary, chg: float) -> void:
	var a: Vector2 = h.position
	var qlen: float = sval("w", "len", chg)
	var b: Vector2 = a + dir * qlen
	if g.terrain != null:
		b = g.terrain.sweep(a, b, 1.0)   # the beam stops at walls and pillars
		qlen = a.distance_to(b)
	var w: float = float(h.sdef["w"]["width"]) * lerpf(0.8, 1.3, chg)
	var dmg: float = sval("w", "dmg", chg)
	h.stat_add("shot_fired")
	var any := false
	for e in g.foes_all(h.team):
		var rel: Vector2 = e.position - a
		var tp: float = clampf(rel.dot(dir), 0.0, qlen)
		var perp: float = (rel - dir * tp).length()
		if perp < w / 2.0 + float(e.radius) and not hit.has(e):
			hit[e] = true
			e.charged = 5.0
			g.damage(h, e, dmg, "skill", "magic", dir * 0.5)
			if bool(e.is_hero) and not any:
				any = true
				h.stat_add("shot_hit")
	g.beam_fx(a, b, Color(0.4, 2.2, 2.6) if chg < 1.0 else Color(2.6, 2.6, 0.8), 1.0 + 0.6 * chg)
	g.sfx("lance")
	g.add_shake(5.0, h)

# ------------------------------------------------------------ Q: 相位闪烁
func _cast_blink(p: Vector2) -> void:
	var to: Vector2 = p - h.position
	var dest: Vector2 = g.clamp_pos(h.position + to.limit_length(blink_dist()), h.radius)
	g.ghost(h, h.position, Color(2.0, 0.4, 1.8, 0.7))
	g._ring(h.position, 30, 4, 0.3, Color(2.2, 0.5, 2.0), 8)
	h.position = dest
	h.trail.clear_points()
	g.sfx("blink")
	var r: float = float(h.sdef["q"]["radius"])
	var nova: float = h.sv("q", "nova")
	var det: float = h.sv("q", "det")
	var stun: float = h.sv("q", "stun")
	var detonated := 0
	for e in g.foes_in(h.team, dest, r):
		var dmg := nova
		if float(e.charged) > 0.0:
			dmg += det
			e.charged = 0.0
			e.stun = maxf(float(e.stun), stun * (0.3 if bool(e.boss) else 1.0))
			detonated += 1
			g._popup(e.position + Vector2(0, -float(e.radius) - 16.0), "引爆!", "big")
		g.damage(h, e, dmg, "skill", "magic", (e.position - dest).normalized() * 1.5)
	g._ring(dest, 20, r, 0.4, Color(2.4, 0.6, 2.2), 12)
	g._burst(dest, Color(2.2, 0.6, 2.2), 30, 380.0, 0.5, 3.0)
	g.sfx("nova", 1.0 if detonated == 0 else 0.85)
	g.add_shake(6.0 + detonated * 1.5, h)
	if detonated >= 3 and h.is_player:
		g.hitstop = 0.06

# ------------------------------------------------------------ R
func _cast_r(p: Vector2) -> void:
	var r := r_radius()
	sings.append({"pos": p, "t": 0.0, "dur": 3.0, "lvl": int(h.sk["r"]), "r": r, "scepter": h.has_scepter()})
	for e in g.foes_in(h.team, p, r):
		e.charged = 5.0
	g.sfx("singularity")
	g._ring(p, r, 20, 0.5, Color(2.0, 0.5, 2.4), 10)

func tick_world(d: float) -> void:
	if sings.is_empty():
		return
	var keep := []
	var rsk: Dictionary = h.sdef["r"]
	for s in sings:
		s["t"] = float(s["t"]) + d
		var p: Vector2 = s["pos"]
		var lvl: int = int(s["lvl"])
		var r: float = float(s["r"])
		var dps: float = float(rsk["dps"][lvl - 1])
		for e in g.foes_in(h.team, p, r * 1.3):
			var to: Vector2 = p - e.position
			var dist: float = to.length()
			var k := 1.0
			if bool(e.boss): k = 0.08
			elif bool(e.is_hero): k = 0.3
			e.pull = to.normalized() * minf(480.0, dist * 5.0) * k
			if dist < r + float(e.radius):
				g.damage(h, e, dps * d, "dot", "magic")
		if Engine.get_process_frames() % 3 == 0:
			var a: float = g.rng.randf() * TAU
			g._burst(p + Vector2.RIGHT.rotated(a) * r, Color(1.6, 0.6, 2.4), 2, 60.0, 0.4, 2.0)
		if float(s["t"]) >= float(s["dur"]):
			var inside: Array = g.foes_in(h.team, p, r)
			var charged_n := 0
			for e in inside:
				if float(e.charged) > 0.0:
					charged_n += 1
			var burst: float = (float(rsk["burst"][lvl - 1]) + (150.0 if bool(s["scepter"]) else 0.0)) * (1.0 + minf(1.0, charged_n * 0.12))
			for e in inside:
				e.stun = maxf(float(e.stun), 0.2 if bool(e.boss) else 0.6)
				g.damage(h, e, burst, "skill", "magic", (e.position - p).normalized() * 2.0)
			g._ring(p, 10, r * 1.5, 0.7, Color(2.6, 0.7, 2.6), 16)
			g._burst(p, Color(2.4, 0.7, 2.4), 60, 600.0, 0.9, 4.0)
			g._burst(p, Color(0.6, 2.2, 2.6), 40, 450.0, 0.8, 3.0)
			g.sfx("collapse")
			g.add_shake(22.0, h)
			if h.is_player:
				g._flash(Color(1.0, 0.5, 1.0, 0.25))
				g.hitstop = 0.1
			if charged_n >= 5:
				g._popup(p + Vector2(0, -60), "奇点坍缩 ×%d" % charged_n, "big")
		else:
			keep.append(s)
	sings = keep

func draw(o: Node2D) -> void:
	var tick := Time.get_ticks_msec() * 0.001
	for s in sings:
		var p: Vector2 = s["pos"]
		var r: float = float(s["r"])
		var k: float = float(s["t"]) / float(s["dur"])
		o.draw_circle(p, r, Color(0.3, 0.0, 0.4, 0.25))
		for i in 4:
			var a0 := tick * (3.0 + i) + i * 1.3
			o.draw_arc(p, r * (1.0 - 0.2 * i) * (1.0 - k * 0.3), a0, a0 + 2.2, 32, Color(1.8, 0.5, 2.2, 0.8), 3.0)
		o.draw_circle(p, 22.0 + 10.0 * sin(tick * 12.0), Color(0, 0, 0, 1))
		o.draw_arc(p, 26.0, 0, TAU, 24, Color(2.4, 0.8, 2.6), 3.0)

# ------------------------------------------------------------ E chain
func _chain(first) -> void:
	var bounces: int = int(h.sv("e", "bounces"))
	var dmg: float = h.sv("e", "dmg")
	var cur = first
	var hit := {}
	var prev: Vector2 = first.position
	for i in bounces + 1:
		if cur == null:
			break
		hit[cur] = true
		g._bolt(prev, cur.position)
		var amount := dmg
		if float(cur.charged) > 0.0:
			amount *= 2.0
			cur.charged = 5.0
		var was_alive: bool = not cur.dead
		g.damage(h, cur, amount, "chain", "magic")
		if was_alive and cur.dead:
			h.cds["q"] = maxf(0.0, float(h.cds["q"]) - 1.0)
		prev = cur.position
		var nxt = null
		var bd := 320.0
		for o in g.foes_in(h.team, prev, 320.0):
			if hit.has(o):
				continue
			var dd: float = prev.distance_to(o.position)
			if dd < bd:
				bd = dd
				nxt = o
		cur = nxt
	g.sfx("chain", g.rng.randf_range(0.95, 1.1), -4.0, 0.05)
