extends RefCounted
## Generic hero AI. It knows nothing about specific heroes:
##  * skills are read through kit.ai_meta(s) — roles / aim / radius / est_dmg / est_heal
##    (data kits infer this from their effects; hand-written kits declare it in heroes_db.gd)
##  * team play comes from the team brain (team_ai.gd): intent, focus target, peel requests,
##    formation slot by role (tank front, carry behind, support at the back)
## The same AI plays any hero, as an ally or as an enemy.

const Profiles = preload("res://game/profiles.gd")
const ItemsDB = preload("res://items_db.gd")

var h
var g
var think := 0.0
var react := 0.22
var aim_err := 40.0
var greed := 1.0
var target = null
var retreating := false
var shop_t := 0.0
var cast_lock := 0.0
var last_cast := ""

# ---- player abilities (game/profiles.gd). Defaults = a neutral 精通 player; apply_profile() sets them.
## each ability changes concrete behaviour, so a better player measurably plays better:
##   reaction  -> think interval (react), chance to dodge telegraphs / skillshots (dodge)
##   mechanics -> skillshot aim error (aim_err), how much combos are valued (combo)
##   awareness -> noise in target choice (aware_noise)
##   decision  -> error in the retreat threshold and premature commits (decide_err)
##   teamwork  -> following the team focus / not stacking disables (follow), engage delay
##   composure -> swing of all of the above under pressure (match point, last alive)
var profile := {}
var stage_i := 2            # proficiency stage: 0 生疏 1 熟悉 2 精通 3 大师
var dodge := 0.45
var combo := 1.0
var aware_noise := 20.0
var decide_err := 0.3
var follow := 0.8
var engage_delay := 0.4
var _eng_t := 0.0
var mech01 := 0.5           # mechanics 0..1 (hesitation)
var lone := 0.15            # teamwork: chance to break formation and fight alone
var obj_discipline := 0.7   # awareness: chance to stay on the objective instead of chasing
## personality rolls are held for a while (not re-rolled every think), so thinking faster only
## means reacting sooner, never flip-flopping more: key -> [value, expires_at]
var _rolls := {}
var _pressure := false

func setup(hero, game, difficulty: int) -> void:
	h = hero
	g = game
	difficulty = clampi(difficulty, 0, 2)
	react = [0.42, 0.26, 0.14][difficulty]
	aim_err = [110.0, 50.0, 14.0][difficulty]
	greed = [0.7, 1.0, 1.2][difficulty]
	think = g.rng.randf_range(0.0, 0.5)
	apply_profile(Profiles.from_difficulty(difficulty))

## map a player profile to behaviour parameters (see the table above)
func apply_profile(p: Dictionary, swing := {}) -> void:
	profile = p
	var e: Dictionary = Profiles.effective(p, str(h.hid), swing)
	stage_i = Profiles.STAGES.find(Profiles.stage(p, str(h.hid)))
	react = lerpf(0.45, 0.10, e["reaction"])
	dodge = lerpf(0.0, 0.9, e["reaction"])
	aim_err = lerpf(140.0, 6.0, e["mechanics"])
	combo = lerpf(0.3, 1.3, e["mechanics"])
	mech01 = e["mechanics"]
	aware_noise = lerpf(70.0, 0.0, e["awareness"])
	obj_discipline = lerpf(0.35, 1.0, e["awareness"])
	decide_err = lerpf(0.6, 0.04, e["decision"])
	greed = 1.0
	follow = lerpf(0.35, 1.0, e["teamwork"])
	engage_delay = lerpf(1.2, 0.0, e["teamwork"])
	lone = lerpf(0.45, 0.0, e["teamwork"])
	# tuning hook: profile["ai_over"] = {"dodge": 0.0, ...} overrides any parameter above (sim --ai_a)
	var over: Dictionary = p.get("ai_over", {})
	for k in over:
		set(k, float(over[k]))

## a random value in [0, 1) that stays the same for `period` seconds (per key)
func _roll(key, period := 2.5) -> float:
	var r = _rolls.get(key)
	if r == null or g.t >= float(r[1]):
		r = [g.rng.randf(), g.t + period * g.rng.randf_range(0.8, 1.2)]
		_rolls[key] = r
	return float(r[0])

## a gaussian value that stays the same for `period` seconds (per key)
func _roll_n(key, sd: float, period := 2.5) -> float:
	var u := _roll(key, period)
	return sd * (sqrt(-2.0 * log(maxf(1e-6, _roll([key, "b"], period)))) * cos(TAU * u))

## composure: when the pressure state changes, re-roll a swing on every ability
func _check_pressure() -> void:
	var p := false
	var r = g.rounds
	if r != null:
		p = maxi(r.score[0], r.score[1]) >= r.ROUNDS_TO_WIN - 1
		var alive := 0
		for a in g.heroes:
			if a.team == h.team and not a.dead:
				alive += 1
		p = p or alive == 1
	if p == _pressure or profile.is_empty():
		return
	_pressure = p
	var swing := {}
	if p:
		var comp: float = (float(profile["attrs"].get("composure", 10)) - 1.0) / 19.0
		for k in Profiles.ATTRS:
			if k != "composure":
				swing[k] = g.rng.randfn((comp - 0.5) * 2.0, lerpf(4.0, 0.5, comp))
	apply_profile(profile, swing)

