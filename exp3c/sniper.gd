extends Node2D
## 3C experiment hero: 鹰隼 — ranged sniper, WASD movement, mouse aim.
##   LMB (hold)   脉冲弹  skillshot toward the cursor, no homing
##   RMB (hold)   蓄力狙击 charge up to 1.5 s, the camera pulls back while charging; release to fire a piercing round
##   Q  战术翻滚  short roll in the move direction, keeps the charge; next basic shot is a loaded round
##   E  震爆雷    lobbed grenade: knockback + slow, sets up charged shots
##   R  天穹之眼  8 s: wider view, charge twice as fast, full-charge shots explode and mark
## All numbers are here so the experiment is easy to tune.

const SPEED := 320.0
const RADIUS := 18.0
const ATK_INTERVAL := 0.42
const ATK_DMG := 42.0
const ATK_SPEED := 1500.0
const ATK_RANGE := 820.0
const ATK_SPREAD := 0.035          # radians (± random)
const CHARGE_TIME := 1.5
const CHARGE_MOVE := 0.45          # move speed multiplier while charging
const SNIPE_MIN := 0.15            # releasing below this cancels
const SNIPE_DMG := [70.0, 300.0]   # min / full charge
const PERFECT_MULT := 1.25         # full charge: 「完美一击」
const SNIPE_SPEED := 3200.0
const SNIPE_RANGE := [950.0, 1900.0]
const SNIPE_CD := 0.8
const ROLL_DIST := 240.0
const ROLL_TIME := 0.18
const ROLL_CD := 5.0
const LOADED_WINDOW := 3.0
const MINE_CD := 9.0
const MINE_RANGE := 560.0
const MINE_R := 150.0
const MINE_DMG := 60.0
const EYE_CD := 45.0
const EYE_TIME := 8.0

var arena
var aim_dir := Vector2.RIGHT
var atk_cd := 0.0
var snipe_cd := 0.0
var charging := false
var charge := 0.0                  # 0..1
var roll_t := 0.0
var roll_dir := Vector2.ZERO
var loaded_t := 0.0                # Q: next basic attack is loaded
var cds := {"q": 0.0, "e": 0.0, "r": 0.0}
var eye_t := 0.0                   # R active
var recoil := 0.0
var _rmb_was := false

func eye_on() -> bool:
	return eye_t > 0.0

func step(d: float, inp: Dictionary) -> void:
	for k in cds:
		cds[k] = maxf(0.0, float(cds[k]) - d)
	atk_cd = maxf(0.0, atk_cd - d)
	snipe_cd = maxf(0.0, snipe_cd - d)
	loaded_t = maxf(0.0, loaded_t - d)
	eye_t = maxf(0.0, eye_t - d)
	recoil = maxf(0.0, recoil - d * 30.0)
	var to_m: Vector2 = inp["mouse"] - position
	if to_m.length() > 4.0:
		aim_dir = to_m.normalized()
	# ---- movement
	var mv: Vector2 = inp["move"]
	if roll_t > 0.0:
		roll_t -= d
		position += roll_dir * (ROLL_DIST / ROLL_TIME) * d
	else:
		var spd := SPEED * (CHARGE_MOVE if charging else 1.0)
		position += mv * spd * d
	position = arena.clamp_in(position, RADIUS)
	# ---- RMB charge (paused while rolling, kept through the roll)
	var rmb: bool = inp["rmb"]
	if rmb and not _rmb_was and snipe_cd <= 0.0:
		charging = true
		charge = 0.0
		arena.sfx("learn", 0.8, -10.0)
	if charging and roll_t <= 0.0:
		var ct := CHARGE_TIME * (0.5 if eye_on() else 1.0)
		var before := charge
		charge = minf(1.0, charge + d / ct)
		if before < 1.0 and charge >= 1.0:
			arena.sfx("zap", 1.4, -6.0)
	if charging and not rmb:
		charging = false
		if charge >= SNIPE_MIN:
			_snipe()
		charge = 0.0
	_rmb_was = rmb
	# ---- LMB basic attack (not while charging)
	if inp["lmb"] and not charging and atk_cd <= 0.0 and roll_t <= 0.0:
		_basic()

func _muzzle() -> Vector2:
	return position + aim_dir * (RADIUS + 16.0)

func _basic() -> void:
	atk_cd = ATK_INTERVAL
	recoil = 4.0
	var loaded := loaded_t > 0.0
	loaded_t = 0.0
	var dir := aim_dir.rotated(0.0 if loaded else randf_range(-ATK_SPREAD, ATK_SPREAD))
	arena.spawn_bullet({"pos": _muzzle(), "vel": dir * ATK_SPEED * (1.3 if loaded else 1.0), "r": 7.0 if loaded else 5.0,
		"dmg": ATK_DMG * (2.0 if loaded else 1.0), "range": ATK_RANGE, "pierce": 2 if loaded else 1, "kind": "loaded" if loaded else "basic"})
	arena.sfx("attack" if not loaded else "lance", randf_range(1.15, 1.3), -8.0)

