extends Node2D
## Simulation of one match: units, combat, rules, spawning. Runs without any view/UI (headless).
## (split out of the old monolithic main.gd — see docs/架构说明.md)

const C = preload("res://game/consts.gd")
const Unit = preload("res://unit.gd")
const Hero = preload("res://hero.gd")
const HeroAI = preload("res://hero_ai.gd")
const TeamAI = preload("res://team_ai.gd")
const HeroesDB = preload("res://heroes_db.gd")
const ItemsDB = preload("res://items_db.gd")
const Grid = preload("res://view/grid.gd")
const Ring = preload("res://view/ring.gd")
const Rounds = preload("res://game/rounds.gd")
const Profiles = preload("res://game/profiles.gd")
const RunesDB = preload("res://game/runes_db.gd")
const Terrain = preload("res://game/terrain.gd")
const Maps = preload("res://game/maps.gd")

signal world_cleared
signal match_started
signal match_ended(win: bool)
signal round_started(n: int)
signal round_live(n: int)
signal round_ended(n: int, winner: int, reason: String)

## optional presentation / UI modules (null when running headless)
var vw = null
var hd = null
var shp = null

## fixed simulation step: the match always advances in DT slices, so results only depend on the seed
const DT := 1.0 / 60.0
var seed_used := 0
var next_uid := 0
## round-mode rules (game/rounds.gd); null in the other modes
var rounds = null
## terrain of the current map (game/terrain.gd); null = open ground (survival / old arena)
var terrain = null
var map_id := ""
## per team: hero uid -> visible to that team (brush), recomputed every step
var _vis := [{}, {}]

# ============================================================ state
var state := C.S.MENU
var mode := C.M.ROUNDS
var paused := false
var rng := RandomNumberGenerator.new()
var TEX := {}
var layer_trails: Node2D
var layer_heroes: Node2D
var player: Hero = null
var heroes: Array = []
## 3C: ranged basic attacks — straight projectiles, not homing: {owner, team, pos, dir, speed, left, dmg, info, r, trail}
var bolts: Array = []
var team0: Array = []
var god := false
var autopilot := false
var sfx_origin := Vector2.INF
# run
var t := 0.0
var shake := 0.0
var hitstop := 0.0
var dead_timer := 0.0
var team_kills := [0, 0]
var first_blood := false
var winner := -1
var difficulty := 1
var brains := {}
var last_cfg := {}
## display names of team 0 / team 1 (league matches pass the real team names)
var team_names := ["霓虹队", "赤潮队"]
func _slice(path: String, rows: Array) -> void:
	var atlas: Texture2D = load(path)
	var y := 0
	for r in rows:
		var at := AtlasTexture.new()
		at.atlas = atlas
		at.region = Rect2(0, y, r[1] * r[3], r[2])
		TEX[r[0]] = at
		if r[3] == 2:
			var f0 := AtlasTexture.new()
			f0.atlas = atlas
			f0.region = Rect2(0, y, r[1], r[2])
			TEX[r[0] + "_0"] = f0
		y += r[2] + 1

func _load_assets() -> void:
	_slice("res://art/sprites.png", C.ATLAS_ROWS)
	_slice("res://art/sprites2.png", C.ATLAS2_ROWS)
	_slice("res://art/heroes.png", C.HERO_ROWS)
	_slice("res://art/heroes2.png", C.HERO_ROWS2)
	_slice("res://art/heroes3.png", C.HERO_ROWS3)
	_slice("res://art/heroes4.png", C.HERO_ROWS4)
	var icons: Texture2D = load("res://art/items.png")
	var order: Array = ItemsDB.ORDER
	for i in order.size():
		var at := AtlasTexture.new()
		at.atlas = icons
		at.region = Rect2((i % C.ICON_COLS) * 24, (i / C.ICON_COLS) * 24, 24, 24)
		TEX["it_" + str(order[i])] = at

# ============================================================ flow
func _clear_world() -> void:
	_init_once()
	next_uid = 0
	for n in heroes:
		if is_instance_valid(n):
			n.queue_free()
	heroes.clear()
	for c in layer_trails.get_children():
		c.queue_free()
	bolts.clear()
	team0.clear()
	player = null
	rounds = null
	terrain = null
	brains = {}
	autopilot = false
	world_cleared.emit()

