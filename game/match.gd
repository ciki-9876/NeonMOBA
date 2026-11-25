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
const Enemy = preload("res://game/enemy.gd")
const HeroShot = preload("res://game/hero_shot.gd")
const EShot = preload("res://game/enemy_shot.gd")
const Grid = preload("res://view/grid.gd")
const Ring = preload("res://view/ring.gd")
const Rounds = preload("res://game/rounds.gd")
const Profiles = preload("res://game/profiles.gd")
const RunesDB = preload("res://game/runes_db.gd")

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

# ============================================================ state
var state := C.S.MENU
var mode := C.M.SURVIVAL
var paused := false
var rng := RandomNumberGenerator.new()
var TEX := {}
var boss_frames: SpriteFrames
var gem_frames: SpriteFrames
var layer_runes: Node2D
var layer_trails: Node2D
var layer_enemies: Node2D
var layer_heroes: Node2D
var layer_shots: Node2D
var player: Hero = null
var heroes: Array = []
var enemies: Array = []
var hshots: Array = []
var eshots: Array = []
var zones: Array = []
var runes: Array = []
var cells := {}
var bosses: Array = []
var seen_kinds := {}
var team0: Array = []
var god := false
var autopilot := false
var sfx_origin := Vector2.INF
# run
var t := 0.0
var kills := 0
var spawn_acc := 0.0
var event_i := 0
var next_rune := 120.0
var shake := 0.0
var hitstop := 0.0
var dead_timer := 0.0
var team_kills := [0, 0]
var first_blood := false
var winner := -1
var difficulty := 1
var brains := {}
var last_cfg := {}
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
	var icons: Texture2D = load("res://art/items.png")
	var order: Array = ItemsDB.ORDER
	for i in order.size():
		var at := AtlasTexture.new()
		at.atlas = icons
		at.region = Rect2((i % C.ICON_COLS) * 24, (i / C.ICON_COLS) * 24, 24, 24)
		TEX["it_" + str(order[i])] = at
	gem_frames = SpriteFrames.new()
	for i in 8:
		gem_frames.add_frame("default", load("res://art/gem_%d.png" % i))
	gem_frames.set_animation_speed("default", 10.0)
	boss_frames = SpriteFrames.new()
	for i in 16:
		boss_frames.add_frame("default", load("res://art/boss_%02d.png" % i))
	boss_frames.set_animation_speed("default", 14.0)

# ============================================================ flow
func _clear_world() -> void:
	_init_once()
	next_uid = 0
	for arr in [enemies, hshots, eshots, runes, heroes]:
		for n in arr:
			if is_instance_valid(n):
				n.queue_free()
		arr.clear()
	for c in layer_trails.get_children():
		c.queue_free()
	zones.clear()
	bosses.clear()
	seen_kinds.clear()
	team0.clear()
	player = null
	rounds = null
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
	kills = 0
	spawn_acc = 0.0
	event_i = 0
	next_rune = 120.0 if mode == C.M.SURVIVAL else 30.0
	shake = 0.0
	hitstop = 0.0
	team_kills = [0, 0]
	first_blood = false
	winner = -1
	state = C.S.PLAY
	paused = false
	match_started.emit()
	sfx("levelup", 0.8, -4.0)

func _start_survival(id: String, match_seed := -1) -> void:
	_clear_world()
	reseed(match_seed)
	mode = C.M.SURVIVAL
	last_cfg = {"mode": C.M.SURVIVAL, "hero": id}
	player = _make_hero(id, 0, true, 1)
	player.position = Vector2.ZERO
	player.face = -PI / 2
	_begin_common()
	toast("你有 1 个技能点：按 Ctrl+Q/W/E 或点击技能上方的「+」学习", Color(1.0, 0.9, 0.4), 7.0)
	toast("右键移动，对手靠近时会自动攻击。攻击前摇是青色光环，后摇是灰色光环（移动可取消后摇）", Color(0.7, 0.95, 1.0), 8.0)
	toast("按 B 打开商店（游戏暂停）：消灭对手获得金钱，购买装备强化英雄", Color(1.0, 0.85, 0.3), 8.0)
	toast("连招：%s" % player.def["combo"], Color(0.7, 1.0, 0.7), 9.0)

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

func _start_arena(a: Array, b: Array, diff: int, match_seed := -1) -> void:
	_clear_world()
	reseed(match_seed)
	mode = C.M.ARENA
	difficulty = diff
	last_cfg = {"mode": C.M.ARENA, "a": a, "b": b, "diff": diff}
	for tm in 2:
		var ids: Array = a if tm == 0 else b
		for i in ids.size():
			var h := _make_hero(str(ids[i]), tm, tm == 0 and i == 0, diff)
			h.hp_mult = 1.15
			h.regen_bonus = 0.5
			h.recalc()
			h.hp = h.max_hp
			var home := home_pos(tm)
			h.position = home + Vector2(0, (i - 1) * 60.0)
			h.face = (Vector2.ZERO - home).angle()
			if tm == 0 and i == 0:
				player = h
	brains = {0: TeamAI.new(), 1: TeamAI.new()}
	brains[0].setup(self, 0)
	brains[1].setup(self, 1)
	_begin_common()
	toast("3V3 竞技场：先拿到 %d 次击倒获胜。阵亡后在泉水复活，泉水会快速回复并灼烧来犯的对手。" % C.ARENA_KILLS, Color(0.7, 0.95, 1.0), 9.0)
	toast("你有 1 个技能点：Ctrl+Q/W/E 学习。B 打开商店（游戏暂停），Tab 查看计分板。", Color(1.0, 0.9, 0.4), 9.0)
	toast("连招：%s" % player.def["combo"], Color(0.7, 1.0, 0.7), 9.0)

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
	var human: bool = bool(setup.get("human", true))
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
	if last_cfg.get("mode", -1) == C.M.ROUNDS:
		_start_rounds(last_cfg["a"], last_cfg["b"], int(last_cfg["diff"]), -1, last_cfg.get("setup", {}))
		return
	if last_cfg.get("mode", -1) == C.M.ARENA:
		_start_arena(last_cfg["a"], last_cfg["b"], int(last_cfg["diff"]))
	else:
		_start_survival(str(last_cfg.get("hero", "drift")))

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
	if mode == C.M.ARENA and p.length() > C.ARENA_R - r:
		return p.normalized() * (C.ARENA_R - r)
	return p

