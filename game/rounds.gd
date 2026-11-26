extends RefCounted
## Round-based 3V3 rules (stage 1 core mode). Owned by game/match.gd while mode == C.M.ROUNDS.
##
## A map is won by the first team to win ROUNDS_TO_WIN rounds. Every round:
##   buy   (BUY_TIME s)  heroes are held inside their spawn, the shop is open, everyone is reset
##   live  (<= LIVE_MAX) the core in the middle unlocks after CORE_UNLOCK s; standing in it
##                       uncontested fills your capture bar. Full bar or wiping the enemy wins.
##                       From OVERTIME_AT capture is twice as fast; at LIVE_MAX the larger bar wins.
##   post  (POST_TIME s) result banner, payouts, then the next round
## Revives (2026-11-26): a hero killed in the live phase may start a REVIVE_TIME countdown and come back at its
## spawn with full hp / mana (cooldowns keep running, they are not refreshed). Each team has REVIVES_PER_MAP
## revives for the whole map; reviving is a choice (the player presses R, the AI decides in ai_wants_revive).
## A team with no hero standing (everyone dead or counting down) loses the round. New rounds revive for free.
## No levels, no creeps, no passive income: growth comes only from items.
## Map mechanics are meant to be swappable later (escort, crystals, ...): everything specific to the
## core lives in _update_core / core_* below.

const C = preload("res://game/consts.gd")

const ROUNDS_TO_WIN := 4
const BUY_TIME := 15.0
const FIRST_BUY_TIME := 25.0
const LIVE_MAX := 80.0
const CORE_UNLOCK := 20.0
const OVERTIME_AT := 60.0
const POST_TIME := 4.0
const CORE_R := 230.0
const CAPTURE_TIME := 8.0        # seconds of uncontested presence to fill the bar
const SPAWN_R := 170.0           # heroes are held inside this radius during the buy phase
const HERO_LEVEL := 12           # fixed hero level (no in-match levelling)
const HP_MULT := 0.55            # hero max hp multiplier in round mode (fight length knob). 2026-11-26: 0.8 -> 0.55 with the hit-rate pass and revives (TTK ~6.4 s -> ~5 s)
const START_GOLD := 3000.0
const WIN_PAY := 2000.0
const LOSS_PAY_BASE := 1500.0     # loss payout: 1500 / 2000 / 2500 / ... (+500 per consecutive loss)
const LOSS_PAY_STEP := 500.0

static func loss_pay(streak: int) -> float:
	return LOSS_PAY_BASE + LOSS_PAY_STEP * float(maxi(streak, 1) - 1)
const KILL_PAY := 150.0
const REVIVE_TIME := 10.0
const REVIVES_PER_MAP := 5
const ASSIST_PAY := 50.0

var g
var phase := "buy"
var phase_t := 0.0
var round_n := 0
var score := [0, 0]
var loss_streak := [0, 0]
var capture := [0.0, 0.0]
var last_winner := -1
var last_reason := ""
var lanes := [-1, -1]               # staging lane each team picked this round (team AI)
var history: Array = []          # [{round, winner, reason, time}]
var revives_left := [REVIVES_PER_MAP, REVIVES_PER_MAP]

func setup(game) -> void:
	g = game

func core_pos() -> Vector2:
	return Vector2.ZERO

func core_open() -> bool:
	return phase == "live" and phase_t >= CORE_UNLOCK

func time_left() -> float:
	match phase:
		"buy": return (FIRST_BUY_TIME if round_n == 1 else BUY_TIME) - phase_t
		"live": return LIVE_MAX - phase_t
	return POST_TIME - phase_t

func spawn_pos(tm: int, i: int) -> Vector2:
	var home: Vector2 = g.home_pos(tm)
	return home + Vector2(0, (i - 1) * 70.0)

## called once when the map starts (after the heroes exist)
func start_map() -> void:
	round_n = 0
	score = [0, 0]
	loss_streak = [0, 0]
	history = []
	revives_left = [REVIVES_PER_MAP, REVIVES_PER_MAP]
	for h in g.heroes:
		h.hp_mult = HP_MULT
		h.gold = START_GOLD
		while h.level < HERO_LEVEL:
			h.gain_xp(h.xp_need())
		auto_learn(h)
		h.refund_tokens = 0
	start_round()