func update(d: float) -> void:
	if h.dead:
		retreating = false
		return
	cast_lock -= d
	think -= d
	_drive(d)
	if think > 0.0:
		return
	think = react * g.rng.randf_range(0.8, 1.25)
	_learn()
	shop_t -= react
	if shop_t <= 0.0:
		shop_t = 1.5
		_shop()
	if h.busy() or h.stun > 0.0:
		return
	_check_pressure()
	if _try_dodge():
		return
	if (h.casting() or h.charging != "") and cast_lock > 0.0:
		return
	var brain = g.brain(h.team)
	if brain != null and brain.engage_ok:
		_eng_t += react
	else:
		_eng_t = 0.0
	var foes: Array = g.seen_foes(h.team, h.position, 1500.0)
	var foe_heroes := []
	for u in foes:
		if bool(u.is_hero):
			foe_heroes.append(u)
	var hpf: float = h.hp / h.max_hp
	var was_retreating := retreating
	_update_retreat(hpf, foe_heroes, brain)
	if retreating and not was_retreating:
		_cover_end = -1.0
	if retreating:
		if _try_support(foe_heroes, brain):
			return
		_do_retreat(foe_heroes)
		return
	# supports look after the team first
	if _try_support(foe_heroes, brain):
		return
	target = _pick_target(foes, brain)
	if _objective_leash(brain):
		return
	if target == null:
		_roam(brain)
		return
	if _try_skills(target, foes, brain):
		return
	_attack(target, foe_heroes, brain)

# ------------------------------------------------------------ helpers
func meta(s: String) -> Dictionary:
	var m: Dictionary = h.kit.ai_meta(s)
	if stage_i >= 2:
		return m
	# 熟悉: no combo knowledge; 生疏: also only the skill's main use
	var m2 := m.duplicate()
	m2.erase("prefer_status")
	m2.erase("setup_status")
	if stage_i == 0 and _roll(["roles", s], 3.0) < 0.5:
		# 生疏: about half the time only thinks of the skill's main use
		var roles: Array = m.get("roles", [])
		var keep := []
		if not roles.is_empty():
			keep.append(roles[0])
		for r in ["ult", "heal", "team_heal"]:
			if r in roles and not r in keep:
				keep.append(r)
		m2["roles"] = keep
	return m2

## awareness (objective play, round mode): once the core is open, don't chase far away from it;
## walk back in when outside it. Returns true when it issued the order.
func _objective_leash(brain) -> bool:
	var obj: Dictionary = g.objective(h.team)
	if obj.is_empty() or not bool(obj["open"]) or brain == null or brain.intent == "retreat":
		return false
	if _roll("objective") > obj_discipline:
		return false
	var core: Vector2 = obj["pos"]
	var r: float = float(g.rounds.CORE_R)
	if target != null and h.valid(target) and target.position.distance_to(core) > r + h.atk_range() + 60.0:
		target = null
	var dist_core: float = h.position.distance_to(core)
	if dist_core > r * 0.85:
		# nobody of ours on the point but they are (or we still need to capture): the closest one walks in
		var mine := 0
		var theirs := 0
		var closest := true
		for u in g.heroes:
			if u.dead:
				continue
			if g.rounds.in_core(u):
				if u.team == h.team: mine += 1
				else: theirs += 1
			elif u.team == h.team and u != h and u.position.distance_to(core) < dist_core:
				closest = false
		if mine == 0 and closest and (theirs > 0 or g.rounds.capture[h.team] < 1.0):
			_move(core + (h.position - core).normalized() * r * 0.35)
			return true
		if target == null or h.position.distance_to(target.position) > h.atk_range() + float(target.radius) + 20.0:
			_amove(brain.slot(h))
			return true
	return false

func _aware01() -> float:
	return clampf(1.0 - aware_noise / 70.0, 0.0, 1.0)

## reaction: step out of telegraphed areas and the path of skillshots
func _try_dodge() -> bool:
	if dodge <= 0.0 or h.has_buff("root") or h.casting():
		return false
	for th in g.threats_for(h.team):
		var p: Vector2 = th["pos"]
		var away := Vector2.ZERO
		if th["kind"] == "area":
			var dist: float = h.position.distance_to(p)
			if dist > float(th["r"]) + h.radius or float(th["t"]) > 1.0:
				continue
			away = (h.position - p).normalized() * (float(th["r"]) - dist + h.radius + 50.0)
		else:
			var dir: Vector2 = th["dir"]
			var rel: Vector2 = h.position - p
			var along: float = rel.dot(dir)
			if along < 0.0 or along > minf(float(th["left"]), float(th["speed"]) * 0.7):
				continue
			var side: float = rel.dot(dir.orthogonal())
			if absf(side) > float(th["w"]) * 0.5 + h.radius + 10.0:
				continue
			away = dir.orthogonal() * (signf(side) if side != 0.0 else 1.0) * (float(th["w"]) * 0.5 + h.radius + 60.0)
		if away == Vector2.ZERO:
			continue
		var is_bolt: bool = bool(th.get("bolt", false))
		h.stat_add("bolt_seen" if is_bolt else "dodge_seen")
		if g.rng.randf() < dodge:
			h.stat_add("bolt_dodge" if is_bolt else "dodge_try")
			_move(g.clamp_pos(h.position + away, h.radius))
			cast_lock = 0.0
			return true
		return false
	return false