func _make_hero(id: String, tm: int, is_player: bool, diff: int) -> Hero:
	var h := Hero.new()
	h.uid = next_uid
	next_uid += 1
	layer_heroes.add_child(h)
	h.setup(self, id, tm, is_player)
	layer_trails.add_child(h.trail)
	heroes.append(h)
	if not is_player:
		var ai := HeroAI.new()
		ai.setup(h, self, diff)
		h.ai = ai
	return h

func _begin_common() -> void:
	t = 0.0
	shake = 0.0
	hitstop = 0.0
	team_kills = [0, 0]
	first_blood = false
	winner = -1
	state = C.S.PLAY
	paused = false
	match_started.emit()
	sfx("levelup", 0.8, -4.0)

## "随机" slots pick a hero for the role the team is still missing (tank / carry / support)
func _fill_random(lst: Array) -> void:
	var have := {}
	for id in lst:
		if id != "":
			have[HeroesDB.HEROES[id]["role"]] = true
	for i in lst.size():
		if lst[i] != "":
			continue
		var want := ""
		for r in ["tank", "support", "carry"]:
			if not have.has(r):
				want = r
				break
		var pool := []
		for id in HeroesDB.ORDER:
			if want == "" or HeroesDB.HEROES[id]["role"] == want:
				pool.append(id)
		var pick: String = str(pool[rng.randi() % pool.size()])
		lst[i] = pick
		have[HeroesDB.HEROES[pick]["role"]] = true

## round-based 3V3 (stage 1 core mode).
## setup (all optional):
##   "profiles": [[p, p, p], [p, p, p]]  players per team (game/profiles.gd); default = from difficulty
##   "runes":    [{hero_id: {rune_id: stacks}}, {...}]   team rune pages (game/runes_db.gd)
##   "human":    false to let the AI play every hero (headless simulation)
func _start_rounds(a: Array, b: Array, diff: int, match_seed := -1, setup := {}) -> void:
	_clear_world()
	reseed(match_seed)
	mode = C.M.ROUNDS
	difficulty = diff
	last_cfg = {"mode": C.M.ROUNDS, "a": a, "b": b, "diff": diff, "setup": setup}
	map_id = str(setup.get("map", Maps.DEFAULT))
	if not Maps.MAPS.has(map_id):
		map_id = Maps.DEFAULT
	terrain = Terrain.new()
	terrain.setup(Maps.MAPS[map_id], C.ARENA_R)
	_vis = [{}, {}]
	var human: bool = bool(setup.get("human", true))
	team_names = setup.get("team_names", ["霓虹队", "赤潮队"])
	var profs: Array = setup.get("profiles", [[], []])
	var runes: Array = setup.get("runes", [{}, {}])
	for tm in 2:
		var ids: Array = a if tm == 0 else b
		for i in ids.size():
			var hid := str(ids[i])
			var is_p: bool = tm == 0 and i == 0
			var h := _make_hero(hid, tm, is_p and human, diff)
			var tp: Array = profs[tm] if tm < profs.size() else []
			h.profile = tp[i] if i < tp.size() else Profiles.from_difficulty(diff)
			var page: Dictionary = (runes[tm] if tm < runes.size() else {}).get(hid, {})
			var mods: Array = RunesDB.rune_mods(page, hid)
			mods.append_array(RunesDB.signature_mods(Profiles.signature(h.profile, hid), hid))
			h.apply_mods(mods)
			if h.ai != null:
				h.ai.apply_profile(h.profile)
			if is_p:
				player = h
	brains = {0: TeamAI.new(), 1: TeamAI.new()}
	brains[0].setup(self, 0)
	brains[1].setup(self, 1)
	team_kills = [0, 0]
	rounds = Rounds.new()
	rounds.setup(self)
	rounds.start_map()
	_begin_common()
	if not human:
		set_autopilot(true)
	toast("回合制 3V3：先赢 %d 个回合获胜。每回合开局有购买时间；第 %d 秒起中央核心开放，站在核心里且没有对手争夺就会推进占领进度，占满或全歼对手即赢下回合。" % [Rounds.ROUNDS_TO_WIN, int(Rounds.CORE_UNLOCK)], Color(0.7, 0.95, 1.0), 10.0)
	toast("回合内阵亡不会复活；没有升级，只有装备成长。赢一回合 +%d，输一回合 +%d 起（每多连败一回合 +%d），输掉的一方可以原价卖出一件装备。" % [int(Rounds.WIN_PAY), int(Rounds.LOSS_PAY_BASE), int(Rounds.LOSS_PAY_STEP)], Color(1.0, 0.9, 0.4), 10.0)

