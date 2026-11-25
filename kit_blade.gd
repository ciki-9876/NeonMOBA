extends "res://kit_base.gd"
## 绯刃 — Q 瞬影斩 / W 血誓 / E 处决 / R 千刃·剑舞
## Combo: Q marks → attacks/slashes on a marked target trigger E (處決) → R slashes alternate mark / execute.

const SLASH_COL := Color(2.6, 0.45, 0.55)

var oath_n := 0
var oath_t := 0.0
var q_follow = null
var q_from := Vector2.ZERO
var r_left := 0
var r_t := 0.0
var r_target = null
var r_first := true
var r_last = null
var slashes: Array = []   # short-lived slash visuals [a, b, t]

func reset() -> void:
	oath_n = 0
	oath_t = 0.0
	r_left = 0
	r_target = null
	q_follow = null

func round_reset() -> void:
	reset()
	slashes.clear()

func busy() -> bool:
	return r_left > 0

func cd_reduction(s: String) -> float:
	return 15.0 if s == "r" and h.has_scepter() else 0.0

func cast_range(s: String, tgt) -> float:
	var cast_bonus: float = float(h.ST.get("cast", 0.0))
	if s == "q":
		return (h.sv("q", "dist") + cast_bonus) if tgt != null else 0.0
	if s == "r":
		return float(h.sdef["r"]["range"]) + cast_bonus
	return 0.0

func skill_radius(s: String) -> float:
	if s == "r":
		return float(h.sdef["r"]["jump"])
	if s == "w":
		return h.atk_range() + 40.0
	return float(h.sdef[s].get("radius", 0.0))

func slash_count() -> int:
	return int(h.sv("r", "slashes")) + (3 if h.has_scepter() else 0)

func est_damage(s: String) -> float:
	var ex: float = h.sv("e", "flat")
	match s:
		"q": return h.sv("q", "dmg") + ex * 0.8
		"w": return h.sv("w", "bonus") * 3.0
		"r": return float(slash_count()) * (h.atk_dmg() + h.sv("r", "bonus")) * 0.8 + ex * float(slash_count()) * 0.4
	return 0.0

func cast(s: String, tgt, pos: Vector2) -> void:
	match s:
		"q": _cast_q(tgt, pos)
		"w": _cast_w()
		"r": _cast_r(tgt)

# ------------------------------------------------------------ Q 瞬影斩
func _cast_q(tgt, pos: Vector2) -> void:
	var from: Vector2 = h.position
	var maxd: float = h.sv("q", "dist") + float(h.ST.get("cast", 0.0))
	var to: Vector2
	if tgt != null:
		var dir: Vector2 = (tgt.position - from).normalized()
		to = tgt.position + dir * (float(tgt.radius) + h.radius + 16.0)
		to = from + (to - from).limit_length(maxd + 80.0)
		q_follow = tgt
	else:
		to = from + (pos - from).limit_length(maxd)
		q_follow = null
	q_from = from
	g.ghost(h, from, Color(2.6, 0.4, 0.5, 0.7))
	g.sfx("dash", 1.15, -2.0)
	h.start_dash(to, 2600.0, _q_land)

func _q_land() -> void:
	var a := q_from
	var b: Vector2 = h.position
	var seg: Vector2 = b - a
	var slen: float = seg.length()
	var dir: Vector2 = seg / maxf(slen, 0.001)
	var w: float = float(h.sdef["q"]["width"])
	var dmg: float = h.sv("q", "dmg")
	var stun_t: float = 1.0 if h.shard_owned else 0.0
	var hits := 0
	for e in g.foes_all(h.team):
		var rel: Vector2 = e.position - a
		var tp: float = clampf(rel.dot(dir), 0.0, slen)
		if (rel - dir * tp).length() < w / 2.0 + float(e.radius):
			g.damage(h, e, dmg, "skill", "phys", dir * 0.6)
			if not e.dead:
				e.mark = float(h.sdef["q"]["mark"])
				e.mark_src = h
				if stun_t > 0.0:
					e.stun = maxf(float(e.stun), stun_t * (0.3 if bool(e.boss) else 1.0))
			hits += 1
	g.beam_fx(a, b, SLASH_COL, 0.6)
	slashes.append([a, b, 0.0])
	g.sfx("lance", 1.35, -4.0)
	if hits > 0:
		g.add_shake(4.0, h)
	if h.valid(q_follow) and h.is_foe(q_follow):
		h.order_attack(q_follow)
	q_follow = null

# ------------------------------------------------------------ W 血誓
func _cast_w() -> void:
	oath_n = int(h.sdef["w"]["charges"])
	oath_t = float(h.sdef["w"]["dur"])
	h.ms_buff_t = 3.0
	h.ms_buff_pct = float(h.sdef["w"]["ms"]) / 100.0
	g._ring(h.position, 60, 10, 0.4, SLASH_COL, 8)
	g._burst(h.position, SLASH_COL, 18, 220.0, 0.5, 2.5)
	g.sfx("learn", 0.7, -2.0)