func home_pos(tm: int) -> Vector2:
	return Vector2(-1000.0 if tm == 0 else 1000.0, 0.0)

func near_home(h) -> bool:
	return mode == C.M.ARENA and h.position.distance_to(home_pos(h.team)) < C.FOUNTAIN_R

func in_enemy_fountain(p: Vector2, tm: int) -> bool:
	return mode == C.M.ARENA and p.distance_to(home_pos(1 - tm)) < C.FOUNTAIN_R + 80.0

func arena_center() -> Vector2:
	return Vector2.ZERO

func foes_in(tm: int, p: Vector2, r: float) -> Array:
	var out := []
	if tm == 0 and not enemies.is_empty():
		for e in _query(p, r + 60.0) + _boss_list():
			if e.targetable() and p.distance_to(e.position) < r + e.radius:
				out.append(e)
	for h in heroes:
		if h.team != tm and h.targetable() and p.distance_to(h.position) < r + h.radius:
			out.append(h)
	return out

func foes_all(tm: int) -> Array:
	var out := []
	if tm == 0:
		for e in enemies:
			if e.targetable():
				out.append(e)
	for h in heroes:
		if h.team != tm and h.targetable():
			out.append(h)
	return out

func nearest_foe(tm: int, p: Vector2, max_d: float):
	var best_u = null
	var bd := max_d
	for u in foes_in(tm, p, max_d):
		var dd: float = p.distance_to(u.position) - u.radius
		if dd < bd:
			bd = dd
			best_u = u
	return best_u

func nearest_foe_hero(tm: int, p: Vector2):
	var best_u = null
	var bd := 1e9
	for h in heroes:
		if h.team == tm or not h.targetable():
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
		if h.cmd_target == u or (h.ai != null and h.ai.target == u):
			n += 1
	return n

func nearest_rune(p: Vector2, max_d: float):
	var best_p = null
	var bd := max_d
	for r in runes:
		var dd: float = p.distance_to(r.position)
		if dd < bd:
			bd = dd
			best_p = r.position
	return best_p

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

func spawn_hero_shot(h, tgt, dmg: float, info: Dictionary) -> void:
	var s := HeroShot.new()
	s.position = h.position + Vector2.from_angle(h.face) * 20.0
	s.owner_h = h
	s.target = tgt
	s.dmg = dmg
	s.info = info
	s.speed = float(h.def["proj_speed"])
	s.last_pos = tgt.position
	var proc: bool = bool(info.get("proc", false))
	var spr := Sprite2D.new()
	spr.texture = TEX["bullet"]
	spr.scale = Vector2(C.PIX, C.PIX) * (1.4 if proc else 1.0)
	if proc:
		spr.modulate = Color(2.4, 2.2, 0.6)
	elif h.team == 1:
		spr.modulate = Color(2.6, 0.8, 0.8)
	else:
		spr.modulate = Color(1.6, 2.4, 2.6)
	s.add_child(spr)
	layer_shots.add_child(s)
	hshots.append(s)
	_burst(h.position + Vector2.from_angle(h.face) * 24.0, Color(0.8, 2.4, 2.8) if h.team == 0 else Color(2.6, 0.8, 0.8), 6, 160.0, 0.15, 2.0)
	sfx("attack", rng.randf_range(0.95, 1.08), -8.0, 0.04)

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

func armor_mult(a: float) -> float:
	return 1.0 - (0.06 * a) / (1.0 + 0.06 * absf(a))

func brain(tm: int):
	return brains.get(tm, null)

func allies_in(tm: int, p: Vector2, r: float) -> Array:
	var out := []
	for h in heroes:
		if h.team == tm and not h.dead and p.distance_to(h.position) < r + h.radius:
			out.append(h)
	return out

func heal(src, tgt, amount: float) -> void:
	if tgt == null or not is_instance_valid(tgt) or tgt.dead or amount <= 0.0:
		return
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
	if tgt.is_hero and is_attack:
		var eva: float = float(tgt.ST.get("eva", 0.0))
		var true_strike: bool = src_hero and not (src.sp().get("mkb", []) as Array).is_empty()
		if eva > 0.0 and not true_strike and rng.randf() < eva:
			if tgt.is_player or (src_hero and src.is_player):
				_popup(tgt.position + Vector2(-20, -40), "闪避", "set")
			return 0.0
	if dtype == "phys":
		a *= armor_mult(tgt.armor_val())
	elif dtype == "magic":
		if src_hero:
			a *= 1.0 + float(src.ST.get("amp", 0.0))
		a *= 1.0 - tgt.mr_val()
	a *= tgt.dmg_taken_mult()
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
	tgt.hp -= a
	if kind != "dot":
		tgt.flash = 0.07
	if not tgt.boss and tgt.kind != "colossus":
		tgt.knock += kb * 140.0
	if tgt.hp <= 0.0:
		_kill(tgt, src)
	return a

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
	if mode == C.M.SURVIVAL:
		if v.is_player:
			shake = 26.0
			_end(false)
		return
	var victim_streak: int = v.streak
	v.streak = 0
	v.respawn_t = minf(40.0, 6.0 + v.level * 1.6)
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
	if mode == C.M.ROUNDS:
		rounds.on_hero_killed(v, k, helpers)
		_kill_feed(v, k, kt)
		return
	var bounty: float = 90.0 + v.level * 6.0 + minf(victim_streak, 6) * 40.0
	if team_kills[1 - kt] - team_kills[kt] >= 5:
		bounty *= 1.5  # comeback bounty for the team that is behind
	if k != null:
		k.gold += bounty
		if k.is_player:
			_popup(v.position + Vector2(-20, -50), "+%d" % int(bounty), "gold")
	for hh in helpers:
		hh.gold += 40.0 + v.level * 5.0
	# shared xp
	var share := []
	for h in heroes:
		if h.team == kt and not h.dead and (h == k or helpers.has(h) or h.position.distance_to(v.position) < 1300.0):
			share.append(h)
	var xp_total: float = 40.0 + v.level * 15.0
	if team_kills[1 - kt] > team_kills[kt]:
		xp_total *= 1.5
	for h in share:
		h.gain_xp(xp_total / float(share.size()) * 1.4 + xp_total * 0.15)
	_kill_feed(v, k, kt)
	if team_kills[kt] >= C.ARENA_KILLS:
		winner = kt
		_end(kt == 0)