## telegraphed areas and skillshots of the other team, for AI dodging (kit.threats())
func threats_for(tm: int) -> Array:
	var out := []
	for h in heroes:
		if h.team != tm:
			out.append_array(h.kit.threats())
	out.append_array(bolt_threats(tm))
	return out

## the team objective for the AI brain (round mode); {} when there is none
func objective(tm: int) -> Dictionary:
	if rounds == null or rounds.phase != "live":
		return {}
	var core: Vector2 = rounds.core_pos()
	var home := home_pos(tm)
	var mine: float = rounds.capture[tm]
	var theirs: float = rounds.capture[1 - tm]
	var urgency := 0.0
	if rounds.core_open():
		urgency = 0.5
		if theirs >= 0.35 or (rounds.time_left() < 20.0 and mine <= theirs) or rounds.phase_t >= Rounds.OVERTIME_AT:
			urgency = 1.0
	return {"pos": core, "open": rounds.core_open(), "urgency": urgency,
		"stage": core + (home - core).normalized() * (Rounds.CORE_R + 140.0)}

func _restart() -> void:
	_start_rounds(last_cfg["a"], last_cfg["b"], int(last_cfg["diff"]), -1, last_cfg.get("setup", {}))

func _end(win: bool) -> void:
	state = C.S.END
	dead_timer = 0.0
	if win:
		sfx("levelup", 0.7)
	else:
		sfx("boom", 0.8)
		shake = 20.0
	match_ended.emit(win)

# ============================================================ hero API (used by hero.gd, kits and the AI)
func clamp_pos(p: Vector2, r := 16.0) -> Vector2:
	if p.length() > C.ARENA_R - r:
		p = p.normalized() * (C.ARENA_R - r)
	if terrain != null:
		p = terrain.push_out(p, r)
	return p

## line of sight between two points (terrain blocks it)
func has_los(a: Vector2, b: Vector2) -> bool:
	return terrain == null or terrain.has_los(a, b)

## does terrain occupy this point? (skillshots stop here)
func blocked_at(p: Vector2) -> bool:
	return terrain != null and terrain.blocked(p, 0.0)

# ------------------------------------------------------------ brush visibility (草丛)
## a hero standing in brush is hidden from the other team, unless one of them is in the same brush
## or very close, or it attacked / cast in the last 1.2 s
func visible_to(u, tm: int) -> bool:
	if terrain == null or u.team == tm or not bool(u.is_hero):
		return true
	return bool(_vis[tm].get(u.uid, true))

func _update_vis() -> void:
	if terrain == null:
		return
	for tm in 2:
		var d := {}
		for u in heroes:
			if u.team != tm:
				d[u.uid] = _compute_vis(u, tm)
		_vis[tm] = d

## 3C: a team sees what is inside the vision radius of any of its living heroes (shared vision);
## inside that, brush still hides (see visible_to)
func _compute_vis(u, tm: int) -> bool:
	if u.dead:
		return true
	var in_sight := false
	for v in heroes:
		if v.team == tm and not v.dead and v.position.distance_to(u.position) <= v.vision():
			in_sight = true
			break
	if not in_sight:
		return false
	var b: int = terrain.brush_at(u.position)
	if b < 0 or t - float(u.revealed_t) < 1.2:
		return true
	for v in heroes:
		if v.team == tm and not v.dead and (terrain.brush_at(v.position) == b or v.position.distance_to(u.position) < 150.0):
			return true
	return false

# ------------------------------------------------------------ 3C basic attacks
## foes (any team but tm) whose body touches the swing arc: within reach of p and inside the cone around dir
func foes_in_arc(tm: int, p: Vector2, dir: Vector2, reach: float, arc: float) -> Array:
	var out := []
	for u in foes_in(tm, p, reach):
		var rel: Vector2 = u.position - p
		var dl := rel.length()
		if dl < 1.0:
			out.append(u)
			continue
		# angular half-size of the body widens the cone slightly
		var slack: float = asin(clampf(float(u.radius) / dl, 0.0, 1.0))
		if absf(dir.angle_to(rel)) <= arc * 0.5 + slack and has_los(p, u.position):
			out.append(u)
	return out

func spawn_bolt(h, p: Vector2, dir: Vector2, dmg: float, info: Dictionary) -> void:
	bolts.append({"owner": h, "team": h.team, "pos": p, "dir": dir, "speed": h.proj_speed(), "left": h.bolt_reach(),
		"dmg": dmg, "info": info, "r": 8.0, "trail": p, "start": p, "range": h.atk_range(),
		"pierce": int(h.sp().get("pierce", 0)), "hit": []})
	sfx("attack", rng.randf_range(1.1, 1.3), -10.0)

