extends RefCounted
## Team brain: one per team. Reads the whole fight and publishes a shared plan that every
## hero AI on the team follows (the player is counted as an ally but never commanded):
##   intent  : group (form up) / fight / hold (wait for respawns) / retreat / setup (hold the line until the objective opens)
##   focus   : the enemy hero the whole team should burst
##   peel    : ally -> the diver that is on top of it (tanks & supports react)
##   engage_ok : whether the backline may commit (the frontline is in, or we are being dived)
##   front   : where the frontline stands; carries and supports form up behind it

var g
var team := 0
var t := 0.0
var intent := "group"
var focus = null
var peel := {}
var engage_ok := false
var front := Vector2.ZERO
var enemy_dir := Vector2.RIGHT
var my_power := 0.0
var their_power := 0.0
var _judge := 1.0
var _judge_t := 0.0
## terrain: staging lane chosen each round, enemy memory (brush), brush to check
var lane := 0
var _lane_round := -1
var lane_brush := -1
var last_seen := {}        # enemy uid -> [position, time]
var ghosts := []           # alive enemies we can't see but remember: [[unit, last_pos], ...]
var check_pos := Vector2.INF
var aware01 := 0.5
var _check_brush := false    # this round: does the team scout brush when enemies are unaccounted for?

func setup(game, tm: int) -> void:
	g = game
	team = tm

func _alive(tm: int) -> Array:
	var out := []
	for h in g.heroes:
		if h.team == tm and not h.dead:
			out.append(h)
	return out

func _centroid(list: Array, fallback: Vector2) -> Vector2:
	if list.is_empty():
		return fallback
	var c := Vector2.ZERO
	for h in list:
		c += h.position
	return c / float(list.size())

## rough Lanchester-style strength: total effective hp × total dps
func _power(list: Array) -> float:
	var hp := 0.0
	var dps := 0.0
	for h in list:
		hp += (float(h.hp) + float(h.barrier)) / maxf(0.25, h.armor_mult(h.armor_val()))
		dps += h.atk_dmg() / maxf(h.atk_interval(), 0.2) + float(h.level) * 6.0
		for s in ["q", "w", "r"]:
			if h.sdef[s]["type"] != "passive" and int(h.sk[s]) > 0 and float(h.cds[s]) <= 0.0:
				dps += float(h.kit.est_damage(s)) * 0.12 + float(h.kit.est_heal(s)) * 0.08
	return hp * dps