## spend all skill points: ultimate whenever possible, then the hero's ai_learn order
func auto_learn(h) -> void:
	var guard := 0
	while h.skill_points > 0 and guard < 40:
		guard += 1
		if h.learn("r"):
			continue
		var done := false
		for s in h.def["ai_learn"]:
			if h.learn(str(s)):
				done = true
				break
		if not done:
			for s in ["q", "w", "e"]:
				if h.learn(s):
					done = true
					break
		if not done:
			break

var _kills_at_start := [0, 0]

func note_lane(tm: int, l: int) -> void:
	lanes[tm] = l

func start_round() -> void:
	round_n += 1
	_kills_at_start = g.team_kills.duplicate()
	lanes = [-1, -1]
	phase = "buy"
	phase_t = 0.0
	capture = [0.0, 0.0]
	var idx := [0, 0]
	g.bolts.clear()
	for h in g.heroes:
		var p := spawn_pos(h.team, idx[h.team])
		idx[h.team] += 1
		h.respawn(p)
		h.kit.round_reset()
		h.recalc()
		h.hp = h.max_hp
		h.mana = h.mana_max
		for s in h.cds:
			h.cds[s] = 0.0
		h.face = (core_pos() - p).angle()
		h.respawn_t = 0.0
		h.revive_t = -1.0
		h.revive_wait = false
		h.dmg_log = {}
		h.streak = 0
	for tm in g.brains:
		g.brains[tm].intent = "group"
	g.round_started.emit(round_n)

func update(d: float) -> void:
	phase_t += d
	match phase:
		"buy":
			for h in g.heroes:
				var home: Vector2 = g.home_pos(h.team)
				if h.position.distance_to(home) > SPAWN_R:
					h.position = home + (h.position - home).limit_length(SPAWN_R)
			if phase_t >= (FIRST_BUY_TIME if round_n == 1 else BUY_TIME):
				phase = "live"
				phase_t = 0.0
				for h in g.heroes:
					h.refund_tokens = 0
				g.round_live.emit(round_n)
		"live":
			_update_revives(d)
			_update_core(d)
			_check_round_end()
		"post":
			if phase_t >= POST_TIME:
				if score[0] >= ROUNDS_TO_WIN or score[1] >= ROUNDS_TO_WIN:
					g.winner = 0 if score[0] > score[1] else 1
					g._end(g.winner == 0)
				else:
					start_round()

func _alive(tm: int) -> int:
	var n := 0
	for h in g.heroes:
		if h.team == tm and not h.dead:
			n += 1
	return n

func in_core(h) -> bool:
	return not h.dead and h.position.distance_to(core_pos()) <= CORE_R

func _update_core(d: float) -> void:
	if not core_open():
		return
	var n := [0, 0]
	for h in g.heroes:
		if in_core(h):
			n[h.team] += 1
			h.stat_add("core_time", d)
	var rate := d / CAPTURE_TIME * (2.0 if phase_t >= OVERTIME_AT else 1.0)
	for tm in 2:
		if n[tm] > 0 and n[1 - tm] == 0:
			capture[tm] = minf(1.0, capture[tm] + rate)

func _check_round_end() -> void:
	var a0 := _alive(0)
	var a1 := _alive(1)
	if a0 == 0 and a1 == 0:
		end_round(-1, "同归于尽")
	elif a1 == 0:
		end_round(0, "全歼")
	elif a0 == 0:
		end_round(1, "全歼")
	elif capture[0] >= 1.0:
		end_round(0, "占领核心")
	elif capture[1] >= 1.0:
		end_round(1, "占领核心")
	elif phase_t >= LIVE_MAX:
		var w := -1
		if capture[0] != capture[1]:
			w = 0 if capture[0] > capture[1] else 1
		elif a0 != a1:
			w = 0 if a0 > a1 else 1
		else:
			var hp := [0.0, 0.0]
			for h in g.heroes:
				if not h.dead:
					hp[h.team] += h.hp / h.max_hp
			if hp[0] != hp[1]:
				w = 0 if hp[0] > hp[1] else 1
		end_round(w, "时间到")

## a draw (w == -1) gives both teams the loss payout and no point
func end_round(w: int, reason: String) -> void:
	var kills_now: Array = g.team_kills.duplicate()
	history.append({"round": round_n, "winner": w, "reason": reason, "time": snappedf(g.t, 0.1), "live": snappedf(phase_t, 0.1),
		"kills": [kills_now[0] - _kills_at_start[0], kills_now[1] - _kills_at_start[1]], "alive": [_alive(0), _alive(1)],
		"capture": [snappedf(capture[0], 0.01), snappedf(capture[1], 0.01)], "lanes": lanes.duplicate()})
	phase = "post"
	phase_t = 0.0
	last_winner = w
	last_reason = reason
	for tm in 2:
		var won := tm == w
		if won:
			score[tm] += 1
			loss_streak[tm] = 0
		else:
			loss_streak[tm] += 1
		var pay: float = WIN_PAY if won else loss_pay(loss_streak[tm])
		for h in g.heroes:
			if h.team == tm:
				h.gold += pay
				h.refund_tokens = 0 if won else 1
	g.round_ended.emit(round_n, w, reason)