func _update_bolts(d: float) -> void:
	if bolts.is_empty():
		return
	var keep := []
	for b in bolts:
		var p0: Vector2 = b["pos"]
		var step: float = minf(float(b["speed"]) * d, float(b["left"]))
		var p1: Vector2 = p0 + b["dir"] * step
		b["left"] = float(b["left"]) - step
		b["trail"] = p0
		var done := float(b["left"]) <= 0.0
		if terrain != null and terrain.seg_blocked(p0, p1, 0.0):
			p1 = terrain.sweep(p0, p1, 1.0)
			done = true
		var hit = null
		var best := 1e9
		for u in foes_in(int(b["team"]), p0.lerp(p1, 0.5), step * 0.5 + float(b["r"]) + 40.0):
			if (b["hit"] as Array).has(u):
				continue
			var cp: Vector2 = Geometry2D.get_closest_point_to_segment(u.position, p0, p1)
			if cp.distance_to(u.position) <= float(u.radius) + float(b["r"]):
				var along: float = p0.distance_to(cp)
				if along < best:
					best = along
					hit = u
		if hit != null:
			(b["hit"] as Array).append(hit)
			if int(b["pierce"]) > 0:
				b["pierce"] = int(b["pierce"]) - 1   # 穿甲弹匣: keeps flying through the first target
			else:
				p1 = hit.position
				done = true
			var o = b["owner"]
			if o != null and is_instance_valid(o):
				var far: bool = (b["start"] as Vector2).distance_to(hit.position) > float(b["range"])
				var hinfo: Dictionary = b["info"]
				hinfo["far"] = far
				o.attack_hit(hit, float(b["dmg"]), hinfo)
				if bool(hit.is_hero):
					o.stat_add("atk_hit")
					hit.stat_add("atk_taken")
		b["pos"] = p1
		if not done:
			keep.append(b)
	bolts = keep

## AI: basic-attack projectiles flying at team tm (for dodging), same format as kit threats()
func bolt_threats(tm: int) -> Array:
	var out := []
	for b in bolts:
		if int(b["team"]) != tm:
			out.append({"kind": "shot", "pos": b["pos"], "dir": b["dir"], "w": float(b["r"]) * 2.0, "speed": float(b["speed"]), "left": float(b["left"]), "bolt": true})
	return out

func reveal(u) -> void:
	u.revealed_t = t

## the foes a team can actually see (AI perception, auto-acquire)
func seen_foes(tm: int, p: Vector2, r: float) -> Array:
	var out := []
	for u in foes_in(tm, p, r):
		if visible_to(u, tm):
			out.append(u)
	return out

func home_pos(tm: int) -> Vector2:
	return Vector2(-1000.0 if tm == 0 else 1000.0, 0.0)

func arena_center() -> Vector2:
	return Vector2.ZERO

func foes_in(tm: int, p: Vector2, r: float) -> Array:
	var out := []
	for h in heroes:
		if h.team != tm and h.targetable() and p.distance_to(h.position) < r + h.radius:
			out.append(h)
	return out

func foes_all(tm: int) -> Array:
	var out := []
	for h in heroes:
		if h.team != tm and h.targetable():
			out.append(h)
	return out

func nearest_foe(tm: int, p: Vector2, max_d: float):
	var best_u = null
	var bd := max_d
	for u in seen_foes(tm, p, max_d):
		var dd: float = p.distance_to(u.position) - u.radius
		if dd < bd:
			bd = dd
			best_u = u
	return best_u

func nearest_foe_hero(tm: int, p: Vector2):
	var best_u = null
	var bd := 1e9
	for h in heroes:
		if h.team == tm or not h.targetable() or not visible_to(h, tm):
			continue
		var dd: float = p.distance_to(h.position)
		if dd < bd:
			bd = dd
			best_u = h
	return best_u

func allies_of(hh) -> Array:
	var out := []
	for h in heroes:
		if h != hh and h.team == hh.team and not h.dead:
			out.append(h)
	return out

func team_focus(tm: int, u) -> int:
	var n := 0
	for h in heroes:
		if h.team != tm or h.dead:
			continue
		if h.ai != null and h.ai.target == u:
			n += 1
	return n

