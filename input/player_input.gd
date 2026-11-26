extends Node2D
## Player control (3C): WASD move, mouse aim, left button = basic attack (hold to keep firing),
## right button = the hero's signature skill (hold to charge when it charges), Q / E / R = skills toward the cursor.
## Writes the hero's virtual controller (hero.gd ctl_*) every frame; the AI writes the same controller.
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

const MatchT = preload("res://game/match.gd")
var gm: MatchT

const PresenterT = preload("res://view/presenter.gd")
var vw: PresenterT
const HudT = preload("res://ui/hud.gd")
var hd: HudT
const ShopUIT = preload("res://ui/shop_ui.gd")
var shp: ShopUIT
const MenusT = preload("res://ui/menus.gd")
var mnu: MenusT
## main.gd (composition root)
var app: Node = null

# player control
var targeting := ""
var selected: Node2D = null
var right_held := false
var right_t := 0.0
var marker_pos := Vector2.ZERO
var marker_t := 0.0
var marker_col := Color.GREEN
# ============================================================ input
func _league() -> bool:
	return app != null and "lg" in app and app.lg != null and app.lg.active()

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var k: int = ev.physical_keycode
		if gm.state == C.S.MENU:
			if k == KEY_1: mnu._open_select(C.M.ROUNDS)
			elif k == KEY_2: mnu.open_exp3c()
			elif k == KEY_3: mnu.open_league()
			return
		if gm.state == C.S.SELECT:
			if k == KEY_ESCAPE: mnu._show_menu()
			return
		if gm.state == C.S.END:
			if gm.dead_timer > 0.6:
				if _league():
					if k in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]: app.lg.on_match_done()
				elif k == KEY_R or k == KEY_SPACE or k == KEY_ENTER: gm._restart()
				elif k == KEY_ESCAPE: mnu._show_menu()
			return
		if k == KEY_ESCAPE:
			if shp.shop_open:
				shp._close_shop()
			elif hd.stats_panel.visible:
				hd.stats_panel.visible = false
			elif targeting != "":
				targeting = ""
			else:
				gm.paused = not gm.paused
				hd.center_lbl.label_settings.font_size = 72
				hd.center_lbl.label_settings.font_color = Color(0.4, 1.0, 1.0)
				hd.center_lbl.modulate.a = 1.0
				hd.center_lbl.text = "暂停" if gm.paused else ""
				hd.sub_lbl.text = ("[ Esc 继续    Q 结束本图（剩余部分直接出结果） ]" if _league() else "[ Esc 继续    Q 退出到菜单 ]") if gm.paused else ""
			return
		if gm.paused:
			if k == KEY_Q:
				gm.paused = false
				if _league():
					app.lg.on_match_done(true)   # the rest of this map is decided by the instant resolver
				else:
					mnu._show_menu()
			return
		if k == KEY_B:
			if shp.shop_open: shp._close_shop()
			else: shp._open_shop()
			return
		if k == KEY_TAB:
			hd.board.visible = not hd.board.visible
			hd._update_board()
			return
		if k == KEY_C:
			hd.stats_panel.visible = not hd.stats_panel.visible
			return
		if shp.shop_open:
			return
		# round mode: the dead player decides on reviving (R = start the countdown, X = stay down)
		if gm.player != null and gm.player.dead and gm.rounds != null and gm.player.revive_wait and not gm.autopilot:
			if k == KEY_R:
				if not gm.rounds.request_revive(gm.player):
					hd.toast("本局复活次数已用完", Color(1.0, 0.6, 0.6), 2.0)
				return
			if k == KEY_X:
				gm.rounds.decline_revive(gm.player)
				return
		var key_map := {KEY_Q: "q", KEY_E: "e", KEY_R: "r"}
		if key_map.has(k):
			var s: String = key_map[k]
			if ev.ctrl_pressed or ev.meta_pressed:
				_learn(s)
			else:
				_press(s)
		elif k == KEY_F6 and bool(gm.last_cfg.get("setup", {}).get("league_watch", false)):
			hd.toast("观战中：比赛由 AI 进行", Color(0.6, 1.0, 1.0), 2.0)
		elif k == KEY_F6:
			gm.set_autopilot(not gm.autopilot)
			hd.toast("AI 托管：%s（F6 切换）" % ("开" if gm.autopilot else "关"), Color(0.6, 1.0, 1.0), 2.5)
		elif k == KEY_F10 and OS.is_debug_build():
			gm.god = not gm.god  # dev shortcut: invulnerable hero for testing
			hd.toast("测试免疫伤害：%s" % ("开" if gm.god else "关"), Color(1, 1, 0.5), 2.0)
		elif k == KEY_F7 and OS.is_debug_build():
			gm.player.gold += 3000.0  # dev shortcut: +3000 gold

	elif ev is InputEventMouseButton:
		if gm.state != C.S.PLAY or gm.paused or shp.shop_open or gm.player == null or gm.autopilot:
			return
		if ev.button_index == MOUSE_BUTTON_RIGHT:
			right_held = ev.pressed
			if ev.pressed:
				_press("w")