func _kill_feed(v, k, kt: int) -> void:
	var kname: String = k.display_name() if k != null else ("泉水" if mode == C.M.ARENA else "环境")
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

func _update_arena(d: float) -> void:
	for h in heroes:
		if h.dead:
			h.respawn_t -= d
			if h.respawn_t <= 0.0:
				var home := home_pos(h.team)
				h.respawn(home + Vector2(rng.randf_range(-60, 60), rng.randf_range(-80, 80)))
				h.face = (Vector2.ZERO - home).angle()
				_ring(h.position, 10, 140, 0.5, h.team_color(), 8)
				if h.is_player:
					sfx("rune", 1.0, -4.0)
			continue
		h.gold += 4.0 * d
		h.gain_xp(4.5 * d)
		var own: float = h.position.distance_to(home_pos(h.team))
		if own < C.FOUNTAIN_R:
			h.hp = minf(h.max_hp, h.hp + h.max_hp * 0.06 * d)
			h.mana = minf(h.mana_max, h.mana + h.mana_max * 0.06 * d)
		if h.position.distance_to(home_pos(1 - h.team)) < C.FOUNTAIN_R:
			damage(null, h, 320.0 * d, "dot", "pure")
	if t >= next_rune:
		next_rune = t + 60.0
		for spot in C.RUNE_SPOTS:
			var taken := false
			for r in runes:
				if r.position.distance_to(spot) < 10.0:
					taken = true
			if not taken:
				_spawn_rune_at(spot)
	if t >= C.ARENA_LEN:
		if team_kills[0] != team_kills[1]:
			winner = 0 if team_kills[0] > team_kills[1] else 1
			_end(winner == 0)
		elif int(t) % 30 == 0 and t - d < floorf(t):
			_announce("加时：下一次击倒决定胜负", Color(1.0, 0.85, 0.3), 1.2)

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
func _hp_mult() -> float:
	var m := t / 60.0
	return 1.0 + m * 0.11 + pow(m / 10.0, 2.0) * 0.5

func _dmg_mult() -> float:
	return 1.0 + t / 60.0 * 0.06

func _update_timeline() -> void:
	while event_i < C.EVENTS.size() and t >= C.EVENTS[event_i][0]:
		var ev: String = C.EVENTS[event_i][1]
		event_i += 1
		match ev:
			"swarm": _swarm()
			"warn1", "warn2", "warn3":
				_announce("⚠ Boss 即将降临 ⚠", Color(1.0, 0.3, 0.85))
				sfx("warning")
			"boss1": _spawn_boss(1)
			"boss2": _spawn_boss(2)
			"boss3": _spawn_boss(3)
	if t >= next_rune:
		next_rune += 120.0
		_spawn_rune_at(player.position + Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(260.0, 420.0))

func _update_spawns(d: float) -> void:
	var x := t / C.GAME_LEN
	var rate := 0.4 + 2.2 * x + 2.4 * x * x
	if not bosses.is_empty():
		rate *= 0.6
	spawn_acc += d * rate
	while spawn_acc >= 1.0:
		spawn_acc -= 1.0
		if enemies.size() < C.MAX_ENEMIES:
			_spawn(_pick_kind(), _edge_pos())

func _count(kind: String) -> int:
	var n := 0
	for e in enemies:
		if e.kind == kind and not e.dead: n += 1
	return n

func _pick_kind() -> String:
	var m := t / 60.0
	var pool := [["grunt", maxf(4.0, 10.0 - m * 0.25)]]
	if m >= 1.5: pool.append(["dasher", 2.5])
	if m >= 2.5: pool.append(["splitter", 2.5])
	if m >= 3.5: pool.append(["shooter", 2.5])
	if m >= 5.0 and _count("sentry") < (3 if m < 20 else 5): pool.append(["sentry", 1.4])
	if m >= 5.0 and _count("frenzy") < 2: pool.append(["frenzy", 0.5])
	if m >= 7.0 and _count("colossus") < 4: pool.append(["colossus", 0.7])
	if m >= 7.0 and _count("mender") < 2: pool.append(["mender", 0.6])
	if m >= 9.0: pool.append(["bomber", 1.8])
	if m >= 12.0 and _count("aegis") < 2: pool.append(["aegis", 0.5])
	if m >= 15.0 and _count("hexer") < 3: pool.append(["hexer", 0.8])
	var total := 0.0
	for p in pool: total += p[1]
	var r := rng.randf() * total
	for p in pool:
		r -= p[1]
		if r <= 0.0: return p[0]
	return "grunt"

func _edge_pos() -> Vector2:
	var a := rng.randf() * TAU
	return player.position + Vector2.RIGHT.rotated(a) * rng.randf_range(760.0, 860.0)