func _team_heroes(tm: int) -> Array:
	var out := []
	for h in heroes:
		if h.team == tm and h.targetable():
			out.append(h)
	return out

func on_level_up(h) -> void:
	if h.is_player and mode != C.M.ROUNDS:   # round mode sets the level at map start: no fanfare
		sfx("levelup", 1.0, -3.0)
		_ring(h.position, 10, 180, 0.5, Color(1.8, 1.6, 0.4), 8)
		_popup(h.position + Vector2(-40, -60), "LEVEL %d" % h.level, "big")
		if h.level in [6, 12, 18]:
			toast("等级 %d：大招「%s」可以升级了！" % [h.level, h.sdef["r"]["name"]], Color(1.0, 0.6, 1.0), 5.0)

func on_hero_cast(_h, _s: String) -> void:
	pass

func item_chain(h, first, bounces: int, dmg: float) -> void:
	var hit := {}
	var cur = first
	var prev: Vector2 = first.position
	for i in bounces + 1:
		if cur == null:
			break
		hit[cur] = true
		_bolt(prev, cur.position, Color(0.8, 1.8, 2.8))
		if not cur.dead:
			damage(h, cur, dmg, "proc", "magic")
		prev = cur.position
		var nxt = null
		var bd := 500.0
		for o in foes_in(h.team, prev, 500.0):
			if hit.has(o):
				continue
			var dd: float = prev.distance_to(o.position)
			if dd < bd:
				bd = dd
				nxt = o
		cur = nxt
	sfx("zap", rng.randf_range(1.1, 1.4), -10.0, 0.08)

## damage that gets through x points of def / res: 100 / (100 + x); negative values amplify
func def_mult(x: float) -> float:
	return 100.0 / (100.0 + x) if x >= 0.0 else 2.0 - 100.0 / (100.0 - x)

func armor_mult(a: float) -> float:
	return def_mult(a)

func brain(tm: int):
	return brains.get(tm, null)

func allies_in(tm: int, p: Vector2, r: float) -> Array:
	var out := []
	for h in heroes:
		if h.team == tm and not h.dead and p.distance_to(h.position) < r + h.radius:
			out.append(h)
	return out

## skill heals: src is the casting hero (skill power and 支援信标 apply); lifesteal passes src = null
func heal(src, tgt, amount: float) -> void:
	if tgt == null or not is_instance_valid(tgt) or tgt.dead or amount <= 0.0:
		return
	amount *= 1.0 - tgt.buff_v("grievous")
	if src != null and is_instance_valid(src) and src.is_hero:
		amount *= src.support_mult()
	var before: float = tgt.hp
	tgt.hp = minf(tgt.max_hp, tgt.hp + amount)
	var done: float = tgt.hp - before
	if src != null and is_instance_valid(src) and src.is_hero:
		src.heal_done += done
		if done >= 1.0:
			_popup(tgt.position + Vector2(0, -tgt.radius - 10.0), "+%d" % int(done), "heal", src.is_player or tgt.is_player, 10.0)

## forced movement (hooks, vortex pulls). Heroes are carried by their dash; creeps snap.
func displace(u, dest: Vector2, speed: float) -> void:
	if u == null or not is_instance_valid(u) or u.dead:
		return
	if u.is_hero:
		u.start_dash(dest, speed, Callable())
	else:
		u.position = dest