func update(d: float) -> void:
	t -= d
	if t > 0.0:
		return
	t = 0.3
	var allies := _alive(team)
	var foes := []
	for h in _alive(1 - team):
		if h.targetable() and g.visible_to(h, team):
			foes.append(h)
	if allies.is_empty():
		intent = "hold"
		return
	_update_memory(allies, foes)
	var home: Vector2 = g.home_pos(team)
	var c := _centroid(allies, home)
	var ec := _centroid(foes, g.home_pos(1 - team))
	enemy_dir = (ec - c).normalized()
	if enemy_dir == Vector2.ZERO:
		enemy_dir = (g.home_pos(1 - team) - home).normalized()
	# power near the fight
	var near_foes := []
	for f in foes:
		if f.position.distance_to(c) < 1300.0:
			near_foes.append(f)
	# remembered (hidden) enemies still count: an aware team doesn't forget who went into the brush
	var near_ghosts := []
	var all_ghosts := []
	for gh in ghosts:
		all_ghosts.append(gh[0])
		if (gh[1] as Vector2).distance_to(c) < 1300.0:
			near_ghosts.append(gh[0])
	my_power = _power(allies)
	their_power = _power(near_foes + near_ghosts)
	# decision: the team's read of a fight is noisy (average of its players' decision error)
	var err := 0.0
	for a in allies:
		if a.ai != null:
			err += float(a.ai.decide_err)
	err /= maxf(1.0, float(allies.size()))
	if g.t >= _judge_t:
		_judge_t = g.t + 3.0
		_judge = exp(g.rng.randfn(0.0, err * 1.2))
	my_power *= _judge
	var total_foes := _power(foes + all_ghosts)
	# ---- intent
	var dist := c.distance_to(ec)
	var obj: Dictionary = g.objective(team)
	if foes.is_empty():
		intent = "group"
	elif my_power < their_power * 0.4 and not near_foes.is_empty():
		intent = "retreat"
	elif dist < 1100.0 and my_power >= their_power * 0.8:
		intent = "fight"
	elif allies.size() < foes.size() and my_power < total_foes * 0.9:
		intent = "hold"
	else:
		intent = "group" if dist > 900.0 else "fight"
	if not obj.is_empty():
		# round mode: nobody respawns, so never "hold"; when the objective is urgent, contest it
		if intent == "hold":
			intent = "group"
		if bool(obj["open"]) and float(obj["urgency"]) >= 1.0 and not foes.is_empty():
			intent = "fight"
		elif not bool(obj["open"]) and intent != "retreat":
			# before the core opens: hold the staging line, only take clearly favourable fights
			intent = "fight" if (not near_foes.is_empty() and my_power >= their_power * 1.3) else "setup"
	# ---- frontline position
	var tank = null
	for h in allies:
		if h.role() == "tank":
			tank = h
			break
	var lead: Vector2 = tank.position if tank != null else c + enemy_dir * 80.0
	match intent:
		"group":
			# advance together toward the middle / the enemy, but stay compact
			front = c.lerp(ec, 0.35) if not foes.is_empty() else c.lerp(Vector2.ZERO, 0.6)
			if tank != null:
				front = front.lerp(lead, 0.5)
			if not obj.is_empty():
				front = _stage(obj) if not bool(obj["open"]) else obj["pos"]
		"setup":
			front = _stage(obj)
		"fight":
			front = lead
			if not obj.is_empty() and bool(obj["open"]):
				front = obj["pos"]
		"hold":
			front = home.lerp(Vector2.ZERO, 0.35)
		"retreat":
			front = home
			if not obj.is_empty():
				front = home.lerp(obj["stage"], 0.5)   # round mode: fall back, but stay in the fight
				if g.terrain != null:
					front = g.terrain.push_out(front, 30.0)
	# ---- focus target: low effective hp, disabled, squishy, close to our front
	var best = null
	var bs := -1e9
	for f in foes:
		var s := 200.0
		s -= (float(f.hp) + float(f.barrier)) / maxf(0.25, f.armor_mult(f.armor_val())) * 0.08
		s += 90.0 if f.disabled() or f.has_buff("root") else 0.0
		match f.role():
			"support": s += 45.0
			"carry": s += 35.0
		s -= f.position.distance_to(front) * 0.12
		if f == focus:
			s += 40.0
		if g.in_enemy_fountain(f.position, team):
			s -= 500.0
		if s > bs:
			bs = s
			best = f
	focus = best
	# ---- peel requests: divers on top of our backline
	peel = {}
	for a in allies:
		if a.role() == "tank":
			continue
		var diver = null
		var dd := 330.0
		for f in foes:
			var x: float = a.position.distance_to(f.position)
			if x < dd:
				dd = x
				diver = f
		if diver != null:
			peel[a] = diver
	# ---- may the backline commit?
	engage_ok = tank == null or not peel.is_empty()
	if tank != null and not engage_ok:
		for f in foes:
			if tank.position.distance_to(f.position) < 320.0 or f.disabled():
				engage_ok = true
				break

## where a hero of this role should stand right now
func slot(h) -> Vector2:
	var back := -enemy_dir
	var side := back.orthogonal()
	var idx: int = int(h.uid % 3) - 1
	var obj: Dictionary = g.objective(team)
	if intent == "setup" and lane_brush >= 0:
		# ambush lane: everybody hides inside the brush
		var bc: Vector2 = g.terrain.brush[lane_brush][0]
		var br: float = float(g.terrain.brush[lane_brush][1]) * 0.5
		match h.role():
			"tank": return bc + enemy_dir * br * 0.6
			"carry": return bc - enemy_dir * br * 0.3 + side * br * 0.8
		return bc - enemy_dir * br * 0.5 - side * br * 0.8
	if not obj.is_empty() and bool(obj["open"]) and intent != "retreat":
		# round mode, core open: everybody stands inside the core (capture needs presence)
		var core: Vector2 = obj["pos"]
		var r: float = float(g.rounds.CORE_R) * 0.55
		match h.role():
			"tank":
				return core + enemy_dir * r * 0.5
			"carry":
				return core + back * r * 0.6 + side * r * 0.7 * float(idx if idx != 0 else 1)
		return core + back * r + side * r * 0.5 * float(idx)
	match h.role():
		"tank":
			return front + enemy_dir * (60.0 if intent == "fight" else 0.0)
		"carry":
			var rng: float = minf(h.atk_range() * 0.8, 380.0)
			return front + back * maxf(120.0, rng) + side * 90.0 * float(idx)
	return front + back * 360.0 + side * 70.0 * float(idx)