func _roles(s: String) -> Array:
	return meta(s).get("roles", [])

func _reach(s: String) -> float:
	var st: Dictionary = h.sdef[s]
	var cast_bonus := 0.0
	var m := meta(s)
	if float(m.get("reach", 0.0)) > 0.0:
		return float(m["reach"])
	if st.has("dist"):
		return h.sv(s, "dist") + cast_bonus
	var r = st.get("range", 0.0)
	if r is Array:
		return h.sv(s, "range") + cast_bonus
	return float(r) + cast_bonus

func _ready_skill(s: String, tgt) -> bool:
	return h.sdef[s]["type"] != "passive" and not meta(s).is_empty() and h.cast_error(s, tgt) == ""

func _status(u, key: String) -> float:
	if key == "" or u == null:
		return 0.0
	var v = u.get(key)
	return float(v) if v != null else 0.0

func _count_in(units: Array, p: Vector2, r: float) -> Vector2:
	var hc := 0.0
	var oc := 0.0
	for u in units:
		if p.distance_to(u.position) < r + float(u.radius) * 0.5:
			if bool(u.is_hero):
				hc += 1.0
			else:
				oc += 1.0
	return Vector2(hc, oc)

func _best_cluster(foes: Array, r: float, max_d: float) -> Array:
	var best_p: Vector2 = h.position
	var best_v := -1.0
	var best_c := Vector2.ZERO
	var cands := []
	for u in foes:
		if bool(u.is_hero) or foes.size() < 30:
			cands.append(u.position)
	var n0 := cands.size()
	for i in n0:
		for j in range(i + 1, mini(n0, i + 4)):
			cands.append((cands[i] + cands[j]) * 0.5)
	for p in cands:
		if h.position.distance_to(p) > max_d:
			continue
		var c := _count_in(foes, p, r)
		var v := c.x + c.y * 0.12
		if v > best_v:
			best_v = v
			best_p = p
			best_c = c
	return [best_p, best_c]

# ------------------------------------------------------------ retreat
func _burst_potential() -> float:
	var total: float = h.atk_dmg() * 3.0
	for s in ["q", "w", "e", "r"]:
		if h.sdef[s]["type"] == "passive" or int(h.sk[s]) <= 0:
			continue
		if float(h.cds[s]) <= 0.0 and h.mana >= h.sv(s, "mana"):
			total += float(h.kit.est_damage(s))
	return total

func _update_retreat(hpf: float, foe_heroes: Array, brain) -> void:
	var near := 0
	for u in foe_heroes:
		if h.position.distance_to(u.position) < 900.0:
			near += 1
	if retreating:
		var team_ok: bool = brain == null or brain.intent != "retreat"
		if g.rounds != null:
			# round mode has no fountain and no respawn: a retreat is only a short disengage.
			# Come back once nobody is close, or when the objective is about to be lost.
			var obj: Dictionary = g.objective(h.team)
			var urgent: bool = not obj.is_empty() and float(obj["urgency"]) >= 1.0
			if (near == 0 or urgent) and team_ok:
				retreating = false
			return
		if (hpf > 0.85 or (near == 0 and hpf > 0.55)) and team_ok:
			retreating = false
		return
	var limit := 0.18 / greed
	if h.role() == "tank":
		limit = 0.15
	limit *= maxf(0.2, 1.0 + _roll_n("retreat", decide_err, 3.0))
	if near >= 2:
		limit += 0.08
	var killable: bool = target != null and h.valid(target) and bool(target.is_hero) and float(target.hp) < _burst_potential() * 0.6
	if brain != null and brain.intent == "retreat" and not killable and near > 0:
		retreating = true
	elif hpf < limit and near > 0 and not killable:
		retreating = true
	elif hpf < 0.12:
		retreating = true

func _do_retreat(foe_heroes: Array) -> void:
	var home: Vector2 = g.home_pos(h.team)
	if g.rounds != null:
		# disengage toward the team (or just away from the nearest foe), not all the way home
		var brain = g.brain(h.team)
		var pull: Vector2 = home
		if brain != null:
			pull = brain.front + (home - brain.front).normalized() * 260.0
		home = pull
	var away: Vector2 = (home - h.position).normalized()
	var chaser = null
	var cd := 1e9
	for u in foe_heroes:
		var dd: float = h.position.distance_to(u.position)
		if dd < cd:
			cd = dd
			chaser = u
	if chaser != null and cd < 550.0:
		for s in ["q", "w", "e", "r"]:
			var typ: String = h.sdef[s]["type"]
			var roles := _roles(s)
			if "escape" in roles and typ in ["point", "unit_or_point"] and _ready_skill(s, null):
				if _cast(s, null, h.position + away * _reach(s)) == "":
					cast_lock = 0.6
					return
			# self-save: shield / banish / heal on myself
			if typ == "ally" and ("save" in roles or "heal" in roles) and _ready_skill(s, h):
				if _cast(s, h, h.position) == "":
					cast_lock = 0.5
					return
			# peel the chaser with a disable
			if "disable" in roles and typ in ["unit", "point"] and _ready_skill(s, chaser) and cd < _reach(s) + 40.0:
				if _cast(s, chaser if typ == "unit" else null, chaser.position) == "":
					cast_lock = 0.5
					return
	# terrain: break line of sight behind a pillar / wall instead of running in the open
	if g.terrain != null and chaser != null and cd < 480.0 and (_cover_end < 0.0 or g.t < _cover_end) and _roll("cover", 2.0) < _aware01():
		var threats := []
		for u in foe_heroes:
			if h.position.distance_to(u.position) < 900.0:
				threats.append(u.position)
		var cp: Vector2 = g.terrain.best_cover(h.position, threats, 380.0, home)
		if cp != Vector2.INF:
			if _cover_end < 0.0:
				_cover_end = g.t + 1.8
			if h.position.distance_to(cp) > 20.0:
				h.stat_add("cover_t", react)
			_move(cp)
			return
	_move(home)