## the one damage entry point for every source (heroes, creeps, zones, items)
func damage(src, tgt, amount: float, kind: String, dtype := "magic", kb := Vector2.ZERO, is_attack := false) -> float:
	if tgt == null or not is_instance_valid(tgt) or tgt.dead or tgt.invuln > 0.0:
		return 0.0
	var src_hero: bool = src != null and is_instance_valid(src) and src.is_hero
	var a := amount
	var skill_dmg: bool = kind in ["skill", "dot", "chain"]
	if src_hero and skill_dmg:
		a *= src.pow_mult()
	if dtype == "phys":
		a *= def_mult(tgt.armor_val())
	elif dtype == "magic":
		a *= def_mult(tgt.mr_val())
	a *= tgt.dmg_taken_mult()
	if src_hero and kind == "skill" and tgt.is_hero:
		var gv: Array = src.sp().get("grievous", [])
		if not gv.is_empty():
			tgt.add_buff("grievous", float(gv[1]), float(gv[0]), src)
		# 屏障发生器: the first skill hit each round raises a shield before the damage lands
		var ssh: float = float(tgt.sp().get("spell_shield", 0.0))
		if ssh > 0.0 and not tgt.spell_shield_used:
			tgt.spell_shield_used = true
			tgt.add_barrier(ssh, 4.0)
	if tgt.barrier > 0.0:
		var absorbed: float = minf(a, tgt.barrier)
		tgt.barrier -= absorbed
		a -= absorbed
		if a <= 0.0:
			tgt.flash = 0.04
			return 0.0
	var show: bool = kind not in ["dot", "enemy"] and src_hero and src.is_player
	if show:
		var ls := "set"
		var txt := str(int(a))
		if kind == "skill": ls = "skill"
		elif kind == "chain" or kind == "proc": ls = "chain"
		elif kind == "crit":
			ls = "crit"
			txt += "!"
		_popup(tgt.position + Vector2(0, -tgt.radius), txt, ls, true, 12.0)
	if tgt.is_hero:
		if tgt.god or (tgt.is_player and god):
			return 0.0
		tgt.hp -= a
		tgt.stat_add("dmg_taken", a)
		tgt.stat_add("taken_" + dtype, a)
		if src_hero:
			src.stat_add("dmg_hero", a)
			var vamp: float = float(src.sp().get("spell_vamp", 0.0))
			if vamp > 0.0 and skill_dmg:
				heal(null, src, a * vamp)
			var bf = brain(src.team)
			if bf != null and bf.focus == tgt:
				src.stat_add("focus_dmg", a)
		tgt.log_damage(src)
		tgt.last_hurt = t
		if kind != "dot":
			tgt.flash = 0.06
		if tgt.is_player and tgt.hurt_cd <= 0.0 and kind != "dot":
			tgt.hurt_cd = 0.35
			sfx("hurt", rng.randf_range(0.9, 1.1), -8.0)
			if a > tgt.max_hp * 0.04:
				_flash(Color(1.0, 0.1, 0.25, 0.1 + minf(0.2, a / tgt.max_hp)))
				shake = maxf(shake, 5.0)
		if tgt.hp <= 0.0:
			_hero_died(tgt, src)
		return a
	return 0.0

# ============================================================ hero death & arena rules
func _hero_died(v, killer) -> void:
	if v.dead:
		return
	v.hp = 0.0
	var c: Color = v.team_color()
	_burst(v.position, c, 50, 480.0, 0.9, 4.0)
	_ring(v.position, 20, 360, 0.7, c, 10)
	sfx("boom", 0.9, -4.0)
	v.die()
	v.deaths += 1
	v.streak = 0
	var k = null
	if killer != null and is_instance_valid(killer) and killer.is_hero and killer.team != v.team:
		k = killer
	var helpers := []
	var newest := -1.0
	for key in v.dmg_log:
		var entry: Array = v.dmg_log[key]
		var hh = entry[0]
		if not is_instance_valid(hh) or t - float(entry[1]) > 12.0:
			continue
		if k == null and float(entry[1]) > newest:
			newest = float(entry[1])
		if hh != k:
			helpers.append(hh)
	if k == null and not helpers.is_empty():
		for hh in helpers:
			if float(v.dmg_log[hh.get_instance_id()][1]) >= newest:
				k = hh
		helpers.erase(k)
	v.dmg_log = {}
	var kt: int = 1 - int(v.team)
	team_kills[kt] += 1
	if k != null:
		k.kills += 1
		k.streak += 1
	for hh in helpers:
		hh.assists += 1
	rounds.on_hero_killed(v, k, helpers)
	_kill_feed(v, k, kt)

func _kill_feed(v, k, kt: int) -> void:
	var kname: String = k.display_name() if k != null else "环境"
	var who_k: String = ("你" if k != null and k.is_player else kname)
	var who_v: String = ("你" if v.is_player else v.display_name())
	var fc := Color(0.5, 1.6, 1.8) if kt == 0 else Color(2.0, 0.55, 0.55)
	_feed("%s %s 击倒了 %s %s" % [("霓虹" if kt == 0 else "赤潮"), who_k, ("赤潮" if kt == 0 else "霓虹"), who_v], fc)
	if not first_blood:
		first_blood = true
		_announce("第一滴血！", Color(1.0, 0.3, 0.35), 1.4)
	elif k != null and k.streak in [3, 5, 7]:
		_announce({3: "%s 势不可挡！", 5: "%s 主宰比赛！", 7: "%s 超神了！"}[k.streak] % who_k, fc, 1.4)
	if v.is_player:
		_flash(Color(0.6, 0.0, 0.1, 0.35))
		shake = 14.0