func _swarm() -> void:
	var m := t / 60.0
	var n := 10 + int(m * 0.8)
	_announce("包 围 ！", Color(1.0, 0.35, 0.45), 1.2)
	var gap := rng.randi() % n
	for i in n:
		if absi(i - gap) <= 1 or absi(i - gap) >= n - 1:
			continue
		var kind := "grunt" if m < 8 or i % 3 != 0 else "splitter"
		_spawn(kind, player.position + Vector2.RIGHT.rotated(TAU * i / n) * 620.0)

func _spawn(kind: String, pos: Vector2, force_elite := false) -> Enemy:
	var def: Dictionary = C.EDEF[kind]
	var e := Enemy.new()
	e.uid = next_uid
	next_uid += 1
	e.kind = kind
	e.team = 1
	e.position = pos
	var hm := _hp_mult()
	e.max_hp = def["hp"] * hm
	e.speed = def["spd"] * rng.randf_range(0.92, 1.08)
	e.radius = def["r"]
	e.dmg = def["dmg"] * _dmg_mult()
	e.rate = def["rate"]
	e.arange = def["range"]
	e.armor = def.get("armor", 0.0)
	e.mr = def.get("mr", 0.0)
	e.gold = def.get("gold", 0.0)
	e.xp = def["xp"]
	e.aura = def.get("aura", "")
	e.base_col = def["col"]
	e.timer = rng.randf_range(0.5, 2.0)
	var m := t / 60.0
	if force_elite or (m >= 12.0 and kind not in ["mini", "bomber"] and rng.randf() < minf(0.2, 0.03 + (m - 12.0) * 0.01)):
		e.elite = true
		e.max_hp *= 3.5
		e.dmg *= 1.4
		e.xp *= 3.0
		e.armor += 4.0
		e.radius *= 1.3
	e.hp = e.max_hp
	var s := Sprite2D.new()
	if def.has("spr"):
		s.texture = TEX[def["spr"]]
	else:
		s.texture = TEX[def["spr2"]]
	s.hframes = 2
	s.scale = Vector2(C.PIX, C.PIX) * (1.3 if e.elite else 1.0)
	e.spr = s
	e.add_child(s)
	layer_enemies.add_child(e)
	enemies.append(e)
	if not seen_kinds.has(kind) and kind != "mini":
		seen_kinds[kind] = true
		if kind != "grunt":
			toast("新对手：%s — %s" % [def["name"], def["desc"]], def["col"].lightened(0.3), 7.0)
	return e

func _spawn_boss(tier: int) -> void:
	var e := Enemy.new()
	e.uid = next_uid
	next_uid += 1
	e.kind = "boss"
	e.team = 1
	e.boss = true
	e.tier = tier
	e.position = player.position + Vector2.RIGHT.rotated(rng.randf() * TAU) * 640.0
	e.max_hp = [9000.0, 24000.0, 60000.0][tier - 1]
	e.hp = e.max_hp
	e.speed = 95.0 + tier * 10.0
	e.radius = 92.0 * (1.0 + 0.12 * (tier - 1))
	e.dmg = 60.0 * _dmg_mult()
	e.xp = 600.0 * tier
	e.armor = 4.0 + 3.0 * tier
	e.mr = 0.25
	e.base_col = C.EDEF["boss"]["col"]
	e.timer = 2.0
	var a := AnimatedSprite2D.new()
	a.sprite_frames = boss_frames
	a.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	a.scale = Vector2.ONE * (1.25 + 0.15 * (tier - 1))
	if tier == 3:
		a.self_modulate = Color(1.4, 1.1, 0.5)
	a.play()
	e.spr = a
	e.add_child(a)
	layer_enemies.add_child(e)
	enemies.append(e)
	bosses.append(e)
	sfx("boss")
	_announce(["典狱长 降临", "典狱长·至尊 降临", "奇点之心 苏醒"][tier - 1], Color(1.0, 0.3, 0.85), 2.0)
	shake = 14.0

func _spawn_rune_at(pos: Vector2) -> void:
	var r := Node2D.new()
	r.position = pos
	var kind: String = ["heal", "haste", "dd"][rng.randi() % 3]
	r.set_meta("kind", kind)
	r.set_meta("life", 60.0 if mode == C.M.SURVIVAL else 9999.0)
	var a := AnimatedSprite2D.new()
	a.sprite_frames = gem_frames
	a.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	a.scale = Vector2(1.3, 1.3)
	a.modulate = {"heal": Color(0.6, 2.0, 0.8), "haste": Color(2.2, 0.6, 0.6), "dd": Color(0.6, 1.0, 2.4)}[kind]
	a.play()
	r.add_child(a)
	layer_runes.add_child(r)
	runes.append(r)
	if mode == C.M.SURVIVAL:
		toast("神符出现了：%s（右键走过去拾取）" % {"heal": "回复神符", "haste": "极速神符", "dd": "双倍伤害神符"}[kind], Color(0.7, 1.0, 0.8), 5.0)
	sfx("rune", 0.8, -6.0)

func _update_runes(d: float) -> void:
	var keep := []
	for r in runes:
		var life: float = r.get_meta("life") - d
		r.set_meta("life", life)
		var taker = null
		if state == C.S.PLAY:
			for h in heroes:
				if not h.dead and r.position.distance_to(h.position) < 44.0:
					taker = h
					break
		if taker != null:
			var kind: String = r.get_meta("kind")
			match kind:
				"heal":
					taker.hp = minf(taker.max_hp, taker.hp + taker.max_hp * 0.4)
					taker.mana = minf(taker.mana_max, taker.mana + taker.mana_max * 0.4)
				"haste": taker.haste_t = 20.0
				"dd": taker.dd_t = 20.0
			_ring(r.position, 10, 160, 0.5, Color(1.6, 2.0, 1.2), 8)
			var nm: String = {"heal": "回复神符：生命和魔法 +40%", "haste": "极速神符：移速大幅提升 20 秒", "dd": "双倍伤害神符：攻击伤害 ×2，持续 20 秒"}[kind]
			if taker.is_player:
				sfx("rune")
				toast(nm, Color(1.0, 1.0, 0.6), 3.0)
			elif mode == C.M.ARENA:
				_feed("%s 拿到了%s" % [taker.display_name(), nm.substr(0, 4)], Color(0.9, 0.9, 0.6))
			r.queue_free()
		elif life <= 0.0:
			r.queue_free()
		else:
			keep.append(r)
	runes = keep