# ------------------------------------------------------------ team support (heal / save / buff allies)
func _try_support(foe_heroes: Array, brain) -> bool:
	var allies: Array = g.allies_in(h.team, h.position, 1400.0)
	if allies.is_empty():
		return false
	var best_s := ""
	var best_u := 0.0
	var best_t = null
	for s in ["r", "q", "w", "e"]:
		var st: Dictionary = h.sdef[s]
		var typ: String = st["type"]
		if typ == "passive" or int(h.sk[s]) <= 0:
			continue
		var m := meta(s)
		var roles: Array = m.get("roles", [])
		var is_ult: bool = bool(m.get("ult", false))
		if not ("heal" in roles or "save" in roles or "buff_ally" in roles or "team_heal" in roles):
			continue
		if "team_heal" in roles and typ == "no_target":
			if not _ready_skill(s, null):
				continue
			var missing := 0.0
			var low := 0
			for a in g.allies_in(h.team, h.position, maxf(float(m.get("radius", 600.0)), 300.0)):
				missing += float(a.max_hp) - float(a.hp)
				if float(a.hp) / float(a.max_hp) < 0.45:
					low += 1
			var u0 := 0.0
			if missing > float(m.get("est_heal", 200.0)) * (1.6 if is_ult else 0.9):
				u0 = 50.0 + 25.0 * float(low)
			if is_ult and low < 2 and missing < float(m.get("est_heal", 200.0)) * 2.5:
				u0 = 0.0
			if u0 > best_u:
				best_u = u0
				best_s = s
				best_t = null
			continue
		if typ != "ally":
			continue
		var reach: float = _reach(s)
		for a in allies:
			if not _ready_skill(s, a):
				break
			var dist: float = h.position.distance_to(a.position)
			if dist > reach + 350.0:
				continue
			var hpf: float = float(a.hp) / float(a.max_hp)
			var u := 0.0
			var danger: bool = brain != null and brain.in_danger(a)
			var hurt_recent: bool = g.t - float(a.last_hurt) < 1.5
			if "heal" in roles:
				var miss: float = float(a.max_hp) - float(a.hp)
				if miss > float(m.get("est_heal", 150.0)) * 0.6:
					u = maxf(u, 40.0 + 70.0 * (1.0 - hpf) + (20.0 if hurt_recent else 0.0))
			if "save" in roles:
				var save_hp: float = float(m.get("save_hp", 0.45))
				if hpf < save_hp and (danger or hurt_recent):
					u = maxf(u, 70.0 + 60.0 * (save_hp - hpf))
				elif not is_ult and (danger or (hurt_recent and hpf < 0.8)):
					u = maxf(u, 48.0 + 30.0 * (1.0 - hpf))
				if is_ult and hpf >= save_hp:
					u = 0.0
			if "buff_ally" in roles and not ("save" in roles):
				var at = a.ai.target if a.ai != null else null
				var engaged: bool = at != null and h.valid(at) and a.position.distance_to(at.position) < a.atk_range() + 150.0
				if engaged:
					u = maxf(u, 46.0 + (15.0 if a.role() == "carry" else 0.0))
			if a == h:
				u *= 0.9
			if u > best_u:
				best_u = u
				best_s = s
				best_t = a
	if best_s == "" or best_u < 45.0:
		return false
	var p: Vector2 = best_t.position if best_t != null else h.position
	if _cast(best_s, best_t, p) == "":
		cast_lock = 0.7
		last_cast = best_s
		return true
	return false

# ------------------------------------------------------------ target selection
func _pick_target(foes: Array, brain):
	var best = null
	var bs := -1e9
	var peel_t = null
	if brain != null and (h.role() == "tank" or h.role() == "support"):
		var pd := 1e9
		for a in brain.peel:
			if not is_instance_valid(a) or a == h:
				continue
			var dv = brain.peel[a]
			if h.valid(dv) and h.position.distance_to(dv.position) < pd:
				pd = h.position.distance_to(dv.position)
				peel_t = dv
	for u in foes:
		if not u.targetable():
			continue
		var dist: float = h.position.distance_to(u.position)
		if dist > 1300.0:
			continue
		var s := 0.0
		if bool(u.is_hero):
			s += 100.0
			s += (1.0 - float(u.hp) / float(u.max_hp)) * 100.0
			s -= float(u.hp) * 0.015
			if brain != null and u == brain.focus and _roll("focus") < follow:
				s += 140.0
			if u == peel_t:
				s += 140.0
			if u.disabled():
				s += 30.0
		else:
			s += 25.0 - float(u.hp) * 0.005
		s -= dist * 0.08
		if g.terrain != null and not g.has_los(h.position, u.position):
			s -= 70.0
		if u == target:
			s += 30.0
		if aware_noise > 0.0:
			s += _roll_n(u, aware_noise, 2.5)
		if s > bs:
			bs = s
			best = u
	return best