func _separate_heroes() -> void:
	for i in heroes.size():
		var a = heroes[i]
		if a.dead or not a.dash.is_empty():
			continue
		for j in range(i + 1, heroes.size()):
			var b = heroes[j]
			if b.dead or not b.dash.is_empty():
				continue
			var dv: Vector2 = a.position - b.position
			var dl := dv.length()
			var minl: float = (a.radius + b.radius) * 0.85
			if dl < minl and dl > 0.01:
				var push := dv / dl * (minl - dl) * 0.5
				a.position = clamp_pos(a.position + push, a.radius)
				b.position = clamp_pos(b.position - push, b.radius)

# ============================================================ survival timeline & spawning
# ============================================================ creeps (survival)
func _apply_auras() -> void:
	for h in heroes:
		h.ac_v = 0.0
		h.shiva_v = 0.0
	for h in heroes:
		if h.dead: continue
		var aura: Array = h.sp().get("as_aura", [])
		if aura.is_empty(): continue
		for u in foes_in(h.team, h.position, float(aura[1])):
			u.shiva_v = maxf(u.shiva_v, float(aura[0]))

# ============================================================ projectiles & zones
# ============================================================ shop & inventory (works for any hero)
func _plan_cost(id: String, avail: Array) -> int:
	var it: Dictionary = ItemsDB.DB[id]
	var comps: Array = it["comps"]
	if comps.is_empty():
		return int(it["cost"])
	var c: int = int(it["recipe"])
	for comp in comps:
		var i := avail.find(comp)
		if i >= 0:
			avail.remove_at(i)
		else:
			c += _plan_cost(comp, avail)
	return c

## consumed on purchase (no inventory slot): 特化芯片
func is_consumed_item(id: String) -> bool:
	return (ItemsDB.DB[id]["special"] as Dictionary).has("shard")

func shop_price_for(h, id: String) -> int:
	if is_consumed_item(id):
		return int(ItemsDB.DB[id]["cost"])
	return _plan_cost(id, h.inv.duplicate())

func inv_after(h, id: String) -> int:
	var avail: Array = h.inv.duplicate()
	_plan_cost(id, avail)
	return avail.size() + 1

func sell_cheapest(h) -> void:
	var bi := -1
	var bc := 1e9
	for i in h.inv.size():
		var c := float(ItemsDB.DB[h.inv[i]]["cost"])
		if c < bc:
			bc = c
			bi = i
	if bi >= 0:
		sell_for(h, bi)

## returns "" on success, otherwise the reason
## returns "" on success, otherwise the reason
func buy_for(h, id: String, verbose: bool) -> String:
	var it: Dictionary = ItemsDB.DB[id]
	if rounds != null:
		var why: String = rounds.shop_block_reason()
		if why != "":
			return why
	var spc: Dictionary = it["special"]
	if is_consumed_item(id):
		if h.shard_owned:
			return "已经装配过特化芯片"
		if h.gold < float(it["cost"]):
			return "金钱不足"
		h.gold -= float(it["cost"])
		h.shard_owned = true
		h.recalc()
		if verbose:
			sfx("pickup", 1.3, -4.0)
			toast("装配 %s：%s" % [it["name"], str(h.def.get("shard_note", it["note"]))], Color(0.6, 1.0, 0.6), 3.0)
		return ""
	if spc.has("scepter") and h.inv.has(id):
		return "已经拥有终极协议"
	var avail: Array = h.inv.duplicate()
	var cost := _plan_cost(id, avail)
	if avail.size() + 1 > 6:
		return "物品栏已满（右键物品可出售）"
	if h.gold < float(cost):
		return "金钱不足（还差 %d）" % int(cost - h.gold)
	h.gold -= float(cost)
	var used: int = h.inv.size() - avail.size()
	h.inv = avail
	h.inv.append(id)
	h.recalc()
	if verbose:
		sfx("rune", 1.1, -6.0)
		toast(("合成 %s" if used > 0 else "购买 %s") % it["name"], Color(1.0, 0.85, 0.3), 3.0)
	return ""

func sell_for(h, i: int) -> float:
	if i >= h.inv.size(): return 0.0
	if rounds != null and rounds.shop_block_reason() != "": return 0.0
	var id: String = h.inv[i]
	var v := float(ItemsDB.DB[id]["cost"]) * 0.5
	if rounds != null and h.refund_tokens > 0:
		h.refund_tokens -= 1
		v = float(ItemsDB.DB[id]["cost"])
	h.gold += v
	h.inv.remove_at(i)
	h.recalc()
	return v