# ============================================================ creeps (survival)
func _kill(e, src) -> void:
	e.dead = true
	kills += 1
	var c: Color = e.base_col * 2.2
	c.a = 1.0
	_burst(e.position, c, 14 if e.radius < 30 else 40, 300.0 if e.radius < 30 else 500.0, 0.45, 3.0)
	_ring(e.position, 6, e.radius * 2.4, 0.25, c, 5)
	sfx("explode", rng.randf_range(0.85, 1.2) * (0.7 if e.radius > 30 else 1.0), -9.0, 0.03)
	var bounty: float = e.gold * (1.0 + t / 1800.0 * 0.5) * (2.5 if e.elite else 1.0)
	if e.boss:
		bounty = 800.0 * e.tier
	var hh = src if (src != null and is_instance_valid(src) and src.is_hero) else player
	if hh != null and not hh.dead:
		hh.gain_xp(e.xp * (1.0 + t / 900.0))
		hh.gold += bounty
		if hh.is_player and bounty >= 1.0:
			_popup(e.position + Vector2(-10, -e.radius - 30), "+%d" % int(bounty), "gold")
	if e.kind == "splitter":
		for k in 2:
			var mm := _spawn("mini", e.position + Vector2(rng.randf_range(-14, 14), rng.randf_range(-14, 14)))
			mm.knock = Vector2.RIGHT.rotated(rng.randf() * TAU) * 260.0
	if e.boss:
		bosses.erase(e)
		_burst(e.position, Color(2.2, 0.5, 2.0), 80, 700.0, 1.2, 5.0)
		_ring(e.position, 20, 800, 1.0, Color(2.4, 0.6, 2.2), 16)
		_flash(Color(1, 0.6, 1, 0.6))
		sfx("boom")
		shake = 34.0
		hitstop = 0.3
		for s in eshots: s.dead = true
		for h in heroes:
			if not h.dead:
				h.hp = h.max_hp
				h.mana = h.mana_max
		_announce("%s 已击破" % _ename(e), Color(1.0, 0.6, 0.95))
		if e.tier == 3:
			_end(true)

func _ename(e) -> String:
	if e.is_hero:
		return e.display_name()
	if e.boss:
		return ["典狱长", "典狱长·至尊", "奇点之心"][e.tier - 1]
	return C.EDEF[e.kind]["name"]

func _rebuild_hash() -> void:
	cells.clear()
	for e in enemies:
		if e.dead or e.boss: continue
		var k := Vector2i(floori(e.position.x / C.CELL), floori(e.position.y / C.CELL))
		if cells.has(k): cells[k].append(e)
		else: cells[k] = [e]

func _query(p: Vector2, r: float) -> Array:
	var out := []
	var rc := int(ceil(r / C.CELL))
	var c := Vector2i(floori(p.x / C.CELL), floori(p.y / C.CELL))
	for x in range(c.x - rc, c.x + rc + 1):
		for y in range(c.y - rc, c.y + rc + 1):
			var k := Vector2i(x, y)
			if cells.has(k): out.append_array(cells[k])
	return out

func _boss_list() -> Array:
	var out := []
	for b in bosses:
		if not b.dead: out.append(b)
	return out

func _apply_auras() -> void:
	for e in enemies:
		e.frenzy = false
		e.shield = false
		e.ac_v = 0.0
		e.shiva_v = 0.0
	for h in heroes:
		h.ac_v = 0.0
		h.shiva_v = 0.0
	for h in heroes:
		if h.dead: continue
		var spx: Dictionary = h.sp()
		var acv: float = float(spx.get("ac_aura", 0.0))
		var shv: float = float(spx.get("shiva", 0.0))
		if acv <= 0.0 and shv <= 0.0: continue
		for u in foes_in(h.team, h.position, 900.0):
			u.ac_v = maxf(u.ac_v, acv)
			u.shiva_v = maxf(u.shiva_v, shv)
	for src in enemies:
		if src.dead or src.aura == "": continue
		for e in _query(src.position, 300.0) + _boss_list():
			if e.dead or e.position.distance_to(src.position) > 280.0: continue
			if src.aura == "frenzy": e.frenzy = true
			else: e.shield = true

func _creep_target(e):
	var tt = e.buff_src("taunt")
	if tt != null and not tt.dead:
		return tt
	var best_h = null
	var bd := 1e9
	for h in team0:
		var dd: float = e.position.distance_to(h.position)
		if dd < bd:
			bd = dd
			best_h = h
	return best_h

func _creep_hit(th, amount: float, dtype := "phys", evadable := false) -> void:
	if state != C.S.PLAY: return
	damage(null, th, amount, "enemy", dtype, Vector2.ZERO, evadable)