func on_attack_fire(_tgt, info: Dictionary) -> void:
	if oath_n > 0 and oath_t > 0.0:
		oath_n -= 1
		info["bonus"] = float(info["bonus"]) + h.sv("w", "bonus")
		info["ls"] = float(info["ls"]) + float(h.sdef["w"]["ls"]) / 100.0
		info["proc"] = true

# ------------------------------------------------------------ E 处决
func on_attack_hit(tgt, _info: Dictionary) -> void:
	if int(h.sk["e"]) > 0 and h.valid(tgt) and float(tgt.mark) > 0.0:
		_execute(tgt)

func _execute(u) -> void:
	u.mark = 0.0
	var flat: float = h.sv("e", "flat")
	var extra: float = flat + (float(u.max_hp) - float(u.hp)) * h.sv("e", "pct") / 100.0
	if not bool(u.is_hero):
		extra = minf(extra, flat + 400.0)
	g._popup(u.position + Vector2(-24, -float(u.radius) - 30.0), "处决!", "big")
	g.damage(h, u, extra, "crit", "phys", Vector2.ZERO)
	h.cds["q"] = maxf(0.0, float(h.cds["q"]) - float(h.sdef["e"]["qcdr"]))
	g.x_slash_fx(u.position, SLASH_COL)
	g.sfx("ahit", 0.6, -2.0)

# ------------------------------------------------------------ R 千刃
func _cast_r(tgt) -> void:
	r_left = slash_count()
	r_t = 0.0
	r_target = tgt
	r_first = true
	r_last = null
	h.atk_phase = 0
	h.invuln = 0.35
	g.sfx("blink", 0.7)
	g._ring(h.position, 10, 120, 0.35, SLASH_COL, 8)

func _pick_target():
	if r_first and h.is_foe(r_target):
		return r_target
	var pool: Array = g.foes_in(h.team, h.position, float(h.sdef["r"]["jump"]))
	if pool.is_empty():
		return null
	var heroes := []
	for u in pool:
		if bool(u.is_hero):
			heroes.append(u)
	var src: Array = heroes if not heroes.is_empty() else pool
	if src.size() > 1 and r_last != null and src.has(r_last) and g.rng.randf() < 0.6:
		src = src.duplicate()
		src.erase(r_last)
	return src[g.rng.randi() % src.size()]

func tick(d: float) -> void:
	oath_t = maxf(0.0, oath_t - d)
	if oath_t <= 0.0:
		oath_n = 0
	var keep := []
	for s in slashes:
		s[2] = float(s[2]) + d
		if float(s[2]) < 0.25:
			keep.append(s)
	slashes = keep
	if r_left <= 0:
		return
	h.invuln = 0.35
	r_t -= d
	if r_t > 0.0:
		return
	r_t = 0.2
	var u = _pick_target()
	r_first = false
	if u == null:
		_end_r()
		return
	var old: Vector2 = h.position
	var off: Vector2 = Vector2.from_angle(g.rng.randf() * TAU) * (float(u.radius) + 34.0)
	g.ghost(h, old, Color(2.6, 0.4, 0.5, 0.6))
	h.position = g.clamp_pos(u.position + off, h.radius)
	h.face = (u.position - h.position).angle()
	h.trail.clear_points()
	slashes.append([old, h.position, 0.0])
	var dmg: float = h.atk_dmg() + h.sv("r", "bonus")
	var dealt: float = g.damage(h, u, dmg, "skill", "phys", Vector2.ZERO)
	var ls: float = float(h.ST.get("ls", 0.0))
	if ls > 0.0 and dealt > 0.0:
		h.hp = minf(h.max_hp, h.hp + dealt * ls)
	if not u.dead:
		if int(h.sk["e"]) > 0 and float(u.mark) > 0.0:
			_execute(u)
		else:
			u.mark = float(h.sdef["q"]["mark"])
			u.mark_src = h
	g.x_slash_fx(u.position, SLASH_COL)
	g.sfx("attack", g.rng.randf_range(1.3, 1.6), -4.0)
	g.add_shake(3.0, h)
	r_last = u
	r_left -= 1
	if r_left <= 0:
		_end_r()

func _end_r() -> void:
	r_left = 0
	h.invuln = 0.0
	var follow = r_last if h.is_foe(r_last) else r_target
	if h.is_foe(follow):
		h.order_attack(follow)

func draw(o: Node2D) -> void:
	for s in slashes:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var k: float = 1.0 - float(s[2]) / 0.25
		o.draw_line(a, b, Color(SLASH_COL.r, SLASH_COL.g, SLASH_COL.b, 0.8 * k), 6.0 * k + 1.0)
		o.draw_line(a, b, Color(3, 2.6, 2.6, k), 2.0)
	if oath_n > 0 and not h.dead:
		for i in oath_n:
			var a2: float = Time.get_ticks_msec() * 0.004 + i * TAU / 3.0
			o.draw_circle(h.position + Vector2.from_angle(a2) * 30.0, 4.0, Color(2.6, 0.5, 0.6, 0.9))