# ============================================================ setup & fixed-step loop
func _ready() -> void:
	_init_once()

var _inited := false
## load textures and build the unit layers (also called lazily, e.g. by the headless runner before _ready)
func _init_once() -> void:
	if _inited:
		return
	_inited = true
	_load_assets()
	_build_layers()

func _build_layers() -> void:
	layer_trails = Node2D.new()
	add_child(layer_trails)
	layer_heroes = Node2D.new()
	add_child(layer_heroes)

## seed the match RNG; s < 0 picks a random seed. Returns the seed actually used (for replays / bug reports).
func reseed(s: int) -> int:
	if s < 0:
		s = randi() & 0x7fffffff
	rng.seed = s
	seed_used = s
	return s

## advance the match by one fixed step (DT). Everything that changes game state happens in here.
## let the AI drive the player's hero (F6 in game; always on in headless simulation)
func set_autopilot(on: bool) -> void:
	autopilot = on
	if on and player != null and player.ai == null:
		var ai := HeroAI.new()
		ai.setup(player, self, maxi(difficulty, 1))
		if not player.profile.is_empty():
			ai.apply_profile(player.profile)
		player.ai = ai

func step(d: float) -> void:
	if state == C.S.PLAY:
		t += d
		rounds.update(d)
	elif state == C.S.END:
		dead_timer += d
		d *= 0.3
	else:
		return
	team0 = _team_heroes(0)
	_update_vis()
	_apply_auras()
	if state == C.S.PLAY:
		for tm in brains:
			brains[tm].update(d)
		for h in heroes:
			if h.ai != null and (not h.is_player or autopilot):
				h.ai.update(d)
	for h in heroes:
		sfx_origin = h.position if not h.is_player else Vector2.INF
		h.update(d)
		h.kit.tick_world(d)
	sfx_origin = Vector2.INF
	_update_bolts(d)
	_separate_heroes()

# ============================================================ forwarding stubs
# Presentation/UI calls made by the simulation. They do nothing when the match runs headless.
func _announce(text: String, col: Color, dur := 1.6) -> void:
	if hd != null:
		hd._announce(text, col, dur)

func _bolt(a: Vector2, b: Vector2, col := Color(2.4, 2.2, 0.8)) -> void:
	if vw != null:
		vw._bolt(a, b, col)

func _burst(pos: Vector2, col: Color, amount := 14, spd := 300.0, life := 0.5, scl := 3.0) -> void:
	if vw != null:
		vw._burst(pos, col, amount, spd, life, scl)

func _feed(text: String, col: Color) -> void:
	if hd != null:
		hd._feed(text, col)

func _flash(c: Color) -> void:
	if hd != null:
		hd._flash(c)

func _popup(pos: Vector2, text: String, style := "set", always := true, jitter := 0.0) -> void:
	if vw != null:
		vw._popup(pos, text, style, always, jitter)

func _ring(pos: Vector2, r0: float, r1: float, life: float, col: Color, width: float) -> void:
	if vw != null:
		vw._ring(pos, r0, r1, life, col, width)

func add_shake(v: float, src) -> void:
	if vw != null:
		vw.add_shake(v, src)

func beam_fx(a: Vector2, b: Vector2, col: Color, scl := 1.0) -> void:
	if vw != null:
		vw.beam_fx(a, b, col, scl)

func ghost(h, p: Vector2, col: Color) -> void:
	if vw != null:
		vw.ghost(h, p, col)

func grid_pulse(v: float) -> void:
	if vw != null:
		vw.grid_pulse(v)

func sfx(n: String, pitch := 1.0, vol := 0.0, min_gap := 0.0) -> void:
	if vw != null:
		vw.sfx(n, pitch, vol, min_gap)

func slash_fx(h, tgt, strong: bool) -> void:
	if vw != null:
		vw.slash_fx(h, tgt, strong)

func swing_fx(h, dir: Vector2, strong: bool) -> void:
	if vw != null:
		vw.swing_fx(h, dir, strong)

func toast(text: String, col := Color.WHITE, dur := 4.0) -> void:
	if hd != null:
		hd.toast(text, col, dur)

func x_slash_fx(p: Vector2, col: Color) -> void:
	if vw != null:
		vw.x_slash_fx(p, col)