func _update_enemies(d: float) -> void:
	var tick := Time.get_ticks_msec() * 0.001
	for e in enemies:
		if e.dead: continue
		e.atk_cd -= d
		e.tick_status(d)
		var th = _creep_target(e)
		var to: Vector2 = (th.position - e.position) if th != null else Vector2.ZERO
		var dist := to.length()
		var dir := to / maxf(dist, 0.001)
		var spd: float = e.speed * (1.4 if e.frenzy else 1.0) * ((1.0 - e.slow_pct) if e.slow > 0.0 else 1.0)
		var dm: float = e.dmg * (1.4 if e.frenzy else 1.0)
		if e.stun > 0.0:
			e.vel = Vector2.ZERO
		elif th != null and state == C.S.PLAY:
			_enemy_ai(e, th, d, to, dist, dir, spd, dm)
			if e.has_buff("root"):
				e.vel = Vector2.ZERO
		else:
			e.vel = e.vel.move_toward(Vector2.ZERO, 400.0 * d)
		if not e.boss:
			for o in _query(e.position, e.radius + 30.0):
				if o == e or o.dead: continue
				var dv: Vector2 = e.position - o.position
				var dl := dv.length()
				var minl: float = (e.radius + o.radius) * 0.9
				if dl < minl and dl > 0.01:
					e.position += dv / dl * (minl - dl) * 0.3
		e.position += (e.vel + e.knock + e.pull) * d
		e.knock = e.knock.move_toward(Vector2.ZERO, 1200.0 * d)
		e.pull = Vector2.ZERO
		if th != null and dist > 1500.0 and not e.boss:
			e.position = th.position - dir * 820.0
		var spr: Node2D = e.spr
		if spr is Sprite2D:
			(spr as Sprite2D).frame = int(tick * 6.0 + e.get_instance_id()) % 2
			if e.kind in ["dasher", "sentry"]:
				spr.rotation = e.aim.angle()
			elif e.kind in ["frenzy", "aegis"]:
				spr.rotation = 0.0
			else:
				spr.rotation += d * (2.5 if e.radius < 30 else 0.5)
		var col: Color = e.base_col * 1.35
		col.a = 1.0
		if e.boss: col = Color(1.2, 1.2, 1.2)
		if e.elite: col = col.lerp(Color(2.2, 1.8, 0.6), 0.35)
		if e.kind == "dasher" and e.phase == 1 and int(tick * 24.0) % 2 == 0: col = Color(3.0, 2.6, 1.0)
		if e.kind == "bomber" and e.phase == 1 and int(tick * 20.0) % 2 == 0: col = Color(3.0, 1.5, 0.6)
		if e.charged > 0.0 and int(tick * 8.0) % 2 == 0: col = col.lerp(Color(0.6, 2.0, 2.4), 0.4)
		if e.mark > 0.0: col = col.lerp(Color(2.4, 0.3, 0.4), 0.3)
		if e.flash > 0.0: col = Color(2.4, 2.4, 2.4)
		if e.stun > 0.0: col = col * Color(0.7, 0.7, 0.8)
		spr.modulate = col

func _rate(e) -> float:
	return e.rate * (1.0 + e.shiva_v)

func _melee(e, th, dist: float, dm: float) -> void:
	if dist < e.arange + e.radius + th.radius and e.atk_cd <= 0.0:
		e.atk_cd = _rate(e)
		_creep_hit(th, dm, "phys", true)

func _enemy_ai(e, th, d: float, to: Vector2, dist: float, dir: Vector2, spd: float, dm: float) -> void:
	var hr: float = th.radius
	match e.kind:
		"grunt", "splitter", "mini":
			e.vel = dir * spd if dist > e.radius + hr else Vector2.ZERO
			_melee(e, th, dist, dm)
		"dasher":
			e.timer -= d
			if e.phase == 0:
				e.vel = dir * spd
				e.aim = dir
				if e.timer <= 0.0 and dist < 420.0:
					e.phase = 1
					e.timer = 0.6
				_melee(e, th, dist, dm * 0.5)
			elif e.phase == 1:
				e.vel = Vector2.ZERO
				e.aim = dir
				if e.timer <= 0.0:
					e.phase = 2
					e.timer = 0.4
			else:
				e.vel = e.aim * 720.0
				if dist < e.radius + hr + 8.0 and e.atk_cd <= 0.0:
					e.atk_cd = 1.0
					_creep_hit(th, dm, "phys", true)
				if e.timer <= 0.0:
					e.phase = 0
					e.timer = rng.randf_range(2.0, 3.0)
		"shooter":
			var strafe := dir.orthogonal() * (1.0 if e.uid % 2 == 0 else -1.0)
			if dist > e.arange: e.vel = dir * spd
			elif dist < e.arange * 0.65: e.vel = -dir * spd
			else: e.vel = strafe * spd * 0.6
			if e.atk_cd <= 0.0 and dist < e.arange + 60.0:
				e.atk_cd = _rate(e)
				_eshot(e.position, dir * 380.0, dm, "phys", true)
		"sentry":
			e.aim = dir
			if e.phase == 0:
				e.vel = dir * spd if dist > 560.0 else Vector2.ZERO
				if dist <= 600.0:
					e.phase = 1
					e.timer = 0.8
			else:
				e.vel = Vector2.ZERO
				e.timer -= d
				if dist > e.arange + 120.0:
					e.phase = 0
				elif e.timer <= 0.0:
					e.timer = e.rate
					var lead: Vector2 = th.position + th.vel * 0.7
					zones.append({"type": "artillery", "pos": lead, "r": 95.0, "t": 0.0, "delay": 1.25, "dmg": dm, "src": e.position})
					sfx("whistle", rng.randf_range(0.9, 1.1), -10.0, 0.3)
		"colossus":
			e.timer -= d
			if e.phase == 0:
				e.vel = dir * spd if dist > e.radius + hr else Vector2.ZERO
				if e.timer <= 0.0 and dist < 190.0:
					e.phase = 1
					e.timer = 1.0
					zones.append({"type": "slam", "pos": e.position, "r": 170.0, "t": 0.0, "delay": 1.0, "dmg": dm * 1.4, "owner": e})
				else:
					_melee(e, th, dist, dm)
			else:
				e.vel = Vector2.ZERO
				if e.timer <= 0.0:
					e.phase = 0
					e.timer = rng.randf_range(3.5, 5.0)
		"frenzy", "aegis":
			e.vel = dir * spd if dist > 300.0 else (-dir * spd * 0.5 if dist < 220.0 else Vector2.ZERO)
		"mender":
			e.vel = dir * spd if dist > 380.0 else (-dir * spd if dist < 280.0 else dir.orthogonal() * spd * 0.4)
			e.timer -= d
			if e.timer <= 0.0:
				e.timer = e.rate
				var healed := 0
				for o in _query(e.position, 280.0) + _boss_list():
					if o.dead or o.position.distance_to(e.position) > 260.0: continue
					if o.hp < o.max_hp:
						o.hp = minf(o.max_hp, o.hp + o.max_hp * (0.15 if not o.boss else 0.01))
						healed += 1
				if healed > 0:
					_ring(e.position, 20, 260, 0.6, Color(0.5, 2.2, 0.9), 6)
					sfx("mend", 1.0, -12.0, 0.4)
		"bomber":
			if e.phase == 0:
				e.vel = dir * spd
				if dist < e.arange:
					e.phase = 1
					e.timer = 0.7
					sfx("fuse", 1.0, -6.0, 0.1)
			else:
				e.vel = Vector2.ZERO
				e.timer -= d
				if e.timer <= 0.0:
					_bomber_explode(e, dm)
		"hexer":
			e.vel = dir * spd if dist > 480.0 else (-dir * spd if dist < 360.0 else dir.orthogonal() * spd * 0.4)
			e.timer -= d
			if e.timer <= 0.0 and dist < e.arange + 80.0:
				e.timer = e.rate
				zones.append({"type": "silence", "pos": th.position, "r": 150.0, "t": 0.0, "delay": 0.9, "dmg": 0.0})
				sfx("silence", 1.2, -10.0, 0.5)
		"boss":
			_boss_ai(e, th, d, dir, dist, spd, dm)