# ------------------------------------------------------------ offensive skills
func _try_skills(t, foes: Array, brain) -> bool:
	var best_s := ""
	var best_u := 0.0
	var best_tgt = null
	var best_pos := Vector2.ZERO
	var dist: float = h.position.distance_to(t.position)
	var t_hero: bool = bool(t.is_hero)
	var t_disabled: float = t.disable_left() if t_hero else 0.0
	var los: bool = g.has_los(h.position, t.position)
	var committed: bool = brain == null or (brain.engage_ok and _eng_t >= engage_delay) or h.role() == "tank" or dist < h.atk_range() + 60.0
	if not committed and _roll("commit", 3.0) < decide_err * 0.25:
		committed = true   # poor decision making: commits before the frontline is in
	for s in ["r", "q", "w", "e"]:
		var st: Dictionary = h.sdef[s]
		var typ: String = st["type"]
		if typ == "passive" or typ == "ally":
			continue
		if not los and typ != "self":
			continue
		var m := meta(s)
		if m.is_empty():
			continue
		var roles: Array = m.get("roles", [])
		if "team_heal" in roles:
			continue
		var aim: String = str(m.get("aim", "target"))
		var as_unit: bool = typ == "unit" or (typ == "unit_or_point" and aim == "unit")
		if not _ready_skill(s, t if as_unit else null):
			continue
		var reach: float = _reach(s)
		var rad: float = float(h.kit.skill_radius(s))
		var est: float = float(h.kit.est_damage(s))
		var lead: Vector2 = t.vel * 0.3 if t_hero else Vector2.ZERO
		var err: Vector2 = Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf() * aim_err
		var pos: Vector2 = t.position + lead + err
		var tgt = t if as_unit else null
		var cnt := Vector2(1.0 if t_hero else 0.0, 0.0 if t_hero else 1.0)
		var self_aoe: bool = aim == "self" and rad > 0.0
		if aim == "self":
			pos = h.position
			cnt = _count_in(foes, h.position, rad)
		elif aim == "cluster":
			var bc: Array = _best_cluster(foes, rad, reach + rad * 0.5)
			pos = bc[0]
			cnt = bc[1]
		var u := 0.0
		var in_reach: bool = dist <= reach + rad * 0.6 + 40.0
		if self_aoe:
			in_reach = cnt.x + cnt.y > 0.0
		if "nuke" in roles and in_reach:
			if t_hero:
				u = maxf(u, 40.0 + 60.0 * minf(1.0, est / maxf(float(t.hp) + float(t.barrier), 1.0)))
				if t_disabled > 0.3:
					u += 22.0   # follow up on a disabled target
			elif foes.size() >= 4:
				u = maxf(u, 30.0)
		if "disable" in roles and in_reach and t_hero:
			if t_disabled > 0.5 and _roll("chain") < follow:
				u = maxf(u, 10.0)   # don't stack disables, chain them (bad teamwork stacks them)
			else:
				u = maxf(u, 52.0 + (20.0 if h.role() == "tank" else 0.0))
		if "gap_close" in roles and dist > h.atk_range() + 120.0 and in_reach and t_hero:
			u = maxf(u, 52.0 if committed else 20.0)
		if "aoe" in roles or self_aoe:
			var need_h: float = float(m.get("min_heroes", 1))
			var need_c: float = float(m.get("min_creeps", 6))
			if aim != "cluster" and aim != "self":
				cnt = _count_in(foes, pos, rad)
			if (cnt.x >= need_h or cnt.y >= need_c) and (self_aoe or h.position.distance_to(pos) <= reach + rad):
				u = maxf(u, 45.0 + 22.0 * cnt.x + 2.0 * cnt.y)
		if "buff_attack" in roles or "buff_self" in roles:
			if dist <= h.atk_range() + float(t.radius) + 120.0:
				u = maxf(u, 55.0)
		if "soft" in roles and in_reach and t_hero:
			u = maxf(u, 42.0)
		if "ult" in roles or bool(m.get("ult", false)):
			var group: float = cnt.x
			if aim != "cluster" and aim != "self":
				group = _count_in(foes, t.position, maxf(rad, 300.0)).x
			var finisher: bool = t_hero and float(t.hp) <= est * 1.2 and float(t.hp) > est * 0.15
			var teamfight: bool = group >= float(m.get("min_heroes", 2))
			if not (finisher or teamfight) or not in_reach:
				u = 0.0
			elif u < 62.0:
				u = 62.0 + 10.0 * group
		if u <= 0.0:
			continue
		if not committed and not ("disable" in roles and h.role() != "carry"):
			u -= 30.0
		var pref: String = str(m.get("prefer_status", ""))
		if pref != "":
			u += (40.0 if _status(t, pref) > 0.0 else -18.0) * combo
		var setup_st: String = str(m.get("setup_status", ""))
		if setup_st != "" and _status(t, setup_st) <= 0.0:
			u += 8.0
		if s != "r" and int(h.sk["r"]) > 0 and float(h.cds["r"]) < 3.0 and h.mana - h.sv(s, "mana") < h.sv("r", "mana"):
			u -= 25.0
		if u > best_u:
			best_u = u
			best_s = s
			best_tgt = tgt
			best_pos = pos
	if best_s == "" or best_u < 45.0:
		return false
	# mechanics: a less skilled player hesitates / fumbles the timing (the cast comes a moment later)
	if _roll("hesitate", 0.8) < (1.0 - mech01) * 0.6:
		return false
	if _cast(best_s, best_tgt, best_pos) == "":
		cast_lock = 0.8
		last_cast = best_s
		return true
	return false