# ------------------------------------------------------------ terrain: lanes, memory, brush checks
func _team_aware() -> float:
	var s := 0.0
	var n := 0
	for a in _alive(team):
		if a.ai != null:
			s += clampf(1.0 - float(a.ai.aware_noise) / 70.0, 0.0, 1.0)
			n += 1
	return s / float(n) if n > 0 else 0.5

## staging point for this round (lane choice); falls back to the map's default stage
func _stage(obj: Dictionary) -> Vector2:
	if g.terrain == null or g.terrain.stages.is_empty():
		return obj["stage"]
	var st: Array = g.terrain.stages_for(team)
	if g.rounds.round_n != _lane_round:
		_lane_round = g.rounds.round_n
		lane = _pick_lane(st.size())
		lane_brush = g.terrain.brush_at(st[lane])
		_check_brush = g.rng.randf() < aware01
		g.rounds.note_lane(team, lane)
	return st[lane]

## centre half the time; after a lost round, try something different (a better decision maker
## changes lanes more reliably), otherwise a coin flip between the two ambush flanks
func _pick_lane(n: int) -> int:
	if n <= 1:
		return 0
	var lost := false
	var h: Array = g.rounds.history
	if not h.is_empty() and int(h[h.size() - 1]["winner"]) != team:
		lost = true
	var prev := lane
	var r: float = g.rng.randf()
	var pick: int = 0 if r < 0.5 else (1 + g.rng.randi_range(0, n - 2))
	if lost and pick == prev and g.rng.randf() < 0.4 + 0.5 * aware01:
		pick = (prev + 1 + g.rng.randi_range(0, n - 2)) % n
	return pick

func _update_memory(allies: Array, foes: Array) -> void:
	if g.terrain == null:
		ghosts = []
		check_pos = Vector2.INF
		return
	aware01 = _team_aware()
	for f in foes:
		last_seen[f.uid] = [f.position, g.t]
	# memory span grows with awareness: 1.5 s (forgets at once) .. 7 s
	var span: float = lerpf(1.5, 7.0, aware01)
	ghosts = []
	check_pos = Vector2.INF
	var best_d := 1e9
	var c := _centroid(allies, g.home_pos(team))
	for e in _alive(1 - team):
		if foes.has(e) or not last_seen.has(e.uid):
			continue
		var ls: Array = last_seen[e.uid]
		if g.t - float(ls[1]) > span:
			continue
		ghosts.append([e, ls[0]])
		# someone vanished into a brush near us: the frontline goes to check it
		var b: int = g.terrain.brush_at(ls[0])
		if b >= 0:
			var bp: Vector2 = g.terrain.brush[b][0]
			var dd: float = bp.distance_to(c)
			if dd < 700.0 and dd < best_d:
				best_d = dd
				check_pos = bp
	# enemies we haven't seen at all (an ambush?): scout the nearest brush before the core opens
	if check_pos == Vector2.INF and _check_brush and foes.size() + ghosts.size() < _alive(1 - team).size():
		var obj: Dictionary = g.objective(team)
		if not obj.is_empty() and not bool(obj["open"]):
			for i in g.terrain.brush.size():
				var bp2: Vector2 = g.terrain.brush[i][0]
				var dd2: float = bp2.distance_to(c)
				if dd2 > 650.0 or dd2 >= best_d:
					continue
				var ours := false
				for a in allies:
					if g.terrain.brush_at(a.position) == i:
						ours = true
				if not ours:
					best_d = dd2
					check_pos = bp2

func in_danger(a) -> bool:
	return peel.has(a) or (float(a.hp) / float(a.max_hp) < 0.4 and g.t - float(a.last_hurt) < 1.5)