func _press(s: String) -> void:
	if gm.player == null or gm.player.dead or gm.autopilot:
		return
	gm.player.ctl_aim = get_global_mouse_position()
	var err: String = gm.player.press(s)
	if err != "":
		_deny(err)

func _unit_at(p: Vector2, foes_only: bool):
	var best_u = null
	var bd := 1e9
	for h in gm.heroes:
		if h.dead or h == gm.player: continue
		if foes_only and (h.team == gm.player.team or not h.targetable()): continue
		var d2: float = p.distance_to(h.position)
		if d2 < h.radius + 18.0 and d2 < bd:
			bd = d2
			best_u = h
	return best_u

func _ally_at(p: Vector2):
	var best_u = null
	var bd := 1e9
	for h in gm.heroes:
		if h.dead or h.team != gm.player.team:
			continue
		var dd: float = p.distance_to(h.position)
		if dd < h.radius + 70.0 and dd < bd:
			bd = dd
			best_u = h
	return best_u

func _marker(p: Vector2, col: Color) -> void:
	marker_pos = p
	marker_t = 0.45
	marker_col = col

func _deny(msg: String) -> void:
	hd.deny_lbl.text = msg
	hd.deny_lbl.modulate.a = 1.0
	var tw := hd.deny_lbl.create_tween()
	tw.tween_interval(0.8)
	tw.tween_property(hd.deny_lbl, "modulate:a", 0.0, 0.4)
	vw.sfx("deny", 1.0, -6.0, 0.15)

func _learn(s: String) -> void:
	if gm.state != C.S.PLAY or gm.player == null: return
	if not gm.player.learn(s):
		if gm.player.skill_points <= 0: _deny("没有技能点")
		elif s == "r": _deny("大招需要等级 6 / 12 / 18")
		else: _deny("需要更高的英雄等级")
		return
	vw.sfx("learn")
	vw._ring(gm.player.position, 10, 90, 0.35, Color(1.6, 1.4, 0.4), 4)

## every frame: WASD + mouse into the player's controller (skipped while the AI drives it: F6)
func _hold_move(_d: float) -> void:
	var h = gm.player
	if h == null or gm.autopilot:
		return
	if gm.state != C.S.PLAY or gm.paused or shp.shop_open or h.dead:
		h.ctl_move = Vector2.ZERO
		h.ctl_fire = false
		h.ctl_hold = false
		return
	var mv := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W): mv.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S): mv.y += 1.0
	if Input.is_physical_key_pressed(KEY_A): mv.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): mv.x += 1.0
	h.ctl_move = mv.normalized()
	h.ctl_aim = get_global_mouse_position()
	h.ctl_fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	h.ctl_hold = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)

func _inp_world_cleared() -> void:
	selected = null
	targeting = ""

func _inp_match_started() -> void:
	selected = gm.player

func _inp_match_ended(_win: bool) -> void:
	targeting = ""

## per-frame input housekeeping that used to be done inside the simulation
func _inp_tick() -> void:
	if selected != null and (not is_instance_valid(selected) or (not selected.is_hero and selected.dead)):
		selected = gm.player
	if gm.player != null and targeting != "" and (gm.player.dead or (gm.player.silence > 0.0 and targeting != "attack")):
		targeting = ""