# ------------------------------------------------------------ attacking & positioning
func _attack(t, foe_heroes: Array, brain) -> void:
	var dist: float = h.position.distance_to(t.position)
	# kite melee divers
	if not bool(h.def["melee"]) and h.atk_phase == 0 and h.atk_ready > 0.3:
		for u in foe_heroes:
			if bool(u.def["melee"]) and h.position.distance_to(u.position) < 240.0:
				var away: Vector2 = (h.position - u.position).normalized()
				_move(h.position + away * 150.0)
				return
	# backline waits for the frontline before walking into the fight
	var lone_wolf: bool = _roll("lone", 3.0) < lone
	if brain != null and bool(t.is_hero) and not lone_wolf and (h.role() != "tank" or brain.intent == "setup"):
		var in_range: bool = dist <= h.atk_range() + float(t.radius) + 40.0
		if not in_range and (not brain.engage_ok or brain.intent == "group" or brain.intent == "hold" or brain.intent == "setup"):
			var slot: Vector2 = brain.slot(h)
			if h.position.distance_to(slot) > 60.0:
				_move(slot)
			return
	_engage(t)

func _roam(brain) -> void:
	if brain != null and _roll("lone", 3.0) < lone:
		# poor teamwork: wanders toward the enemy instead of holding the formation
		var e2 = g.nearest_foe_hero(h.team, h.position)
		if e2 != null:
			_amove(e2.position)
			return
	if brain != null and brain.check_pos != Vector2.INF and brain.intent != "retreat" \
			and (h.role() == "tank" or (h.role() != "support" and _roll("check", 3.0) < 0.3)) and _roll("check_aw", 3.0) < _aware01() + 0.2:
		h.stat_add("brush_check", react)
		_amove(brain.check_pos)
		return
	if brain != null:
		var slot: Vector2 = brain.slot(h)
		if brain.intent == "fight" or brain.intent == "group":
			_amove(slot)
		else:
			_move(slot)
		return
	var tgt = g.nearest_foe_hero(h.team, h.position)
	if tgt == null:
		_amove(g.arena_center())
	else:
		_amove(tgt.position)

# ------------------------------------------------------------ growth
func _learn() -> void:
	var guard := 0
	while h.skill_points > 0 and guard < 5:
		guard += 1
		if h.learn("r"):
			continue
		var done := false
		for s in h.def["ai_learn"]:
			if h.learn(str(s)):
				done = true
				break
		if not done:
			break

## items that answer what hurts us (round mode counter-building); per role: [tank, others]
const COUNTERS := {"phys": ["reactive", "plate"], "magic": ["barrier", "coat"], "heal": ["drill", "wound"], "tanky": ["drill", "drill"]}
const ARMOR_ITEMS := ["plate", "reactive", "tboots", "drill", "permafrost"]
const MR_ITEMS := ["coat", "barrier", "permafrost"]
## 1 = adapts its build to the opponent after a lost round (tuning: --ai_b adapt=0 turns it off)
var adapt := 1.0
var _cover_end := -1.0      # cover is a short break of line of sight per retreat, not a place to camp

func _shop() -> void:
	if g.rounds != null:
		_shop_rounds()
		return
	_buy_next(h.def["build"])

## does the hero own id, or an item built from it? (特化芯片 counts once fitted)
func _owns(id: String) -> bool:
	if g.is_consumed_item(id):
		return h.shard_owned
	for x in h.inv:
		if _contains(str(x), id):
			return true
	return false

func _contains(x: String, id: String) -> bool:
	if x == id:
		return true
	for c in ItemsDB.DB[x]["comps"]:
		if _contains(str(c), id):
			return true
	return false

## components of id still missing from the inventory (the same matching as the shop's recipe cost:
## a component counts only while it sits in the inventory as itself)
func _missing_parts(id: String, avail: Array, out: Array) -> void:
	for c in ItemsDB.DB[id]["comps"]:
		var cid: String = str(c)
		var i := avail.find(cid)
		if i >= 0:
			avail.remove_at(i)
		else:
			out.append(cid)
			_missing_parts(cid, avail, [])   # its own parts are covered by buying it later

## the priciest missing part of id (or a part of that part) that fits in the budget ("" = none)
func _affordable_part(id: String, budget: float) -> String:
	var miss := []
	_missing_parts(id, h.inv.duplicate(), miss)
	var best := ""
	var best_c := -1.0
	var queue: Array = miss.duplicate()
	while not queue.is_empty():
		var cid: String = str(queue.pop_front())
		var p := float(g.shop_price_for(h, cid))
		if p <= budget:
			if p > best_c:
				best = cid
				best_c = p
		else:
			var sub := []
			_missing_parts(cid, h.inv.duplicate(), sub)
			queue.append_array(sub)
	return best