func _bomber_explode(e, dm: float) -> void:
	var r := 140.0
	for th in team0:
		if th.position.distance_to(e.position) < r + th.radius:
			_creep_hit(th, dm, "magic")
	for o in _query(e.position, r + 40.0):
		if o != e and not o.dead and o.position.distance_to(e.position) < r:
			damage(null, o, dm * 0.5, "enemy", "pure")
	_ring(e.position, 10, r, 0.35, Color(2.4, 1.4, 0.4), 10)
	_burst(e.position, Color(2.4, 1.4, 0.4), 30, 420.0, 0.5, 3.0)
	sfx("explode", 0.8, -2.0)
	shake = maxf(shake, 8.0)
	e.hp = 0.0
	e.dead = true
	kills += 1
	if player != null and not player.dead:
		player.gain_xp(e.xp * (1.0 + t / 900.0) * 0.5)

func _boss_ai(e, th, d: float, dir: Vector2, dist: float, spd: float, dm: float) -> void:
	e.vel = dir * (spd if dist > e.radius + 140.0 else 10.0)
	e.aim = dir
	if dist < e.radius + th.radius and e.atk_cd <= 0.0:
		e.atk_cd = 1.2
		_creep_hit(th, dm, "phys", true)
	e.timer -= d
	var enraged: bool = e.hp < e.max_hp * 0.5
	if e.timer <= 0.0:
		var n: int = 14 + e.tier * 4 + (6 if enraged else 0)
		var off: float = e.phase * 0.23
		for i in n:
			_eshot(e.position, Vector2.RIGHT.rotated(off + TAU * i / n) * (200.0 + 20.0 * e.tier), dm * 0.5)
		e.phase += 1
		e.timer = (1.8 if not enraged else 1.2) - 0.15 * (e.tier - 1)
		sfx("zap", 0.55, -4.0)
		grid_pulse(0.6)
		if e.tier >= 2 and e.phase % 4 == 0:
			var kinds := ["frenzy", "aegis", "mender"] if e.tier == 2 else ["bomber", "bomber", "bomber", "hexer"]
			for k in kinds:
				_spawn(k, e.position + Vector2.RIGHT.rotated(rng.randf() * TAU) * 140.0)
	if enraged or e.tier == 3:
		e.aux_t -= d
		if e.aux_t <= 0.0:
			e.aux_t = 0.12
			e.spin += 0.42
			for k in (3 if e.tier < 3 else 4):
				_eshot(e.position, Vector2.RIGHT.rotated(e.spin + TAU * k / 3.0) * 220.0, dm * 0.35)

func _eshot(pos: Vector2, v: Vector2, dmg: float, dtype := "magic", evadable := false) -> void:
	var b := EShot.new()
	b.position = pos
	b.vel = v
	b.dmg = dmg
	b.dtype = dtype
	b.evadable = evadable
	var s := Sprite2D.new()
	s.texture = TEX["ebullet"]
	s.scale = Vector2(C.PIX, C.PIX)
	s.modulate = Color(2.4, 0.8, 2.2)
	b.add_child(s)
	layer_shots.add_child(b)
	eshots.append(b)

# ============================================================ projectiles & zones
func _update_hshots(d: float) -> void:
	for s in hshots:
		if s.dead: continue
		var tv = s.target
		if tv == null or not is_instance_valid(tv) or tv.dead or tv.invuln > 0.0:
			# DOTA: the projectile still flies to the last known position, then fizzles
			s.position = s.position.move_toward(s.last_pos, s.speed * d)
			if s.position.distance_to(s.last_pos) < 4.0: s.dead = true
			continue
		s.last_pos = tv.position
		var to: Vector2 = tv.position - s.position
		s.rotation = to.angle()
		if to.length() < s.speed * d + tv.radius * 0.5:
			s.dead = true
			var ow = s.owner_h
			if ow != null and is_instance_valid(ow):
				ow.attack_hit(tv, s.dmg, s.info)
			_burst(tv.position - to.normalized() * tv.radius * 0.5, Color(1.5, 2.4, 2.6), 4, 180.0, 0.2, 2.0)
			sfx("ahit", rng.randf_range(0.9, 1.2), -12.0, 0.04)
		else:
			s.position += to.normalized() * s.speed * d