## kill rewards inside a round; the dead hero may now choose to revive
func on_hero_killed(v, k, helpers: Array) -> void:
	v.respawn_t = 9999.0
	v.revive_t = -1.0
	v.revive_wait = phase == "live"
	v.revive_ask_t = g.t
	if k != null:
		k.gold += KILL_PAY
	for hh in helpers:
		hh.gold += ASSIST_PAY

## the dead hero spends one of its team's revives and starts the countdown. Returns false if not possible.
func request_revive(h) -> bool:
	if phase != "live" or not h.dead or not h.revive_wait or int(revives_left[h.team]) <= 0:
		return false
	revives_left[h.team] -= 1
	h.revive_wait = false
	h.revive_t = REVIVE_TIME
	h.respawn_t = REVIVE_TIME
	h.stat_add("revives")
	g._announce_revive(h)
	return true

## the hero decides to stay down this round (frees the HUD prompt; the AI may still change its mind)
func decline_revive(h) -> void:
	h.revive_wait = false

func _update_revives(d: float) -> void:
	for h in g.heroes:
		if not h.dead:
			continue
		if h.revive_t >= 0.0:
			h.revive_t -= d
			h.respawn_t = maxf(0.0, h.revive_t)
			if h.revive_t <= 0.0:
				_revive(h)
		elif h.revive_wait and not (h.is_player and not g.autopilot):
			# AI: think for a moment (better decision-making = faster), then re-check every 2 s
			if g.t - h.revive_ask_t >= h.ai.revive_delay():
				h.revive_ask_t = g.t + 1.0
				if ai_wants_revive(h):
					request_revive(h)

func _revive(h) -> void:
	var i := 0
	for o in g.heroes:
		if o == h:
			break
		if o.team == h.team:
			i += 1
	var p := spawn_pos(h.team, i)
	h.revive_t = -1.0
	h.respawn_t = 0.0
	h.respawn(p)                 # full hp / mana, statuses cleared; cooldowns are kept
	h.face = (core_pos() - p).angle()
	h.dmg_log = {}
	g._ring(p, 24, 220, 0.6, h.team_color(), 8)

## AI revive strategy. A revive costs one of the map's 5 shared revives and 10 s; it is worth it when the
## round can still be saved (time, enemy capture), the team is not hopelessly behind, and the budget allows:
## spend freely on match point (either side), otherwise keep about one revive per remaining round.
func ai_wants_revive(h) -> bool:
	var tm: int = h.team
	var left: int = int(revives_left[tm])
	if left <= 0 or _alive(tm) == 0:
		return false
	var t_left := LIVE_MAX - phase_t
	if t_left < REVIVE_TIME + 6.0:
		return false
	var cap_rate := (2.0 if phase_t >= OVERTIME_AT else 1.0) / CAPTURE_TIME
	var foe_cap_eta: float = (1.0 - float(capture[1 - tm])) / cap_rate
	var foe_on_core := false
	for o in g.heroes:
		if o.team != tm and in_core(o):
			foe_on_core = true
	if foe_on_core and foe_cap_eta < REVIVE_TIME + 4.0:
		return false   # the round is decided before we are back
	var rounds_max: int = (ROUNDS_TO_WIN - int(score[tm])) + (ROUNDS_TO_WIN - int(score[1 - tm])) - 1
	# about 70% of the possible remaining rounds are actually played
	var budget: float = float(left) / maxf(1.0, float(rounds_max) * 0.7)
	var v := 0.6
	v += 0.3 if budget >= 1.0 else -0.3 * (1.0 - budget)
	if int(score[0]) == ROUNDS_TO_WIN - 1 or int(score[1]) == ROUNDS_TO_WIN - 1:
		v += 0.4
	v += 0.15 * float(_alive(tm) - _alive(1 - tm))
	v += g.rng.randfn(0.0, h.ai.revive_noise())
	return v > 0.5

## the shop only works in the buy phase
func shop_block_reason() -> String:
	if phase != "buy":
		return "只能在购买阶段购物"
	return ""