## buys toward the build: the first item not owned yet — whole when affordable, otherwise its priciest
## affordable missing part. An item with no affordable part is saved for only when the hero has at least
## 60% of its price; otherwise the next item of the build is tried. Returns true if something was bought.
func _buy_next(build: Array) -> bool:
	for id in build:
		var sid: String = str(id)
		if _owns(sid):
			continue
		var price := float(g.shop_price_for(h, sid))
		var pick := sid
		if h.gold < price:
			pick = _affordable_part(sid, h.gold)
			if pick == "":
				if h.gold >= price * 0.6:
					return false
				continue
		if not g.is_consumed_item(pick) and g.inv_after(h, pick) > 6:
			g.sell_cheapest(h)
		return g.buy_for(h, pick, false) == ""
	return false

# ------------------------------------------------------------ round mode shopping
## what is killing us: after a lost round, buy an answer to the damage type that dominates what
## our team has taken so far (armor vs physical, magic resist vs magic). {} -> no counter needed
func _counter_item() -> String:
	if adapt <= 0.0 or g.rounds.loss_streak[h.team] <= 0:
		return ""
	var phys := 0.0
	var magic := 0.0
	var foe_heal := 0.0
	var foe_hp := 0.0
	var n_foes := 0
	for a in g.heroes:
		if a.team == h.team:
			phys += float(a.stats.get("taken_phys", 0.0))
			magic += float(a.stats.get("taken_magic", 0.0))
		else:
			foe_heal += float(a.heal_done)
			foe_hp += float(a.max_hp) / g.def_mult(float(a.armor_val()))
			n_foes += 1
	var idx := 0 if h.role() == "tank" else 1
	var total := phys + magic
	var kind := ""
	if total >= 1500.0 and phys / total >= 0.6:
		kind = "phys"
	elif total >= 1500.0 and magic / total >= 0.6:
		kind = "magic"
	elif foe_heal >= 1200.0 and h.role() != "support":
		kind = "heal"
	elif n_foes > 0 and foe_hp / n_foes > 2000.0 and h.role() == "carry" and float(h.ST.get("pow", 0.0)) <= 0.0:
		kind = "tanky"   # physical carries vs an effectively tanky lineup: armor break
	if kind == "":
		return ""
	var want: String = str(COUNTERS[kind][idx])
	var owned: Array = ARMOR_ITEMS if kind == "phys" else (MR_ITEMS if kind == "magic" else [want])
	for id in owned:
		if _owns(str(id)):
			return ""
	return want

## the loser's one full-price sale: sell the item that helps least against what hurts us and
## (if possible) just covers the shortfall
func _refund_pick(shortfall: float, keep: String) -> int:
	var best := -1
	var best_c := 1e9
	var top := -1
	var top_c := -1.0
	for i in h.inv.size():
		var id: String = h.inv[i]
		if id == keep or ARMOR_ITEMS.has(id) or MR_ITEMS.has(id):
			continue
		var c := float(ItemsDB.DB[id]["cost"])
		if c >= shortfall and c < best_c:
			best_c = c
			best = i
		if c > top_c:
			top_c = c
			top = i
	return best if best >= 0 else top

func _shop_rounds() -> void:
	if g.rounds.phase != "buy":
		return
	var want := _counter_item()
	if want != "":
		var price: float = float(g.shop_price_for(h, want))
		if h.gold < price and h.refund_tokens > 0:
			var idx := _refund_pick(price - h.gold, want)
			if idx >= 0:
				g.sell_for(h, idx)
				h.stat_add("refund_used")
		if h.gold >= price:
			if g.inv_after(h, want) > 6:
				g.sell_cheapest(h)
			if g.buy_for(h, want, false) == "":
				h.stat_add("counter_buy")
	# spend down: whole items or components toward the build, a few purchases per shopping tick
	for i in 6:
		if not _buy_next(h.def["build"]):
			break

# ============================================================ 3C driver
## The decision code above sets an intent (_move / _amove / _engage / _cast). Every step, _drive() turns it into
## the hero's controller input exactly like a player would: a move direction, an aim point, fire, held keys.
##   mechanics -> aim error of every basic attack (sampled per shot) and how well it strafes
##   reaction  -> how quickly the aim follows the target (aim lag) and dodging (bolts included, see _try_dodge)
var mode := "idle"          # idle | move | amove | attack
var goal := Vector2.ZERO
var goal_unit = null
var _cast_aim := Vector2.ZERO
var _cast_unit = null
var _charge_goal := 1.0
var _charge_unit = null
var _aim_pt := Vector2.ZERO
var _aim_off := Vector2.ZERO
var _last_phase := 0
var _strafe := 1.0
var _strafe_t := 0.0

func _move(p: Vector2) -> void:
	mode = "move"
	goal = p
	goal_unit = null

func _amove(p: Vector2) -> void:
	mode = "amove"
	goal = p
	goal_unit = null

func _engage(u) -> void:
	mode = "attack"
	goal_unit = u

