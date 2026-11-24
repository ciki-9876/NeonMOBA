extends RefCounted
## Team brain: one per team. Reads the whole fight and publishes a shared plan that every
## hero AI on the team follows (the player is counted as an ally but never commanded):
##   intent  : group (form up) / fight / hold (wait for respawns) / retreat
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
		if h.targetable():
			foes.append(h)
	if allies.is_empty():
		intent = "hold"
		return
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
	my_power = _power(allies)
	their_power = _power(near_foes)
	var total_foes := _power(foes)
	# ---- intent
	var dist := c.distance_to(ec)
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
		"fight":
			front = lead
		"hold":
			front = home.lerp(Vector2.ZERO, 0.35)
		"retreat":
			front = home
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
	var idx: int = int(h.get_instance_id() % 3) - 1
	match h.role():
		"tank":
			return front + enemy_dir * (60.0 if intent == "fight" else 0.0)
		"carry":
			var rng: float = minf(h.atk_range() * 0.8, 380.0)
			return front + back * maxf(120.0, rng) + side * 90.0 * float(idx)
	return front + back * 360.0 + side * 70.0 * float(idx)

func in_danger(a) -> bool:
	return peel.has(a) or (float(a.hp) / float(a.max_hp) < 0.4 and g.t - float(a.last_hurt) < 1.5)