func _snipe() -> void:
	snipe_cd = SNIPE_CD
	recoil = 14.0
	var c := charge
	var perfect := c >= 1.0
	var dmg: float = lerpf(SNIPE_DMG[0], SNIPE_DMG[1], pow(c, 1.3)) * (PERFECT_MULT if perfect else 1.0)
	arena.spawn_bullet({"pos": _muzzle(), "vel": aim_dir * SNIPE_SPEED, "r": 6.0 + 4.0 * c, "dmg": dmg,
		"range": lerpf(SNIPE_RANGE[0], SNIPE_RANGE[1], c), "pierce": 99 if perfect else 1 + int(c * 2.0),
		"kind": "perfect" if perfect else "snipe", "explode": perfect and eye_on()})
	arena.stats["snipe_fired"] += 1
	arena.add_shake(10.0 if perfect else 5.0)
	arena.sfx("lance", 0.7 if perfect else 0.9, -2.0 if perfect else -5.0)

func cast(s: String, inp: Dictionary) -> void:
	if float(cds[s]) > 0.0:
		arena.toast("技能冷却中")
		return
	match s:
		"q":
			var mv: Vector2 = inp["move"]
			roll_dir = mv.normalized() if mv.length() > 0.1 else -aim_dir
			roll_t = ROLL_TIME
			loaded_t = LOADED_WINDOW
			cds["q"] = ROLL_CD
			arena.sfx("dash", 1.2, -6.0)
		"e":
			var to: Vector2 = inp["mouse"]
			if position.distance_to(to) > MINE_RANGE:
				to = position + (to - position).normalized() * MINE_RANGE
			arena.spawn_mine(position, to)
			cds["e"] = MINE_CD
			arena.sfx("whistle", 1.3, -8.0)
		"r":
			eye_t = EYE_TIME
			cds["r"] = EYE_CD
			arena.sfx("rune", 0.8, -4.0)

func _draw() -> void:
	var c := Color(0.4, 2.0, 2.4)
	var roll := roll_t > 0.0
	var body_r := RADIUS * (0.8 if roll else 1.0)
	# laser sight while charging (spread cone narrows with charge)
	if charging:
		var rng: float = lerpf(SNIPE_RANGE[0], SNIPE_RANGE[1], charge)
		var spread: float = lerpf(0.10, 0.0, charge)
		var lc := Color(2.6, 0.4, 0.5, 0.25 + 0.6 * charge) if charge < 1.0 else Color(3.0, 2.4, 0.6, 0.95)
		var m := aim_dir * (RADIUS + 16.0)
		draw_line(m, aim_dir * rng, lc, 1.0 + 2.0 * charge)
		if spread > 0.002:
			draw_line(m, aim_dir.rotated(spread) * rng * 0.6, Color(lc.r, lc.g, lc.b, 0.25), 1.0)
			draw_line(m, aim_dir.rotated(-spread) * rng * 0.6, Color(lc.r, lc.g, lc.b, 0.25), 1.0)
		draw_arc(Vector2.ZERO, RADIUS + 14.0, -PI / 2.0, -PI / 2.0 + TAU * charge, 40, lc, 4.0)
	if eye_on():
		draw_arc(Vector2.ZERO, RADIUS + 22.0, 0, TAU, 40, Color(2.4, 1.6, 0.4, 0.5), 2.0)
	# body: rounded hull + long barrel toward the cursor
	draw_circle(Vector2.ZERO, body_r, Color(0.05, 0.10, 0.16, 1.0))
	draw_arc(Vector2.ZERO, body_r, 0, TAU, 32, c, 3.0)
	var b0 := aim_dir * (body_r - 4.0 - recoil)
	var b1 := aim_dir * (body_r + 26.0 - recoil)
	draw_line(b0, b1, Color(0.8, 2.2, 2.6), 5.0)
	draw_line(b1 - aim_dir * 4.0, b1 + aim_dir * 3.0, Color(2.6, 2.6, 2.6), 3.0)
	var side := aim_dir.orthogonal()
	draw_line(side * 6.0, side * 6.0 + aim_dir * 10.0, Color(c.r, c.g, c.b, 0.7), 2.0)
	draw_line(-side * 6.0, -side * 6.0 + aim_dir * 10.0, Color(c.r, c.g, c.b, 0.7), 2.0)
	if loaded_t > 0.0:
		draw_circle(b1, 5.0, Color(2.8, 2.0, 0.6))