## cast toward a unit or a point; charge skills are held until the wanted charge is reached
func _cast(s: String, tgt, pos: Vector2) -> String:
	var unit_ok: bool = tgt != null and is_instance_valid(tgt) and not tgt.dead
	h.ctl_aim = tgt.position if unit_ok else pos
	_aim_pt = h.ctl_aim
	var err: String = h.press(s)
	if err != "":
		return err
	_cast_unit = tgt if unit_ok else null
	_cast_aim = pos
	if h.charging == s:
		_charge_unit = tgt if unit_ok and tgt != h else null
		# good mechanics: waits for a fuller charge (but not when the target is about to walk out of reach)
		_charge_goal = clampf(0.55 + 0.45 * mech01 + g.rng.randf_range(-0.15, 0.1), 0.3, 1.0)
		h.ctl_hold = true
	return ""

func _steer(p: Vector2) -> void:
	if h.position.distance_to(p) < 10.0:
		h.ctl_move = Vector2.ZERO
		return
	h.ctl_move = (h.steer_point(p) - h.position).normalized()

## where to shoot at u: lead by the projectile flight time (velocity estimate is the target's current one)
func _lead(u, speed: float) -> Vector2:
	var p: Vector2 = u.position
	if speed <= 0.0 or not ("vel" in u):
		return p
	var tt: float = h.position.distance_to(p) / speed
	return p + (u.vel as Vector2) * tt

func _aim_at(p: Vector2, d: float) -> void:
	# reaction: the aim catches up with a time constant ~ half the think interval
	var tau: float = maxf(0.03, react * 0.5)
	_aim_pt = _aim_pt.lerp(p, 1.0 - exp(-d / tau))
	h.ctl_aim = _aim_pt + _aim_off

func _drive(d: float) -> void:
	h.ctl_move = Vector2.ZERO
	h.ctl_fire = false
	# a new swing / shot starts: sample this shot's aim error
	if h.atk_phase == 1 and _last_phase != 1:
		_aim_off = Vector2.from_angle(g.rng.randf() * TAU) * sqrt(g.rng.randf()) * aim_err * 0.6
	_last_phase = h.atk_phase
	if h.casting():
		_aim_at(_cast_unit.position if _cast_unit != null and is_instance_valid(_cast_unit) else _cast_aim, d)
		return
	if h.charging != "":
		var cu = _charge_unit
		var cp: Vector2 = _cast_aim
		if cu != null and is_instance_valid(cu) and not cu.dead:
			var sh_speed := 1500.0
			cp = _lead(cu, sh_speed)
		_aim_at(cp, d)
		var reach: float = _reach(h.charging)
		var leaving: bool = cu != null and is_instance_valid(cu) and h.position.distance_to(cu.position) > reach * 0.9
		h.ctl_hold = h.charge < _charge_goal and not leaving
		if mode == "attack":
			_kite(goal_unit, d)
		return
	h.ctl_hold = false
	match mode:
		"move":
			_steer(goal)
			_aim_at(goal, d)
		"amove":
			var f = g.nearest_foe(h.team, h.position, h.atk_range() + 160.0)
			if f != null:
				_shoot(f, d)
				_kite(f, d)
			else:
				_steer(goal)
				_aim_at(goal, d)
		"attack":
			var u = goal_unit
			if u == null or not h.is_foe(u):
				mode = "idle"
				return
			_shoot(u, d)
			_kite(u, d)
		_:
			var f2 = g.nearest_foe(h.team, h.position, h.atk_range() + 60.0)
			if f2 != null:
				_shoot(f2, d)

## aim and fire at u when it is worth a shot
func _shoot(u, d: float) -> void:
	var melee: bool = bool(h.def["melee"])
	var dist: float = h.position.distance_to(u.position)
	if melee:
		_aim_at(u.position, d)
		h.ctl_fire = dist <= h.melee_reach() + float(u.radius) - 4.0
	else:
		_aim_at(_lead(u, h.proj_speed()), d)
		h.ctl_fire = dist <= h.bolt_reach() * 0.85 and g.has_los(h.position, u.position)

## footwork around a target: melee closes in; ranged holds ~85% of its range and strafes (mechanics)
func _kite(u, d: float) -> void:
	if u == null or not is_instance_valid(u) or u.dead:
		return
	var to: Vector2 = u.position - h.position
	var dist := to.length()
	if bool(h.def["melee"]):
		if dist > h.melee_reach() * 0.7 + float(u.radius):
			_steer(u.position)
		return
	var want: float = h.atk_range() * 0.85
	if dist > h.atk_range() or not g.has_los(h.position, u.position):
		_steer(u.position)
		return
	_strafe_t -= d
	if _strafe_t <= 0.0:
		_strafe_t = g.rng.randf_range(0.35, 0.9)
		_strafe = -_strafe if g.rng.randf() < 0.7 else _strafe
	var dirn := to / maxf(dist, 1.0)
	var mv: Vector2 = dirn.orthogonal() * _strafe * (0.25 + 0.75 * mech01)
	if dist < want * 0.6:
		mv -= dirn
	elif dist > want * 1.1:
		mv += dirn * 0.6
	h.ctl_move = mv.limit_length(1.0)
	# don't strafe into a wall
	if g.terrain != null and g.terrain.blocked(h.position + h.ctl_move * 40.0, h.radius):
		_strafe = -_strafe
		h.ctl_move = (dirn.orthogonal() * _strafe).limit_length(1.0)