func _update_eshots(d: float) -> void:
	for b in eshots:
		if b.dead: continue
		b.position += b.vel * d
		b.life -= d
		b.rotation += d * 6.0
		if b.life <= 0.0:
			b.dead = true
			continue
		if state != C.S.PLAY: continue
		for th in team0:
			if b.position.distance_to(th.position) < th.radius + 9.0:
				b.dead = true
				_creep_hit(th, b.dmg, b.dtype, b.evadable)
				break

func _update_zones(d: float) -> void:
	var keep := []
	for z in zones:
		z["t"] += d
		if z["type"] == "slam":
			var owner = z.get("owner")
			if owner == null or not is_instance_valid(owner) or owner.dead or owner.stun > 0.0:
				continue  # interrupted by stun / death
		if z["t"] < z["delay"]:
			keep.append(z)
			continue
		var p: Vector2 = z["pos"]
		var r: float = z["r"]
		var inside := []
		if state == C.S.PLAY:
			for th in team0:
				if th.position.distance_to(p) < r + th.radius * 0.5:
					inside.append(th)
		match z["type"]:
			"artillery":
				for th in inside: _creep_hit(th, z["dmg"], "phys")
				_ring(p, 10, r, 0.3, Color(2.4, 1.2, 0.3), 8)
				_burst(p, Color(2.4, 1.2, 0.4), 18, 300.0, 0.4, 3.0)
				sfx("explode", 1.2, -8.0, 0.05)
			"slam":
				for th in inside:
					_creep_hit(th, z["dmg"], "phys")
					th.slow = 2.0
					th.slow_pct = 0.4
				_ring(p, 20, r, 0.4, Color(2.4, 0.8, 0.5), 12)
				_burst(p, Color(1.8, 0.8, 0.5), 24, 360.0, 0.5, 3.0)
				sfx("slam", 1.0, -2.0)
				shake = maxf(shake, 8.0)
			"silence":
				for th in inside:
					th.silence = 2.5
					if th.cmd == Hero.C.CAST:
						th.cmd = Hero.C.IDLE
					if th.is_player:
						_popup(th.position + Vector2(-30, -50), "沉默!", "set")
				_ring(p, r, 20, 0.3, Color(1.8, 0.6, 2.4), 6)
	zones = keep

func _cleanup() -> void:
	for arr_name in ["enemies", "hshots", "eshots"]:
		var arr: Array = get(arr_name)
		var keep := []
		for n in arr:
			if not is_instance_valid(n): continue
			if n.dead: n.queue_free()
			else: keep.append(n)
		set(arr_name, keep)

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

func shop_price_for(h, id: String) -> int:
	if ItemsDB.DB[id]["cat"] == "consumable":
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
func buy_for(h, id: String, verbose: bool) -> String:
	var it: Dictionary = ItemsDB.DB[id]
	if rounds != null:
		var why: String = rounds.shop_block_reason()
		if why != "":
			return why
		if it["cat"] == "consumable" and (it["special"] as Dictionary).has("c_xp"):
			return "回合制没有等级成长，不能使用经验书"
	if it["cat"] == "consumable":
		var spc: Dictionary = it["special"]
		if spc.has("shard") and h.shard_owned:
			return "已经使用过魔晶"
		if spc.has("moon") and h.moon_used:
			return "银月之晶只能使用一次"
		if h.gold < float(it["cost"]):
			return "金钱不足"
		h.gold -= float(it["cost"])
		_consume(h, spc)
		if verbose:
			sfx("pickup", 1.3, -4.0)
			var note: String = it["note"]
			if spc.has("shard"):
				note = str(h.def["shard_note"])
			toast("使用 %s：%s" % [it["name"], note], Color(0.6, 1.0, 0.6), 3.0)
	else:
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

func _consume(h, spc: Dictionary) -> void:
	if spc.has("c_hp"): h.regen_buffs.append({"hp": float(spc["c_hp"][0]), "t": float(spc["c_hp"][1])})
	if spc.has("c_mp"): h.regen_buffs.append({"mp": float(spc["c_mp"][0]), "t": float(spc["c_mp"][1])})
	if spc.has("c_mana_now"): h.mana = minf(h.mana_max, h.mana + float(spc["c_mana_now"]))
	if spc.has("c_xp"): h.gain_xp(h.xp_need() * float(spc["c_xp"]))
	if spc.has("shard"): h.shard_owned = true
	if spc.has("moon"):
		h.moon_used = true
		h.recalc()

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
	layer_runes = Node2D.new()
	add_child(layer_runes)
	layer_trails = Node2D.new()
	add_child(layer_trails)
	layer_enemies = Node2D.new()
	add_child(layer_enemies)
	layer_heroes = Node2D.new()
	add_child(layer_heroes)
	layer_shots = Node2D.new()
	add_child(layer_shots)

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
		if mode == C.M.SURVIVAL:
			_update_timeline()
			_update_spawns(d)
			if not player.dead:
				player.gold += 1.6 * d
			if t >= C.GAME_LEN:
				_end(true)
		elif mode == C.M.ROUNDS:
			rounds.update(d)
		else:
			_update_arena(d)
	elif state == C.S.END:
		dead_timer += d
		d *= 0.3
	else:
		return
	team0 = _team_heroes(0)
	_rebuild_hash()
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
	_separate_heroes()
	_update_enemies(d)
	_update_hshots(d)
	_update_eshots(d)
	_update_zones(d)
	_update_runes(d)
	_cleanup()

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

func toast(text: String, col := Color.WHITE, dur := 4.0) -> void:
	if hd != null:
		hd.toast(text, col, dur)

func x_slash_fx(p: Vector2, col: Color) -> void:
	if vw != null:
		vw.x_slash_fx(p, col)
